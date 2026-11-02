#!/bin/bash
# The eight source screens for Capling's App Store screenshots, from the demo world on a simulator (no taps).
#   scripts/store_art/capture_listing.sh <udid> [out-dir]      ->  <out>/01-today.png ... 08-streak.png   (default build/listing/src)
# The app must be installed on <udid>. Every frame is looked at before it is used: no dialogs, no Live Activity in the island, a 9:41 bar.
set -u
cd "$(dirname "$0")/../.." || exit 2
udid=${1:?udid}; out=${2:-build/listing/src}
mkdir -p "$out"
xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
shot() {  # name route wait [KEY=VALUE ...]
  local name=$1 route=$2 wait=$3; shift 3
  EXTRA="$*" WAIT=$wait scripts/shots.sh "$udid" "$out/.tmp" "$route" >/dev/null
  mv "$out/.tmp/$(echo "$route" | tr ':/' '--').png" "$out/$name.png" && echo "$out/$name.png"
}
shot 01-today today 7
shot 02-graded session 7 CRAMLESS_SESSION_STATE=graded
shot 03-exam exam 7
shot 04-questions captureFlow 12 CRAMLESS_CAPTURE_PHASE=review
shot 05-ask ask 16 CRAMLESS_ASSISTANT=cards
shot 06-sky sky 8 CRAMLESS_SKY=still
shot 07-saved session 8 CRAMLESS_SESSION_STATE=exameve-summary
shot 08-streak streak 7
rmdir "$out/.tmp" 2>/dev/null
xcrun simctl status_bar "$udid" clear
