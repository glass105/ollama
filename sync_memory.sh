#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$SCRIPT_DIR/.env"
  set +a
fi

MEMORY_DIR="${MEMORY_DIR:-$SCRIPT_DIR}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"

log() {
  echo "[sync] $*"
}

if [ ! -d "$MEMORY_DIR/.git" ]; then
  log "No git repository found at $MEMORY_DIR"
  exit 1
fi

cd "$MEMORY_DIR"

git config user.name >/dev/null 2>&1 || git config user.name "runpod-memory-bot"
git config user.email >/dev/null 2>&1 || git config user.email "runpod-memory-bot@users.noreply.github.com"

log "Pulling latest changes from $GITHUB_BRANCH."
git pull --rebase origin "$GITHUB_BRANCH"

log "Adding allowed memory/config assets only."
git add README.md \
  MEMORY/*.md \
  PROMPTS/*.md \
  PDFS/*.md \
  PDFS/*.pdf \
  IMAGES/*.md \
  IMAGES/*.png \
  IMAGES/*.jpg \
  IMAGES/*.jpeg \
  IMAGES/*.webp \
  IMAGES/*.gif \
  IMAGES/*.svg \
  2>/dev/null || true

if git diff --cached --quiet; then
  log "No allowed changes to commit."
  exit 0
fi

timestamp="$(date -u +"%Y-%m-%d %H:%M:%S UTC")"
git commit -m "Update RunPod memory - $timestamp"
git push origin "$GITHUB_BRANCH"

log "Memory synced to GitHub."
