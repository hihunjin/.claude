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
ITEMS=(settings.json statusline-command.sh commands scripts output-styles)

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

# macOS: a launchd agent sweeps expired desktop notifications every 5 minutes,
# so the last notification of a session ages out of the notification centre too
# (notify.sh can only sweep while it is posting something new).
#
# The agent runs from a copy under ~/Library rather than from the repo: launchd
# agents are refused access to TCC-protected folders such as ~/Documents or
# ~/Desktop, which is where the repo may well be checked out. Re-run this
# script after changing scripts/notify-sweep.sh to refresh the copy.
if [ "$(uname -s)" = "Darwin" ]; then
  AGENT_LABEL="com.hihunjin.claude-notify-sweep"
  AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"
  AGENT_DIR="$HOME/Library/Application Support/claude-notify-sweep"
  AGENT_BIN="$AGENT_DIR/notify-sweep.sh"

  mkdir -p "$AGENT_DIR" "$HOME/Library/LaunchAgents"
  cp "$REPO/scripts/notify-sweep.sh" "$AGENT_BIN"
  chmod +x "$AGENT_BIN"

  cat > "$AGENT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$AGENT_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>$AGENT_BIN</string>
  </array>
  <key>StartInterval</key>
  <integer>300</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>ProcessType</key>
  <string>Background</string>
</dict>
</plist>
PLIST

  launchctl bootout "gui/$UID/$AGENT_LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$UID" "$AGENT_PLIST" 2>/dev/null || launchctl load "$AGENT_PLIST" 2>/dev/null || true
  echo "loaded     $AGENT_LABEL (retracts notifications once they are an hour old)"
fi

echo
echo "Done. Machine-local overrides go in $TARGET/settings.local.json (not tracked)."

# Dependency hints, phrased for whichever package manager is actually present.
pkg_hint() {  # pkg_hint <brew-name> <apt-name> <dnf-name> <pacman-name>
  if command -v brew >/dev/null 2>&1;    then echo "brew install $1"
  elif command -v apt-get >/dev/null 2>&1;  then echo "sudo apt install $2"
  elif command -v dnf >/dev/null 2>&1;      then echo "sudo dnf install $3"
  elif command -v pacman >/dev/null 2>&1;   then echo "sudo pacman -S $4"
  else echo "install $1 with your package manager"
  fi
}

command -v jq >/dev/null 2>&1 || \
  echo "NOTE: the status line needs jq -> $(pkg_hint jq jq jq jq)"

if ! command -v terminal-notifier >/dev/null 2>&1 && ! command -v notify-send >/dev/null 2>&1; then
  case "$(uname -s)" in
    Darwin) echo "NOTE: optional -> $(pkg_hint terminal-notifier '' '' '') (Stop-hook notifications; osascript is used otherwise)" ;;
    *)      echo "NOTE: optional -> $(pkg_hint '' libnotify-bin libnotify libnotify) (Stop-hook notifications)" ;;
  esac
fi
