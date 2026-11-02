#!/usr/bin/env bash
# Decodes Cap's animation clips (the app's HEVC-with-alpha videos) into PNG frames with alpha under public/capclips/<pose>/0001.png ...
# ffmpeg cannot read Apple's alpha layer, so this goes through AVFoundation (scripts/cap_anim/hevc_frames.swift). Not in git (about 110 MB).
#   scripts/capclips.sh                 # the six poses the preview uses
#   scripts/capclips.sh wave proud      # others
set -e
cd "$(dirname "$0")/.."
poses=("$@")
[ ${#poses[@]} -eq 0 ] && poses=(scan think nice point stargaze celebrate)
for id in "${poses[@]}"; do
  rm -rf "public/capclips/$id"
  swift ../cap_anim/hevc_frames.swift "../../Cramless/Resources/CapClips/cap-$id.mov" "public/capclips/$id" all | grep -v '^  frame'
done
