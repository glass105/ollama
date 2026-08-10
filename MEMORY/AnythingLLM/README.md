# AnythingLLM Export

Generated from the live disposable RunPod AnythingLLM runtime at 2026-08-07 20:33:01 UTC.

Updated with verified runtime notes from 2026-08-10.

This folder stores durable Markdown state only: workspace settings, document manifests, chat history, and operator notes.

It intentionally does not store AnythingLLM SQLite databases, LanceDB/vector stores, uploaded runtime files, caches, logs, tokens, passwords, private keys, or full raw extracted PDF text.

The source CMG documents remain in `PDFS/Nokia/`. On pod startup, AnythingLLM should be recreated from Git and should re-import/re-index those source files rather than relying on runtime state.

In the verified 2026-08-10 runtime, AnythingLLM ran on internal port `3010`, was exposed through nginx on port `3001`, used Ollama with `qwen3-coder:30b`, and used local LanceDB runtime storage.

The RunPod base image may already define nginx port `3001` for another UI. Startup must remove existing `listen 3001` nginx server blocks before adding the AnythingLLM proxy, or the public AnythingLLM URL can incorrectly display Open WebUI.

RunPod network volume `390eu4ykoc` may be used as an opt-in persistent RAG/vector-state target. It should store vector-facing snapshots or reusable RAG state only, not secrets, generated API keys, full auth databases, model files, logs, or OpenClaw runtime state.
