"""SRT translation through a logged-in AI agent CLI (Codex first).

Only the subtitle text travels to the agent, numbered and in blocks; timings never
leave this module. The translated file keeps the original cue count and timestamps,
so it can be attached to the same take markers as the original. If the agent drops,
merges or invents a line, the block is rejected instead of writing a shifted file.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol

TIME_LINE = re.compile(
    r"^\s*(\d{1,2}:\d{2}:\d{2}[,.]\d{1,3})\s*-->\s*(\d{1,2}:\d{2}:\d{2}[,.]\d{1,3})(.*)$"
)
DEFAULT_BLOCK = 60
LANG_NAMES = {
    "it": "Italian", "en": "English", "fr": "French", "de": "German", "es": "Spanish",
    "pt": "Portuguese", "zh": "Chinese", "ja": "Japanese", "ko": "Korean", "ru": "Russian",
}


class TranslationError(Exception):
    """A translation that cannot be trusted or completed."""


@dataclass
class Cue:
    start: str
    end: str
    text: str
    extra: str = ""


def parse_srt(text: str) -> list[Cue]:
    """Read SRT cues; tolerant of BOM, CRLF, missing numbers and dot milliseconds."""
    cues: list[Cue] = []
    lines = text.lstrip("﻿").replace("\r\n", "\n").replace("\r", "\n").split("\n")
    i = 0
    while i < len(lines):
        match = TIME_LINE.match(lines[i])
        if not match:
            i += 1
            continue
        i += 1
        body: list[str] = []
        while i < len(lines) and lines[i].strip() != "":
            if TIME_LINE.match(lines[i]):
                break
            body.append(lines[i])
            i += 1
        # a bare number right before the next timing line is the next cue's index
        if body and body[-1].strip().isdigit() and i < len(lines) and TIME_LINE.match(lines[i]):
            body.pop()
        cues.append(Cue(match.group(1), match.group(2), "\n".join(body).strip(), match.group(3)))
    return cues


def render_srt(cues: Sequence[Cue]) -> str:
    blocks = [
        f"{n}\n{cue.start} --> {cue.end}{cue.extra}\n{cue.text}" for n, cue in enumerate(cues, 1)
    ]
    return "\n\n".join(blocks) + ("\n" if blocks else "")


def lang_name(code: str) -> str:
    return LANG_NAMES.get(code, code)


def build_prompt(lines: Mapping[int, str], source: str, target: str) -> str:
    src = "the original language (detect it)" if source in ("", "auto") else lang_name(source)
    items = "\n".join(f"{n}\t{text.replace(chr(10), ' / ')}" for n, text in lines.items())
    return (
        f"Translate these subtitle lines from {src} into {lang_name(target)}.\n"
        "They are spoken dialogue for dubbing: natural, faithful, similar length.\n"
        "Rules: one output line for every input number, same numbers; never merge, split, skip "
        "or add lines; ' / ' marks a line break, keep it where it fits; keep names; no notes.\n"
        "Do not run commands or read files: answer only with the JSON.\n\n"
        f"{items}\n"
    )


OUTPUT_SCHEMA: dict[str, Any] = {
    "type": "object",
    "additionalProperties": False,
    "required": ["lines"],
    "properties": {
        "lines": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["n", "text"],
                "properties": {"n": {"type": "integer"}, "text": {"type": "string"}},
            },
        }
    },
}


def parse_answer(answer: str, expected: Sequence[int]) -> dict[int, str]:
    """Check the agent's JSON: exactly the expected numbers, each once."""
    try:
        document = json.loads(answer)
    except json.JSONDecodeError as error:
        raise TranslationError(f"the agent did not answer with JSON: {error}") from error
    rows = document.get("lines") if isinstance(document, dict) else None
    if not isinstance(rows, list):
        raise TranslationError("the agent answer has no 'lines' list")
    out: dict[int, str] = {}
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("n"), int):
            raise TranslationError("the agent answer has a malformed line")
        if not isinstance(row.get("text"), str):
            raise TranslationError(f"line {row['n']}: text is not a string")
        if row["n"] in out:
            raise TranslationError(f"line {row['n']} translated twice")
        out[row["n"]] = row["text"].replace(" / ", "\n").strip()
    missing = [n for n in expected if n not in out]
    extra = [n for n in out if n not in set(expected)]
    if missing or extra:
        raise TranslationError(
            f"the agent changed the lines (missing {missing[:5]}, extra {extra[:5]}): "
            "file not written"
        )
    return out


class Translator(Protocol):
    name: str

    def translate(self, lines: Mapping[int, str], source: str, target: str) -> dict[int, str]: ...


Runner = Callable[..., subprocess.CompletedProcess[str]]

# REAPER starts us with a bare PATH: the agent CLIs live in user folders (nvm, ~/.local...).
SEARCH_DIRS = ("~/.local/bin", "~/.opencode/bin", "/opt/homebrew/bin", "/usr/local/bin", "~/bin")


def search_path() -> str:
    dirs = [os.path.expanduser(d) for d in SEARCH_DIRS]
    nvm = Path(os.path.expanduser("~/.nvm/versions/node"))
    if nvm.is_dir():
        dirs += [str(p / "bin") for p in sorted(nvm.iterdir(), reverse=True)]
    dirs += os.environ.get("PATH", "").split(os.pathsep)
    return os.pathsep.join(d for d in dirs if d)


# CLI che arrivano dentro un'app e si aggiornano con lei: hanno la precedenza su quelle
# installate a mano (npm), che restano indietro e non conoscono i modelli nuovi.
APP_CLIS = {"codex": ("/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
                      "/Applications/Codex.app/Contents/Resources/codex-cli/bin/codex")}


def find_cli(name: str) -> str | None:
    for candidate in APP_CLIS.get(name, ()):
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return shutil.which(name, path=search_path())


def codex_config_model(config: Path | None = None) -> str | None:
    """The model chosen in ~/.codex/config.toml (top-level `model = "..."`), if any."""
    path = config or Path(os.path.expanduser("~/.codex/config.toml"))
    try:
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.strip().startswith("["):
                break
            match = re.match(r'\s*model\s*=\s*"([^"]+)"', line)
            if match:
                return match.group(1)
    except OSError:
        return None
    return None


class CodexTranslator:
    """`codex exec` with the user's ChatGPT login, read-only sandbox, fixed JSON schema."""

    name = "codex"

    def __init__(self, executable: str, *, model: str | None = None, timeout: float = 600,
                 runner: Runner = subprocess.run) -> None:
        self.executable = executable
        self.model = model
        self.timeout = timeout
        self.runner = runner

    def translate(self, lines: Mapping[int, str], source: str, target: str) -> dict[int, str]:
        with tempfile.TemporaryDirectory(prefix="zp-translate-") as work:
            schema = Path(work) / "schema.json"
            answer = Path(work) / "answer.json"
            schema.write_text(json.dumps(OUTPUT_SCHEMA), encoding="utf-8")
            command = [
                self.executable, "exec", "--sandbox", "read-only", "--skip-git-repo-check",
                "--ephemeral", "--color", "never", "-C", work,
                "--output-schema", str(schema), "-o", str(answer),
            ]
            if self.model:
                command += ["-m", self.model]
            command.append("-")
            env = dict(os.environ, PATH=search_path())
            try:
                result = self.runner(
                    command, input=build_prompt(lines, source, target), capture_output=True,
                    text=True, timeout=self.timeout, env=env, check=False,
                )
            except subprocess.TimeoutExpired as error:
                message = f"codex did not answer within {self.timeout:.0f} s"
                raise TranslationError(message) from error
            if result.returncode != 0 or not answer.exists():
                detail = (result.stderr or result.stdout or "").strip().splitlines()[-3:]
                raise TranslationError("codex failed: " + " | ".join(detail))
            return parse_answer(answer.read_text(encoding="utf-8"), list(lines))


ENGINES: dict[str, str] = {"codex": "codex"}


def codex_models(executable: str, runner: Runner = subprocess.run) -> list[str]:
    """Models the logged-in Codex offers, best first (`codex debug models`, visible ones only)."""
    try:
        result = runner([executable, "debug", "models"], capture_output=True, text=True,
                        timeout=30, env=dict(os.environ, PATH=search_path()), check=False)
        catalog = json.loads(result.stdout or "{}")
    except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError):
        return []
    rows = [m for m in catalog.get("models", []) if isinstance(m, dict)
            and m.get("visibility") == "list" and isinstance(m.get("slug"), str)]
    rows.sort(key=lambda m: m.get("priority", 999))
    return [m["slug"] for m in rows]


def available_engines() -> list[dict[str, Any]]:
    """Engines this Mac can use now, for the REAPER menu."""
    found = []
    for engine, cli in ENGINES.items():
        path = find_cli(cli)
        models = codex_models(path) if path else []
        found.append({"engine": engine, "available": path is not None, "path": path,
                      "cloud": True, "login": True, "models": models})
    return found


def make_translator(engine: str, *, model: str | None = None, timeout: float = 600) -> Translator:
    if engine not in ENGINES:
        raise TranslationError(f"unknown engine: {engine}")
    path = find_cli(ENGINES[engine])
    if path is None:
        raise TranslationError(f"{engine} is not installed or not found")
    if not model:
        # il modello scelto nella configurazione di Codex, se questo Codex lo offre;
        # altrimenti il primo dell'elenco (non passare mai un modello che rifiuterebbe)
        offered = codex_models(path)
        preferred = codex_config_model()
        model = preferred if preferred in offered else (offered[0] if offered else None)
    return CodexTranslator(path, model=model, timeout=timeout)


def default_output(source: Path, target: str) -> Path:
    """Episodio01.srt -> Episodio01.it.srt (an existing language tag is replaced)."""
    stem = re.sub(r"\.[a-z]{2,3}$", "", source.stem)
    return source.with_name(f"{stem}.{target}.srt")


def translate_srt(
    source: Path, target: str, translator: Translator, *, source_lang: str = "auto",
    block: int = DEFAULT_BLOCK, progress: Callable[[int, int], None] | None = None,
) -> str:
    cues = parse_srt(source.read_text(encoding="utf-8"))
    if not cues:
        raise TranslationError(f"no subtitles found in {source.name}")
    numbered = {n: cue.text for n, cue in enumerate(cues, 1) if cue.text}
    numbers = list(numbered)
    done: dict[int, str] = {}
    for start in range(0, len(numbers), block):
        part = {n: numbered[n] for n in numbers[start:start + block]}
        done.update(translator.translate(part, source_lang, target))
        if progress:
            progress(min(start + block, len(numbers)), len(numbers))
    translated = [
        Cue(cue.start, cue.end, done.get(n, cue.text), cue.extra) for n, cue in enumerate(cues, 1)
    ]
    return render_srt(translated)
