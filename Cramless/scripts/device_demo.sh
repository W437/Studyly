#!/bin/bash
# Opens the isolated build (scripts/device_isolated.sh) on a connected phone in DEMO mode, on the Ask tab: the seeded Bio 101 world,
# the mock relay's scripted replies (so Ask Cap's assistant works without a server: "Make me flashcards on mitosis", "Quiz me
# on mitosis", "Write me a note summarising mitosis", "Plan my midterm for 12 November", "Research mitosis vs meiosis online"),
# Cap's own sounds and clips, and the phone's real haptics.
#
#   scripts/device_demo.sh <device-udid>
#
# Why it is needed: the assistant only runs through the relay, and a build with no Supabase project (the default) has none, so
# opened from its icon it hides the assistant. This launches it with the DEBUG demo switches instead. Nothing is saved: the
# harness keeps everything in memory, so closing the app and opening it from its icon gives the normal, empty app again. The phone
# must be unlocked (a locked phone refuses the launch).
set -u
udid=${1:?usage: scripts/device_demo.sh <device-udid>}
cd "$(dirname "$0")/.." || exit 1

state=$(xcrun devicectl list devices 2>/dev/null | grep "$udid" | head -1)
echo "device: ${state:-not listed}"
# "unavailable" contains "available": the phone is off, locked or not on this network.
case "$state" in
  *unavailable*) echo "the device is unavailable (off, locked or not on this network); nothing was launched"; exit 2 ;;
  *available*|*connected*) ;;
  *) echo "the device is not connected; nothing was launched"; exit 2 ;;
esac

launched=$(xcrun devicectl device process launch --device "$udid" --terminate-existing \
  --environment-variables '{"CRAMLESS_UITEST":"1","CRAMLESS_ROUTE":"ask","CRAMLESS_SOUNDS":"1","CRAMLESS_CAP_CLIPS":"1"}' \
  com.loopware.Capling 2>&1)
if echo "$launched" | grep -qi "locked"; then echo "the phone is locked: unlock it and run this again"; exit 2; fi
if echo "$launched" | grep -qi "not installed\|could not be found\|no such"; then
  echo "Capling isn't installed on it: run scripts/device_isolated.sh $udid first"; exit 3
fi
echo "$launched" | tail -2
