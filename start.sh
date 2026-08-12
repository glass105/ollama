#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$SCRIPT_DIR/.env"
  set +a
fi

GITHUB_MEMORY_REPO="${GITHUB_MEMORY_REPO:-https://github.com/glass105/ollama.git}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
MEMORY_DIR="${MEMORY_DIR:-/workspace/ollama-memory}"
COMBINED_CONTEXT="${COMBINED_CONTEXT:-/workspace/current_context.md}"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen3-coder:30b}"
OLLAMA_UPSTREAM_HOST="${OLLAMA_UPSTREAM_HOST:-${OLLAMA_HOST:-127.0.0.1:11434}}"
ENABLE_MODEL_PULL="${ENABLE_MODEL_PULL:-true}"
RAG_EMBEDDING_MODEL="${RAG_EMBEDDING_MODEL:-nomic-embed-text:latest}"
ENABLE_OPENCLAW="${ENABLE_OPENCLAW:-true}"
OPENCLAW_GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
OPENCLAW_GATEWAY_BIND="${OPENCLAW_GATEWAY_BIND:-loopback}"
OPENCLAW_GATEWAY_AUTH="${OPENCLAW_GATEWAY_AUTH:-token}"
OPENCLAW_ALLOWED_ORIGINS="${OPENCLAW_ALLOWED_ORIGINS:-}"
OPENCLAW_ALLOW_HOST_HEADER_ORIGIN_FALLBACK="${OPENCLAW_ALLOW_HOST_HEADER_ORIGIN_FALLBACK:-false}"
ENABLE_ANYTHINGLLM="${ENABLE_ANYTHINGLLM:-true}"
ENABLE_ANYTHINGLLM_PDF_AUTO_INDEX="${ENABLE_ANYTHINGLLM_PDF_AUTO_INDEX:-true}"
ANYTHINGLLM_DIR="${ANYTHINGLLM_DIR:-/workspace/anything-llm}"
ANYTHINGLLM_REPO="${ANYTHINGLLM_REPO:-https://github.com/Mintplex-Labs/anything-llm.git}"
ANYTHINGLLM_PUBLIC_PORT="${ANYTHINGLLM_PUBLIC_PORT:-3001}"
ANYTHINGLLM_INTERNAL_PORT="${ANYTHINGLLM_INTERNAL_PORT:-3010}"
ANYTHINGLLM_DEPLOY_DIR="${ANYTHINGLLM_DEPLOY_DIR:-/workspace/anythingllm-deploy}"
ANYTHINGLLM_STORAGE_DIR="${ANYTHINGLLM_STORAGE_DIR:-/workspace/anything-llm/server/storage}"
ANYTHINGLLM_JWT_SECRET="${ANYTHINGLLM_JWT_SECRET:-runpod-anythingllm-local-compare}"
ANYTHINGLLM_API_KEY_FILE="${ANYTHINGLLM_API_KEY_FILE:-/tmp/anythingllm-api-key}"
ANYTHINGLLM_PDF_DIR="${ANYTHINGLLM_PDF_DIR:-$MEMORY_DIR/PDFS}"
ENABLE_RAG_S3_CACHE="${ENABLE_RAG_S3_CACHE:-false}"
RAG_S3_CACHE_ID="${RAG_S3_CACHE_ID:-lp8wr68ped}"
RAG_S3_REGION="${RAG_S3_REGION:-us-nc-1}"
RAG_S3_ENDPOINT="${RAG_S3_ENDPOINT:-https://s3api-us-nc-1.runpod.io}"
RAG_S3_BUCKET="${RAG_S3_BUCKET:-lp8wr68ped}"
RAG_S3_PREFIX="${RAG_S3_PREFIX:-ollama-rag-cache}"
RAG_S3_ARCHIVE_NAME="${RAG_S3_ARCHIVE_NAME:-rag-vector-state.tar.gz}"

log() {
  echo "[start] $*"
}

restore_rag_cache() {
  case "$(printf '%s' "$ENABLE_RAG_S3_CACHE" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes|y|on) ;;
    *) return 0 ;;
  esac

  if [ ! -f "$MEMORY_DIR/restore_rag_cache.sh" ]; then
    log "RAG cache restore requested but restore_rag_cache.sh is missing."
    return 0
  fi

  log "Restoring S3 RAG cache from bucket $RAG_S3_BUCKET using cache ID $RAG_S3_CACHE_ID."
  ANYTHINGLLM_STORAGE_DIR="$ANYTHINGLLM_STORAGE_DIR" \
    ENABLE_RAG_S3_CACHE="$ENABLE_RAG_S3_CACHE" \
    RAG_S3_CACHE_ID="$RAG_S3_CACHE_ID" \
    RAG_S3_REGION="$RAG_S3_REGION" \
    RAG_S3_ENDPOINT="$RAG_S3_ENDPOINT" \
    RAG_S3_BUCKET="$RAG_S3_BUCKET" \
    RAG_S3_PREFIX="$RAG_S3_PREFIX" \
    RAG_S3_ARCHIVE_NAME="$RAG_S3_ARCHIVE_NAME" \
    RAG_S3_ACCESS_KEY_ID="${RAG_S3_ACCESS_KEY_ID:-}" \
    RAG_S3_SECRET_ACCESS_KEY="${RAG_S3_SECRET_ACCESS_KEY:-}" \
    RAG_S3_SESSION_TOKEN="${RAG_S3_SESSION_TOKEN:-}" \
    bash "$MEMORY_DIR/restore_rag_cache.sh" > /tmp/restore-rag-cache.log 2>&1 || {
      log "RAG cache restore failed. See /tmp/restore-rag-cache.log."
      return 0
    }
}

save_rag_cache() {
  case "$(printf '%s' "$ENABLE_RAG_S3_CACHE" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes|y|on) ;;
    *) return 0 ;;
  esac

  if [ ! -f "$MEMORY_DIR/save_rag_cache.sh" ]; then
    log "RAG cache save requested but save_rag_cache.sh is missing."
    return 0
  fi

  log "Saving S3 RAG cache to bucket $RAG_S3_BUCKET using cache ID $RAG_S3_CACHE_ID."
  ANYTHINGLLM_STORAGE_DIR="$ANYTHINGLLM_STORAGE_DIR" \
    ENABLE_RAG_S3_CACHE="$ENABLE_RAG_S3_CACHE" \
    RAG_S3_CACHE_ID="$RAG_S3_CACHE_ID" \
    RAG_S3_REGION="$RAG_S3_REGION" \
    RAG_S3_ENDPOINT="$RAG_S3_ENDPOINT" \
    RAG_S3_BUCKET="$RAG_S3_BUCKET" \
    RAG_S3_PREFIX="$RAG_S3_PREFIX" \
    RAG_S3_ARCHIVE_NAME="$RAG_S3_ARCHIVE_NAME" \
    RAG_S3_ACCESS_KEY_ID="${RAG_S3_ACCESS_KEY_ID:-}" \
    RAG_S3_SECRET_ACCESS_KEY="${RAG_S3_SECRET_ACCESS_KEY:-}" \
    RAG_S3_SESSION_TOKEN="${RAG_S3_SESSION_TOKEN:-}" \
    bash "$MEMORY_DIR/save_rag_cache.sh" > /tmp/save-rag-cache.log 2>&1 || {
      log "RAG cache save failed. See /tmp/save-rag-cache.log."
      return 0
    }
}

save_rag_cache_on_shutdown() {
  log "Shutdown received; attempting final RAG cache save."
  save_rag_cache
  exit 0
}

install_packages() {
  local missing=()

  command -v git >/dev/null 2>&1 || missing+=("git")
  command -v curl >/dev/null 2>&1 || missing+=("curl")

  if [ "${#missing[@]}" -eq 0 ]; then
    return 0
  fi

  log "Installing missing packages: ${missing[*]}"
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache "${missing[@]}"
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y "${missing[@]}"
  elif command -v yum >/dev/null 2>&1; then
    yum install -y "${missing[@]}"
  elif command -v microdnf >/dev/null 2>&1; then
    microdnf install -y "${missing[@]}"
  else
    log "Could not find a supported package manager to install ${missing[*]}."
    exit 1
  fi
}

ensure_repo() {
  if [ -d "$MEMORY_DIR/.git" ]; then
    log "Updating memory repo at $MEMORY_DIR."
    git -C "$MEMORY_DIR" config core.fileMode false
    git -C "$MEMORY_DIR" pull --rebase origin "$GITHUB_BRANCH"
  else
    log "Cloning memory repo into $MEMORY_DIR."
    mkdir -p "$(dirname "$MEMORY_DIR")"
    git clone --branch "$GITHUB_BRANCH" "$GITHUB_MEMORY_REPO" "$MEMORY_DIR"
    git -C "$MEMORY_DIR" config core.fileMode false
  fi
}

ensure_ollama() {
  if command -v ollama >/dev/null 2>&1; then
    return 0
  fi

  log "Ollama is not installed. Installing Ollama."
  curl -fsSL https://ollama.com/install.sh | sh
}

ensure_openclaw() {
  case "$(printf '%s' "$ENABLE_OPENCLAW" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes|y) ;;
    *)
      log "Skipping OpenClaw install because ENABLE_OPENCLAW=$ENABLE_OPENCLAW."
      return 1
      ;;
  esac

  if command -v openclaw >/dev/null 2>&1; then
    return 0
  fi

  log "OpenClaw is not installed. Installing OpenClaw."
  curl -fsSL https://openclaw.ai/install.sh -o /tmp/openclaw-install.sh
  bash /tmp/openclaw-install.sh > /tmp/openclaw-install.log 2>&1 || {
    log "OpenClaw install failed. See /tmp/openclaw-install.log."
    return 1
  }
}

patch_openclaw_visible_no_reply() {
  if ! command -v python3 >/dev/null 2>&1; then
    return 0
  fi

  python3 - <<'PY'
from pathlib import Path

dist = Path("/usr/lib/node_modules/openclaw/dist")
if not dist.exists():
    raise SystemExit(0)

replacement = (
    'if (text && isSilentReplyPayloadText(text, silentToken)) {\\n'
    '\\t\\ttext = "I received the request, but the model returned OpenClaw\\'s silent NO_REPLY control token instead of an answer. Please retry in a new session with the exact document or command you want searched.";\\n'
    '\\t}'
)

for path in dist.glob("normalize-reply-*.js"):
    text = path.read_text()
    old = (
        'if (text && isSilentReplyPayloadText(text, silentToken)) {\\n'
        '\\t\\tif (!hasContent("")) {\\n'
        '\\t\\t\\topts.onSkip?.("silent");\\n'
        '\\t\\t\\treturn null;\\n'
        '\\t\\t}\\n'
        '\\t\\ttext = "";\\n'
        '\\t}'
    )
    if old in text and "OpenClaw generated a silent NO_REPLY control token" not in text:
        path.write_text(text.replace(old, replacement))
        print(f"patched {path}")

for path in dist.glob("system-prompt-config-*.js"):
    text = path.read_text()
    old = 'if (!isMinimal && silentReplyPromptMode !== "none")'
    new = 'if (!isMinimal && false && silentReplyPromptMode !== "none")'
    if old in text:
        path.write_text(text.replace(old, new))
        print(f"patched {path}")
PY
}

configure_openclaw() {
  if ! command -v openclaw >/dev/null 2>&1; then
    return 1
  fi

  log "Configuring OpenClaw for local Ollama model $OLLAMA_MODEL."
  mkdir -p /root/.openclaw/workspace
  local visible_reply_rule="/tmp/openclaw-visible-reply-rule.md"
  cat > "$visible_reply_rule" <<'EOF'
# Disposable RunPod WebChat Visible Reply Rule

This rule has highest priority for this disposable RunPod setup.
For direct WebChat messages where `senderIsOwner` is true, always return visible helpful text.
Never return `NO_REPLY` to owner/operator greetings, capability checks, document-access questions, troubleshooting prompts, or project-memory checks.
Use `NO_REPLY` only for actual heartbeat polls, duplicate transport events, or messages that explicitly ask for silence.
If asked whether you can read a document or file, answer with what you can access and, when useful, inspect the workspace or Git-backed files before responding.
Treat questions phrased as "can you read...", "can you search...", "can you access...", or "can you use..." as direct requests that require a visible answer. Start with "Yes" or "No", then explain what source or tool you can use.
For example, "Can you search the CMG CLI guide?" requires a visible answer about whether the guide is available and how to query it.

EOF
  local anythingllm_tool_rule="/tmp/openclaw-anythingllm-tool-rule.md"
  cat > "$anythingllm_tool_rule" <<'EOF'
# AnythingLLM RAG Tool

AnythingLLM is the primary RAG layer for Git-backed PDFs and XLSX files.
For questions about PDF, XLSX, CMM, CMG, Nokia, commands, alarms, or reference documents, call the local helper before answering:

```bash
/workspace/ollama-memory/anythingllm_query.sh Nokia "<question>"
```

Use the returned answer and sources in your reply. Do not read LanceDB/vector files directly. Do not print API keys or token files.
If the user asks whether you can read or search a guide, answer visibly and offer to use the helper.

EOF
  for workspace_file in AGENTS.md SOUL.md HEARTBEAT.md TOOLS.md; do
    local workspace_path="/root/.openclaw/workspace/$workspace_file"
    touch "$workspace_path"
    if ! grep -q "Disposable RunPod WebChat Visible Reply Rule" "$workspace_path"; then
      local workspace_tmp
      workspace_tmp="$(mktemp)"
      cat "$visible_reply_rule" "$workspace_path" > "$workspace_tmp"
      mv "$workspace_tmp" "$workspace_path"
    fi
    if ! grep -q "AnythingLLM RAG Tool" "$workspace_path"; then
      local tool_tmp
      tool_tmp="$(mktemp)"
      cat "$anythingllm_tool_rule" "$workspace_path" > "$tool_tmp"
      mv "$tool_tmp" "$workspace_path"
    fi
  done
  python3 - <<'PY'
from pathlib import Path
import re

path = Path("/root/.openclaw/workspace/AGENTS.md")
if path.exists():
    text = path.read_text(errors="ignore")
    text = re.sub(r"\n## Group Chats\n.*?(?=\n## Tools\n)", "\n", text, flags=re.S)
    path.write_text(text)
PY

  local allowed_origins_json="[]"
  if [ -n "$OPENCLAW_ALLOWED_ORIGINS" ]; then
    allowed_origins_json="$(
      printf '%s' "$OPENCLAW_ALLOWED_ORIGINS" | "$(
        command -v python3 >/dev/null 2>&1 && printf python3 || printf python
      )" -c 'import json,sys; print(json.dumps([x.strip() for x in sys.stdin.read().split(",") if x.strip()]))'
    )"
  fi

  cat > /tmp/openclaw-ollama.patch.json <<EOF
{
  "gateway": {
    "mode": "local",
    "bind": "$OPENCLAW_GATEWAY_BIND",
    "port": $OPENCLAW_GATEWAY_PORT,
    "auth": {
      "mode": "$OPENCLAW_GATEWAY_AUTH"
    },
    "controlUi": {
      "allowedOrigins": $allowed_origins_json,
      "dangerouslyAllowHostHeaderOriginFallback": $OPENCLAW_ALLOW_HOST_HEADER_ORIGIN_FALLBACK
    }
  },
  "models": {
    "providers": {
      "ollama": {
        "baseUrl": "http://127.0.0.1:11434",
        "apiKey": "ollama-local",
        "api": "ollama",
        "timeoutSeconds": 420,
        "contextWindow": 65536,
        "maxTokens": 8192,
        "models": [
          {
            "id": "$OLLAMA_MODEL",
            "name": "$OLLAMA_MODEL",
            "input": ["text"],
            "contextWindow": 65536,
            "maxTokens": 8192,
            "params": {
              "num_ctx": 65536,
              "keep_alive": "15m"
            }
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "compaction": {
        "reserveTokensFloor": 24000
      },
      "model": {
        "primary": "ollama/$OLLAMA_MODEL"
      }
    }
  }
}
EOF
  openclaw config patch --file /tmp/openclaw-ollama.patch.json > /tmp/openclaw-config.log 2>&1 || {
    log "OpenClaw config failed. See /tmp/openclaw-config.log."
    return 1
  }
  openclaw models set "ollama/$OLLAMA_MODEL" >> /tmp/openclaw-config.log 2>&1 || true
}

start_openclaw_gateway() {
  if ! command -v openclaw >/dev/null 2>&1; then
    return 1
  fi

  mkdir -p /tmp/openclaw

  if [ "$OPENCLAW_GATEWAY_AUTH" = "token" ] && [ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
    if command -v openssl >/dev/null 2>&1; then
      OPENCLAW_GATEWAY_TOKEN="$(openssl rand -hex 24)"
    else
      OPENCLAW_GATEWAY_TOKEN="$(date +%s%N)"
    fi
    export OPENCLAW_GATEWAY_TOKEN
    printf '%s\n' "$OPENCLAW_GATEWAY_TOKEN" > /tmp/openclaw/gateway-token
    chmod 600 /tmp/openclaw/gateway-token
  fi

  if [ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
    printf '%s\n' "$OPENCLAW_GATEWAY_TOKEN" > /tmp/openclaw/gateway-token
    chmod 600 /tmp/openclaw/gateway-token
  fi

  log "Starting OpenClaw gateway on $OPENCLAW_GATEWAY_BIND:$OPENCLAW_GATEWAY_PORT with auth=$OPENCLAW_GATEWAY_AUTH."
  local openclaw_token_args=""
  if [ "$OPENCLAW_GATEWAY_AUTH" = "token" ] && [ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
    openclaw_token_args="--token $OPENCLAW_GATEWAY_TOKEN"
  fi

  # shellcheck disable=SC2086
  OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-}" nohup openclaw gateway \
    --bind "$OPENCLAW_GATEWAY_BIND" \
    --port "$OPENCLAW_GATEWAY_PORT" \
    --auth "$OPENCLAW_GATEWAY_AUTH" \
    $openclaw_token_args \
    --allow-unconfigured \
    run \
    > /tmp/openclaw/gateway.log 2>&1 &
}

wait_for_ollama() {
  log "Waiting for Ollama on http://$OLLAMA_UPSTREAM_HOST."
  for _ in $(seq 1 120); do
    if curl -fsS "http://$OLLAMA_UPSTREAM_HOST/api/tags" >/dev/null 2>&1; then
      log "Ollama is ready."
      return 0
    fi
    sleep 1
  done

  log "Ollama did not become ready within 120 seconds."
  exit 1
}

start_ollama() {
  log "Starting Ollama upstream with OLLAMA_HOST=$OLLAMA_UPSTREAM_HOST."
  export OLLAMA_HOST="$OLLAMA_UPSTREAM_HOST"
  nohup ollama serve > /tmp/ollama.log 2>&1 &
}

pull_model() {
  case "$(printf '%s' "$ENABLE_MODEL_PULL" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes|y)
      log "Pulling Ollama model $OLLAMA_MODEL."
      ollama pull "$OLLAMA_MODEL"
      ;;
    *)
      log "Skipping model pull because ENABLE_MODEL_PULL=$ENABLE_MODEL_PULL."
      ;;
  esac
}

pull_embedding_model() {
  log "Pulling Ollama embedding model $RAG_EMBEDDING_MODEL for AnythingLLM RAG."
  ollama pull "$RAG_EMBEDDING_MODEL" || {
    log "Embedding model pull failed; AnythingLLM RAG indexing may fail."
    return 1
  }
}

ensure_node20_for_anythingllm() {
  if [ -x /usr/local/bin/node ] && /usr/local/bin/node -v | grep -Eq '^v20\.'; then
    return 0
  fi

  if command -v node >/dev/null 2>&1 && node -v | grep -Eq '^v20\.'; then
    return 0
  fi

  if ! command -v npm >/dev/null 2>&1; then
    log "npm is missing; installing nodejs and npm for AnythingLLM."
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs npm
    elif command -v apk >/dev/null 2>&1; then
      apk add --no-cache nodejs npm
    elif command -v dnf >/dev/null 2>&1; then
      dnf install -y nodejs npm
    elif command -v yum >/dev/null 2>&1; then
      yum install -y nodejs npm
    else
      log "No supported package manager found to install npm."
      return 1
    fi
  fi

  log "Installing Node 20 for AnythingLLM."
  npm install -g n
  n 20.19.0
}

configure_anythingllm_nginx() {
  if ! command -v nginx >/dev/null 2>&1 || [ ! -f /etc/nginx/nginx.conf ]; then
    log "nginx is not available; AnythingLLM will listen on port $ANYTHINGLLM_PUBLIC_PORT directly."
    ANYTHINGLLM_INTERNAL_PORT="$ANYTHINGLLM_PUBLIC_PORT"
    return 0
  fi

  log "Adding nginx proxy from port $ANYTHINGLLM_PUBLIC_PORT to AnythingLLM port $ANYTHINGLLM_INTERNAL_PORT."
  python3 - /etc/nginx/nginx.conf "$ANYTHINGLLM_PUBLIC_PORT" "$ANYTHINGLLM_INTERNAL_PORT" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
port = sys.argv[2]
internal_port = sys.argv[3]
text = path.read_text()

def remove_matching_servers(src: str) -> str:
    out = []
    i = 0
    pattern = re.compile(r'(?m)^[ \t]*server[ \t]*\{')
    while True:
        match = pattern.search(src, i)
        if not match:
            out.append(src[i:])
            break
        start = match.start()
        brace = src.find("{", match.start(), match.end() + 1)
        depth = 0
        end = None
        j = brace
        while j < len(src):
            if src[j] == "{":
                depth += 1
            elif src[j] == "}":
                depth -= 1
                if depth == 0:
                    end = j + 1
                    break
            j += 1
        if end is None:
            out.append(src[i:])
            break
        block = src[start:end]
        if re.search(rf'(?m)^[ \t]*listen[ \t]+{re.escape(port)}(?:[ \t;]|$)', block):
            out.append(src[i:start])
        else:
            out.append(src[i:end])
        i = end
    return "".join(out)

cleaned = remove_matching_servers(text)
block = f"""
    # AnythingLLM comparison UI
    server {{
        listen {port};

        location / {{
            add_header Cache-Control no-cache;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_buffering off;
            proxy_cache off;
            proxy_connect_timeout 605;
            proxy_send_timeout 605;
            proxy_read_timeout 605;
            send_timeout 605;
            proxy_pass http://127.0.0.1:{internal_port};
        }}
    }}
"""
if "http {" in cleaned:
    cleaned = cleaned.replace("http {", "http {\n" + block, 1)
else:
    cleaned += "\nhttp {\n" + block + "\n}\n"
path.write_text(cleaned)
PY
  nginx -t
  nginx -s reload || service nginx restart || true
}

configure_anythingllm_env() {
  mkdir -p "$ANYTHINGLLM_STORAGE_DIR"
  python3 - \
    "$ANYTHINGLLM_DIR/server/.env" \
    "$ANYTHINGLLM_INTERNAL_PORT" \
    "http://127.0.0.1:${OLLAMA_UPSTREAM_HOST##*:}" \
    "$OLLAMA_MODEL" \
    "$RAG_EMBEDDING_MODEL" \
    "$ANYTHINGLLM_STORAGE_DIR" \
    "$ANYTHINGLLM_JWT_SECRET" <<'PY'
from pathlib import Path
import sys

env_path, port, ollama_url, model, embedding_model, storage_dir, jwt_secret = sys.argv[1:8]
path = Path(env_path)
lines = path.read_text().splitlines() if path.exists() else []
updates = {
    "LLM_PROVIDER": "'ollama'",
    "OLLAMA_BASE_PATH": f"'{ollama_url}'",
    "OLLAMA_MODEL_PREF": f"'{model}'",
    "OLLAMA_MODEL_TOKEN_LIMIT": "32768",
    "OLLAMA_RESPONSE_TIMEOUT": "7200000",
    "EMBEDDING_ENGINE": "'ollama'",
    "EMBEDDING_BASE_PATH": f"'{ollama_url}'",
    "EMBEDDING_MODEL_PREF": f"'{embedding_model}'",
    "EMBEDDING_MODEL_MAX_CHUNK_LENGTH": "8192",
    "SERVER_PORT": str(port),
    "STORAGE_DIR": f'"{storage_dir}"',
    "JWT_SECRET": f'"{jwt_secret}"',
}
seen = set()
out = []
for line in lines:
    key = line.split("=", 1)[0].strip().lstrip("#").strip() if "=" in line else ""
    if key in updates:
        if key not in seen:
            out.append(f"{key}={updates[key]}")
            seen.add(key)
        continue
    out.append(line)
for key, value in updates.items():
    if key not in seen:
        out.append(f"{key}={value}")
path.write_text("\n".join(out) + "\n")
PY
}

configure_anythingllm_frontend_env() {
  local env_path="$ANYTHINGLLM_DIR/frontend/.env"
  mkdir -p "$(dirname "$env_path")"
  python3 - "$env_path" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
lines = path.read_text().splitlines() if path.exists() else []
updates = {
    "VITE_API_BASE": "'/api'",
}
seen = set()
out = []
for line in lines:
    key = line.split("=", 1)[0].strip().lstrip("#").strip() if "=" in line else ""
    if key in updates:
        if key not in seen:
            out.append(f"{key}={updates[key]}")
            seen.add(key)
        continue
    out.append(line)
for key, value in updates.items():
    if key not in seen:
        out.append(f"{key}={value}")
path.write_text("\n".join(out) + "\n")
PY
}

configure_anythingllm_workspaces() {
  local db_path="$ANYTHINGLLM_STORAGE_DIR/anythingllm.db"
  if [ ! -f "$db_path" ]; then
    return 0
  fi

  log "Configuring AnythingLLM workspaces to use Ollama model $OLLAMA_MODEL."
  python3 - "$db_path" "$OLLAMA_MODEL" <<'PY'
import sqlite3
import sys
import time

db_path, model = sys.argv[1:3]
con = sqlite3.connect(db_path)
now = int(time.time() * 1000)
con.execute(
    "update workspaces set chatProvider = ?, chatModel = ?, "
    "agentProvider = ?, agentModel = ?, lastUpdatedAt = ?",
    ("ollama", model, "ollama", model, now),
)
con.commit()
PY
}

ensure_anythingllm() {
  case "$(printf '%s' "$ENABLE_ANYTHINGLLM" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes|y|on) ;;
    *)
      log "Skipping AnythingLLM because ENABLE_ANYTHINGLLM=$ENABLE_ANYTHINGLLM."
      return 0
      ;;
  esac

  ensure_node20_for_anythingllm || return 1
  command -v yarn >/dev/null 2>&1 || npm install -g yarn

  if [ -d "$ANYTHINGLLM_DIR/.git" ]; then
    log "Updating AnythingLLM at $ANYTHINGLLM_DIR."
    git -C "$ANYTHINGLLM_DIR" pull --rebase
  else
    log "Cloning AnythingLLM into $ANYTHINGLLM_DIR."
    git clone "$ANYTHINGLLM_REPO" "$ANYTHINGLLM_DIR"
  fi

  log "Installing AnythingLLM dependencies."
  export PATH="/usr/local/bin:$PATH"
  export PUPPETEER_SKIP_DOWNLOAD=true
  export PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
  cd "$ANYTHINGLLM_DIR"
  yarn setup
  configure_anythingllm_env
  configure_anythingllm_frontend_env

  log "Building AnythingLLM frontend."
  cd "$ANYTHINGLLM_DIR/frontend"
  yarn build
  rm -rf "$ANYTHINGLLM_DIR/server/public"
  cp -r "$ANYTHINGLLM_DIR/frontend/dist" "$ANYTHINGLLM_DIR/server/public"

  cd "$ANYTHINGLLM_DIR/server"
  yarn prisma generate
  yarn prisma migrate deploy || yarn prisma migrate reset --force --skip-seed || true

  configure_anythingllm_nginx
  configure_anythingllm_workspaces

  mkdir -p "$ANYTHINGLLM_DEPLOY_DIR/logs"
  cat > "$ANYTHINGLLM_DEPLOY_DIR/start-anythingllm.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
NODE20=/usr/local/bin/node
export PATH=/usr/local/bin:/usr/bin:/bin
export PUPPETEER_SKIP_DOWNLOAD=true
export PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
if [ -f "$ANYTHINGLLM_DEPLOY_DIR/server.pid" ]; then
  kill "\$(cat "$ANYTHINGLLM_DEPLOY_DIR/server.pid")" 2>/dev/null || true
fi
if [ -f "$ANYTHINGLLM_DEPLOY_DIR/collector.pid" ]; then
  kill "\$(cat "$ANYTHINGLLM_DEPLOY_DIR/collector.pid")" 2>/dev/null || true
fi
if command -v fuser >/dev/null 2>&1; then
  fuser -k ${ANYTHINGLLM_INTERNAL_PORT}/tcp 2>/dev/null || true
  fuser -k 8888/tcp 2>/dev/null || true
else
  pkill -f '/usr/local/bin/node index.js' 2>/dev/null || true
fi
sleep 1
cd "$ANYTHINGLLM_DIR/server"
set -a
. "$ANYTHINGLLM_DIR/server/.env"
set +a
export NODE_ENV=production
nohup "\$NODE20" index.js > "$ANYTHINGLLM_DEPLOY_DIR/logs/server.log" 2>&1 < /dev/null &
echo \$! > "$ANYTHINGLLM_DEPLOY_DIR/server.pid"
cd "$ANYTHINGLLM_DIR/collector"
nohup "\$NODE20" index.js > "$ANYTHINGLLM_DEPLOY_DIR/logs/collector.log" 2>&1 < /dev/null &
echo \$! > "$ANYTHINGLLM_DEPLOY_DIR/collector.pid"
EOF
  chmod +x "$ANYTHINGLLM_DEPLOY_DIR/start-anythingllm.sh"
  "$ANYTHINGLLM_DEPLOY_DIR/start-anythingllm.sh"
}

wait_for_anythingllm() {
  case "$(printf '%s' "$ENABLE_ANYTHINGLLM" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes|y|on) ;;
    *) return 0 ;;
  esac

  log "Waiting for AnythingLLM on http://localhost:$ANYTHINGLLM_PUBLIC_PORT."
  for _ in $(seq 1 180); do
    if curl -fsS "http://localhost:$ANYTHINGLLM_PUBLIC_PORT/api/ping" >/dev/null 2>&1; then
      log "AnythingLLM is ready."
      return 0
    fi
    sleep 1
  done

  log "AnythingLLM did not become ready within 180 seconds."
  return 1
}

auto_index_anythingllm_pdfs() {
  case "$(printf '%s' "$ENABLE_ANYTHINGLLM_PDF_AUTO_INDEX" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes|y|on) ;;
    *)
      log "Skipping AnythingLLM PDF auto-index because ENABLE_ANYTHINGLLM_PDF_AUTO_INDEX=$ENABLE_ANYTHINGLLM_PDF_AUTO_INDEX."
      return 0
      ;;
  esac

  if [ ! -f "$MEMORY_DIR/auto_index_anythingllm_pdfs.py" ]; then
    log "AnythingLLM PDF auto-index script is missing; skipping."
    return 0
  fi

  log "Starting AnythingLLM PDF auto-index for $ANYTHINGLLM_PDF_DIR."
  MEMORY_DIR="$MEMORY_DIR" \
    ANYTHINGLLM_DIR="$ANYTHINGLLM_DIR" \
    ANYTHINGLLM_STORAGE_DIR="$ANYTHINGLLM_STORAGE_DIR" \
    ANYTHINGLLM_URL="http://127.0.0.1:$ANYTHINGLLM_INTERNAL_PORT" \
    ANYTHINGLLM_API_KEY_FILE="$ANYTHINGLLM_API_KEY_FILE" \
    ANYTHINGLLM_PDF_DIR="$ANYTHINGLLM_PDF_DIR" \
    OLLAMA_MODEL="$OLLAMA_MODEL" \
    nohup python3 "$MEMORY_DIR/auto_index_anythingllm_pdfs.py" \
      > /tmp/anythingllm-pdf-auto-index.log 2>&1 &
}

start_autosync() {
  log "Starting memory autosync."
  nohup "$MEMORY_DIR/autosync_memory.sh" > /tmp/autosync-memory.log 2>&1 &
}

print_details() {
  cat <<EOF

Disposable RunPod AI pod is starting.

AnythingLLM:
  http://<RUNPOD_HOST_OR_PROXY>:${ANYTHINGLLM_PUBLIC_PORT}

Ollama API inside pod:
  http://localhost:11434

Ollama API from a trusted network or RunPod proxy:
  http://<RUNPOD_HOST_OR_PROXY>:11434

Local PC OpenClaw through SSH tunnel:
  ssh -L 11434:localhost:11434 <RUNPOD_SSH_CONNECTION>
  OLLAMA_BASE_URL=http://localhost:11434
  MODEL=${OLLAMA_MODEL}

Same-pod OpenClaw:
  OLLAMA_BASE_URL=http://localhost:11434
  MODEL=${OLLAMA_MODEL}

Combined context:
  ${COMBINED_CONTEXT}

Logs:
  /tmp/ollama.log
  /tmp/autosync-memory.log
  ${ANYTHINGLLM_DEPLOY_DIR}/logs/server.log
  ${ANYTHINGLLM_DEPLOY_DIR}/logs/collector.log
  /tmp/anythingllm-pdf-auto-index.log

Security:
  Do not expose Ollama publicly without protection. Prefer SSH tunnel, VPN,
  Tailscale, or Cloudflare Tunnel.

EOF
}

if [ "${START_ONLY_ANYTHINGLLM:-false}" = "true" ]; then
  ensure_anythingllm > /tmp/anythingllm-setup.log 2>&1 || {
    log "AnythingLLM setup failed. See /tmp/anythingllm-setup.log and ${ANYTHINGLLM_DEPLOY_DIR}/logs/server.log if it started."
    exit 1
  }
  wait_for_anythingllm
  auto_index_anythingllm_pdfs
  exit 0
fi

install_packages
ensure_repo
chmod +x "$MEMORY_DIR/start.sh" "$MEMORY_DIR/load_memory.sh" "$MEMORY_DIR/sync_memory.sh" "$MEMORY_DIR/autosync_memory.sh"
chmod +x "$MEMORY_DIR/auto_index_anythingllm_pdfs.py" 2>/dev/null || true
chmod +x "$MEMORY_DIR/query_anythingllm.py" "$MEMORY_DIR/anythingllm_query.sh" 2>/dev/null || true
chmod +x "$MEMORY_DIR/restore_rag_cache.sh" 2>/dev/null || true
chmod +x "$MEMORY_DIR/save_rag_cache.sh" 2>/dev/null || true
trap save_rag_cache_on_shutdown INT TERM
"$MEMORY_DIR/load_memory.sh"
ensure_ollama
start_ollama
wait_for_ollama
pull_model
pull_embedding_model || true
start_autosync
ensure_anythingllm > /tmp/anythingllm-setup.log 2>&1 || log "AnythingLLM setup failed. See /tmp/anythingllm-setup.log and ${ANYTHINGLLM_DEPLOY_DIR}/logs/server.log if it started."
restore_rag_cache
wait_for_anythingllm || true
auto_index_anythingllm_pdfs
(
  sleep "${RAG_S3_SAVE_DELAY_SECONDS:-900}"
  save_rag_cache
) &
if ensure_openclaw; then
  patch_openclaw_visible_no_reply || true
  configure_openclaw || true
  start_openclaw_gateway || true
else
  log "OpenClaw is not running. Continuing without OpenClaw gateway."
fi
print_details

wait
