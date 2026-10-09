from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

from zp_speech.explain import build_keys_prompt, explain_keys
from zp_speech.translate import CodexTranslator, TranslationError


def test_prompt_has_list_language_and_limits() -> None:
    prompt = build_keys_prompt("Space -> Transport: Play/pause\n\nCmd+K -> Item: Trim\n", "it")
    assert "Italian" in prompt and "clear and direct" in prompt
    assert "Space -> Transport: Play/pause\nCmd+K -> Item: Trim" in prompt
    assert "Do not invent" in prompt


def test_explain_runs_codex_plain_text(tmp_path: Path) -> None:
    seen = {}

    def runner(command, **kw):
        seen["command"], seen["input"] = command, kw["input"]
        out = Path(command[command.index("-o") + 1])
        out.write_text("Set per il montaggio.\n", encoding="utf-8")
        return subprocess.CompletedProcess(command, 0, "", "")

    agent = CodexTranslator("/x/codex", model="m1", runner=runner)
    text = explain_keys("S -> Split", agent=agent)
    assert text == "Set per il montaggio."
    assert "--output-schema" not in seen["command"] and seen["command"][-3:] == ["-m", "m1", "-"]
    assert "S -> Split" in seen["input"]


def test_explain_errors() -> None:
    def failing(command, **kw):
        return subprocess.CompletedProcess(command, 1, "", "boom")

    with pytest.raises(TranslationError):
        explain_keys("   ", agent=CodexTranslator("/x/codex", runner=failing))
    with pytest.raises(TranslationError, match="boom"):
        explain_keys("A -> B", agent=CodexTranslator("/x/codex", runner=failing))


def test_prompt_agents_commands_and_cleanup() -> None:
    from zp_speech.translate import PromptAgent, extract_json

    calls = []

    def runner(command, **kw):
        calls.append((command, kw.get("input")))
        out = "\x1b[1m<think>hmm</think>Risposta\x1b[0m\n"
        return subprocess.CompletedProcess(command, 0, out, "")

    claude = PromptAgent("claude", "/x/claude", model="sonnet", runner=runner)
    assert claude.ask("domanda") == "Risposta"
    cmd, stdin = calls[-1]
    assert cmd[:4] == ["/x/claude", "-p", "--output-format", "text"] and "Bash" in cmd[5]
    assert cmd[-2:] == ["--model", "sonnet"] and stdin == "domanda"
    PromptAgent("ollama", "/x/ollama", model="qwen3.6:latest", runner=runner).ask("x")
    assert calls[-1][0][:3] == ["/x/ollama", "run", "qwen3.6:latest"] and calls[-1][1] == "x"
    PromptAgent("opencode", "/x/opencode", runner=runner).ask("y")
    cmd, stdin = calls[-1]
    assert cmd[:3] == ["/x/opencode", "run", "--file"] and stdin is None
    PromptAgent("qwen", "/x/qwen", runner=runner).ask("z")
    assert calls[-1][1] == "z"
    with pytest.raises(TranslationError, match="no local model"):
        PromptAgent("ollama", "/x/ollama", runner=runner).ask("x")
    assert extract_json('Ecco:\n```json\n{"lines": []}\n```') == '{"lines": []}'
    with pytest.raises(TranslationError):
        extract_json("niente json")


def test_prompt_agent_translates_with_json_in_text() -> None:
    from zp_speech.translate import PromptAgent

    def runner(command, **kw):
        assert "Answer ONLY with this JSON" in kw["input"]
        out = 'Sure!\n{"lines": [{"n": 1, "text": "Ciao"}, {"n": 2, "text": "Va / bene"}]}'
        return subprocess.CompletedProcess(command, 0, out, "")

    agent = PromptAgent("claude", "/x/claude", runner=runner)
    out = agent.translate({1: "Hi", 2: "OK"}, "en", "it")
    assert out == {1: "Ciao", 2: "Va\nbene"}


def test_auto_picks_first_available(monkeypatch) -> None:
    import zp_speech.translate as T

    found = {"claude": "/x/claude", "ollama": "/x/ollama"}
    monkeypatch.setattr(T, "find_cli", lambda name: found.get(name))
    monkeypatch.setattr(T, "ollama_models", lambda path: ["gemma4:latest"])
    assert T.resolve_engine("auto") == "claude"
    agent = T.make_translator("auto")
    assert isinstance(agent, T.PromptAgent) and agent.name == "claude"
    ol = T.make_translator("ollama")
    assert ol.model == "gemma4:latest"
    engines = {e["engine"]: e for e in T.available_engines()}
    assert engines["ollama"]["cloud"] is False and "Mac" in engines["ollama"]["where"]
    assert engines["codex"]["available"] is False
    monkeypatch.setattr(T, "find_cli", lambda name: None)
    with pytest.raises(TranslationError, match="no AI agent"):
        T.resolve_engine("auto")
