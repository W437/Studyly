#!/bin/bash
# Build or test Cramless with a watchdog.
#
#   scripts/xc.sh build                          the Cramless scheme (app + widget extension), generic iOS Simulator
#   SIM_ID=<udid> scripts/xc.sh test             the CramlessTests unit tests on that simulator
#   SIM_ID=<udid> scripts/xc.sh test -only-testing:CramlessTests/FooTests    a subset (replaces the default)
#   XC_NO_BUILD=1 SIM_ID=<udid> scripts/xc.sh test   run again without compiling (test-without-building)
#   DERIVED=<dir> scripts/xc.sh build            use another derived-data folder (default: build)
#
# It regenerates the Xcode project first (project.yml is the source of truth), writes the full log to
# build/xc-<action>.log, prints the errors and the verdict, and exits 0 only on success. xcodebuild sometimes
# sits for minutes after the last test while the simulator collects diagnostics, so a watchdog stops it once
# the suite has finished.
set -u
cd "$(dirname "$0")/.." || exit 2

action=${1:-build}
shift || true
derived=${DERIVED:-build}
mkdir -p "$derived"
log="$derived/xc-$action.log"

# Secrets.xcconfig is gitignored; a fresh checkout has none and the project references it.
if [ ! -f Secrets.xcconfig ]; then
  printf '%s\n' '// Gitignored. Blank values: the app runs with on-device and offline AI only (no relay, no sync).' \
    '// The host only, without https:// (xcconfig reads // as a comment), for example abcdefgh.supabase.co' \
    'CRAMLESS_SUPABASE_HOST =' 'CRAMLESS_SUPABASE_ANON_KEY =' > Secrets.xcconfig
fi

xcodegen generate --quiet || { echo "xcodegen failed"; exit 2; }

args=(-project Cramless.xcodeproj -scheme Cramless -derivedDataPath "$derived" CODE_SIGNING_ALLOWED=NO)
case $action in
  build)
    args+=(-destination 'generic/platform=iOS Simulator' build)
    ;;
  test)
    [ -n "${SIM_ID:-}" ] || { echo "SIM_ID is not set. Pick one from: xcrun simctl list devices available"; exit 2; }
    args+=(-destination "platform=iOS Simulator,id=$SIM_ID")
    if [ $# -eq 0 ]; then args+=(-only-testing:CramlessTests); else args+=("$@"); fi
    if [ "${XC_NO_BUILD:-}" = 1 ]; then args+=(test-without-building); else args+=(test); fi
    ;;
  *) echo "usage: scripts/xc.sh build | test [xcodebuild args]"; exit 2 ;;
esac

# simq's xcodebuild wrapper shares one compile cache between worktrees and, for that, rewrites source paths to /^src/…. A few
# tests find the source folder through #filePath (LocalizationTests, PaywallCopyTests) or write PNGs into docs/ with it
# (GameRenderTests, WidgetRenderTests), and fail on the rewritten path ("no such file", "volume is read only"). The tests build
# without the cache.
[ "$action" = test ] && export SIMQ_NO_CACHE=1

xcodebuild "${args[@]}" > "$log" 2>&1 &
pid=$!
finished_at=0
while kill -0 "$pid" 2>/dev/null; do
  sleep 3
  if [ "$action" = test ] && [ "$finished_at" -eq 0 ] && grep -qE "Test Suite '(All|Selected) tests' (passed|failed)" "$log"; then
    finished_at=$(date +%s)
  fi
  if [ "$finished_at" -ne 0 ] && [ $(( $(date +%s) - finished_at )) -gt 25 ]; then
    echo "(xcodebuild did not exit 25 s after the suite finished; stopping it)"
    pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null
    break
  fi
done
wait "$pid" 2>/dev/null
code=$?

# Compiler and tool errors only (runtime log lines in a test run also say "error:").
grep -E ":[0-9]+:[0-9]+: error:|^error:|xcodebuild: error|ld: error|Command .* failed" "$log" \
  | grep -v "appintentsnltrainingprocessor" | sort -u | head -40
if [ "$action" = build ]; then
  if grep -q "\*\* BUILD SUCCEEDED \*\*" "$log"; then
    scripts/sync_strings.sh "$derived" || echo "(the String Catalogs didn't sync)"
    echo "** BUILD SUCCEEDED **"; exit 0
  fi
  echo "** BUILD FAILED ** (log: $log)"; exit 1
fi

failed=$(grep -E "Test Case .* failed" "$log" | sort -u)
[ -n "$failed" ] && echo "$failed" | head -40
summary=$(grep -E "Executed [0-9]+ tests?, with .*failures?" "$log" | tail -1 | sed 's/^[[:space:]]*//')
echo "${summary:-no test summary found}"
# When the test host crashes, xcodebuild starts it again for the tests that are left and the final totals describe
# that second launch only: a crashing test reads as green. Never trust that.
if grep -q "Restarting after unexpected exit" "$log"; then
  echo "** THE TEST HOST CRASHED AND WAS RESTARTED ** the totals above are the last launch's only. Failing tests, if any:"
  sed -n '/^Failing tests:/,/^$/p' "$log" | head -20
  echo "(log: $log)"; exit 1
fi
if grep -qE "Test Suite '(All|Selected) tests' passed" "$log"; then
  scripts/sync_strings.sh "$derived" || echo "(the String Catalogs didn't sync)"
  echo "** TEST SUCCEEDED **"; exit 0
fi
echo "** TEST FAILED ** (log: $log, exit $code)"; exit 1
