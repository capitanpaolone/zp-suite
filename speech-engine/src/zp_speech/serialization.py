"""Deterministic JSON serialization for contract documents."""

from __future__ import annotations

import json
from collections.abc import Mapping
from typing import Any, cast


def dumps(document: Mapping[str, Any]) -> str:
    """Serialize a document deterministically for fixtures, cache and IPC."""

    return json.dumps(
        document,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    )


def loads(payload: str) -> dict[str, Any]:
    """Deserialize a JSON object, rejecting non-object top-level values."""

    value = json.loads(payload)
    if not isinstance(value, dict):
        raise ValueError("A ZP Speech document must be a JSON object")
    return cast(dict[str, Any], value)
