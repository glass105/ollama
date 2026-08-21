# Brief Recreate Prompt

```text
You are Codex acting as a DevOps/AI infrastructure engineer.

Recreate my RunPod Ollama environment from:
https://github.com/glass105/ollama.git

Use the RunPod API key from:
C:\Users\joerc\OneDrive\Documents\ollama\.env

Use the project-local SSH public key as the pod `PUBLIC_KEY`:
C:\Users\joerc\OneDrive\Documents\ollama\.ssh\ollama_runpod_ed25519.pub

Before creating the pod, ask me:
"Do you want to include persistent RAG/vector storage for this pod creation?"

If I answer yes:
- Use RunPod S3/RAG cache ID `lp8wr68ped`.
- Do not attach RunPod network storage.
- Keep volumeInGb=0.
- Set `ENABLE_RAG_S3_CACHE=true` in the pod env.
- Use region `us-nc-1`.
- Use endpoint `https://s3api-us-nc-1.runpod.io`.
- Use bucket `lp8wr68ped`.
- Use prefix `ollama-rag-cache`.
- Set `RAG_S3_RETENTION_COUNT=2`, which keeps three tar files total when combined with the overwritten `latest/` archive.
- Restore/save only AnythingLLM RAG/vector snapshots and sanitized manifests, including safe workspace linkage needed to reconnect workspaces such as `Nokia` to restored LanceDB/vector state.
- Keep only three S3 tar files total: the overwritten `latest/` restore pointer plus the two newest historical snapshots.
- Never store models, secrets, keys, tokens, logs, auth DBs, OpenClaw runtime state, or general app caches in the RAG cache.
- S3 credentials must come from local env, RunPod secrets, or manual secure input; never commit them.

If I answer no:
- Set `ENABLE_RAG_S3_CACHE=false` in the pod env.
- Do not restore a RAG cache.
- Keep the setup disposable and rebuild AnythingLLM RAG/vector state from Git-backed PDFs/XLSX files on startup.

Approved GPUs only:
- NVIDIA RTX 4000 Ada Generation
- NVIDIA RTX A4000
- NVIDIA RTX A4500
- NVIDIA RTX A5000

If none are available, stop and ask before using another GPU.

Create pod:
- name: ollama-qwen3-coder-disposable
- imageName: runpod/pytorch:1.0.3-cu1281-torch291-ubuntu2404
- cloudType: SECURE
- computeType: GPU
- gpuCount: 1
- gpuTypePriority: custom
- containerDiskInGb: 120
- volumeInGb: 0
- no networkVolumeId
- ports: 3001/http, 18789/http, 19124/http, 22/tcp

Use qwen3-coder:30b as the default model.

Set env for Ollama, AnythingLLM, OpenClaw, the OpenClaw-only Ollama RAG proxy on port 11437, the opt-in equipment HTTPS bridge (`ENABLE_EQUIPMENT_HTTPS_BRIDGE=true`, port 19124), Git-backed Markdown memory, PDF/XLSX auto-indexing, and optional S3 RAG-cache restore/upload. Use generated token auth for both OpenClaw and the equipment bridge; save tokens only in local ignored files and pod `/tmp` paths, and never commit them.

Use the staged startup defaults:
- `START_BACKGROUND_SERVICES=true`
- `START_MODEL_PULL_IN_BACKGROUND=true`
- `WAIT_FOR_ANYTHINGLLM_BEFORE_OPENCLAW=false`
- `OPENCLAW_RAG_QUERY_TIMEOUT_SECONDS=90`
- `OPENCLAW_RAG_MAX_CONTEXT_CHARS=4000`
- `OPENCLAW_RAG_MAX_QUESTION_CHARS=2000`

Do not inject full Markdown memory, full PDF text, or full AnythingLLM answers into OpenClaw. AnythingLLM remains the RAG source of truth; OpenClaw should call the helper/proxy on demand and receive only concise retrieved context.

For easier OpenClaw login, set `OPENCLAW_PUBLIC_URL=https://<POD_ID>-18789.proxy.runpod.net` once the pod ID is known, set `OPENCLAW_GATEWAY_AUTH=token`, and save/print the pod helper file `/tmp/openclaw/dashboard-url` plus the local token file path.

Startup command:
cd /workspace && git clone https://github.com/glass105/ollama.git ollama-memory || true && cd /workspace/ollama-memory && git pull && chmod +x start.sh load_memory.sh sync_memory.sh autosync_memory.sh restore_rag_cache.sh save_rag_cache.sh auto_index_anythingllm_pdfs.py query_anythingllm.py anythingllm_query.sh openclaw_ollama_rag_proxy.py equipment_https_bridge.py equipment_bridge_client.py stop_equipment_https_bridge.sh && bash start.sh

Preserve RunPod SSH by launching /start.sh in the background before repo startup if needed.

Verify:
- volumeInGb is 0
- GPU is approved
- Ollama responds quickly after boot
- model pulls, AnythingLLM, and OpenClaw start in background and become healthy from their logs
- qwen3-coder:30b and qwen3-embedding:8b are installed
- /workspace/current_context.md exists
- AnythingLLM uses Ollama/qwen3-coder:30b
- OpenClaw uses the RAG proxy at `127.0.0.1:11437`
- `https://<POD_ID>-19124.proxy.runpod.net/health` returns the equipment bridge health response
- PDF/RAG state is restored from S3 cache or rebuilt/incrementally indexed from PDFs/XLSX files
- `bash /workspace/ollama-memory/anythingllm_query.sh Nokia "What can you answer from the CMM guide?"` returns an AnythingLLM RAG answer

Final output:
- Pod ID
- GPU used
- volumeInGb
- whether S3 RAG cache restore was used
- SSH command
- project-local SSH key path
- AnythingLLM URL
- OpenClaw Dashboard URL
- OpenClaw tokenized Dashboard URL from `/tmp/openclaw/dashboard-url`
- local secret file paths
- verification checklist
```
