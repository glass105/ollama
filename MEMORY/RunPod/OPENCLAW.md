# OpenClaw

## Same-Pod Connection

OpenClaw agents running inside the same RunPod pod should use:

```text
OLLAMA_BASE_URL=http://localhost:11434
MODEL=qwen3-coder:30b
```

## Local PC Connection Through SSH Tunnel

From the local PC, create an SSH tunnel to the RunPod pod:

```bash
ssh -L 11434:localhost:11434 <RUNPOD_SSH_CONNECTION>
```

Then local OpenClaw uses:

```text
OLLAMA_BASE_URL=http://localhost:11434
MODEL=qwen3-coder:30b
```

## AnythingLLM RAG Access

OpenClaw should use AnythingLLM indirectly through the local API helper for reference-document questions:

```bash
cd /workspace/ollama-memory
bash anythingllm_query.sh Nokia "Using cmm_cli_reference_guide.pdf, what command shows all interfaces?"
```

AnythingLLM remains the owner of ingestion, retrieval, workspaces, and source metadata. OpenClaw should not read LanceDB/vector files directly and should never print AnythingLLM API keys.
