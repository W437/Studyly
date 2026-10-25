#!/bin/bash
# Taps Cap eighteen times in 70 seconds on Today's sky, films it and counts the frames where he is missing.
#
#   scripts/cap_anim/stress_taps.sh <udid>
#
# Run it after any change to `CapClipPlayer`, `CapStage` or `CapView`'s clip handling. Each tap ends in a hand-off from his
# reaction back to the idle loop: the place where a video layer (Core Animation) and the drawing under it (SwiftUI) race, and a
# blink of one or two frames is invisible in a screenshot. The app must be installed on <udid>. Exits 1 on any dropout.
set -u
cd "$(dirname "$0")/../.." || exit 2
udid=${1:?udid}
out=build/films/cap-stress
mkdir -p "$out"
pokes=$(python3 -c "print(','.join(str(2000 + 3700 * i) for i in range(18)))")
simq run media -- scripts/film.sh "$udid" "$out" touch-stress 72 CRAMLESS_CAP_CLIPS=1 CRAMLESS_CAP_SEED=9 CRAMLESS_CAP_POKE="$pokes" > "$out/film.log" 2>&1 \
  || { echo "the film failed: see $out/film.log"; exit 2; }
python3 scripts/cap_anim/film_gaps.py "$out/touch-stress.mp4" --box 20 640 440 400 --skip 1.0
