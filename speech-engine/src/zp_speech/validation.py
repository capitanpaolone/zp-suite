"""JSON Schema and semantic validation for ZP Speech v1 documents."""

from __future__ import annotations

import json
from collections.abc import Mapping, Sequence
from functools import lru_cache
from importlib.resources import files
from typing import Any

from jsonschema import Draft202012Validator
from jsonschema.exceptions import ValidationError
from jsonschema.protocols import Validator


class ContractValidationError(ValueError):
    """Raised when a document violates the public v1 contract."""


@lru_cache(maxsize=1)
def _validator() -> Validator:
    schema_path = files("zp_speech").joinpath("schemas/zp-speech-v1.schema.json")
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema)


def _fail(path: str, message: str) -> None:
    raise ContractValidationError(f"{path}: {message}")


def _ordered(intervals: Sequence[Mapping[str, Any]], path: str) -> None:
    previous: tuple[int, int] | None = None
    for index, interval in enumerate(intervals):
        current = (interval["start_ms"], interval["end_ms"])
        if current[0] >= current[1]:
            _fail(f"{path}[{index}]", "interval must satisfy start_ms < end_ms")
        if previous is not None and current < previous:
            _fail(f"{path}[{index}]", "intervals must be ordered by start_ms, then end_ms")
        previous = current


def _validate_transcript(document: Mapping[str, Any]) -> None:
    if document["source_id"] != document["source"]["source_id"]:
        _fail("source.source_id", "must equal the transcript source_id")
    expected_source_id = "sha256:" + document["source"]["content_hash"]["digest"]
    if document["source_id"] != expected_source_id:
        _fail("source.content_hash.digest", "must be the digest encoded by source_id")
    if not document["capabilities"]["segment_timestamps"]:
        _fail("capabilities.segment_timestamps", "must be true for a timed transcript")
    segments = document["segments"]
    _ordered(segments, "segments")
    word_timestamps = document["capabilities"]["word_timestamps"]

    for segment_index, segment in enumerate(segments):
        if segment.get("speaker") is not None and not document["capabilities"]["diarization"]:
            _fail(
                f"segments[{segment_index}].speaker",
                "speaker labels require capabilities.diarization=true",
            )
        words = segment.get("words")
        if words is None:
            continue
        if not word_timestamps:
            _fail(
                f"segments[{segment_index}].words",
                "words require capabilities.word_timestamps=true",
            )
        _ordered(words, f"segments[{segment_index}].words")
        for word_index, word in enumerate(words):
            if word["start_ms"] < segment["start_ms"] or word["end_ms"] > segment["end_ms"]:
                _fail(
                    f"segments[{segment_index}].words[{word_index}]",
                    "word interval must be contained in its segment interval",
                )


def _validate_search_result(document: Mapping[str, Any]) -> None:
    matches = document["matches"]
    _ordered(matches, "matches")
    for index, match in enumerate(matches):
        if match["segment_start_ms"] >= match["segment_end_ms"]:
            _fail(f"matches[{index}]", "segment interval must satisfy start_ms < end_ms")
        if match["source_id"] != document["source_id"]:
            _fail(f"matches[{index}].source_id", "must equal the result source_id")
        if match["start_ms"] < match["segment_start_ms"]:
            _fail(f"matches[{index}].start_ms", "must fall inside the segment")
        if match["end_ms"] > match["segment_end_ms"]:
            _fail(f"matches[{index}].end_ms", "must fall inside the segment")


def validate_document(document: Mapping[str, Any]) -> None:
    """Validate JSON shape and cross-field temporal invariants.

    All time intervals use integer milliseconds and half-open semantics
    ``[start_ms, end_ms)``. Therefore every interval requires start_ms < end_ms.
    """

    try:
        _validator().validate(document)
    except ValidationError as error:
        path = ".".join(str(part) for part in error.absolute_path) or "$"
        raise ContractValidationError(f"{path}: {error.message}") from error

    kind = document["kind"]
    if kind == "transcript":
        _validate_transcript(document)
    elif kind == "search_result":
        _validate_search_result(document)
