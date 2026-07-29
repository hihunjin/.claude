#!/usr/bin/env bash
# Point Claude Code at a custom Anthropic-compatible gateway.
# Reads credentials from ~/.claude/.env.local (never hard-code them here).
# Writes ~/.claude/settings.local.json, which overrides the tracked settings.json.
set -euo pipefail

ENV_FILE="$HOME/.claude/.env.local"
KEY_SCRIPT="$HOME/.claude/anthropic_key.sh"   # gitignored

[ -f "$ENV_FILE" ] || { echo "Missing $ENV_FILE — copy .env.local.example and fill it in." >&2; exit 1; }
# shellcheck disable=SC1090
. "$ENV_FILE"

: "${CUSTOM_API_BASE_URL:?set CUSTOM_API_BASE_URL in $ENV_FILE}"
: "${CUSTOM_API_KEY:?set CUSTOM_API_KEY in $ENV_FILE}"

# Bake the current key value in — apiKeyHelper runs without the env file sourced.
cat > "$KEY_SCRIPT" <<EOF
#!/bin/sh
printf %s "$CUSTOM_API_KEY"
EOF
chmod 600 "$KEY_SCRIPT"

TLS_ENV=""
if [ "${CUSTOM_API_INSECURE_TLS:-0}" = "1" ]; then
  TLS_ENV=',
    "NODE_TLS_REJECT_UNAUTHORIZED": "0"'
fi

cat > "$HOME/.claude/settings.local.json" <<EOF
{
  "apiKeyHelper": "$KEY_SCRIPT",
  "env": {
    "ANTHROPIC_BASE_URL": "$CUSTOM_API_BASE_URL"$TLS_ENV
  }
}
EOF

echo "Switched to custom API mode ($CUSTOM_API_BASE_URL). Restart Claude Code."
