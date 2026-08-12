# Reference Documents

The `PDFS/` directory stores reference PDFs and spreadsheets that are durable GitHub-backed project assets.
Vendor-specific references can be grouped in subdirectories such as `PDFS/Nokia/`.

Available Nokia references:

- `PDFS/Nokia/CMG_CLI_Reference_Guide.pdf` - CMG CLI Reference Guide.
- `PDFS/Nokia/CMG_Configuration_Guide_part_1.pdf` - CMG Configuration Guide, pages 1-541.
- `PDFS/Nokia/CMG_Configuration_Guide_part_2.pdf` - CMG Configuration Guide, pages 542-1082.
- `PDFS/Nokia/cmm_cli_reference_guide.pdf` - CMM CLI Reference Guide.
- `PDFS/Nokia/CMM_Alarms.xlsx` - CMM alarm spreadsheet; converted to Markdown by the auto-indexers before embedding.

These references are not automatically read by Qwen through raw Ollama. To answer questions from a reference, use AnythingLLM RAG, OpenClaw tools, or first extract/summarize the relevant pages or rows into Markdown memory.

AnythingLLM indexes the Git-backed references into the `Nokia` workspace. Runtime vector databases and extracted/generated documents remain disposable and should be saved only through the S3 RAG cache, not Git.

Open WebUI is no longer part of the future RunPod pipeline.
