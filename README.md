# claude-config

My portable [Claude Code](https://claude.com/claude-code) setup — settings, slash commands,
a status line, and API-switching scripts. Clone on a new machine, run `install.sh`, done.

Works on macOS and Linux.

## Install

```bash
git clone <this-repo-url> ~/dotfiles/claude
~/dotfiles/claude/install.sh
```

`install.sh` symlinks each tracked item into `~/.claude/`, backing up anything already
there as `<name>.bak-<timestamp>`. Because they're symlinks, a later `git pull` is enough —
no re-install needed.

Dependencies — `install.sh` tells you which of these are missing, using the right package
manager for the machine:

| | macOS | Debian/Ubuntu | Fedora | Arch |
| --- | --- | --- | --- | --- |
| Status line (**required**) | `brew install jq` | `sudo apt install jq` | `sudo dnf install jq` | `sudo pacman -S jq` |
| Stop-hook notification (optional) | `brew install terminal-notifier` | `sudo apt install libnotify-bin` | `sudo dnf install libnotify` | `sudo pacman -S libnotify` |

The notification is optional on both platforms: on macOS it falls back to `osascript`, and
everywhere else to a terminal bell.

## What's in here

| Path | Purpose |
| --- | --- |
| `settings.json` | Model, status line, Stop hook, misc preferences |
| `statusline-command.sh` | Status line: `~/path \| branch \| model \| ctx: 42%` |
| `commands/` | Model/effort slash commands (see below) |
| `scripts/notify.sh` | Cross-platform desktop notification used by the Stop hook |
| `scripts/use_*.sh`, `*proxy*` | Switch between a custom API gateway and the normal subscription |
| `install.sh` | Symlinks everything into `~/.claude/` |
| `.env.local.example` | Template for machine-local secrets |

### Slash commands

Re-run the same prompt on a different model or reasoning effort:

| Command | Model | Effort |
| --- | --- | --- |
| `/h` | Haiku 4.5 | — |
| `/s` | Sonnet 5 | medium |
| `/sx` | Sonnet 5 | xhigh |
| `/o` | Opus 5 | medium |
| `/ox` | Opus 5 | xhigh |
| `/om` | Opus 5 | max |

Usage: `/ox refactor this module and explain the tradeoffs`

### API switching (optional)

For running against an Anthropic-compatible gateway instead of the normal login:

```bash
cp ~/dotfiles/claude/.env.local.example ~/.claude/.env.local   # install.sh does this too
$EDITOR ~/.claude/.env.local                                   # fill in URL + key
~/.claude/scripts/use_custom_api.sh    # write settings.local.json pointing at the gateway
~/.claude/scripts/use_subscription.sh  # revert to the normal subscription
```

`scripts/fallback_proxy.py` (started by `scripts/start_proxy.sh`) is a local proxy that
tries the gateway first and falls back to `api.anthropic.com`. Wire it up by setting
`"apiKeyHelper": "~/.claude/scripts/start_proxy.sh"` and
`ANTHROPIC_BASE_URL=http://127.0.0.1:7070` in `~/.claude/settings.local.json`.

## Secrets

No credentials live in this repo. Everything sensitive goes in `~/.claude/.env.local`
or the generated `~/.claude/anthropic_key.sh`, both gitignored.

## Local overrides

`~/.claude/settings.local.json` is not tracked and takes precedence over `settings.json` —
use it for anything machine-specific (extra permissions, per-machine API config).
Note that `use_subscription.sh` deletes that file, so keep unrelated overrides elsewhere
if you switch modes often.

## Not tracked

Claude Code regenerates its runtime state (`projects/`, `sessions/`, `history.jsonl`,
`telemetry/`, `file-history/`, …) on its own. It's all gitignored — it's large, machine-local,
and contains conversation content.
