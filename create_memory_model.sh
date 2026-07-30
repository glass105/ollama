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
OLLAMA_MEMORY_MODEL="${OLLAMA_MEMORY_MODEL:-qwen3-coder-memory:30b}"

if [ ! -f "$COMBINED_CONTEXT" ]; then
  "$MEMORY_DIR/load_memory.sh"
fi

modelfile="$(mktemp /tmp/ollama-memory-model.XXXXXX.Modelfile)"
trap 'rm -f "$modelfile"' EXIT

{
  echo "FROM $OLLAMA_MODEL"
  echo 'SYSTEM """'
  echo "You are Qwen running in this disposable RunPod project environment."
  echo
  echo "Use the following Markdown project memory as your current project context."
  echo "When the user asks what you remember from the MD files, summarize this memory."
  echo "Do not claim you cannot access the memory unless the user asks about files outside this provided context."
  echo
  cat "$COMBINED_CONTEXT"
  echo
  echo '"""'
} > "$modelfile"

ollama create "$OLLAMA_MEMORY_MODEL" -f "$modelfile"
echo "Created Ollama memory model: $OLLAMA_MEMORY_MODEL"
