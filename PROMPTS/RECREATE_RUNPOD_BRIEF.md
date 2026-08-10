# Brief Recreate Prompt

```text
You are Codex acting as a DevOps/AI infrastructure engineer.

Recreate my RunPod Ollama environment from:
https://github.com/glass105/ollama.git

Use the RunPod API key from:
C:\Users\joerc\OneDrive\Documents\AI-Karate\.env

Before creating the pod, ask me:
"Do you want to attach RunPod network storage for persistent RAG/vector state?"

If I answer yes:
- Use networkVolumeId=390eu4ykoc.
- Keep volumeInGb=0.
- Mount the network volume at /runpod-volume.
- Use it only for RAG/vector state, not models, secrets, keys, tokens, logs, caches, DBs with auth data, or OpenClaw runtime state.
- Use a path such as /runpod-volume/ollama-rag-state.

If I answer no:
- Do not attach network storage.
- Keep the setup fully disposable and rebuild RAG/vector state on startup.

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
- ports: 3000/http, 3001/http, 18789/http, 22/tcp

Use qwen3-coder:30b as the default model.

Set env for Ollama, Open WebUI, AnythingLLM, OpenClaw, Git-backed Markdown memory, PDF auto-indexing, and admin bootstrap. Generate OpenClaw tokens locally and never commit them.

Startup command:
cd /workspace && git clone https://github.com/glass105/ollama.git ollama-memory || true && cd /workspace/ollama-memory && git pull && chmod +x start.sh load_memory.sh sync_memory.sh autosync_memory.sh auto_index_open_webui_pdfs.py auto_index_anythingllm_pdfs.py && bash start.sh

Preserve RunPod SSH by launching /start.sh in the background before repo startup if needed.

Verify:
- volumeInGb is 0
- GPU is approved
- Ollama upstream, memory proxy, Open WebUI, AnythingLLM, and OpenClaw respond
- qwen3-coder:30b and nomic-embed-text:latest are installed
- /workspace/current_context.md exists
- Open WebUI uses the memory proxy
- AnythingLLM uses Ollama/qwen3-coder:30b
- PDF/RAG state is loaded or incrementally indexed

Final output:
- Pod ID
- GPU used
- volumeInGb
- whether network storage was attached
- SSH command
- Open WebUI URL
- AnythingLLM URL
- OpenClaw Dashboard URL
- local secret file paths
- verification checklist
```
