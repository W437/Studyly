#!/usr/bin/env python3
"""A storyboard of a finished render: 12 evenly spaced frames, each labelled with its
number, time and frame, in one image for the report (and for a quick look at the arc).

    python3 tools/storyboard.py renders/App-ad-6-speedrun.mp4 renders/ad6-storyboard.jpg
    python3 tools/storyboard.py in.mp4 out.jpg --frames 12 --width 300 --title "Ad 6 · Speedrun"

Portrait videos lay out 6×2, square and landscape 4×3. Needs ffmpeg and Pillow.
"""
import argparse
import math
import os
import subprocess
import sys
import tempfile

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("needs Pillow: pip3 install pillow")


def probe(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height,r_frame_rate:format=duration",
                          "-of", "default=nw=1", path], capture_output=True, text=True).stdout
    kv = dict(line.split("=", 1) for line in out.split() if "=" in line)
    num, den = kv.get("r_frame_rate", "30/1").split("/")
    return int(kv["width"]), int(kv["height"]), float(kv["duration"]), float(num) / float(den or 1)


def load_font(size):
    for f in ("/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc", "/Library/Fonts/Arial.ttf",
              "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        if os.path.exists(f):
            try:
                return ImageFont.truetype(f, size)
            except OSError:
                continue
    return ImageFont.load_default()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("video")
    ap.add_argument("out")
    ap.add_argument("--frames", type=int, default=12)
    ap.add_argument("--width", type=int, default=270, help="tile width in px")
    ap.add_argument("--title", help="a heading (default: the file name)")
    a = ap.parse_args()
    w, h, dur, fps = probe(a.video)
    n = a.frames
    cols = 6 if h > w * 1.2 else 4
    rows = math.ceil(n / cols)
    tw = a.width
    th = round(tw * h / w)
    label_h, pad = 34, 10
    title_h = 50
    title = a.title or os.path.basename(a.video)
    sheet = Image.new("RGB", (cols * (tw + pad) + pad, title_h + rows * (th + label_h + pad) + pad), (18, 20, 22))
    draw = ImageDraw.Draw(sheet)
    font, big = load_font(17), load_font(26)
    draw.text((pad, 12), f"{title}  ·  {dur:.1f} s  ·  {w}×{h}", fill=(236, 240, 238), font=big)
    with tempfile.TemporaryDirectory() as tmp:
        for i in range(n):
            t = (i + 0.5) * dur / n
            png = os.path.join(tmp, f"{i}.png")
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", f"{t:.3f}", "-i", a.video, "-frames:v", "1", png], check=True)
            im = Image.open(png).convert("RGB").resize((tw, th), Image.LANCZOS)
            x = pad + (i % cols) * (tw + pad)
            y = title_h + pad + (i // cols) * (th + label_h + pad)
            sheet.paste(im, (x, y))
            draw.text((x + 2, y + th + 7), f"{i + 1:02d}   {t:5.2f} s   f{round(t * fps)}", fill=(200, 206, 204), font=font)
    sheet.save(a.out, quality=86)
    print(f"{a.out}: {n} frames of {dur:.2f} s, {cols}×{rows}")


if __name__ == "__main__":
    main()
