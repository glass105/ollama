# TODO

- Confirm the preferred RunPod base image includes CUDA support, Python, pip, Node, and enough system tools for Ollama and AnythingLLM.
- Confirm the selected RunPod GPU is one of: RTX 4000 Ada, RTX A4000, RTX A4500, RTX A5000.
- Confirm the AnythingLLM install method works on the selected base image.
- Confirm the OpenClaw connection method for local PC agents.
- Test local PC OpenClaw access through an SSH tunnel.
- Test same-pod OpenClaw access through `http://localhost:11434`.
- Verify `qwen3-coder:30b` pulls and runs acceptably on the selected GPU.
- Review memory changes before every push to GitHub.
- Consider splitting `PDFS/Nokia/` into separate `PDFS/CMM/` and `PDFS/CMG/` collections if retrieval continues to mix CMM and CMG answers.
- Test an AnythingLLM query against `cmm_cli_reference_guide.pdf` and `CMM_Alarms.xlsx` after each fresh pod/RAG-cache restore.
- Test OpenClaw calling `anythingllm_query.sh Nokia "<question>"` for CMM and CMG guide questions after each fresh pod launch.
- On future OpenClaw upgrades, retest whether password auth works correctly behind the RunPod proxy. Until then, keep tokenized dashboard auth as the supported path.
