# AnythingLLM Export

Generated from the live disposable RunPod AnythingLLM runtime at 2026-08-07 20:33:01 UTC.

Updated with verified runtime notes from 2026-08-10.

This folder stores durable Markdown state only: workspace settings, document manifests, chat history, and operator notes.

It intentionally does not store AnythingLLM SQLite databases, LanceDB/vector stores, uploaded runtime files, caches, logs, tokens, passwords, private keys, or full raw extracted PDF text.

The source CMG documents remain in `PDFS/Nokia/`. On pod startup, AnythingLLM should be recreated from Git and should re-import/re-index those source files rather than relying on runtime state.

In the verified 2026-08-10 runtime, AnythingLLM ran on internal port `3010`, was exposed through nginx on port `3001`, used Ollama with `qwen3-coder:30b`, and used local LanceDB runtime storage.

The RunPod base image may already define nginx port `3001` for another UI. Startup must remove existing `listen 3001` nginx server blocks before adding the AnythingLLM proxy, or the public AnythingLLM URL can incorrectly display Open WebUI.

RunPod network volumes are no longer part of the recreate path. Persistent AnythingLLM RAG/vector reuse should use the RunPod S3-compatible cache target `lp8wr68ped`.

The S3 RAG cache should store only vector-facing snapshots and manifests, such as AnythingLLM LanceDB state, document JSON, vector cache, and sanitized manifest files. It must not store secrets, generated API keys, full auth databases, model files, logs, or OpenClaw runtime state.
