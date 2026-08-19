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
RAG_S3_RETENTION_COUNT="${RAG_S3_RETENTION_COUNT:-3}"
ANYTHINGLLM_STORAGE_DIR="${ANYTHINGLLM_STORAGE_DIR:-/workspace/anything-llm/server/storage}"

log() {
  echo "[save-rag-cache] $*"
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
    cp -a "$src" "$dst"
  fi
}

write_manifests() {
  local out_dir="$1"
  mkdir -p "$out_dir"
  python3 - "$out_dir" "$ANYTHINGLLM_STORAGE_DIR" <<'PY'
import json
import sqlite3
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
anything_storage = Path(sys.argv[2])

def dump_tables(db_path, tables, output_name):
    if not db_path.exists():
        return
    con = sqlite3.connect(db_path)
    con.row_factory = sqlite3.Row
    manifest = {}
    for table in tables:
        try:
            manifest[table] = [dict(row) for row in con.execute(f'select * from "{table}"')]
        except Exception as exc:
            manifest[table] = {"error": str(exc)}
    (out_dir / output_name).write_text(json.dumps(manifest, indent=2, sort_keys=True))

dump_tables(
    anything_storage / "anythingllm.db",
    ["workspaces", "workspace_documents", "document_vectors"],
    "anythingllm-rag-manifest.json",
)
PY
}

prune_old_snapshots() {
  local snapshots_uri="s3://${RAG_S3_BUCKET}/${RAG_S3_PREFIX}/snapshots/"

  if ! [[ "$RAG_S3_RETENTION_COUNT" =~ ^[0-9]+$ ]]; then
    log "Invalid RAG_S3_RETENTION_COUNT=$RAG_S3_RETENTION_COUNT; skipping snapshot pruning."
    return 0
  fi

  if [ "$RAG_S3_RETENTION_COUNT" -lt 1 ]; then
    log "RAG_S3_RETENTION_COUNT=$RAG_S3_RETENTION_COUNT; skipping snapshot pruning."
    return 0
  fi

  mapfile -t snapshot_keys < <(
    aws s3 ls --region "$RAG_S3_REGION" --endpoint-url "$RAG_S3_ENDPOINT" "$snapshots_uri" --recursive |
      awk -v archive="$RAG_S3_ARCHIVE_NAME" '$4 ~ archive "$" { print $1 " " $2 " " $4 }' |
      sort |
      awk '{ print $3 }'
  )

  local snapshot_count="${#snapshot_keys[@]}"
  if [ "$snapshot_count" -le "$RAG_S3_RETENTION_COUNT" ]; then
    log "Snapshot retention OK: $snapshot_count snapshot archive(s), limit $RAG_S3_RETENTION_COUNT."
    return 0
  fi

  local prune_count=$((snapshot_count - RAG_S3_RETENTION_COUNT))
  log "Pruning $prune_count old snapshot archive(s); keeping latest $RAG_S3_RETENTION_COUNT."
  local i
  for ((i = 0; i < prune_count; i++)); do
    aws s3 rm --region "$RAG_S3_REGION" --endpoint-url "$RAG_S3_ENDPOINT" \
      "s3://${RAG_S3_BUCKET}/${snapshot_keys[$i]}"
  done
}

main() {
  if ! enabled; then
    log "Skipping save because ENABLE_RAG_S3_CACHE=$ENABLE_RAG_S3_CACHE."
    return 0
  fi

  configure_aws_env
  if ! ensure_aws; then
    log "aws CLI is unavailable; skipping RAG cache save."
    return 0
  fi

  local stamp
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  local stage="/tmp/rag-vector-state-$stamp"
  local archive="/tmp/${RAG_S3_ARCHIVE_NAME}"
  rm -rf "$stage"
  mkdir -p "$stage/anythingllm" "$stage/manifests"

  copy_dir_if_present "$ANYTHINGLLM_STORAGE_DIR/lancedb" "$stage/anythingllm/lancedb"
  copy_dir_if_present "$ANYTHINGLLM_STORAGE_DIR/documents" "$stage/anythingllm/documents"
  copy_dir_if_present "$ANYTHINGLLM_STORAGE_DIR/vector-cache" "$stage/anythingllm/vector-cache"
  write_manifests "$stage/manifests"

  cat > "$stage/README.md" <<'EOF'
# RAG Vector State Snapshot

This snapshot is intended for S3-compatible RAG cache storage only.

It includes vector/RAG-facing runtime artifacts and sanitized manifests.
It intentionally excludes full app SQLite databases, API keys, auth tables,
tokens, logs, model files, OpenClaw runtime state, and general caches.
EOF

  (cd /tmp && tar -czf "$archive" "$(basename "$stage")")

  local latest_uri="s3://${RAG_S3_BUCKET}/${RAG_S3_PREFIX}/latest/${RAG_S3_ARCHIVE_NAME}"
  local snapshot_uri="s3://${RAG_S3_BUCKET}/${RAG_S3_PREFIX}/snapshots/${stamp}/${RAG_S3_ARCHIVE_NAME}"

  log "Uploading RAG cache snapshot to $latest_uri."
  aws s3 cp --region "$RAG_S3_REGION" --endpoint-url "$RAG_S3_ENDPOINT" "$archive" "$latest_uri"
  aws s3 cp --region "$RAG_S3_REGION" --endpoint-url "$RAG_S3_ENDPOINT" "$archive" "$snapshot_uri"
  prune_old_snapshots
  log "RAG cache save complete."
}

main "$@"
