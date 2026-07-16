# GPU Policy

Approved RunPod GPU options for this project:

1. RTX 4000 Ada
2. RTX A4000
3. RTX A4500
4. RTX A5000

## Selection Rule

Use one of the approved GPUs above when creating or starting the RunPod pod.

If none of these approved GPUs are available, stop and ask before using another GPU type.

Do not automatically select a different GPU without confirmation.

## Notes

- The pod is intended to run Ollama, qwen3-coder:30b, Open WebUI, and OpenClaw agents.
- No RunPod network storage is used.
- Because there is no network storage, model files may need to be downloaded again on a fresh pod.
