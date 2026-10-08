from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

from zp_speech import translate as T
from zp_speech.cli import main

SRT = (
    "﻿1\r\n00:00:00,520 --> 00:00:02,000\r\n你好\r\n\r\n"
    "2\n00:00:03.100 --> 00:00:05,000 X1:10\nprima riga\nseconda riga\n\n"
    "3\n00:00:06,000 --> 00:00:07,000\n\n\n"
    "4\n00:00:08,000 --> 00:00:09,500\n12\n"
)


def test_parse_and_render_keep_timings() -> None:
    cues = T.parse_srt(SRT)
    starts = ["00:00:00,520", "00:00:03.100", "00:00:06,000", "00:00:08,000"]
    assert [c.start for c in cues] == starts
    assert cues[1].text == "prima riga\nseconda riga"
    assert cues[1].extra == " X1:10"
    assert cues[2].text == ""
    assert cues[3].text == "12"  # a number as dialogue is kept
    again = T.parse_srt(T.render_srt(cues))
    assert [(c.start, c.end, c.text) for c in again] == [(c.start, c.end, c.text) for c in cues]


def test_parse_without_numbers() -> None:
    cues = T.parse_srt("00:00:01,000 --> 00:00:02,000\nuno\n00:00:03,000 --> 00:00:04,000\ndue\n")
    assert [c.text for c in cues] == ["uno", "due"]


def test_parse_answer_checks_numbers() -> None:
    answer = json.dumps({"lines": [{"n": 2, "text": "a / b"}, {"n": 1, "text": "c"}]})
    ok = T.parse_answer(answer, [1, 2])
    assert ok == {1: "c", 2: "a\nb"}
    for bad, msg in [
        ("not json", "JSON"),
        (json.dumps({"x": 1}), "lines"),
        (json.dumps({"lines": [{"n": 1, "text": "a"}]}), "missing"),
        (json.dumps({"lines": [{"n": 1, "text": "a"}, {"n": 1, "text": "b"}]}), "twice"),
        (json.dumps({"lines": [{"n": i, "text": "x"} for i in (1, 2, 3)]}), "extra"),
        (json.dumps({"lines": [{"n": "1", "text": "a"}]}), "malformed"),
        (json.dumps({"lines": [{"n": 1, "text": 5}]}), "string"),
    ]:
        with pytest.raises(T.TranslationError, match=msg):
            T.parse_answer(bad, [1, 2] if msg != "malformed" and msg != "string" else [1])


class FakeTranslator:
    name = "fake"

    def __init__(self) -> None:
        self.calls: list[dict[int, str]] = []

    def translate(self, lines, source, target):
        self.calls.append(dict(lines))
        return {n: f"[{target}] {text}" for n, text in lines.items()}


def test_translate_srt_blocks_and_keeps_empty(tmp_path: Path) -> None:
    src = tmp_path / "Episodio01.srt"
    src.write_text(SRT, encoding="utf-8")
    fake = FakeTranslator()
    seen: list[tuple[int, int]] = []
    out = T.translate_srt(src, "it", fake, block=2, progress=lambda d, t: seen.append((d, t)))
    assert [sorted(c) for c in fake.calls] == [[1, 2], [4]]  # empty cue 3 not sent
    assert seen == [(2, 3), (3, 3)]
    cues = T.parse_srt(out)
    assert len(cues) == 4
    assert cues[0].text == "[it] 你好" and cues[0].start == "00:00:00,520"
    assert cues[2].text == ""


def test_translate_srt_empty_file(tmp_path: Path) -> None:
    src = tmp_path / "vuoto.srt"
    src.write_text("niente", encoding="utf-8")
    with pytest.raises(T.TranslationError, match="no subtitles"):
        T.translate_srt(src, "it", FakeTranslator())


def test_default_output_names() -> None:
    assert T.default_output(Path("/a/Episodio01.srt"), "it") == Path("/a/Episodio01.it.srt")
    assert T.default_output(Path("/a/Episodio01.zh.srt"), "it") == Path("/a/Episodio01.it.srt")


def test_prompt_mentions_languages_and_rules() -> None:
    prompt = T.build_prompt({7: "a\nb"}, "zh", "it")
    assert "from Chinese into Italian" in prompt and "7\ta / b" in prompt
    assert "detect it" in T.build_prompt({1: "x"}, "auto", "fr")


def test_codex_command_and_answer(tmp_path: Path) -> None:
    captured = {}

    def runner(command, **kwargs):
        captured["command"] = command
        captured["input"] = kwargs["input"]
        captured["path"] = kwargs["env"]["PATH"]
        out = Path(command[command.index("-o") + 1])
        schema = json.loads(Path(command[command.index("--output-schema") + 1]).read_text())
        assert schema["required"] == ["lines"]
        out.write_text(json.dumps({"lines": [{"n": 1, "text": "ciao"}]}), encoding="utf-8")
        return subprocess.CompletedProcess(command, 0, "", "")

    tr = T.CodexTranslator("/x/codex", model="gpt-x", runner=runner)
    assert tr.translate({1: "hello"}, "en", "it") == {1: "ciao"}
    cmd = captured["command"]
    assert cmd[:4] == ["/x/codex", "exec", "--sandbox", "read-only"]
    assert "--ephemeral" in cmd and cmd[-1] == "-" and cmd[cmd.index("-m") + 1] == "gpt-x"
    assert "1\thello" in captured["input"]


def test_codex_failure_and_timeout() -> None:
    def fails(command, **kwargs):
        return subprocess.CompletedProcess(command, 1, "", "line1\nNot logged in\n")

    with pytest.raises(T.TranslationError, match="Not logged in"):
        T.CodexTranslator("/x/codex", runner=fails).translate({1: "a"}, "en", "it")

    def slow(command, **kwargs):
        raise subprocess.TimeoutExpired(command, 1)

    with pytest.raises(T.TranslationError, match="did not answer"):
        T.CodexTranslator("/x/codex", timeout=1, runner=slow).translate({1: "a"}, "en", "it")


def test_find_cli_uses_user_dirs(tmp_path: Path, monkeypatch) -> None:
    bin_dir = tmp_path / ".nvm" / "versions" / "node" / "v1" / "bin"
    bin_dir.mkdir(parents=True)
    tool = bin_dir / "codex"
    tool.write_text("#!/bin/sh\n")
    tool.chmod(0o755)
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("PATH", "/usr/bin")
    monkeypatch.setattr(T, "APP_CLIS", {})
    assert T.find_cli("codex") == str(tool)
    engines = T.available_engines()
    assert engines[0]["engine"] == "codex" and engines[0]["available"]
    assert isinstance(T.make_translator("codex"), T.CodexTranslator)
    with pytest.raises(T.TranslationError, match="unknown"):
        T.make_translator("nope")
    monkeypatch.setenv("HOME", str(tmp_path / "vuota"))
    with pytest.raises(T.TranslationError, match="not installed"):
        T.make_translator("codex")


def test_cli_translate(tmp_path: Path, monkeypatch, capsys) -> None:
    src = tmp_path / "ep.srt"
    src.write_text(SRT, encoding="utf-8")
    monkeypatch.setattr("zp_speech.translate.make_translator", lambda *a, **k: FakeTranslator())
    assert main(["translate", str(src), "--to", "it"]) == 0
    out = tmp_path / "ep.it.srt"
    assert out.exists() and capsys.readouterr().out.strip() == str(out)
    assert main(["translate", str(src), "--to", "it"]) == 2  # no overwrite
    assert "exists" in capsys.readouterr().err
    assert main(["translate", str(src), "--to", "it", "--overwrite"]) == 0
    assert main(["translate", str(tmp_path / "manca.srt"), "--to", "it", "--output",
                 str(tmp_path / "x.srt")]) == 2


def test_cli_translators(capsys) -> None:
    assert main(["translators"]) == 0
    assert "engines" in json.loads(capsys.readouterr().out)


def test_codex_models_best_first() -> None:
    catalog = {"models": [
        {"slug": "old", "visibility": "list", "priority": 9},
        {"slug": "hidden", "visibility": "hide", "priority": 1},
        {"slug": "best", "visibility": "list", "priority": 2},
    ]}

    def runner(command, **kwargs):
        assert command[1:] == ["debug", "models"]
        return subprocess.CompletedProcess(command, 0, json.dumps(catalog), "")

    assert T.codex_models("/x/codex", runner=runner) == ["best", "old"]

    def broken(command, **kwargs):
        return subprocess.CompletedProcess(command, 1, "not json", "")

    assert T.codex_models("/x/codex", runner=broken) == []


def test_make_translator_picks_offered_model(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(T, "find_cli", lambda name: "/x/codex")
    monkeypatch.setattr(T, "codex_models", lambda path: ["best", "old"])
    monkeypatch.setattr(T, "codex_config_model", lambda: "old")
    assert T.make_translator("codex").model == "old"  # quello della configurazione
    monkeypatch.setattr(T, "codex_config_model", lambda: "sparito")
    assert T.make_translator("codex").model == "best"
    assert T.make_translator("codex", model="old").model == "old"
    monkeypatch.setattr(T, "codex_models", lambda path: [])
    assert T.make_translator("codex").model is None


def test_find_cli_prefers_app_bundle(tmp_path: Path, monkeypatch) -> None:
    app = tmp_path / "codex"
    app.write_text("#!/bin/sh\n")
    app.chmod(0o755)
    monkeypatch.setattr(T, "APP_CLIS", {"codex": (str(tmp_path / "manca"), str(app))})
    assert T.find_cli("codex") == str(app)


def test_codex_config_model(tmp_path: Path) -> None:
    cfg = tmp_path / "config.toml"
    cfg.write_text('model = "gpt-6-luna"\nmodel_verbosity = "low"\n[profiles.x]\nmodel = "y"\n')
    assert T.codex_config_model(cfg) == "gpt-6-luna"
    cfg.write_text('[profiles.x]\nmodel = "y"\n')
    assert T.codex_config_model(cfg) is None
    assert T.codex_config_model(tmp_path / "manca.toml") is None
