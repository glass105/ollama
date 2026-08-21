# Recreate RunPod Pipeline Prompt

```text
You are Codex acting as a DevOps/AI infrastructure engineer.

Recreate my RunPod Ollama environment from:
https://github.com/glass105/ollama.git

Use the RunPod API key from:
C:\Users\joerc\OneDrive\Documents\ollama\.env

Before creating the pod, ask:
"Do you want to restore persistent RAG/vector state from S3?"

If yes:
- Set ENABLE_RAG_S3_CACHE=true.
- Use RunPod S3 cache:
  - region: us-nc-1
  - endpoint: https://s3api-us-nc-1.runpod.io
  - bucket: lp8wr68ped
  - prefix: ollama-rag-cache
- Use S3 only for AnythingLLM RAG/vector snapshots, LanceDB, document/vector cache files, and sanitized workspace manifests.
- Keep only three tar files total: latest plus two historical snapshots.
- Do not store models, secrets, keys, tokens, logs, auth DBs, OpenClaw runtime state, or general caches in S3 or Git.

If no:
- Set ENABLE_RAG_S3_CACHE=false.
- Rebuild AnythingLLM RAG from Git-backed PDFs/XLSX files.

Rules:
- No RunPod network storage.
- No persistent pod volume.
- volumeInGb=0.
- No networkVolumeId.
- Approved GPUs only:
  - NVIDIA RTX 4000 Ada Generation
  - NVIDIA RTX A4000
  - NVIDIA RTX A4500
  - NVIDIA RTX A5000
- If none are available, stop and ask.
- Default model: qwen3-coder:30b.

Create pod:
- name: ollama-qwen3-coder-disposable
- imageName: runpod/pytorch:1.0.3-cu1281-torch291-ubuntu2404
- cloudType: SECURE
- computeType: GPU
- gpuCount: 1
- gpuTypePriority: custom
- containerDiskInGb: 120
- volumeInGb: 0
- ports: 3001/http, 18789/http, 19124/http, 22/tcp

Use the project-local SSH public key as PUBLIC_KEY:
C:\Users\joerc\OneDrive\Documents\ollama\.ssh\ollama_runpod_ed25519.pub

Set env for Ollama, AnythingLLM, OpenClaw, the OpenClaw RAG proxy on 11437, Git-backed Markdown memory, PDF/XLSX auto-indexing, optional S3 restore/save, and optional equipment HTTPS bridge.

Use staged startup:
- START_BACKGROUND_SERVICES=true
- START_MODEL_PULL_IN_BACKGROUND=true
- WAIT_FOR_ANYTHINGLLM_BEFORE_OPENCLAW=false
- OPENCLAW_RAG_QUERY_TIMEOUT_SECONDS=90
- OPENCLAW_RAG_MAX_CONTEXT_CHARS=4000
- OPENCLAW_RAG_MAX_QUESTION_CHARS=2000

Generate OpenClaw and bridge tokens locally. Save secrets only in ignored local files and pod /tmp paths. Never commit secrets.

Startup command:
cd /workspace && git clone https://github.com/glass105/ollama.git ollama-memory || true && cd /workspace/ollama-memory && git pull && chmod +x start.sh load_memory.sh sync_memory.sh autosync_memory.sh restore_rag_cache.sh save_rag_cache.sh auto_index_anythingllm_pdfs.py query_anythingllm.py anythingllm_query.sh openclaw_ollama_rag_proxy.py equipment_https_bridge.py equipment_bridge_client.py stop_equipment_https_bridge.sh && bash start.sh

Verify:
- volumeInGb is 0
- GPU is approved
- Ollama responds on 127.0.0.1:11434
- AnythingLLM responds on port 3001
- qwen3-coder:30b and qwen3-embedding:8b are installed
- /workspace/current_context.md exists
- AnythingLLM uses Ollama/qwen3-coder:30b
- Nokia workspace is restored or rebuilt
- `bash /workspace/ollama-memory/anythingllm_query.sh Nokia "What command lists all CMM interfaces?"` returns a RAG-grounded answer
- OpenClaw responds on port 18789
- OpenClaw uses the RAG proxy at 127.0.0.1:11437

Final output:
- Pod ID
- GPU used
- volumeInGb
- whether S3 RAG cache was restored
- SSH command
- AnythingLLM URL
- OpenClaw Dashboard URL
- OpenClaw tokenized Dashboard URL
- local secret file paths
- verification checklist
```
