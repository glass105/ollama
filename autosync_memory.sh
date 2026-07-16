#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$SCRIPT_DIR/.env"
  set +a
fi

MEMORY_DIR="${MEMORY_DIR:-/workspace/ollama-memory}"
SYNC_INTERVAL_SECONDS="${SYNC_INTERVAL_SECONDS:-1800}"

log() {
  echo "[autosync] $*"
}

run_sync() {
  "$SCRIPT_DIR/sync_memory.sh" || log "Sync failed. Check GitHub auth, network, or conflicts."
}

shutdown_sync() {
  log "Shutdown signal detected. Running final sync."
  run_sync || true
  exit 0
}

trap shutdown_sync SIGINT SIGTERM

log "Starting memory autosync every ${SYNC_INTERVAL_SECONDS} seconds."
log "Memory directory: $MEMORY_DIR"

run_sync || true

while true; do
  sleep "$SYNC_INTERVAL_SECONDS" &
  wait $!
  run_sync || true
done
