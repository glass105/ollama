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
OPEN_WEBUI_DATA_DIR="${DATA_DIR:-/workspace/open-webui}"
OPEN_WEBUI_MEMORY_MODEL="${OPEN_WEBUI_MEMORY_MODEL:-qwen3-coder-memory-webui:30b}"
OPEN_WEBUI_MEMORY_MODEL_NAME="${OPEN_WEBUI_MEMORY_MODEL_NAME:-Qwen3 Coder Memory}"

if [ ! -f "$COMBINED_CONTEXT" ]; then
  "$MEMORY_DIR/load_memory.sh"
fi

python_bin="python3"
if ! command -v "$python_bin" >/dev/null 2>&1; then
  python_bin="python"
fi

"$python_bin" - "$OPEN_WEBUI_DATA_DIR/webui.db" "$COMBINED_CONTEXT" "$OLLAMA_MODEL" "$OPEN_WEBUI_MEMORY_MODEL" "$OPEN_WEBUI_MEMORY_MODEL_NAME" <<'PY'
import json
import sqlite3
import sys
import time

db_path, context_path, base_model, model_id, model_name = sys.argv[1:6]

with open(context_path, 'r', encoding='utf-8') as f:
    context = f.read().strip()

system = f"""You are Qwen running in this disposable RunPod project environment.

Use the following Markdown project memory as your current project context.
When the user asks what you remember from the MD files, summarize this memory.
Do not claim you cannot access the memory unless the user asks about files outside this provided context.
Follow MEMORY/DECISIONS.md and never store secrets, keys, tokens, logs, caches, databases, or model files in GitHub.

{context}
"""

now = int(time.time())
params = {
    'system': system,
    'temperature': 0.2,
}
meta = {
    'description': 'Open WebUI wrapper that injects /workspace/current_context.md as project memory.',
    'tags': [{'name': 'memory'}, {'name': 'runpod'}, {'name': 'ollama'}],
    'capabilities': {
        'vision': False,
        'citations': False,
    },
}

con = sqlite3.connect(db_path)
user_row = con.execute(
    "select id from user where role = 'admin' order by created_at asc limit 1"
).fetchone()
if not user_row:
    user_row = con.execute("select id from user order by created_at asc limit 1").fetchone()
if not user_row:
    raise SystemExit('Open WebUI has no user yet. Create the first admin account, then rerun this script.')

user_id = user_row[0]
con.execute(
    """
    insert into model (id, user_id, base_model_id, name, params, meta, updated_at, created_at, is_active)
    values (?, ?, ?, ?, ?, ?, ?, ?, 1)
    on conflict(id) do update set
      user_id = excluded.user_id,
      base_model_id = excluded.base_model_id,
      name = excluded.name,
      params = excluded.params,
      meta = excluded.meta,
      updated_at = excluded.updated_at,
      is_active = 1
    """,
    (model_id, user_id, base_model, model_name, json.dumps(params), json.dumps(meta), now, now),
)
con.commit()
print(f'Configured Open WebUI memory model: {model_id} -> {base_model}')
PY
