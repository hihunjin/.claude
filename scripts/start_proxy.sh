#!/usr/bin/env bash
# apiKeyHelper entry point: ensure fallback_proxy.py is running, then emit a
# placeholder key. Claude Code sends it as the Authorization header; the proxy
# replaces it with the real backend token.
set -euo pipefail

PORT="${CLAUDE_PROXY_PORT:-7070}"
PROXY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fallback_proxy.py"

if ! curl -sf "http://127.0.0.1:$PORT" >/dev/null 2>&1; then
  nohup python3 "$PROXY" >>"$HOME/.claude/proxy.log" 2>&1 &
  sleep 1
fi

echo "proxy-key"
