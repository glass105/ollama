---
name: equipment-bridge
description: Run approved read-only operations such as show_version on named Nokia equipment through the HTTPS equipment worker.
metadata:
  {
    "openclaw":
      {
        "requires": { "bins": ["python3"] },
      },
  }
---

# Equipment Bridge

Use this skill when the user explicitly asks to run, execute, or retrieve a supported read-only operation from named equipment.

## Required workflow

1. Identify the device and operation from the user's request.
2. Use only a named operation supported by the Windows worker, such as `show_version`, `show_alarms`, `show_pdn_context`, or `show_ue_context`.
3. For `show_ue_context`, require an IMSI and pass it as `--param imsi=<digits>`.
4. Run exactly one bridge command with the `exec` tool:

```bash
/workspace/ollama-memory/openclaw_equipment_tool.py --device DEVICE --operation OPERATION
```

5. Wait for that command to finish. It submits the job and waits for the Windows worker in one invocation.
6. Return the actual `stdout`, status, and exit code. If the bridge reports failure or timeout, report that error without inventing equipment output.

## Safety

- Never use the `nodes` tool for equipment commands.
- Never SSH directly to equipment from the pod.
- Never run arbitrary CLI text supplied by a user. Use only the worker's named operations.
- Device and operation values may contain only letters, digits, underscores, and hyphens.
- Never print bridge tokens, equipment passwords, or other credentials.
