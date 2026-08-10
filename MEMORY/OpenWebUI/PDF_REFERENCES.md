# PDF References

The `PDFS/` directory stores reference PDFs that are durable GitHub-backed project assets.
Vendor-specific PDFs can be grouped in subdirectories such as `PDFS/Nokia/`.

Available PDFs:

- `PDFS/Nokia/CMG_CLI_Reference_Guide.pdf` - CMG CLI Reference Guide.
- `PDFS/Nokia/CMG_Configuration_Guide_part_1.pdf` - CMG Configuration Guide, pages 1-541.
- `PDFS/Nokia/CMG_Configuration_Guide_part_2.pdf` - CMG Configuration Guide, pages 542-1082.

These PDFs are not automatically read by Qwen through the memory proxy. The memory proxy injects Markdown from `/workspace/current_context.md`; it does not extract PDF text. To answer questions from a PDF, first extract or summarize the relevant PDF pages into Markdown memory, or use an external PDF/RAG extraction step.

Open WebUI auto-indexing currently targets the Git-backed PDFs above. In the verified RunPod setup, Open WebUI indexed the three CMG PDF files into the `Nokia` Knowledge collection.

AnythingLLM can also contain runtime-indexed documents that are not present in Git. The verified runtime included `cmm_cli_reference_guide.pdf` in AnythingLLM storage, but that PDF was not present under the local Git-backed `PDFS/` directory at the time this note was written.
