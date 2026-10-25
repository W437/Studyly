#!/bin/bash
# Screenshots Today's hero in the demo world: scripts/hero_shot.sh <udid> <name> [KEY=VALUE ...]  ->  build/hero-shots/<name>.png
# and <name>-hero.png (the top half). Needs the app installed on <udid>.
set -u
cd "$(dirname "$0")/.." || exit 2
udid=${1:?udid}; name=${2:?name}; shift 2
mkdir -p build/hero-shots
envs=(SIMCTL_CHILD_CRAMLESS_UITEST=1)
for kv in "$@"; do envs+=("SIMCTL_CHILD_$kv"); done
xcrun simctl terminate "$udid" com.loopware.Capling >/dev/null 2>&1
env "${envs[@]}" xcrun simctl launch "$udid" com.loopware.Capling >/dev/null
sleep "${HERO_WAIT:-5}"
xcrun simctl io "$udid" screenshot "build/hero-shots/$name.png" >/dev/null 2>&1
python3 - "build/hero-shots/$name.png" "build/hero-shots/$name-hero.png" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
w, h = im.size
im.crop((0, 0, w, int(h * 0.52))).save(sys.argv[2])
PY
echo "build/hero-shots/$name-hero.png"
