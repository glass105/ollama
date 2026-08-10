# AnythingLLM Workspaces

Generated: 2026-08-07 20:33:01 UTC

## Nokia

- id: `1`
- name: `Nokia`
- slug: `my-workspace`
- chatProvider: `ollama`
- chatModel: `qwen3-coder:30b`
- agentProvider: `ollama`
- agentModel: `qwen3-coder:30b`
- chatMode: `automatic`
- openAiHistory: `20`
- similarityThreshold: `0.25`
- topN: `4`
- vectorSearchMode: `default`

Verified 2026-08-10:

- AnythingLLM should use Ollama at the pod-local upstream service.
- AnythingLLM should use `qwen3-coder:30b` for chat and agent settings.
- AnythingLLM should use LanceDB locally on the disposable pod filesystem.
- The `Nokia` workspace contained both CMG and CMM documents. For CMM questions, constrain the prompt to `cmm_cli_reference_guide.pdf` or split CMM into its own workspace to reduce cross-document retrieval.

### System Prompt

Given the following conversation, relevant context, and a follow up question, reply with an answer to the current question the user is asking. The current date and time is {datetime}. Return only your response to the question given the above information following the users instructions as needed.
