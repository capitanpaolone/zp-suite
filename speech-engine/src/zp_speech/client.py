"""Small synchronous client for the local ZP Speech Service job API."""

from __future__ import annotations

import json
import os
import time
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from zp_speech.providers import ProviderError

DEFAULT_BASE_URL = "http://127.0.0.1:8770"


def _get_json(url: str, timeout: float = 10) -> dict[str, Any]:
    request = Request(url, headers={"Accept": "application/json"})
    with urlopen(request, timeout=timeout) as response:
        payload = json.load(response)
    if not isinstance(payload, dict):
        raise RuntimeError("ZP Speech Service returned invalid JSON")
    return payload


def request_transcription(
    source: str,
    *,
    language: str = "it",
    model: str | None = None,
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
    request = Request(
        f"{endpoint}/api/v1/transcriptions",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )
    try:
        with urlopen(request, timeout=10) as response:
            submitted = json.load(response)
    except HTTPError as error:
        try:
            document = json.loads(error.read())
            provider_error = document.get("error", {})
            message = provider_error.get("message") if isinstance(provider_error, dict) else None
        except (ValueError, UnicodeDecodeError):
            message = None
        raise RuntimeError(message or f"ZP Speech Service ha risposto HTTP {error.code}") from error
    if not isinstance(submitted, dict) or not isinstance(submitted.get("job_id"), str):
        raise RuntimeError("ZP Speech Service non ha restituito l'ID del job")

    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            job = _get_json(f"{endpoint}/api/v1/jobs/{submitted['job_id']}", timeout=15)
        except (OSError, ValueError, URLError, TimeoutError) as error:
            raise RuntimeError(f"Connessione a ZP Speech Service interrotta: {error}") from error
        state = job.get("status")
        if state == "succeeded":
            result = job.get("result")
            if not isinstance(result, dict) or result.get("kind") != "transcript":
                raise RuntimeError("Il servizio ha restituito un transcript ZP non valido")
            return result
        if state == "failed":
            document = job.get("error", {})
            error_doc = document.get("error", {}) if isinstance(document, dict) else {}
            message = error_doc.get("message") if isinstance(error_doc, dict) else None
            raise ProviderError(
                str(error_doc.get("code", "transcription_failed")),
                str(message or "Trascrizione ZP non riuscita"),
            )
        if state not in {"queued", "running"}:
            raise RuntimeError(f"Stato job ZP non riconosciuto: {state}")
        time.sleep(poll_interval)
    raise TimeoutError("Tempo massimo di attesa del job ZP Speech superato")
