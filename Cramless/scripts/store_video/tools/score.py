#!/usr/bin/env python3
"""The preview's sound: a short score and its sound effects, synthesized from the app's own palettes (Cramless/DesignSystem/Feel/CLSynth.swift:
marimba, kalimba and glass are additive voices with a mallet click, in C major pentatonic), plus a soft pad, a round bass, a kick, a shaker and claps.
No samples and no AI: it is deterministic and royalty-free, and every note and effect sits on an exact frame of the 30 fps edit (120 BPM, a beat is
15 frames). Writes renders/preview-audio.wav (stereo, 48 kHz) and prints the loudness.

    python3.13 -m venv .venv && .venv/bin/pip install numpy        # once
    .venv/bin/python tools/score.py [--out renders/preview-audio.wav] [--stems out/stems]

Use Python 3.13 or older: NumPy 2.2 on Python 3.14 can overwrite a reused array in place (`scalar * t` turned a time axis into 1e40 here; the app's
CLAUDE.md warns about the same bug), which silently produced NaNs and a silent pad.

The edit's frames are in EVENTS below; keep them in step with src/capling/*.tsx (the comments there name them).
"""
import argparse
import os
import subprocess
import sys
import numpy as np

SR = 48000
FPS = 30
BEAT = 0.5          # 120 BPM
LENGTH = 26.0       # seconds of audio (the picture is 25 s: the last second is the tail, trimmed when muxing)
rng = np.random.default_rng(20261101)


# ---- notes ------------------------------------------------------------------------------------------------------------------------------
_NAMES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def hz(name):
    """'C5' -> 523.25 Hz (A4 = 440)."""
    n = _NAMES[name[0]] + (1 if "#" in name else 0) - (1 if "b" in name[1:] else 0)
    octave = int(name[-1])
    return 440.0 * 2 ** ((n - 9 + 12 * (octave - 4)) / 12)


def frame(f):
    return f / FPS


# ---- the app's palettes (CLSynth.Palette) --------------------------------------------------------------------------------------------------
class Pal:
    def __init__(self, partials, attack, strike, strike_decay, length, gain):
        self.partials, self.attack, self.strike, self.strike_decay, self.length, self.gain = partials, attack, strike, strike_decay, length, gain


MARIMBA = Pal([(1, 1, 0.42), (3.93, 0.32, 0.11), (9.2, 0.1, 0.045)], 0.002, 0.22, 0.004, 0.9, 0.95)
KALIMBA = Pal([(1, 1, 0.85), (5.4, 0.22, 0.07), (2, 0.08, 0.35)], 0.0015, 0.18, 0.003, 1.4, 0.9)
GLASS = Pal([(1, 1, 1.1), (2.76, 0.28, 0.5), (5.4, 0.12, 0.22)], 0.012, 0.0, 0.001, 1.8, 0.85)


def struck(freq, pal, vel=1.0, damp=1.0, length=None):
    """One note on a palette: the partials of a struck bar, each fading at its own rate, and the mallet's click."""
    L = length or pal.length
    n = int(L * SR)
    t = np.arange(n) / SR
    s = np.zeros(n)
    for ratio, amp, dec in pal.partials:
        if freq * ratio < SR * 0.45:
            s += amp * np.exp(np.negative(t) / max(0.001, dec * damp)) * np.sin(2 * np.pi * freq * ratio * t)
    if pal.strike > 0:
        s += pal.strike * rng.uniform(-1, 1, n) * np.exp(np.negative(t) / max(0.0005, pal.strike_decay))
    if pal.attack > 0:
        s *= np.minimum(1, t / pal.attack)
    fade = int(0.03 * SR)
    s[-fade:] *= np.linspace(1, 0, fade)
    return vel * pal.gain * s


class Track:
    """A mono bus the events are mixed into at exact times."""

    def __init__(self):
        self.x = np.zeros(int((LENGTH + 2) * SR))

    def add(self, t, sig, gain=1.0):
        i = int(round(t * SR))
        if i < 0:
            sig = sig[-i:]
            i = 0
        j = min(len(self.x), i + len(sig))
        if j > i:
            self.x[i:j] += gain * sig[: j - i]

    def note(self, t, name_or_hz, pal, vel=1.0, gain=0.4, damp=1.0, length=None):
        f = hz(name_or_hz) if isinstance(name_or_hz, str) else name_or_hz
        self.add(t, struck(f, pal, vel, damp, length), gain)


# ---- filters (whole buses, in the frequency domain: zero phase) ---------------------------------------------------------------------------
def fft_filter(x, lo=None, hi=None, order=2):
    n = int(2 ** np.ceil(np.log2(len(x))))
    X = np.fft.rfft(x, n)
    f = np.fft.rfftfreq(n, 1 / SR)
    g = np.ones_like(f)
    if lo:
        g *= 1 / np.sqrt(1 + (lo / np.maximum(f, 1e-6)) ** (2 * order))
    if hi:
        g *= 1 / np.sqrt(1 + (f / hi) ** (2 * order))
    return np.fft.irfft(X * g, n)[: len(x)]


def reverb(x, rt60=1.9, predelay=0.02, damp_hz=5200, seed=7):
    """A stereo room from decaying noise (exponential tail, darker as it fades). Returns (L, R) wet only."""
    r = np.random.default_rng(seed)
    n = int(rt60 * 1.15 * SR)
    t = np.arange(n) / SR
    out = []
    for c in range(2):
        ir = r.normal(size=n) * np.exp(np.multiply(t, -6.9 / rt60))
        ir = fft_filter(ir, lo=180, hi=damp_hz, order=1)
        ir[: int(predelay * SR)] = 0
        ir = np.concatenate([np.zeros(int(predelay * SR) + c * 31), ir])[:n]
        ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
        m = int(2 ** np.ceil(np.log2(len(x) + len(ir))))
        y = np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(ir, m), m)[: len(x)]
        out.append(y)
    return out


# ---- drums and effects ------------------------------------------------------------------------------------------------------------------
def kick(vel=1.0):
    n = int(0.45 * SR)
    t = np.arange(n) / SR
    f = 46 + 120 * np.exp(np.negative(t) / 0.032)
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * np.exp(np.negative(t) / 0.15) * np.subtract(1.0, np.exp(np.negative(t) / 0.0015))
    click = rng.uniform(-1, 1, n) * np.exp(np.negative(t) / 0.003) * 0.35
    return vel * (body + click)


def shaker(vel=1.0, accent=False):
    n = int(0.09 * SR)
    t = np.arange(n) / SR
    s = rng.uniform(-1, 1, n) * np.minimum(1, t / 0.004) * np.exp(np.negative(t) / (0.034 if accent else 0.022))
    return vel * fft_filter(s, lo=4200)[:n]


def clap(vel=1.0):
    n = int(0.3 * SR)
    s = np.zeros(n)
    t = np.arange(n) / SR
    for k, d in enumerate([0.0, 0.011, 0.023]):
        i = int(d * SR)
        s[i:] += rng.uniform(-1, 1, n - i) * np.exp(np.negative(t[: n - i]) / (0.006 if k < 2 else 0.07))
    return vel * fft_filter(s, lo=900, hi=4200)[:n]


def crash(dur=1.8, vel=1.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    s = rng.uniform(-1, 1, n) * np.exp(np.negative(t) / (dur * 0.33)) * np.minimum(1, t / 0.002)
    return vel * fft_filter(s, lo=5200)[:n]


def riser(dur, vel=1.0, f0=300, f1=2600):
    n = int(dur * SR)
    t = np.arange(n) / SR
    u = t / dur
    noise = fft_filter(rng.uniform(-1, 1, n), lo=2200) * (u ** 2.2)
    f = f0 * (f1 / f0) ** u
    sweep = np.sin(2 * np.pi * np.cumsum(f) / SR) * (u ** 2.6) * 0.5
    out = vel * (noise + sweep)
    out[-int(0.01 * SR):] *= np.linspace(1, 0, int(0.01 * SR))
    return out


def whoosh(dur, vel=1.0, f_from=7000, f_to=500, shape=1.5):
    """Noise through a falling (or rising) low-pass: a quick pass of air."""
    n = int(dur * SR)
    u = np.arange(n) / n
    fc = f_from * (f_to / f_from) ** (u ** shape)
    a = np.subtract(1.0, np.exp(np.multiply(fc, -2 * np.pi / SR)))
    x = rng.uniform(-1, 1, n)
    y = np.zeros(n)
    s = 0.0
    for i in range(n):
        s += a[i] * (x[i] - s)
        y[i] = s
    env = np.sin(np.pi * np.minimum(1, u * 1.0)) ** 1.2
    return vel * y * env


def thump(vel=1.0, f=52, dur=0.5):
    n = int(dur * SR)
    t = np.arange(n) / SR
    return vel * np.sin(2 * np.pi * (f + 40 * np.exp(np.negative(t) / 0.05)) * t) * np.exp(np.negative(t) / 0.14)


def shutter(vel=1.0):
    """A camera's click: two short noise taps."""
    n = int(0.12 * SR)
    t = np.arange(n) / SR
    s = rng.uniform(-1, 1, n) * (np.exp(np.negative(t) / 0.004) + 0.7 * np.exp(np.negative(np.maximum(0.0, np.subtract(t, 0.045))) / 0.005) * (t > 0.045))
    return vel * fft_filter(s, lo=1200, hi=7000)[:n]


def pad_voice(freq, dur, vel=1.0):
    """A soft held tone: detuned sines with a few harmonics, a slow attack and a long release."""
    n = int((dur + 0.7) * SR)
    t = np.arange(n) / SR
    s = np.zeros(n)
    for det in (-0.0018, 0.0, 0.0021):
        for k, a in ((1, 1.0), (2, 0.35), (3, 0.14), (4, 0.06)):
            s += a * np.sin(2 * np.pi * freq * (1 + det) * k * t + rng.uniform(0, 6.28)) / 3
    att = np.minimum(1, t / 0.35)
    rel = np.where(t > dur, np.exp(np.negative(np.subtract(t, dur)) / 0.22), 1.0)
    return vel * s * att * rel


def bass_note(freq, dur, vel=1.0):
    n = int((dur + 0.15) * SR)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * freq * t) + 0.35 * np.sin(2 * np.pi * 2 * freq * t) + 0.12 * np.sin(2 * np.pi * 3 * freq * t)
    env = np.minimum(1, t / 0.006) * np.where(t > dur, np.exp(np.negative(np.subtract(t, dur)) / 0.05), 1.0) * (0.55 + 0.45 * np.exp(np.negative(t) / 0.35))
    return vel * s * env


# ---- the score -------------------------------------------------------------------------------------------------------------------------------
CHORDS = {  # pad voicing, bass root
    "C": (["C3", "G3", "D4", "E4"], "C2"), "G": (["G2", "D3", "B3", "A3"], "G2"), "Am": (["A2", "E3", "G3", "C4"], "A2"), "F": (["F2", "C3", "E3", "A3"], "F2"),
}
# bar -> chord (bar 1 starts at 0 s; a bar is 2 s)
BARS = {1: "C", 2: "G", 3: "Am", 4: "F", 5: "C", 6: "F", 7: "G", 8: "Am", 9: "F", 10: "C", 11: "G", 12: "C"}
ARP = {"C": ["E5", "G5", "C6", "G5"], "G": ["D5", "G5", "B5", "G5"], "Am": ["C5", "E5", "A5", "E5"], "F": ["C5", "F5", "A5", "F5"]}
# marimba phrases: (beat within the bar, note, length in beats)
MEL = {
    1: [(0, "G5"), (0.5, "E5"), (1, "G5"), (1.5, "A5"), (2, "G5"), (3, "E5"), (3.5, "D5")],
    2: [(0, "D5"), (0.5, "G5"), (1, "B5"), (1.5, "D6"), (2, "B5"), (3, "G5"), (3.5, "A5")],
    3: [(0, "E5"), (1, "A5"), (1.5, "C6"), (2, "B5"), (2.5, "A5"), (3, "E5")],
    4: [(0, "F5"), (1, "A5"), (1.5, "C6"), (2, "A5"), (3, "G5"), (3.5, "F5")],
    5: [(0, "E5"), (0.5, "G5"), (1, "C6"), (2, "B5"), (2.5, "G5"), (3, "E5")],
    6: [(0, "A5"), (0.5, "C6"), (1, "F6"), (1.5, "E6"), (2, "C6"), (2.5, "A5"), (3, "C6"), (3.5, "D6")],
    7: [(0, "D6"), (0.5, "B5"), (1, "G5"), (1.5, "B5"), (2, "D6"), (2.5, "G6"), (3, "F6"), (3.5, "D6")],
    10: [(0, "E6"), (0.5, "G6"), (1, "E6"), (1.5, "C6"), (2, "D6"), (2.5, "E6"), (3, "G5"), (3.5, "A5")],
    11: [(0, "D6"), (0.5, "B5"), (1, "D6"), (1.5, "G6"), (2, "F6"), (2.5, "D6"), (3, "B5"), (3.5, "D6")],
}
GLASS_PHRASE = {8: [(0, "E5"), (1, "A5"), (2, "C6"), (3, "B5")]}


def bar_t(bar, beat=0.0):
    return ((bar - 1) * 4 + beat) * BEAT


def build():
    mar, kal, gls, pad, bas, drm, shk, clp, fxs = (Track() for _ in range(9))
    sfx_dry, sfx_wet = Track(), Track()

    # ---- music ----
    for bar in range(1, 13):
        chord = BARS[bar]
        notes, root = CHORDS[chord]
        t0 = bar_t(bar)
        final_bar = bar == 12
        sections = {"hook": bar <= 2, "verse": 3 <= bar <= 5, "lift": 6 <= bar <= 7, "break": 8 <= bar <= 9, "final": 10 <= bar <= 11}
        # pad: held through the bar (two bars for the ending)
        for nn in notes:
            pad.add(t0, pad_voice(hz(nn), 2.0 * (2 if final_bar else 1) + (0.6 if final_bar else 0)), 0.11 if not sections["break"] else 0.15)
        if not sections["break"] and not final_bar:
            # bass on the beat and a push
            for b, d in ((0, 0.9), (1.5, 0.45), (2, 0.9), (3.5, 0.4)):
                bas.add(t0 + b * BEAT, bass_note(hz(root), d * BEAT * 2), 0.5)
        if sections["break"]:
            bas.add(t0, bass_note(hz(root), 3.6), 0.4)
        # drums
        if not sections["break"] and not final_bar:
            for b in (0, 2) + ((3.5,) if bar in (2, 7, 11) else ()):
                drm.add(t0 + b * BEAT, kick(0.9 if b != 3.5 else 0.55), 0.8)
            for k in range(8):
                shk.add(t0 + k * 0.25, shaker(0.9 if k % 2 else 0.5, accent=bool(k % 2)), 0.20)
            if not sections["hook"]:
                for b in (1, 3):
                    clp.add(t0 + b * BEAT, clap(0.8), 0.32)
        if sections["break"] and bar == 9:
            for k in range(4):
                shk.add(t0 + (2 + k * 0.5) * BEAT * 2 * 0.5, shaker(0.35 + 0.15 * k, accent=False), 0.16)
        # kalimba arpeggio on the "ands"
        if not final_bar and not sections["break"]:
            for j, nn in enumerate(ARP[chord]):
                kal.note(t0 + (j + 0.5) * BEAT, nn, KALIMBA, vel=0.55 if not sections["hook"] else 0.45, gain=0.30)
        # marimba lead
        for beat, nn in MEL.get(bar, []):
            mar.note(t0 + beat * BEAT, nn, MARIMBA, vel=0.9 if beat % 1 == 0 else 0.75, gain=0.40)
        for beat, nn in GLASS_PHRASE.get(bar, []):
            gls.note(t0 + beat * BEAT, nn, GLASS, vel=0.8, gain=0.34)

    # the five stars relight at 16.0 s, 16.25 s ... 17.0 s: five bells climbing the scale (C5 D5 E5 G5 A5), bar 9
    for tt, nn in zip((480, 487.5, 495, 502.5, 510), ("C6", "D6", "E6", "G6", "A6")):
        gls.note(frame(tt), nn, GLASS, vel=1.0, gain=0.42)
    # the lift into the end: a rising swell and a reversed cymbal that lands on 18.0 s (f540)
    fxs.add(16.9, riser(1.1, 0.8), 0.20)
    fxs.add(18.0 - 1.4, crash(1.4)[::-1].copy(), 0.30)
    # the final bars: marimba tremolo roll under the ending chord, then the hit at 22.0 s (f660)
    hit = frame(660)
    for nn, d in (("C5", 0), ("E5", 0.012), ("G5", 0.024), ("C6", 0.036), ("E6", 0.05)):
        mar.note(hit + d, nn, MARIMBA, vel=1.0, gain=0.55, damp=2.2, length=2.4)
    gls.note(hit, "C6", GLASS, vel=1.0, gain=0.5, length=3.2)
    gls.note(hit + 0.02, "G6", GLASS, vel=0.9, gain=0.38, length=3.2)
    drm.add(hit, kick(1.0), 1.0)
    fxs.add(hit, crash(2.6), 0.42)
    bas.add(hit, bass_note(hz("C2"), 2.6), 0.6)
    # a fill in the bar before: marimba run up the scale into the hit
    for j, nn in enumerate(("C5", "D5", "E5", "G5", "A5", "C6", "D6", "E6")):
        mar.note(hit - 0.5 + j * 0.0625, nn, MARIMBA, vel=0.6 + 0.05 * j, gain=0.36)

    # ---- sound effects: the app's own cues, on the edit's frames ----
    def cue(f, notes, pal=MARIMBA, vel=1.0, gain=0.45, wet=False, damp=1.0, length=None):
        tr = sfx_wet if wet else sfx_dry
        for dt, nn, v in notes:
            tr.note(frame(f) + dt, nn, pal, vel=vel * v, gain=gain, damp=damp, length=length)

    SCALE = ["C5", "D5", "E5", "G5", "A5", "C6", "D6", "E6"]
    # beat 1: the page flies in, the snap
    sfx_dry.add(frame(2), whoosh(0.35, 0.8, 6000, 900), 0.12)
    sfx_dry.add(frame(30), shutter(1.0), 0.5)
    cue(30, [(0, "C7", 1.0)], MARIMBA, gain=0.28, damp=0.25, length=0.25)
    sfx_wet.add(frame(31), thump(0.8, 70, 0.4), 0.22)
    # the scanner sweeps the page and the three marks land
    sfx_dry.add(frame(32), riser(0.9, 0.5, 500, 2200), 0.06)
    for f in (44, 50, 56):
        cue(f, [(0, "G6", 1.0)], KALIMBA, gain=0.26, damp=0.5)
    # three questions fly out of the page: the app's cardOut(0..2)
    for k, f in enumerate((70, 77, 84)):
        sfx_dry.add(frame(f - 5), whoosh(0.18, 0.7, 5000, 1400), 0.10)
        cue(f, [(0, SCALE[k], 1.0)], MARIMBA, gain=0.36, damp=0.6, wet=True)
    cue(92, [(0, "E5", 1.0)], MARIMBA, gain=0.42, wet=True)          # the right option
    cue(100, [(0, "G5", 0.8), (0.06, "C6", 0.9)], KALIMBA, gain=0.34, wet=True)   # the blank fills
    # the cards whip away, the new headline
    sfx_dry.add(frame(108), whoosh(0.4, 0.9, 7000, 600), 0.14)
    # typing: soft ticks, faster in the middle (the answer types itself between f146 and f210)
    for f in np.arange(146, 210, 2.0):
        sfx_dry.add(frame(f), shaker(0.5, accent=True)[: int(0.02 * SR)] * 1.0, 0.16)
    # the three key ideas light up: the scale climbs (C5 D5 E5), then Check, then Nice
    for k, f in enumerate((158, 195, 210)):
        cue(f, [(0, SCALE[k], 1.0)], MARIMBA, gain=0.42, wet=True)
    sfx_dry.add(frame(225), clap(0.8), 0.10)
    cue(225, [(0, "C5", 1.0)], MARIMBA, gain=0.30, damp=0.7)
    # "Nice!": the app's flourish and a little confetti shimmer
    cue(228, [(0, "C5", 0.85), (0.045, "E5", 0.9), (0.09, "G5", 0.95), (0.135, "C6", 1.0)], MARIMBA, gain=0.5, wet=True)
    sfx_wet.add(frame(229), whoosh(0.5, 0.7, 2500, 9000, 0.7), 0.10)
    # the three check marks leave the card and arrive: the ring is born
    for k, f in enumerate((268, 272, 277)):
        cue(f, [(0, ["G5", "C6", "E6"][k], 1.0)], KALIMBA, gain=0.30, wet=True)
    sfx_dry.add(frame(266), whoosh(0.5, 0.9, 3000, 7000, 0.8), 0.10)
    cue(285, [(0, "C5", 1.0), (0.0, "G5", 0.7)], GLASS, gain=0.46, wet=True)
    sfx_wet.add(frame(285), thump(0.9, 60, 0.5), 0.24)
    # the ring fills: a rising line, then the climb to 91% with the path being drawn
    sfx_wet.add(frame(289), riser(1.35, 0.6, 400, 1700), 0.07)
    for k, f in enumerate((309, 319, 329)):
        cue(f, [(0, ["E5", "G5", "A5"][k], 1.0)], KALIMBA, gain=0.22, wet=True)
    sfx_wet.add(frame(345), riser(1.0, 0.6, 600, 2800), 0.08)
    cue(375, [(0, "C5", 0.7), (0.05, "E6", 0.8), (0.10, "G6", 0.9), (0.15, "C7", 1.0)], MARIMBA, gain=0.5, wet=True)   # the app's "saved"
    sfx_dry.add(frame(345), whoosh(0.3, 0.6, 4000, 1200), 0.08)
    cue(390, [(0, "E6", 1.0)], KALIMBA, gain=0.34, wet=True)         # the end of the path
    # the plate becomes the sky
    sfx_dry.add(frame(404), whoosh(0.9, 1.0, 9000, 300, 1.2), 0.16)
    sfx_wet.add(frame(426), thump(1.0, 46, 0.9), 0.30)
    # the stars rise into the dawn: a bright shimmer, then Cap
    sfx_wet.add(frame(534), whoosh(1.4, 0.8, 1500, 9500, 0.8), 0.12)
    cue(573, [(0, "C5", 0.85), (0.045, "E5", 0.9), (0.09, "G5", 0.95), (0.135, "C6", 1.0)], MARIMBA, gain=0.46, wet=True)
    # Cap's own celebrate clip touches down at f618 (it starts on f544; his second leap is on the hit at f660)
    sfx_wet.add(frame(618), thump(0.7, 80, 0.3), 0.12)
    # the lockup: the icon pops, "capling" spelled in seven notes, the star lands
    cue(628, [(0, "G5", 1.0)], MARIMBA, gain=0.40, wet=True)
    for k in range(7):
        cue(636 + k * 2.2, [(0, SCALE[k], 0.9)], MARIMBA, gain=0.30, damp=0.7, wet=True)
    sfx_wet.add(frame(626), whoosh(1.0, 0.7, 2000, 9000, 0.7), 0.10)
    cue(660, [(0, "C7", 1.0)], GLASS, gain=0.34, wet=True, length=2.6)
    cue(690, [(0, "G6", 0.7), (0.06, "C7", 0.8)], GLASS, gain=0.22, wet=True)   # the glint across the word

    return dict(mar=mar, kal=kal, gls=gls, pad=pad, bas=bas, drm=drm, shk=shk, clp=clp, fxs=fxs, sfx_dry=sfx_dry, sfx_wet=sfx_wet)


def duck(x, hits, depth=0.45, rel=0.16):
    g = np.ones_like(x)
    t = np.arange(len(x)) / SR
    for h in hits:
        m = t >= h
        g = np.minimum(g, np.subtract(1.0, depth * m * np.exp(np.negative(np.maximum(0.0, np.subtract(t, h))) / rel)))
    return x * g


def mixdown(tr, stems=None):
    n = len(tr["mar"].x)
    kicks = [bar_t(b, k * 2 * 1.0) for b in range(1, 12) if not (8 <= b <= 9) for k in (0, 1)]
    kicks += [frame(660)]
    # buses: (track, pan -1..1, dry gain, reverb send)
    spec = {
        "mar": (-0.18, 1.0, 0.16), "kal": (0.28, 1.0, 0.22), "gls": (0.1, 0.9, 0.38), "pad": (0.0, 1.0, 0.30),
        "bas": (0.0, 1.0, 0.0), "drm": (0.0, 1.0, 0.04), "shk": (0.22, 1.0, 0.06), "clp": (-0.1, 1.0, 0.35), "fxs": (0.0, 1.0, 0.22),
        "sfx_dry": (0.0, 1.0, 0.0), "sfx_wet": (0.0, 1.0, 0.30),
    }
    L = np.zeros(n)
    R = np.zeros(n)
    send = np.zeros(n)
    for name, (pan, g, snd) in spec.items():
        x = tr[name].x.copy()
        if name == "pad":
            x = fft_filter(x, lo=90, hi=2400)
            x = duck(x, kicks, 0.40)
        if name == "bas":
            x = fft_filter(x, lo=35, hi=900)
            x = duck(x, kicks, 0.28)
        if name == "mar":
            x = fft_filter(x, lo=140)
        if name == "kal":
            x = fft_filter(x, lo=200)
        if name == "shk":
            x = fft_filter(x, lo=3500)
        if stems:
            os.makedirs(stems, exist_ok=True)
            write_wav(os.path.join(stems, f"{name}.wav"), np.stack([x, x], 1))
        lg, rg = np.sqrt(0.5 * (1 - pan)) * 1.0, np.sqrt(0.5 * (1 + pan)) * 1.0
        L += x * g * lg
        R += x * g * rg
        send += x * snd
    wl, wr = reverb(send)
    L += wl * 1.0
    R += wr * 1.0
    out = np.stack([L, R], 1)[: int(LENGTH * SR)] * 0.5
    # master: gentle soft-clip glue and a high-pass for DC; loudness is normalised afterwards
    out = np.tanh(out * 1.25) / np.tanh(1.25)
    peak = float(np.abs(out).max())
    if peak > 0.89:
        out = out * (0.89 / peak)
    out[:, 0] = fft_filter(out[:, 0], lo=28)
    out[:, 1] = fft_filter(out[:, 1], lo=28)
    # the picture ends at 25.0 s: the ending chord rings out and fades over its last 1.2 s; a 5 ms fade-in
    end = int(25.0 * SR)
    out = out[:end]
    fade_start = int(23.8 * SR)
    out[fade_start:] *= np.linspace(1, 0, len(out) - fade_start)[:, None] ** 1.5
    out[: int(0.005 * SR)] *= np.linspace(0, 1, int(0.005 * SR))[:, None]
    return out


def write_wav(path, x):
    import wave
    y = np.clip(x, -1, 1)
    y = (y * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(y.shape[1])
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(y.tobytes())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="renders/preview-audio.wav")
    ap.add_argument("--stems", default=None)
    a = ap.parse_args()
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    mix = mixdown(build(), a.stems)
    raw = a.out.replace(".wav", "-raw.wav")
    write_wav(raw, mix)
    # loudness: -16 LUFS integrated, true peak -1.5 dBTP (ffmpeg's loudnorm, two passes)
    r = subprocess.run(["ffmpeg", "-v", "info", "-y", "-i", raw, "-af", "loudnorm=I=-16:TP=-1.5:LRA=9:print_format=json", "-f", "null", "-"], capture_output=True, text=True)
    import json, re
    blob = re.search(r"\{[^{}]*\"input_i\"[^{}]*\}", r.stderr, re.S)
    if not blob:
        print(r.stderr[-800:])
        sys.exit("loudnorm measure failed")
    m = json.loads(blob.group(0))
    flt = (f"loudnorm=I=-16:TP=-1.5:LRA=9:measured_I={m['input_i']}:measured_TP={m['input_tp']}:measured_LRA={m['input_lra']}:measured_thresh={m['input_thresh']}:offset={m['target_offset']}:linear=true")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", raw, "-af", flt, "-ar", str(SR), "-c:a", "pcm_s16le", a.out], check=True)
    os.remove(raw)
    print(f"wrote {a.out}: measured {m['input_i']} LUFS, peak {m['input_tp']} dBTP before normalising")


if __name__ == "__main__":
    main()
