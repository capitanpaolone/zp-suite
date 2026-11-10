"""Adapter for the local OpenAI Whisper Python runtime (macOS, Windows, Linux)."""

from __future__ import annotations

import hashlib
import json
import math
import os
import shutil
import subprocess
import sys
from collections.abc import Callable, Mapping, Sequence
from pathlib import Path
from typing import Any, cast

from zp_speech.contracts import API_VERSION, SCHEMA_VERSION
from zp_speech.providers.macwhisper import ProviderError, Runner, default_runner
from zp_speech.validation import ContractValidationError, validate_document

PROVIDER = "openai-whisper"
ENGINE = "openai-whisper"

WHISPER_MODEL_SIZES_MB: dict[str, int] = {
    "tiny": 75,
    "tiny.en": 75,
    "base": 145,
    "base.en": 145,
    "small": 465,
    "small.en": 465,
    "medium": 1460,
    "medium.en": 1460,
    "large-v1": 2950,
    "large-v2": 2950,
    "large-v3": 2950,
    "large-v3-turbo": 1550,
}

MODEL_ALIASES: dict[str, str] = {
    "turbo": "large-v3-turbo",
    "large": "large-v3",
}

PREFERRED_MODELS: tuple[str, ...] = (
    "large-v3-turbo",
    "large-v3",
    "medium",
    "small",
    "base",
    "tiny",
)

_PROBE_SCRIPT = (
    "import json, whisper, torch; "
    "print(json.dumps({'version': getattr(whisper, '__version__', 'unknown'), "
    "'torch': getattr(torch, '__version__', 'unknown')}))"
)

_TRANSCRIBE_SCRIPT = """\
import json, os, sys, torch, whisper

model_file, source_path, language, ffmpeg_dir = sys.argv[1:5]
if ffmpeg_dir:
    os.environ["PATH"] = ffmpeg_dir + os.pathsep + os.environ.get("PATH", "")
device = os.environ.get("ZP_WHISPER_DEVICE") or ("cuda" if torch.cuda.is_available() else "cpu")
model = whisper.load_model(model_file, device=device)
lang_arg = None if language == "auto" else language
result = model.transcribe(
    source_path,
    language=lang_arg,
    word_timestamps=True,
    verbose=False,
    fp16=(device == "cuda"),
)
sys.stdout.write(json.dumps(result, ensure_ascii=False))
"""

_DOWNLOAD_SCRIPT = """\
import sys, whisper

model_name, models_dir = sys.argv[1:3]
url = whisper._MODELS[model_name]
path = whisper._download(url, models_dir, False)
sys.stdout.write(str(path) + "\\n")
"""


def zp_data_root(
    *,
    platform: str | None = None,
    env: Mapping[str, str] | None = None,
    home: Path | None = None,
) -> Path:
    """Return the platform-appropriate ZP user data root directory."""
    environment = os.environ if env is None else env
    override = environment.get("ZP_DATA_DIR")
    if override:
        return Path(override).expanduser()
    user_home = Path.home() if home is None else home
    target = sys.platform if platform is None else platform
    if target == "darwin":
        return user_home / "Library" / "Application Support" / "ZP"
    if target.startswith("win"):
        local_app = environment.get("LOCALAPPDATA")
        base = Path(local_app) if local_app else (user_home / "AppData" / "Local")
        return base / "ZP"
    xdg = environment.get("XDG_DATA_HOME")
    base = Path(xdg) if xdg else (user_home / ".local" / "share")
    return base / "zp"


def default_whisper_python(
    data_root: Path | None = None,
    *,
    platform: str | None = None,
) -> Path:
    """Return the expected Python executable inside the isolated OpenAI Whisper venv."""
    root = zp_data_root(platform=platform) if data_root is None else data_root
    target = sys.platform if platform is None else platform
    venv_dir = root / "runtimes" / "openai-whisper"
    if target.startswith("win"):
        return venv_dir / "Scripts" / "python.exe"
    return venv_dir / "bin" / "python"


def default_models_dir(data_root: Path | None = None) -> Path:
    """Return the shared ZP directory holding local OpenAI Whisper .pt weights."""
    root = zp_data_root() if data_root is None else data_root
    return root / "models" / "whisper"


def default_whisper_cache_dir() -> Path:
    """Return the standard upstream PyTorch/OpenAI Whisper cache directory (~/.cache/whisper)."""
    return Path.home() / ".cache" / "whisper"


def find_model_file(stem: str, models_dir: Path) -> Path:
    """Locate the .pt model file in models_dir or the standard upstream cache fallback."""
    candidate = models_dir / f"{stem}.pt"
    if candidate.is_file() and candidate.stat().st_size > 0:
        return candidate
    fallback = default_whisper_cache_dir() / f"{stem}.pt"
    if fallback.is_file() and fallback.stat().st_size > 0:
        return fallback
    return candidate


def canonical_model_stem(model: str) -> str:
    """Strip optional provider prefix and resolve Whisper model aliases."""
    cleaned = model.strip()
    if ":" in cleaned:
        prefix, rest = cleaned.split(":", 1)
        if prefix != PROVIDER:
            raise ProviderError(
                "unsupported_model",
                f"model belongs to another provider: {model}",
                provider=PROVIDER,
            )
        cleaned = rest.strip()
    if not cleaned:
        raise ProviderError("unsupported_model", "model name must not be empty", provider=PROVIDER)
    return MODEL_ALIASES.get(cleaned, cleaned)


def installed_models(models_dir: Path, *, include_cache: bool = True) -> list[str]:
    """List installed OpenAI Whisper models in deterministic preference order.

    Checks models_dir and, when include_cache is True, also checks the standard
    upstream cache ~/.cache/whisper so already-downloaded models are recognized.
    """
    found: set[str] = set()
    directories: list[Path] = [models_dir]
    if include_cache:
        cache_dir = default_whisper_cache_dir()
        if cache_dir != models_dir and cache_dir.is_dir():
            directories.append(cache_dir)
    for directory in directories:
        if not directory.is_dir():
            continue
        for entry in directory.iterdir():
            if (
                entry.is_file()
                and entry.suffix == ".pt"
                and not entry.name.startswith(".")
                and entry.stat().st_size > 0
            ):
                found.add(entry.stem)
    ordered: list[str] = []
    for preferred in PREFERRED_MODELS:
        if preferred in found:
            ordered.append(f"{PROVIDER}:{preferred}")
            found.remove(preferred)
    for extra in sorted(found):
        ordered.append(f"{PROVIDER}:{extra}")
    return ordered


def _is_executable(path: Path) -> bool:
    if not path.is_file():
        return False
    if sys.platform.startswith("win"):
        return True
    return bool(path.stat().st_mode & 0o111)


def find_ffmpeg(explicit: Path | None = None, *, env: Mapping[str, str] | None = None) -> Path:
    """Locate a usable ffmpeg binary or raise ProviderError."""
    environment = os.environ if env is None else env
    candidates: list[Path] = []
    if explicit is not None:
        candidates.append(explicit)
    env_bin = environment.get("ZP_FFMPEG_BIN")
    if env_bin:
        candidates.append(Path(env_bin).expanduser())
    which_path = shutil.which("ffmpeg", path=environment.get("PATH"))
    if which_path:
        candidates.append(Path(which_path))
    for fixed in ("/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"):
        candidates.append(Path(fixed))
    for candidate in candidates:
        if _is_executable(candidate):
            return candidate
    raise ProviderError(
        "provider_unavailable",
        "FFmpeg non trovato: è richiesto da OpenAI Whisper per leggere i file audio",
        provider=PROVIDER,
        details={"missing": "ffmpeg"},
    )


def _seconds_to_ms(value: object, path: str) -> int:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ProviderError(
            "transcription_failed",
            f"{path} must be a number of seconds",
            provider=PROVIDER,
        )
    if not math.isfinite(value) or value < 0:
        raise ProviderError(
            "transcription_failed",
            f"{path} must be a non-negative finite number of seconds",
            provider=PROVIDER,
        )
    return round(float(value) * 1000)


def _text(value: object, path: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ProviderError(
            "transcription_failed",
            f"{path} must be non-empty text",
            provider=PROVIDER,
        )
    return value.strip()


def _normalize_word(raw: object, path: str) -> dict[str, Any]:
    if not isinstance(raw, Mapping):
        raise ProviderError("transcription_failed", f"{path} must be an object", provider=PROVIDER)
    raw_map = cast(Mapping[str, object], raw)
    token = raw_map.get("word") if "word" in raw_map else raw_map.get("text")
    word: dict[str, Any] = {
        "start_ms": _seconds_to_ms(raw_map.get("start"), f"{path}.start"),
        "end_ms": _seconds_to_ms(raw_map.get("end"), f"{path}.end"),
        "text": _text(token, f"{path}.word"),
    }
    prob = raw_map.get("probability")
    if isinstance(prob, (int, float)) and not isinstance(prob, bool) and 0.0 <= float(prob) <= 1.0:
        word["confidence"] = round(float(prob), 4)
    return word


def _is_blank_word(raw: object) -> bool:
    """True for Whisper word entries whose token is whitespace only (dropped, not an error)."""
    if not isinstance(raw, Mapping):
        return False
    token = cast(Mapping[str, object], raw).get("word")
    return isinstance(token, str) and not token.strip()


def normalize_openai_whisper_json(
    raw: str | Mapping[str, object],
    *,
    source: Path,
    model: str,
    language: str,
) -> dict[str, Any]:
    """Convert an OpenAI Whisper result into the provider-neutral ZP Speech v1 transcript."""
    try:
        parsed: object = json.loads(raw) if isinstance(raw, str) else raw
    except json.JSONDecodeError as error:
        raise ProviderError(
            "transcription_failed",
            "OpenAI Whisper returned malformed JSON",
            provider=PROVIDER,
        ) from error
    if not isinstance(parsed, Mapping):
        raise ProviderError(
            "transcription_failed",
            "OpenAI Whisper JSON has no segments array",
            provider=PROVIDER,
        )
    parsed_map = cast(Mapping[str, object], parsed)
    raw_segments = parsed_map.get("segments")
    if not isinstance(raw_segments, list):
        raise ProviderError(
            "transcription_failed",
            "OpenAI Whisper JSON has no segments array",
            provider=PROVIDER,
        )

    segments: list[dict[str, Any]] = []
    has_words = False
    for index, item in enumerate(cast(list[object], raw_segments)):
        path = f"segments[{index}]"
        if not isinstance(item, Mapping):
            raise ProviderError(
                "transcription_failed", f"{path} must be an object", provider=PROVIDER
            )
        item_map = cast(Mapping[str, object], item)
        text_val = item_map.get("text")
        if isinstance(text_val, str) and not text_val.strip():
            continue
        start_ms = _seconds_to_ms(item_map.get("start"), f"{path}.start")
        end_ms = _seconds_to_ms(item_map.get("end"), f"{path}.end")
        if start_ms >= end_ms:
            raise ProviderError(
                "transcription_failed",
                f"invalid OpenAI Whisper timing: {path} must satisfy start < end",
                provider=PROVIDER,
            )
        segment: dict[str, Any] = {
            "start_ms": start_ms,
            "end_ms": end_ms,
            "text": _text(text_val, f"{path}.text"),
        }
        raw_words = item_map.get("words")
        if raw_words is not None:
            if not isinstance(raw_words, list):
                raise ProviderError(
                    "transcription_failed",
                    f"{path}.words must be an array",
                    provider=PROVIDER,
                )
            words_list = [
                _normalize_word(w, f"{path}.words[{w_idx}]")
                for w_idx, w in enumerate(cast(list[object], raw_words))
                if not _is_blank_word(w)
            ]
            for word in words_list:
                seg_start, seg_end = segment["start_ms"], segment["end_ms"]
                anchor = min(max(word["start_ms"], seg_start), seg_end)
                word["start_ms"] = max(word["start_ms"], seg_start)
                word["end_ms"] = min(word["end_ms"], seg_end)
                if word["start_ms"] >= word["end_ms"]:
                    if anchor > seg_start:
                        word["start_ms"], word["end_ms"] = anchor - 1, anchor
                    else:
                        word["start_ms"], word["end_ms"] = seg_start, seg_start + 1
            words_list.sort(key=lambda word: (word["start_ms"], word["end_ms"]))
            segment["words"] = words_list
            has_words = True
        segments.append(segment)

    try:
        payload = source.read_bytes()
    except OSError as error:
        raise ProviderError(
            "invalid_source", f"cannot read source: {source.name}", provider=PROVIDER
        ) from error
    digest = hashlib.sha256(payload).hexdigest()
    detected_lang = parsed_map.get("language")
    resolved_lang = (
        detected_lang.strip()
        if language == "auto" and isinstance(detected_lang, str) and detected_lang.strip()
        else language
    )
    stem = canonical_model_stem(model)
    full_model = f"{PROVIDER}:{stem}"
    capabilities = {
        "segment_timestamps": True,
        "word_timestamps": has_words,
        "diarization": False,
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
        "engine": ENGINE,
        "provider": PROVIDER,
        "model": full_model,
        "language": resolved_lang,
        "capabilities": capabilities,
        "segments": segments,
    }
    try:
        validate_document(document)
    except ContractValidationError as error:
        raise ProviderError(
            "transcription_failed",
            f"invalid OpenAI Whisper timing: {error}",
            provider=PROVIDER,
        ) from error
    return document


class OpenAIWhisperProvider:
    """Discover, inspect and invoke OpenAI Whisper in its isolated Python 3.11 environment."""

    def __init__(
        self,
        python_executable: Path,
        *,
        ffmpeg_executable: Path,
        models_dir: Path,
        runner: Runner = default_runner,
    ) -> None:
        self.python_executable = python_executable
        self.ffmpeg_executable = ffmpeg_executable
        self.models_dir = models_dir
        self.runner = runner

    @classmethod
    def detect(
        cls,
        python_executable: Path | None = None,
        *,
        ffmpeg_executable: Path | None = None,
        models_dir: Path | None = None,
        env: Mapping[str, str] | None = None,
        runner: Runner = default_runner,
    ) -> OpenAIWhisperProvider:
        environment = os.environ if env is None else env
        root = zp_data_root(env=environment)
        candidate = python_executable
        if candidate is None:
            env_py = environment.get("ZP_WHISPER_PYTHON")
            candidate = Path(env_py).expanduser() if env_py else default_whisper_python(root)
        if not candidate.is_file():
            raise ProviderError(
                "provider_not_found",
                f"Ambiente Python di OpenAI Whisper non trovato in {candidate}",
                provider=PROVIDER,
                details={"python_executable": str(candidate)},
            )
        if not _is_executable(candidate):
            raise ProviderError(
                "provider_unavailable",
                f"Interprete Python di OpenAI Whisper non eseguibile: {candidate}",
                provider=PROVIDER,
                details={"python_executable": str(candidate)},
            )
        ffmpeg_bin = find_ffmpeg(ffmpeg_executable, env=environment)
        resolved_models = models_dir
        if resolved_models is None:
            env_models = environment.get("ZP_WHISPER_MODELS_DIR")
            resolved_models = (
                Path(env_models).expanduser() if env_models else default_models_dir(root)
            )
        return cls(
            candidate,
            ffmpeg_executable=ffmpeg_bin,
            models_dir=resolved_models,
            runner=runner,
        )

    def _command(
        self, arguments: Sequence[str], timeout: float
    ) -> subprocess.CompletedProcess[str]:
        try:
            return self.runner([str(self.python_executable), *arguments], timeout)
        except FileNotFoundError as error:
            raise ProviderError(
                "provider_not_found",
                "OpenAI Whisper Python runtime disappeared",
                provider=PROVIDER,
            ) from error
        except subprocess.TimeoutExpired as error:
            raise ProviderError(
                "timeout",
                "OpenAI Whisper command timed out",
                retryable=True,
                provider=PROVIDER,
            ) from error
        except (PermissionError, OSError) as error:
            raise ProviderError(
                "provider_unavailable",
                "OpenAI Whisper Python runtime is unavailable",
                provider=PROVIDER,
            ) from error

    def capabilities(self, *, timeout: float = 15) -> dict[str, Any]:
        probe = self._command(["-c", _PROBE_SCRIPT], timeout)
        if probe.returncode:
            detail = (probe.stderr or probe.stdout or "OpenAI Whisper import failed").strip()
            raise ProviderError(
                "provider_unavailable",
                f"Libreria openai-whisper o PyTorch non pronta: {detail}",
                provider=PROVIDER,
            )
        try:
            info: object = json.loads(probe.stdout.strip())
        except json.JSONDecodeError as error:
            raise ProviderError(
                "provider_unavailable",
                "OpenAI Whisper runtime returned invalid probe output",
                provider=PROVIDER,
            ) from error
        version = (
            str(cast(Mapping[str, object], info).get("version") or "").strip()
            if isinstance(info, Mapping)
            else ""
        )
        if not version:
            raise ProviderError(
                "provider_unavailable",
                "OpenAI Whisper returned no version",
                provider=PROVIDER,
            )
        models = installed_models(self.models_dir)
        if not models:
            raise ProviderError(
                "provider_unavailable",
                f"Nessun modello OpenAI Whisper scaricato in {self.models_dir}",
                provider=PROVIDER,
                details={"models_dir": str(self.models_dir)},
            )
        document: dict[str, Any] = {
            "schema_version": SCHEMA_VERSION,
            "api_version": API_VERSION,
            "kind": "provider_capabilities",
            "provider": PROVIDER,
            "engine": ENGINE,
            "provider_version": version,
            "models": models,
            "capabilities": {
                "segment_timestamps": True,
                "word_timestamps": True,
                "diarization": False,
                "language_detection": True,
                "streaming": False,
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
            raise ProviderError(
                "invalid_source",
                f"source is not a readable file: {source.name}",
                provider=PROVIDER,
            )
        if source.suffix.lower() != ".wav":
            raise ProviderError(
                "unsupported_capability",
                "only WAV input has been verified for OpenAI Whisper",
                provider=PROVIDER,
            )
        if cancelled is not None and cancelled():
            raise ProviderError("cancelled", "transcription was cancelled", provider=PROVIDER)
        info = self.capabilities(timeout=min(timeout, 15))
        if speakers and not info["capabilities"]["diarization"]:
            raise ProviderError(
                "unsupported_capability",
                "speaker diarization is not supported by OpenAI Whisper",
                provider=PROVIDER,
            )
        models = cast(list[str], info["models"])
        if model is None or not model.strip():
            selected_full = models[0]
            stem = canonical_model_stem(selected_full)
        else:
            stem = canonical_model_stem(model)
            selected_full = f"{PROVIDER}:{stem}"
            if selected_full not in models:
                raise ProviderError(
                    "unsupported_model",
                    f"model is not installed: {model}",
                    provider=PROVIDER,
                    details={"models_dir": str(self.models_dir), "installed": models},
                )
        model_file = find_model_file(stem, self.models_dir)
        result = self._command(
            [
                "-c",
                _TRANSCRIBE_SCRIPT,
                str(model_file),
                str(source),
                language,
                str(self.ffmpeg_executable.parent),
            ],
            timeout,
        )
        if cancelled is not None and cancelled():
            raise ProviderError("cancelled", "transcription was cancelled", provider=PROVIDER)
        if result.returncode:
            message = (result.stderr or result.stdout or "OpenAI Whisper command failed").strip()
            raise ProviderError("transcription_failed", message, provider=PROVIDER)
        if not result.stdout.strip():
            raise ProviderError(
                "transcription_failed",
                "OpenAI Whisper returned an empty transcript",
                provider=PROVIDER,
            )
        return normalize_openai_whisper_json(
            result.stdout, source=source, model=selected_full, language=language
        )


def list_models_status(models_dir: Path | None = None) -> dict[str, Any]:
    """Return catalog, installed models and disk availability for UI/CLI inspection."""
    target_dir = default_models_dir() if models_dir is None else models_dir
    installed = set(installed_models(target_dir))
    check_dir = target_dir if target_dir.exists() else target_dir.parent
    while not check_dir.exists() and check_dir.parent != check_dir:
        check_dir = check_dir.parent
    free_mb = shutil.disk_usage(check_dir).free // (1024 * 1024)
    catalog = [
        {
            "model": f"{PROVIDER}:{name}",
            "name": name,
            "size_mb": size_mb,
            "installed": f"{PROVIDER}:{name}" in installed,
        }
        for name, size_mb in WHISPER_MODEL_SIZES_MB.items()
    ]
    return {
        "models_dir": str(target_dir),
        "free_mb": free_mb,
        "installed": installed_models(target_dir),
        "catalog": catalog,
    }


def download_model(
    model: str,
    *,
    python_executable: Path | None = None,
    models_dir: Path | None = None,
    env: Mapping[str, str] | None = None,
    runner: Runner = default_runner,
    timeout: float = 3600,
) -> Path:
    """Explicitly download an OpenAI Whisper model to the shared ZP directory."""
    stem = canonical_model_stem(model)
    if stem not in WHISPER_MODEL_SIZES_MB:
        raise ProviderError(
            "unsupported_model",
            f"unknown OpenAI Whisper model: {model}",
            provider=PROVIDER,
        )
    environment = os.environ if env is None else env
    root = zp_data_root(env=environment)
    target_dir = models_dir or (
        Path(environment["ZP_WHISPER_MODELS_DIR"]).expanduser()
        if "ZP_WHISPER_MODELS_DIR" in environment
        else default_models_dir(root)
    )
    target_dir.mkdir(parents=True, exist_ok=True)
    required_mb = WHISPER_MODEL_SIZES_MB[stem] + 200
    free_mb = shutil.disk_usage(target_dir).free // (1024 * 1024)
    if free_mb < required_mb:
        raise ProviderError(
            "provider_unavailable",
            f"Spazio su disco insufficiente per {stem}: richiesti ~{required_mb} MB, "
            f"disponibili {free_mb} MB in {target_dir}",
            provider=PROVIDER,
            details={"required_mb": required_mb, "free_mb": free_mb},
        )
    py_bin = python_executable or (
        Path(environment["ZP_WHISPER_PYTHON"]).expanduser()
        if "ZP_WHISPER_PYTHON" in environment
        else default_whisper_python(root)
    )
    if not _is_executable(py_bin):
        raise ProviderError(
            "provider_not_found",
            f"Ambiente Python di OpenAI Whisper non trovato in {py_bin}",
            provider=PROVIDER,
        )
    result = runner([str(py_bin), "-c", _DOWNLOAD_SCRIPT, stem, str(target_dir)], timeout)
    if result.returncode:
        message = (result.stderr or result.stdout or "Download modello non riuscito").strip()
        raise ProviderError("provider_unavailable", message, provider=PROVIDER)
    model_path = target_dir / f"{stem}.pt"
    if not model_path.is_file() or model_path.stat().st_size == 0:
        raise ProviderError(
            "provider_unavailable",
            f"File modello non trovato dopo il download: {model_path}",
            provider=PROVIDER,
        )
    return model_path
