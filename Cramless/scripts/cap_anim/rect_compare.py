#!/usr/bin/env python3
"""A crop of Today's sky round Cap with the contrast turned up, from a film frame: shows whether a clip draws a lighter rectangle
or a halo behind him (the old encodes did; see docs/design.md ▸ Cap).

    rect_compare.py <film.mp4> <seconds> <out.png>

The crop is the sky's lower left (x 0 to 700, y 430 to 1080 of a 1206 x 2608 film), the levels 20 to 130 stretched to the full
range. Run it on the same moment of two films to compare."""
import subprocess, sys, io
import numpy as np
from PIL import Image

film, seconds, out = sys.argv[1], sys.argv[2], sys.argv[3]
png = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-ss", seconds, "-i", film, "-frames:v", "1", "-f", "image2pipe",
                      "-vcodec", "png", "-"], capture_output=True, check=True).stdout
im = np.asarray(Image.open(io.BytesIO(png)).convert("RGB")).astype(np.float32)
crop = im[430:1080, 0:700]
lo, hi = 20, 130
stretched = np.clip((crop - lo) / (hi - lo), 0, 1) ** 0.8 * 255
Image.fromarray(stretched.astype(np.uint8)).save(out)
print(out, stretched.shape)
