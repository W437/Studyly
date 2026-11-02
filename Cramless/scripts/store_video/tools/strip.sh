#!/usr/bin/env bash
# A frame strip of a rendered preview or a constant-fps clip, every frame labelled with its
# time and frame number, to look at by eye (every transition, every landing).
#   tools/strip.sh out/v6/preview.mp4 out/v6/strip.jpg                      # the whole thing, 6 fps
#   tools/strip.sh out/v6/preview.mp4 out/v6/strip-3.jpg --from 3.5 --to 5.5 --fps 15   # one transition, every other frame
# Options: --fps N (6) --width PX (160) --cols N (12) --from S --to S --video-fps N (30, for frame labels)
# NOT for raw Simulator takes: their timestamps are broken (use the gallery kit's `strip --raw`).
set -euo pipefail
if (( $# < 2 )) || [[ $1 == -h || $1 == --help ]]; then sed -n 2,7p "$0"; exit 1; fi
in=$1; out=$2; shift 2
fps=6; width=160; cols=12; from=0; to=""; vfps=30
while (( $# )); do
  case $1 in
    --fps) fps=$2; shift 2 ;;
    --width) width=$2; shift 2 ;;
    --cols) cols=$2; shift 2 ;;
    --from) from=$2; shift 2 ;;
    --to) to=$2; shift 2 ;;
    --video-fps) vfps=$2; shift 2 ;;
    *) echo "unknown option $1" >&2; exit 1 ;;
  esac
done
dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$in")
[[ -z $to ]] && to=$dur
n=$(python3 -c "import math; print(max(1, math.ceil(($to - $from) * $fps - 1e-6)))")
rows=$(( (n + cols - 1) / cols ))
fs=$(( width / 9 > 11 ? width / 9 : 11 ))
label="%{pts\\:flt\\:${from}}s f%{eif\\:(t+${from})*${vfps}\\:d}"
ffmpeg -v error -y -ss "$from" -to "$to" -i "$in" \
  -vf "fps=${fps},scale=${width}:-2,drawtext=text='${label}':x=3:y=3:fontsize=${fs}:fontcolor=red:box=1:boxcolor=white@0.85:boxborderw=2,tile=${cols}x${rows}:padding=2:color=black" \
  -frames:v 1 -q:v 3 "$out"
echo "$out: $n frames, ${cols}x${rows}, ${from}–${to} s"
