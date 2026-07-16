#!/usr/bin/env bash
set -euo pipefail

# Auto-sync lightweight project memory/reference files to GitHub on a timer
# and during graceful shutdown.
# Intended for a disposable RunPod pod where GitHub is the long-term memory store.

MEMORY_DIR="${MEMORY_DIR:-/workspace/ollama-memory}"
SYNC_INTERVAL_SECONDS="${SYNC_INTERVAL_SECONDS:-1800}" # 30 minutes

log() {
  echo "[autosync] $*"
}

sync_memory() {
  if [ ! -d "$MEMORY_DIR/.git" ]; then
    log "Memory repo not found at $MEMORY_DIR. Skipping sync."
    return 0
  fi

  cd "$MEMORY_DIR"

  log "Syncing memory, PDFs, and images to GitHub..."

  # Set a safe default git identity if the container does not already have one.
  git config user.name >/dev/null 2>&1 || git config user.name "runpod-memory-bot"
  git config user.email >/dev/null 2>&1 || git config user.email "runpod-memory-bot@users.noreply.github.com"

  # Pull latest first to reduce conflict risk.
  if ! git pull --rebase; then
    log "Warning: git pull --rebase failed. Resolve conflicts manually if needed."
    return 1
  fi

  # Only add lightweight project memory/reference files.
  # This avoids accidentally committing models, databases, logs, caches, or secrets.
  git add README.md MEMORY/*.md PROMPTS/*.md PDFS/*.pdf PDFS/*.md \
    IMAGES/*.png IMAGES/*.jpg IMAGES/*.jpeg IMAGES/*.webp IMAGES/*.gif IMAGES/*.svg IMAGES/*.md \
    2>/dev/null || true

  if git diff --cached --quiet; then
    log "No memory, PDF, or image changes to commit."
    return 0
  fi

  timestamp="$(date -u +"%Y-%m-%d %H:%M:%S UTC")"
  git commit -m "Update memory assets - $timestamp"

  if ! git push; then
    log "Warning: git push failed. Check GitHub authentication."
    return 1
  fi

  log "Memory assets synced successfully."
}

shutdown_sync() {
  log "Shutdown signal detected. Running final memory sync..."
  sync_memory || true
  exit 0
}

trap shutdown_sync SIGTERM SIGINT

log "Starting memory auto-sync every $SYNC_INTERVAL_SECONDS seconds."
log "Memory directory: $MEMORY_DIR"

# Run once at startup so current memory is preserved early.
sync_memory || true

while true; do
  sleep "$SYNC_INTERVAL_SECONDS" &
  wait $!
  sync_memory || true
done
