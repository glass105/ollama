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
OPEN_WEBUI_DATA_DIR="${DATA_DIR:-${OPEN_WEBUI_DATA_DIR:-/workspace/open-webui}}"
ANYTHINGLLM_STORAGE_DIR="${ANYTHINGLLM_STORAGE_DIR:-/workspace/anything-llm/server/storage}"

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

  copy_dir_if_present "$snapshot_root/open-webui/vector_db" "$OPEN_WEBUI_DATA_DIR/vector_db"
  copy_dir_if_present "$snapshot_root/open-webui/uploads" "$OPEN_WEBUI_DATA_DIR/uploads"
  copy_dir_if_present "$snapshot_root/anythingllm/lancedb" "$ANYTHINGLLM_STORAGE_DIR/lancedb"
  copy_dir_if_present "$snapshot_root/anythingllm/documents" "$ANYTHINGLLM_STORAGE_DIR/documents"
  copy_dir_if_present "$snapshot_root/anythingllm/vector-cache" "$ANYTHINGLLM_STORAGE_DIR/vector-cache"
  copy_dir_if_present "$snapshot_root/manifests" "${RAG_CACHE_MANIFEST_DIR:-/workspace/rag-cache-manifests}"

  log "RAG cache restore complete."
}

main "$@"
