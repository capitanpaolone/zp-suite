"""Canonical time semantics for ZP Speech documents."""


def contains_time(start_ms: int, end_ms: int, time_ms: int) -> bool:
    """Return whether time_ms is inside the half-open interval [start_ms, end_ms)."""

    if start_ms < 0 or start_ms >= end_ms:
        raise ValueError("invalid half-open interval")
    return start_ms <= time_ms < end_ms
