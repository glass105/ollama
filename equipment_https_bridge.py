#!/usr/bin/env python3
"""Authenticated HTTPS-proxy backend for pull-based equipment jobs.

RunPod terminates HTTPS at its proxy. This service listens on pod HTTP and never
connects to the Windows worker; the worker polls it over outbound HTTPS.
"""

from __future__ import annotations

import argparse
import hmac
import json
import os
import re
import threading
import time
import uuid
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


VERSION = 1
MAX_BODY_BYTES = 1_048_576
MAX_TEXT_CHARS = 524_288
NAME_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
JOB_RE = re.compile(r"^/api/jobs/([0-9a-f-]{36})(?:/(result|cancel))?$")


def now_epoch() -> int:
    return int(time.time())


class JobStore:
    def __init__(self, state_file: Path) -> None:
        self.state_file = state_file
        self.lock = threading.RLock()
        self.jobs: dict[str, dict] = {}
        self._load()

    def _load(self) -> None:
        if not self.state_file.is_file():
            return
        try:
            payload = json.loads(self.state_file.read_text(encoding="utf-8"))
            self.jobs = payload.get("jobs", {})
        except (OSError, json.JSONDecodeError):
            self.jobs = {}

    def _save(self) -> None:
        self.state_file.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.state_file.with_suffix(".tmp")
        temporary.write_text(
            json.dumps({"schemaVersion": VERSION, "jobs": self.jobs}, indent=2),
            encoding="utf-8",
        )
        temporary.chmod(0o600)
        os.replace(temporary, self.state_file)

    def _expire(self) -> None:
        current = now_epoch()
        changed = False
        for job in self.jobs.values():
            if job["status"] in {"pending", "claimed"} and job["expiresAt"] <= current:
                job["status"] = "expired"
                job["updatedAt"] = current
                changed = True
        if changed:
            self._save()

    def create(self, device: str, operation: str, ttl_seconds: int) -> dict:
        with self.lock:
            created = now_epoch()
            job_id = str(uuid.uuid4())
            job = {
                "id": job_id,
                "device": device,
                "operation": operation,
                "status": "pending",
                "workerId": None,
                "createdAt": created,
                "updatedAt": created,
                "expiresAt": created + ttl_seconds,
                "result": None,
            }
            self.jobs[job_id] = job
            self._save()
            return dict(job)

    def get(self, job_id: str) -> dict | None:
        with self.lock:
            self._expire()
            job = self.jobs.get(job_id)
            return dict(job) if job else None

    def claim_next(self, worker_id: str) -> dict | None:
        with self.lock:
            self._expire()
            pending = sorted(
                (job for job in self.jobs.values() if job["status"] == "pending"),
                key=lambda item: item["createdAt"],
            )
            if not pending:
                return None
            job = pending[0]
            job["status"] = "claimed"
            job["workerId"] = worker_id
            job["updatedAt"] = now_epoch()
            self._save()
            return dict(job)

    def result(self, job_id: str, worker_id: str, payload: dict) -> dict | None:
        with self.lock:
            self._expire()
            job = self.jobs.get(job_id)
            if not job:
                return None
            if job["status"] != "claimed" or job["workerId"] != worker_id:
                raise PermissionError("Job is not claimed by this worker.")
            status = payload.get("status")
            if status not in {"completed", "failed", "rejected"}:
                raise ValueError("Invalid result status.")
            job["status"] = status
            job["updatedAt"] = now_epoch()
            job["result"] = {
                "exitCode": payload.get("exitCode"),
                "stdout": str(payload.get("stdout", ""))[:MAX_TEXT_CHARS],
                "stderr": str(payload.get("stderr", ""))[:MAX_TEXT_CHARS],
                "durationMs": payload.get("durationMs"),
                "message": str(payload.get("message", ""))[:4096],
            }
            self._save()
            return dict(job)

    def cancel(self, job_id: str) -> dict | None:
        with self.lock:
            self._expire()
            job = self.jobs.get(job_id)
            if not job:
                return None
            if job["status"] != "pending":
                raise ValueError("Only pending jobs can be cancelled.")
            job["status"] = "cancelled"
            job["updatedAt"] = now_epoch()
            self._save()
            return dict(job)


class BridgeHandler(BaseHTTPRequestHandler):
    server_version = "EquipmentBridge/1"

    @property
    def bridge(self) -> "BridgeServer":
        return self.server  # type: ignore[return-value]

    def log_message(self, format_string: str, *args: object) -> None:
        print(f"[equipment-bridge] {self.address_string()} {format_string % args}")

    def _json(self, status: HTTPStatus, payload: dict | None = None) -> None:
        body = b"" if payload is None else json.dumps(payload).encode("utf-8")
        self.send_response(status)
        if body:
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _authorized(self, role: str) -> bool:
        expected = self.bridge.client_token if role == "client" else self.bridge.worker_token
        supplied = self.headers.get("Authorization", "")
        prefix = "Bearer "
        valid = supplied.startswith(prefix) and hmac.compare_digest(
            supplied[len(prefix) :].encode(), expected.encode()
        )
        if not valid:
            self._json(HTTPStatus.UNAUTHORIZED, {"error": "unauthorized"})
        return valid

    def _body(self) -> dict:
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError as exc:
            raise ValueError("Invalid Content-Length.") from exc
        if length < 1 or length > MAX_BODY_BYTES:
            raise ValueError("Invalid request size.")
        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise ValueError("Invalid JSON body.") from exc
        if not isinstance(payload, dict):
            raise ValueError("JSON body must be an object.")
        return payload

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self._json(HTTPStatus.OK, {"status": "ok", "service": "equipment-command-bridge", "version": VERSION})
            return
        if parsed.path == "/api/jobs/next":
            if not self._authorized("worker"):
                return
            worker_id = parse_qs(parsed.query).get("workerId", [""])[0]
            if not NAME_RE.fullmatch(worker_id):
                self._json(HTTPStatus.BAD_REQUEST, {"error": "invalid workerId"})
                return
            job = self.bridge.store.claim_next(worker_id)
            self._json(HTTPStatus.OK, {"job": job})
            return
        match = JOB_RE.fullmatch(parsed.path)
        if match and not match.group(2):
            if not self._authorized("client"):
                return
            job = self.bridge.store.get(match.group(1))
            if not job:
                self._json(HTTPStatus.NOT_FOUND, {"error": "job not found"})
                return
            self._json(HTTPStatus.OK, {"job": job})
            return
        self._json(HTTPStatus.NOT_FOUND, {"error": "not found"})

    def do_POST(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        try:
            if parsed.path == "/api/jobs":
                if not self._authorized("client"):
                    return
                payload = self._body()
                device = str(payload.get("device", ""))
                operation = str(payload.get("operation", ""))
                if not NAME_RE.fullmatch(device) or not NAME_RE.fullmatch(operation):
                    self._json(HTTPStatus.BAD_REQUEST, {"error": "invalid device or operation"})
                    return
                ttl_seconds = int(payload.get("ttlSeconds", 300))
                if not 30 <= ttl_seconds <= 3600:
                    self._json(HTTPStatus.BAD_REQUEST, {"error": "ttlSeconds must be 30..3600"})
                    return
                job = self.bridge.store.create(device, operation, ttl_seconds)
                self._json(HTTPStatus.CREATED, {"job": job})
                return

            match = JOB_RE.fullmatch(parsed.path)
            if match and match.group(2) == "result":
                if not self._authorized("worker"):
                    return
                payload = self._body()
                worker_id = str(payload.get("workerId", ""))
                if not NAME_RE.fullmatch(worker_id):
                    self._json(HTTPStatus.BAD_REQUEST, {"error": "invalid workerId"})
                    return
                try:
                    job = self.bridge.store.result(match.group(1), worker_id, payload)
                except PermissionError as exc:
                    self._json(HTTPStatus.CONFLICT, {"error": str(exc)})
                    return
                if not job:
                    self._json(HTTPStatus.NOT_FOUND, {"error": "job not found"})
                    return
                self._json(HTTPStatus.OK, {"job": job})
                return

            if match and match.group(2) == "cancel":
                if not self._authorized("client"):
                    return
                try:
                    job = self.bridge.store.cancel(match.group(1))
                except ValueError as exc:
                    self._json(HTTPStatus.CONFLICT, {"error": str(exc)})
                    return
                if not job:
                    self._json(HTTPStatus.NOT_FOUND, {"error": "job not found"})
                    return
                self._json(HTTPStatus.OK, {"job": job})
                return
        except (ValueError, TypeError) as exc:
            self._json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return
        self._json(HTTPStatus.NOT_FOUND, {"error": "not found"})


class BridgeServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address: tuple[str, int], store: JobStore, client_token: str, worker_token: str) -> None:
        super().__init__(address, BridgeHandler)
        self.store = store
        self.client_token = client_token
        self.worker_token = worker_token


def read_token(path: Path) -> str:
    token = path.read_text(encoding="utf-8").strip()
    if len(token) < 32:
        raise SystemExit(f"Token is missing or too short: {path}")
    return token


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default=os.environ.get("EQUIPMENT_BRIDGE_HOST", "0.0.0.0"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("EQUIPMENT_BRIDGE_PORT", "19124")))
    parser.add_argument("--state-file", type=Path, default=Path("/tmp/equipment-bridge/jobs.json"))
    parser.add_argument("--client-token-file", type=Path, default=Path("/tmp/equipment-bridge/client-token"))
    parser.add_argument("--worker-token-file", type=Path, default=Path("/tmp/equipment-bridge/worker-token"))
    args = parser.parse_args()

    server = BridgeServer(
        (args.host, args.port),
        JobStore(args.state_file),
        read_token(args.client_token_file),
        read_token(args.worker_token_file),
    )
    print(f"[equipment-bridge] listening on {args.host}:{args.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
