#!/bin/bash
# One tour film: a person's journey through the app (scripts/journeys/tour.py), recorded with real taps, the app's own sounds laid
# over it (film.sh), and the small copy the tour page plays (scripts/journeys/tour.py package).
#
#   simq run media -- scripts/journey_film.sh <udid> <out-dir> <journey> [KEY=VALUE ...]
#   JOURNEY_PACE=1.3 simq run media -- scripts/journey_film.sh $SIM build/tour readiness      every beat 1.3 times as long
#
# The app must already be installed on <udid> (a DEBUG build: xcrun simctl install <udid> build/Build/Products/Debug-iphonesimulator/Cramless.app).
# Writes <out-dir>/<journey>.mp4 (full size, 60 fps, with sound), .marks.json and .cues.json, and <out-dir>/web/<journey>.{mp4,jpg,vtt,json}.
# Rehearse first without recording: python3 scripts/journeys/tour.py try <journey> <udid>.
set -eu
cd "$(dirname "$0")/.."
udid=${1:?udid}; out=${2:?out dir}; name=${3:?journey}; shift 3
bundle=com.loopware.Capling
python3 scripts/journeys/tour.py exists "$name"
envs=()
while IFS= read -r kv; do envs+=("$kv"); done < <(python3 scripts/journeys/tour.py env "$name")
penv=()
for kv in "${envs[@]}" "$@"; do penv+=("SIMCTL_CHILD_$kv"); done

# A clean install: what a new person has (no permission granted yet, nothing left over from the last take).
python3 scripts/journeys/tour.py fresh "$udid"
# The harness shows the welcome on the first launch after an install (and Today on every one after): launch once and let go of it.
xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1 || true
env "${penv[@]}" xcrun simctl launch "$udid" "$bundle" >/dev/null
sleep 3
xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1 || true
# The first mobilecli call on a simulator starts its agent, which sends the app to the background: do that now, with the app closed.
python3 scripts/journeys/tour.py warm "$udid" >/dev/null 2>&1 || true

mkdir -p "$out"
FILM_NO_HALF=1 FILM_DRIVER="python3 scripts/journeys/tour.py run $name" scripts/film.sh "$udid" "$out" "$name" 900 "${envs[@]}" "$@"
python3 scripts/journeys/tour.py package "$name" "$out"
