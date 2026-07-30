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
COMBINED_CONTEXT="${COMBINED_CONTEXT:-/workspace/current_context.md}"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen3-coder:30b}"

if [ ! -f "$COMBINED_CONTEXT" ]; then
  "$MEMORY_DIR/load_memory.sh"
fi

if [ "$#" -gt 0 ]; then
  user_prompt="$*"
else
  user_prompt="$(cat)"
fi

{
  echo "Use the following project memory as context. If the answer depends on this setup, rely on this memory."
  echo
  cat "$COMBINED_CONTEXT"
  echo
  echo "---"
  echo
  echo "User request:"
  echo "$user_prompt"
} | ollama run "$OLLAMA_MODEL"
