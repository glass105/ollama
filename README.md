# Disposable RunPod Ollama Setup

Minimal startup and memory setup for a disposable RunPod pod running Ollama, `qwen3-coder:30b`, AnythingLLM, and OpenClaw agents.

## Architecture Overview

This repo is the durable, GitHub-backed layer for the pod:

- Startup scripts
- Lightweight configuration
- Markdown project memory
- System prompts
- Reference PDFs and spreadsheets
- Reference images

The RunPod pod provides disposable compute. Ollama, AnythingLLM runtime data, downloaded models, logs, caches, vector stores, and databases live only on the pod filesystem unless the optional S3 RAG cache is enabled.

## Storage Policy

This setup does not use RunPod network storage and does not use persistent RunPod volume storage. Keep `volumeInGb=0`.

GitHub stores scripts, configuration, prompts, Markdown memory, PDFs, spreadsheets, and images only. Do not commit secrets, model files, logs, caches, databases, vector stores, or runtime state.

## What Is Lost When The Pod Is Deleted

- Downloaded Ollama models
- AnythingLLM runtime data
- Pod-local LanceDB/vector state unless saved to the optional S3 RAG cache
- Logs
- Caches
- Local databases
- Any uncommitted pod-local changes

## What Survives

In GitHub:

- `README.md`
- Startup and sync scripts
- Markdown memory in `MEMORY/`
- Prompts in `PROMPTS/`
- PDFs and spreadsheets in `PDFS/`
- Images in `IMAGES/`

In optional S3 RAG cache:

- AnythingLLM RAG/vector snapshots and sanitized manifests only

## Approved RunPod GPUs

Use one of these GPUs:

- NVIDIA RTX 4000 Ada Generation
- NVIDIA RTX A4000
- NVIDIA RTX A4500
- NVIDIA RTX A5000

If none are available, stop and ask before using another GPU.

## RunPod Startup Command

Use this as the pod startup command:

```bash
cd /workspace && \
git clone https://github.com/glass105/ollama.git ollama-memory || true && \
cd /workspace/ollama-memory && \
git pull && \
chmod +x start.sh load_memory.sh sync_memory.sh autosync_memory.sh restore_rag_cache.sh save_rag_cache.sh auto_index_anythingllm_pdfs.py query_anythingllm.py anythingllm_query.sh && \
bash start.sh
```

## Project-Local SSH Key

Use the project-local SSH key for this setup:

```text
C:\Users\joerc\OneDrive\Documents\ollama\.ssh\ollama_runpod_ed25519
```

When creating a pod through the RunPod API, set the pod `PUBLIC_KEY` environment variable from:

```text
C:\Users\joerc\OneDrive\Documents\ollama\.ssh\ollama_runpod_ed25519.pub
```

The `.ssh/` folder is ignored by Git. Never commit SSH keys.

The startup script:

1. Loads `.env` if present.
2. Installs required system packages.
3. Clones or updates this repo in `/workspace/ollama-memory`.
4. Builds `/workspace/current_context.md`.
5. Starts Ollama.
6. Pulls `qwen3-coder:30b` and `nomic-embed-text:latest`.
7. Starts memory autosync.
8. Installs and starts AnythingLLM on port `3001`.
9. Restores optional S3 RAG cache if enabled.
10. Auto-indexes PDFs and XLSX workbooks from `PDFS/` into AnythingLLM workspaces.
11. Starts OpenClaw if enabled.
12. Prints connection details.

## AnythingLLM Access

AnythingLLM is the primary UI and RAG layer. Expose port `3001/http` on the RunPod pod:

```text
http://<RUNPOD_HOST_OR_PROXY>:3001
```

Startup configures AnythingLLM to use local Ollama:

```text
LLM provider: Ollama
Ollama base URL: http://127.0.0.1:11434
Chat model: qwen3-coder:30b
Embedding provider: Ollama
Embedding model: nomic-embed-text:latest
```

AnythingLLM runtime data, workspace uploads, vector stores, logs, Node dependencies, and databases are disposable pod-local state. They must not be committed to GitHub.

## AnythingLLM Reference Auto-Index

Reference auto-indexing is enabled by default:

```bash
ENABLE_ANYTHINGLLM=true
ENABLE_ANYTHINGLLM_PDF_AUTO_INDEX=true
ANYTHINGLLM_PDF_DIR=/workspace/ollama-memory/PDFS
RAG_EMBEDDING_MODEL=nomic-embed-text:latest
```

The auto-indexer scans each immediate reference subdirectory and creates or reuses an AnythingLLM workspace with the same name:

```text
PDFS/Nokia/*.pdf, PDFS/Nokia/*.xlsx -> AnythingLLM workspace: Nokia
```

It generates a pod-local AnythingLLM API key in `/tmp/anythingllm-api-key`, uploads each reference into its workspace, and lets AnythingLLM recreate the local LanceDB vector database. XLSX files are converted to Markdown text before upload so alarms and tables can be embedded.

Logs:

```text
/workspace/anythingllm-deploy/logs/server.log
/workspace/anythingllm-deploy/logs/collector.log
/tmp/anythingllm-pdf-auto-index.log
```

## Optional S3 RAG Cache

For portable RAG/vector reuse across fresh pods, startup can optionally restore and save an AnythingLLM RAG snapshot through RunPod's S3-compatible API.

The selected cache target is:

```bash
RAG_S3_REGION=us-nc-1
RAG_S3_ENDPOINT=https://s3api-us-nc-1.runpod.io
RAG_S3_BUCKET=lp8wr68ped
RAG_S3_PREFIX=ollama-rag-cache
```

Enable it only when S3 credentials are provided securely:

```bash
ENABLE_RAG_S3_CACHE=true
RAG_S3_ACCESS_KEY_ID=<secret>
RAG_S3_SECRET_ACCESS_KEY=<secret>
```

The cache scripts store only AnythingLLM vector/RAG-facing artifacts and sanitized manifests. They do not intentionally store model files, OpenClaw runtime state, logs, tokens, generated API keys, full auth databases, or general caches.

## Ollama API

Inside the pod:

```text
http://localhost:11434
```

Avoid exposing Ollama directly to the public internet.

Ollama does not automatically read `/workspace/current_context.md`. The memory file must be included in a prompt, system prompt, or agent/tool layer. For direct command-line use:

```bash
cd /workspace/ollama-memory
bash ask_with_memory.sh "Summarize the current project setup."
```

## OpenClaw Local PC Access

Create an SSH tunnel from the local PC:

```bash
ssh -L 11434:localhost:11434 <RUNPOD_SSH_CONNECTION>
```

Then configure local OpenClaw:

```text
OLLAMA_BASE_URL=http://localhost:11434
MODEL=qwen3-coder:30b
```

## OpenClaw Same-Pod Access

For OpenClaw agents running inside the same pod:

```text
OLLAMA_BASE_URL=http://localhost:11434
MODEL=qwen3-coder:30b
```

OpenClaw is configured to use `ollama/qwen3-coder:30b`, with a 66k context window and visible direct WebChat replies.

## OpenClaw Dashboard Login

Use password auth for the public RunPod proxy. Startup writes a pod-local helper file with the dashboard URL, WebSocket URL, auth mode, and pod-local password file path:

```bash
cat /tmp/openclaw/dashboard-url
```

If the pod exposes OpenClaw through the normal RunPod proxy, set `OPENCLAW_PUBLIC_URL` to:

```text
https://<POD_ID>-18789.proxy.runpod.net
```

When `OPENCLAW_PUBLIC_URL` or a RunPod pod-id environment variable is available, startup also adds that origin to `gateway.controlUi.allowedOrigins` so the browser does not hit the origin allowlist error.

## OpenClaw And AnythingLLM RAG

OpenClaw does not read the AnythingLLM LanceDB/vector database directly. It should call the local AnythingLLM API helper and let AnythingLLM handle retrieval:

```bash
cd /workspace/ollama-memory
bash anythingllm_query.sh Nokia "Using cmm_cli_reference_guide.pdf, what command shows all interfaces?"
```

For CMM, CMG, Nokia, PDF, XLSX, command, interface, alarm, guide, and reference questions, OpenClaw is instructed to run that helper first, then answer from the returned AnythingLLM response and source metadata. OpenClaw should not answer these from model memory. The helper uses the pod-local AnythingLLM API key at `/tmp/anythingllm-api-key` and must not print or commit it.

Startup also runs an OpenClaw-only Ollama RAG proxy on `127.0.0.1:11437`. OpenClaw is configured to use that proxy as its Ollama base URL. The proxy detects CMM/CMG/Nokia/reference prompts, asks AnythingLLM first, injects the returned RAG answer as mandatory context, and then forwards the request to real Ollama on `127.0.0.1:11434`. AnythingLLM continues to use real Ollama directly, so there is no retrieval loop.

## Manual Sync

Run:

```bash
cd /workspace/ollama-memory
bash sync_memory.sh
```

Only approved Git-backed memory/config/reference assets are added.

## Autosync

`autosync_memory.sh` runs every 30 minutes by default:

```bash
SYNC_INTERVAL_SECONDS=1800
```

It also runs one final sync on graceful shutdown.

## PDFs, Spreadsheets, And Images

Store lightweight PDF and spreadsheet references in:

```text
PDFS/
```

Vendor-specific references can be grouped in subdirectories such as:

```text
PDFS/Nokia/
```

Store lightweight image references in:

```text
IMAGES/
```

Do not store private documents, credential-bearing screenshots, large datasets, vector stores, or model files in these folders.

## Troubleshooting

If AnythingLLM does not start, check:

```bash
cat /workspace/anythingllm-deploy/logs/server.log
cat /workspace/anythingllm-deploy/logs/collector.log
```

If Ollama does not start, check:

```bash
cat /tmp/ollama.log
curl http://localhost:11434/api/tags
```

If model pull fails, verify network access and disk space:

```bash
ollama pull qwen3-coder:30b
ollama pull nomic-embed-text:latest
```

If memory sync fails, verify GitHub auth and branch state:

```bash
git status
git pull --rebase origin main
bash sync_memory.sh
```

## Security Warnings

- Do not expose Ollama publicly without auth.
- Prefer SSH tunnel, VPN, Tailscale, or Cloudflare Tunnel.
- Never commit `.env`, secrets, keys, tokens, logs, caches, databases, vector stores, or model files.
- Review memory changes before pushing.
- Treat OpenClaw agents as high-privilege automation.
