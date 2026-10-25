#!/bin/bash
# The Cramless backend on this Mac, for tests against real services: Postgres, Auth, PostgREST, Storage and the
# Kong gateway (`supabase start`, project `cramless`, ports 584xx) plus the Edge Functions in MOCK mode
# (`supabase functions serve`: the AI routes answer with the fixtures after real auth, validation and quotas).
#
#   scripts/local_stack.sh up      start the stack and the functions, wait until the relay answers, print `env`
#   scripts/local_stack.sh down    stop the functions, then `supabase stop --no-backup` (this project only)
#   scripts/local_stack.sh env [--service] [--test-runner | --deno]
#       the API URL and anon key as export lines; the service key only with --service.
#       Default names CRAMLESS_LOCAL_STACK_URL / _ANON_KEY / _SERVICE_KEY; --test-runner adds the TEST_RUNNER_
#       prefix xcodebuild forwards to the test host; --deno prints the names the Deno tests read.
#
#   eval "$(scripts/local_stack.sh env --service --test-runner)"
#   SIM_ID=<udid> scripts/xc.sh test -only-testing:CramlessTests/LocalStackTests
#
# Only the `cramless` project's containers are touched: other local stacks on this Mac keep running. Studio,
# analytics, vector, imgproxy, the mail catcher, realtime and postgres-meta are not started. The functions' env file
# (MOCK mode, no keys), the serve log and its pid live in $LOCAL_STACK_DIR (default build/local-stack, gitignored);
# supabase/functions/.env is never read or written.
set -u
cd "$(dirname "$0")/.." || exit 2

state=${LOCAL_STACK_DIR:-build/local-stack}
# The names `supabase start -x` accepts (CLI 2.109; its --help lists older aliases it rejects). The edge runtime is
# started by `functions serve` below, with the MOCK env file.
excluded=edge-runtime,imgproxy,logflare,mailpit,postgres-meta,realtime,studio,supavisor,vector

containers() { docker ps --format '{{.Names}}' | grep -E '^supabase_.+_cramless$'; }

status_env() { supabase status -o env 2>/dev/null; }

# A value from `supabase status -o env` (NAME="value").
value() { printf '%s\n' "$1" | sed -n "s/^$2=\"\{0,1\}\([^\"]*\)\"\{0,1\}\$/\1/p" | head -1; }

serve_pid() {
  local pid
  pid=$(cat "$state/functions.pid" 2>/dev/null) || return 1
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && echo "$pid"
}

print_env() {
  local service=0 prefix="" deno=0 status url anon key
  for arg in "$@"; do
    case $arg in
      --service) service=1 ;;
      --test-runner) prefix=TEST_RUNNER_ ;;
      --deno) deno=1 ;;
      *) echo "usage: scripts/local_stack.sh env [--service] [--test-runner | --deno]" >&2; exit 2 ;;
    esac
  done
  status=$(status_env) || { echo "The cramless stack isn't running (scripts/local_stack.sh up)." >&2; exit 1; }
  url=$(value "$status" API_URL)
  anon=$(value "$status" ANON_KEY)
  [ -n "$url" ] && [ -n "$anon" ] || { echo "supabase status gave no API_URL/ANON_KEY." >&2; exit 1; }
  if [ "$deno" = 1 ]; then
    echo "export CRAMLESS_TEST_SUPABASE_URL=$url"
    echo "export CRAMLESS_TEST_ANON_KEY=$anon"
    [ "$service" = 1 ] && echo "export CRAMLESS_TEST_SERVICE_KEY=$(value "$status" SERVICE_ROLE_KEY)"
  else
    echo "export ${prefix}CRAMLESS_LOCAL_STACK_URL=$url"
    echo "export ${prefix}CRAMLESS_LOCAL_STACK_ANON_KEY=$anon"
    [ "$service" = 1 ] && echo "export ${prefix}CRAMLESS_LOCAL_STACK_SERVICE_KEY=$(value "$status" SERVICE_ROLE_KEY)"
  fi
  return 0
}

up() {
  if status_env >/dev/null; then
    echo "The cramless stack is already running."
  else
    supabase start -x "$excluded" || { echo "supabase start failed"; exit 1; }
  fi
  mkdir -p "$state"
  # MOCK mode on a local stack; every key stays empty (see supabase/functions/.env.example).
  cat > "$state/functions.env" <<'ENV'
CRAMLESS_MOCK=1
APPLE_BUNDLE_ID=com.loopware.Capling
CRAMLESS_ALLOW_XCODE_JWS=1
ANTHROPIC_API_KEY=
ANTHROPIC_BASE_URL=
APPLE_APP_ID=
CRAMLESS_INVITE_BASE_URL=
ENV
  if pid=$(serve_pid); then
    echo "supabase functions serve is already running (pid $pid)."
  else
    nohup supabase functions serve --env-file "$state/functions.env" < /dev/null > "$state/functions.log" 2>&1 &
    echo $! > "$state/functions.pid"
  fi

  local status url code=000
  status=$(status_env)
  url=$(value "$status" API_URL)
  # The relay is up when it refuses a request without a session in its own envelope.
  for _ in $(seq 1 60); do
    code=$(curl -s -o "$state/probe.json" -w '%{http_code}' "$url/functions/v1/ai/quota" \
      -H "apikey: $(value "$status" ANON_KEY)" 2>/dev/null)
    [ "$code" = 401 ] && grep -q '"unauthorized"' "$state/probe.json" && break
    serve_pid >/dev/null || { echo "supabase functions serve exited:"; tail -20 "$state/functions.log"; exit 1; }
    sleep 2
  done
  rm -f "$state/probe.json"
  if [ "$code" != 401 ]; then
    echo "The functions didn't answer in time (last HTTP $code). Log: $state/functions.log"
    exit 1
  fi
  echo "Ready: $url (functions in MOCK mode, log $state/functions.log)"
  print_env
}

down() {
  local pid children
  if pid=$(serve_pid); then
    # `supabase` may be a Node wrapper around the CLI binary: stop the binary too.
    children=$(pgrep -P "$pid")
    kill -TERM $children "$pid" 2>/dev/null
    for _ in $(seq 1 20); do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
    kill -KILL $children "$pid" 2>/dev/null
  fi
  rm -f "$state/functions.pid"
  supabase stop --no-backup
  local left
  left=$(containers)
  if [ -n "$left" ]; then
    echo "Still running:"; echo "$left"; exit 1
  fi
  echo "The cramless stack is stopped (no supabase_*_cramless containers)."
}

case ${1:-} in
  up) up ;;
  down) down ;;
  env) shift; print_env "$@" ;;
  *) echo "usage: scripts/local_stack.sh up | down | env [--service] [--test-runner | --deno]"; exit 2 ;;
esac
