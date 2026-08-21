#!/usr/bin/env python3
"""Ollama-compatible proxy that injects AnythingLLM RAG context for OpenClaw."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


LISTEN_HOST = os.environ.get("OPENCLAW_RAG_PROXY_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("OPENCLAW_RAG_PROXY_PORT", "11437"))
OLLAMA_UPSTREAM = os.environ.get("OPENCLAW_RAG_PROXY_UPSTREAM", "http://127.0.0.1:11434").rstrip("/")
MEMORY_DIR = Path(os.environ.get("MEMORY_DIR", "/workspace/ollama-memory"))
QUERY_HELPER = os.environ.get("ANYTHINGLLM_QUERY_HELPER", str(MEMORY_DIR / "anythingllm_query.sh"))
DEFAULT_WORKSPACE = os.environ.get("ANYTHINGLLM_DEFAULT_WORKSPACE", "Nokia")
QUERY_TIMEOUT_SECONDS = int(os.environ.get("OPENCLAW_RAG_QUERY_TIMEOUT_SECONDS", "90"))
MAX_CONTEXT_CHARS = int(os.environ.get("OPENCLAW_RAG_MAX_CONTEXT_CHARS", "4000"))
MAX_QUESTION_CHARS = int(os.environ.get("OPENCLAW_RAG_MAX_QUESTION_CHARS", "2000"))

TRIGGER_TERMS = tuple(
    term.strip().lower()
    for term in os.environ.get(
        "OPENCLAW_RAG_TRIGGER_TERMS",
        "cmm,cmg,nokia,pdf,xlsx,guide,reference,command,commands,interface,interfaces,alarm,alarms,intfsummary",
    ).split(",")
    if term.strip()
)


def log(message: str) -> None:
    print(f"[openclaw-rag-proxy] {message}", flush=True)


def should_inject(question: str) -> bool:
    lower = question.lower()
    return any(term in lower for term in TRIGGER_TERMS)


def last_user_message(messages: list[dict]) -> str:
    for message in reversed(messages):
        if message.get("role") == "user":
            content = message.get("content", "")
            return content if isinstance(content, str) else json.dumps(content)
    return ""


def anythingllm_context(question: str) -> str:
    question = question[:MAX_QUESTION_CHARS]
    try:
        result = subprocess.run(
            [QUERY_HELPER, DEFAULT_WORKSPACE, question],
            check=False,
            capture_output=True,
            text=True,
            timeout=QUERY_TIMEOUT_SECONDS,
        )
    except Exception as exc:
        return f"AnythingLLM helper failed before returning context: {exc}"

    output = (result.stdout or "").strip()
    error = (result.stderr or "").strip()
    if result.returncode != 0:
        detail = error or output or f"exit status {result.returncode}"
        return f"AnythingLLM helper failed: {detail}"
    if len(output) > MAX_CONTEXT_CHARS:
        return output[:MAX_CONTEXT_CHARS].rstrip() + "\n\n[AnythingLLM RAG output truncated by proxy.]"
    return output


def inject_chat(payload: dict) -> dict:
    messages = payload.get("messages")
    if not isinstance(messages, list):
        return payload
    question = last_user_message(messages)
    if not question or not should_inject(question):
        return payload

    context = anythingllm_context(question)
    instruction = (
        "Use this concise AnythingLLM RAG result as source-of-truth for relevant "
        "CMM/CMG/Nokia/reference details. Do not invent commands. If it reports a helper "
        "failure or insufficient evidence, say so instead of guessing.\n\n"
        f"{context}"
    )
    payload = dict(payload)
    payload["messages"] = [{"role": "system", "content": instruction}] + messages
    log(f"injected AnythingLLM context for chat question: {question[:120]!r}")
    return payload


def inject_generate(payload: dict) -> dict:
    prompt = payload.get("prompt")
    if not isinstance(prompt, str) or not should_inject(prompt):
        return payload
    context = anythingllm_context(prompt)
    payload = dict(payload)
    payload["prompt"] = (
        "Use this concise AnythingLLM RAG result as source-of-truth when relevant. "
        "Do not invent commands.\n\n"
        f"{context}\n\nUser prompt:\n{prompt}"
    )
    log(f"injected AnythingLLM context for generate prompt: {prompt[:120]!r}")
    return payload


def maybe_inject(path: str, payload: dict) -> dict:
    if path in ("/api/chat", "/v1/chat/completions"):
        return inject_chat(payload)
    if path == "/api/generate":
        return inject_generate(payload)
    return payload


class ProxyHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self) -> None:
        self.forward()

    def do_POST(self) -> None:
        self.forward()

    def do_HEAD(self) -> None:
        self.forward()

    def forward(self) -> None:
        length = int(self.headers.get("Content-Length", "0") or "0")
        body = self.rfile.read(length) if length else b""
        outbound_body = body

        if body and "application/json" in self.headers.get("Content-Type", ""):
            try:
                payload = json.loads(body.decode("utf-8"))
                outbound_body = json.dumps(maybe_inject(self.path.split("?", 1)[0], payload)).encode("utf-8")
            except Exception as exc:
                log(f"payload injection skipped: {exc}")
                outbound_body = body

        headers = {
            key: value
            for key, value in self.headers.items()
            if key.lower() not in {"host", "content-length", "connection", "accept-encoding"}
        }
        if outbound_body:
            headers["Content-Length"] = str(len(outbound_body))

        req = Request(
            f"{OLLAMA_UPSTREAM}{self.path}",
            data=outbound_body if self.command not in {"GET", "HEAD"} else None,
            method=self.command,
            headers=headers,
        )
        try:
            with urlopen(req, timeout=600) as response:
                response_body = response.read()
                self.send_response(response.status)
                for key, value in response.headers.items():
                    if key.lower() not in {"transfer-encoding", "connection", "content-length"}:
                        self.send_header(key, value)
                self.send_header("Content-Length", str(len(response_body)))
                self.end_headers()
                if self.command != "HEAD":
                    self.wfile.write(response_body)
        except HTTPError as exc:
            response_body = exc.read()
            self.send_response(exc.code)
            self.send_header("Content-Type", exc.headers.get("Content-Type", "text/plain"))
            self.send_header("Content-Length", str(len(response_body)))
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(response_body)
        except URLError as exc:
            response_body = f"Upstream Ollama error: {exc}".encode("utf-8")
            self.send_response(502)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(response_body)))
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(response_body)

    def log_message(self, fmt: str, *args: object) -> None:
        log(fmt % args)


def main() -> int:
    server = ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), ProxyHandler)
    log(f"listening on http://{LISTEN_HOST}:{LISTEN_PORT}, upstream={OLLAMA_UPSTREAM}")
    server.serve_forever()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(0)
    except Exception as exc:
        print(f"openclaw rag proxy failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
