#!/bin/bash
# Films a hooked launch on a simulator, with the app's own sounds laid over it (simulator recordings are silent).
#
#   scripts/film.sh <udid> <out-dir> <name> <seconds> [KEY=VALUE ...]
#   scripts/film.sh $SIM build/films feel-lab 80 CRAMLESS_FEELLAB=sounds CRAMLESS_SOUND_PALETTE=kalimba
#
# Launches the installed app with CRAMLESS_UITEST=1 plus the given variables (see App/TestHarness.swift), records the
# screen for <seconds>, pulls the cue log the app wrote (Documents/feel-log.jsonl, see DesignSystem/Feel/CLFeel.swift),
# aligns it frame by frame through the timecode strip the app draws on film launches (then crops it off), renders the
# soundtrack with the app's synthesizer at the logged times (scripts/sound_audition, palette from
# CRAMLESS_SOUND_PALETTE, default marimba) and writes <name>.mp4, <name>-half.mp4 (half speed, for motion), and
# <name>.jpg (a poster frame), and keeps the cue times as <name>.cues.json. FILM_PALETTES="marimba kalimba glass"
# scores the same recording once per palette (<name>-<palette>.mp4) to compare them on identical footage.
# FILM_NO_HALF=1 skips the half-speed copy (the tour films don't use it, and it doubles the encoding time). FILM_GIF=1 adds <name>.gif of the first 12 seconds; FILM_KEEP_RAW=1 keeps the uncut recording. Haptics can't be filmed: feel them in the Feel lab on a phone.
# FILM_DRIVER="<command>" runs that command while it records, instead of waiting <seconds> (then <seconds> only bounds the timecode
# search; the film is as long as the command plus FILM_TAIL, default 1.5 s). The command is how a person would use the app: see
# scripts/journeys. It gets JOURNEY_UDID, and JOURNEY_MARKS, a file it appends {"t": wall seconds, "cue": caption} lines to; film.sh
# turns those into <name>.marks.json (film seconds, from the same timecode as the cues), the chapters and captions of a tour page.
# Films are H.264 High at a constant 60 fps, level 5.1. The recorder's own stream is variable-rate at about 100-120 fps,
# and encoded as it comes it is labelled level 6.1; the Phase 5 films made that way would not play on the owner's iPhone.
# The app must already be installed (see scripts/shots.sh).
set -eu
udid=${1:?udid}; out=${2:?out dir}; name=${3:?name}; secs=${4:?seconds}; shift 4
cd "$(dirname "$0")/.."
# FILM_BUNDLE films another install of the app (a copy with its own bundle id on a simulator other sessions share).
bundle=${FILM_BUNDLE:-com.loopware.Capling}
palette=marimba
envs=(SIMCTL_CHILD_CRAMLESS_UITEST=1 SIMCTL_CHILD_CRAMLESS_FILM_SYNC=1)
for kv in "$@"; do
  envs+=("SIMCTL_CHILD_$kv")
  case $kv in CRAMLESS_SOUND_PALETTE=*) palette=${kv#*=} ;; esac
done
synth=build/sound_audition/sound_audition
[ -x "$synth" ] || scripts/sound_audition/run.sh >/dev/null
mkdir -p "$out"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1 || true
xcrun simctl io "$udid" recordVideo --codec h264 --force "$tmp/raw.mov" 2>"$tmp/rec.log" &
rec=$!
# The film's first frame is when the recorder says it started; cue times are measured from then.
for _ in $(seq 1 100); do grep -q "Recording started" "$tmp/rec.log" 2>/dev/null && break; sleep 0.05; done
started=$(python3 -c 'import time; print(time.time())')
env "${envs[@]}" xcrun simctl launch "$udid" "$bundle" >/dev/null
driver_status=0
if [ -n "${FILM_DRIVER:-}" ]; then
  JOURNEY_UDID=$udid JOURNEY_MARKS="$tmp/marks.jsonl" bash -c "$FILM_DRIVER" || driver_status=$?
  sleep "${FILM_TAIL:-1.5}"
  # The film is as long as the driver took: the poster frame and the timecode window below follow it.
  secs=$(python3 -c "import time; print(round(time.time() - $started, 1))")
else
  sleep "$secs"
fi
kill -INT "$rec"; wait "$rec" 2>/dev/null || true
xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1 || true

container=$(xcrun simctl get_app_container "$udid" "$bundle" data)
# On film launches the app draws a timecode strip along the top edge (FilmTimecode: the wall clock in milliseconds
# as 32 black and white blocks, every frame). Read it off every frame, so each logged sound lands on the frame it
# happened, however the recorder dropped or stalled; the film starts with the app's first frame, and the strip is
# cropped off. Without a strip, fall back to the recorder's start (about a second off, drifting).
ffprobe -v error -select_streams v -show_entries frame=pts_time -of csv=p=0 "$tmp/raw.mov" > "$tmp/pts.txt"
# One strip row per recorded frame (passthrough: no frames padded in for a constant rate).
ffmpeg -nostdin -v fatal -i "$tmp/raw.mov" -an -fps_mode passthrough \
  -vf "crop=iw:6:0:3,scale=32:1:flags=area,format=gray" -f rawvideo - > "$tmp/strip.raw"
touch "$tmp/marks.jsonl"
python3 - "$container/Documents/feel-log.jsonl" "$started" "$secs" "$tmp/pts.txt" "$tmp/strip.raw" "$tmp/events.json" \
  "$tmp/trim" "$tmp/marks.jsonl" "$tmp/marks.json" <<'PY'
import bisect, json, sys
log, started, secs, pts_file, strip_file, out, trim_file, marks_file, marks_out = sys.argv[1:10]
started, secs = float(started), float(secs)
entries = []
try:
    entries = [json.loads(line) for line in open(log)]
except FileNotFoundError:
    pass
pts = [float(line.split(",")[0]) for line in open(pts_file) if line.strip()]
strip = open(strip_file, "rb").read()
base = int(started * 1000)
read = []                                     # (film seconds, wall seconds) for every frame that decodes
for i, t in enumerate(pts):
    block = strip[i * 32:(i + 1) * 32]
    if len(block) < 32:
        break
    # A clean block is near black or white; a frame with a muddy one (compression, the launch zoom) is skipped.
    if any(40 < b < 215 for b in block):
        continue
    code = int("".join("1" if b > 128 else "0" for b in block), 2)
    wall_ms = base - (base % 2**32) + code
    if wall_ms - base > 2**31: wall_ms -= 2**32
    if base - wall_ms > 2**31: wall_ms += 2**32
    wall = wall_ms / 1000
    if started - 5 <= wall <= started + secs + 20:
        read.append((t, wall))
# Keep frames whose clock offset (wall − film) agrees with their neighbours' median: a misread bit makes an outlier.
frames = []
for i, (t, wall) in enumerate(read):
    near = sorted(w - f for f, w in read[max(0, i - 15):i + 16])
    if abs((wall - t) - near[len(near) // 2]) < 0.25:
        frames.append((t, wall))
frames.sort(key=lambda fw: fw[1])
if len(frames) >= 10:
    trim = frames[0][0]
    walls = [w for _, w in frames]
    def film_time(t):
        i = bisect.bisect_left(walls, t)
        if i >= len(frames):
            return frames[-1][0] + (t - frames[-1][1]) - trim
        return frames[i][0] - trim
    how = f"timed frame by frame from the timecode ({len(frames)} frames read)"
else:
    trim = 0.0
    film_time = lambda t: t - started
    how = "no timecode found; timed from the recorder's start (about a second off, drifting)"
events = [{"t": round(film_time(e["t"]), 3), "cue": e["cue"]} for e in entries]
events = [e for e in events if e["t"] >= 0]
json.dump(events, open(out, "w"))
# The driver's captions, on the same clock as the cues.
marks = [json.loads(line) for line in open(marks_file) if line.strip()]
mapped = []
for m in marks:
    item = {"t": round(film_time(m["t"]), 3), "text": m["cue"]}
    if "until" in m:                            # a cut: a stretch of the film to drop (the driver was waiting on the app)
        item["until"] = round(film_time(m["until"]), 3)
    mapped.append(item)
json.dump([m for m in mapped if m["t"] >= 0], open(marks_out, "w"), indent=1)
open(trim_file, "w").write(f"{trim:.3f}")
print(f"{len(events)} cues logged, {how}")
PY
trim=$(cat "$tmp/trim")
cp "$tmp/events.json" "$out/$name.cues.json"
[ -n "${FILM_DRIVER:-}" ] && cp "$tmp/marks.json" "$out/$name.marks.json"
[ "${FILM_KEEP_RAW:-0}" = 1 ] && cp "$tmp/raw.mov" "$out/$name.raw.mov"

# score <palette> <file>: the recording with that palette's soundtrack.
score() {
  "$synth" score "$1" "$tmp/events.json" "$tmp/sound-$1.wav" >/dev/null
  # Trim with a filter, not a fast seek: seeking these variable-rate recordings lands a second or more off. The film is
  # then resampled to a constant 60 fps at level 5.1 (see the header).
  ffmpeg -hide_banner -loglevel error -y -i "$tmp/raw.mov" -i "$tmp/sound-$1.wav" \
    -filter_complex "[0:v]trim=start=$trim,setpts=PTS-STARTPTS,crop=iw:ih-14:0:14,fps=60[v]" -map "[v]" -map 1:a \
    -c:v libx264 -preset veryfast -crf 20 -profile:v high -level:v 5.1 -pix_fmt yuv420p \
    -c:a aac -b:a 160k -af apad -shortest -movflags +faststart \
    "$2"
}
score "$palette" "$out/$name.mp4"
for p in ${FILM_PALETTES:-}; do score "$p" "$out/$name-$p.mp4"; done
if [ "${FILM_NO_HALF:-0}" != 1 ]; then
# Half speed is cut from the recording, not from the 60 fps film, so it keeps all of the recorder's frames and stays smooth.
# Its length is set outright (-t): `apad` makes the audio endless, and -shortest does not stop a filter_complex output.
half=$(python3 -c "import subprocess,sys; d=float(subprocess.run(['ffprobe','-v','error','-show_entries','format=duration','-of','csv=p=0',sys.argv[1]],capture_output=True,text=True).stdout); print(round(2*d,3))" "$out/$name.mp4")
ffmpeg -hide_banner -loglevel error -y -i "$tmp/raw.mov" -i "$tmp/sound-$palette.wav" \
  -filter_complex "[0:v]trim=start=$trim,setpts=2*(PTS-STARTPTS),crop=iw:ih-14:0:14,fps=60[v];[1:a]atempo=0.5,apad[a]" \
  -map "[v]" -map "[a]" -t "$half" -c:v libx264 -preset veryfast -crf 20 -profile:v high -level:v 5.1 -pix_fmt yuv420p \
  -c:a aac -b:a 160k -movflags +faststart \
  "$out/$name-half.mp4"
fi
poster=$(python3 -c "print(max(1, int($secs * 0.4)))")
ffmpeg -hide_banner -loglevel error -y -ss "$poster" -i "$out/$name.mp4" -frames:v 1 -q:v 3 "$out/$name.jpg"
if [ "${FILM_GIF:-0}" = 1 ]; then
  ffmpeg -hide_banner -loglevel error -y -t 12 -i "$out/$name.mp4" \
    -vf "fps=12,scale=360:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse" "$out/$name.gif"
fi
echo "$out/$name.mp4"
[ "$driver_status" = 0 ] || { echo "the driver exited $driver_status (the film was kept)" >&2; exit 3; }
