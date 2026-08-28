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
| `scripts/claude-vllm.sh` | Run Claude Code against a self-hosted vLLM server, given only its address |
| `install.sh` | Symlinks everything into `~/.claude/` |
| `.env.local.example` | Template for machine-local secrets |

### Slash commands

Re-run the same prompt on a different model or reasoning effort:

| Model | low | medium | high | xhigh | max |
| --- | --- | --- | --- | --- | --- |
| Fable 5 | `/fl` | `/f` | `/fh` | `/fx` | `/fm` |
| Sonnet 5 | `/sl` | `/s` | `/sh` | `/sx` | `/sm` |
| Opus 5 | `/ol` | `/o` | `/oh` | `/ox` | `/om` |

Plus `/h` — Haiku 4.5, which has no effort levels.

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

## Self-hosted vLLM

`scripts/claude-vllm.sh` points Claude Code at your own vLLM server. Give it the address
and nothing else — it asks `/v1/models` what is being served, and picks the transport:

```bash
~/.claude/scripts/claude-vllm.sh 10.0.0.5:8000            # host:port
~/.claude/scripts/claude-vllm.sh https://vllm.example.com # or a full URL, incl. a path prefix
~/.claude/scripts/claude-vllm.sh 10.0.0.5:8000 --print "explain this repo"
```

Run `claude-vllm.sh install` once to symlink it onto your PATH (`~/.local/bin/claude-vllm`),
so you can drop the `.claude/scripts` prefix and just run `claude-vllm 10.0.0.5:8000`.

If several models are served it lists them and asks. You can pick more than one — enter
`1,3` and they are mapped onto Claude Code's model aliases in order, so `/model` switches
between them inside the session:

```
vllm:   /model opus   -> Qwen/Qwen3-32B
vllm:   /model sonnet -> mistralai/Devstral-Small
```

Up to three (opus, sonnet, haiku); unused aliases fall back to the first. `VLLM_MODEL`
accepts the same thing as a comma-separated list. In proxy mode each model is registered
under its real id too, so `/model <exact-id>` also works.

Credentials and defaults come from
`~/.claude/.env.local` (gitignored, same file the gateway scripts use), so with `VLLM_URL`
and `VLLM_API_KEY` set there the command is just `claude-vllm.sh` with no arguments:

| Variable | Meaning |
| --- | --- |
| `VLLM_URL` | Server address — `host:port` or a full URL |
| `VLLM_API_KEY` | Key the server expects (default `dummy` if it needs none) |
| `VLLM_MODEL` | Pin a model id, or several comma-separated, instead of being asked |
| `VLLM_INSECURE_TLS` | `1` for a self-signed certificate |
| `VLLM_PROXY_PORT` | First port tried for the LiteLLM proxy (default 4000) |

An exported variable always wins over the file. Failures are reported distinctly — rejected
key, wrong path prefix, unreachable host — rather than as one generic error.

Claude Code speaks the Anthropic Messages API, vLLM usually speaks OpenAI, so the script
probes `POST /v1/messages`:

- **present** — it connects straight to the server.
- **absent** — it starts a LiteLLM proxy on localhost that translates Anthropic to OpenAI,
  and kills it again when Claude Code exits. LiteLLM must be installed
  (`uv tool install 'litellm[proxy]'`); the script offers to do it. Log:
  `~/.claude/vllm-proxy.log`.

Env vars are set for that one process only, so your normal `claude` is untouched — no
`settings.local.json` involved, nothing to revert.

Serve the model with tool calling enabled or Claude Code cannot read or edit anything:

```bash
vllm serve <model> --enable-auto-tool-choice --tool-call-parser hermes --max-model-len 32768
```

(the parser must match the model — `hermes`, `llama3_json`, `mistral`, …). The script warns
if a tool-calling request is rejected. Expect the agent loop to struggle on small models;
that is the model, not the config.

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
