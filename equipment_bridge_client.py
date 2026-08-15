#!/usr/bin/env python3
"""Submit and inspect equipment jobs from the RunPod/OpenClaw side."""

from __future__ import annotations

import argparse
import json
import os
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


DEFAULT_URL = os.environ.get("EQUIPMENT_BRIDGE_URL", "http://127.0.0.1:19124").rstrip("/")
DEFAULT_TOKEN_FILE = Path(os.environ.get("EQUIPMENT_BRIDGE_CLIENT_TOKEN_FILE", "/tmp/equipment-bridge/client-token"))


def request_json(base_url: str, token: str, path: str, payload: dict | None = None) -> dict:
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    request = Request(
        f"{base_url}{path}",
        data=body,
        method="GET" if body is None else "POST",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    try:
        with urlopen(request, timeout=15) as response:
            return json.loads(response.read().decode("utf-8"))
    except HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"Bridge returned HTTP {exc.code}: {detail}") from exc
    except URLError as exc:
        raise SystemExit(f"Bridge request failed: {exc.reason}") from exc


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default=DEFAULT_URL)
    parser.add_argument("--token-file", type=Path, default=DEFAULT_TOKEN_FILE)
    subparsers = parser.add_subparsers(dest="action", required=True)
    submit = subparsers.add_parser("submit")
    submit.add_argument("device")
    submit.add_argument("operation")
    submit.add_argument("--ttl", type=int, default=300)
    status = subparsers.add_parser("status")
    status.add_argument("job_id")
    wait = subparsers.add_parser("wait")
    wait.add_argument("job_id")
    wait.add_argument("--timeout", type=int, default=180)
    cancel = subparsers.add_parser("cancel")
    cancel.add_argument("job_id")
    args = parser.parse_args()

    token = args.token_file.read_text(encoding="utf-8").strip()
    if args.action == "submit":
        result = request_json(args.url, token, "/api/jobs", {
            "device": args.device, "operation": args.operation, "ttlSeconds": args.ttl
        })
    elif args.action == "status":
        result = request_json(args.url, token, f"/api/jobs/{args.job_id}")
    elif args.action == "cancel":
        result = request_json(args.url, token, f"/api/jobs/{args.job_id}/cancel", {})
    else:
        deadline = time.monotonic() + args.timeout
        while True:
            result = request_json(args.url, token, f"/api/jobs/{args.job_id}")
            if result["job"]["status"] not in {"pending", "claimed"}:
                break
            if time.monotonic() >= deadline:
                raise SystemExit("Timed out waiting for equipment job.")
            time.sleep(2)
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
