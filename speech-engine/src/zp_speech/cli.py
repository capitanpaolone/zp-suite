"""Minimal command-line entry point for ZP Speech Engine."""

from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Callable, Sequence
from pathlib import Path
from typing import Any, Protocol

from zp_speech.client import request_transcription
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
    serve = commands.add_parser("serve", help="run the singleton loopback speech service")
    serve.add_argument("--host", choices=["127.0.0.1", "localhost"], default="127.0.0.1")
    serve.add_argument("--port", type=int, choices=range(1024, 65536), default=8770)
    request_service = commands.add_parser("request", help="submit a job to the shared local service")
    request_service.add_argument("source", type=Path)
    request_service.add_argument("--language", default="it")
    request_service.add_argument("--model")
    request_service.add_argument("--timeout", type=float, default=21600)
    request_service.add_argument("--format", choices=["json", "srt"], default="srt")
    request_service.add_argument("--output", type=Path)
    translate = commands.add_parser("translate", help="translate an SRT with a logged-in AI agent")
    translate.add_argument("source", type=Path)
    translate.add_argument("--to", required=True, dest="target")
    translate.add_argument("--from", default="auto", dest="source_lang")
    translate.add_argument("--engine", default="auto")
    translate.add_argument("--model")
    translate.add_argument("--timeout", type=float, default=600)
    translate.add_argument("--block", type=int, default=60)
    translate.add_argument("--output", type=Path)
    translate.add_argument("--overwrite", action="store_true")
    commands.add_parser("translators", help="list the translation engines available here")
    explain = commands.add_parser(
        "explain-keys", help="explain a REAPER shortcut list with a logged-in AI agent")
    explain.add_argument("source", type=Path, help="text file, one 'key -> action' per line")
    explain.add_argument("--output", type=Path, required=True)
    explain.add_argument("--engine", default="auto")
    explain.add_argument("--model")
    explain.add_argument("--lang", default="it")
    explain.add_argument("--timeout", type=float, default=300)
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


def _translate(args: argparse.Namespace) -> int:
    from zp_speech.translate import (
        TranslationError,
        default_output,
        make_translator,
        translate_srt,
    )

    source = args.source.expanduser().resolve()
    output = (args.output or default_output(source, args.target)).expanduser()
    if output.exists() and not args.overwrite:
        sys.stderr.write(f"zp-speech translate: {output.name} exists already (use --overwrite)\n")
        return 2

    def progress(done: int, total: int) -> None:
        sys.stderr.write(f"progress {done}/{total}\n")
        sys.stderr.flush()

    try:
        translator = make_translator(args.engine, model=args.model, timeout=args.timeout)
        rendered = translate_srt(source, args.target, translator, source_lang=args.source_lang,
                                 block=max(1, args.block), progress=progress)
        output.write_text(rendered, encoding="utf-8")
    except (TranslationError, OSError, UnicodeDecodeError) as error:
        sys.stderr.write(f"zp-speech translate: {error}\n")
        return 2
    sys.stdout.write(str(output) + "\n")
    return 0


def _default_provider() -> SpeechProvider:
    return MacWhisperProvider.detect()


def main(
    argv: Sequence[str] | None = None,
    *,
    provider_factory: ProviderFactory = _default_provider,
) -> int:
    """Run a CLI command and return a process-style exit status."""
    args = _parser().parse_args(argv)
    if args.command == "serve":
        from zp_speech.service import serve

        try:
            serve(args.host, args.port)
        except (OSError, RuntimeError, ValueError) as error:
            sys.stderr.write(f"zp-speech serve: {error}\n")
            return 2
        return 0
    if args.command == "translators":
        from zp_speech.translate import available_engines

        sys.stdout.write(json.dumps({"engines": available_engines()}, ensure_ascii=False) + "\n")
        return 0
    if args.command == "translate":
        return _translate(args)
    if args.command == "explain-keys":
        from zp_speech.explain import explain_keys
        from zp_speech.translate import TranslationError

        try:
            listing = args.source.expanduser().read_text(encoding="utf-8")
            text = explain_keys(listing, engine=args.engine, model=args.model,
                                lang=args.lang, timeout=args.timeout)
            args.output.expanduser().write_text(text + "\n", encoding="utf-8")
        except (TranslationError, OSError, UnicodeDecodeError) as error:
            sys.stderr.write(f"zp-speech explain-keys: {error}\n")
            return 2
        sys.stdout.write(str(args.output) + "\n")
        return 0
    if args.command == "request":
        try:
            payload = request_transcription(
                str(args.source.expanduser().resolve()), language=args.language,
                model=args.model, timeout=args.timeout,
            )
            rendered = (
                transcript_to_srt(payload)
                if args.format == "srt"
                else json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
            )
            if args.output is None:
                sys.stdout.write(rendered)
            else:
                args.output.write_text(rendered, encoding="utf-8")
            return 0
        except (ProviderError, OSError, RuntimeError, TimeoutError) as error:
            sys.stderr.write(f"zp-speech request: {error}\n")
            return 2
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
