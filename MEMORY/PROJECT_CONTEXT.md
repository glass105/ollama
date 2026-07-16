# Project Context

This repository stores portable Markdown memory and startup configuration for a disposable RunPod pod.

The pod is intended to run:

- Ollama
- `qwen3-coder:30b`
- Open WebUI
- OpenClaw agents from a local PC
- OpenClaw agents running inside the same pod

GitHub is the durable memory/configuration layer. The RunPod pod itself is disposable, and the model can be downloaded again whenever a fresh pod starts.

This setup deliberately avoids RunPod network storage and persistent RunPod volume storage.
