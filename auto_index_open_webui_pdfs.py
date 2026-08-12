#!/usr/bin/env python3
import hashlib
import json
import os
import shutil
import sqlite3
import time
import uuid
import zipfile
from html import unescape
from xml.etree import ElementTree
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


DATA_DIR = Path(os.environ.get("DATA_DIR", "/workspace/open-webui"))
MEMORY_DIR = Path(os.environ.get("MEMORY_DIR", "/workspace/ollama-memory"))
PDF_DIR = Path(os.environ.get("OPEN_WEBUI_PDF_DIR", str(MEMORY_DIR / "PDFS")))
WEBUI_URL = os.environ.get("OPEN_WEBUI_URL", "http://127.0.0.1:3000").rstrip("/")
KNOWLEDGE_DESCRIPTION_TEMPLATE = os.environ.get(
    "OPEN_WEBUI_PDF_KNOWLEDGE_DESCRIPTION_TEMPLATE",
    "Git-backed PDF references from PDFS/{collection}",
)
WEBUI_SECRET_KEY_FILE = Path(os.environ.get("WEBUI_SECRET_KEY_FILE", str(MEMORY_DIR / ".webui_secret_key")))
LOG_PREFIX = "[open-webui-pdf-index]"
USER_WAIT_TIMEOUT_SECONDS = int(os.environ.get("OPEN_WEBUI_PDF_INDEX_USER_WAIT_SECONDS", "1800"))


def log(message: str) -> None:
    print(f"{LOG_PREFIX} {message}", flush=True)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def db_connect() -> sqlite3.Connection:
    db_path = DATA_DIR / "webui.db"
    con = sqlite3.connect(db_path)
    con.row_factory = sqlite3.Row
    return con


def get_admin_user_id(con: sqlite3.Connection) -> str:
    configured_email = os.environ.get("OPEN_WEBUI_ADMIN_EMAIL", "").strip().lower()
    if configured_email:
        row = con.execute(
            "select id from user where lower(email) = ? order by created_at limit 1",
            (configured_email,),
        ).fetchone()
        if row:
            return row["id"]

    row = con.execute("select id from user where role = 'admin' order by created_at limit 1").fetchone()
    if row:
        return row["id"]

    row = con.execute("select id from user order by created_at limit 1").fetchone()
    if row:
        return row["id"]

    raise RuntimeError("No Open WebUI user exists yet; create or bootstrap an admin before PDF auto-indexing.")


def wait_for_admin_user_id(con: sqlite3.Connection, timeout_seconds: int = USER_WAIT_TIMEOUT_SECONDS) -> str:
    deadline = time.time() + timeout_seconds
    last_error = None
    while time.time() < deadline:
        try:
            return get_admin_user_id(con)
        except RuntimeError as exc:
            last_error = exc
            log("waiting for an Open WebUI user before PDF auto-indexing")
            time.sleep(10)
    raise RuntimeError(str(last_error) if last_error else "No Open WebUI user exists yet.")


def ensure_knowledge(con: sqlite3.Connection, user_id: str, name: str) -> str:
    row = con.execute(
        "select id from knowledge where name = ? and user_id = ? order by created_at limit 1",
        (name, user_id),
    ).fetchone()
    if row:
        return row["id"]

    now = int(time.time())
    knowledge_id = str(uuid.uuid4())
    description = KNOWLEDGE_DESCRIPTION_TEMPLATE.format(collection=name)
    con.execute(
        "insert into knowledge (id, user_id, name, description, meta, created_at, updated_at, data) "
        "values (?, ?, ?, ?, ?, ?, ?, ?)",
        (knowledge_id, user_id, name, description, None, now, now, None),
    )
    con.commit()
    log(f"created knowledge '{name}' ({knowledge_id})")
    return knowledge_id


def extract_pdf_text(path: Path) -> str:
    try:
        from pypdf import PdfReader
    except ImportError as exc:
        raise RuntimeError("pypdf is required; install it in the Open WebUI venv.") from exc

    reader = PdfReader(str(path))
    parts = [f"# {path.stem}", "", f"Source PDF: {path}", f"Pages: {len(reader.pages)}", ""]
    for index, page in enumerate(reader.pages, 1):
        text = page.extract_text() or ""
        parts.append(f"\n---\n\n## Page {index}\n\n{text.strip()}\n")
        if index % 100 == 0:
            log(f"extracted {path.name}: {index}/{len(reader.pages)} pages")
    return "\n".join(parts)


def _xlsx_cell_value(cell, shared_strings: list[str]) -> str:
    value = cell.find("{*}v")
    if value is None or value.text is None:
        inline = cell.find("{*}is/{*}t")
        return unescape(inline.text if inline is not None and inline.text else "")

    raw = value.text
    if cell.attrib.get("t") == "s":
        try:
            return shared_strings[int(raw)]
        except Exception:
            return raw
    return raw


def extract_xlsx_text(path: Path) -> str:
    shared_strings: list[str] = []
    parts = [f"# {path.stem}", "", f"Source workbook: {path}", ""]
    with zipfile.ZipFile(path) as archive:
        if "xl/sharedStrings.xml" in archive.namelist():
            root = ElementTree.fromstring(archive.read("xl/sharedStrings.xml"))
            for item in root.findall("{*}si"):
                texts = [node.text or "" for node in item.findall(".//{*}t")]
                shared_strings.append(unescape("".join(texts)))

        workbook_names: dict[str, str] = {}
        if "xl/workbook.xml" in archive.namelist():
            workbook = ElementTree.fromstring(archive.read("xl/workbook.xml"))
            for index, sheet in enumerate(workbook.findall(".//{*}sheet"), 1):
                workbook_names[f"sheet{index}"] = sheet.attrib.get("name", f"Sheet {index}")

        sheet_paths = sorted(
            name for name in archive.namelist()
            if name.startswith("xl/worksheets/sheet") and name.endswith(".xml")
        )
        for index, sheet_path in enumerate(sheet_paths, 1):
            sheet_name = workbook_names.get(f"sheet{index}", f"Sheet {index}")
            parts.append(f"\n---\n\n## Sheet: {sheet_name}\n")
            root = ElementTree.fromstring(archive.read(sheet_path))
            rows_written = 0
            for row in root.findall(".//{*}sheetData/{*}row"):
                values = [
                    _xlsx_cell_value(cell, shared_strings).strip()
                    for cell in row.findall("{*}c")
                ]
                while values and values[-1] == "":
                    values.pop()
                if any(values):
                    parts.append(" | ".join(values))
                    rows_written += 1
                if rows_written and rows_written % 500 == 0:
                    log(f"extracted {path.name}: {sheet_name} {rows_written} rows")
    return "\n".join(parts)


def extract_document_text(path: Path) -> str:
    if path.suffix.lower() == ".pdf":
        return extract_pdf_text(path)
    if path.suffix.lower() == ".xlsx":
        return extract_xlsx_text(path)
    raise RuntimeError(f"Unsupported document type: {path}")


def find_file_by_hash(con: sqlite3.Connection, file_hash: str) -> sqlite3.Row | None:
    pattern = f'%"{file_hash}"%'
    return con.execute("select * from file where meta like ? order by created_at desc limit 1", (pattern,)).fetchone()


def upsert_file_record(
    con: sqlite3.Connection,
    user_id: str,
    knowledge_id: str,
    document_path: Path,
    content: str,
    file_hash: str,
) -> str:
    existing = find_file_by_hash(con, file_hash)
    now = int(time.time())
    uploads_dir = DATA_DIR / "uploads"
    uploads_dir.mkdir(parents=True, exist_ok=True)

    if existing:
        file_id = existing["id"]
    else:
        file_id = str(uuid.uuid4())

    upload_path = uploads_dir / f"{file_id}_{document_path.name}"
    if not upload_path.exists():
        shutil.copy2(document_path, upload_path)

    meta = {
        "name": document_path.name,
        "content_type": "application/pdf" if document_path.suffix.lower() == ".pdf" else "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "size": document_path.stat().st_size,
        "file_hash": file_hash,
        "data": {"knowledge_id": knowledge_id, "directory_id": None},
    }
    data = {
        "status": "pending",
        "stage": "git_pdf_auto_index",
        "content": content,
    }

    if existing:
        con.execute(
            "update file set user_id = ?, filename = ?, meta = ?, data = ?, updated_at = ?, path = ? where id = ?",
            (user_id, document_path.name, json.dumps(meta), json.dumps(data), now, str(upload_path), file_id),
        )
    else:
        con.execute(
            "insert into file (id, user_id, filename, meta, created_at, hash, data, updated_at, path) "
            "values (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (file_id, user_id, document_path.name, json.dumps(meta), now, None, json.dumps(data), now, str(upload_path)),
        )
    con.commit()
    return file_id


def create_token(user_id: str) -> str:
    if WEBUI_SECRET_KEY_FILE.exists() and not os.environ.get("WEBUI_SECRET_KEY"):
        os.environ["WEBUI_SECRET_KEY"] = WEBUI_SECRET_KEY_FILE.read_text().strip()
    os.environ.setdefault("DATA_DIR", str(DATA_DIR))
    from open_webui.utils.auth import create_token as webui_create_token

    return webui_create_token({"id": user_id})


def post_json(url: str, token: str, payload: dict, timeout_seconds: int = 14400) -> dict:
    body = json.dumps(payload).encode("utf-8")
    req = Request(
        url,
        data=body,
        method="POST",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    try:
        with urlopen(req, timeout=timeout_seconds) as response:
            raw = response.read().decode("utf-8")
    except HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Open WebUI API failed: HTTP {exc.code}: {detail}") from exc
    except URLError as exc:
        raise RuntimeError(f"Open WebUI API unavailable: {exc}") from exc
    return json.loads(raw) if raw else {}


def wait_for_webui(timeout_seconds: int = 180) -> None:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        try:
            req = Request(f"{WEBUI_URL}/api/version")
            with urlopen(req, timeout=5):
                return
        except Exception:
            time.sleep(2)
    raise RuntimeError(f"Open WebUI did not respond at {WEBUI_URL}")


def already_linked(con: sqlite3.Connection, knowledge_id: str, file_id: str) -> bool:
    row = con.execute(
        "select 1 from knowledge_file where knowledge_id = ? and file_id = ? limit 1",
        (knowledge_id, file_id),
    ).fetchone()
    if not row:
        return False
    file_row = con.execute("select hash, data from file where id = ?", (file_id,)).fetchone()
    if not file_row or not file_row["hash"]:
        return False
    data = json.loads(file_row["data"]) if file_row["data"] else {}
    return data.get("status") == "completed"


def document_collection_name(path: Path) -> str | None:
    relative = path.relative_to(PDF_DIR)
    if len(relative.parts) < 2:
        return None
    return relative.parts[0]


def main() -> int:
    wait_for_webui()
    if not PDF_DIR.is_dir():
        log(f"PDF directory not found: {PDF_DIR}; skipping")
        return 0

    documents = sorted(
        p for p in PDF_DIR.rglob("*")
        if p.is_file() and p.suffix.lower() in {".pdf", ".xlsx"}
    )
    if not documents:
        log(f"no PDFs or XLSX files found in {PDF_DIR}; skipping")
        return 0

    with db_connect() as con:
        user_id = wait_for_admin_user_id(con)
        token = create_token(user_id)
        knowledge_ids: dict[str, str] = {}

        for document in documents:
            collection_name = document_collection_name(document)
            if not collection_name:
                log(f"skipping top-level document without collection directory: {document.name}")
                continue

            if collection_name not in knowledge_ids:
                knowledge_ids[collection_name] = ensure_knowledge(con, user_id, collection_name)
            knowledge_id = knowledge_ids[collection_name]

            file_hash = sha256_file(document)
            existing = find_file_by_hash(con, file_hash)
            if existing and already_linked(con, knowledge_id, existing["id"]):
                log(f"already indexed in '{collection_name}': {document.name}")
                continue

            log(f"extracting: {document.name}")
            content = extract_document_text(document)
            file_id = upsert_file_record(con, user_id, knowledge_id, document, content, file_hash)
            log(f"indexing {document.name} into knowledge '{collection_name}'")
            post_json(f"{WEBUI_URL}/api/v1/knowledge/{knowledge_id}/file/add", token, {"file_id": file_id})
            log(f"indexed in '{collection_name}': {document.name}")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        log(f"ERROR: {exc}")
        raise
