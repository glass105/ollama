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
OLLAMA_UPSTREAM_HOST="${OLLAMA_UPSTREAM_HOST:-127.0.0.1:11436}"
OLLAMA_PROXY_PORT="${OLLAMA_PROXY_PORT:-11434}"
OPEN_WEBUI_PORT="${OPEN_WEBUI_PORT:-3000}"
OPEN_WEBUI_MEMORY_PROXY_PORT="${OPEN_WEBUI_MEMORY_PROXY_PORT:-11435}"
OPEN_WEBUI_BOOTSTRAP_ADMIN="${OPEN_WEBUI_BOOTSTRAP_ADMIN:-false}"
OPEN_WEBUI_ADMIN_EMAIL="${OPEN_WEBUI_ADMIN_EMAIL:-}"
OPEN_WEBUI_ADMIN_NAME="${OPEN_WEBUI_ADMIN_NAME:-}"
OPEN_WEBUI_ADMIN_PASSWORD_FILE="${OPEN_WEBUI_ADMIN_PASSWORD_FILE:-/tmp/open-webui-admin-password}"
ENABLE_MODEL_PULL="${ENABLE_MODEL_PULL:-true}"
OPEN_WEBUI_VENV="${OPEN_WEBUI_VENV:-/workspace/open-webui-venv}"
ENABLE_OPEN_WEBUI_FAST_RAG="${ENABLE_OPEN_WEBUI_FAST_RAG:-true}"
OPEN_WEBUI_RAG_EMBEDDING_MODEL="${OPEN_WEBUI_RAG_EMBEDDING_MODEL:-nomic-embed-text:latest}"
OPEN_WEBUI_RAG_EMBEDDING_BATCH_SIZE="${OPEN_WEBUI_RAG_EMBEDDING_BATCH_SIZE:-16}"
OPEN_WEBUI_RAG_EMBEDDING_CONCURRENT_REQUESTS="${OPEN_WEBUI_RAG_EMBEDDING_CONCURRENT_REQUESTS:-1}"
ENABLE_OPEN_WEBUI_PDF_AUTO_INDEX="${ENABLE_OPEN_WEBUI_PDF_AUTO_INDEX:-true}"
OPEN_WEBUI_PDF_KNOWLEDGE_DESCRIPTION_TEMPLATE="${OPEN_WEBUI_PDF_KNOWLEDGE_DESCRIPTION_TEMPLATE:-Git-backed PDF references from PDFS/{collection}}"
ENABLE_OPENCLAW="${ENABLE_OPENCLAW:-true}"
OPENCLAW_GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
OPENCLAW_GATEWAY_BIND="${OPENCLAW_GATEWAY_BIND:-loopback}"
OPENCLAW_GATEWAY_AUTH="${OPENCLAW_GATEWAY_AUTH:-token}"
OPENCLAW_ALLOWED_ORIGINS="${OPENCLAW_ALLOWED_ORIGINS:-}"
OPENCLAW_ALLOW_HOST_HEADER_ORIGIN_FALLBACK="${OPENCLAW_ALLOW_HOST_HEADER_ORIGIN_FALLBACK:-false}"

log() {
  echo "[start] $*"
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

ensure_open_webui() {
  if [ -x "$OPEN_WEBUI_VENV/bin/open-webui" ]; then
    return 0
  fi

  log "Open WebUI is not installed in $OPEN_WEBUI_VENV. Installing with pip."
  if command -v python3 >/dev/null 2>&1; then
    python3 -m venv "$OPEN_WEBUI_VENV"
    "$OPEN_WEBUI_VENV/bin/python" -m pip install --upgrade pip > /tmp/open-webui-install.log 2>&1
    "$OPEN_WEBUI_VENV/bin/python" -m pip install --no-cache-dir --upgrade open-webui >> /tmp/open-webui-install.log 2>&1
  elif command -v python >/dev/null 2>&1; then
    python -m venv "$OPEN_WEBUI_VENV"
    "$OPEN_WEBUI_VENV/bin/python" -m pip install --upgrade pip > /tmp/open-webui-install.log 2>&1
    "$OPEN_WEBUI_VENV/bin/python" -m pip install --no-cache-dir --upgrade open-webui >> /tmp/open-webui-install.log 2>&1
  else
    log "Python is required to install Open WebUI."
    return 1
  fi
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

configure_openclaw() {
  if ! command -v openclaw >/dev/null 2>&1; then
    return 1
  fi

  log "Configuring OpenClaw for local Ollama model $OLLAMA_MODEL."
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
        "contextWindow": 32768,
        "maxTokens": 8192,
        "models": [
          {
            "id": "$OLLAMA_MODEL",
            "name": "$OLLAMA_MODEL",
            "input": ["text"],
            "contextWindow": 32768,
            "maxTokens": 8192,
            "params": {
              "num_ctx": 32768,
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
  OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-}" nohup openclaw gateway \
    --bind "$OPENCLAW_GATEWAY_BIND" \
    --port "$OPENCLAW_GATEWAY_PORT" \
    --auth "$OPENCLAW_GATEWAY_AUTH" \
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
  case "$(printf '%s' "$ENABLE_OPEN_WEBUI_FAST_RAG" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes|y|on) ;;
    *)
      log "Skipping RAG embedding model pull because ENABLE_OPEN_WEBUI_FAST_RAG=$ENABLE_OPEN_WEBUI_FAST_RAG."
      return 0
      ;;
  esac

  log "Pulling Ollama embedding model $OPEN_WEBUI_RAG_EMBEDDING_MODEL."
  ollama pull "$OPEN_WEBUI_RAG_EMBEDDING_MODEL" || {
    log "Embedding model pull failed; Open WebUI may fall back to slower local embeddings."
    return 1
  }
}

start_open_webui() {
  log "Starting Open WebUI on port $OPEN_WEBUI_PORT."
  export OLLAMA_BASE_URL="http://localhost:$OLLAMA_PROXY_PORT"
  export WEBUI_AUTH="${WEBUI_AUTH:-True}"
  export DATA_DIR="${DATA_DIR:-/workspace/open-webui}"
  mkdir -p "$DATA_DIR"
  nohup "$OPEN_WEBUI_VENV/bin/open-webui" serve --host 0.0.0.0 --port "$OPEN_WEBUI_PORT" > /tmp/open-webui.log 2>&1 &
}

stop_open_webui() {
  pkill -f "$OPEN_WEBUI_VENV/bin/open-webui serve --host 0.0.0.0 --port $OPEN_WEBUI_PORT" 2>/dev/null || true
}

restart_open_webui() {
  log "Restarting Open WebUI so updated runtime configuration is active."
  stop_open_webui
  sleep 3
  start_open_webui
}

wait_for_open_webui() {
  log "Waiting for Open WebUI on http://localhost:$OPEN_WEBUI_PORT."
  for _ in $(seq 1 180); do
    if curl -fsS "http://localhost:$OPEN_WEBUI_PORT/api/version" >/dev/null 2>&1; then
      log "Open WebUI is ready."
      return 0
    fi
    sleep 1
  done

  log "Open WebUI did not become ready within 180 seconds."
  return 1
}

start_open_webui_memory_proxy() {
  if [ ! -f "$MEMORY_DIR/open_webui_memory_proxy.py" ]; then
    return 0
  fi

  log "Starting Open WebUI memory proxy on localhost:$OLLAMA_PROXY_PORT."
  COMBINED_CONTEXT="$COMBINED_CONTEXT" \
    OPEN_WEBUI_MEMORY_PROXY_PORT="$OLLAMA_PROXY_PORT" \
    OLLAMA_UPSTREAM_URL="http://$OLLAMA_UPSTREAM_HOST" \
    nohup python3 "$MEMORY_DIR/open_webui_memory_proxy.py" > /tmp/open-webui-memory-proxy-$OLLAMA_PROXY_PORT.log 2>&1 &
  if [ "$OPEN_WEBUI_MEMORY_PROXY_PORT" != "$OLLAMA_PROXY_PORT" ]; then
    log "Starting compatibility memory proxy on localhost:$OPEN_WEBUI_MEMORY_PROXY_PORT."
    COMBINED_CONTEXT="$COMBINED_CONTEXT" \
      OPEN_WEBUI_MEMORY_PROXY_PORT="$OPEN_WEBUI_MEMORY_PROXY_PORT" \
      OLLAMA_UPSTREAM_URL="http://$OLLAMA_UPSTREAM_HOST" \
      nohup python3 "$MEMORY_DIR/open_webui_memory_proxy.py" > /tmp/open-webui-memory-proxy.log 2>&1 &
  fi
}

configure_open_webui_fast_rag() {
  case "$(printf '%s' "$ENABLE_OPEN_WEBUI_FAST_RAG" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes|y|on) ;;
    *)
      log "Skipping fast Open WebUI RAG config because ENABLE_OPEN_WEBUI_FAST_RAG=$ENABLE_OPEN_WEBUI_FAST_RAG."
      return 0
      ;;
  esac

  log "Configuring Open WebUI RAG embeddings to use Ollama model $OPEN_WEBUI_RAG_EMBEDDING_MODEL."
  for _ in $(seq 1 60); do
    if [ -f "${DATA_DIR:-/workspace/open-webui}/webui.db" ]; then
      python3 - \
        "${DATA_DIR:-/workspace/open-webui}/webui.db" \
        "$OPEN_WEBUI_RAG_EMBEDDING_MODEL" \
        "$OPEN_WEBUI_RAG_EMBEDDING_BATCH_SIZE" \
        "$OPEN_WEBUI_RAG_EMBEDDING_CONCURRENT_REQUESTS" <<'PY' || true
import json
import sqlite3
import sys
import time

db_path, embedding_model, batch_size, concurrent_requests = sys.argv[1:5]
updates = {
    "rag.embedding_engine": "ollama",
    "rag.embedding_model": embedding_model,
    "rag.ollama.base_url": "http://localhost:11434",
    "rag.embedding_batch_size": int(batch_size),
    "rag.embedding_concurrent_requests": int(concurrent_requests),
    "rag.enable_async_embedding": True,
}
con = sqlite3.connect(db_path)
now = int(time.time())
for key, value in updates.items():
    con.execute(
        "insert into config (key, value, updated_at) values (?, ?, ?) "
        "on conflict(key) do update set value = excluded.value, updated_at = excluded.updated_at",
        (key, json.dumps(value), now),
    )
con.commit()
PY
      return 0
    fi
    sleep 1
  done

  log "Open WebUI database was not ready; skipping fast RAG configuration."
}

configure_open_webui_proxy_url() {
  log "Configuring Open WebUI to use memory proxy."
  for _ in $(seq 1 60); do
    if [ -f "${DATA_DIR:-/workspace/open-webui}/webui.db" ]; then
      python3 - "${DATA_DIR:-/workspace/open-webui}/webui.db" "$OLLAMA_PROXY_PORT" "$OLLAMA_MODEL" <<'PY' || true
import json
import sqlite3
import sys
import time

db_path, port, model = sys.argv[1:4]
con = sqlite3.connect(db_path)
now = int(time.time())
updates = {
    "ollama.base_urls": [f"http://localhost:{port}"],
    "openai.enable": False,
    "memories.enable": False,
    "memories.system_context.enable": False,
    "memories.background_review.enable": False,
    "models.default_metadata": {"capabilities": {"memory": False}},
    "ui.default_models": model,
    "ui.default_pinned_models": model,
}
for key, value in updates.items():
    con.execute(
        "insert into config (key, value, updated_at) values (?, ?, ?) "
        "on conflict(key) do update set value = excluded.value, updated_at = excluded.updated_at",
        (key, json.dumps(value), now),
    )
row = con.execute("select value from config where key = ?", ("user.permissions",)).fetchone()
try:
    permissions = json.loads(row[0]) if row and row[0] else {}
except Exception:
    permissions = {}
if not isinstance(permissions, dict):
    permissions = {}
features = permissions.setdefault("features", {})
if isinstance(features, dict):
    features["memories"] = False
con.execute(
    "insert into config (key, value, updated_at) values (?, ?, ?) "
    "on conflict(key) do update set value = excluded.value, updated_at = excluded.updated_at",
    ("user.permissions", json.dumps(permissions), now),
)
con.commit()
PY
      return 0
    fi
    sleep 1
  done

  log "Open WebUI database was not ready; skipping proxy URL configuration."
}

auto_index_open_webui_pdfs() {
  case "$(printf '%s' "$ENABLE_OPEN_WEBUI_PDF_AUTO_INDEX" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes|y|on) ;;
    *)
      log "Skipping Open WebUI PDF auto-index because ENABLE_OPEN_WEBUI_PDF_AUTO_INDEX=$ENABLE_OPEN_WEBUI_PDF_AUTO_INDEX."
      return 0
      ;;
  esac

  if [ ! -f "$MEMORY_DIR/auto_index_open_webui_pdfs.py" ]; then
    log "PDF auto-index script is missing; skipping."
    return 0
  fi

  log "Starting Open WebUI PDF auto-index for $MEMORY_DIR/PDFS."
  DATA_DIR="${DATA_DIR:-/workspace/open-webui}" \
    MEMORY_DIR="$MEMORY_DIR" \
    OPEN_WEBUI_URL="http://127.0.0.1:$OPEN_WEBUI_PORT" \
    OPEN_WEBUI_PDF_KNOWLEDGE_DESCRIPTION_TEMPLATE="$OPEN_WEBUI_PDF_KNOWLEDGE_DESCRIPTION_TEMPLATE" \
    WEBUI_SECRET_KEY_FILE="$MEMORY_DIR/.webui_secret_key" \
    nohup "$OPEN_WEBUI_VENV/bin/python" "$MEMORY_DIR/auto_index_open_webui_pdfs.py" \
      > /tmp/open-webui-pdf-auto-index.log 2>&1 &
}

bootstrap_open_webui_admin() {
  case "$(printf '%s' "$OPEN_WEBUI_BOOTSTRAP_ADMIN" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes|y|on) ;;
    *)
      return 0
      ;;
  esac

  if [ ! -f "$MEMORY_DIR/bootstrap_open_webui_admin.py" ]; then
    log "Open WebUI admin bootstrap script is missing; skipping admin bootstrap."
    return 0
  fi

  if [ -z "$OPEN_WEBUI_ADMIN_EMAIL" ]; then
    log "OPEN_WEBUI_BOOTSTRAP_ADMIN is enabled but OPEN_WEBUI_ADMIN_EMAIL is empty; skipping admin bootstrap."
    return 0
  fi

  log "Bootstrapping Open WebUI admin account for $OPEN_WEBUI_ADMIN_EMAIL."
  DATA_DIR="${DATA_DIR:-/workspace/open-webui}" \
    OPEN_WEBUI_BOOTSTRAP_ADMIN="$OPEN_WEBUI_BOOTSTRAP_ADMIN" \
    OPEN_WEBUI_ADMIN_EMAIL="$OPEN_WEBUI_ADMIN_EMAIL" \
    OPEN_WEBUI_ADMIN_NAME="$OPEN_WEBUI_ADMIN_NAME" \
    OPEN_WEBUI_ADMIN_PASSWORD="${OPEN_WEBUI_ADMIN_PASSWORD:-}" \
    OPEN_WEBUI_ADMIN_PASSWORD_FILE="$OPEN_WEBUI_ADMIN_PASSWORD_FILE" \
    "$OPEN_WEBUI_VENV/bin/python" "$MEMORY_DIR/bootstrap_open_webui_admin.py" || {
      log "Open WebUI admin bootstrap failed."
      return 1
    }
}

start_autosync() {
  log "Starting memory autosync."
  nohup "$MEMORY_DIR/autosync_memory.sh" > /tmp/autosync-memory.log 2>&1 &
}

print_details() {
  cat <<EOF

Disposable RunPod AI pod is starting.

Open WebUI:
  http://<RUNPOD_HOST_OR_PROXY>:${OPEN_WEBUI_PORT}

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
  /tmp/open-webui.log
  /tmp/autosync-memory.log

Open WebUI bootstrap admin:
  Email: ${OPEN_WEBUI_ADMIN_EMAIL:-disabled}
  Pod-local password file: ${OPEN_WEBUI_ADMIN_PASSWORD_FILE}

Security:
  Do not expose Ollama publicly without protection. Prefer SSH tunnel, VPN,
  Tailscale, or Cloudflare Tunnel.

EOF
}

install_packages
ensure_repo
chmod +x "$MEMORY_DIR/start.sh" "$MEMORY_DIR/load_memory.sh" "$MEMORY_DIR/sync_memory.sh" "$MEMORY_DIR/autosync_memory.sh"
chmod +x "$MEMORY_DIR/auto_index_open_webui_pdfs.py" 2>/dev/null || true
"$MEMORY_DIR/load_memory.sh"
ensure_ollama
start_ollama
wait_for_ollama
start_open_webui_memory_proxy
pull_model
pull_embedding_model || true
if ensure_open_webui; then
  start_open_webui
  wait_for_open_webui || true
  configure_open_webui_proxy_url
  configure_open_webui_fast_rag
  bootstrap_open_webui_admin || true
  case "$(printf '%s' "$ENABLE_OPEN_WEBUI_FAST_RAG" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes|y|on)
      restart_open_webui
      wait_for_open_webui || true
      ;;
  esac
  auto_index_open_webui_pdfs
else
  log "Open WebUI install failed. See /tmp/open-webui-install.log. Continuing with Ollama, SSH, and memory sync."
fi
start_autosync
if ensure_openclaw; then
  configure_openclaw || true
  start_openclaw_gateway || true
else
  log "OpenClaw is not running. Continuing without OpenClaw gateway."
fi
print_details

wait
