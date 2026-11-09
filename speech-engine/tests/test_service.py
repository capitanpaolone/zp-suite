from __future__ import annotations

import http.client
import json
import socket
import threading
import time
import wave
from collections.abc import Iterator
from pathlib import Path
from typing import Any

import pytest

from zp_speech import service as service_module
from zp_speech.providers import ProviderError
from zp_speech.service import (
    MAX_OUTSTANDING_JOBS,
    SERVICE_ENGINE,
    Job,
    SingletonLock,
    SpeechService,
    _is_loopback_host,
    create_server,
    serve,
)


def write_wav(path: Path, *, seconds: float = 0.5, rate: int = 16000) -> Path:
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(rate)
        wav.writeframes(b"\x00\x00" * int(rate * seconds))
    return path


class FakeProvider:
    def __init__(self, transcript: dict[str, Any], *, error: Exception | None = None) -> None:
        self.transcript = transcript
        self.error = error
        self.calls: list[dict[str, Any]] = []

    def capabilities(self) -> dict[str, Any]:
        if self.error is not None:
            raise self.error
        return {"kind": "provider_capabilities", "provider": "fake"}

    def transcribe(self, source: Path, **kwargs: Any) -> dict[str, Any]:
        self.calls.append({"source": source, **kwargs})
        if self.error is not None:
            raise self.error
        return json.loads(json.dumps(self.transcript))


def wait_done(service: SpeechService, job: Job) -> dict[str, Any]:
    assert job.future is not None
    job.future.result(timeout=5)
    return service.job_document(job)


# --- SingletonLock -----------------------------------------------------------


def test_singleton_lock_blocks_second_instance(tmp_path: Path) -> None:
    first = SingletonLock(tmp_path / "control")
    lock_file = tmp_path / "control" / "speech-service.lock"
    assert lock_file.read_text(encoding="utf-8").strip().isdigit()
    with pytest.raises(RuntimeError, match="già attiva"):
        SingletonLock(tmp_path / "control")
    first.close()
    second = SingletonLock(tmp_path / "control")
    second.close()


def test_singleton_lock_uses_env_control_dir(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("ZP_CONTROL_DIR", str(tmp_path / "env-control"))
    lock = SingletonLock()
    assert (tmp_path / "env-control" / "speech-service.lock").is_file()
    lock.close()


# --- SpeechService.submit validation ------------------------------------------


@pytest.mark.parametrize(
    ("request_doc", "code"),
    [
        ({}, "invalid_source"),
        ({"source": "relative.wav"}, "invalid_source"),
        ({"source": "/definitely/missing/zp.wav"}, "invalid_source"),
    ],
)
def test_submit_rejects_bad_sources(request_doc: dict[str, Any], code: str) -> None:
    service = SpeechService(FakeProvider({}))
    try:
        with pytest.raises(ProviderError) as caught:
            service.submit(request_doc)
        assert caught.value.code == code
    finally:
        service.close()


def test_submit_rejects_directory(tmp_path: Path) -> None:
    service = SpeechService(FakeProvider({}))
    try:
        with pytest.raises(ProviderError, match="must be a file"):
            service.submit({"source": str(tmp_path)})
    finally:
        service.close()


@pytest.mark.parametrize(
    ("extra", "code"),
    [
        ({"engine": "whisper.cpp"}, "unsupported_capability"),
        ({"engine": 3}, "unsupported_capability"),
        ({"language": ""}, "invalid_source"),
        ({"language": "x" * 33}, "invalid_source"),
        ({"model": 5}, "unsupported_model"),
        ({"model": "m" * 257}, "unsupported_model"),
        ({"speakers": "yes"}, "unsupported_capability"),
        ({"timeout": True}, "timeout"),
        ({"timeout": "10"}, "timeout"),
        ({"timeout": 0}, "timeout"),
        ({"timeout": 21601}, "timeout"),
    ],
)
def test_submit_rejects_bad_parameters(tmp_path: Path, extra: dict[str, Any], code: str) -> None:
    source = write_wav(tmp_path / "voice.wav")
    service = SpeechService(FakeProvider({}))
    try:
        with pytest.raises(ProviderError) as caught:
            service.submit({"source": str(source), **extra})
        assert caught.value.code == code
    finally:
        service.close()


# --- SpeechService job execution ----------------------------------------------


def test_job_succeeds_and_adds_wav_duration(load_fixture, tmp_path: Path) -> None:
    source = write_wav(tmp_path / "voice.wav", seconds=0.5)
    provider = FakeProvider(load_fixture("transcript_without_words.json"))
    service = SpeechService(provider)
    try:
        job = service.submit(
            {
                "source": str(source),
                "engine": "openai-whisper",
                "language": "auto",
                "model": "openai-whisper:small",
                "speakers": False,
                "timeout": 30,
            }
        )
        document = wait_done(service, job)
        assert document["status"] == "succeeded"
        assert document["error"] is None
        assert document["result"]["source"]["duration_ms"] == 500
        assert provider.calls[0]["language"] == "auto"
        assert provider.calls[0]["model"] == "openai-whisper:small"
        assert provider.calls[0]["timeout"] == 30.0
        assert service.get_document(job.job_id) == document
        assert service.get_document("0" * 32) is None
    finally:
        service.close()


def test_job_with_non_wav_source_keeps_provider_result(load_fixture, tmp_path: Path) -> None:
    source = tmp_path / "voice.wav"
    source.write_bytes(b"not a riff file")
    service = SpeechService(FakeProvider(load_fixture("transcript_without_words.json")))
    try:
        document = wait_done(service, service.submit({"source": str(source)}))
        assert document["status"] == "succeeded"
        assert "duration_ms" not in document["result"]["source"]
    finally:
        service.close()


def test_job_provider_error_is_reported(tmp_path: Path) -> None:
    source = write_wav(tmp_path / "voice.wav")
    error = ProviderError("unsupported_model", "model is not installed: medium")
    service = SpeechService(FakeProvider({}, error=error))
    try:
        document = wait_done(service, service.submit({"source": str(source)}))
        assert document["status"] == "failed"
        assert document["error"]["error"]["code"] == "unsupported_model"
    finally:
        service.close()


def test_job_unexpected_exception_is_contained(tmp_path: Path) -> None:
    source = write_wav(tmp_path / "voice.wav")
    service = SpeechService(FakeProvider({}, error=ZeroDivisionError("boom")))
    try:
        document = wait_done(service, service.submit({"source": str(source)}))
        assert document["status"] == "failed"
        assert document["error"]["error"]["code"] == "transcription_failed"
    finally:
        service.close()


def test_service_resolves_provider_via_detection(load_fixture, tmp_path: Path, monkeypatch) -> None:
    provider = FakeProvider(load_fixture("transcript_without_words.json"))
    seen: list[tuple[str, str | None]] = []

    def fake_detect(engine: str, *, model: str | None = None) -> FakeProvider:
        seen.append((engine, model))
        return provider

    monkeypatch.setattr(service_module, "detect_provider", fake_detect)
    service = SpeechService(engine="macwhisper")
    try:
        assert service.capabilities()["provider"] == "fake"
        assert service.capabilities(engine="openai-whisper")["provider"] == "fake"
        source = write_wav(tmp_path / "voice.wav")
        wait_done(service, service.submit({"source": str(source), "model": "m"}))
        assert seen == [("macwhisper", None), ("openai-whisper", None), ("macwhisper", "m")]
    finally:
        service.close()


def test_queue_limit_and_history_eviction(tmp_path: Path) -> None:
    source = write_wav(tmp_path / "voice.wav")
    service = SpeechService(FakeProvider({}))
    try:
        with service.lock:
            for index in range(MAX_OUTSTANDING_JOBS):
                service.jobs[f"{index:032x}"] = Job(f"{index:032x}", status="running")
        with pytest.raises(ProviderError) as caught:
            service.submit({"source": str(source)})
        assert caught.value.code == "provider_unavailable"
        assert caught.value.retryable is True

        with service.lock:
            service.jobs.clear()
            for index in range(256):
                service.jobs[f"{index:032x}"] = Job(f"{index:032x}", status="succeeded")
        job = service.submit({"source": str(source)})
        wait_done(service, job)
        assert f"{0:032x}" not in service.jobs
        assert job.job_id in service.jobs
        assert len(service.jobs) == 256
    finally:
        service.close()


# --- HTTP layer ----------------------------------------------------------------


def test_is_loopback_host() -> None:
    assert _is_loopback_host("127.0.0.1:8770", 8770)
    assert _is_loopback_host("localhost:8770", 8770)
    assert not _is_loopback_host("127.0.0.1:9999", 8770)
    assert not _is_loopback_host("example.com:8770", 8770)
    assert not _is_loopback_host(None, 8770)
    assert not _is_loopback_host("", 8770)
    assert not _is_loopback_host("127.0.0.1:notaport", 8770)


def test_create_server_rejects_non_loopback_and_bad_port() -> None:
    with pytest.raises(ValueError, match="loopback"):
        create_server("0.0.0.0", 8770)
    with pytest.raises(ValueError, match="port"):
        create_server("127.0.0.1", 0)


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.bind(("127.0.0.1", 0))
        return int(probe.getsockname()[1])


def test_create_server_releases_lock_when_service_fails(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("ZP_CONTROL_DIR", str(tmp_path))

    def broken_service() -> SpeechService:
        raise RuntimeError("cannot start executor")

    monkeypatch.setattr(service_module, "SpeechService", broken_service)
    with pytest.raises(RuntimeError, match="executor"):
        create_server("127.0.0.1", free_port())
    SingletonLock(tmp_path).close()


def test_create_server_releases_lock_when_bind_fails(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("ZP_CONTROL_DIR", str(tmp_path))
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as busy:
        busy.bind(("127.0.0.1", 0))
        busy.listen(1)
        with pytest.raises(OSError):
            create_server("127.0.0.1", int(busy.getsockname()[1]))
    SingletonLock(tmp_path).close()


class LiveServer:
    def __init__(self, port: int, provider: FakeProvider) -> None:
        self.port = port
        self.provider = provider

    def request(
        self,
        method: str,
        path: str,
        body: bytes | None = None,
        headers: dict[str, str] | None = None,
    ) -> tuple[int, dict[str, Any]]:
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        try:
            connection.request(method, path, body=body, headers=headers or {})
            response = connection.getresponse()
            return response.status, json.loads(response.read() or b"{}")
        finally:
            connection.close()


@pytest.fixture
def live_server(load_fixture, tmp_path: Path, monkeypatch) -> Iterator[LiveServer]:
    monkeypatch.setenv("ZP_CONTROL_DIR", str(tmp_path / "control"))
    provider = FakeProvider(load_fixture("transcript_without_words.json"))
    monkeypatch.setattr(service_module, "detect_provider", lambda engine, *, model=None: provider)
    port = free_port()
    server = create_server("127.0.0.1", port)
    thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.05})
    thread.start()
    try:
        yield LiveServer(port, provider)
    finally:
        server.shutdown()
        server.server_close()
        server.zp_speech_service.close()
        server.zp_speech_lock.close()
        thread.join(timeout=5)


def test_http_health_capabilities_and_routing(live_server: LiveServer) -> None:
    status, body = live_server.request("GET", "/api/v1/health")
    assert status == 200
    assert body == {"status": "ok", "engine": SERVICE_ENGINE, "api_version": "v1"}

    status, body = live_server.request("GET", "/api/v1/capabilities?engine=openai-whisper")
    assert status == 200
    assert body["provider"] == "fake"

    live_server.provider.error = ProviderError("provider_not_found", "missing")
    status, body = live_server.request("GET", "/api/v1/capabilities")
    assert status == 503
    assert body["error"]["code"] == "provider_not_found"
    live_server.provider.error = None

    assert live_server.request("GET", f"/api/v1/jobs/{'a' * 32}")[0] == 404
    assert live_server.request("GET", "/nope")[0] == 404
    assert live_server.request("POST", "/nope", b"{}")[0] == 404


def test_http_rejects_non_local_host_and_origin(live_server: LiveServer) -> None:
    status, body = live_server.request("GET", "/api/v1/health", headers={"Host": "evil.test"})
    assert status == 403
    assert "Host" in body["error"]
    status, body = live_server.request(
        "GET", "/api/v1/health", headers={"Origin": "https://evil.test"}
    )
    assert status == 403
    assert "Origin" in body["error"]
    status, _ = live_server.request(
        "POST", "/api/v1/transcriptions", b"{}", headers={"Origin": "http://[::1"}
    )
    assert status == 403
    status, _ = live_server.request(
        "GET", "/api/v1/health", headers={"Origin": f"http://127.0.0.1:{live_server.port}"}
    )
    assert status == 200


def test_http_rejects_malformed_posts(live_server: LiveServer, tmp_path: Path) -> None:
    path = "/api/v1/transcriptions"
    status, body = live_server.request("POST", path, b"x" * (64 * 1024 + 1))
    assert status == 400
    assert "too large" in body["error"]
    status, body = live_server.request("POST", path, b"[1, 2]")
    assert status == 400
    assert "JSON object" in body["error"]
    status, _ = live_server.request("POST", path, b"{not json")
    assert status == 400
    status, body = live_server.request("POST", path, json.dumps({"source": "rel.wav"}).encode())
    assert status == 422
    assert body["error"]["code"] == "invalid_source"

    source = write_wav(tmp_path / "voice.wav")
    payload = json.dumps({"source": str(source), "timeout": 30}).encode()
    status, body = live_server.request("POST", path, payload)
    assert status == 202
    job_id = body["job_id"]
    assert body["status_url"] == f"/api/v1/jobs/{job_id}"
    for _ in range(100):
        status, job = live_server.request("GET", body["status_url"])
        if job["status"] in {"succeeded", "failed"}:
            break
        time.sleep(0.02)
    assert status == 200
    assert job["status"] == "succeeded"
    assert job["result"]["source"]["duration_ms"] == 500


def test_http_queue_full_returns_503(live_server: LiveServer, tmp_path: Path, monkeypatch) -> None:
    source = write_wav(tmp_path / "voice.wav")

    def full(self: SpeechService, request: dict[str, Any]) -> Job:
        raise ProviderError("provider_unavailable", "speech queue is full", retryable=True)

    monkeypatch.setattr(SpeechService, "submit", full)
    status, body = live_server.request(
        "POST", "/api/v1/transcriptions", json.dumps({"source": str(source)}).encode()
    )
    assert status == 503
    assert body["error"]["code"] == "provider_unavailable"


def test_serve_closes_everything_on_keyboard_interrupt(monkeypatch) -> None:
    events: list[str] = []

    class FakeCloser:
        def __init__(self, name: str) -> None:
            self.name = name

        def close(self) -> None:
            events.append(f"{self.name}.close")

    class FakeServer:
        zp_speech_service = FakeCloser("service")
        zp_speech_lock = FakeCloser("lock")

        def serve_forever(self, poll_interval: float) -> None:
            events.append(f"serve:{poll_interval}")
            raise KeyboardInterrupt

        def shutdown(self) -> None:
            events.append("shutdown")

        def server_close(self) -> None:
            events.append("server_close")

    monkeypatch.setattr(service_module, "create_server", lambda host, port: FakeServer())
    serve("127.0.0.1", 8770)
    assert events == ["serve:0.25", "shutdown", "server_close", "service.close", "lock.close"]
