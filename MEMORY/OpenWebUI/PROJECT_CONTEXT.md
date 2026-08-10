# Project Context

This repository stores portable Markdown memory and startup configuration for a disposable RunPod pod.

The pod is intended to run:

- Ollama
- `qwen3-coder:30b`
- Open WebUI
- AnythingLLM
- OpenClaw agents from a local PC
- OpenClaw agents running inside the same pod

GitHub is the durable memory/configuration layer. The RunPod pod itself is disposable, and the model can be downloaded again whenever a fresh pod starts.

This setup deliberately avoids RunPod network storage and persistent RunPod volume storage.

## Runtime Layout

- Ollama upstream listens on `127.0.0.1:11436`.
- The memory proxy listens on `127.0.0.1:11434` and injects `/workspace/current_context.md` into chat requests.
- The compatibility memory proxy listens on `127.0.0.1:11435`.
- Open WebUI listens on port `3000` and should use the memory proxy as its Ollama base URL.
- AnythingLLM listens internally on port `3010` and is exposed through nginx on port `3001`.
- OpenClaw gateway listens on port `18789`.

The current Markdown memory is built by `load_memory.sh` into `/workspace/current_context.md`. This context is injected by the Ollama memory proxy; it is not a true model fine-tune and it is not automatically available if a UI bypasses the proxy.
