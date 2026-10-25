#!/bin/bash
# Films Cap being tapped, for the review page (build/review/cap-touch/): his sky on Today, the cast with a tap on each pose, and
# a session's answer panel.
#
#   scripts/cap_anim/films_touch.sh <udid> <out-dir> [name ...]     (no names = all)
#
# The app must be installed on <udid>. Each film is `scripts/film.sh` through `simq run media`, with CRAMLESS_CAP_CLIPS=1 (the
# harness shows Cap still unless asked), CRAMLESS_CAP_POKE (taps every Cap on screen at those times) and CRAMLESS_CAP_SEED
# (so his rolls and his words repeat). See `CapView.touch()`.
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

# Today: four single taps, then four quick ones in a row (he gets flustered).
film touch-today 22 CRAMLESS_CAP_SEED=3 CRAMLESS_CAP_POKE=2500,7500,12000,16000,16300,16600,16900
# Every pose of the cast, then a tap on it.
film touch-cast 196 CRAMLESS_FEELLAB=cast CRAMLESS_CAST_POKE=1 CRAMLESS_CAP_SEED=11
# A session: three answers, each panel's Cap tapped 2 s after it opens.
film touch-session 40 CRAMLESS_ROUTE=session CRAMLESS_SESSION_AUTOPLAY=rrp CRAMLESS_AUTOPLAY_BEAT=5200 CRAMLESS_MOCK_AI=0 \
  CRAMLESS_SESSION_MINUTES=5 CRAMLESS_CAP_SEED=21 CRAMLESS_CAP_POKE=2000
