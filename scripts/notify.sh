#!/bin/sh
# Cross-platform desktop notification. Used by the Stop hook in settings.json.
#   usage: notify.sh [message] [title]
#
# Every notification is tagged with a unique handle and an expiry is dropped in
# the queue directory, so notify-sweep.sh can pull it back out of the
# notification centre once it is CLAUDE_NOTIFY_TTL seconds old (default 1h).
# Set CLAUDE_NOTIFY_TTL=0 to keep notifications until they are dismissed.
# Exits 0 no matter what — a missing notifier must never fail the hook.
message="${1:-Claude Code has finished responding.}"
title="${2:-Claude Code}"

ttl="${CLAUDE_NOTIFY_TTL:-3600}"
queue="${CLAUDE_NOTIFY_QUEUE:-$HOME/.claude/.notify-queue}"
sweeper="$(dirname "$0")/notify-sweep.sh"

# enqueue <kind> <handle> — record how to retract this notification later.
enqueue() {
  case "$ttl" in ''|*[!0-9]*) return 0 ;; esac
  [ "$ttl" -gt 0 ] || return 0
  mkdir -p "$queue" 2>/dev/null || return 0
  # Expiry lives in the filename so the sweeper can skip live entries without
  # opening them; mktemp keeps concurrent hooks from colliding.
  f=$(mktemp "$queue/$(( $(date +%s) + ttl )).XXXXXX" 2>/dev/null) || return 0
  printf '%s\t%s\n' "$1" "$2" > "$f"
}

if command -v terminal-notifier >/dev/null 2>&1; then
  # macOS, preferred: supports sound, a proper title, and later retraction
  group="cc-$(date +%s)-$$"
  terminal-notifier -title "$title" -message "$message" -sound Glass -group "$group"
  enqueue tn "$group"
elif command -v notify-send >/dev/null 2>&1; then
  # Linux (libnotify). -p prints the notification id, which gdbus can close later.
  id=$(notify-send -a "$title" -p "$title" "$message" 2>/dev/null) || id=""
  case "$id" in
    ''|*[!0-9]*) notify-send -a "$title" "$title" "$message" ;;  # -p unsupported: plain post
    *)           enqueue ns "$id" ;;
  esac
  # Optional chime, if a sound daemon is present
  if command -v canberra-gtk-play >/dev/null 2>&1; then
    canberra-gtk-play -i complete >/dev/null 2>&1 &
  elif command -v paplay >/dev/null 2>&1 && [ -f /usr/share/sounds/freedesktop/stereo/complete.oga ]; then
    paplay /usr/share/sounds/freedesktop/stereo/complete.oga >/dev/null 2>&1 &
  fi
elif [ "$(uname -s)" = "Darwin" ] && command -v osascript >/dev/null 2>&1; then
  # macOS fallback when terminal-notifier isn't installed. These cannot be
  # retracted programmatically, so nothing is queued for them.
  osascript -e "display notification \"$message\" with title \"$title\" sound name \"Glass\"" >/dev/null 2>&1
else
  # Last resort: terminal bell (silently skipped when there's no tty)
  { printf '\a' >/dev/tty; } 2>/dev/null || true
fi

# Clear anything that has aged out. Detached so a wedged notifier can never
# stall the hook; the launchd agent covers sessions that end before the hour.
[ -f "$sweeper" ] && nohup sh "$sweeper" >/dev/null 2>&1 &

exit 0
