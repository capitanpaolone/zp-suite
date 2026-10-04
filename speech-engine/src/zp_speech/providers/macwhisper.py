"""Adapter for the public MacWhisper command-line interface."""

from __future__ import annotations

import hashlib
import json
import math
import shutil
import subprocess
from collections.abc import Callable, Mapping, Sequence
from pathlib import Path
from typing import Any, Protocol, cast

from zp_speech.contracts import API_VERSION, ERROR_CODES, SCHEMA_VERSION
from zp_speech.validation import ContractValidationError, validate_document

PROVIDER = "macwhisper"
DEFAULT_EXECUTABLE = Path("/Applications/MacWhisper.app/Contents/MacOS/mw")


class Runner(Protocol):
    def __call__(self, args: Sequence[str], timeout: float) -> subprocess.CompletedProcess[str]: ...


class ProviderError(RuntimeError):
    """A provider failure represented by a stable public error code."""

    def __init__(
        self,
        code: str,
        message: str,
        *,
        retryable: bool = False,
        details: Mapping[str, object] | None = None,
    ) -> None:
        if code not in ERROR_CODES:
            raise ValueError(f"unknown public error code: {code}")
        super().__init__(message)
        self.code = code
        self.retryable = retryable
        self.details = dict(details or {})

    def as_document(self) -> dict[str, Any]:
        document: dict[str, Any] = {
            "schema_version": SCHEMA_VERSION,
            "api_version": API_VERSION,
            "kind": "error",
            "error": {
                "code": self.code,
                "message": str(self),
                "retryable": self.retryable,
                "provider": PROVIDER,
                "details": self.details,
            },
        }
        validate_document(document)
        return document


def _run(args: Sequence[str], timeout: float) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, capture_output=True, text=True, check=False, timeout=timeout)


def _milliseconds(value: object, path: str) -> int:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ProviderError("transcription_failed", f"{path} must be a number of milliseconds")
    if not math.isfinite(value) or value < 0 or int(value) != value:
        raise ProviderError(
            "transcription_failed", f"{path} must be a non-negative integer millisecond value"
        )
    return int(value)


def _text(value: object, path: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ProviderError("transcription_failed", f"{path} must be non-empty text")
    return value.strip()


def _normalize_word(raw: object, path: str) -> dict[str, Any]:
    if not isinstance(raw, Mapping):
        raise ProviderError("transcription_failed", f"{path} must be an object")
    raw = cast(Mapping[str, object], raw)
    return {
        "start_ms": _milliseconds(raw.get("start"), f"{path}.start"),
        "end_ms": _milliseconds(raw.get("end"), f"{path}.end"),
        "text": _text(raw.get("text"), f"{path}.text"),
    }


def normalize_macwhisper_json(
    raw: str | Mapping[str, object],
    *,
    source: Path,
    model: str,
    language: str,
) -> dict[str, Any]:
    """Convert a MacWhisper JSON result into the provider-neutral v1 transcript."""
    try:
        parsed: object = json.loads(raw) if isinstance(raw, str) else raw
    except json.JSONDecodeError as error:
        raise ProviderError("transcription_failed", "MacWhisper returned malformed JSON") from error
    if not isinstance(parsed, Mapping):
        raise ProviderError("transcription_failed", "MacWhisper JSON has no segments array")
    parsed_map = cast(Mapping[str, object], parsed)
    raw_segments = parsed_map.get("segments")
    if not isinstance(raw_segments, list):
        raise ProviderError("transcription_failed", "MacWhisper JSON has no segments array")

    segments: list[dict[str, Any]] = []
    has_words = False
    has_speakers = False
    for index, item in enumerate(cast(list[object], raw_segments)):
        path = f"segments[{index}]"
        if not isinstance(item, Mapping):
            raise ProviderError("transcription_failed", f"{path} must be an object")
        item = cast(Mapping[str, object], item)
        segment: dict[str, Any] = {
            "start_ms": _milliseconds(item.get("start"), f"{path}.start"),
            "end_ms": _milliseconds(item.get("end"), f"{path}.end"),
            "text": _text(item.get("text"), f"{path}.text"),
        }
        raw_words = item.get("words")
        if raw_words is not None:
            if not isinstance(raw_words, list):
                raise ProviderError("transcription_failed", f"{path}.words must be an array")
            words = cast(list[object], raw_words)
            normalized_words = [
                _normalize_word(word, f"{path}.words[{word_index}]")
                for word_index, word in enumerate(words)
            ]
            for word_index, word in enumerate(normalized_words):
                # Word timestamps can drift past their segment by more than rounding:
                # real Whisper output overshoots by hundreds of ms. The segment is
                # authoritative for SRT and markers, so clamp the word into it; only a
                # word lying entirely outside its segment is an error.
                word["start_ms"] = max(word["start_ms"], segment["start_ms"])
                word["end_ms"] = min(word["end_ms"], segment["end_ms"])
                # Whisper emits zero-length words when it splits elisions ("l" + "'ha").
                # Schema v1 intervals are half-open, so give them 1 ms inside the segment.
                if word["start_ms"] == word["end_ms"]:
                    if word["end_ms"] < segment["end_ms"]:
                        word["end_ms"] += 1
                    else:
                        word["start_ms"] -= 1
                if word["start_ms"] >= word["end_ms"]:
                    raise ProviderError(
                        "transcription_failed",
                        f"{path}.words[{word_index}] lies outside its segment",
                    )
            segment["words"] = normalized_words
            has_words = True
        speaker = item.get("speaker")
        if speaker is not None:
            segment["speaker"] = _text(speaker, f"{path}.speaker")
            has_speakers = True
        segments.append(segment)

    try:
        payload = source.read_bytes()
    except OSError as error:
        raise ProviderError("invalid_source", f"cannot read source: {source.name}") from error
    digest = hashlib.sha256(payload).hexdigest()
    capabilities = {
        "segment_timestamps": True,
        "word_timestamps": has_words,
        "diarization": has_speakers,
        "language_detection": language == "auto",
        "streaming": False,
        "input_formats": [source.suffix.lower().lstrip(".") or "unknown"],
        "output_formats": ["json"],
    }
    document: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "api_version": API_VERSION,
        "kind": "transcript",
        "source_id": f"sha256:{digest}",
        "source": {
            "source_id": f"sha256:{digest}",
            "kind": "file",
            "display_name": source.name,
            "size_bytes": len(payload),
            "content_hash": {"algorithm": "sha256", "digest": digest},
        },
        "engine": model.split(":", 1)[0],
        "provider": PROVIDER,
        "model": model,
        "language": language,
        "capabilities": capabilities,
        "segments": segments,
    }
    try:
        validate_document(document)
    except ContractValidationError as error:
        timing_details = []
        for segment_index, segment in enumerate(segments):
            for word_index, word in enumerate(segment.get("words", [])):
                if word["start_ms"] < segment["start_ms"] or word["end_ms"] > segment["end_ms"]:
                    timing_details.append(
                        f"segments[{segment_index}] [{segment['start_ms']}, {segment['end_ms']}) "
                        f"words[{word_index}] [{word['start_ms']}, {word['end_ms']})"
                    )
        detail = f"; intervalli: {'; '.join(timing_details[:8])}" if timing_details else ""
        raise ProviderError(
            "transcription_failed", f"invalid MacWhisper timing: {error}{detail}"
        ) from error
    return document


class MacWhisperProvider:
    """Discover, inspect and invoke MacWhisper without touching its private database."""

    def __init__(self, executable: Path, *, runner: Runner = _run) -> None:
        self.executable = executable
        self.runner = runner

    @classmethod
    def detect(cls, executable: Path | None = None, *, runner: Runner = _run) -> MacWhisperProvider:
        candidate = executable
        if candidate is None:
            candidate = DEFAULT_EXECUTABLE if DEFAULT_EXECUTABLE.is_file() else None
        if candidate is None:
            found = shutil.which("mw")
            candidate = Path(found) if found else None
        if candidate is None or not candidate.is_file():
            raise ProviderError("provider_not_found", "MacWhisper public CLI was not found")
        if not candidate.stat().st_mode & 0o111:
            raise ProviderError("provider_unavailable", "MacWhisper public CLI is not executable")
        return cls(candidate, runner=runner)

    def _command(
        self, arguments: Sequence[str], timeout: float
    ) -> subprocess.CompletedProcess[str]:
        try:
            return self.runner([str(self.executable), *arguments], timeout)
        except FileNotFoundError as error:
            raise ProviderError(
                "provider_not_found", "MacWhisper public CLI disappeared"
            ) from error
        except subprocess.TimeoutExpired as error:
            raise ProviderError(
                "timeout", "MacWhisper command timed out", retryable=True
            ) from error
        except (PermissionError, OSError) as error:
            raise ProviderError(
                "provider_unavailable", "MacWhisper public CLI is unavailable"
            ) from error

    @staticmethod
    def _failure(result: subprocess.CompletedProcess[str]) -> ProviderError:
        message = (result.stderr or result.stdout or "MacWhisper command failed").strip()
        lowered = message.lower()
        if "unknown model" in lowered:
            return ProviderError("unsupported_model", message)
        if "cancel" in lowered:
            return ProviderError("cancelled", message)
        if "unsupported" in lowered or "not available" in lowered:
            return ProviderError("unsupported_capability", message)
        if "not running" in lowered or "not ready" in lowered:
            return ProviderError("provider_unavailable", message, retryable=True)
        return ProviderError("transcription_failed", message)

    def capabilities(self, *, timeout: float = 10) -> dict[str, Any]:
        version_result = self._command(["version"], timeout)
        if version_result.returncode:
            raise self._failure(version_result)
        version_line = version_result.stdout.strip()
        version = version_line.removeprefix("MacWhisper ").split(" ", 1)[0]
        if not version:
            raise ProviderError("provider_unavailable", "MacWhisper returned no version")

        models_result = self._command(["models", "list"], timeout)
        if models_result.returncode:
            raise self._failure(models_result)
        models: list[str] = []
        for line in models_result.stdout.splitlines():
            stripped = line.strip().removeprefix("→").removeprefix("▸").strip()
            if (
                stripped
                and not stripped.startswith("Installed models")
                and not stripped.startswith("ID ")
            ):
                models.append(stripped.split(None, 1)[0])
        if not models:
            raise ProviderError("provider_unavailable", "MacWhisper reported no installed models")
        document: dict[str, Any] = {
            "schema_version": SCHEMA_VERSION,
            "api_version": API_VERSION,
            "kind": "provider_capabilities",
            "provider": PROVIDER,
            "engine": "macwhisper-cli",
            "provider_version": version,
            "models": models,
            "capabilities": {
                "segment_timestamps": True,
                "word_timestamps": True,
                "diarization": False,
                "language_detection": True,
                "streaming": True,
                "input_formats": ["wav"],
                "output_formats": ["json", "srt", "txt"],
            },
        }
        validate_document(document)
        return document

    def transcribe(
        self,
        source: Path,
        *,
        language: str = "it",
        model: str | None = None,
        speakers: bool = False,
        timeout: float = 120,
        cancelled: Callable[[], bool] | None = None,
    ) -> dict[str, Any]:
        if not source.is_file():
            raise ProviderError("invalid_source", f"source is not a readable file: {source.name}")
        if source.suffix.lower() != ".wav":
            raise ProviderError(
                "unsupported_capability", "only WAV input has been verified for MacWhisper"
            )
        if cancelled is not None and cancelled():
            raise ProviderError("cancelled", "transcription was cancelled")
        info = self.capabilities(timeout=min(timeout, 10))
        if speakers and not info["capabilities"]["diarization"]:
            raise ProviderError("unsupported_capability", "speaker diarization is not verified")
        models = cast(list[str], info["models"])
        selected_model = model or models[0]
        if selected_model not in models:
            raise ProviderError("unsupported_model", f"model is not installed: {selected_model}")
        arguments = ["transcribe", str(source), "--language", language, "--format", "json"]
        arguments.extend(["--model", selected_model, "--no-speakers"])
        result = self._command(arguments, timeout)
        if cancelled is not None and cancelled():
            raise ProviderError("cancelled", "transcription was cancelled")
        if result.returncode:
            raise self._failure(result)
        if not result.stdout.strip():
            raise ProviderError("transcription_failed", "MacWhisper returned an empty transcript")
        return normalize_macwhisper_json(
            result.stdout, source=source, model=selected_model, language=language
        )
