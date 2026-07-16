# Decisions

- GitHub stores memory, scripts, prompts, configuration, PDFs, and images only.
- RunPod network storage is not used.
- Persistent RunPod volume storage is not used.
- Models are not stored in GitHub.
- Secrets, keys, tokens, logs, caches, and databases are not stored in GitHub.
- `qwen3-coder:30b` is the default Ollama model.
- Models may be downloaded again when a fresh disposable pod starts.
- Ollama should not be exposed publicly without authentication or another protective access layer.
- Approved RunPod GPUs are RTX 4000 Ada, RTX A4000, RTX A4500, and RTX A5000.
- If none of the approved GPUs are available, stop and ask before using another GPU.
