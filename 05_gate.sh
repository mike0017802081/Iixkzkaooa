#!/usr/bin/env bash
# phase 5 — start noVNC + authentication gate
# SESSION_KEY must be set in the environment (from GitHub secret VNC_PASS).
set -euo pipefail

NOVNC_PORT="${NOVNC_PORT:-6080}"
VNC_PORT="${VNC_PORT:-5901}"
GATE_PORT="${GATE_PORT:-8080}"
GATE_SCRIPT="$(dirname "$(realpath "$0")")/05_gate.py"

[[ -n "${SESSION_KEY:-}" ]] || {
  echo "SESSION_KEY is not set — cannot start auth gate" >&2
  exit 1
}

# ── start noVNC + websockify (proxies VNC over WebSocket) ─────────────────────
# noVNC listens only on localhost; the auth gate is the public-facing layer.
python3 /opt/novnc/utils/websockify/websockify.py \
  --web /opt/novnc \
  --host 127.0.0.1 \
  "${NOVNC_PORT}" \
  "127.0.0.1:${VNC_PORT}" \
  > /tmp/novnc.log 2>&1 \
  &
echo "$!" > /tmp/novnc.pid
sleep 2

# verify noVNC is up
if ! curl -sf "http://127.0.0.1:${NOVNC_PORT}/" >/dev/null 2>&1; then
  echo "noVNC did not start — check /tmp/novnc.log" >&2
  cat /tmp/novnc.log >&2
  exit 1
fi
echo "novnc: running on 127.0.0.1:${NOVNC_PORT}"

# ── start Python auth gate (binds 0.0.0.0:GATE_PORT) ────────────────────────
SESSION_KEY="${SESSION_KEY}" \
  NOVNC_PORT="${NOVNC_PORT}" \
  GATE_PORT="${GATE_PORT}" \
  python3 "${GATE_SCRIPT}" \
  > /tmp/gate.log 2>&1 \
  &
echo "$!" > /tmp/gate.pid
sleep 2

if ! kill -0 "$(cat /tmp/gate.pid)" 2>/dev/null; then
  echo "auth gate failed to start — check /tmp/gate.log" >&2
  cat /tmp/gate.log >&2
  exit 1
fi
echo "gate: running on 0.0.0.0:${GATE_PORT}"
