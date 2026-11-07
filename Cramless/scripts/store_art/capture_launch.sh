#!/bin/bash
# The source screens for the launch set of Capling's App Store screenshots: the demo world with its clock pinned, light mode, US formats, no taps.
#   scripts/store_art/capture_launch.sh <udid> [out-dir] [name ...]      ->  <out>/<name>.png   (default build/listing/launch/src, every shot)
# The app must be installed on <udid>. CRAMLESS_NOW pins every number: the Chem quiz is on Sunday at 10:00. Look at every frame before it is used.
set -u
cd "$(dirname "$0")/../.." || exit 2
udid=${1:?udid}; out=${2:-build/listing/launch/src}; shift; [ $# -gt 0 ] && shift
want=" $* "
mkdir -p "$out"
bundle=com.loopware.Capling
NOW_PIN=2026-11-06T14:00:00-05:00
xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
shot() {  # name route wait [KEY=VALUE ...]   (a value may hold spaces)
  local name=$1 route=$2 wait=$3; shift 3
  [ "$want" != "  " ] && [[ "$want" != *" $name "* ]] && return
  local env_args=(SIMCTL_CHILD_CRAMLESS_UITEST=1 "SIMCTL_CHILD_CRAMLESS_ROUTE=$route" SIMCTL_CHILD_CRAMLESS_THEME=light "SIMCTL_CHILD_CRAMLESS_NOW=$NOW_PIN")
  for kv in "$@"; do env_args+=("SIMCTL_CHILD_$kv"); done
  xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1
  env "${env_args[@]}" xcrun simctl launch "$udid" "$bundle" -AppleLanguages "(en-US)" -AppleLocale en_US >/dev/null || { echo "launch failed: $name"; return; }
  sleep "$wait"
  xcrun simctl io "$udid" screenshot "$out/$name.png" >/dev/null 2>&1 && echo "$out/$name.png"
}
ANSWER="To grow and repair damaged tissue. Mitosis copies the chromosomes so each new cell is identical and has the same number of chromosomes."
shot today today 7
shot plan onboarding:14 14     # the chart draws itself: wait for its last dot
shot graded session 8 CRAMLESS_SESSION_STATE=ownwords "CRAMLESS_SESSION_ANSWER=$ANSWER" CRAMLESS_MOCK_AI=0
shot exam exam:0 7
shot exam-bio exam:1 7
shot capture-checking captureFlow 8 CRAMLESS_CAPTURE_PHASE=checking
shot questions captureFlow 12 CRAMLESS_CAPTURE_PHASE=review
shot ask-cards ask 16 CRAMLESS_ASSISTANT=cards
shot ask-quiz ask 16 CRAMLESS_ASSISTANT=quiz
shot ask-problem ask 14 CRAMLESS_SNAP=asked
shot lecture-notes lectureNotes 7
shot lecture-cued lectureNotes 7 CRAMLESS_NOTES_FOCUS=725
shot sky sky 8 CRAMLESS_SKY=still
shot streak streak 7
shot mock-mcq mock:1 7 CRAMLESS_MOCK=mcq
shot outloud outLoud 7
shot notice-mixup today 8 CRAMLESS_NOTICES=mixup CRAMLESS_TODAY_SCROLL=notice
xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1
xcrun simctl status_bar "$udid" clear
