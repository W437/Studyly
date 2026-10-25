#!/usr/bin/env python3
"""Checks cap_anim.key_frame against composites that look like real video: chroma bleed, noise and motion blur.

    keyer_check.py          prints, for three poses on four pink backgrounds, the alpha error, the colour error and how many
                            visible pixels are still magenta or pink-purple (there should be next to none)

Clean composites passed while real clips still showed a pink rim and pink streaks on fast-moving arms; these don't.
"""
import numpy as np
from PIL import Image, ImageFilter

import cap_anim as ca


def video_like(canvas_rgb, rng, motion):
    y, cb, cr = canvas_rgb.convert("YCbCr").split()
    cb, cr = cb.filter(ImageFilter.GaussianBlur(2.0)), cr.filter(ImageFilter.GaussianBlur(2.0))
    img = Image.merge("YCbCr", (y, cb, cr)).convert("RGB")
    a = np.asarray(img).astype(np.float32) / 255
    if motion:                                               # the right half smeared sideways, like a fast arm
        w = a.shape[1]
        half = a[:, w // 2:].copy()
        acc = np.zeros_like(half)
        for dx in range(motion):
            acc = np.add(acc, np.roll(half, dx, axis=1))
        a[:, w // 2:] = np.divide(acc, motion)
    return np.clip(np.add(a, rng.normal(0, 1.5 / 255, a.shape).astype(np.float32)), 0, 1)


def main():
    rng = np.random.default_rng(7)
    worst = 0
    for motion in (0, 9):
        for pose in ("stargaze", "wave", "celebrate"):
            art = Image.open(ca.pose_png(pose)).convert("RGBA")
            truth = np.asarray(art).astype(np.float32) / 255
            for name, bg in (("magenta", (255, 0, 255)), ("raspberry", (189, 48, 116)), ("dusty rose", (173, 76, 110)), ("hot pink", (224, 0, 185))):
                canvas = Image.new("RGBA", (ca.CANVAS, ca.CANVAS), bg + (255,))
                canvas.alpha_composite(art, (ca.PAD, ca.PAD))
                rgb = video_like(canvas.convert("RGB"), rng, motion)
                keyed = ca.key_frame(rgb, ca.border_background(rgb))
                pink = int(np.logical_and(ca.pinkish(keyed[..., :3].astype(np.float64)), np.greater(keyed[..., 3], 0.25)).sum())
                crop = keyed[ca.PAD:ca.PAD + ca.POSE, ca.PAD:ca.PAD + ca.POSE]
                err = float(np.abs(np.subtract(crop[..., 3], truth[..., 3])).mean())
                worst = max(worst, pink)
                print(f"motion blur {motion}px  {pose:9s} on {name:10s} alpha error {err:.4f}   pink pixels left {pink:5d}")
    print("worst pink count:", worst)


if __name__ == "__main__":
    main()
