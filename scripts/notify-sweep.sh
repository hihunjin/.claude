#!/bin/sh
# Retract desktop notifications that notify.sh queued and that have aged out.
#
# The queue is a directory of tiny files named <expiry-epoch>.XXXXXX whose
# contents are "<kind>\t<handle>". A file is processed once and then deleted,
# so overlapping sweeps are harmless and no locking is needed.
#
# Run automatically by notify.sh after each notification and by the launchd
# agent (see install.sh) so the last notification of a session is cleared too.
queue="${CLAUDE_NOTIFY_QUEUE:-$HOME/.claude/.notify-queue}"

# launchd hands agents a minimal PATH, so the notifier has to be findable.
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
export PATH

[ -d "$queue" ] || exit 0

# Run a command, killing it if it wedges — terminal-notifier is known to hang
# on some macOS builds and this runs unattended.
run_capped() {
  "$@" >/dev/null 2>&1 &
  cmd=$!
  # Poll rather than spawn a killer subshell: nothing to clean up afterwards,
  # and we can never fire a stale kill at a recycled pid.
  i=0
  while [ "$i" -lt 100 ] && kill -0 "$cmd" 2>/dev/null; do
    sleep 0.1
    i=$((i + 1))
  done
  kill -9 "$cmd" 2>/dev/null
  wait "$cmd" 2>/dev/null
}

now=$(date +%s)

for f in "$queue"/*.*; do
  [ -f "$f" ] || continue

  base=${f##*/}
  expiry=${base%%.*}
  # Anything unparseable is junk we put there; drop it rather than keep retrying.
  case "$expiry" in ''|*[!0-9]*) rm -f "$f"; continue ;; esac
  [ "$now" -ge "$expiry" ] || continue

  kind=''; handle=''
  IFS='	' read -r kind handle < "$f"

  case "$kind" in
    tn)
      command -v terminal-notifier >/dev/null 2>&1 &&
        run_capped terminal-notifier -remove "$handle"
      ;;
    ns)
      command -v gdbus >/dev/null 2>&1 &&
        run_capped gdbus call --session \
          --dest org.freedesktop.Notifications \
          --object-path /org/freedesktop/Notifications \
          --method org.freedesktop.Notifications.CloseNotification "$handle"
      ;;
  esac

  rm -f "$f"
done

exit 0
