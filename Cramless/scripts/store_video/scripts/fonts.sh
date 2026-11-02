#!/usr/bin/env bash
# Copies the fonts the preview uses into public/fonts: Apple's system fonts (not redistributed, so not in git) and the app's own Bricolage faces.
set -e
cd "$(dirname "$0")/.."
mkdir -p public/fonts
cp /System/Library/Fonts/SFNS.ttf /System/Library/Fonts/SFNSRounded.ttf public/fonts/
cp ../../Cramless/Resources/Fonts/BricolageGrotesque-*.ttf public/fonts/
