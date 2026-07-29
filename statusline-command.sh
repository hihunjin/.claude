#!/bin/sh
# Status line: <cwd> | <git branch> | <model> | ctx: <n>%
# Requires jq. Fed the session JSON on stdin by Claude Code.
input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
model=$(echo "$input" | jq -r '.model.display_name // empty')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

[ -n "$cwd" ] || cwd=$(pwd)
short_cwd=$(echo "$cwd" | sed "s|^$HOME|~|")

branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)

out="$short_cwd"
[ -n "$branch" ] && out="$out | $branch"
[ -n "$model" ] && out="$out | $model"
[ -n "$used" ] && out="$out | ctx: $(printf '%.0f' "$used")%"

printf '%s' "$out"
