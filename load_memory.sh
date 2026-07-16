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

mkdir -p "$(dirname "$COMBINED_CONTEXT")"

{
  echo "# Combined Project Context"
  echo
  echo "Generated at: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
  echo
} > "$COMBINED_CONTEXT"

append_file() {
  local relative_path="$1"
  local source_file="$MEMORY_DIR/$relative_path"

  if [ -f "$source_file" ]; then
    {
      echo
      echo "---"
      echo
      echo "## $relative_path"
      echo
      cat "$source_file"
      echo
    } >> "$COMBINED_CONTEXT"
  fi
}

append_file "MEMORY/PROJECT_CONTEXT.md"
append_file "MEMORY/TODO.md"
append_file "MEMORY/DECISIONS.md"
append_file "MEMORY/OPENCLAW.md"
append_file "MEMORY/SECURITY.md"
append_file "PROMPTS/QWEN_SYSTEM_PROMPT.md"

echo "Combined memory written to $COMBINED_CONTEXT"
