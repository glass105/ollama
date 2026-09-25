#!/usr/bin/env python3
"""Run one approved equipment-bridge operation and wait for its result."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from pathlib import Path

from equipment_bridge_client import request_json


NAME_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
PARAM_NAME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_-]{0,63}$")
DEFAULT_URL = os.environ.get("EQUIPMENT_BRIDGE_URL", "http://127.0.0.1:19124").rstrip("/")
DEFAULT_TOKEN_FILE = Path(
    os.environ.get("EQUIPMENT_BRIDGE_CLIENT_TOKEN_FILE", "/tmp/equipment-bridge/client-token")
)
MAX_OUTPUT_CHARS = int(os.environ.get("OPENCLAW_EQUIPMENT_MAX_OUTPUT_CHARS", "20000"))


def parse_parameters(items: list[str]) -> dict[str, str]:
    parameters: dict[str, str] = {}
    for item in items:
        if "=" not in item:
            raise ValueError(f"invalid parameter {item!r}; expected NAME=VALUE")
        name, value = item.split("=", 1)
        if not PARAM_NAME_RE.fullmatch(name) or name in parameters:
            raise ValueError(f"invalid or duplicate parameter name: {name!r}")
        if len(value) > 256 or any(ord(char) < 32 for char in value):
            raise ValueError(f"invalid value for parameter {name!r}")
        parameters[name] = value
    return parameters


def bounded(value: object) -> str:
    text = str(value or "")
    if len(text) <= MAX_OUTPUT_CHARS:
        return text
    omitted = len(text) - MAX_OUTPUT_CHARS
    return f"{text[:MAX_OUTPUT_CHARS]}\n...[truncated {omitted} characters]"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--operation", required=True)
    parser.add_argument("--param", action="append", default=[], metavar="NAME=VALUE")
    parser.add_argument("--timeout", type=int, default=180)
    parser.add_argument("--url", default=DEFAULT_URL)
    parser.add_argument("--token-file", type=Path, default=DEFAULT_TOKEN_FILE)
    args = parser.parse_args()

    if not NAME_RE.fullmatch(args.device):
        parser.error("device must contain only letters, digits, underscores, or hyphens")
    if not NAME_RE.fullmatch(args.operation):
        parser.error("operation must contain only letters, digits, underscores, or hyphens")
    if not 10 <= args.timeout <= 600:
        parser.error("timeout must be between 10 and 600 seconds")

    try:
        parameters = parse_parameters(args.param)
        token = args.token_file.read_text(encoding="utf-8").strip()
    except (OSError, ValueError) as exc:
        print(f"equipment bridge configuration error: {exc}", file=sys.stderr)
        return 2

    if len(token) < 32:
        print("equipment bridge client token is missing or too short", file=sys.stderr)
        return 2

    ttl_seconds = min(900, max(300, args.timeout + 60))
    created = request_json(
        args.url.rstrip("/"),
        token,
        "/api/jobs",
        {
            "device": args.device,
            "operation": args.operation,
            "parameters": parameters,
            "ttlSeconds": ttl_seconds,
        },
    )
    job_id = created["job"]["id"]
    deadline = time.monotonic() + args.timeout

    while True:
        response = request_json(args.url.rstrip("/"), token, f"/api/jobs/{job_id}")
        job = response["job"]
        if job["status"] not in {"pending", "claimed"}:
            break
        if time.monotonic() >= deadline:
            try:
                request_json(args.url.rstrip("/"), token, f"/api/jobs/{job_id}/cancel", {})
            except SystemExit:
                pass
            print(
                json.dumps(
                    {
                        "jobId": job_id,
                        "device": args.device,
                        "operation": args.operation,
                        "status": "timed_out",
                        "message": "The equipment worker did not return a result before the timeout.",
                    },
                    indent=2,
                )
            )
            return 1
        time.sleep(2)

    result = job.get("result") or {}
    output = {
        "jobId": job_id,
        "device": job.get("device", args.device),
        "operation": job.get("operation", args.operation),
        "status": job.get("status"),
        "workerId": job.get("workerId"),
        "exitCode": result.get("exitCode"),
        "stdout": bounded(result.get("stdout")),
        "stderr": bounded(result.get("stderr")),
        "durationMs": result.get("durationMs"),
        "message": bounded(result.get("message")),
    }
    print(json.dumps(output, indent=2))
    return 0 if job.get("status") == "completed" and result.get("exitCode") == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
