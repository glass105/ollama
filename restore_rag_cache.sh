#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$SCRIPT_DIR/.env"
  set +a
fi

ENABLE_RAG_S3_CACHE="${ENABLE_RAG_S3_CACHE:-false}"
RAG_S3_REGION="${RAG_S3_REGION:-us-nc-1}"
RAG_S3_ENDPOINT="${RAG_S3_ENDPOINT:-https://s3api-us-nc-1.runpod.io}"
RAG_S3_BUCKET="${RAG_S3_BUCKET:-lp8wr68ped}"
RAG_S3_PREFIX="${RAG_S3_PREFIX:-ollama-rag-cache}"
RAG_S3_ARCHIVE_NAME="${RAG_S3_ARCHIVE_NAME:-rag-vector-state.tar.gz}"
ANYTHINGLLM_STORAGE_DIR="${ANYTHINGLLM_STORAGE_DIR:-/workspace/anything-llm/server/storage}"
RAG_CACHE_MANIFEST_DIR="${RAG_CACHE_MANIFEST_DIR:-/workspace/rag-cache-manifests}"

log() {
  echo "[restore-rag-cache] $*"
}

enabled() {
  case "$(printf '%s' "$ENABLE_RAG_S3_CACHE" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

ensure_aws() {
  if command -v aws >/dev/null 2>&1; then
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 -m pip install --user --no-cache-dir awscli >/tmp/rag-cache-awscli-install.log 2>&1
    export PATH="$HOME/.local/bin:$PATH"
  elif command -v python >/dev/null 2>&1; then
    python -m pip install --user --no-cache-dir awscli >/tmp/rag-cache-awscli-install.log 2>&1
    export PATH="$HOME/.local/bin:$PATH"
  fi

  command -v aws >/dev/null 2>&1
}

configure_aws_env() {
  if [ -n "${RAG_S3_ACCESS_KEY_ID:-}" ]; then
    export AWS_ACCESS_KEY_ID="$RAG_S3_ACCESS_KEY_ID"
  fi
  if [ -n "${RAG_S3_SECRET_ACCESS_KEY:-}" ]; then
    export AWS_SECRET_ACCESS_KEY="$RAG_S3_SECRET_ACCESS_KEY"
  fi
  if [ -n "${RAG_S3_SESSION_TOKEN:-}" ]; then
    export AWS_SESSION_TOKEN="$RAG_S3_SESSION_TOKEN"
  fi
  export AWS_DEFAULT_REGION="$RAG_S3_REGION"
}

copy_dir_if_present() {
  local src="$1"
  local dst="$2"
  if [ -d "$src" ]; then
    mkdir -p "$(dirname "$dst")"
    rm -rf "$dst"
    cp -a "$src" "$dst"
    log "Restored $dst."
  fi
}

restore_anythingllm_workspace_manifest() {
  local manifest_path="$1"
  local db_path="$ANYTHINGLLM_STORAGE_DIR/anythingllm.db"

  if [ ! -f "$manifest_path" ]; then
    log "No AnythingLLM workspace manifest found at $manifest_path; skipping workspace restore."
    return 0
  fi

  if [ ! -f "$db_path" ]; then
    log "AnythingLLM database not found at $db_path; skipping workspace restore."
    return 0
  fi

  python3 - "$manifest_path" "$db_path" <<'PY'
import json
import sqlite3
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
db_path = Path(sys.argv[2])
manifest = json.loads(manifest_path.read_text())

def rows_for(table):
    rows = manifest.get(table, [])
    return rows if isinstance(rows, list) else []

def table_columns(con, table):
    try:
        return [row[1] for row in con.execute(f'pragma table_info("{table}")')]
    except sqlite3.Error:
        return []

def qi(name):
    return '"' + str(name).replace('"', '""') + '"'

def filtered(row, columns, overrides=None):
    data = dict(row)
    if overrides:
        data.update(overrides)
    return {key: data[key] for key in columns if key in data}

def find_workspace(con, row):
    lookup_fields = ("id", "slug", "vectorTag", "name")
    for field in lookup_fields:
        value = row.get(field)
        if value in (None, ""):
            continue
        found = con.execute(f'select id from workspaces where "{field}" = ? limit 1', (value,)).fetchone()
        if found:
            return found[0]
    return None

def insert_row(con, table, row):
    columns = table_columns(con, table)
    data = filtered(row, columns)
    if not data:
        return None
    keys = list(data)
    sql = (
        f'insert or replace into {qi(table)} ({", ".join(qi(key) for key in keys)}) '
        f'values ({", ".join("?" for _ in keys)})'
    )
    cur = con.execute(sql, [data[key] for key in keys])
    return data.get("id") or cur.lastrowid

def update_workspace(con, row):
    columns = table_columns(con, "workspaces")
    if not columns:
        return None
    existing_id = find_workspace(con, row)
    if existing_id is None:
        return insert_row(con, "workspaces", row)

    safe_update = filtered(row, columns, {"id": existing_id})
    assignments = [key for key in safe_update if key != "id"]
    if assignments:
        con.execute(
            f'update workspaces set {", ".join(qi(key) + " = ?" for key in assignments)} where id = ?',
            [safe_update[key] for key in assignments] + [existing_id],
        )
    return existing_id

with sqlite3.connect(db_path) as con:
    con.row_factory = sqlite3.Row
    workspace_id_map = {}
    restored_workspaces = 0

    for row in rows_for("workspaces"):
        old_id = row.get("id")
        new_id = update_workspace(con, row)
        if new_id is not None:
            restored_workspaces += 1
            if old_id is not None:
                workspace_id_map[old_id] = new_id

    workspace_document_rows = rows_for("workspace_documents")
    touched_workspace_ids = {
        workspace_id_map.get(row.get("workspaceId"), row.get("workspaceId"))
        for row in workspace_document_rows
        if row.get("workspaceId") is not None
    }
    for workspace_id in touched_workspace_ids:
        con.execute("delete from workspace_documents where workspaceId = ?", (workspace_id,))

    restored_workspace_documents = 0
    for row in workspace_document_rows:
        workspace_id = workspace_id_map.get(row.get("workspaceId"), row.get("workspaceId"))
        if workspace_id is None:
            continue
        if insert_row(con, "workspace_documents", {**row, "workspaceId": workspace_id}) is not None:
            restored_workspace_documents += 1

    document_vector_rows = rows_for("document_vectors")
    touched_doc_ids = {row.get("docId") for row in document_vector_rows if row.get("docId") is not None}
    for doc_id in touched_doc_ids:
        con.execute("delete from document_vectors where docId = ?", (doc_id,))

    restored_document_vectors = 0
    for row in document_vector_rows:
        if insert_row(con, "document_vectors", row) is not None:
            restored_document_vectors += 1

print(
    "restored "
    f"{restored_workspaces} workspace row(s), "
    f"{restored_workspace_documents} workspace document row(s), "
    f"{restored_document_vectors} document vector row(s)"
)
PY
}

main() {
  if ! enabled; then
    log "Skipping restore because ENABLE_RAG_S3_CACHE=$ENABLE_RAG_S3_CACHE."
    return 0
  fi

  configure_aws_env
  if ! ensure_aws; then
    log "aws CLI is unavailable; skipping RAG cache restore."
    return 0
  fi

  local uri="s3://${RAG_S3_BUCKET}/${RAG_S3_PREFIX}/latest/${RAG_S3_ARCHIVE_NAME}"
  local archive="/tmp/${RAG_S3_ARCHIVE_NAME}"
  local restore_root="/tmp/rag-cache-restore"

  log "Checking for RAG cache at $uri."
  if ! aws s3 ls --region "$RAG_S3_REGION" --endpoint-url "$RAG_S3_ENDPOINT" "$uri" >/dev/null 2>&1; then
    log "No RAG cache archive found; startup will rebuild from PDFs."
    return 0
  fi

  log "Downloading RAG cache archive."
  aws s3 cp --region "$RAG_S3_REGION" --endpoint-url "$RAG_S3_ENDPOINT" "$uri" "$archive"

  rm -rf "$restore_root"
  mkdir -p "$restore_root"
  tar -xzf "$archive" -C "$restore_root"

  local snapshot_root
  snapshot_root="$(find "$restore_root" -mindepth 1 -maxdepth 1 -type d | head -1)"
  if [ -z "$snapshot_root" ]; then
    log "Archive did not contain a snapshot directory; skipping restore."
    return 0
  fi

  copy_dir_if_present "$snapshot_root/anythingllm/lancedb" "$ANYTHINGLLM_STORAGE_DIR/lancedb"
  copy_dir_if_present "$snapshot_root/anythingllm/documents" "$ANYTHINGLLM_STORAGE_DIR/documents"
  copy_dir_if_present "$snapshot_root/anythingllm/vector-cache" "$ANYTHINGLLM_STORAGE_DIR/vector-cache"
  copy_dir_if_present "$snapshot_root/manifests" "$RAG_CACHE_MANIFEST_DIR"
  restore_anythingllm_workspace_manifest "$snapshot_root/manifests/anythingllm-rag-manifest.json"

  log "RAG cache restore complete."
}

main "$@"
