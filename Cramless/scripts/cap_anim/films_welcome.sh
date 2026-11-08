#!/bin/bash
# Films the welcome and the demo pages for the review page (build/review/welcome-v2/): the welcome with touches (the sounds laid
# over the notes), with nobody touching (Cap lights the stars himself), with Reduce Motion, and the two intro pages that changed.
#
#   scripts/cap_anim/films_welcome.sh <udid> <out-dir> [name ...]     (no names = all)
#
# The app must be installed on <udid>. Each film is `scripts/film.sh` through `simq run media`, with CRAMLESS_CAP_CLIPS=1 and
# CRAMLESS_SOUNDS=1 (film.sh mixes the app's own notes in at the logged times). CRAMLESS_WELCOME=2600:s1,4400:s4 taps stars by index
# (see WelcomeWorld.runHooks), the same path a finger takes. The Simulator has no motion sensor, so the layers sway on their own.
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
  simq run media -- scripts/film.sh "$udid" "$out" "$name" "$secs" CRAMLESS_CAP_CLIPS=1 CRAMLESS_SOUNDS=1 "$@"
}

# Three touches: the back corner, the right corner, the left. The third lights the rest, the arc of light climbs, Cap cheers.
film welcome-touch 17 CRAMLESS_ONBOARDING=1 CRAMLESS_WELCOME=3200:s1,5200:s4,7200:s0
# Nobody touches: he says hello, says "go on", lights the first star himself, then the next two, and the cap is lit.
film welcome-alone 27 CRAMLESS_ONBOARDING=1
# Reduce Motion: no clips, no ripples, no ignition; the stars light at once and the sky brightens. The sounds still play.
film welcome-calm 13 CRAMLESS_ONBOARDING=1 CRAMLESS_REDUCE_MOTION=1 CRAMLESS_WELCOME=3200:s1,5000:s4,6800:s0
# The old intro's first two demos (they left onboarding and stay for films and store art): the scan that makes flashcards and
# questions, and the flashcards page. `introScene:<n>` opens one as a cover over Today, so no hidden welcome plays under it.
film intro-snap 14 CRAMLESS_ROUTE=introScene:1
film intro-flashcards 16 CRAMLESS_ROUTE=introScene:2
