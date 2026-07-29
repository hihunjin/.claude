#!/bin/sh
# Cross-platform desktop notification. Used by the Stop hook in settings.json.
#   usage: notify.sh [message] [title]
# Exits 0 no matter what — a missing notifier must never fail the hook.
message="${1:-Claude Code has finished responding.}"
title="${2:-Claude Code}"

if command -v terminal-notifier >/dev/null 2>&1; then
  # macOS, preferred: supports sound and a proper title
  terminal-notifier -title "$title" -message "$message" -sound Glass
elif command -v notify-send >/dev/null 2>&1; then
  # Linux (libnotify)
  notify-send -a "$title" "$title" "$message"
  # Optional chime, if a sound daemon is present
  if command -v canberra-gtk-play >/dev/null 2>&1; then
    canberra-gtk-play -i complete >/dev/null 2>&1 &
  elif command -v paplay >/dev/null 2>&1 && [ -f /usr/share/sounds/freedesktop/stereo/complete.oga ]; then
    paplay /usr/share/sounds/freedesktop/stereo/complete.oga >/dev/null 2>&1 &
  fi
elif [ "$(uname -s)" = "Darwin" ] && command -v osascript >/dev/null 2>&1; then
  # macOS fallback when terminal-notifier isn't installed
  osascript -e "display notification \"$message\" with title \"$title\" sound name \"Glass\"" >/dev/null 2>&1
else
  # Last resort: terminal bell (silently skipped when there's no tty)
  { printf '\a' >/dev/tty; } 2>/dev/null || true
fi

exit 0
