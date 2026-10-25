#!/bin/bash
# Turns Cap's raw 1024 px renders (docs/rethink/brand/raw/…) into app art with one shared frame, so poses line up
# when they cross-fade and Cap's squash and hop always land on the same feet line.
#
#   scripts/cap_post.sh ship <pose> <raw.png>        writes Cramless/Resources/Assets.xcassets/Cap-<pose>.imageset
#   scripts/cap_post.sh sheet <out.png> <raw.png>…   a contact sheet of the framed art on Night, light and white
#   scripts/cap_post.sh frame <raw.png> <out.png>    just the framing (1024 px, transparent)
#
# Framing: the art is measured by its alpha (anything under 8% counts as empty), moved so its lowest point sits
# FEET px above the bottom of the 1024 px canvas and its weight is centred sideways (the middle of what is drawn, not
# of the bounding box, so a telescope or a speech bubble doesn't push Cap off centre), and scaled down only if it
# wouldn't fit with MARGIN px around it. Poses keep the scale they were drawn at, so Cap's head stays the same size.
# Needs ImageMagick (brew install imagemagick).
set -eu
cd "$(dirname "$0")/.."

CANVAS=1024
FEET=36        # the bottom margin of the first four poses, in 1024 px units
MARGIN=36      # the least room on the other three sides
APP=600        # the app's art, in px
CATALOG=Cramless/Resources/Assets.xcassets

frame() {  # frame <in> <out>
  local in=$1 out=$2 box w h x y
  box=$(magick "$in" -channel A -separate +channel -threshold 8% -format '%@' info:)   # WxH+X+Y
  w=${box%%x*}; h=${box#*x}; h=${h%%+*}; x=${box#*+}; x=${x%%+*}; y=${box##*+}
  # The weight's horizontal centre, from a 64 px copy of the alpha channel.
  local cx
  cx=$(magick "$in" -channel A -separate +channel -scale 64x64! -depth 8 txt:- |
       awk -F'[,:() ]+' 'NR>1 { v=$5+0; if (v > 20) { sx += $1 * v; sw += v } } END { printf "%d", (sw ? sx / sw : 31.5) * 16 + 8 }')
  # Scale down only if it won't fit; never up.
  local room_w=$((CANVAS - 2 * MARGIN)) room_h=$((CANVAS - FEET - MARGIN)) pct=100
  if [ "$w" -gt "$room_w" ] || [ "$h" -gt "$room_h" ]; then
    pct=$(awk -v w="$w" -v h="$h" -v rw="$room_w" -v rh="$room_h" 'BEGIN { a = rw / w; b = rh / h; printf "%.4f", (a < b ? a : b) * 100 }')
    w=$(awk -v w="$w" -v p="$pct" 'BEGIN { printf "%d", w * p / 100 + 0.5 }')
    h=$(awk -v h="$h" -v p="$pct" 'BEGIN { printf "%d", h * p / 100 + 0.5 }')
    cx=$(awk -v cx="$cx" -v x="$x" -v p="$pct" 'BEGIN { printf "%d", (cx - x) * p / 100 + x * 0 }')
    x=0
  fi
  # Where the cropped art goes: centred on its weight, clamped inside the margins; feet on the feet line.
  local left=$(( CANVAS / 2 - (cx - x) * 100 / 100 ))
  [ "$left" -lt "$MARGIN" ] && left=$MARGIN
  [ $((left + w)) -gt $((CANVAS - MARGIN)) ] && left=$((CANVAS - MARGIN - w))
  local top=$((CANVAS - FEET - h))
  magick -size ${CANVAS}x${CANVAS} xc:none \
    \( "$in" -crop "${box}" +repage -resize "${pct}%" \) -geometry "+${left}+${top}" -composite -depth 8 "$out"
}

case ${1:-} in
  frame)
    frame "$2" "$3"
    ;;
  ship)
    pose=$2; raw=$3
    dir=$CATALOG/Cap-$pose.imageset
    mkdir -p "$dir"
    tmp=$(mktemp -t cap_post).png
    frame "$raw" "$tmp"
    magick "$tmp" -filter Lanczos -resize ${APP}x${APP} -strip "$dir/cap-$pose.png"
    rm -f "$tmp"
    cat > "$dir/Contents.json" <<JSON
{
  "images" : [ { "filename" : "cap-$pose.png", "idiom" : "universal" } ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "preserves-vector-representation" : false }
}
JSON
    echo "$dir/cap-$pose.png"
    ;;
  sheet)
    out=$2; shift 2
    work=$(mktemp -d -t cap_sheet)
    i=0
    for raw in "$@"; do
      i=$((i + 1)); name=$(basename "$raw" .png)
      frame "$raw" "$work/$name.png"
    done
    cd "$work"
    # Night, light and white, side by side, so edge halos show on every surface the app draws Cap on.
    for bg in '#14213D' '#F1F5FA' '#FFFFFF'; do
      for f in *.png; do
        case $f in surface-*) continue ;; esac
        magick -size ${CANVAS}x${CANVAS} "xc:$bg" "$f" -composite -resize 300x300 "surface-${bg#\#}-$f"
      done
    done
    cd - > /dev/null
    for bg in 14213D F1F5FA FFFFFF; do
      magick montage -label '%t' "$work"/surface-$bg-*.png -tile 5x -geometry +3+3 -background "#$bg" \
        -fill gray50 -pointsize 14 "$work/row-$bg.png"
    done
    magick "$work"/row-14213D.png "$work"/row-F1F5FA.png "$work"/row-FFFFFF.png -append "$out"
    rm -rf "$work"
    echo "$out"
    ;;
  *)
    sed -n 2,14p "$0"; exit 2 ;;
esac
