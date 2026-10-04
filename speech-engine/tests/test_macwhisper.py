from __future__ import annotations

import subprocess
from collections.abc import Sequence
from pathlib import Path
from typing import Any

import pytest

from zp_speech.providers.macwhisper import (
    MacWhisperProvider,
    ProviderError,
    _run,
    normalize_macwhisper_json,
)
from zp_speech.validation import validate_document

FIXTURES = Path(__file__).parent / "fixtures" / "macwhisper" / "14.8.1"
MODEL = "whisperkit:openai_whisper-large-v3-v20240930"
VERSION = subprocess.CompletedProcess([], 0, "MacWhisper 14.8.1 (1481)\n", "")
MODELS = subprocess.CompletedProcess(
    [],
    0,
    "  ID NAME SIZE\n▸ whisperkit:openai_whisper-large-v3-v20240930 Large\n"
    "  whisperkit:openai_whisper-small Small\n",
    "",
)


class QueueRunner:
    def __init__(self, results: Sequence[object]) -> None:
        self.results = list(results)
        self.calls: list[tuple[list[str], float]] = []

    def __call__(self, args: Sequence[str], timeout: float) -> subprocess.CompletedProcess[str]:
        self.calls.append((list(args), timeout))
        result = self.results.pop(0)
        if isinstance(result, BaseException):
            raise result
        assert isinstance(result, subprocess.CompletedProcess)
        return result


def error_code(error: pytest.ExceptionInfo[ProviderError]) -> str:
    validate_document(error.value.as_document())
    return error.value.code


def test_detect_explicit_available_and_not_executable(tmp_path: Path) -> None:
    executable = tmp_path / "mw"
    executable.write_text("cli", encoding="utf-8")
    executable.chmod(0o755)
    assert MacWhisperProvider.detect(executable).executable == executable
    executable.chmod(0o644)
    with pytest.raises(ProviderError) as error:
        MacWhisperProvider.detect(executable)
    assert error_code(error) == "provider_unavailable"


def test_detect_absent(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.setattr("zp_speech.providers.macwhisper.DEFAULT_EXECUTABLE", tmp_path / "absent")
    monkeypatch.setattr("zp_speech.providers.macwhisper.shutil.which", lambda _: None)
    with pytest.raises(ProviderError) as error:
        MacWhisperProvider.detect()
    assert error_code(error) == "provider_not_found"


def test_detect_from_path(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    executable = tmp_path / "mw"
    executable.write_text("cli", encoding="utf-8")
    executable.chmod(0o755)
    monkeypatch.setattr("zp_speech.providers.macwhisper.DEFAULT_EXECUTABLE", tmp_path / "absent")
    monkeypatch.setattr("zp_speech.providers.macwhisper.shutil.which", lambda _: str(executable))
    assert MacWhisperProvider.detect().executable == executable


def test_capabilities_are_verified_and_conservative(tmp_path: Path) -> None:
    runner = QueueRunner([VERSION, MODELS])
    document = MacWhisperProvider(tmp_path / "mw", runner=runner).capabilities()
    validate_document(document)
    assert document["provider_version"] == "14.8.1"
    assert document["models"] == [MODEL, "whisperkit:openai_whisper-small"]
    assert document["capabilities"] == {
        "segment_timestamps": True,
        "word_timestamps": True,
        "diarization": False,
        "language_detection": True,
        "streaming": True,
        "input_formats": ["wav"],
        "output_formats": ["json", "srt", "txt"],
    }


@pytest.mark.parametrize("fixture_name", ["simple.json", "pauses.json", "longer.json"])
def test_real_json_regression_fixtures(fixture_name: str, tmp_path: Path) -> None:
    source = tmp_path / "sample.wav"
    source.write_bytes(b"exact source bytes")
    document = normalize_macwhisper_json(
        (FIXTURES / fixture_name).read_text(encoding="utf-8"),
        source=source,
        model=MODEL,
        language="it",
    )
    validate_document(document)
    assert document["segments"]
    assert document["capabilities"]["word_timestamps"] is True
    assert document["source_id"] == (
        "sha256:08df54b6923c9c8ab26e145805e456aac6ee96804d9a0d31d770f4bf8ccfcecf"
    )


def test_real_speaker_probe_is_conservatively_unlabelled(tmp_path: Path) -> None:
    source = tmp_path / "voices.wav"
    source.write_bytes(b"voices")
    document = normalize_macwhisper_json(
        (FIXTURES / "two-speakers.json").read_text(encoding="utf-8"),
        source=source,
        model=MODEL,
        language="it",
    )
    assert document["capabilities"]["diarization"] is False
    assert all("speaker" not in segment for segment in document["segments"])


def test_normalize_without_words_and_with_speaker(tmp_path: Path) -> None:
    source = tmp_path / "source"
    source.write_bytes(b"x")
    raw = {"segments": [{"start": 0.0, "end": 1000.0, "text": " Ciao ", "speaker": " A "}]}
    document = normalize_macwhisper_json(raw, source=source, model="engine:model", language="auto")
    assert document["engine"] == "engine"
    assert document["segments"] == [{"start_ms": 0, "end_ms": 1000, "text": "Ciao", "speaker": "A"}]
    assert document["capabilities"]["language_detection"] is True
    assert document["capabilities"]["word_timestamps"] is False


def test_normalize_rounding_drift_within_one_ms(tmp_path: Path) -> None:
    source = tmp_path / "source.wav"
    source.write_bytes(b"x")
    raw = {
        "segments": [
            {
                "start": 1,
                "end": 100,
                "text": "Ciao",
                "words": [{"start": 0, "end": 101, "text": "Ciao"}],
            }
        ]
    }
    document = normalize_macwhisper_json(raw, source=source, model=MODEL, language="it")
    assert document["segments"][0]["words"] == [{"start_ms": 1, "end_ms": 100, "text": "Ciao"}]


def test_normalize_clamps_word_overshoot_beyond_rounding(tmp_path: Path) -> None:
    # Real Whisper output: a word can end hundreds of ms after its segment.
    source = tmp_path / "source.wav"
    source.write_bytes(b"x")
    raw = {
        "segments": [
            {
                "start": 2,
                "end": 1000,
                "text": "Ciao mondo",
                "words": [
                    {"start": 0, "end": 500, "text": "Ciao"},
                    {"start": 500, "end": 1201, "text": "mondo"},
                ],
            }
        ]
    }
    document = normalize_macwhisper_json(raw, source=source, model=MODEL, language="it")
    assert document["segments"][0]["words"] == [
        {"start_ms": 2, "end_ms": 500, "text": "Ciao"},
        {"start_ms": 500, "end_ms": 1000, "text": "mondo"},
    ]


def test_normalize_rejects_word_outside_its_segment(tmp_path: Path) -> None:
    source = tmp_path / "source.wav"
    source.write_bytes(b"x")
    raw = {
        "segments": [
            {
                "start": 0,
                "end": 1000,
                "text": "Ciao",
                "words": [{"start": 1200, "end": 1300, "text": "Ciao"}],
            }
        ]
    }
    with pytest.raises(ProviderError, match="lies outside its segment"):
        normalize_macwhisper_json(raw, source=source, model=MODEL, language="it")


@pytest.mark.parametrize(
    ("raw", "message"),
    [
        ("{", "malformed JSON"),
        ({}, "no segments"),
        ({"segments": [1]}, "must be an object"),
        ({"segments": [{"start": True, "end": 2, "text": "x"}]}, "must be a number"),
        ({"segments": [{"start": 0.5, "end": 2, "text": "x"}]}, "integer millisecond"),
        ({"segments": [{"start": 0, "end": 2, "text": " "}]}, "non-empty text"),
        ({"segments": [{"start": 0, "end": 2, "text": "x", "words": {}}]}, "array"),
        ({"segments": [{"start": 0, "end": 2, "text": "x", "words": [1]}]}, "object"),
        (
            {"segments": [{"start": 0, "end": 2, "text": "x", "words": [{"start": 0}]}]},
            "number",
        ),
        ({"segments": [{"start": 3, "end": 2, "text": "x"}]}, "invalid MacWhisper timing"),
    ],
)
def test_malformed_provider_data(raw: Any, message: str, tmp_path: Path) -> None:
    source = tmp_path / "source.wav"
    source.write_bytes(b"x")
    with pytest.raises(ProviderError, match=message) as error:
        normalize_macwhisper_json(raw, source=source, model=MODEL, language="it")
    assert error_code(error) == "transcription_failed"


def test_unreadable_source_during_normalization(tmp_path: Path) -> None:
    with pytest.raises(ProviderError) as error:
        normalize_macwhisper_json(
            {"segments": []}, source=tmp_path / "gone.wav", model=MODEL, language="it"
        )
    assert error_code(error) == "invalid_source"


def test_transcribe_success_and_command(tmp_path: Path) -> None:
    source = tmp_path / "source.wav"
    source.write_bytes(b"audio")
    raw = (FIXTURES / "simple.json").read_text(encoding="utf-8")
    runner = QueueRunner([VERSION, MODELS, subprocess.CompletedProcess([], 0, raw, "")])
    provider = MacWhisperProvider(tmp_path / "mw", runner=runner)
    document = provider.transcribe(source, timeout=30)
    assert document["model"] == MODEL
    assert runner.calls[-1] == (
        [
            str(tmp_path / "mw"),
            "transcribe",
            str(source),
            "--language",
            "it",
            "--format",
            "json",
            "--model",
            MODEL,
            "--no-speakers",
        ],
        30,
    )


def test_transcribe_capability_model_and_cancellation(tmp_path: Path) -> None:
    source = tmp_path / "source.wav"
    source.write_bytes(b"audio")
    provider = MacWhisperProvider(tmp_path / "mw", runner=QueueRunner([VERSION, MODELS]))
    with pytest.raises(ProviderError) as error:
        provider.transcribe(source, speakers=True)
    assert error_code(error) == "unsupported_capability"
    with pytest.raises(ProviderError) as error:
        provider.transcribe(source, cancelled=lambda: True)
    assert error_code(error) == "cancelled"


def test_transcribe_invalid_source_and_model(tmp_path: Path) -> None:
    provider = MacWhisperProvider(tmp_path / "mw", runner=QueueRunner([VERSION, MODELS]))
    with pytest.raises(ProviderError) as error:
        provider.transcribe(tmp_path / "missing.wav")
    assert error_code(error) == "invalid_source"
    source = tmp_path / "source.wav"
    source.write_bytes(b"audio")
    with pytest.raises(ProviderError) as error:
        provider.transcribe(source, model="missing:model")
    assert error_code(error) == "unsupported_model"


def test_transcribe_rejects_unverified_input_format(tmp_path: Path) -> None:
    source = tmp_path / "source.mp3"
    source.write_bytes(b"audio")
    with pytest.raises(ProviderError) as error:
        MacWhisperProvider(tmp_path / "mw").transcribe(source)
    assert error_code(error) == "unsupported_capability"


@pytest.mark.parametrize(
    ("message", "code"),
    [
        ("Unknown model 'x'", "unsupported_model"),
        ("operation cancelled", "cancelled"),
        ("feature unsupported", "unsupported_capability"),
        ("service not running", "provider_unavailable"),
        ("generic failure", "transcription_failed"),
    ],
)
def test_nonzero_exit_mapping(message: str, code: str, tmp_path: Path) -> None:
    provider = MacWhisperProvider(tmp_path / "mw")
    result = subprocess.CompletedProcess([], 1, "", message)
    error = provider._failure(result)
    assert error.code == code
    assert error.retryable is (code == "provider_unavailable")


@pytest.mark.parametrize(
    ("raised", "code"),
    [
        (FileNotFoundError(), "provider_not_found"),
        (subprocess.TimeoutExpired("mw", 1), "timeout"),
        (PermissionError(), "provider_unavailable"),
    ],
)
def test_command_exception_mapping(raised: BaseException, code: str, tmp_path: Path) -> None:
    provider = MacWhisperProvider(tmp_path / "mw", runner=QueueRunner([raised]))
    with pytest.raises(ProviderError) as error:
        provider.capabilities()
    assert error_code(error) == code


@pytest.mark.parametrize(
    "results",
    [
        [subprocess.CompletedProcess([], 1, "", "generic")],
        [subprocess.CompletedProcess([], 0, "", "")],
        [VERSION, subprocess.CompletedProcess([], 1, "", "not ready")],
        [VERSION, subprocess.CompletedProcess([], 0, "Installed models (0):\n", "")],
    ],
)
def test_capability_probe_failures(results: list[object], tmp_path: Path) -> None:
    provider = MacWhisperProvider(tmp_path / "mw", runner=QueueRunner(results))
    with pytest.raises(ProviderError):
        provider.capabilities()


def test_transcribe_empty_and_cancelled_after_run(tmp_path: Path) -> None:
    source = tmp_path / "source.wav"
    source.write_bytes(b"audio")
    provider = MacWhisperProvider(
        tmp_path / "mw",
        runner=QueueRunner([VERSION, MODELS, subprocess.CompletedProcess([], 0, "", "")]),
    )
    with pytest.raises(ProviderError) as error:
        provider.transcribe(source)
    assert error_code(error) == "transcription_failed"

    checks = iter([False, True])
    provider = MacWhisperProvider(
        tmp_path / "mw",
        runner=QueueRunner(
            [VERSION, MODELS, subprocess.CompletedProcess([], 0, '{"segments": []}', "")]
        ),
    )
    with pytest.raises(ProviderError) as error:
        provider.transcribe(source, cancelled=lambda: next(checks))
    assert error_code(error) == "cancelled"


def test_unknown_error_code_is_rejected() -> None:
    with pytest.raises(ValueError, match="unknown public error code"):
        ProviderError("made_up", "no")


def test_default_runner_and_nonmapping_json() -> None:
    result = _run(["/usr/bin/printf", "ok"], 2)
    assert result.stdout == "ok"
    with pytest.raises(ProviderError, match="no segments"):
        normalize_macwhisper_json("[]", source=Path("unused"), model=MODEL, language="it")


def test_transcribe_nonzero_exit(tmp_path: Path) -> None:
    source = tmp_path / "source.wav"
    source.write_bytes(b"audio")
    runner = QueueRunner(
        [VERSION, MODELS, subprocess.CompletedProcess([], 1, "", "transcription broke")]
    )
    with pytest.raises(ProviderError) as error:
        MacWhisperProvider(tmp_path / "mw", runner=runner).transcribe(source)
    assert error_code(error) == "transcription_failed"
