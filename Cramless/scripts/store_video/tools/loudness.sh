#!/usr/bin/env bash
# Measures a render's loudness and true peak against the ad targets
# (-16 to -14 LUFS integrated, true peak <= -1 dBTP), optionally fixing it.
#   tools/loudness.sh renders/App-ad-6-speedrun.mp4
#   tools/loudness.sh renders/App-ad-6-speedrun.mp4 --fix    # two-pass loudnorm to -14 LUFS / -1.5 dBTP → <name>.loud.mp4
# Better than --fix: change the music/SFX volumes in the ad and re-render (keeps the mix's balance).
set -euo pipefail
if (( $# < 1 )) || [[ $1 == -h || $1 == --help ]]; then sed -n 2,6p "$0"; exit 1; fi
in=$1; fix=${2:-}
measure() {
  ffmpeg -nostats -i "$1" -af ebur128=peak=true -f null - 2>&1 | awk '/Summary:/{s=1} s' |
    awk '/I:/{i=$2} /LRA:/{l=$2} /Peak:/{p=$2} END{print i, l, p}'
}
read -r I LRA TP <<<"$(measure "$in")"
verdict=$(python3 -c "
i, tp = float('$I'), float('$TP')
bad = []
if not (-16.5 <= i <= -13.5): bad.append('loudness off target')
if tp > -1.0: bad.append('true peak above -1 dBTP')
print('FAIL: ' + ', '.join(bad) if bad else 'PASS')")
echo "$in: $I LUFS integrated, LRA $LRA LU, true peak $TP dBTP → $verdict"
if [[ $fix == --fix && $verdict != PASS ]]; then
  stats=$(ffmpeg -nostats -i "$in" -af loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json -f null - 2>&1 |
    python3 -c "import re,sys; print(re.findall(r'\{[^{}]*\}', sys.stdin.read())[-1])")
  get() { python3 -c "import json,sys; print(json.loads(sys.stdin.read())['$1'])" <<<"$stats"; }
  if [[ -n $(ffprobe -v error -select_streams v -show_entries stream=index -of csv=p=0 "$in") ]]; then
    out="${in%.*}.loud.mp4"; vcodec=(-c:v copy)
  else
    out="${in%.*}.loud.m4a"; vcodec=(-vn)
  fi
  ffmpeg -v error -y -i "$in" "${vcodec[@]}" -af "loudnorm=I=-14:TP=-1.5:LRA=11:measured_I=$(get input_i):measured_TP=$(get input_tp):measured_LRA=$(get input_lra):measured_thresh=$(get input_thresh):offset=$(get target_offset):linear=true" \
    -ar 48000 -c:a aac -b:a 256k "$out"
  read -r I LRA TP <<<"$(measure "$out")"
  echo "$out: $I LUFS integrated, LRA $LRA LU, true peak $TP dBTP"
fi
