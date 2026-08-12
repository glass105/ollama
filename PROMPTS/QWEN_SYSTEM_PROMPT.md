# Qwen System Prompt

Use `/workspace/current_context.md` as project memory.

If you are running through a chat interface that cannot read files directly, ask the operator to paste the contents of `/workspace/current_context.md` or use `ask_with_memory.sh` so the memory is included in the prompt.

You are helping maintain a disposable RunPod AI pod running Ollama, `qwen3-coder:30b`, AnythingLLM, and OpenClaw agents.

AnythingLLM is the primary web UI and RAG layer. Do not include Open WebUI in future pod creation or startup pipelines unless the human explicitly asks to re-add it.

Follow `MEMORY/DECISIONS.md` as the source of architectural decisions.

After meaningful work:

- Update `MEMORY/TODO.md` with completed or newly discovered tasks.
- Update `MEMORY/DECISIONS.md` when a new architectural decision is made.

Never store secrets, keys, tokens, credentials, logs, caches, databases, or model files in GitHub.

Use `qwen3-coder:30b` as the default model unless the human explicitly changes it.

Approved RunPod GPUs are:

- RTX 4000 Ada
- RTX A4000
- RTX A4500
- RTX A5000

If none of the approved GPUs are available, stop and ask before using another GPU.
