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
- Restore/save only AnythingLLM RAG/vector snapshots and manifests.
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
- ports: 3001/http, 18789/http, 22/tcp

Use qwen3-coder:30b as the default model.

Set env for Ollama, AnythingLLM, OpenClaw, the OpenClaw-only Ollama RAG proxy on port 11437, Git-backed Markdown memory, PDF/XLSX auto-indexing, and optional S3 RAG-cache restore/upload. Use OpenClaw token auth, generate the token locally, save it only in local ignored files and `/tmp/openclaw/gateway-token`, and never commit it.

For easier OpenClaw login, set `OPENCLAW_PUBLIC_URL=https://<POD_ID>-18789.proxy.runpod.net` once the pod ID is known, set `OPENCLAW_GATEWAY_AUTH=token`, and save/print the pod helper file `/tmp/openclaw/dashboard-url` plus the local token file path.

Startup command:
cd /workspace && git clone https://github.com/glass105/ollama.git ollama-memory || true && cd /workspace/ollama-memory && git pull && chmod +x start.sh load_memory.sh sync_memory.sh autosync_memory.sh restore_rag_cache.sh save_rag_cache.sh auto_index_anythingllm_pdfs.py query_anythingllm.py anythingllm_query.sh && bash start.sh

Preserve RunPod SSH by launching /start.sh in the background before repo startup if needed.

Verify:
- volumeInGb is 0
- GPU is approved
- Ollama, AnythingLLM, and OpenClaw respond
- qwen3-coder:30b and nomic-embed-text:latest are installed
- /workspace/current_context.md exists
- AnythingLLM uses Ollama/qwen3-coder:30b
- OpenClaw uses the RAG proxy at `127.0.0.1:11437`
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
