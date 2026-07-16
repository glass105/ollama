# Recreate Disposable RunPod Pipeline Prompt

Use this prompt in a fresh Codex task to recreate the disposable RunPod AI pod setup.

```text
You are Codex acting as a DevOps/AI infrastructure engineer.

Goal: recreate my disposable RunPod AI pod setup from the GitHub repo:

https://github.com/glass105/ollama.git

Use the RunPod API key already stored in:
C:\Users\joerc\OneDrive\Documents\AI-Karate\.env

Hard rules:
- Do not use RunPod network storage.
- Do not use persistent RunPod volume storage.
- Set RunPod volumeInGb=0.
- Do not store models, secrets, keys, tokens, logs, caches, databases, or OpenClaw runtime state in GitHub.
- GitHub is only for scripts, configuration, prompts, Markdown memory, PDFs, and images.
- The model can be re-downloaded when a fresh pod starts.
- Use qwen3-coder:30b as the default model.
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
   - sync_memory.sh
   - autosync_memory.sh
4. Ensure memory loads locally with load_memory.sh.
5. Create a RunPod pod using REST API:
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
   - ports:
     - 3000/http
     - 18789/http
     - 22/tcp
6. Include env:
   - GITHUB_MEMORY_REPO=https://github.com/glass105/ollama.git
   - GITHUB_BRANCH=main
   - MEMORY_DIR=/workspace/ollama-memory
   - COMBINED_CONTEXT=/workspace/current_context.md
   - OLLAMA_MODEL=qwen3-coder:30b
   - OLLAMA_HOST=0.0.0.0:11434
   - OPEN_WEBUI_PORT=3000
   - ENABLE_MODEL_PULL=true
   - SYNC_INTERVAL_SECONDS=1800
   - ENABLE_OPENCLAW=true
   - OPENCLAW_GATEWAY_PORT=18789
   - OPENCLAW_GATEWAY_BIND=lan
   - OPENCLAW_GATEWAY_AUTH=token
   - OPENCLAW_GATEWAY_TOKEN=<generate a random token locally, do not commit it>
7. Use this pod startup command:
   cd /workspace && \
   git clone https://github.com/glass105/ollama.git ollama-memory || true && \
   cd /workspace/ollama-memory && \
   git pull && \
   chmod +x start.sh load_memory.sh sync_memory.sh autosync_memory.sh && \
   bash start.sh
8. If SSH is needed, preserve RunPod default startup by launching /start.sh in the background before the repo startup command.
9. Poll the pod until public IP and SSH port are available.
10. Verify inside the pod:
    - volumeInGb is 0 from RunPod API
    - nvidia-smi shows an approved GPU
    - /workspace/current_context.md exists
    - ollama API responds at localhost:11434
    - ollama list includes qwen3-coder:30b
    - Open WebUI responds on localhost:3000
    - OpenClaw gateway responds on localhost:18789
    - OpenClaw default model is ollama/qwen3-coder:30b
11. Expose:
    - Open WebUI:
      https://<POD_ID>-3000.proxy.runpod.net/
    - OpenClaw:
      https://<POD_ID>-18789.proxy.runpod.net/
12. If OpenClaw browser says "Browser origin not allowed," set:
    gateway.controlUi.allowedOrigins = [
      "https://<POD_ID>-18789.proxy.runpod.net"
    ]
    and restart the OpenClaw gateway.
13. If RunPod proxy still fails origin checks, temporarily set:
    gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback=true
    but keep token auth enabled.
14. If OpenClaw says "Device pairing required," run:
    openclaw devices approve <REQUEST_ID> --url ws://127.0.0.1:18789 --token <TOKEN>
15. Final output must include:
    - Pod ID
    - GPU used
    - volumeInGb
    - SSH command
    - Open WebUI URL
    - OpenClaw Dashboard URL
    - where the local token file is saved
    - verification checklist

Save generated OpenClaw tokens locally only, for example:

C:\Users\joerc\OneDrive\Documents\ollama\tmp\openclaw_public_gateway_token.local.txt
```
