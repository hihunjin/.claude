#!/usr/bin/env bash
# Link this repo's config into ~/.claude.
#
#   git clone <repo-url> ~/dotfiles/claude
#   ~/dotfiles/claude/install.sh
#
# Existing files are backed up to ~/.claude/<name>.bak-<timestamp> before linking.
# Re-run any time; `git pull` alone is enough afterwards since everything is symlinked.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HOME/.claude"
STAMP="$(date +%Y%m%d-%H%M%S)"

# Items linked from the repo into ~/.claude
ITEMS=(settings.json statusline-command.sh commands scripts)

if [ "$REPO" = "$TARGET" ]; then
  echo "Repo is already at $TARGET — nothing to link." >&2
  exit 0
fi

mkdir -p "$TARGET"

for item in "${ITEMS[@]}"; do
  src="$REPO/$item"
  dst="$TARGET/$item"

  [ -e "$src" ] || continue

  if [ -L "$dst" ]; then
    rm "$dst"
  elif [ -e "$dst" ]; then
    mv "$dst" "$dst.bak-$STAMP"
    echo "backed up  $dst -> $dst.bak-$STAMP"
  fi

  ln -s "$src" "$dst"
  echo "linked     $dst -> $src"
done

chmod +x "$REPO/statusline-command.sh" "$REPO/scripts/"*.sh "$REPO/scripts/"*.py 2>/dev/null || true

if [ ! -f "$TARGET/.env.local" ]; then
  cp "$REPO/.env.local.example" "$TARGET/.env.local"
  echo "created    $TARGET/.env.local (fill in your values; it is gitignored)"
fi

echo
echo "Done. Machine-local overrides go in $TARGET/settings.local.json (not tracked)."
command -v jq >/dev/null || echo "NOTE: install jq for the status line -> brew install jq"
command -v terminal-notifier >/dev/null || echo "NOTE: optional -> brew install terminal-notifier (Stop-hook notifications)"
