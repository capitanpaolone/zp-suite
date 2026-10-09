"""Short plain-language explanation of a REAPER shortcut set, written by an AI agent.

Used by ZP Set Comandi (34): REAPER sends only the list "key -> action name" of one set
(a few dozen lines), the agent answers with a few short sentences. Nothing else leaves the Mac.
"""
from __future__ import annotations

from zp_speech.translate import (
    CodexTranslator,
    PromptAgent,
    TranslationError,
    lang_name,
    make_translator,
)

MAX_LINES = 400        # a set is a few dozen lines; cap what we send anyway
MAX_WORDS = 120


def build_keys_prompt(listing: str, lang: str = "it") -> str:
    rows = [r.strip() for r in listing.splitlines() if r.strip()][:MAX_LINES]
    body = "\n".join(rows)
    return (
        "You know the REAPER audio editor well. Below is a set of keyboard shortcuts, "
        "one per line, as 'key -> action'.\n"
        f"Write in {lang_name(lang)}, clear and direct: short sentences, simple words, "
        f"at most {MAX_WORDS} words, plain text only (no markdown, no lists with symbols).\n"
        "First say in one sentence what kind of work this set is made for (for example "
        "editing, recording, mixing, video). Then group the most important shortcuts by "
        "topic (play and record, cutting, zoom, view...), naming a few keys as examples. "
        "If many default keys are only disabled, say so. "
        "Do not invent shortcuts that are not listed.\n\n"
        f"SHORTCUTS:\n{body}\n"
    )


def explain_keys(listing: str, *, engine: str = "auto", model: str | None = None,
                 lang: str = "it", timeout: float = 300,
                 agent: CodexTranslator | PromptAgent | None = None) -> str:
    if not listing.strip():
        raise TranslationError("the set has no shortcuts to explain")
    agent = agent or make_translator(engine, model=model, timeout=timeout)
    text = agent.ask(build_keys_prompt(listing, lang))
    if not text:
        raise TranslationError("the agent gave an empty answer")
    return text
