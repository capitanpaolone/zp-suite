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
