"""SubRip export from normalized source-time transcripts."""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any, cast

from zp_speech.validation import ContractValidationError, validate_document


def _timestamp(milliseconds: int) -> str:
    hours, remainder = divmod(milliseconds, 3_600_000)
    minutes, remainder = divmod(remainder, 60_000)
    seconds, millis = divmod(remainder, 1_000)
    return f"{hours:02d}:{minutes:02d}:{seconds:02d},{millis:03d}"


def transcript_to_srt(document: Mapping[str, Any]) -> str:
    """Render validated transcript segments as deterministic UTF-8 SRT text."""
    validate_document(document)
    if document["kind"] != "transcript":
        raise ContractValidationError("kind: SRT export requires a transcript")
    blocks: list[str] = []
    segments = cast(list[Mapping[str, Any]], document["segments"])
    for number, segment in enumerate(segments, start=1):
        blocks.append(
            f"{number}\n{_timestamp(segment['start_ms'])} --> "
            f"{_timestamp(segment['end_ms'])}\n{segment['text']}"
        )
    return "\n\n".join(blocks) + ("\n" if blocks else "")
