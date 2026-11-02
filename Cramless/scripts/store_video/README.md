# Capling App Store preview (Remotion)

A 25 s portrait motion piece (886 x 1920, 30 fps) drawn in code from the app's own pieces: no screenshots, no recording of the app. Cap is not
redrawn: he plays his own animation clips from the app (`Cramless/Resources/CapClips`). It follows
the listing art's look (the sky ground, the toy-sign lettering, Cap, solid four-point stars) and tells the app in five beats:
Snap pages into Questions, Answer in your own Words, Know your Readiness, Light up your Memory, "A little every day. Ready on exam day."
Each cut is a shape that carries over: the question card grows into the answer card, the check marks fly into the readiness ring, the white
plate becomes the night sky, the stars rise into the dawn, and the star lands where the wordmark's i has its dot.

It is built on the `app-video-ads` skill's Remotion template (`~/.claude/skills/app-video-ads`), reduced to this one composition.

## Render

```sh
npm install                      # once
scripts/fonts.sh                 # copies Apple's SF fonts (not in git) and the app's Bricolage faces into public/fonts
scripts/capclips.sh              # decodes Cap's clips (HEVC with alpha) to PNG frames in public/capclips (not in git, ~110 MB; needs Xcode's swift)
npm run typecheck
node tools/frames.mjs --frames 30,120,300 --scale 0.5 --cols 3 --out out/s/sheet.png   # look at chosen frames (one bundle, fast)
npm run preview                  # half-size motion preview -> out/preview.mp4 (about 10 s)
npm run render                   # full size, silent -> renders/capling-preview-silent.mp4 (about 50 s)

python3.13 -m venv .venv && .venv/bin/pip install numpy       # once, for the sound (not Python 3.14: see tools/score.py)
.venv/bin/python tools/score.py --out renders/preview-audio.wav
ffmpeg -y -i renders/capling-preview-silent.mp4 -i renders/preview-audio.wav -map 0:v -map 1:a -c:v copy -c:a aac -b:a 256k -ar 48000 -t 25 \
  -movflags +faststart renders/capling-app-preview.mp4
tools/loudness.sh renders/capling-app-preview.mp4            # -14 to -16 LUFS, true peak <= -1 dBTP
```

Renders go through `simq run media -- npm run render` on this Mac. `out/` and `renders/` are not tracked.

## Files

- `src/capling/theme.ts`: Capling's colours (from `Shared/BrandPalette.swift`), the three skies (day, night, dawn) and the timeline `T` (120 BPM: a beat
  is 15 frames, a bar 60).
- `kit.tsx` (fonts, ground, toy-sign lettering, sparkles, Cap), `headline.tsx`, `elements.tsx` (page, scanner brackets, question cards),
  `s1.tsx` to `s5.tsx` (the beats), `disc.tsx` (the plate that becomes the sky), `Preview.tsx` (the composition and the sky's colour over time).
- `public/cap/*.png` (the app's Cap poses), `public/capclips/<pose>/0001.png ...` (his clips, from `scripts/capclips.sh`), `public/art/appicon.png`,
  `public/fonts` (Bricolage is OFL; SF is copied by `scripts/fonts.sh`).
- Cap: `Cap` in `kit.tsx` takes `clip={{start, until?}}`: from edit frame `start` the clip's pictures replace the drawing (the same box, on the
  clip's 720 px canvas), and the code's own breathing waits until it is over. Where each plays: scan 0 (stops on picture 65), think 128, nice 214,
  point 346, stargaze 440, celebrate 544 (stops on 114). The nice clip pumps his fist every 12 pictures = every beat, so start 214 puts the pumps
  on f225, 240, 255, 270; the celebrate clip lands at f618 while the wordmark is built and leaps again at f660, the last hit.
- `tools/score.py`: the sound, synthesized from the app's marimba, kalimba and glass palettes (`CLSynth.swift`) plus a pad, bass and drums, with the
  sound effects on exact frames. `tools/frames.mjs`, `strip.sh`, `storyboard.py`, `loudness.sh`, `analyse_audio.py`: checking tools.
- `sources/music/music-plan.json`: a composition plan for an AI track (ElevenLabs Music on fal, about $0.50 for two candidates). Not used: the key
  needs `lockbox unlock`. The synthesized score is what ships.

## Notes

- Apple's reference data (read 2026-11-01): the iPhone App Preview takes 886 x 1920 or 1920 x 886, 23 to 30 fps, 15 to 30 s, **audio required**, 500 MB.
  The header (3840 x 1646) and search-results (3:2) video slots take 5 to 30 s at 30 or 60 fps with no audio requirement.
- App Review guideline 2.3.4: previews may only use screen captures of the app. This piece is drawn, so it may be refused as the App Preview.
- The numbers on screen (42% to 91%, 63 stars, 17 dim) are the demo world's. The readiness ring climbs with the path's line being drawn (`ringValue` reads the
  height of the line's head), so the ring, the line's end (just above its 90% goal line) and its label "Exam day 91%" are one number (`END_VALUE` in `s3.tsx`);
  the chart is labelled a projection.
- Remotion renders JPEG frames by default and tags the file full range with a BT.601 matrix: `--image-format=png --color-space=bt709` fixes both
  (limited range, BT.709). `--scale` must give whole pixels: 0.5 does, 0.4 does not.
- Cap's clips are 24 fps and the edit is 30: each picture is held for its time, every fifth one twice (an extreme at a multiple of 4 is the held one),
  never blended (a blend ghosts the paws and the baked-in confetti). Every clip ends by dissolving onto its pose's drawing: where the clip's last
  pose and the drawing differ, that is a double image for 3 to 5 pictures (scan 66 to 70, celebrate 115 to 119, nice 92 to 94), so `until` stops on
  the last clean one. ffmpeg cannot read the clips' alpha: `scripts/capclips.sh` goes through AVFoundation (`../cap_anim/hevc_frames.swift`).
- The sound was checked by analysis only (tempo, bars, loudness, onsets). Listen before it goes anywhere.
