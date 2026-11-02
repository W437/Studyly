#!/usr/bin/env bash
# Copies a gallery clip into an ad's own folder, trimmed to what the ad uses, frame-exact,
# at native resolution. Ads never point at the gallery: it gets re-captured and would
# change under them.
#   tools/copy_clip.sh ../gallery/media/clips/markup-signature.mp4 public/v6/clips/sign.mp4 0.3 4.8
# Prints the offset: manifest moment times minus it = times in the copy.
set -euo pipefail
if (( $# < 2 )) || [[ $1 == -h || $1 == --help ]]; then sed -n 2,6p "$0"; exit 1; fi
src=$1; dst=$2; from=${3:-0}; to=${4:-}
mkdir -p "$(dirname "$dst")"
args=(-v error -y -i "$src" -ss "$from")
[[ -n $to ]] && args+=(-to "$to")
ffmpeg "${args[@]}" -an -c:v libx264 -preset medium -crf 16 -pix_fmt yuv420p -r 30 -movflags +faststart "$dst"
echo "$dst: from $from s of $(basename "$src") (subtract $from from the manifest's moment times), $(ffprobe -v error -show_entries format=duration -of csv=p=0 "$dst") s"
