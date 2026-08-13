# Recreate Disposable RunPod Pipeline Prompt

Use this prompt in a fresh Codex task to recreate the disposable RunPod AI pod setup.

```text
You are Codex acting as a DevOps/AI infrastructure engineer.

Goal: recreate my disposable RunPod AI pod setup from the GitHub repo:

https://github.com/glass105/ollama.git

Use the RunPod API key already stored in:
C:\Users\joerc\OneDrive\Documents\ollama\.env

Use the project-local SSH public key as the pod PUBLIC_KEY:
C:\Users\joerc\OneDrive\Documents\ollama\.ssh\ollama_runpod_ed25519.pub

Hard rules:
- Do not use RunPod network storage.
- Do not use persistent RunPod volume storage.
- Set RunPod volumeInGb=0.
- Do not store models, secrets, keys, tokens, logs, caches, databases, vector stores, or OpenClaw runtime state in GitHub.
- GitHub is only for scripts, configuration, prompts, Markdown memory, PDFs, spreadsheets, and images.
- The model can be re-downloaded when a fresh pod starts.
- Use qwen3-coder:30b as the default model.
- AnythingLLM is the primary web UI and RAG layer.
- Do not include Open WebUI in this setup.
- Approved RunPod GPUs only:
  - NVIDIA RTX 4000 Ada Generation
  - NVIDIA RTX A4000
  - NVIDIA RTX A4500
  - NVIDIA RTX A5000
- If none of those GPUs are available, stop and ask before using another GPU.

Pipeline:
1. Work from:
   C:\Users\joerc\OneDrive\Documents\ollama
2. Pull latest main from GitHub.
3. Verify scripts:
   - start.sh
   - load_memory.sh
   - ask_with_memory.sh
   - sync_memory.sh
   - autosync_memory.sh
   - restore_rag_cache.sh
   - save_rag_cache.sh
   - auto_index_anythingllm_pdfs.py
   - query_anythingllm.py
   - anythingllm_query.sh
   - openclaw_ollama_rag_proxy.py
4. Ensure memory loads locally with load_memory.sh.
5. Ask whether to enable the S3 RAG cache. If yes, use cache ID `lp8wr68ped`; if no, rebuild RAG from Git-backed PDFs/XLSX files.
6. Create a RunPod pod using REST API:
   - name: ollama-qwen3-coder-disposable
   - imageName: runpod/pytorch:1.0.3-cu1281-torch291-ubuntu2404
   - cloudType: SECURE
   - computeType: GPU
   - gpuCount: 1
   - gpuTypeIds:
     - NVIDIA RTX 4000 Ada Generation
     - NVIDIA RTX A4000
     - NVIDIA RTX A4500
     - NVIDIA RTX A5000
   - gpuTypePriority: custom
   - containerDiskInGb: 120
   - volumeInGb: 0
   - no networkVolumeId
   - ports:
     - 3001/http
     - 18789/http
     - 22/tcp
7. Include env:
   - GITHUB_MEMORY_REPO=https://github.com/glass105/ollama.git
   - GITHUB_BRANCH=main
   - PUBLIC_KEY=<contents of C:\Users\joerc\OneDrive\Documents\ollama\.ssh\ollama_runpod_ed25519.pub>
   - MEMORY_DIR=/workspace/ollama-memory
   - COMBINED_CONTEXT=/workspace/current_context.md
   - OLLAMA_MODEL=qwen3-coder:30b
   - OLLAMA_HOST=127.0.0.1:11434
   - ENABLE_MODEL_PULL=true
   - RAG_EMBEDDING_MODEL=nomic-embed-text:latest
   - ENABLE_ANYTHINGLLM=true
   - ENABLE_ANYTHINGLLM_PDF_AUTO_INDEX=true
   - ANYTHINGLLM_PUBLIC_PORT=3001
   - ANYTHINGLLM_INTERNAL_PORT=3010
   - ANYTHINGLLM_PDF_DIR=/workspace/ollama-memory/PDFS
   - SYNC_INTERVAL_SECONDS=1800
   - ENABLE_OPENCLAW=true
   - OPENCLAW_GATEWAY_PORT=18789
   - OPENCLAW_GATEWAY_BIND=lan
   - OPENCLAW_GATEWAY_AUTH=password
   - OPENCLAW_GATEWAY_PASSWORD_FILE=/tmp/openclaw/gateway-password
   - OPENCLAW_PUBLIC_URL=https://<POD_ID>-18789.proxy.runpod.net once the pod ID is known
   - OPENCLAW_DASHBOARD_URL_FILE=/tmp/openclaw/dashboard-url
   - ENABLE_OPENCLAW_RAG_PROXY=true
   - OPENCLAW_RAG_PROXY_PORT=11437
8. If S3 RAG cache is enabled, include:
   - ENABLE_RAG_S3_CACHE=true
   - RAG_S3_CACHE_ID=lp8wr68ped
   - RAG_S3_REGION=us-nc-1
   - RAG_S3_ENDPOINT=https://s3api-us-nc-1.runpod.io
   - RAG_S3_BUCKET=lp8wr68ped
   - RAG_S3_PREFIX=ollama-rag-cache
   - RAG_S3_ACCESS_KEY_ID=<secret, do not commit>
   - RAG_S3_SECRET_ACCESS_KEY=<secret, do not commit>
9. Use this pod startup command:
   cd /workspace && \
   git clone https://github.com/glass105/ollama.git ollama-memory || true && \
   cd /workspace/ollama-memory && \
   git pull && \
   chmod +x start.sh load_memory.sh sync_memory.sh autosync_memory.sh restore_rag_cache.sh save_rag_cache.sh auto_index_anythingllm_pdfs.py query_anythingllm.py anythingllm_query.sh openclaw_ollama_rag_proxy.py && \
   bash start.sh
10. If SSH is needed, preserve RunPod default startup by launching /start.sh in the background before the repo startup command.
11. Poll the pod until public IP and SSH port are available.
12. Verify inside the pod:
    - volumeInGb is 0 from RunPod API
    - nvidia-smi shows an approved GPU
    - /workspace/current_context.md exists
    - Ollama responds at localhost:11434
    - ollama list includes qwen3-coder:30b
    - ollama list includes nomic-embed-text:latest
    - AnythingLLM responds on localhost:3001
    - AnythingLLM uses Ollama/qwen3-coder:30b
    - AnythingLLM auto-indexed PDFs/XLSX files under PDFS/<folder>/ into matching workspaces
    - OpenClaw Ollama RAG proxy responds on localhost:11437
    - `bash /workspace/ollama-memory/anythingllm_query.sh Nokia "What can you answer from the CMM guide?"` returns an AnythingLLM RAG answer
    - OpenClaw gateway responds on localhost:18789
    - OpenClaw default model is ollama/qwen3-coder:30b
    - `bash /workspace/ollama-memory/ask_with_memory.sh "What is this pod setup?"` answers using the Markdown memory
13. Expose:
    - AnythingLLM:
      https://<POD_ID>-3001.proxy.runpod.net/
    - OpenClaw:
      https://<POD_ID>-18789.proxy.runpod.net/
14. For easier OpenClaw login, read and report:
    `/tmp/openclaw/dashboard-url`
    This contains the dashboard URL, WebSocket URL, auth mode, and pod-local password file path. Do not commit it.
15. If OpenClaw browser says "Browser origin not allowed," set:
    gateway.controlUi.allowedOrigins = [
      "https://<POD_ID>-18789.proxy.runpod.net"
    ]
    and restart the OpenClaw gateway.
16. If OpenClaw says "Device pairing required," run:
    openclaw devices approve <REQUEST_ID> --url ws://127.0.0.1:18789 --password "$(cat /tmp/openclaw/gateway-password)"
17. Final output must include:
    - Pod ID
    - GPU used
    - volumeInGb
    - whether S3 RAG cache was used
    - SSH command
    - project-local SSH key path
    - AnythingLLM URL
    - OpenClaw Dashboard URL
    - OpenClaw Dashboard URL from /tmp/openclaw/dashboard-url
    - where local secret files are saved
    - verification checklist

Save generated OpenClaw passwords locally only, for example:

C:\Users\joerc\OneDrive\Documents\ollama\tmp\openclaw_gateway_password.local.txt
```
