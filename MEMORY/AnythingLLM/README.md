# AnythingLLM Export

Generated from the live disposable RunPod AnythingLLM runtime at 2026-08-07 20:33:01 UTC.

Updated with verified runtime notes from 2026-08-10.

This folder stores durable Markdown state only: workspace settings, document manifests, chat history, and operator notes.

It intentionally does not store AnythingLLM SQLite databases, LanceDB/vector stores, uploaded runtime files, caches, logs, tokens, passwords, private keys, or full raw extracted PDF text.

The source CMG and CMM documents remain in `PDFS/Nokia/`. On pod startup, AnythingLLM should be recreated from Git and should re-import/re-index those source files, or restore the S3 RAG cache, rather than relying on disposable pod runtime state.

In the verified 2026-08-10 runtime, AnythingLLM ran on internal port `3010`, was exposed through nginx on port `3001`, used Ollama with `qwen3-coder:30b`, and used local LanceDB runtime storage.

The RunPod base image may already define nginx port `3001` for another UI. Startup must remove existing `listen 3001` nginx server blocks before adding the AnythingLLM proxy.

RunPod network volumes are no longer part of the recreate path. Persistent AnythingLLM RAG/vector reuse should use the RunPod S3-compatible cache target `lp8wr68ped`.

The S3 RAG cache should store only vector-facing snapshots and manifests, such as AnythingLLM LanceDB state, document JSON, vector cache, and sanitized manifest files. The sanitized manifest may include safe workspace linkage rows so restored LanceDB/vector data can be reattached to workspaces such as `Nokia`. It must not store secrets, generated API keys, full auth databases, model files, logs, or OpenClaw runtime state.

As of 2026-08-19, RAG cache saves prune S3 storage to three tar files total: the overwritten `latest/` restore pointer plus the newest two historical snapshot tar files.

OpenClaw can query AnythingLLM RAG indirectly through the pod-local helper:

```bash
/workspace/ollama-memory/anythingllm_query.sh Nokia "<question>"
```

This calls the AnythingLLM workspace API and returns the RAG-grounded answer and source metadata. OpenClaw should not read LanceDB/vector files directly.

Verified 2026-08-12:

- `PDFS/Nokia/cmm_cli_reference_guide.pdf` is Git-backed and indexed in AnythingLLM workspace `Nokia`.
- `PDFS/Nokia/CMM_Alarms.xlsx` is Git-backed and indexed in AnythingLLM workspace `Nokia` after conversion to generated Markdown text.
- The S3 RAG cache was refreshed after CMM PDF and XLSX indexing.
