#!/bin/bash
# Films Cap's clips in the app, in the places he lives, for the review page.
#
#   scripts/cap_anim/films.sh <udid> <out-dir> [name ...]     (no names = all)
#
# The app must be installed on <udid> (a simulator from `simq sim --udid`). Each film is `scripts/film.sh` with
# CRAMLESS_CAP_CLIPS=1 (the harness shows Cap still unless it is asked), run through `simq run media` so the Mac isn't
# asked for more recording and encoding than it has room for. Films come out as H.264 at a constant 60 fps, level 5.1.
set -u
cd "$(dirname "$0")/../.." || exit 2
udid=${1:?udid}; out=${2:?out dir}; shift 2
want=("$@")

film() {
  local name=$1 secs=$2; shift 2
  if [ ${#want[@]} -gt 0 ]; then
    local ok=0; for w in "${want[@]}"; do [ "$w" = "$name" ] && ok=1; done
    [ $ok = 1 ] || return 0
  fi
  echo "== $name ($secs s)"
  simq run media -- scripts/film.sh "$udid" "$out" "$name" "$secs" CRAMLESS_CAP_CLIPS=1 "$@"
}

# Every pose in turn, large, in one view (so each change of pose is the app's real transition).
film cast 100 CRAMLESS_FEELLAB=cast
# Today's four states: the sky and a telescope, a finished day, nothing due, exam eve asleep.
film today-sky 10
film today-done 10 CRAMLESS_TODAY=done
film today-rest 10 CRAMLESS_TODAY=caughtUp
film today-eve 10 CRAMLESS_TODAY=eveDone
# A whole session: right, right, right, right, right (a run of five), partly, wrong, "I don't know".
film session 52 CRAMLESS_ROUTE=session CRAMLESS_SESSION_AUTOPLAY=rrrrrpwk CRAMLESS_AUTOPLAY_BEAT=1700 CRAMLESS_MOCK_AI=0 CRAMLESS_SESSION_MINUTES=5 CRAMLESS_SOUNDS=1
# The summary at the end of a good day, and the welcome.
film summary 12 CRAMLESS_ROUTE=session CRAMLESS_SESSION_STATE=summary CRAMLESS_CELEBRATION=big CRAMLESS_SOUNDS=1
film welcome 12 CRAMLESS_ONBOARDING=1
# The same cast with Reduce Motion on: Cap is a drawing and a pose change is a cross-fade.
film cast-reduced 24 CRAMLESS_FEELLAB=cast CRAMLESS_REDUCE_MOTION=1
