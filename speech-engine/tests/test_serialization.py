from __future__ import annotations

import math

import pytest

from zp_speech.serialization import dumps, loads


def test_serialization_is_deterministic_and_unicode_safe(load_fixture):
    document = load_fixture("transcript_with_words.json")
    first = dumps(document)
    second = dumps(dict(reversed(list(document.items()))))

    assert first == second
    assert "Questa è una frase." in first
    assert loads(first) == document


def test_serialization_rejects_non_finite_numbers():
    with pytest.raises(ValueError):
        dumps({"confidence": math.nan})


def test_deserialization_requires_an_object():
    with pytest.raises(ValueError, match="JSON object"):
        loads("[]")
