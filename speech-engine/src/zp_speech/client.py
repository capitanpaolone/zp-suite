"""Small synchronous client for the local ZP Speech Service job API."""

from __future__ import annotations

import json
import os
import time
from typing import Any, cast
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from zp_speech.providers import ProviderError

DEFAULT_BASE_URL = "http://127.0.0.1:8770"


def _as_dict(value: object) -> dict[str, Any] | None:
    return cast(dict[str, Any], value) if isinstance(value, dict) else None


def _get_json(url: str, timeout: float = 10) -> dict[str, Any]:
    request = Request(url, headers={"Accept": "application/json"})
    with urlopen(request, timeout=timeout) as response:
        payload: object = json.load(response)
    document = _as_dict(payload)
    if document is None:
        raise RuntimeError("ZP Speech Service returned invalid JSON")
    return document


def request_transcription(
    source: str,
    *,
    language: str = "it",
    model: str | None = None,
    engine: str | None = None,
    timeout: float = 21600,
    poll_interval: float = 1.0,
    base_url: str | None = None,
) -> dict[str, Any]:
    """Submit a local WAV and return its validated ZP Speech v1 transcript."""
    endpoint = (base_url or os.environ.get("ZP_SPEECH_URL") or DEFAULT_BASE_URL).rstrip("/")
    startup_deadline = time.monotonic() + min(timeout, 15)
    last_error: Exception | None = None
    while True:
        try:
            health = _get_json(f"{endpoint}/api/v1/health")
            break
        except (OSError, ValueError, URLError, TimeoutError) as error:
            last_error = error
            if time.monotonic() >= startup_deadline:
                raise RuntimeError(
                    f"ZP Speech Service non raggiungibile su {endpoint}: {last_error}"
                ) from error
            time.sleep(0.25)
    if health.get("engine") != "zp-speech-service-v1" or health.get("status") != "ok":
        raise RuntimeError(f"Servizio inatteso su {endpoint}")

    payload: dict[str, Any] = {"source": source, "language": language, "timeout": timeout}
    if model:
        payload["model"] = model
    if engine and engine != "auto":
        payload["engine"] = engine
    request = Request(
        f"{endpoint}/api/v1/transcriptions",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )
    try:
        with urlopen(request, timeout=10) as response:
            raw_submitted: object = json.load(response)
    except HTTPError as error:
        message: object = None
        try:
            document = _as_dict(json.loads(error.read())) or {}
            provider_error = _as_dict(document.get("error")) or {}
            message = provider_error.get("message")
        except (ValueError, UnicodeDecodeError):
            message = None
        raise RuntimeError(
            str(message or f"ZP Speech Service ha risposto HTTP {error.code}")
        ) from error
    submitted = _as_dict(raw_submitted)
    if submitted is None or not isinstance(submitted.get("job_id"), str):
        raise RuntimeError("ZP Speech Service non ha restituito l'ID del job")

    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            job = _get_json(f"{endpoint}/api/v1/jobs/{submitted['job_id']}", timeout=15)
        except (OSError, ValueError, URLError, TimeoutError) as error:
            raise RuntimeError(f"Connessione a ZP Speech Service interrotta: {error}") from error
        state = job.get("status")
        if state == "succeeded":
            result = _as_dict(job.get("result"))
            if result is None or result.get("kind") != "transcript":
                raise RuntimeError("Il servizio ha restituito un transcript ZP non valido")
            return result
        if state == "failed":
            failure = _as_dict(job.get("error")) or {}
            error_doc = _as_dict(failure.get("error")) or {}
            raise ProviderError(
                str(error_doc.get("code", "transcription_failed")),
                str(error_doc.get("message") or "Trascrizione ZP non riuscita"),
            )
        if state not in {"queued", "running"}:
            raise RuntimeError(f"Stato job ZP non riconosciuto: {state}")
        time.sleep(poll_interval)
    raise TimeoutError("Tempo massimo di attesa del job ZP Speech superato")
