#!/usr/bin/env python3
import json
import mimetypes
import os
import secrets
import sqlite3
import time
import uuid
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


MEMORY_DIR = Path(os.environ.get("MEMORY_DIR", "/workspace/ollama-memory"))
PDF_DIR = Path(os.environ.get("ANYTHINGLLM_PDF_DIR", str(MEMORY_DIR / "PDFS")))
ANYTHINGLLM_DIR = Path(os.environ.get("ANYTHINGLLM_DIR", "/workspace/anything-llm"))
ANYTHINGLLM_STORAGE_DIR = Path(
    os.environ.get("ANYTHINGLLM_STORAGE_DIR", str(ANYTHINGLLM_DIR / "server" / "storage"))
)
ANYTHINGLLM_URL = os.environ.get("ANYTHINGLLM_URL", "http://127.0.0.1:3010").rstrip("/")
ANYTHINGLLM_API_KEY_FILE = Path(
    os.environ.get("ANYTHINGLLM_API_KEY_FILE", "/tmp/anythingllm-api-key")
)
WORKSPACE_PROMPT = os.environ.get(
    "ANYTHINGLLM_WORKSPACE_PROMPT",
    "Answer using the workspace documents when relevant. If the documents do not contain the answer, say so.",
)
LOG_PREFIX = "[anythingllm-pdf-index]"


def log(message: str) -> None:
    print(f"{LOG_PREFIX} {message}", flush=True)


def db_path() -> Path:
    return ANYTHINGLLM_STORAGE_DIR / "anythingllm.db"


def db_connect() -> sqlite3.Connection:
    con = sqlite3.connect(db_path())
    con.row_factory = sqlite3.Row
    return con


def wait_for_anythingllm(timeout_seconds: int = 180) -> None:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        try:
            with urlopen(f"{ANYTHINGLLM_URL}/api/ping", timeout=5):
                return
        except Exception:
            time.sleep(2)
    raise RuntimeError(f"AnythingLLM did not respond at {ANYTHINGLLM_URL}")


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
            (token, None, now_ms, now_ms, "Git PDF auto-index"),
        )
        con.commit()

    ANYTHINGLLM_API_KEY_FILE.parent.mkdir(parents=True, exist_ok=True)
    ANYTHINGLLM_API_KEY_FILE.write_text(token + "\n", encoding="utf-8")
    try:
        ANYTHINGLLM_API_KEY_FILE.chmod(0o600)
    except Exception:
        pass
    return token


def request_json(path: str, token: str, payload: dict | None = None, method: str = "GET") -> dict:
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    req = Request(
        f"{ANYTHINGLLM_URL}{path}",
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    with urlopen(req, timeout=120) as response:
        raw = response.read().decode("utf-8")
    return json.loads(raw) if raw else {}


def detect_api_prefix(token: str) -> str:
    for prefix in ("/api/v1", "/v1"):
        try:
            request_json(f"{prefix}/workspaces", token)
            return prefix
        except Exception:
            continue
    raise RuntimeError("Could not find a working AnythingLLM API prefix.")


def slugify(name: str) -> str:
    slug = "".join(ch.lower() if ch.isalnum() else "-" for ch in name).strip("-")
    while "--" in slug:
        slug = slug.replace("--", "-")
    return slug or "workspace"


def workspace_by_slug(slug: str) -> sqlite3.Row | None:
    with db_connect() as con:
        return con.execute("select * from workspaces where slug = ? limit 1", (slug,)).fetchone()


def workspace_by_name(name: str) -> sqlite3.Row | None:
    with db_connect() as con:
        return con.execute("select * from workspaces where lower(name) = lower(?) order by id limit 1", (name,)).fetchone()


def configure_workspace(workspace_id: int, workspace_name: str) -> None:
    now_ms = int(time.time() * 1000)
    model = os.environ.get("OLLAMA_MODEL", "qwen3-coder:30b")
    with db_connect() as con:
        con.execute(
            "update workspaces set name = ?, chatProvider = ?, chatModel = ?, "
            "agentProvider = ?, agentModel = ?, openAiPrompt = ?, lastUpdatedAt = ? "
            "where id = ?",
            (
                workspace_name,
                "ollama",
                model,
                "ollama",
                model,
                WORKSPACE_PROMPT,
                now_ms,
                workspace_id,
            ),
        )
        con.commit()


def ensure_workspace(prefix: str, token: str, workspace_name: str) -> str:
    slug = slugify(workspace_name)
    row = workspace_by_name(workspace_name) or workspace_by_slug(slug)
    if row:
        configure_workspace(row["id"], workspace_name)
        return row["slug"]

    log(f"creating AnythingLLM workspace '{workspace_name}'")
    response = request_json(
        f"{prefix}/workspace/new",
        token,
        {
            "name": workspace_name,
            "chatProvider": "ollama",
            "chatModel": os.environ.get("OLLAMA_MODEL", "qwen3-coder:30b"),
            "agentProvider": "ollama",
            "agentModel": os.environ.get("OLLAMA_MODEL", "qwen3-coder:30b"),
            "openAiPrompt": WORKSPACE_PROMPT,
            "chatMode": "automatic",
            "topN": 4,
        },
        method="POST",
    )
    workspace = response.get("workspace") or {}
    actual_slug = workspace.get("slug") or slug
    row = workspace_by_slug(actual_slug)
    if row:
        configure_workspace(row["id"], workspace_name)
    return actual_slug


def workspace_doc_titles(slug: str) -> set[str]:
    with db_connect() as con:
        workspace = con.execute("select id from workspaces where slug = ? limit 1", (slug,)).fetchone()
        if not workspace:
            return set()
        rows = con.execute(
            "select metadata from workspace_documents where workspaceId = ?",
            (workspace["id"],),
        ).fetchall()
    titles: set[str] = set()
    for row in rows:
        try:
            metadata = json.loads(row["metadata"] or "{}")
        except Exception:
            metadata = {}
        title = metadata.get("title")
        if title:
            titles.add(title)
    return titles


def multipart_upload(path: str, token: str, pdf: Path, workspace_slug: str) -> dict:
    boundary = "----anythingllm-git-pdf-" + uuid.uuid4().hex
    content_type = mimetypes.guess_type(pdf.name)[0] or "application/octet-stream"
    metadata = {
        "title": pdf.name,
        "description": f"Git-backed PDF from {pdf.relative_to(PDF_DIR)}",
        "docSource": "GitHub PDFS directory",
    }
    parts: list[bytes] = []

    def add_field(name: str, value: str) -> None:
        parts.append(f"--{boundary}\r\n".encode())
        parts.append(f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode())
        parts.append(value.encode())
        parts.append(b"\r\n")

    add_field("addToWorkspaces", workspace_slug)
    add_field("metadata", json.dumps(metadata))
    parts.append(f"--{boundary}\r\n".encode())
    parts.append(
        (
            f'Content-Disposition: form-data; name="file"; filename="{pdf.name}"\r\n'
            f"Content-Type: {content_type}\r\n\r\n"
        ).encode()
    )
    parts.append(pdf.read_bytes())
    parts.append(b"\r\n")
    parts.append(f"--{boundary}--\r\n".encode())
    body = b"".join(parts)

    req = Request(
        f"{ANYTHINGLLM_URL}{path}",
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            "Content-Length": str(len(body)),
        },
    )
    try:
        with urlopen(req, timeout=14400) as response:
            raw = response.read().decode("utf-8")
    except HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"AnythingLLM upload failed: HTTP {exc.code}: {detail}") from exc
    except URLError as exc:
        raise RuntimeError(f"AnythingLLM upload failed: {exc}") from exc
    return json.loads(raw) if raw else {}


def pdf_collection_name(path: Path) -> str | None:
    relative = path.relative_to(PDF_DIR)
    if len(relative.parts) < 2:
        return None
    return relative.parts[0]


def main() -> int:
    wait_for_anythingllm()
    if not PDF_DIR.is_dir():
        log(f"PDF directory not found: {PDF_DIR}; skipping")
        return 0

    pdfs = sorted(p for p in PDF_DIR.rglob("*.pdf") if p.is_file())
    if not pdfs:
        log(f"no PDFs found in {PDF_DIR}; skipping")
        return 0

    token = ensure_api_key()
    prefix = detect_api_prefix(token)
    log(f"using AnythingLLM API prefix {prefix}")

    workspace_slugs: dict[str, str] = {}
    for pdf in pdfs:
        collection_name = pdf_collection_name(pdf)
        if not collection_name:
            log(f"skipping top-level PDF without collection directory: {pdf.name}")
            continue

        if collection_name not in workspace_slugs:
            workspace_slugs[collection_name] = ensure_workspace(prefix, token, collection_name)
        slug = workspace_slugs[collection_name]
        existing_titles = workspace_doc_titles(slug)
        if pdf.name in existing_titles:
            log(f"already indexed in workspace '{collection_name}': {pdf.name}")
            continue

        log(f"uploading and embedding {pdf.name} into AnythingLLM workspace '{collection_name}'")
        result = multipart_upload(f"{prefix}/document/upload", token, pdf, slug)
        if not result.get("success"):
            raise RuntimeError(f"AnythingLLM did not report success for {pdf.name}: {result}")
        log(f"indexed in workspace '{collection_name}': {pdf.name}")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        log(f"ERROR: {exc}")
        raise
