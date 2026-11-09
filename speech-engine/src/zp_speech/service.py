"""Loopback-only, single-process HTTP service for ZP Speech v1."""

from __future__ import annotations

import contextlib
import json
import logging
import os
import re
import secrets
import threading
import wave
from concurrent.futures import Future, ThreadPoolExecutor
from dataclasses import dataclass, field
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, cast
from urllib.parse import parse_qs, urlsplit

from zp_speech.providers import ENGINE_CHOICES, ProviderError, detect_provider, zp_data_root
from zp_speech.validation import validate_document

SERVICE_ENGINE = "zp-speech-service-v1"
MAX_REQUEST_BYTES = 64 * 1024
MAX_OUTSTANDING_JOBS = 8
JOB_ID_RE = re.compile(r"^[0-9a-f]{32}$")
LOG = logging.getLogger("zp_speech.service")
DEFAULT_CONTROL_DIR = zp_data_root() / "control"


def _try_lock(fd: int) -> None:
    if os.name == "nt":  # pragma: no cover
        import msvcrt

        try:
            msvcrt.locking(fd, msvcrt.LK_NBLCK, 1)
        except OSError as error:
            raise BlockingIOError from error
    else:
        import fcntl

        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)


def _unlock(fd: int) -> None:
    if os.name == "nt":  # pragma: no cover
        import msvcrt

        with contextlib.suppress(OSError):
            msvcrt.locking(fd, msvcrt.LK_UNLCK, 1)
    else:
        import fcntl

        fcntl.flock(fd, fcntl.LOCK_UN)


class SingletonLock:
    """Hold an OS lock so alternate ports cannot start a second provider process."""

    def __init__(self, control_dir: Path | None = None) -> None:
        directory = control_dir or Path(os.environ.get("ZP_CONTROL_DIR", DEFAULT_CONTROL_DIR))
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.handle = (directory / "speech-service.lock").open("a+", encoding="utf-8")
        try:
            _try_lock(self.handle.fileno())
        except BlockingIOError as error:
            self.handle.close()
            raise RuntimeError("un'altra istanza di ZP Speech Service è già attiva") from error
        self.handle.seek(0)
        self.handle.truncate()
        self.handle.write(f"{os.getpid()}\n")
        self.handle.flush()

    def close(self) -> None:
        _unlock(self.handle.fileno())
        self.handle.close()


@dataclass
class Job:
    job_id: str
    status: str = "queued"
    result: dict[str, Any] | None = None
    error: dict[str, Any] | None = None
    future: Future[dict[str, Any]] | None = field(default=None, repr=False)

    def as_document(self) -> dict[str, Any]:
        """Return a detached view; callers must hold the owning service lock."""
        return {
            "job_id": self.job_id,
            "status": self.status,
            "result": self.result,
            "error": self.error,
        }


class SpeechService:
    """Owns provider execution and serializes transcription work within this process."""

    def __init__(self, provider: Any | None = None, *, engine: str | None = None) -> None:
        self.provider = provider
        self.default_engine = engine or os.environ.get("ZP_SPEECH_ENGINE", "auto")
        self.executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="zp-speech")
        self.lock = threading.Lock()
        self.jobs: dict[str, Job] = {}

    def _resolve_provider(self, engine: str | None = None, model: str | None = None) -> Any:
        if self.provider is not None:
            return self.provider
        return detect_provider(engine or self.default_engine, model=model)

    def submit(self, request: dict[str, Any]) -> Job:
        source_value = request.get("source")
        if not isinstance(source_value, str) or not source_value:
            raise ProviderError("invalid_source", "source must be an absolute local file path")
        source = Path(source_value).expanduser()
        if not source.is_absolute():
            raise ProviderError("invalid_source", "source must be an absolute local file path")
        try:
            source = source.resolve(strict=True)
        except OSError as error:
            raise ProviderError("invalid_source", "source file does not exist") from error
        if not source.is_file():
            raise ProviderError("invalid_source", "source must be a file")

        engine = request.get("engine", self.default_engine)
        language = request.get("language", "it")
        model = request.get("model")
        speakers = request.get("speakers", False)
        timeout = request.get("timeout", 3600)
        if not isinstance(engine, str) or engine not in ENGINE_CHOICES:
            raise ProviderError(
                "unsupported_capability", f"engine must be one of {', '.join(ENGINE_CHOICES)}"
            )
        if not isinstance(language, str) or not language or len(language) > 32:
            raise ProviderError("invalid_source", "language must be a short non-empty string")
        if model is not None and (not isinstance(model, str) or len(model) > 256):
            raise ProviderError("unsupported_model", "model must be a short string")
        if not isinstance(speakers, bool):
            raise ProviderError("unsupported_capability", "speakers must be a boolean")
        if (
            isinstance(timeout, bool)
            or not isinstance(timeout, (int, float))
            or not 1 <= timeout <= 21600
        ):
            raise ProviderError("timeout", "timeout must be between 1 and 21600 seconds")

        with self.lock:
            active = sum(job.status in {"queued", "running"} for job in self.jobs.values())
            if active >= MAX_OUTSTANDING_JOBS:
                raise ProviderError("provider_unavailable", "speech queue is full", retryable=True)
            if len(self.jobs) >= 256:
                for old_id, old_job in self.jobs.items():
                    if old_job.status not in {"queued", "running"}:
                        del self.jobs[old_id]
                        break
            job = Job(secrets.token_hex(16))
            self.jobs[job.job_id] = job
            job.future = self.executor.submit(
                self._run_job, job, source, engine, language, model, speakers, float(timeout)
            )
            return job

    def _run_job(
        self,
        job: Job,
        source: Path,
        engine: str,
        language: str,
        model: str | None,
        speakers: bool,
        timeout: float,
    ) -> dict[str, Any]:
        with self.lock:
            job.status = "running"
        try:
            provider = self._resolve_provider(engine, model)
            result = provider.transcribe(
                source,
                language=language,
                model=model,
                speakers=speakers,
                timeout=timeout,
            )
            try:
                with wave.open(str(source), "rb") as wav:
                    rate = wav.getframerate()
                    if rate > 0:
                        result["source"]["duration_ms"] = round(wav.getnframes() * 1000 / rate)
                        validate_document(result)
            except (wave.Error, OSError, KeyError, TypeError):
                pass
        except ProviderError as error:
            with self.lock:
                job.error = error.as_document()
                job.status = "failed"
        except Exception:
            LOG.exception("Unexpected provider failure for job %s", job.job_id)
            error = ProviderError("transcription_failed", "unexpected provider failure")
            with self.lock:
                job.error = error.as_document()
                job.status = "failed"
        else:
            with self.lock:
                job.result = result
                job.status = "succeeded"
        return job.result or job.error or {}

    def get_document(self, job_id: str) -> dict[str, Any] | None:
        with self.lock:
            job = self.jobs.get(job_id)
            return job.as_document() if job is not None else None

    def job_document(self, job: Job) -> dict[str, Any]:
        with self.lock:
            return job.as_document()

    def capabilities(self, *, engine: str | None = None) -> dict[str, Any]:
        provider = self._resolve_provider(engine)
        return provider.capabilities()

    def close(self) -> None:
        self.executor.shutdown(wait=False, cancel_futures=True)


def _is_loopback_host(value: str | None, port: int) -> bool:
    if not value:
        return False
    try:
        parsed = urlsplit(f"http://{value}")
        return parsed.hostname in {"127.0.0.1", "localhost", "::1"} and parsed.port == port
    except ValueError:
        return False


class SpeechHTTPServer(ThreadingHTTPServer):
    """Threading server that owns the speech service and the singleton lock."""

    zp_speech_service: SpeechService
    zp_speech_lock: SingletonLock


def create_server(host: str = "127.0.0.1", port: int = 8770) -> SpeechHTTPServer:
    if host not in {"127.0.0.1", "localhost", "::1"}:
        raise ValueError("ZP Speech Service may bind only to loopback")
    if not 1 <= port <= 65535:
        raise ValueError("port must be between 1 and 65535")
    singleton_lock = SingletonLock()
    try:
        service = SpeechService()
    except Exception:
        singleton_lock.close()
        raise

    class Handler(BaseHTTPRequestHandler):
        server_version = SERVICE_ENGINE
        protocol_version = "HTTP/1.1"

        def log_message(self, format: str, *args: object) -> None:
            LOG.info("%s - %s", self.address_string(), format % args)

        def _json(self, payload: dict[str, Any], status: int = 200) -> None:
            body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def _local_request(self) -> bool:
            if not _is_loopback_host(self.headers.get("Host"), port):
                self._json({"error": "non-local Host header rejected"}, 403)
                return False
            origin = self.headers.get("Origin")
            if origin:
                try:
                    parsed = urlsplit(origin)
                    if parsed.scheme != "http" or parsed.hostname not in {
                        "127.0.0.1",
                        "localhost",
                        "::1",
                    }:
                        raise ValueError
                except ValueError:
                    self._json({"error": "non-local Origin rejected"}, 403)
                    return False
            return True

        def do_GET(self) -> None:  # noqa: N802 - stdlib handler API
            if not self._local_request():
                return
            parsed = urlsplit(self.path)
            if parsed.path == "/api/v1/health":
                self._json({"status": "ok", "engine": SERVICE_ENGINE, "api_version": "v1"})
                return
            if parsed.path == "/api/v1/capabilities":
                query = parse_qs(parsed.query)
                req_engine = query.get("engine", [None])[0]
                try:
                    self._json(service.capabilities(engine=req_engine))
                except ProviderError as error:
                    self._json(error.as_document(), 503)
                return
            match = re.fullmatch(r"/api/v1/jobs/([0-9a-f]{32})", parsed.path)
            if match:
                document = service.get_document(match.group(1))
                if document is None:
                    self._json({"error": "job not found"}, 404)
                else:
                    self._json(document)
                return
            self._json({"error": "not found"}, 404)

        def do_POST(self) -> None:  # noqa: N802 - stdlib handler API
            if not self._local_request():
                return
            if self.path != "/api/v1/transcriptions":
                self._json({"error": "not found"}, 404)
                return
            try:
                length = int(self.headers.get("Content-Length", "-1"))
                if length < 0 or length > MAX_REQUEST_BYTES:
                    raise ValueError("Content-Length missing or request too large")
                request: object = json.loads(self.rfile.read(length))
                if not isinstance(request, dict):
                    raise ValueError("request must be a JSON object")
                job = service.submit(cast(dict[str, Any], request))
            except ProviderError as error:
                self._json(
                    error.as_document(), 422 if error.code != "provider_unavailable" else 503
                )
                return
            except (ValueError, UnicodeDecodeError, json.JSONDecodeError) as error:
                self._json({"error": str(error)}, 400)
                return
            document = service.job_document(job)
            self._json(
                {
                    "job_id": document["job_id"],
                    "status": document["status"],
                    "status_url": f"/api/v1/jobs/{document['job_id']}",
                },
                202,
            )

    try:
        server = SpeechHTTPServer((host, port), Handler)
    except Exception:
        service.close()
        singleton_lock.close()
        raise
    server.daemon_threads = True
    server.zp_speech_service = service
    server.zp_speech_lock = singleton_lock
    return server


def serve(host: str = "127.0.0.1", port: int = 8770) -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    server = create_server(host, port)
    LOG.info("ZP Speech Service listening on http://%s:%s", host, port)
    try:
        server.serve_forever(poll_interval=0.25)
    except KeyboardInterrupt:
        pass
    finally:
        server.shutdown()
        server.server_close()
        server.zp_speech_service.close()
        server.zp_speech_lock.close()
