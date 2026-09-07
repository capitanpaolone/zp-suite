from __future__ import annotations

import json
from pathlib import Path

import pytest

from zp_speech.exporters import transcript_to_srt
from zp_speech.validation import ContractValidationError


def test_srt_matches_real_macwhisper_fixture(load_fixture) -> None:
    transcript = load_fixture("transcript_with_words.json")
    transcript["segments"] = [
        {
            "start_ms": 20,
            "end_ms": 3640,
            "text": "Buongiorno, questa è una prova semplice dello ZP Speed Engine.",
        }
    ]
    transcript["capabilities"]["word_timestamps"] = False
    expected = (
        Path(__file__).parent / "fixtures" / "macwhisper" / "14.8.1" / "simple.srt"
    ).read_text(encoding="utf-8")
    assert transcript_to_srt(transcript) == expected.rstrip() + "\n"


def test_srt_multiple_segments_and_empty(load_fixture) -> None:
    transcript = load_fixture("transcript_without_words.json")
    transcript["segments"] = [
        {"start_ms": 3_661_002, "end_ms": 3_662_003, "text": "Uno"},
        {"start_ms": 3_662_003, "end_ms": 3_663_004, "text": "Due"},
    ]
    rendered = transcript_to_srt(transcript)
    assert "01:01:01,002 --> 01:01:02,003" in rendered
    assert rendered.endswith("Due\n")
    transcript["segments"] = []
    assert transcript_to_srt(transcript) == ""


def test_srt_rejects_non_transcript() -> None:
    document = json.loads(
        (Path(__file__).parent / "fixtures" / "provider_capabilities.json").read_text()
    )
    with pytest.raises(ContractValidationError, match="requires a transcript"):
        transcript_to_srt(document)
