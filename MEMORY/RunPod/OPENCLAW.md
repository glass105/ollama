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

For CMM, CMG, Nokia, PDF, XLSX, command, interface, alarm, guide, or reference questions, OpenClaw must run the helper before answering. If it cannot run the helper, it should say the helper failed instead of inventing commands from model memory. OpenClaw should not mention Open WebUI because Open WebUI is no longer part of the active pipeline.

Startup also runs an OpenClaw-only Ollama RAG proxy on `127.0.0.1:11437`. OpenClaw should use that as its Ollama provider base URL. The proxy injects AnythingLLM RAG output into CMM/CMG/Nokia/reference prompts before forwarding to real Ollama on `127.0.0.1:11434`.

## Public Dashboard Helper

Use OpenClaw gateway token auth when using the RunPod proxy. For easier login, startup should write:

```text
/tmp/openclaw/dashboard-url
```

That file may contain the public dashboard URL, WebSocket URL, gateway token, and tokenized dashboard URL for the current disposable pod. It is runtime-only state and must not be committed to Git. The local copy of the gateway token belongs under:

```text
C:\Users\joerc\OneDrive\Documents\ollama\tmp\openclaw_public_gateway_token.local.txt
```

Password auth was tested on 2026-08-13 with OpenClaw `2026.7.1-2` behind the RunPod proxy. Although the UI showed a password field and `gateway.auth.mode=password`, browser and CLI device connections still failed with `token_missing`. The working setup is token auth with the tokenized dashboard URL from `/tmp/openclaw/dashboard-url`.

For another PC, move an access bundle containing the project-local SSH key, `tmp/openclaw_dashboard_url.local.txt`, and `openclaw_dashboard.ps1`. Extract it on the other PC and run:

```powershell
.\openclaw_dashboard.ps1
```

If OpenClaw shows `Device pairing required`, approve the pending request from the pod:

```bash
TOKEN="$(cat /tmp/openclaw/gateway-token)"
openclaw devices list --url ws://127.0.0.1:18789 --token "$TOKEN"
openclaw devices approve <REQUEST_ID> --url ws://127.0.0.1:18789 --token "$TOKEN"
```
