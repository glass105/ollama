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
OLLAMA_HOST="${OLLAMA_HOST:-0.0.0.0:11434}"
OPEN_WEBUI_PORT="${OPEN_WEBUI_PORT:-3000}"
ENABLE_MODEL_PULL="${ENABLE_MODEL_PULL:-true}"
OPEN_WEBUI_VENV="${OPEN_WEBUI_VENV:-/workspace/open-webui-venv}"
ENABLE_OPENCLAW="${ENABLE_OPENCLAW:-true}"
OPENCLAW_GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
OPENCLAW_GATEWAY_BIND="${OPENCLAW_GATEWAY_BIND:-loopback}"
OPENCLAW_GATEWAY_AUTH="${OPENCLAW_GATEWAY_AUTH:-token}"

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
    git -C "$MEMORY_DIR" pull --rebase origin "$GITHUB_BRANCH"
  else
    log "Cloning memory repo into $MEMORY_DIR."
    mkdir -p "$(dirname "$MEMORY_DIR")"
    git clone --branch "$GITHUB_BRANCH" "$GITHUB_MEMORY_REPO" "$MEMORY_DIR"
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
  cat > /tmp/openclaw-ollama.patch.json <<EOF
{
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

  log "Starting OpenClaw gateway on $OPENCLAW_GATEWAY_BIND:$OPENCLAW_GATEWAY_PORT with auth=$OPENCLAW_GATEWAY_AUTH."
  nohup openclaw gateway run \
    --bind "$OPENCLAW_GATEWAY_BIND" \
    --port "$OPENCLAW_GATEWAY_PORT" \
    --auth "$OPENCLAW_GATEWAY_AUTH" \
    --token "${OPENCLAW_GATEWAY_TOKEN:-}" \
    --allow-unconfigured \
    > /tmp/openclaw/gateway.log 2>&1 &
}

wait_for_ollama() {
  log "Waiting for Ollama on http://localhost:11434."
  for _ in $(seq 1 120); do
    if curl -fsS http://localhost:11434/api/tags >/dev/null 2>&1; then
      log "Ollama is ready."
      return 0
    fi
    sleep 1
  done

  log "Ollama did not become ready within 120 seconds."
  exit 1
}

start_ollama() {
  log "Starting Ollama with OLLAMA_HOST=$OLLAMA_HOST."
  export OLLAMA_HOST
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

start_open_webui() {
  log "Starting Open WebUI on port $OPEN_WEBUI_PORT."
  export OLLAMA_BASE_URL="http://localhost:11434"
  export WEBUI_AUTH="${WEBUI_AUTH:-True}"
  export DATA_DIR="${DATA_DIR:-/workspace/open-webui}"
  mkdir -p "$DATA_DIR"
  nohup "$OPEN_WEBUI_VENV/bin/open-webui" serve --host 0.0.0.0 --port "$OPEN_WEBUI_PORT" > /tmp/open-webui.log 2>&1 &
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

Security:
  Do not expose Ollama publicly without protection. Prefer SSH tunnel, VPN,
  Tailscale, or Cloudflare Tunnel.

EOF
}

install_packages
ensure_repo
chmod +x "$MEMORY_DIR/start.sh" "$MEMORY_DIR/load_memory.sh" "$MEMORY_DIR/sync_memory.sh" "$MEMORY_DIR/autosync_memory.sh"
"$MEMORY_DIR/load_memory.sh"
ensure_ollama
start_ollama
wait_for_ollama
pull_model
if ensure_open_webui; then
  start_open_webui
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
