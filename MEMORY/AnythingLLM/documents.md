# AnythingLLM Document Manifest

Generated: 2026-08-07 20:33:01 UTC

Verified update: 2026-08-12 runtime indexed five Git-backed references in the `Nokia` workspace:

- `CMG_CLI_Reference_Guide.pdf`
- `CMG_Configuration_Guide_part_1.pdf`
- `CMG_Configuration_Guide_part_2.pdf`
- `cmm_cli_reference_guide.pdf`
- `CMM_Alarms.xlsx` (converted to generated Markdown for embedding)

Verified update: 2026-08-25 active Nokia target set:

- `CMG_CLI_Reference_Guide.pdf`
- `cmm_cli_reference_guide.pdf`
- `CMM_Alarms.xlsx`

The following files were removed from the active Git-backed RAG set and should not be re-added or indexed unless explicitly requested:

- `PDFS/Nokia/CMG_Configuration_Guide_part_1.pdf`
- `PDFS/Nokia/CMG_Configuration_Guide_part_2.pdf`

The 2026-08-12 runtime had 1850 total vectors in AnythingLLM after CMM alarm workbook indexing.

Runtime vector databases and extracted JSON files are not committed to Git.

For a CMM-only retrieval prompt, use:

```text
Use only the indexed document named cmm_cli_reference_guide.pdf.
Do not use CMG_CLI_Reference_Guide.pdf.
Do not use CMG_Configuration_Guide_part_1.pdf.
Do not use CMG_Configuration_Guide_part_2.pdf.
```

For CMM alarm questions, add:

```text
Use the indexed document titled CMM_Alarms.xlsx.
```

| Workspace | Title | Source | Words | Token Estimate | Published | Stored JSON |
|---|---|---|---:|---:|---|---|
| Nokia | CMG_CLI_Reference_Guide.pdf | file:///workspace/anything-llm/collector/hotdir/CMG_CLI_Reference_Guide.pdf | 1030941 | 794495 | 8/7/2026, 6:53:47 PM | custom-documents/CMG_CLI_Reference_Guide.pdf-1c018471-9197-4447-9228-6dea7465ea67.json |
| Nokia | CMG_Configuration_Guide.pdf | file:///workspace/anything-llm/collector/hotdir/CMG_Configuration_Guide.pdf | 305253 | 261301 | 8/7/2026, 7:08:16 PM | custom-documents/CMG_Configuration_Guide.pdf-4ac16d42-f672-42bb-a544-7ca2ff2a2f67.json |
| Nokia | CMG_Configuration_Guide_part_2.pdf | file:///workspace/anything-llm/collector/hotdir/CMG_Configuration_Guide_part_2.pdf | 134025 | 121961 | 8/7/2026, 6:53:48 PM | custom-documents/CMG_Configuration_Guide_part_2.pdf-9ac1900f-07a0-4ad6-9764-404c80409dc4.json |

## Reload Source Mapping

- `CMG_CLI_Reference_Guide.pdf` should be reloaded from `PDFS/Nokia/CMG_CLI_Reference_Guide.pdf`.
- `cmm_cli_reference_guide.pdf` should be reloaded from `PDFS/Nokia/cmm_cli_reference_guide.pdf`.
- `CMM_Alarms.xlsx` should be reloaded from `PDFS/Nokia/CMM_Alarms.xlsx`.
