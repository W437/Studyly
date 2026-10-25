#!/bin/bash
# Films Today's hero as a world, for the review page (build/review/cap-touch/): the world at rest and being tapped, exam eve, the
# empty state and the largest text.
#
#   scripts/cap_anim/films_hero.sh <udid> <out-dir> [name ...]     (no names = all)
#
# The app must be installed on <udid>. Each film is `scripts/film.sh` through `simq run media`, with CRAMLESS_CAP_CLIPS=1,
# CRAMLESS_HERO (taps in the hero: see HeroWorld.runHooks) and CRAMLESS_CAP_POKE (taps Cap). The Simulator has no motion sensor, so
# the layers sway on their own: that is the tilt parallax a phone gives by being moved.
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

# The world at rest (it sways, stars breathe, a star falls), then a tap on a constellation, its card, a tap on Cap, and back.
film hero-live 30 CRAMLESS_CAP_SEED=4 CRAMLESS_HERO=3500:c2,10500:close,13500:x300y180,16000:c9,23500:close CRAMLESS_CAP_POKE=26500
# Pull to refresh: a pull held past the line (the ridge lights up, a tick), let go: an arc of light climbs, a star falls, Cap says so
# and the pill agrees. Then a short pull that springs back and does nothing. The page itself doesn't move in these (the hook gives the
# hero the readings a finger would); the real drag, with the page moving under the pinned hero, is filmed by hand.
film hero-pull 14 CRAMLESS_CAP_SEED=4 CRAMLESS_HERO_PULL=2500:100:700,9500:50:400
film hero-pull-calm 9 CRAMLESS_REDUCE_MOTION=1 CRAMLESS_HERO_PULL=2000:100:600
# The same pull in the other states: nothing studied yet (outlines), a constellation in focus (it lets go), exam eve.
film hero-pull-empty 7 CRAMLESS_TODAY=noMaterial CRAMLESS_SEED=0 CRAMLESS_HERO_PULL=2000:100:400
film hero-pull-focus 9 CRAMLESS_HERO=1200:c2 CRAMLESS_HERO_PULL=3800:100:400
film hero-pull-eve 7 CRAMLESS_TODAY=examEve CRAMLESS_HERO_PULL=2000:100:400
# The same world on exam eve (one region lit, the rest receding, still), and with nothing studied yet (unlit outlines).
film hero-eve 12 CRAMLESS_TODAY=examEve
film hero-empty 12 CRAMLESS_TODAY=noMaterial CRAMLESS_SEED=0 CRAMLESS_HERO=5000:x200y200,7000:x80y150
