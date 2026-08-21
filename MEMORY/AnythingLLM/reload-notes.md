# AnythingLLM Reload Notes

Generated: 2026-08-07 20:33:01 UTC

Recommended startup behavior:

1. Clone/pull this Git repository.
2. Start Ollama on the upstream port.
3. Start AnythingLLM with:
   - LLM provider: `ollama`
   - Ollama base URL: `http://127.0.0.1:11434`
   - Chat model: `qwen3-coder:30b`
   - Embedding provider: `ollama`
   - Embedding model: `qwen3-embedding:8b`
4. Create or update the AnythingLLM workspace `Nokia`.
5. Upload/re-index source documents from `PDFS/Nokia/`.
6. Treat generated AnythingLLM DB/vector/cache files as disposable runtime state.

Current workspace target:

- Workspace name: `Nokia`
- Workspace slug: `my-workspace`
- Chat provider/model: `ollama` / `qwen3-coder:30b`
- Agent provider/model: `ollama` / `qwen3-coder:30b`
