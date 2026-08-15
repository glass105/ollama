#!/usr/bin/env python3
"""Prepare and use SSH aliases backed by Windows reverse tunnels."""

from __future__ import annotations

import argparse
import csv
import os
import re
import socket
import subprocess
import sys
from pathlib import Path


DEFAULT_INVENTORY = Path(os.environ.get("EQUIPMENT_FILE", "/tmp/equipment.csv"))
DEFAULT_CONFIG = Path(os.environ.get("EQUIPMENT_SSH_CONFIG", "/tmp/equipment_ssh_config"))
NAME_RE = re.compile(r"^[A-Za-z0-9_-]+$")
ADDRESS_RE = re.compile(r"^[A-Za-z0-9_.:-]+$")


def enabled(value: str) -> bool:
    return value.strip().lower() in {"1", "true", "yes", "y", "on"}


def load_devices(path: Path) -> dict[str, dict[str, str]]:
    if not path.is_file():
        raise SystemExit(f"Equipment inventory not found: {path}")

    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        required = {"name", "user", "address", "ssh_port", "tunnel_port", "enabled"}
        missing = required.difference(reader.fieldnames or [])
        if missing:
            raise SystemExit(f"Equipment inventory is missing columns: {', '.join(sorted(missing))}")

        devices: dict[str, dict[str, str]] = {}
        tunnel_ports: set[int] = set()
        for line_number, row in enumerate(reader, start=2):
            if not enabled(row["enabled"]):
                continue

            name = row["name"].strip()
            user = row["user"].strip()
            address = row["address"].strip()
            if not NAME_RE.fullmatch(name):
                raise SystemExit(f"Invalid equipment name on line {line_number}: {name!r}")
            if not NAME_RE.fullmatch(user):
                raise SystemExit(f"Invalid equipment user on line {line_number}: {user!r}")
            if not ADDRESS_RE.fullmatch(address):
                raise SystemExit(f"Invalid equipment address on line {line_number}: {address!r}")
            if name in devices:
                raise SystemExit(f"Duplicate equipment name: {name}")

            try:
                ssh_port = int(row["ssh_port"])
                tunnel_port = int(row["tunnel_port"])
            except ValueError as exc:
                raise SystemExit(f"Invalid port on equipment line {line_number}") from exc
            if not 1 <= ssh_port <= 65535:
                raise SystemExit(f"Invalid SSH port for {name}: {ssh_port}")
            if not 1024 <= tunnel_port <= 65535:
                raise SystemExit(f"Invalid tunnel port for {name}: {tunnel_port}")
            if tunnel_port in tunnel_ports:
                raise SystemExit(f"Duplicate tunnel port: {tunnel_port}")

            tunnel_ports.add(tunnel_port)
            devices[name] = {
                "name": name,
                "user": user,
                "address": address,
                "ssh_port": str(ssh_port),
                "tunnel_port": str(tunnel_port),
            }

    if not devices:
        raise SystemExit("Equipment inventory contains no enabled devices.")
    return devices


def render_config(devices: dict[str, dict[str, str]]) -> str:
    identity_file = os.environ.get("EQUIPMENT_IDENTITY_FILE", "").strip()
    known_hosts_file = os.environ.get(
        "EQUIPMENT_KNOWN_HOSTS_FILE", "/root/.ssh/known_hosts"
    ).strip()
    strict_host_key = os.environ.get("EQUIPMENT_STRICT_HOST_KEY_CHECKING", "ask").strip()

    blocks: list[str] = []
    for device in devices.values():
        lines = [
            f"Host {device['name']}",
            "    HostName 127.0.0.1",
            f"    Port {device['tunnel_port']}",
            f"    User {device['user']}",
            f"    HostKeyAlias {device['name']}",
            "    ConnectTimeout 10",
            "    ServerAliveInterval 15",
            "    ServerAliveCountMax 2",
            f"    StrictHostKeyChecking {strict_host_key}",
            f"    UserKnownHostsFile {known_hosts_file}",
        ]
        if identity_file:
            lines.extend([f"    IdentityFile {identity_file}", "    IdentitiesOnly yes"])
        blocks.append("\n".join(lines))
    return "\n\n".join(blocks) + "\n"


def prepare(devices: dict[str, dict[str, str]], config_path: Path) -> int:
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(render_config(devices), encoding="utf-8")
    config_path.chmod(0o600)
    print(f"Prepared {len(devices)} equipment aliases in {config_path}")
    return 0


def port_open(port: int) -> bool:
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=2):
            return True
    except OSError:
        return False


def check(devices: dict[str, dict[str, str]]) -> int:
    failed = False
    for device in devices.values():
        port = int(device["tunnel_port"])
        reachable = port_open(port)
        print(f"{device['name']}: {'reachable' if reachable else 'unavailable'} on 127.0.0.1:{port}")
        failed = failed or not reachable
    return 1 if failed else 0


def run_command(
    devices: dict[str, dict[str, str]], config_path: Path, name: str, command: list[str]
) -> int:
    if name not in devices:
        raise SystemExit(f"Unknown or disabled equipment: {name}")
    if not config_path.is_file():
        prepare(devices, config_path)

    port = int(devices[name]["tunnel_port"])
    if not port_open(port):
        raise SystemExit(f"Tunnel for {name} is unavailable on 127.0.0.1:{port}")

    ssh_command = ["ssh", "-F", str(config_path), name]
    if command:
        ssh_command.extend(command)
    try:
        completed = subprocess.run(ssh_command, check=False, timeout=120)
    except subprocess.TimeoutExpired:
        print(f"SSH command timed out for {name}.", file=sys.stderr)
        return 124
    return completed.returncode


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", type=Path, default=DEFAULT_INVENTORY)
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    subparsers = parser.add_subparsers(dest="action", required=True)
    subparsers.add_parser("prepare", help="Generate the pod-local SSH alias configuration.")
    subparsers.add_parser("list", help="List enabled equipment without credentials.")
    subparsers.add_parser("check", help="Check reverse-tunnel listeners.")
    run_parser = subparsers.add_parser("run", help="SSH to equipment through its tunnel.")
    run_parser.add_argument("name")
    run_parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    devices = load_devices(args.inventory)
    if args.action == "prepare":
        return prepare(devices, args.config)
    if args.action == "list":
        for device in devices.values():
            print(
                f"{device['name']} user={device['user']} "
                f"tunnel=127.0.0.1:{device['tunnel_port']}"
            )
        return 0
    if args.action == "check":
        return check(devices)
    return run_command(devices, args.config, args.name, args.command)


if __name__ == "__main__":
    raise SystemExit(main())
