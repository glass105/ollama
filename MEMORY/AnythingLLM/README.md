# AnythingLLM Export

Generated from the live disposable RunPod AnythingLLM runtime at 2026-08-07 20:33:01 UTC.

This folder stores durable Markdown state only: workspace settings, document manifests, chat history, and operator notes.

It intentionally does not store AnythingLLM SQLite databases, LanceDB/vector stores, uploaded runtime files, caches, logs, tokens, passwords, private keys, or full raw extracted PDF text.

The source documents remain in `PDFS/Nokia/`. On pod startup, AnythingLLM should be recreated from Git and should re-import/re-index those source files rather than relying on runtime state.
