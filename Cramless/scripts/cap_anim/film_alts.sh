#!/bin/bash
# Makes the fallback encodings of every film in a review folder: alt/<name>-hevc.mp4 (H.265) and alt/<name>-small.mp4 (smaller
# H.264), and the same for each half-speed copy. A review page tries the standard film first and moves to these by itself
# if a phone refuses it (the first Phase 5 films were refused: see docs/BUILD.md).
# Both come from the Mac's hardware encoders (VideoToolbox): software x265 took ten minutes for one long film, and this Mac is
# shared. They are fallbacks, so a little less compression efficiency does not matter.
#
#   scripts/cap_anim/film_alts.sh <folder>
set -eu
dir=${1:?folder}
mkdir -p "$dir/alt"
for f in "$dir"/*.mp4; do
  b=$(basename "$f" .mp4)
  case $b in *-hevc|*-small) continue ;; esac
  if [ ! -f "$dir/alt/$b-hevc.mp4" ] || [ "$f" -nt "$dir/alt/$b-hevc.mp4" ]; then
    simq run media -- ffmpeg -hide_banner -loglevel error -y -i "$f" -c:v hevc_videotoolbox -q:v 60 -pix_fmt yuv420p \
      -tag:v hvc1 -c:a copy -movflags +faststart "$dir/alt/$b-hevc.mp4"
  fi
  if [ ! -f "$dir/alt/$b-small.mp4" ] || [ "$f" -nt "$dir/alt/$b-small.mp4" ]; then
    simq run media -- ffmpeg -hide_banner -loglevel error -y -i "$f" -vf "scale=828:1792:flags=lanczos,setsar=1,fps=60" \
      -c:v h264_videotoolbox -q:v 60 -profile:v high -level 4.2 -pix_fmt yuv420p -c:a copy -movflags +faststart "$dir/alt/$b-small.mp4"
  fi
  echo "alts for $b"
done
