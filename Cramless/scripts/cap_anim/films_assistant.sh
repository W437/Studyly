#!/bin/bash
# Films and stills of Ask Cap's assistant for the review page (build/review/ask-cap-assistant/): flashcards written and checked,
# added and taken back, questions, a note being written, an exam on a calendar tile, web research with the sites' tiles, a look
# up then a deck, "Let Cap do it", the free plan's limits and the settings page.
#
#   scripts/cap_anim/films_assistant.sh <udid> <out-dir> [name ...]     (no names = all)
#
# The app must be installed on <udid>. Every state is a DEBUG hook with no taps: CRAMLESS_ASSISTANT=<script> asks Cap in a Bio 101
# chat and the mock relay plays its script with the live delays (Features/Ask/AskDemo.swift). Films are `scripts/film.sh` through
# `simq run media`, with the app's own sounds mixed in; stills are simctl screenshots after a wait or a freeze.
set -u
cd "$(dirname "$0")/../.." || exit 2
udid=${1:?udid}; out=${2:?out dir}; shift 2
want=("$@")
NOW=${NOW:-2026-10-26T13:00:00Z}
mkdir -p "$out" "$out/stills"
bundle=com.loopware.Capling

wanted() {
  [ ${#want[@]} -eq 0 ] && return 0
  local w; for w in "${want[@]}"; do [ "$w" = "$1" ] && return 0; done
  return 1
}

film() {
  local name=$1 secs=$2; shift 2
  wanted "$name" || return 0
  echo "== film $name ($secs s)"
  FILM_NO_HALF=${FILM_NO_HALF:-0} simq run media -- scripts/film.sh "$udid" "$out" "$name" "$secs" \
    CRAMLESS_CAP_CLIPS=1 CRAMLESS_SOUNDS=1 "CRAMLESS_NOW=$NOW" CRAMLESS_ROUTE=ask "$@"
}

# shot <name> <wait seconds> KEY=VALUE ...   (stills/<name>.png)   WAIT_SCALE=1.5 waits half as long again, on a busy Mac
shot() {
  local name=$1 wait_s=$2; shift 2
  wanted "$name" || wanted stills || return 0
  local envs=(SIMCTL_CHILD_CRAMLESS_UITEST=1 "SIMCTL_CHILD_CRAMLESS_NOW=$NOW" SIMCTL_CHILD_CRAMLESS_ROUTE=ask)
  local kv; for kv in "$@"; do envs+=("SIMCTL_CHILD_$kv"); done
  xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1
  env "${envs[@]}" xcrun simctl launch "$udid" "$bundle" >/dev/null || { echo "launch failed: $name"; return; }
  sleep "$(awk "BEGIN { print $wait_s * ${WAIT_SCALE:-1} }")"
  xcrun simctl io "$udid" screenshot "$out/stills/$name.png" >/dev/null 2>&1 && echo "still $name"
}

# ---- Films
# Flashcards: the model writes six cards (each appears as it is written, with a note), each is checked against the notes, the
# card turns to "your call", and Cap's short note arrives.
film cards 12 CRAMLESS_ASSISTANT=cards
# The same, then the student presses Add and, later, Undo.
film cards-add 24 CRAMLESS_ASSISTANT=cards CRAMLESS_ASSISTANT_APPROVE=11000 CRAMLESS_ASSISTANT_UNDO=18000
# "Let Cap do it": the same request with it switched on for cards.
film cards-auto 12 CRAMLESS_ASSISTANT=cards CRAMLESS_ASSISTANT_AUTO=cards
film quiz 12 CRAMLESS_ASSISTANT=quiz
film note 14 CRAMLESS_ASSISTANT=note
film exam 9 CRAMLESS_ASSISTANT=exam
# Web research: the search types itself, the sites' tiles appear, a ring reads across them, the summary writes itself.
film research 16 CRAMLESS_ASSISTANT=research
film research-save 24 CRAMLESS_ASSISTANT=research CRAMLESS_ASSISTANT_APPROVE=12000
# A lookup of the notes, then a deck made from what it found.
film multi 14 CRAMLESS_ASSISTANT=multi
film practice 9 CRAMLESS_ASSISTANT=practice
# What the free plan sees: the day's drafts used up, and web research that needs Capling Pro.
film limit 7 CRAMLESS_ASSISTANT=limit
film research-pro 10 CRAMLESS_ASSISTANT=research CRAMLESS_RESEARCH=pro

# ---- Stills
shot empty 4
shot cards-writing 6.2 CRAMLESS_ASSISTANT=cards CRAMLESS_ASSISTANT_FREEZE=6
shot cards-checking 9 CRAMLESS_ASSISTANT=cards CRAMLESS_ASSISTANT_FREEZE=13
shot cards-ready 14 CRAMLESS_ASSISTANT=cards
shot cards-added 16 CRAMLESS_ASSISTANT=cards CRAMLESS_ASSISTANT_APPROVE=11000
shot cards-added-auto 14 CRAMLESS_ASSISTANT=cards CRAMLESS_ASSISTANT_AUTO=cards
shot quiz-ready 14 CRAMLESS_ASSISTANT=quiz
shot note-writing 8 CRAMLESS_ASSISTANT=note CRAMLESS_ASSISTANT_FREEZE=12
shot note-ready 15 CRAMLESS_ASSISTANT=note
shot exam-ready 11 CRAMLESS_ASSISTANT=exam
shot research-searching 7 CRAMLESS_ASSISTANT=research CRAMLESS_ASSISTANT_FREEZE=6
shot research-reading 8 CRAMLESS_ASSISTANT=research CRAMLESS_ASSISTANT_FREEZE=7
shot research-writing 9 CRAMLESS_ASSISTANT=research CRAMLESS_ASSISTANT_FREEZE=10
shot research-ready 22 CRAMLESS_ASSISTANT=research
shot research-pro 14 CRAMLESS_ASSISTANT=research CRAMLESS_RESEARCH=pro
shot multi-ready 18 CRAMLESS_ASSISTANT=multi
shot limit 11 CRAMLESS_ASSISTANT=limit
shot practice 10 CRAMLESS_ASSISTANT=practice
shot cards-dark 14 CRAMLESS_ASSISTANT=cards CRAMLESS_THEME=dark
# Reduce Motion: nothing is drawn on, the last frame of each step stands alone (not on the review page; a check).
shot cards-calm 12 CRAMLESS_ASSISTANT=cards CRAMLESS_REDUCE_MOTION=1
shot research-calm 14 CRAMLESS_ASSISTANT=research CRAMLESS_REDUCE_MOTION=1
shot research-dark 22 CRAMLESS_ASSISTANT=research CRAMLESS_THEME=dark
shot settings 4 CRAMLESS_ROUTE=settings:assistant
shot settings-teen 4 CRAMLESS_ROUTE=settings:assistant CRAMLESS_AGE=teen
shot settings-added 5 CRAMLESS_ROUTE=settings:assistant CRAMLESS_ASSISTANT_SEED=1 CRAMLESS_SCROLL=added
shot ai-privacy 4 CRAMLESS_ROUTE=settings:aiPrivacy CRAMLESS_SCROLL=bottom
xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1
exit 0
