from __future__ import annotations

import subprocess
import sys
from collections.abc import Sequence
from pathlib import Path
from typing import Any

import pytest

from zp_speech.providers import (
    OpenAIWhisperProvider,
    ProviderError,
    canonical_model_stem,
    default_models_dir,
    default_whisper_python,
    detect_provider,
    download_model,
    installed_models,
    list_models_status,
    normalize_openai_whisper_json,
    zp_data_root,
)
from zp_speech.providers.openai_whisper import find_ffmpeg
from zp_speech.validation import validate_document

PROBE_OK = subprocess.CompletedProcess([], 0, '{"version": "20240930", "torch": "2.5.1"}\n', "")
SAMPLE_RESULT = (
    '{"text": "Buongiorno a tutti.", "language": "it", '
    '"segments": [{"start": 0.02, "end": 1.84, "text": " Buongiorno a tutti. ", '
    '"words": [{"word": " Buongiorno", "start": 0.02, "end": 0.9, "probability": 0.98}, '
    '{"word": " a", "start": 0.9, "end": 1.1, "probability": 0.95}, '
    '{"word": " tutti.", "start": 1.1, "end": 1.84, "probability": 0.99}]}]}'
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


def _make_exec(path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("#!/bin/sh\n", encoding="utf-8")
    path.chmod(0o755)
    return path


def _make_model(models_dir: Path, name: str = "small") -> Path:
    models_dir.mkdir(parents=True, exist_ok=True)
    pt = models_dir / f"{name}.pt"
    pt.write_bytes(b"weights")
    return pt


def test_zp_data_root_platforms(tmp_path: Path) -> None:
    assert zp_data_root(env={"ZP_DATA_DIR": str(tmp_path / "custom")}) == tmp_path / "custom"
    assert (
        zp_data_root(platform="darwin", env={}, home=tmp_path)
        == tmp_path / "Library" / "Application Support" / "ZP"
    )
    assert (
        zp_data_root(platform="win32", env={"LOCALAPPDATA": str(tmp_path / "Local")}, home=tmp_path)
        == tmp_path / "Local" / "ZP"
    )
    assert (
        zp_data_root(platform="win32", env={}, home=tmp_path)
        == tmp_path / "AppData" / "Local" / "ZP"
    )
    assert (
        zp_data_root(platform="linux", env={"XDG_DATA_HOME": str(tmp_path / "xdg")}, home=tmp_path)
        == tmp_path / "xdg" / "zp"
    )
    assert (
        zp_data_root(platform="linux", env={}, home=tmp_path)
        == tmp_path / ".local" / "share" / "zp"
    )


def test_default_paths(tmp_path: Path) -> None:
    assert default_whisper_python(tmp_path, platform="darwin") == (
        tmp_path / "runtimes" / "openai-whisper" / "bin" / "python"
    )
    assert default_whisper_python(tmp_path, platform="win32") == (
        tmp_path / "runtimes" / "openai-whisper" / "Scripts" / "python.exe"
    )
    assert default_models_dir(tmp_path) == tmp_path / "models" / "whisper"


def test_canonical_model_stem_and_installed_models(tmp_path: Path) -> None:
    assert canonical_model_stem("small") == "small"
    assert canonical_model_stem("openai-whisper:turbo") == "large-v3-turbo"
    assert canonical_model_stem("large") == "large-v3"
    with pytest.raises(ProviderError) as err1:
        canonical_model_stem("whisperkit:small")
    assert error_code(err1) == "unsupported_model"
    with pytest.raises(ProviderError) as err2:
        canonical_model_stem("openai-whisper:   ")
    assert error_code(err2) == "unsupported_model"

    assert installed_models(tmp_path / "missing") == []
    models_dir = tmp_path / "models"
    _make_model(models_dir, "small")
    _make_model(models_dir, "large-v3-turbo")
    _make_model(models_dir, "custom-it")
    (models_dir / ".hidden.pt").write_bytes(b"x")
    (models_dir / "empty.pt").write_bytes(b"")
    assert installed_models(models_dir) == [
        "openai-whisper:large-v3-turbo",
        "openai-whisper:small",
        "openai-whisper:custom-it",
    ]


def test_find_ffmpeg(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    ff = _make_exec(tmp_path / "ffmpeg")
    assert find_ffmpeg(ff, env={}) == ff
    assert find_ffmpeg(env={"ZP_FFMPEG_BIN": str(ff)}) == ff

    monkeypatch.setattr("zp_speech.providers.openai_whisper.shutil.which", lambda *_, **__: None)
    monkeypatch.setattr(
        "zp_speech.providers.openai_whisper._is_executable",
        lambda p: p == ff,
    )
    with pytest.raises(ProviderError) as error:
        find_ffmpeg(tmp_path / "missing", env={"PATH": ""})
    assert error_code(error) == "provider_unavailable"


def test_find_ffmpeg_private_zp_copy(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    name = "ffmpeg.exe" if sys.platform.startswith("win") else "ffmpeg"
    private = _make_exec(tmp_path / "ffmpeg" / "bin" / name)
    monkeypatch.setattr("zp_speech.providers.openai_whisper.shutil.which", lambda *_, **__: None)
    assert find_ffmpeg(env={"ZP_DATA_DIR": str(tmp_path), "PATH": ""}) == private


def test_detect_provider_errors_and_success(tmp_path: Path) -> None:
    py = tmp_path / "python"
    ff = _make_exec(tmp_path / "ffmpeg")
    models_dir = tmp_path / "models"
    with pytest.raises(ProviderError) as err_missing:
        OpenAIWhisperProvider.detect(py, ffmpeg_executable=ff, models_dir=models_dir)
    assert error_code(err_missing) == "provider_not_found"

    py.write_text("#!/bin/sh\n", encoding="utf-8")
    py.chmod(0o644)
    with pytest.raises(ProviderError) as err_perm:
        OpenAIWhisperProvider.detect(py, ffmpeg_executable=ff, models_dir=models_dir)
    assert error_code(err_perm) == "provider_unavailable"

    py.chmod(0o755)
    provider = OpenAIWhisperProvider.detect(
        env={
            "ZP_WHISPER_PYTHON": str(py),
            "ZP_FFMPEG_BIN": str(ff),
            "ZP_WHISPER_MODELS_DIR": str(models_dir),
        }
    )
    assert provider.python_executable == py
    assert provider.ffmpeg_executable == ff
    assert provider.models_dir == models_dir


def test_capabilities_and_probe_errors(tmp_path: Path) -> None:
    py = _make_exec(tmp_path / "python")
    ff = _make_exec(tmp_path / "ffmpeg")
    models_dir = tmp_path / "models"

    # No models installed yet
    provider_no_models = OpenAIWhisperProvider(
        py, ffmpeg_executable=ff, models_dir=models_dir, runner=QueueRunner([PROBE_OK])
    )
    with pytest.raises(ProviderError) as err_no_models:
        provider_no_models.capabilities()
    assert error_code(err_no_models) == "provider_unavailable"

    _make_model(models_dir, "small")
    provider = OpenAIWhisperProvider(
        py, ffmpeg_executable=ff, models_dir=models_dir, runner=QueueRunner([PROBE_OK])
    )
    cap = provider.capabilities()
    validate_document(cap)
    assert cap["provider"] == "openai-whisper"
    assert cap["provider_version"] == "20240930"
    assert cap["models"] == ["openai-whisper:small"]

    # Probe failures
    for bad_result in (
        subprocess.CompletedProcess([], 1, "", "ImportError: No module named whisper"),
        subprocess.CompletedProcess([], 0, "{not-json", ""),
        subprocess.CompletedProcess([], 0, '{"version": ""}', ""),
    ):
        p = OpenAIWhisperProvider(
            py, ffmpeg_executable=ff, models_dir=models_dir, runner=QueueRunner([bad_result])
        )
        with pytest.raises(ProviderError) as err:
            p.capabilities()
        assert error_code(err) == "provider_unavailable"


@pytest.mark.parametrize(
    ("raised", "expected_code"),
    [
        (FileNotFoundError(), "provider_not_found"),
        (subprocess.TimeoutExpired("python", 1), "timeout"),
        (PermissionError(), "provider_unavailable"),
    ],
)
def test_command_exceptions(raised: BaseException, expected_code: str, tmp_path: Path) -> None:
    py = _make_exec(tmp_path / "python")
    ff = _make_exec(tmp_path / "ffmpeg")
    provider = OpenAIWhisperProvider(
        py, ffmpeg_executable=ff, models_dir=tmp_path / "models", runner=QueueRunner([raised])
    )
    with pytest.raises(ProviderError) as error:
        provider.capabilities()
    assert error_code(error) == expected_code


def test_normalize_openai_whisper_json_variants(tmp_path: Path) -> None:
    source = tmp_path / "sample.wav"
    source.write_bytes(b"audio-bytes")
    doc = normalize_openai_whisper_json(
        SAMPLE_RESULT, source=source, model="small", language="auto"
    )
    validate_document(doc)
    assert doc["provider"] == "openai-whisper"
    assert doc["model"] == "openai-whisper:small"
    assert doc["language"] == "it"
    assert doc["capabilities"]["word_timestamps"] is True
    assert doc["segments"][0]["start_ms"] == 20
    assert doc["segments"][0]["end_ms"] == 1840
    assert doc["segments"][0]["words"][0] == {
        "start_ms": 20,
        "end_ms": 900,
        "text": "Buongiorno",
        "confidence": 0.98,
    }

    # Clamping, empty segments skipped, empty word skipped, zero-length word at start and inside
    edge_raw = {
        "segments": [
            {"start": 0.0, "end": 0.5, "text": "   "},
            {
                "start": 0.1,
                "end": 1.0,
                "text": "Uno due tre",
                "words": [
                    {"word": "  ", "start": 0.1, "end": 0.2},
                    {"word": "Uno", "start": 0.0, "end": 0.05},
                    {"text": "due", "start": 0.5, "end": 0.5},
                    {"word": "tre", "start": 1.2, "end": 1.5},
                ],
            },
        ]
    }
    doc_edge = normalize_openai_whisper_json(
        edge_raw, source=source, model="openai-whisper:small", language="it"
    )
    validate_document(doc_edge)
    assert doc_edge["segments"][0]["words"] == [
        {"start_ms": 100, "end_ms": 101, "text": "Uno"},
        {"start_ms": 499, "end_ms": 500, "text": "due"},
        {"start_ms": 999, "end_ms": 1000, "text": "tre"},
    ]


@pytest.mark.parametrize(
    ("raw", "match"),
    [
        ("{", "malformed JSON"),
        ("[]", "no segments"),
        ({}, "no segments"),
        ({"segments": [1]}, "must be an object"),
        ({"segments": [{"start": True, "end": 1.0, "text": "x"}]}, "number of seconds"),
        ({"segments": [{"start": -1.0, "end": 1.0, "text": "x"}]}, "non-negative finite"),
        ({"segments": [{"start": 1.0, "end": 1.0, "text": "x"}]}, "start < end"),
        ({"segments": [{"start": 0.0, "end": 1.0, "text": 123}]}, "non-empty text"),
        ({"segments": [{"start": 0.0, "end": 1.0, "text": "x", "words": {}}]}, "must be an array"),
        (
            {"segments": [{"start": 0.0, "end": 1.0, "text": "x", "words": [1]}]},
            "must be an object",
        ),
        (
            {
                "segments": [
                    {"start": 0.5, "end": 1.0, "text": "dopo"},
                    {"start": 0.1, "end": 0.4, "text": "prima"},
                ]
            },
            "invalid OpenAI Whisper timing",
        ),
    ],
)
def test_normalize_openai_whisper_errors(raw: Any, match: str, tmp_path: Path) -> None:
    source = tmp_path / "sample.wav"
    source.write_bytes(b"x")
    with pytest.raises(ProviderError, match=match) as error:
        normalize_openai_whisper_json(raw, source=source, model="small", language="it")
    assert error_code(error) == "transcription_failed"


def test_normalize_unreadable_source(tmp_path: Path) -> None:
    with pytest.raises(ProviderError) as error:
        normalize_openai_whisper_json(
            {"segments": []}, source=tmp_path / "missing.wav", model="small", language="it"
        )
    assert error_code(error) == "invalid_source"


def test_transcribe_flow_and_errors(tmp_path: Path) -> None:
    py = _make_exec(tmp_path / "python")
    ff = _make_exec(tmp_path / "ffmpeg")
    models_dir = tmp_path / "models"
    _make_model(models_dir, "small")
    source = tmp_path / "voice.wav"
    source.write_bytes(b"wav")

    runner = QueueRunner([PROBE_OK, subprocess.CompletedProcess([], 0, SAMPLE_RESULT, "")])
    provider = OpenAIWhisperProvider(py, ffmpeg_executable=ff, models_dir=models_dir, runner=runner)
    doc = provider.transcribe(source, model="small", language="it", timeout=25)
    assert doc["model"] == "openai-whisper:small"

    # Explicit None model uses first installed
    runner2 = QueueRunner([PROBE_OK, subprocess.CompletedProcess([], 0, SAMPLE_RESULT, "")])
    provider2 = OpenAIWhisperProvider(
        py, ffmpeg_executable=ff, models_dir=models_dir, runner=runner2
    )
    assert provider2.transcribe(source, model=None)["model"] == "openai-whisper:small"

    # Missing source, non-wav, cancelled before, speakers=True, missing model
    with pytest.raises(ProviderError) as e_src:
        provider.transcribe(tmp_path / "absent.wav")
    assert error_code(e_src) == "invalid_source"

    mp3 = tmp_path / "voice.mp3"
    mp3.write_bytes(b"mp3")
    with pytest.raises(ProviderError) as e_mp3:
        provider.transcribe(mp3)
    assert error_code(e_mp3) == "unsupported_capability"

    with pytest.raises(ProviderError) as e_cancel:
        provider.transcribe(source, cancelled=lambda: True)
    assert error_code(e_cancel) == "cancelled"

    provider_spk = OpenAIWhisperProvider(
        py, ffmpeg_executable=ff, models_dir=models_dir, runner=QueueRunner([PROBE_OK])
    )
    with pytest.raises(ProviderError) as e_spk:
        provider_spk.transcribe(source, speakers=True)
    assert error_code(e_spk) == "unsupported_capability"

    provider_mod = OpenAIWhisperProvider(
        py, ffmpeg_executable=ff, models_dir=models_dir, runner=QueueRunner([PROBE_OK])
    )
    with pytest.raises(ProviderError) as e_mod:
        provider_mod.transcribe(source, model="medium")
    assert error_code(e_mod) == "unsupported_model"

    # Cancelled after run, non-zero exit, empty stdout
    checks = iter([False, True])
    provider_c2 = OpenAIWhisperProvider(
        py,
        ffmpeg_executable=ff,
        models_dir=models_dir,
        runner=QueueRunner([PROBE_OK, subprocess.CompletedProcess([], 0, SAMPLE_RESULT, "")]),
    )
    with pytest.raises(ProviderError) as e_c2:
        provider_c2.transcribe(source, cancelled=lambda: next(checks))
    assert error_code(e_c2) == "cancelled"

    provider_fail = OpenAIWhisperProvider(
        py,
        ffmpeg_executable=ff,
        models_dir=models_dir,
        runner=QueueRunner([PROBE_OK, subprocess.CompletedProcess([], 1, "", "boom")]),
    )
    with pytest.raises(ProviderError) as e_fail:
        provider_fail.transcribe(source)
    assert error_code(e_fail) == "transcription_failed"

    provider_empty = OpenAIWhisperProvider(
        py,
        ffmpeg_executable=ff,
        models_dir=models_dir,
        runner=QueueRunner([PROBE_OK, subprocess.CompletedProcess([], 0, "  ", "")]),
    )
    with pytest.raises(ProviderError) as e_empty:
        provider_empty.transcribe(source)
    assert error_code(e_empty) == "transcription_failed"


def test_list_models_status_and_download_model(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    models_dir = tmp_path / "deep" / "nested" / "models"
    status = list_models_status(models_dir)
    assert status["installed"] == []
    assert status["free_mb"] > 0

    py = _make_exec(tmp_path / "python")
    with pytest.raises(ProviderError) as e_unknown:
        download_model("nonexistent-model", python_executable=py, models_dir=models_dir)
    assert error_code(e_unknown) == "unsupported_model"

    with pytest.raises(ProviderError) as e_nopy:
        download_model("tiny", python_executable=tmp_path / "no_py", models_dir=models_dir)
    assert error_code(e_nopy) == "provider_not_found"

    # Successful download when runner writes the .pt file
    def fake_dl_runner(args: Sequence[str], timeout: float) -> subprocess.CompletedProcess[str]:
        _make_model(models_dir, "tiny")
        return subprocess.CompletedProcess(list(args), 0, str(models_dir / "tiny.pt") + "\n", "")

    downloaded = download_model(
        "tiny", python_executable=py, models_dir=models_dir, runner=fake_dl_runner
    )
    assert downloaded == models_dir / "tiny.pt"

    # Runner exits 0 but file missing
    with pytest.raises(ProviderError) as e_nofile:
        download_model(
            "base",
            python_executable=py,
            models_dir=models_dir,
            runner=QueueRunner([subprocess.CompletedProcess([], 0, "", "")]),
        )
    assert error_code(e_nofile) == "provider_unavailable"

    # Runner fails
    with pytest.raises(ProviderError) as e_dlfail:
        download_model(
            "base",
            python_executable=py,
            models_dir=models_dir,
            runner=QueueRunner([subprocess.CompletedProcess([], 1, "", "network error")]),
        )
    assert error_code(e_dlfail) == "provider_unavailable"

    # Insufficient disk space
    monkeypatch.setattr(
        "zp_speech.providers.openai_whisper.shutil.disk_usage",
        lambda _: type("U", (), {"free": 10 * 1024 * 1024})(),
    )
    with pytest.raises(ProviderError) as e_space:
        download_model("large-v3", python_executable=py, models_dir=models_dir)
    assert error_code(e_space) == "provider_unavailable"


def test_detect_provider_selection() -> None:
    class DummyProvider:
        def __init__(self, name: str) -> None:
            self.name = name

        def capabilities(self) -> dict[str, Any]:
            return {"provider": self.name}

    mw = DummyProvider("macwhisper")
    ow = DummyProvider("openai-whisper")

    assert (
        detect_provider(
            "macwhisper", macwhisper_detector=lambda: mw, openai_whisper_detector=lambda: ow
        )
        is mw
    )
    assert (
        detect_provider(
            "openai-whisper", macwhisper_detector=lambda: mw, openai_whisper_detector=lambda: ow
        )
        is ow
    )
    assert (
        detect_provider(
            "auto",
            model="openai-whisper:small",
            macwhisper_detector=lambda: mw,
            openai_whisper_detector=lambda: ow,
        )
        is ow
    )
    assert (
        detect_provider(
            "auto",
            model="whisperkit:small",
            macwhisper_detector=lambda: mw,
            openai_whisper_detector=lambda: ow,
        )
        is mw
    )
    assert (
        detect_provider("auto", macwhisper_detector=lambda: mw, openai_whisper_detector=lambda: ow)
        is mw
    )

    def fail_mw() -> Any:
        raise ProviderError("provider_not_found", "no mw")

    def fail_ow() -> Any:
        raise ProviderError("provider_not_found", "no ow", provider="openai-whisper")

    assert (
        detect_provider("auto", macwhisper_detector=fail_mw, openai_whisper_detector=lambda: ow)
        is ow
    )
    with pytest.raises(ProviderError) as e_both:
        detect_provider("auto", macwhisper_detector=fail_mw, openai_whisper_detector=fail_ow)
    assert error_code(e_both) == "provider_not_found"

    with pytest.raises(ProviderError) as e_bad:
        detect_provider("unknown-engine")
    assert error_code(e_bad) == "unsupported_capability"


def test_find_model_file_and_cache_fallback(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    from zp_speech.providers.openai_whisper import find_model_file, installed_models

    primary = tmp_path / "primary"
    primary.mkdir()
    cache = tmp_path / "cache"
    cache.mkdir()
    target = "zp_speech.providers.openai_whisper.default_whisper_cache_dir"
    monkeypatch.setattr(target, lambda: cache)

    (cache / "small.pt").write_bytes(b"small-weights")
    assert find_model_file("small", primary) == cache / "small.pt"
    assert installed_models(primary, include_cache=True) == ["openai-whisper:small"]

    # Primary overrides cache
    (primary / "small.pt").write_bytes(b"primary-weights")
    assert find_model_file("small", primary) == primary / "small.pt"
