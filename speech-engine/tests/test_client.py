from __future__ import annotations

import io
import json
from collections.abc import Callable
from email.message import Message
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request

import pytest

from zp_speech import client as client_module
from zp_speech.client import _get_json, request_transcription
from zp_speech.providers import ProviderError

BASE = "http://127.0.0.1:8770"
HEALTH_OK = {"status": "ok", "engine": "zp-speech-service-v1", "api_version": "v1"}
JOB_ID = "a" * 32


# io.BytesIO is already a context manager and readable by json.load, like urlopen's response.
FakeResponse = io.BytesIO


def respond(payload: object) -> FakeResponse:
    return FakeResponse(json.dumps(payload).encode("utf-8"))


class Router:
    """Fake urlopen: route by method + path; job polls consume a queue of documents."""

    def __init__(
        self,
        *,
        health: object = HEALTH_OK,
        submit: object | Exception = None,
        jobs: list[object | Exception] | None = None,
    ) -> None:
        self.health = health
        self.submit = {"job_id": JOB_ID, "status": "queued"} if submit is None else submit
        self.jobs = list(jobs or [])
        self.posted: list[dict[str, Any]] = []

    def __call__(self, request: Request, timeout: float = 10) -> FakeResponse:
        url = request.full_url
        if url.endswith("/api/v1/health"):
            if isinstance(self.health, Exception):
                raise self.health
            return respond(self.health)
        if url.endswith("/api/v1/transcriptions"):
            assert request.get_method() == "POST"
            data = request.data
            assert isinstance(data, bytes)
            self.posted.append(json.loads(data))
            if isinstance(self.submit, Exception):
                raise self.submit
            return respond(self.submit)
        assert url.endswith(f"/api/v1/jobs/{JOB_ID}")
        item = self.jobs.pop(0)
        if isinstance(item, Exception):
            raise item
        return respond(item)


@pytest.fixture
def no_sleep(monkeypatch) -> None:
    monkeypatch.setattr(client_module.time, "sleep", lambda _seconds: None)


def install(monkeypatch, router: Callable[..., FakeResponse]) -> None:
    monkeypatch.setattr(client_module, "urlopen", router)


def http_error(code: int, body: bytes) -> HTTPError:
    return HTTPError(f"{BASE}/api/v1/transcriptions", code, "err", Message(), io.BytesIO(body))


def test_get_json_rejects_non_object(monkeypatch) -> None:
    install(monkeypatch, lambda request, timeout=10: respond([1, 2]))
    with pytest.raises(RuntimeError, match="invalid JSON"):
        _get_json(f"{BASE}/api/v1/health")


def test_success_returns_transcript_and_sends_payload(monkeypatch, no_sleep) -> None:
    transcript = {"kind": "transcript", "segments": []}
    router = Router(
        jobs=[
            {"status": "queued"},
            {"status": "running"},
            {"status": "succeeded", "result": transcript},
        ]
    )
    install(monkeypatch, router)
    result = request_transcription(
        "/tmp/voice.wav",
        language="auto",
        model="openai-whisper:small",
        engine="openai-whisper",
        timeout=60,
        base_url=BASE + "/",
    )
    assert result == transcript
    assert router.posted == [
        {
            "source": "/tmp/voice.wav",
            "language": "auto",
            "timeout": 60,
            "model": "openai-whisper:small",
            "engine": "openai-whisper",
        }
    ]


def test_auto_engine_and_env_url_are_respected(monkeypatch, no_sleep) -> None:
    seen: list[str] = []
    router = Router(jobs=[{"status": "succeeded", "result": {"kind": "transcript"}}])

    def recording(request: Request, timeout: float = 10) -> FakeResponse:
        seen.append(request.full_url)
        return router(request, timeout)

    install(monkeypatch, recording)
    monkeypatch.setenv("ZP_SPEECH_URL", "http://localhost:9999")
    request_transcription("/tmp/voice.wav", engine="auto")
    assert router.posted[0] == {"source": "/tmp/voice.wav", "language": "it", "timeout": 21600}
    assert all(url.startswith("http://localhost:9999/") for url in seen)


def test_unreachable_service_times_out(monkeypatch, no_sleep) -> None:
    install(monkeypatch, Router(health=URLError("refused")))
    clock = iter([0.0, 0.5, 100.0])
    monkeypatch.setattr(client_module.time, "monotonic", lambda: next(clock))
    with pytest.raises(RuntimeError, match="non raggiungibile"):
        request_transcription("/tmp/voice.wav", timeout=5, base_url=BASE)


def test_unexpected_service_on_port(monkeypatch) -> None:
    install(monkeypatch, Router(health={"status": "ok", "engine": "something-else"}))
    with pytest.raises(RuntimeError, match="Servizio inatteso"):
        request_transcription("/tmp/voice.wav", base_url=BASE)


@pytest.mark.parametrize(
    ("body", "expected"),
    [
        (json.dumps({"error": {"message": "source must be a file"}}).encode(), "must be a file"),
        (json.dumps({"error": "plain"}).encode(), "HTTP 422"),
        (json.dumps([1]).encode(), "HTTP 422"),
        (b"not json", "HTTP 422"),
    ],
)
def test_submit_http_errors(monkeypatch, body: bytes, expected: str) -> None:
    install(monkeypatch, Router(submit=http_error(422, body)))
    with pytest.raises(RuntimeError, match=expected):
        request_transcription("/tmp/voice.wav", base_url=BASE)


@pytest.mark.parametrize("submitted", [[1], {"job_id": 7}])
def test_submit_without_job_id(monkeypatch, submitted: object) -> None:
    install(monkeypatch, Router(submit=submitted))
    with pytest.raises(RuntimeError, match="ID del job"):
        request_transcription("/tmp/voice.wav", base_url=BASE)


def test_poll_connection_error(monkeypatch) -> None:
    install(monkeypatch, Router(jobs=[URLError("reset")]))
    with pytest.raises(RuntimeError, match="interrotta"):
        request_transcription("/tmp/voice.wav", base_url=BASE)


@pytest.mark.parametrize("result", [None, {"kind": "error"}])
def test_succeeded_with_invalid_result(monkeypatch, result: object) -> None:
    install(monkeypatch, Router(jobs=[{"status": "succeeded", "result": result}]))
    with pytest.raises(RuntimeError, match="non valido"):
        request_transcription("/tmp/voice.wav", base_url=BASE)


@pytest.mark.parametrize(
    ("error", "code", "message"),
    [
        (
            {"error": {"code": "unsupported_model", "message": "model is not installed"}},
            "unsupported_model",
            "model is not installed",
        ),
        ({"error": "flat"}, "transcription_failed", "Trascrizione ZP non riuscita"),
        (None, "transcription_failed", "Trascrizione ZP non riuscita"),
    ],
)
def test_failed_job_raises_provider_error(
    monkeypatch, error: object, code: str, message: str
) -> None:
    install(monkeypatch, Router(jobs=[{"status": "failed", "error": error}]))
    with pytest.raises(ProviderError, match=message) as caught:
        request_transcription("/tmp/voice.wav", base_url=BASE)
    assert caught.value.code == code


def test_unknown_job_state(monkeypatch) -> None:
    install(monkeypatch, Router(jobs=[{"status": "exploded"}]))
    with pytest.raises(RuntimeError, match="non riconosciuto"):
        request_transcription("/tmp/voice.wav", base_url=BASE)


def test_job_wait_deadline(monkeypatch, no_sleep) -> None:
    install(monkeypatch, Router(jobs=[{"status": "running"}]))
    # startup deadline, job deadline, first loop check, second loop check (expired)
    clock = iter([0.0, 0.0, 0.0, 10.0])
    monkeypatch.setattr(client_module.time, "monotonic", lambda: next(clock))
    with pytest.raises(TimeoutError, match="Tempo massimo"):
        request_transcription("/tmp/voice.wav", timeout=5, base_url=BASE)
