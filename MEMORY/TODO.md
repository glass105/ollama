# TODO

- Confirm the preferred RunPod base image includes CUDA support, Python, pip, and enough system tools for Ollama and Open WebUI.
- Confirm the selected RunPod GPU is one of: RTX 4000 Ada, RTX A4000, RTX A4500, RTX A5000.
- Confirm the Open WebUI install method works on the selected base image.
- Confirm the OpenClaw connection method for local PC agents.
- Test local PC OpenClaw access through an SSH tunnel.
- Test same-pod OpenClaw access through `http://localhost:11434`.
- Verify `qwen3-coder:30b` pulls and runs acceptably on the selected GPU.
- Review memory changes before every push to GitHub.
