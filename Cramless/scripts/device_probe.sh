#!/bin/bash
# Runs the DEBUG device probe (Cramless/App/DeviceProbe.swift) on a connected phone with the isolated build installed
# (scripts/device_isolated.sh) and copies its report to build/device_probe/report.json.
#
#   scripts/device_probe.sh <device-udid> [timeout-seconds]
#
# The phone must be unlocked (a locked phone refuses the launch). The probe runs the AI jobs on the phone's own model,
# so it can take a minute or two the first time (model and speech assets load).
set -u
udid=${1:?usage: scripts/device_probe.sh <device-udid> [timeout-seconds]}
timeout=${2:-300}
cd "$(dirname "$0")/.." || exit 1
out=build/device_probe
mkdir -p "$out"
rm -f "$out/report.json"
launched=$(xcrun devicectl device process launch --device "$udid" --terminate-existing \
  --environment-variables '{"CRAMLESS_UITEST":"1","CRAMLESS_MOCK_AI":"0","CRAMLESS_SEED":"0","CRAMLESS_PROBE":"1"}' \
  com.loopware.Capling 2>&1)
if echo "$launched" | grep -qi "locked"; then echo "the phone is locked: unlock it and run this again"; exit 2; fi
echo "$launched" | tail -1
start=$(date +%s)
while [ $(( $(date +%s) - start )) -lt "$timeout" ]; do
  sleep 10
  xcrun devicectl device copy from --device "$udid" --domain-type appDataContainer \
    --domain-identifier com.loopware.Capling --source Documents/probe-report.json \
    --destination "$out/report.json" > /dev/null 2>&1 || continue
  if grep -q '"done" : true' "$out/report.json" 2>/dev/null; then
    echo "probe finished in $(( $(date +%s) - start )) s: $out/report.json"; exit 0
  fi
done
echo "the probe didn't finish within $timeout s; the partial report (if any) is $out/report.json"; exit 1
