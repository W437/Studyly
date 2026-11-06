#!/bin/bash
# Films Today's sky band, for the review page: the band at rest (and a tap on it, which opens the full sky), the pull to refresh,
# exam eve, the empty state and Reduce Motion.
#
#   scripts/cap_anim/films_hero.sh <udid> <out-dir> [name ...]     (no names = all)
#
# The app must be installed on <udid>. Each film is `scripts/film.sh` through `simq run media`, with CRAMLESS_CAP_CLIPS=1,
# CRAMLESS_HERO (a tap at a point in the band: see HeroWorld.runHooks; it opens the sky) and CRAMLESS_CAP_POKE (taps Cap). The Simulator has no motion sensor, so
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

# The band at rest (it sways, stars breathe, a star falls), a tap on Cap, then a tap on the sky, which opens the full sky.
film hero-live 20 CRAMLESS_CAP_SEED=4 CRAMLESS_CAP_POKE=6000 CRAMLESS_HERO=14000:x200y120
# Reduce Motion: the band holds still (no sway, no twinkle, no shooting star); a pull only brightens it.
film hero-calm 10 CRAMLESS_REDUCE_MOTION=1 CRAMLESS_HERO_PULL=4000:100:600
# Pull to refresh: a pull held past the line (the ridge lights up, a tick), let go: an arc of light climbs, a star falls, Cap says so
# and the pill agrees. Then a short pull that springs back and does nothing. The page itself doesn't move in these (the hook gives the
# hero the readings a finger would); the real drag, with the page moving under the pinned hero, is filmed by hand.
film hero-pull 14 CRAMLESS_CAP_SEED=4 CRAMLESS_HERO_PULL=2500:100:700,9500:50:400
film hero-pull-calm 9 CRAMLESS_REDUCE_MOTION=1 CRAMLESS_HERO_PULL=2000:100:600
# The same pull in the other states: nothing studied yet (outlines), exam eve.
film hero-pull-empty 7 CRAMLESS_TODAY=noMaterial CRAMLESS_SEED=0 CRAMLESS_HERO_PULL=2000:100:400
film hero-pull-eve 7 CRAMLESS_TODAY=examEve CRAMLESS_HERO_PULL=2000:100:400
# The same band on exam eve (one region lit, the rest receding), and with nothing studied yet (unlit outlines; a tap ripples).
film hero-eve 12 CRAMLESS_TODAY=examEve
film hero-empty 12 CRAMLESS_TODAY=noMaterial CRAMLESS_SEED=0 CRAMLESS_HERO=5000:x200y200,7000:x80y150
