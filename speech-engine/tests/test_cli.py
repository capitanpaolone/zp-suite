from __future__ import annotations

import json
from pathlib import Path

from zp_speech.cli import main
from zp_speech.providers import ProviderError


class FakeProvider:
    def __init__(self, transcript: dict[str, object], capabilities: dict[str, object]) -> None:
        self.transcript = transcript
        self.info = capabilities
        self.arguments: tuple[object, ...] | None = None

    def capabilities(self) -> dict[str, object]:
        return self.info

    def transcribe(self, source: Path, **kwargs: object) -> dict[str, object]:
        self.arguments = (source, kwargs)
        return self.transcript


def test_doctor_writes_json(load_fixture, capsys) -> None:
    provider = FakeProvider(
        load_fixture("transcript_without_words.json"), load_fixture("provider_capabilities.json")
    )
    assert main(["doctor"], provider_factory=lambda: provider) == 0
    output = json.loads(capsys.readouterr().out)
    assert output["kind"] == "provider_capabilities"


def test_doctor_uses_default_provider(load_fixture, capsys, monkeypatch) -> None:
    provider = FakeProvider(
        load_fixture("transcript_without_words.json"), load_fixture("provider_capabilities.json")
    )
    monkeypatch.setattr("zp_speech.cli.MacWhisperProvider.detect", lambda: provider)
    assert main(["doctor"]) == 0
    assert json.loads(capsys.readouterr().out)["kind"] == "provider_capabilities"


def test_transcribe_json_stdout(load_fixture, capsys, tmp_path: Path) -> None:
    provider = FakeProvider(
        load_fixture("transcript_without_words.json"), load_fixture("provider_capabilities.json")
    )
    source = tmp_path / "voice.wav"
    assert (
        main(
            ["transcribe", str(source), "--language", "auto", "--model", "m", "--timeout", "4"],
            provider_factory=lambda: provider,
        )
        == 0
    )
    assert json.loads(capsys.readouterr().out)["kind"] == "transcript"
    assert provider.arguments == (
        source,
        {"language": "auto", "model": "m", "speakers": False, "timeout": 4.0},
    )


def test_transcribe_srt_to_file(load_fixture, tmp_path: Path) -> None:
    provider = FakeProvider(
        load_fixture("transcript_without_words.json"), load_fixture("provider_capabilities.json")
    )
    output = tmp_path / "result.srt"
    assert (
        main(
            ["transcribe", "voice.wav", "--speakers", "--format", "srt", "--output", str(output)],
            provider_factory=lambda: provider,
        )
        == 0
    )
    assert "-->" in output.read_text(encoding="utf-8")


def test_cli_provider_error(capsys) -> None:
    def fail() -> FakeProvider:
        raise ProviderError("provider_not_found", "missing")

    assert main(["doctor"], provider_factory=fail) == 2
    assert json.loads(capsys.readouterr().err)["error"]["code"] == "provider_not_found"


def test_cli_output_write_error(load_fixture, tmp_path: Path, capsys) -> None:
    provider = FakeProvider(
        load_fixture("transcript_without_words.json"), load_fixture("provider_capabilities.json")
    )
    assert (
        main(
            ["transcribe", "voice.wav", "--output", str(tmp_path)],
            provider_factory=lambda: provider,
        )
        == 2
    )
    assert json.loads(capsys.readouterr().err)["error"]["code"] == "invalid_source"


def test_cli_models_and_download_model(tmp_path: Path, capsys, monkeypatch) -> None:
    monkeypatch.setattr(
        "zp_speech.cli.list_models_status",
        lambda: {"models_dir": str(tmp_path), "free_mb": 1000, "installed": [], "catalog": []},
    )
    assert main(["models"]) == 0
    assert json.loads(capsys.readouterr().out)["models_dir"] == str(tmp_path)

    monkeypatch.setattr(
        "zp_speech.cli.download_model", lambda model, timeout=3600: tmp_path / f"{model}.pt"
    )
    assert main(["download-model", "small"]) == 0
    assert capsys.readouterr().out.strip() == str(tmp_path / "small.pt")

    def fail_download(model: str, timeout: float = 3600) -> Path:
        raise ProviderError("provider_unavailable", "no space", provider="openai-whisper")

    monkeypatch.setattr("zp_speech.cli.download_model", fail_download)
    assert main(["download-model", "small"]) == 2
    assert json.loads(capsys.readouterr().err)["error"]["code"] == "provider_unavailable"


def test_cli_serve_success_and_failure(monkeypatch, capsys) -> None:
    calls: list[tuple[str, int]] = []
    monkeypatch.setattr("zp_speech.service.serve", lambda host, port: calls.append((host, port)))
    assert main(["serve", "--port", "8771"]) == 0
    assert calls == [("127.0.0.1", 8771)]

    def busy(host: str, port: int) -> None:
        raise RuntimeError("un'altra istanza di ZP Speech Service è già attiva")

    monkeypatch.setattr("zp_speech.service.serve", busy)
    assert main(["serve"]) == 2
    assert "già attiva" in capsys.readouterr().err


def test_cli_explain_keys(tmp_path: Path, monkeypatch, capsys) -> None:
    source = tmp_path / "keys.txt"
    source.write_text("Ctrl+S -> Save project\n", encoding="utf-8")
    output = tmp_path / "explained.txt"
    seen: dict[str, object] = {}

    def fake_explain(listing: str, **kwargs: object) -> str:
        seen.update(kwargs, listing=listing)
        return "Ctrl+S salva il progetto"

    monkeypatch.setattr("zp_speech.explain.explain_keys", fake_explain)
    args = ["explain-keys", str(source), "--output", str(output), "--engine", "codex"]
    assert main([*args, "--lang", "en", "--timeout", "9"]) == 0
    assert output.read_text(encoding="utf-8") == "Ctrl+S salva il progetto\n"
    assert seen == {
        "listing": "Ctrl+S -> Save project\n",
        "engine": "codex",
        "model": None,
        "lang": "en",
        "timeout": 9.0,
    }
    assert capsys.readouterr().out.strip() == str(output)

    missing = tmp_path / "missing.txt"
    assert main(["explain-keys", str(missing), "--output", str(output)]) == 2
    assert "zp-speech explain-keys:" in capsys.readouterr().err


def test_cli_request_formats_and_errors(load_fixture, tmp_path: Path, monkeypatch, capsys) -> None:
    transcript = load_fixture("transcript_without_words.json")
    seen: list[dict[str, object]] = []

    def fake_request(source: str, **kwargs: object) -> dict[str, object]:
        seen.append({"source": source, **kwargs})
        return transcript

    monkeypatch.setattr("zp_speech.cli.request_transcription", fake_request)
    source = tmp_path / "voice.wav"
    request = ["request", str(source), "--engine", "openai-whisper", "--model", "small"]
    assert main([*request, "--format", "json", "--timeout", "30"]) == 0
    assert json.loads(capsys.readouterr().out)["kind"] == "transcript"
    assert seen[0] == {
        "source": str(source.resolve()),
        "engine": "openai-whisper",
        "language": "it",
        "model": "small",
        "timeout": 30.0,
    }

    output = tmp_path / "voice.srt"
    assert main(["request", str(source), "--output", str(output)]) == 0
    assert "-->" in output.read_text(encoding="utf-8")

    def unreachable(source: str, **kwargs: object) -> dict[str, object]:
        raise RuntimeError("ZP Speech Service non raggiungibile")

    monkeypatch.setattr("zp_speech.cli.request_transcription", unreachable)
    assert main(["request", str(source)]) == 2
    assert "non raggiungibile" in capsys.readouterr().err


def test_default_provider_uses_auto_detection(load_fixture, monkeypatch) -> None:
    from zp_speech.cli import _default_provider

    provider = FakeProvider(
        load_fixture("transcript_without_words.json"), load_fixture("provider_capabilities.json")
    )
    monkeypatch.setattr("zp_speech.cli.MacWhisperProvider.detect", lambda: provider)
    assert _default_provider() is provider


def test_cli_engine_flag_selects_openai_whisper(load_fixture, monkeypatch, capsys) -> None:
    provider = FakeProvider(
        load_fixture("transcript_without_words.json"), load_fixture("provider_capabilities.json")
    )

    def unexpected() -> FakeProvider:
        raise AssertionError("MacWhisper must not be probed when --engine openai-whisper")

    monkeypatch.setattr("zp_speech.cli.MacWhisperProvider.detect", unexpected)
    monkeypatch.setattr("zp_speech.cli.OpenAIWhisperProvider.detect", lambda: provider)
    assert main(["doctor", "--engine", "openai-whisper"]) == 0
    assert json.loads(capsys.readouterr().out)["kind"] == "provider_capabilities"
