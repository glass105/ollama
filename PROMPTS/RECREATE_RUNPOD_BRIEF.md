# Brief Recreate Prompt

```text
You are Codex acting as a DevOps/AI infrastructure engineer.

Recreate my RunPod Ollama environment from:
https://github.com/glass105/ollama.git

Use the RunPod API key from:
C:\Users\joerc\OneDrive\Documents\AI-Karate\.env

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
- Restore the RAG/vector snapshot from S3-compatible object storage into pod-local paths.
- Use object storage only for RAG/vector snapshots and manifests.
- Do not store models, secrets, keys, tokens, logs, auth DBs, OpenClaw runtime state, or general app caches in the RAG cache.
- S3 credentials must come from local env, RunPod secrets, or manual secure input; never commit them.

If I answer no:
- Set `ENABLE_RAG_S3_CACHE=false` in the pod env.
- Do not restore a RAG cache.
- Keep the setup fully disposable and rebuild RAG/vector state from Git-backed PDFs on startup.

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
- ports: 3000/http, 3001/http, 18789/http, 22/tcp

Use qwen3-coder:30b as the default model.

Set env for Ollama, Open WebUI, AnythingLLM, OpenClaw, Git-backed Markdown memory, PDF auto-indexing, optional S3 RAG-cache restore/upload, and admin bootstrap. Generate OpenClaw tokens locally and never commit them.

If S3 RAG cache is enabled, include:
- ENABLE_RAG_S3_CACHE=true
- RAG_S3_CACHE_ID=lp8wr68ped
- RAG_S3_REGION=us-nc-1
- RAG_S3_ENDPOINT=https://s3api-us-nc-1.runpod.io
- RAG_S3_BUCKET=lp8wr68ped
- RAG_S3_PREFIX=ollama-rag-cache
- RAG_S3_ACCESS_KEY_ID=<secret, do not commit>
- RAG_S3_SECRET_ACCESS_KEY=<secret, do not commit>

Startup command:
cd /workspace && git clone https://github.com/glass105/ollama.git ollama-memory || true && cd /workspace/ollama-memory && git pull && chmod +x start.sh load_memory.sh sync_memory.sh autosync_memory.sh restore_rag_cache.sh save_rag_cache.sh auto_index_open_webui_pdfs.py auto_index_anythingllm_pdfs.py && bash start.sh

Preserve RunPod SSH by launching /start.sh in the background before repo startup if needed.

Verify:
- volumeInGb is 0
- GPU is approved
- Ollama upstream, memory proxy, Open WebUI, AnythingLLM, and OpenClaw respond
- qwen3-coder:30b and nomic-embed-text:latest are installed
- /workspace/current_context.md exists
- Open WebUI uses the memory proxy
- AnythingLLM uses Ollama/qwen3-coder:30b
- PDF/RAG state is restored from S3 cache or rebuilt/incrementally indexed from PDFs

Final output:
- Pod ID
- GPU used
- volumeInGb
- whether S3 RAG cache restore was used
- SSH command
- Open WebUI URL
- AnythingLLM URL
- OpenClaw Dashboard URL
- local secret file paths
- verification checklist
```
