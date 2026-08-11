# Disposable RunPod Ollama Setup

Minimal startup and memory setup for a disposable RunPod pod running Ollama, `qwen3-coder:30b`, Open WebUI, OpenClaw agents, and optional AnythingLLM.

## Architecture Overview

This repo is the durable, GitHub-backed layer for the pod:

- Startup scripts
- Lightweight configuration
- Markdown project memory
- System prompts
- Reference PDFs
- Reference images

The RunPod pod provides disposable compute. Ollama, Open WebUI, downloaded models, logs, caches, and databases live only on the pod filesystem and are expected to disappear when the pod is deleted.

## No Network Storage

This setup does not use RunPod network storage.

It also does not use persistent RunPod volume storage. A fresh pod can clone this repo, rebuild the runtime state, and pull `qwen3-coder:30b` again.

## What Is Lost When The Pod Is Deleted

- Downloaded Ollama models
- Open WebUI runtime data
- Logs
- Caches
- Local databases
- Any uncommitted pod-local changes

## What Survives In GitHub

- `README.md`
- `start.sh`
- `load_memory.sh`
- `sync_memory.sh`
- `autosync_memory.sh`
- `.env.example`
- Markdown memory in `MEMORY/OpenWebUI/` and `MEMORY/AnythingLLM/`
- Prompts in `PROMPTS/`
- PDFs in `PDFS/`
- Images in `IMAGES/`

Do not store secrets, model files, logs, caches, databases, or runtime state in GitHub.

## Approved RunPod GPUs

Use one of these GPUs:

- RTX 4000 Ada
- RTX A4000
- RTX A4500
- RTX A5000

If none are available, stop and ask before using another GPU.

## RunPod Startup Command

Use this as the pod startup command:

```bash
cd /workspace && \
git clone https://github.com/glass105/ollama.git ollama-memory || true && \
cd /workspace/ollama-memory && \
git pull && \
chmod +x start.sh load_memory.sh sync_memory.sh autosync_memory.sh && \
(chmod +x restore_rag_cache.sh save_rag_cache.sh auto_index_open_webui_pdfs.py auto_index_anythingllm_pdfs.py 2>/dev/null || true) && \
bash start.sh
```

The startup script:

1. Loads `.env` if present.
2. Installs `git` and `curl` if missing.
3. Clones or updates this repo in `/workspace/ollama-memory`.
4. Builds `/workspace/current_context.md`.
5. Starts Ollama.
6. Waits for Ollama on port `11434`.
7. Pulls `qwen3-coder:30b` when enabled.
8. Starts the pod-local Open WebUI memory proxy on port `11435`.
9. Starts Open WebUI on port `3000`.
10. Configures Open WebUI to use the memory proxy as its Ollama base URL.
11. Configures Open WebUI RAG embeddings to use Ollama for faster indexing.
12. Optionally bootstraps an Open WebUI admin.
13. Auto-indexes PDFs from each subdirectory in `PDFS/` into matching Open WebUI Knowledge collections.
14. Starts memory autosync.
15. Optionally installs and starts AnythingLLM on port `3001`.
16. Starts OpenClaw if enabled.
17. Prints connection details.

## Open WebUI Access

Open WebUI listens on port `3000`:

```text
http://<RUNPOD_HOST_OR_PROXY>:3000
```

Keep Open WebUI protected. Do not expose it broadly without an access control layer.

Open WebUI is pointed at a pod-local memory proxy on `http://localhost:11435`. The proxy forwards to Ollama on `http://localhost:11434` and injects `/workspace/current_context.md` into chat/generate requests. The proxy is pod-local only and does not store runtime state.

To bootstrap an administrator on each fresh pod, set:

```bash
OPEN_WEBUI_BOOTSTRAP_ADMIN=true
OPEN_WEBUI_ADMIN_EMAIL=joercoleman@mail.com
OPEN_WEBUI_ADMIN_NAME="Joseph Coleman"
```

If `OPEN_WEBUI_ADMIN_PASSWORD` is not set, startup generates a pod-local password and stores it at:

```text
/tmp/open-webui-admin-password
```

That password file is disposable pod runtime state and must not be committed to GitHub.

## Ollama API

Inside the pod:

```text
http://localhost:11434
```

Avoid exposing Ollama directly to the public internet.

Ollama does not automatically read `/workspace/current_context.md`. The memory file must be included in a prompt, proxy, system prompt, or agent/tool layer. For direct command-line use:

```bash
cd /workspace/ollama-memory
bash ask_with_memory.sh "Summarize the current project setup."
```

For Open WebUI, select `qwen3-coder:30b`. Memory is injected by the pod-local proxy, not by a separate model.

If Open WebUI answers as though it cannot see project memory, verify that its Ollama base URL is the memory proxy:

```text
http://localhost:11435
```

The proxy log is:

```text
/tmp/open-webui-memory-proxy.log
```

## Open WebUI RAG And PDF Auto-Index

Startup records and reapplies the speed settings that made the pod responsive:

- Chat memory proxy defaults to `OPEN_WEBUI_MEMORY_PROXY_NUM_CTX=8192`.
- Chat memory proxy defaults to `OPEN_WEBUI_MEMORY_PROXY_NUM_PREDICT=768`.
- Open WebUI RAG embeddings use Ollama instead of the slow local CPU sentence-transformer path.
- Default RAG embedding model is `nomic-embed-text:latest`.
- Default embedding batch size is `16`.

The embedding model is pulled at startup when fast RAG is enabled:

```bash
ENABLE_OPEN_WEBUI_FAST_RAG=true
OPEN_WEBUI_RAG_EMBEDDING_MODEL=nomic-embed-text:latest
```

PDF auto-indexing is enabled by default. It scans Git-backed PDF subdirectories in:

```text
PDFS/
```

Each immediate subdirectory becomes an Open WebUI Knowledge collection with the same name. For example:

```text
PDFS/Nokia/*.pdf -> Knowledge: Nokia
PDFS/Cisco/*.pdf -> Knowledge: Cisco
```

Top-level PDFs directly under `PDFS/` are skipped so the folder layout remains the source of truth.

```bash
ENABLE_OPEN_WEBUI_PDF_AUTO_INDEX=true
OPEN_WEBUI_PDF_KNOWLEDGE_DESCRIPTION_TEMPLATE="Git-backed PDF references from PDFS/{collection}"
```

The auto-indexer stores extracted text, Open WebUI upload records, Chroma vectors, and status data only in the pod-local Open WebUI runtime directory. Those generated runtime files are disposable and must not be committed.

The auto-index log is:

```text
/tmp/open-webui-pdf-auto-index.log
```

## AnythingLLM Comparison

AnythingLLM can be deployed beside Open WebUI for a separate RAG comparison layer.

Expose port `3001/http` on the RunPod pod and enable:

```bash
ENABLE_ANYTHINGLLM=true
ANYTHINGLLM_PUBLIC_PORT=3001
ANYTHINGLLM_INTERNAL_PORT=3010
```

Startup configures AnythingLLM to use the same local Ollama upstream as Open WebUI:

```text
LLM provider: Ollama
Ollama base URL: http://127.0.0.1:11436
Chat model: qwen3-coder:30b
Embedding provider: Ollama
Embedding model: nomic-embed-text:latest
```

AnythingLLM runtime data, workspace uploads, vector stores, logs, Node dependencies, and databases are disposable pod-local state. They must not be committed to GitHub.

AnythingLLM PDF auto-indexing can rebuild its disposable LanceDB vectors from Git-backed PDFs on each fresh pod:

```bash
ENABLE_ANYTHINGLLM=true
ENABLE_ANYTHINGLLM_PDF_AUTO_INDEX=true
ANYTHINGLLM_PDF_DIR=/workspace/ollama-memory/PDFS
```

The auto-indexer scans each immediate PDF subdirectory and creates or reuses an AnythingLLM workspace with the same name:

```text
PDFS/Nokia/*.pdf -> AnythingLLM workspace: Nokia
```

It generates a pod-local AnythingLLM API key in `/tmp/anythingllm-api-key`, uploads each PDF into its workspace, and lets AnythingLLM recreate the local LanceDB vector database. The API key and LanceDB data are disposable runtime state and must not be committed.

## Optional S3 RAG Cache

RunPod network volumes are not used by default. For portable RAG/vector reuse across datacenters, startup can optionally restore and save a sanitized RAG snapshot through RunPod's S3-compatible API.

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

The cache scripts store only vector/RAG-facing artifacts and sanitized manifests. They do not intentionally store model files, OpenClaw runtime state, logs, tokens, generated API keys, or full auth databases.

The AnythingLLM URL is:

```text
http://<RUNPOD_HOST_OR_PROXY>:3001
```

The logs are:

```text
/workspace/anythingllm-deploy/logs/server.log
/workspace/anythingllm-deploy/logs/collector.log
/tmp/anythingllm-pdf-auto-index.log
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

OpenClaw is configured to use `ollama/qwen3-coder:30b`, but agents still need to be instructed to use `/workspace/current_context.md` when project memory matters.

## Manual Sync

Run:

```bash
cd /workspace/ollama-memory
bash sync_memory.sh
```

Only these paths are added:

```text
README.md
MEMORY/*.md
MEMORY/**/*.md
PROMPTS/*.md
PDFS/*.md
PDFS/*.pdf
PDFS/**/*.md
PDFS/**/*.pdf
IMAGES/*.md
IMAGES/*.png
IMAGES/*.jpg
IMAGES/*.jpeg
IMAGES/*.webp
IMAGES/*.gif
IMAGES/*.svg
```

## Autosync

`autosync_memory.sh` runs every 30 minutes by default:

```bash
SYNC_INTERVAL_SECONDS=1800
```

It also runs one final sync on graceful shutdown.

Autosync depends on working GitHub authentication for pushes.

## PDFs And Images

Store lightweight PDF references in:

```text
PDFS/
```

Vendor-specific PDFs can be grouped in subdirectories such as:

```text
PDFS/Nokia/
```

Store lightweight image references in:

```text
IMAGES/
```

Do not store private documents, credential-bearing screenshots, large datasets, or model files in these folders.

## Troubleshooting

If Open WebUI does not start, check:

```bash
cat /tmp/open-webui.log
```

If Ollama does not start, check:

```bash
cat /tmp/ollama.log
curl http://localhost:11434/api/tags
```

If model pull fails, verify network access and disk space:

```bash
ollama pull qwen3-coder:30b
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
- Never commit `.env`, secrets, keys, tokens, logs, caches, databases, or model files.
- Review memory changes before pushing.
- Treat OpenClaw agents as high-privilege automation.
