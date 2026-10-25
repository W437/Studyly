#!/bin/bash
# Renders every Cramless sound, on every palette, with the app's own synthesizer (Cramless/DesignSystem/Feel/
# CLSynth.swift, compiled for this Mac): one WAV per cue, plus a 30-second session, into docs/shots/audition/.
# The owner picks a palette by ear; scripts/film.sh lays these same files over silent simulator films.
#
#   scripts/sound_audition/run.sh        (a few seconds)
set -eu
cd "$(dirname "$0")/../.."
out=build/sound_audition
mkdir -p "$out"
swiftc -O -target arm64-apple-macos26.0 Cramless/DesignSystem/Feel/CLSynth.swift scripts/sound_audition/main.swift \
  -o "$out/sound_audition"
"$out/sound_audition" docs/shots/audition
