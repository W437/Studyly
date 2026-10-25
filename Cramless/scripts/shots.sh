#!/bin/bash
# Screenshot harness routes headlessly (no taps).
#
#   scripts/shots.sh <udid> <out-dir> <route> [route ...]
#   THEME=dark scripts/shots.sh <udid> shots/dark today exam session
#   WAIT=6 EXTRA="CRAMLESS_SEED=0" scripts/shots.sh <udid> shots/empty today
#
# Each route is launched fresh with CRAMLESS_UITEST=1 and CRAMLESS_ROUTE=<route> (see App/TestHarness.swift),
# shot after WAIT seconds (default 4), and saved as <out-dir>/<route>.png (":" becomes "-"). The app must already
# be installed (scripts/xc.sh build, then xcrun simctl install <udid> build/Build/Products/Debug-iphonesimulator/Cramless.app).
# EXTRA adds more KEY=VALUE launch variables (space-separated); THEME=dark|light; NOW=<ISO 8601> freezes the clock.
# SHOT_LANG=es (or ja, ar, …) runs the app in that language. PSEUDO=bounded|double|rtl runs a pseudo-language: bounded
# wraps every localized string in [# … #] (text without brackets isn't localized yet), double doubles each one
# (room for longer languages), rtl lays everything out right to left.
set -u
udid=${1:?udid}; out=${2:?out dir}; shift 2
mkdir -p "$out"
wait_s=${WAIT:-4}
bundle=com.loopware.Capling
for route in "$@"; do
  env_args=(SIMCTL_CHILD_CRAMLESS_UITEST=1 "SIMCTL_CHILD_CRAMLESS_ROUTE=$route")
  [ -n "${THEME:-}" ] && env_args+=("SIMCTL_CHILD_CRAMLESS_THEME=$THEME")
  [ -n "${NOW:-}" ] && env_args+=("SIMCTL_CHILD_CRAMLESS_NOW=$NOW")
  for kv in ${EXTRA:-}; do env_args+=("SIMCTL_CHILD_$kv"); done
  launch_args=()
  if [ -n "${SHOT_LANG:-}" ]; then launch_args+=(-AppleLanguages "($SHOT_LANG)" -AppleLocale "$SHOT_LANG"); fi
  case "${PSEUDO:-}" in
    bounded) launch_args+=(-NSSurroundLocalizedStrings YES) ;;
    double) launch_args+=(-NSDoubleLocalizedStrings YES) ;;
    rtl) launch_args+=(-NSForceRightToLeftWritingDirection YES -AppleTextDirection YES) ;;
  esac
  xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1
  env "${env_args[@]}" xcrun simctl launch "$udid" "$bundle" ${launch_args[@]+"${launch_args[@]}"} >/dev/null || { echo "launch failed: $route"; continue; }
  sleep "$wait_s"
  name=$(echo "$route" | tr ':/' '--')
  xcrun simctl io "$udid" screenshot "$out/$name.png" >/dev/null 2>&1 && echo "$out/$name.png"
done
xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1
exit 0
