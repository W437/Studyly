#!/usr/bin/env bash
# Runs a command holding one machine-wide lock, so renders started by agents working in
# parallel (in this project or any other) queue instead of fighting for the CPU.
#   scripts/one-at-a-time.sh npx remotion render …
# A lock whose owner died (a render killed with SIGKILL) is cleared automatically.
LOCK=${RENDER_LOCK:-${TMPDIR:-/tmp}/remotion-render.lock}
waited=0
until mkdir "$LOCK" 2>/dev/null; do
  pid=$(cat "$LOCK/pid" 2>/dev/null)
  if [[ -n $pid ]] && ! kill -0 "$pid" 2>/dev/null; then
    rm -rf "$LOCK"
    continue
  fi
  if (( waited == 0 )); then echo "waiting for the render lock ($LOCK, held by ${pid:-?})…" >&2; fi
  waited=1
  sleep 3
done
echo $$ > "$LOCK/pid"
trap 'rm -rf "$LOCK"' EXIT INT TERM
"$@"
