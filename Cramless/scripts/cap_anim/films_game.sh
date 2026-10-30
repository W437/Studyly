#!/bin/bash
# Films the game loop for the review page (build/review/game-loop/): a streak milestone taking over the summary (7, 30 and 100 days:
# the flame in its three stages), the day's quests ticking off, a week of quests lighting a new sky, a badge earned and its medal, and
# the six skies behind Today.
#
#   scripts/cap_anim/films_game.sh <udid> <out-dir> [name ...]     (no names = all)
#
# The app must be installed on <udid>. Each film is `scripts/film.sh` through `simq run media`, with CRAMLESS_CAP_CLIPS=1 and
# CRAMLESS_SOUNDS=1 (film.sh mixes the app's own sounds in at the logged times). Every state is a DEBUG hook, with no taps: see
# AppModel+GameHarness.swift and the summary's CRAMLESS_SUMMARY_* hooks. CRAMLESS_SESSION_STATE=…-summary answers eight questions and
# shows the summary; its choreography takes about 7 seconds, the celebration last.
set -u
cd "$(dirname "$0")/../.." || exit 2
udid=${1:?udid}; out=${2:?out dir}; shift 2
want=("$@")
# An afternoon: the clock is frozen there, because after 22:00 the celebrations are calm (quiet hours: no confetti) and the
# sounds are softer.
NOW=${NOW:-2026-10-26T13:00:00Z}

film() {
  local name=$1 secs=$2; shift 2
  if [ ${#want[@]} -gt 0 ]; then
    local ok=0; for w in "${want[@]}"; do [ "$w" = "$name" ] && ok=1; done
    [ $ok = 1 ] || return 0
  fi
  echo "== $name ($secs s)"
  simq run media -- scripts/film.sh "$udid" "$out" "$name" "$secs" CRAMLESS_CAP_CLIPS=1 CRAMLESS_SOUNDS=1 "CRAMLESS_NOW=$NOW" "$@"
}

# The flame in three stages: a streak one short of the milestone, then a session. Cap is proud; the flame pops in and bounces once.
film milestone-7 15 CRAMLESS_ROUTE=session CRAMLESS_SCENARIO=streak:6 CRAMLESS_SESSION_STATE=milestone-summary
film milestone-30 15 CRAMLESS_ROUTE=session CRAMLESS_SCENARIO=streak:29 CRAMLESS_SESSION_STATE=milestone-summary
film milestone-100 15 CRAMLESS_ROUTE=session CRAMLESS_SCENARIO=streak:99 CRAMLESS_SESSION_STATE=milestone-summary
# The day's quests: three, none done, 7 of 12 this week. The session finishes them one by one, and the week's meter moves.
film quests 12 CRAMLESS_ROUTE=session CRAMLESS_QUEST_PICKS=finishSession,ownWords,learnNew CRAMLESS_QUESTS=start \
  CRAMLESS_SESSION_STATE=quest-summary CRAMLESS_SUMMARY_SCROLL=700
# The last quest of a week of twelve: a new sky is lit, "Use it" puts it behind the stars, and Done goes back to Today in Dusk.
film new-sky 17 CRAMLESS_ROUTE=session CRAMLESS_QUEST_PICKS=finishSession,ownWords,learnNew CRAMLESS_QUESTS=weekFull \
  CRAMLESS_SESSION_STATE=quest-summary CRAMLESS_SUMMARY_SCROLL=700 CRAMLESS_SUMMARY_USE_SKY=1400 CRAMLESS_SUMMARY_DONE=2200
# A badge earned (the 7-day one): its card in the summary, then its sheet, with the medal swaying as it would follow a tilted phone.
film badge 19 CRAMLESS_ROUTE=session CRAMLESS_SESSION_STATE=badge-summary CRAMLESS_SUMMARY_SCROLL=700 CRAMLESS_SUMMARY_BADGE=1500
# The six skies behind Today, two and a half seconds each.
film sky-tour 18 CRAMLESS_SKY_TOUR=2500
