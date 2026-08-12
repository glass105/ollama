#!/usr/bin/env python3
"""Ask an AnythingLLM workspace through its local API.

This is intended for OpenClaw agents running on the same disposable RunPod pod.
AnythingLLM owns document ingestion and retrieval; this helper only asks the
workspace API and prints the grounded answer plus source metadata.
"""

from __future__ import annotations

import argparse
import json
import os
import secrets
import sqlite3
import sys
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


ANYTHINGLLM_DIR = Path(os.environ.get("ANYTHINGLLM_DIR", "/workspace/anything-llm"))
ANYTHINGLLM_STORAGE_DIR = Path(
    os.environ.get("ANYTHINGLLM_STORAGE_DIR", str(ANYTHINGLLM_DIR / "server" / "storage"))
)
ANYTHINGLLM_URL = os.environ.get("ANYTHINGLLM_URL", "http://127.0.0.1:3010").rstrip("/")
ANYTHINGLLM_API_KEY_FILE = Path(
    os.environ.get("ANYTHINGLLM_API_KEY_FILE", "/tmp/anythingllm-api-key")
)


class AnythingLLMError(RuntimeError):
    pass


def db_path() -> Path:
    return ANYTHINGLLM_STORAGE_DIR / "anythingllm.db"


def db_connect() -> sqlite3.Connection:
    path = db_path()
    if not path.exists():
        raise AnythingLLMError(f"AnythingLLM database not found at {path}")
    con = sqlite3.connect(path)
    con.row_factory = sqlite3.Row
    return con


def wait_for_anythingllm(timeout_seconds: int) -> None:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        try:
            with urlopen(f"{ANYTHINGLLM_URL}/api/ping", timeout=5):
                return
        except Exception:
            time.sleep(2)
    raise AnythingLLMError(f"AnythingLLM did not respond at {ANYTHINGLLM_URL}")


def ensure_api_key() -> str:
    if ANYTHINGLLM_API_KEY_FILE.exists():
        token = ANYTHINGLLM_API_KEY_FILE.read_text(encoding="utf-8").strip()
        if token:
            return token

    token = "allm-" + secrets.token_urlsafe(32)
    now_ms = int(time.time() * 1000)
    with db_connect() as con:
        con.execute(
            "insert into api_keys (secret, createdBy, createdAt, lastUpdatedAt, name) "
            "values (?, ?, ?, ?, ?)",
            (token, None, now_ms, now_ms, "OpenClaw AnythingLLM query bridge"),
        )
        con.commit()

    ANYTHINGLLM_API_KEY_FILE.parent.mkdir(parents=True, exist_ok=True)
    ANYTHINGLLM_API_KEY_FILE.write_text(token + "\n", encoding="utf-8")
    try:
        ANYTHINGLLM_API_KEY_FILE.chmod(0o600)
    except Exception:
        pass
    return token


def request_json(path: str, token: str, payload: dict | None = None, method: str = "GET", timeout: int = 180) -> dict:
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    req = Request(
        f"{ANYTHINGLLM_URL}{path}",
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )
    try:
        with urlopen(req, timeout=timeout) as response:
            raw = response.read().decode("utf-8", errors="replace")
    except HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise AnythingLLMError(f"HTTP {exc.code} from {path}: {detail}") from exc
    except URLError as exc:
        raise AnythingLLMError(f"Could not reach AnythingLLM at {ANYTHINGLLM_URL}: {exc}") from exc
    return json.loads(raw) if raw else {}


def detect_api_prefix(token: str) -> str:
    for prefix in ("/api/v1", "/v1"):
        try:
            request_json(f"{prefix}/workspaces", token, timeout=30)
            return prefix
        except Exception:
            continue
    raise AnythingLLMError("Could not find a working AnythingLLM API prefix.")


def slugify(name: str) -> str:
    slug = "".join(ch.lower() if ch.isalnum() else "-" for ch in name).strip("-")
    while "--" in slug:
        slug = slug.replace("--", "-")
    return slug or "workspace"


def workspace_slug(workspace: str) -> str:
    requested_slug = slugify(workspace)
    with db_connect() as con:
        row = con.execute(
            "select slug from workspaces where lower(name) = lower(?) or lower(slug) = lower(?) order by id limit 1",
            (workspace, requested_slug),
        ).fetchone()
    return row["slug"] if row else requested_slug


def call_workspace_chat(prefix: str, token: str, slug: str, question: str, mode: str, timeout: int) -> dict:
    payloads = [
        {"message": question, "mode": mode},
        {"message": question},
    ]
    errors: list[str] = []
    for payload in payloads:
        try:
            return request_json(f"{prefix}/workspace/{slug}/chat", token, payload, method="POST", timeout=timeout)
        except AnythingLLMError as exc:
            errors.append(str(exc))
    raise AnythingLLMError("AnythingLLM workspace chat failed. Tried /workspace/{slug}/chat. " + " | ".join(errors))


def first_text(value: object) -> str:
    if isinstance(value, str):
        return value.strip()
    if isinstance(value, dict):
        for key in ("textResponse", "response", "answer", "message", "text", "content"):
            text = first_text(value.get(key))
            if text:
                return text
    if isinstance(value, list):
        for item in value:
            text = first_text(item)
            if text:
                return text
    return ""


def collect_sources(response: dict) -> list[dict]:
    sources: list[dict] = []

    def add(candidate: object) -> None:
        if isinstance(candidate, dict):
            sources.append(candidate)
        elif isinstance(candidate, list):
            for item in candidate:
                add(item)

    for key in ("sources", "sourceDocuments", "documents", "context", "sourceContext"):
        add(response.get(key))
    return sources


def source_label(source: dict) -> str:
    title = (
        source.get("title")
        or source.get("name")
        or source.get("filename")
        or source.get("docpath")
        or source.get("location")
        or source.get("source")
        or "source"
    )
    score = source.get("score") or source.get("similarity") or source.get("distance")
    if score is None:
        return str(title)
    return f"{title} ({score})"


def print_markdown(workspace: str, question: str, response: dict) -> None:
    answer = first_text(response) or "(AnythingLLM returned no answer text.)"
    print("# AnythingLLM RAG Answer")
    print()
    print(f"Workspace: {workspace}")
    print(f"Question: {question}")
    print()
    print(answer)

    sources = collect_sources(response)
    if sources:
        print()
        print("## Sources")
        seen: set[str] = set()
        for source in sources[:10]:
            label = source_label(source)
            if label in seen:
                continue
            seen.add(label)
            print(f"- {label}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Ask an AnythingLLM workspace through its local API.")
    parser.add_argument("workspace", help="AnythingLLM workspace name or slug, for example Nokia")
    parser.add_argument("question", nargs="+", help="Question to ask the workspace")
    parser.add_argument("--mode", default="query", choices=("query", "chat"), help="AnythingLLM chat mode")
    parser.add_argument("--timeout", type=int, default=300, help="Request timeout in seconds")
    parser.add_argument("--json", action="store_true", help="Print raw JSON response")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    question = " ".join(args.question).strip()
    if not question:
        raise AnythingLLMError("Question cannot be empty.")

    wait_for_anythingllm(args.timeout)
    token = ensure_api_key()
    prefix = detect_api_prefix(token)
    slug = workspace_slug(args.workspace)
    response = call_workspace_chat(prefix, token, slug, question, args.mode, args.timeout)
    if args.json:
        print(json.dumps(response, indent=2, sort_keys=True))
    else:
        print_markdown(args.workspace, question, response)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AnythingLLMError as exc:
        print(f"AnythingLLM query failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
