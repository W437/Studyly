#!/bin/bash
# The stills for the game loop's review page (build/review/game-loop/stills/): every screen it touches, taken headlessly (no taps) and
# saved as small JPEGs, plus the art sheets from the render tests (docs/shots/game/) and the icon sheet.
#
#   scripts/cap_anim/stills_game.sh <udid> [out-dir]
#
# The app must be installed on <udid>; run the render tests first (`scripts/xcq.sh test -only-testing:CramlessTests/GameRenderTests`)
# and `python3 scripts/make_alt_icons.py --sheet` for the art. The clock is frozen in the afternoon (after 22:00 celebrations are calm).
set -u
cd "$(dirname "$0")/../.." || exit 2
udid=${1:?udid}; out=${2:-build/review/game-loop/stills}
mkdir -p "$out"
raw=build/p6-raw
# ONLY="streak badges" retakes just those (the others stay as they were).
[ -n "${ONLY:-}" ] || rm -rf "$raw"
mkdir -p "$raw"
NOW=${NOW:-2026-10-26T13:00:00Z}

shot() {  # name route [KEY=VALUE ...]
  local name=$1 route=$2; shift 2
  if [ -n "${ONLY:-}" ] && [[ " $ONLY " != *" $name "* ]]; then return 0; fi
  # Its own folder: two names can share a route (streak, streak-milestones), and the later shot must not eat the earlier one.
  local one="$raw/.one"; rm -rf "$one"; mkdir -p "$one"
  WAIT=${WAIT:-6} NOW=$NOW EXTRA="$*" scripts/shots.sh "$udid" "$one" "$route" >/dev/null
  local file="$one/$(echo "$route" | tr ':/' '--').png"
  [ -f "$file" ] && mv "$file" "$raw/$name.png" || echo "missing: $name"
  rm -rf "$one"
}

shot today-quests today CRAMLESS_QUESTS=partial CRAMLESS_QUEST_PICKS=finishSession,rightInARow,fixMixUp
THEME=dark shot today-quests-dark today CRAMLESS_QUESTS=partial CRAMLESS_QUEST_PICKS=finishSession,rightInARow,fixMixUp
shot streak streak
shot streak-milestones streak CRAMLESS_SCROLL=milestones
shot progress-badges progress CRAMLESS_SCROLL=badges
shot badges badges
shot badge-earned badge:streak7
shot badge-unearned badge:streak30
# appearance-sky and appearance-icon (Settings ▸ Appearance, the pickers with their locked ones) are taken by hand into build/p6-hand/:
# CRAMLESS_SCROLL=bottom stops short on a page whose last rows sit in a lazy grid, so launch `settings:appearance`, swipe up twice
# (the `mobile` tools, from y 600, 420 pt each) and `xcrun simctl io <udid> screenshot build/p6-hand/<name>.png`.
WAIT=15 shot summary-quests session CRAMLESS_QUEST_PICKS=finishSession,ownWords,learnNew CRAMLESS_QUESTS=weekFull \
  CRAMLESS_SESSION_STATE=quest-summary CRAMLESS_SUMMARY_SCROLL=700
WAIT=15 shot summary-badge session CRAMLESS_SESSION_STATE=badge-summary CRAMLESS_SUMMARY_SCROLL=700
for sky in dusk aurora ember bloom glacier; do shot today-$sky today CRAMLESS_SKY_THEME=$sky; done
# Reduce Motion, and the largest text size.
WAIT=7 shot calm-milestone session CRAMLESS_REDUCE_MOTION=1 CRAMLESS_SCENARIO=streak:99 CRAMLESS_SESSION_STATE=milestone-summary
if [ -z "${ONLY:-}" ] || [[ " $ONLY " == *" ax-badges "* ]]; then
  xcrun simctl ui "$udid" content_size accessibility-extra-extra-extra-large; sleep 2
  shot ax-badges badges
  xcrun simctl ui "$udid" content_size large
fi

# Small JPEGs of the screens, and the art.
python3 - "$raw" "$out" <<'PY'
import sys
from pathlib import Path
from PIL import Image
raw, out = Path(sys.argv[1]), Path(sys.argv[2])
for f in sorted(list(raw.glob("*.png")) + list(Path("build/p6-hand").glob("*.png"))):
    im = Image.open(f).convert("RGB")
    im = im.resize((540, round(im.height * 540 / im.width)), Image.LANCZOS)
    im.save(out / f"{f.stem}.jpg", quality=84, optimize=True)
art = {
    "flames": "docs/shots/game/flames-light.png",
    "medals": "docs/shots/game/medals-light.png",
    "skies": "docs/shots/game/skies-light.png",
    "icons": "build/icons/sheet.png",
    "ax-quests": "docs/shots/game/quests-ax-light.png",
}
for name, path in art.items():
    p = Path(path)
    if not p.exists():
        print("missing art:", path)
        continue
    im = Image.open(p).convert("RGB")
    width = 540 if name == "ax-quests" else 1100
    if im.width > width:
        im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    im.save(out / f"{name}.jpg", quality=86, optimize=True)
print("wrote", len(list(out.glob("*.jpg"))), "stills to", out)
PY
