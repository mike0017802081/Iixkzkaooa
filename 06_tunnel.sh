#!/usr/bin/env bash
# phase 6 — open a Cloudflare Quick Tunnel to expose the auth gate publicly
set -euo pipefail

GATE_PORT="${GATE_PORT:-8080}"
TUNNEL_LOG="/tmp/tunnel.log"

# ── start cloudflared quick tunnel ───────────────────────────────────────────
cloudflared tunnel \
  --no-autoupdate \
  --url "http://127.0.0.1:${GATE_PORT}" \
  > "${TUNNEL_LOG}" 2>&1 \
  &
echo "$!" > /tmp/tunnel.pid

# wait for the public URL to appear in the log (up to 30 s)
echo "waiting for tunnel URL..."
WAITED=0
PUBLIC_URL=""
until [[ -n "${PUBLIC_URL}" ]]; do
  sleep 2
  WAITED=$((WAITED + 2))
  PUBLIC_URL="$(grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' \
    "${TUNNEL_LOG}" 2>/dev/null | head -1 || true)"
  if (( WAITED >= 30 )); then
    echo "tunnel URL not found after 30s — dumping log:" >&2
    cat "${TUNNEL_LOG}" >&2
    break
  fi
done

if [[ -n "${PUBLIC_URL}" ]]; then
  echo ""
  echo "┌─────────────────────────────────────────────────────┐"
  echo "│  Remote session ready                               │"
  echo "│  Open in your browser:                              │"
  echo "│  ${PUBLIC_URL}"
  echo "│  Enter the access key when prompted.                │"
  echo "└─────────────────────────────────────────────────────┘"
  echo ""
else
  echo "tunnel: could not obtain public URL — session may still be accessible"
fi
