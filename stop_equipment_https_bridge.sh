#!/usr/bin/env bash
set -euo pipefail

PID_FILE="${EQUIPMENT_BRIDGE_PID_FILE:-/tmp/equipment-bridge/server.pid}"

if [ ! -f "$PID_FILE" ]; then
  echo "Equipment HTTPS bridge is not running (no PID file)."
  exit 0
fi

PID="$(cat "$PID_FILE")"
case "$PID" in
  ''|*[!0-9]*)
    echo "Invalid equipment bridge PID file; refusing to signal anything." >&2
    exit 1
    ;;
esac

if kill -0 "$PID" 2>/dev/null; then
  kill "$PID"
  echo "Stopped equipment HTTPS bridge process $PID."
else
  echo "Equipment HTTPS bridge process $PID is already stopped."
fi
rm -f "$PID_FILE"
