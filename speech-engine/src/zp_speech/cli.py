"""Minimal command-line entry point for ZP Speech Engine."""

from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Callable, Sequence
from pathlib import Path
from typing import Any, Protocol

from zp_speech.exporters import transcript_to_srt
from zp_speech.providers import MacWhisperProvider, ProviderError


class SpeechProvider(Protocol):
    def capabilities(self) -> dict[str, Any]: ...

    def transcribe(
        self,
        source: Path,
        *,
        language: str,
        model: str | None,
        speakers: bool,
        timeout: float,
    ) -> dict[str, Any]: ...


ProviderFactory = Callable[[], SpeechProvider]


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="zp-speech")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("doctor", help="inspect the MacWhisper CLI")
    transcribe = commands.add_parser("transcribe", help="transcribe a local audio file")
    transcribe.add_argument("source", type=Path)
    transcribe.add_argument("--engine", choices=["macwhisper"], default="macwhisper")
    transcribe.add_argument("--language", default="it")
    transcribe.add_argument("--model")
    transcribe.add_argument("--speakers", action="store_true")
    transcribe.add_argument("--timeout", type=float, default=120)
    transcribe.add_argument("--format", choices=["json", "srt"], default="json")
    transcribe.add_argument("--output", type=Path)
    return parser


def _default_provider() -> SpeechProvider:
    return MacWhisperProvider.detect()


def main(
    argv: Sequence[str] | None = None,
    *,
    provider_factory: ProviderFactory = _default_provider,
) -> int:
    """Run a CLI command and return a process-style exit status."""
    args = _parser().parse_args(argv)
    try:
        provider = provider_factory()
        if args.command == "doctor":
            payload = provider.capabilities()
            rendered = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
        else:
            payload = provider.transcribe(
                args.source,
                language=args.language,
                model=args.model,
                speakers=args.speakers,
                timeout=args.timeout,
            )
            rendered = (
                transcript_to_srt(payload)
                if args.format == "srt"
                else json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
            )
        output = getattr(args, "output", None)
        if output is None:
            sys.stdout.write(rendered)
        else:
            output.write_text(rendered, encoding="utf-8")
        return 0
    except (ProviderError, OSError) as error:
        provider_error = (
            error
            if isinstance(error, ProviderError)
            else ProviderError("invalid_source", f"cannot write output: {error}")
        )
        sys.stderr.write(
            json.dumps(provider_error.as_document(), ensure_ascii=False, sort_keys=True) + "\n"
        )
        return 2
