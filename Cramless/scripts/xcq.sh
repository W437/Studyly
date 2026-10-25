#!/bin/bash
# scripts/xc.sh, patient: the Mac is shared by about ten agent sessions, and `simq` lets one build and two simulators run at
# a time. When it has no slot it waits 90 s, then exits 75 with "Run the same command again to keep your place". This runs the
# same command again until it gets one (or XCQ_ATTEMPTS, default 80, is used up), and otherwise behaves exactly like xc.sh.
#
#   scripts/xcq.sh build
#   SIM_ID=<udid> scripts/xcq.sh test -only-testing:CramlessTests/CapPoseTests
set -u
cd "$(dirname "$0")/.." || exit 2
action=${1:-build}
log="${DERIVED:-build}/xc-$action.log"
for attempt in $(seq 1 "${XCQ_ATTEMPTS:-80}"); do
  scripts/xc.sh "$@"
  code=$?
  if grep -q "keep your place (exit 75)" "$log" 2>/dev/null; then
    echo "(queued behind other sessions; attempt $attempt)"
    continue
  fi
  exit $code
done
echo "gave up waiting for a slot"
exit 75
