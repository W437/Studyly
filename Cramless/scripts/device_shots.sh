#!/bin/bash
# Captures the real display of a connected phone while the isolated build (scripts/device_isolated.sh) shows each route
# (CRAMLESS_ROUTE, with the demo world). Captures only while Cramless is running in front; a locked phone stops it.
#
#   scripts/device_shots.sh <device-udid> [folder] [route ...]       folder defaults to build/device_shots
set -u
udid=${1:?usage: scripts/device_shots.sh <device-udid> [folder] [route ...]}
out=${2:-build/device_shots}
shift 2 2>/dev/null || shift $#
routes=${*:-"today session exam library ask progress"}
cd "$(dirname "$0")/.." || exit 1
mkdir -p "$out"
for route in $routes; do
  launched=$(xcrun devicectl device process launch --device "$udid" --terminate-existing \
             --environment-variables "{\"CRAMLESS_UITEST\":\"1\",\"CRAMLESS_ROUTE\":\"$route\"}" com.loopware.Capling 2>&1)
  if echo "$launched" | grep -qi "locked"; then echo "the phone is locked: stopped at $route"; exit 2; fi
  sleep 6
  pid=$(xcrun devicectl device info processes --device "$udid" 2>/dev/null | grep 'Cramless.app/Cramless ' | awk '{print $1}' | head -1)
  if [ -z "$pid" ]; then echo "  $route: Cramless is not running, nothing captured"; continue; fi
  name=$(echo "$route" | tr ':/' '--')
  xcrun devicectl device capture screenshot --device "$udid" --destination "$out/$name.png" > /dev/null 2>&1 \
    && echo "  $route: $out/$name.png" || echo "  $route: the capture failed"
  xcrun devicectl device process terminate --device "$udid" --pid "$pid" > /dev/null 2>&1
done
