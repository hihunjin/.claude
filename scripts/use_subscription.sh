#!/usr/bin/env bash
# Switch back to the normal Claude subscription/login (undoes use_custom_api.sh).
set -euo pipefail

rm -f "$HOME/.claude/settings.local.json" "$HOME/.claude/anthropic_key.sh"
echo "Switched to Claude subscription mode. Restart Claude Code."
