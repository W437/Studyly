#!/bin/bash
# A library of the app's screens (3x, from the demo world, no taps) to cut pieces from for the App Store art.
#   scripts/store_art/capture_library.sh <udid> [out-dir]      ->  <out>/<name>.png      (default build/listing/lib)
# Each line below is  name | route | wait seconds | KEY=VALUE ...   The app must be installed on <udid>. Look at every frame before use.
set -u
cd "$(dirname "$0")/../.." || exit 2
udid=${1:?udid}; out=${2:-build/listing/lib}
mkdir -p "$out/.tmp"
xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
while IFS='|' read -r name route wait env; do
  name=$(echo "$name" | xargs); [ -z "$name" ] && continue
  route=$(echo "$route" | xargs); env=$(echo "$env" | xargs)
  EXTRA="$env" WAIT=${wait// /} scripts/shots.sh "$udid" "$out/.tmp" "$route" >/dev/null
  f="$out/.tmp/$(echo "$route" | tr ':/' '--').png"
  [ -f "$f" ] && mv "$f" "$out/$name.png" && echo "$out/$name.png"
done <<'LIST'
today | today | 7 |
today-eve | today | 7 | CRAMLESS_TODAY=examEve
today-done | today | 7 | CRAMLESS_TODAY=done
library | library | 6 |
course | course | 6 |
progress | progress | 6 |
exam | exam | 6 |
exam-past | exam | 6 | CRAMLESS_SCENARIO=graded
ownwords | session | 6 | CRAMLESS_SESSION_STATE=ownwords
graded | session | 7 | CRAMLESS_SESSION_STATE=graded
mcq | session | 6 | CRAMLESS_SESSION_STATE=mcq
mcq-answered | session | 6 | CRAMLESS_SESSION_STATE=mcq-answered
cloze | session | 6 | CRAMLESS_SESSION_STATE=cloze
cloze-answered | session | 6 | CRAMLESS_SESSION_STATE=cloze-answered
flashcard | session | 6 | CRAMLESS_SESSION_STATE=flashcard
flipped | session | 6 | CRAMLESS_SESSION_STATE=flipped
diagram | session | 6 | CRAMLESS_SESSION_STATE=diagram-filled
summary | session | 8 | CRAMLESS_SESSION_STATE=summary
saved | session | 8 | CRAMLESS_SESSION_STATE=exameve-summary
milestone | session | 9 | CRAMLESS_SESSION_STATE=milestone-summary
badge-summary | session | 9 | CRAMLESS_SESSION_STATE=badge-summary
sky | sky | 8 | CRAMLESS_SKY=still
sky-focus | sky | 8 | CRAMLESS_SKY=still,focus:1
sky-list | sky | 8 | CRAMLESS_SKY=still,list
sky-fill | sky | 8 | CRAMLESS_SKY=still,fill:40
ask | ask | 6 |
ask-cards | ask | 16 | CRAMLESS_ASSISTANT=cards
ask-quiz | ask | 16 | CRAMLESS_ASSISTANT=quiz
ask-note | ask | 16 | CRAMLESS_ASSISTANT=note
ask-exam | ask | 16 | CRAMLESS_ASSISTANT=exam
ask-answer | ask | 16 | CRAMLESS_ASSISTANT=answer
ask-research | ask | 16 | CRAMLESS_ASSISTANT=research CRAMLESS_RESEARCH=pro
questions | captureFlow | 12 | CRAMLESS_CAPTURE_PHASE=review
capture-writing | captureFlow | 8 | CRAMLESS_CAPTURE_PHASE=writing
capture-checking | captureFlow | 8 | CRAMLESS_CAPTURE_PHASE=checking
capture-done | captureFlow | 8 | CRAMLESS_CAPTURE_PHASE=done
scanner | scanner | 6 |
paste | paste | 6 |
import | importDeck | 6 |
record | record | 6 | CRAMLESS_LECTURE_PREFILL=6
lecture-notes | lectureNotes | 6 |
settings | settings | 6 |
squad | squad | 6 |
streak | streak | 7 |
badges | badges | 6 | CRAMLESS_UNLOCK=all
badge | badge:streak30 | 7 |
paywall | paywall | 7 |
welcome | onboarding:0 | 6 |
welcome-lit | onboarding:0 | 8 | CRAMLESS_WELCOME=lit3
onb1 | introScene:1 | 6 |
onb2 | introScene:2 | 6 |
onb3 | introScene:3 | 6 |
onb4 | introScene:4 | 6 |
onb5 | introScene:5 | 6 |
onb6 | introScene:6 | 6 |
first-set | onboarding:1 | 6 |
first-session | onboarding:2 | 7 |
onb-date | onboarding:3 | 6 |
plan | onboarding:4 | 7 |
theme-night | today | 7 | CRAMLESS_UNLOCK=all CRAMLESS_SKY_THEME=night
theme-dusk | today | 7 | CRAMLESS_UNLOCK=all CRAMLESS_SKY_THEME=dusk
theme-aurora | today | 7 | CRAMLESS_UNLOCK=all CRAMLESS_SKY_THEME=aurora
theme-ember | today | 7 | CRAMLESS_UNLOCK=all CRAMLESS_SKY_THEME=ember
theme-bloom | today | 7 | CRAMLESS_UNLOCK=all CRAMLESS_SKY_THEME=bloom
theme-glacier | today | 7 | CRAMLESS_UNLOCK=all CRAMLESS_SKY_THEME=glacier
LIST
rmdir "$out/.tmp" 2>/dev/null
xcrun simctl status_bar "$udid" clear
