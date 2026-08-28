#!/usr/bin/env bash
# Run Claude Code against a self-hosted vLLM server, given only its address.
#
#   claude-vllm.sh 10.0.0.5:8000 [claude args...]
#
# Run "claude-vllm.sh install" once to symlink this script onto your PATH as
# `claude-vllm`, so you can drop the .claude/scripts prefix from then on.
#
# Discovers the served model from /v1/models, then picks a transport:
#   direct - the server already answers Anthropic /v1/messages; talk to it as-is.
#   proxy  - it only speaks OpenAI; start a LiteLLM translator on localhost and
#            shut it down again when Claude Code exits.
#
# Reads VLLM_URL / VLLM_API_KEY / VLLM_MODEL from ~/.claude/.env.local if present, so a
# key never has to be typed on the command line. Env vars already set win over the file.
# Other overrides: VLLM_PROXY_PORT, VLLM_INSECURE_TLS=1 (self-signed certificate).
set -euo pipefail

die()  { echo "vllm: $*" >&2; exit 1; }
note() { echo "vllm: $*" >&2; }

# ------------------------------------------------------------- self-install ---
if [ "${1:-}" = "install" ] || [ "${1:-}" = "--install" ]; then
  SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  BIN_DIR="$HOME/.local/bin"
  mkdir -p "$BIN_DIR"
  ln -sf "$SELF" "$BIN_DIR/claude-vllm"
  note "linked $BIN_DIR/claude-vllm -> $SELF"
  case ":$PATH:" in
    *":$BIN_DIR:"*) note "ready — run: claude-vllm <host:port>" ;;
    *) note "add this to your shell rc (~/.zshrc or ~/.bashrc), then restart your shell:"
       note "  export PATH=\"$BIN_DIR:\$PATH\"" ;;
  esac
  exit 0
fi

# ------------------------------------------------------------- credentials ---
ENV_FILE="$HOME/.claude/.env.local"
if [ -f "$ENV_FILE" ]; then
  for var in VLLM_URL VLLM_API_KEY VLLM_MODEL VLLM_INSECURE_TLS; do
    eval "cur=\${$var:-}"
    if [ -z "$cur" ]; then
      val=$(sed -n "s/^[[:space:]]*\(export[[:space:]][[:space:]]*\)\{0,1\}$var=//p" "$ENV_FILE" \
            | tail -1 | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'\$//")
      if [ -n "$val" ]; then eval "$var=\$val"; fi
    fi
  done
fi

# ---------------------------------------------------------------- address ----
ADDR="${1:-${VLLM_URL:-}}"
if [ -z "$ADDR" ]; then
  echo "usage: claude-vllm.sh <host:port|url> [claude args...]" >&2
  echo "       or set VLLM_URL (and VLLM_API_KEY) in $ENV_FILE and pass nothing" >&2
  exit 1
fi
[ $# -gt 0 ] && shift || true
case "$ADDR" in
  http://*|https://*) ;;
  *) ADDR="http://$ADDR" ;;
esac
BASE="${ADDR%/}"; BASE="${BASE%/v1}"          # tolerate a trailing /v1
KEY="${VLLM_API_KEY:-dummy}"

# Self-signed certificate: relax it for curl here and for Claude Code's Node runtime later.
INSECURE=""
if [ "${VLLM_INSECURE_TLS:-0}" = "1" ]; then
  INSECURE="-k"
  export NODE_TLS_REJECT_UNAUTHORIZED=0
  note "TLS verification disabled (VLLM_INSECURE_TLS=1)"
fi

CODE=$(curl -s $INSECURE -o /dev/null -w '%{http_code}' --connect-timeout 5 \
       -H "Authorization: Bearer $KEY" "$BASE/v1/models" 2>/dev/null) || true
[ -n "$CODE" ] || CODE=000
case "$CODE" in
  200) ;;
  401|403) die "$BASE rejected the API key (HTTP $CODE) — check VLLM_API_KEY in $ENV_FILE" ;;
  404)     die "no /v1/models at $BASE — wrong path prefix? (HTTP 404)" ;;
  000)     die "cannot reach $BASE — server down, wrong host/port, or TLS rejected" \
               "(self-signed cert? set VLLM_INSECURE_TLS=1)" ;;
  *)       die "unexpected HTTP $CODE from $BASE/v1/models" ;;
esac

# ------------------------------------------------------------------ model ----
# One or more models. Filled in priority order — the first becomes /model
# haiku, the second /model sonnet, the third /model opus, the fourth /model
# fable — so several vLLM models can be switched between inside a session.
# An alias with no corresponding pick is left unset, not duplicated.
PICKED=()

if [ -n "${VLLM_MODEL:-}" ]; then
  old="$IFS"; IFS=','
  for m in $VLLM_MODEL; do
    m=$(echo "$m" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -n "$m" ] && PICKED[${#PICKED[@]}]="$m"
  done
  IFS="$old"
else
  if command -v jq >/dev/null 2>&1; then
    IDS=$(curl -sf $INSECURE -H "Authorization: Bearer $KEY" "$BASE/v1/models" | jq -r '.data[].id')
  else
    IDS=$(curl -sf $INSECURE -H "Authorization: Bearer $KEY" "$BASE/v1/models" \
          | tr ',' '\n' | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  fi
  MODELS=()
  while IFS= read -r line; do [ -n "$line" ] && MODELS[${#MODELS[@]}]="$line"; done <<< "$IDS"
  [ ${#MODELS[@]} -gt 0 ] || die "no models listed at $BASE/v1/models"

  if [ ${#MODELS[@]} -eq 1 ]; then
    PICKED[0]="${MODELS[0]}"
  elif [ -t 0 ]; then
    echo "vllm: models served at $BASE:" >&2
    i=0; while [ $i -lt ${#MODELS[@]} ]; do
      printf '  %2d) %s\n' "$((i+1))" "${MODELS[$i]}" >&2; i=$((i+1))
    done
    echo "vllm: pick one, or several to switch between with /model" >&2
    echo "vllm: (e.g. \"1,3\" -> 1 becomes haiku, 3 becomes sonnet)" >&2
    read -r -p "vllm: selection [1]: " pick </dev/tty
    pick="${pick:-1}"
    old="$IFS"; IFS=', '
    for n in $pick; do
      case "$n" in
        ''|*[!0-9]*) die "invalid selection: $n" ;;
      esac
      [ "$n" -ge 1 ] && [ "$n" -le ${#MODELS[@]} ] || die "selection out of range: $n"
      PICKED[${#PICKED[@]}]="${MODELS[$((n-1))]}"
    done
    IFS="$old"
    [ ${#PICKED[@]} -gt 0 ] || die "nothing selected"
    [ ${#PICKED[@]} -le 4 ] || die "at most 4 models (opus, sonnet, haiku, fable)"
  else
    PICKED[0]="${MODELS[0]}"
    note "several models served; using ${MODELS[0]} (set VLLM_MODEL to choose)"
  fi
fi

MODEL="${PICKED[0]}"                          # default / probe target

# Fill alias slots in priority order — haiku, sonnet, opus, fable — one picked
# model per slot. An alias with no corresponding pick is left unset rather
# than duplicating an earlier pick into it.
HAIKU="${PICKED[0]:-}"
SONNET="${PICKED[1]:-}"
OPUS="${PICKED[2]:-}"
FABLE="${PICKED[3]:-}"

note "models: ${PICKED[*]}"

# --------------------------------------------------------- tool-call check ---
if ! curl -sf $INSECURE -X POST -H "Authorization: Bearer $KEY" -H 'content-type: application/json' \
     "$BASE/v1/chat/completions" -d "{\"model\":\"$MODEL\",\"max_tokens\":1,\
\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\
\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"ping\",\"description\":\"ping\",\
\"parameters\":{\"type\":\"object\",\"properties\":{}}}}]}" >/dev/null 2>&1; then
  note "WARNING: the server rejected a tool-calling request. Claude Code cannot read or"
  note "         edit files without it — restart vLLM with --enable-auto-tool-choice and"
  note "         a --tool-call-parser matching this model."
fi

# --------------------------------------------------------------- transport ---
MSG_CODE=$(curl -s $INSECURE -o /dev/null -w '%{http_code}' -X POST -H "Authorization: Bearer $KEY" \
           -H 'content-type: application/json' "$BASE/v1/messages" -d '{}' || echo 000)

PROXY_PID=""
cleanup() { [ -n "$PROXY_PID" ] && kill "$PROXY_PID" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

case "$MSG_CODE" in
  404|405|501|000)
    note "no native /v1/messages (HTTP $MSG_CODE) — starting a LiteLLM translation proxy"

    if ! command -v litellm >/dev/null 2>&1; then
      yn=n
      [ -t 0 ] && read -r -p "vllm: litellm is not installed. Install it now? [y/N] " yn </dev/tty
      case "$yn" in
        [yY]*)
          if command -v uv >/dev/null 2>&1;      then uv tool install 'litellm[proxy]'
          elif command -v pipx >/dev/null 2>&1;  then pipx install 'litellm[proxy]'
          else die "need uv or pipx to install litellm"; fi ;;
        *) die "install it first:  uv tool install 'litellm[proxy]'" ;;
      esac
    fi

    PORT="${VLLM_PROXY_PORT:-4000}"
    while lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; do PORT=$((PORT+1)); done

    CFG=$(mktemp -t litellm-vllm); chmod 600 "$CFG"
    LOG="$HOME/.claude/vllm-proxy.log"; mkdir -p "$HOME/.claude"
    echo "model_list:" > "$CFG"
    for m in "${PICKED[@]}"; do
      cat >> "$CFG" <<YAML
  - model_name: $m
    litellm_params:
      model: openai/$m
      api_base: $BASE/v1
      api_key: $KEY
YAML
    done
    cat >> "$CFG" <<'YAML'
litellm_settings:
  drop_params: true
YAML
    litellm --config "$CFG" --port "$PORT" >>"$LOG" 2>&1 &
    PROXY_PID=$!

    ready=0
    for _ in $(seq 1 60); do
      if curl -sf "http://127.0.0.1:$PORT/health/liveliness" >/dev/null 2>&1; then ready=1; break; fi
      kill -0 "$PROXY_PID" 2>/dev/null || die "litellm exited — see $LOG"
      sleep 1
    done
    [ "$ready" = 1 ] || die "litellm did not come up within 60s — see $LOG"

    note "proxy ready on 127.0.0.1:$PORT (log: $LOG)"
    ENDPOINT="http://127.0.0.1:$PORT"
    ;;
  *)
    note "native Anthropic endpoint detected (HTTP $MSG_CODE) — connecting directly"
    ENDPOINT="$BASE"
    ;;
esac

# ------------------------------------------------------------ launch claude --
export ANTHROPIC_BASE_URL="$ENDPOINT"
export ANTHROPIC_AUTH_TOKEN="$KEY"
export ANTHROPIC_MODEL="$MODEL"
[ -n "$HAIKU" ]  && export ANTHROPIC_DEFAULT_HAIKU_MODEL="$HAIKU"
[ -n "$SONNET" ] && export ANTHROPIC_DEFAULT_SONNET_MODEL="$SONNET"
[ -n "$OPUS" ]   && export ANTHROPIC_DEFAULT_OPUS_MODEL="$OPUS"
[ -n "$FABLE" ]  && export ANTHROPIC_DEFAULT_FABLE_MODEL="$FABLE"

if [ ${#PICKED[@]} -gt 1 ]; then
  note "switch inside Claude Code with /model:"
  [ -n "$HAIKU" ]  && note "  /model haiku  -> $HAIKU"
  [ -n "$SONNET" ] && note "  /model sonnet -> $SONNET"
  [ -n "$OPUS" ]   && note "  /model opus   -> $OPUS"
  [ -n "$FABLE" ]  && note "  /model fable  -> $FABLE"
fi
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export DISABLE_PROMPT_CACHING=1

claude "$@"
