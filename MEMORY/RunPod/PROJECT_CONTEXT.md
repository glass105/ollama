# Project Context

This repository stores portable Markdown memory and startup configuration for a disposable RunPod pod.

The pod is intended to run:

- Ollama
- `qwen3-coder:30b`
- AnythingLLM
- OpenClaw agents from a local PC
- OpenClaw agents running inside the same pod

GitHub is the durable memory/configuration layer. The RunPod pod itself is disposable, and the model can be downloaded again whenever a fresh pod starts.

This setup deliberately avoids RunPod network storage and persistent RunPod volume storage.

## Runtime Layout

- Ollama listens on `127.0.0.1:11434`.
- AnythingLLM listens internally on port `3010` and is exposed through nginx on port `3001`.
- OpenClaw gateway listens on port `18789`.

The current Markdown memory is built by `load_memory.sh` into `/workspace/current_context.md`. This context is not a true model fine-tune. Chat interfaces and agents must include it through their own prompt, tool, RAG, or context layer.

AnythingLLM is the primary browser UI and RAG layer for future pod launches.
