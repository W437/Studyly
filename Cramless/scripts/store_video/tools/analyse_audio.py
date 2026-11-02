#!/usr/bin/env python3
"""Analyses audio you can't listen to: the music an ad is cut to, or its sound effects.

    python3 tools/analyse_audio.py music.mp3                 # tempo, first beat, bars, sections, loudness, tail
    python3 tools/analyse_audio.py music.mp3 --bpm 150       # force the tempo, refine the phase
    python3 tools/analyse_audio.py music.mp3 --json out.json # the numbers for code
    python3 tools/analyse_audio.py --sfx sfx-*.mp3           # levels, lead-in to the peak, pitch, clicks

Music report:
  * duration, integrated loudness (LUFS), loudness range, true peak (ffmpeg ebur128)
  * tempo by autocorrelation of spectral flux (top candidates: half/double tempo show up
    here, pick the one the style asked for), then refined with the beat phase by a comb search
  * the beat in frames at --fps, the first beat's time and frame, the likely downbeat
  * RMS per bar with its frame: jumps of ≥ 3 dB are section changes (the drop, the break)
  * the strongest onsets (hits worth cutting on) with frames
  * the tail: does the track end in silence or cut off?
Needs ffmpeg and numpy.
"""
import argparse
import json
import re
import subprocess
import sys

try:
    import numpy as np
except ImportError:
    sys.exit("needs numpy: pip3 install numpy")

SR = 22050


def decode(path, sr=SR):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(sr), "-f", "f32le", "-"],
                         capture_output=True).stdout
    x = np.frombuffer(raw, dtype=np.float32).astype(np.float64)
    if not len(x):
        sys.exit(f"could not decode {path}")
    return x


def loudness(path):
    """Integrated LUFS, loudness range (LU) and true peak (dBFS) from ffmpeg's ebur128."""
    err = subprocess.run(["ffmpeg", "-nostats", "-i", path, "-af", "ebur128=peak=true", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    summary = err[err.rfind("Summary:"):] if "Summary:" in err else err

    def grab(label):
        m = re.search(label + r"\s*(-?[\d.]+|-inf)", summary)
        return None if not m or m.group(1) == "-inf" else float(m.group(1))
    return {"lufs": grab(r"I:"), "lra": grab(r"LRA:"), "true_peak": grab(r"Peak:")}


def db(v):
    return float(20 * np.log10(max(float(v), 1e-9)))


def rms_db(seg):
    return db(np.sqrt(np.mean(seg ** 2))) if len(seg) else -120.0


def flux_envelope(x, n=1024, hop=256):
    frames = np.lib.stride_tricks.sliding_window_view(x, n)[::hop] * np.hanning(n)
    spec = np.log1p(100 * np.abs(np.fft.rfft(frames, axis=1)))
    flux = np.concatenate([[0], np.maximum(0, np.diff(spec, axis=0)).sum(axis=1)])
    flux = np.maximum(0, flux - np.convolve(flux, np.ones(16) / 16, mode="same"))
    low_bins = max(2, int(150 / (SR / n)))
    low = spec[:, :low_bins].sum(axis=1)
    low_flux = np.concatenate([[0], np.maximum(0, np.diff(low))])
    return flux, low_flux, SR / hop


def tempo_candidates(flux, fr, lo, hi):
    ac = np.correlate(flux, flux, mode="full")[len(flux) - 1:]
    scores = []
    for bpm in np.arange(lo, hi + 0.001, 0.25):
        lag = 60 / bpm * fr
        l0 = int(np.floor(lag))
        if l0 + 2 >= len(ac):
            continue
        v = ac[l0] * (1 - (lag - l0)) + ac[l0 + 1] * (lag - l0)
        l2 = int(round(2 * lag))
        v += 0.5 * (ac[l2] if l2 < len(ac) else 0)
        scores.append((v, bpm))
    scores.sort(reverse=True)
    picked = []
    for v, bpm in scores:
        if all(abs(bpm - p) > 3 for _, p in picked):
            picked.append((v, bpm))
        if len(picked) == 3:
            break
    top = picked[0][0] if picked else 1
    return [(round(b, 2), round(v / top, 2)) for v, b in picked]


def refine(flux, fr, bpm, t0, t1):
    """Tempo ±2 BPM and beat phase that put the most onset energy on the beats in [t0, t1]."""
    best = (-1.0, bpm, 0.0)
    for bb in np.arange(bpm - 2, bpm + 2.001, 0.02):
        p = 60 / bb
        phases = np.arange(0, p, 0.004)
        k = np.arange(np.ceil(t0 / p) - 1, np.floor(t1 / p) + 1)
        times = phases[:, None] + k[None, :] * p
        ok = (times >= t0) & (times <= t1)
        idx = np.clip(np.round(times * fr).astype(int), 0, len(flux) - 1)
        vals = np.where(ok, flux[idx], 0).sum(axis=1) / np.maximum(1, ok.sum(axis=1))
        i = int(np.argmax(vals))
        if vals[i] > best[0]:
            best = (float(vals[i]), float(bb), float(phases[i]))
    return best[1], best[2]


def music(path, a):
    x = decode(path)
    dur = len(x) / SR
    loud = loudness(path)
    flux, low_flux, fr = flux_envelope(x)
    t0 = a.start if a.start is not None else min(2.0, dur * 0.1)
    t1 = a.end if a.end is not None else max(t0 + 2, dur - 3.5)
    seg = flux[int(t0 * fr):int(t1 * fr)]
    cands = tempo_candidates(seg, fr, a.min, a.max)
    # half/double tempo: autocorrelation scores both; ads live in about 88–175 BPM, so among
    # near-equal candidates prefer that range (say --bpm when you know what you asked for)
    pick = cands[0][0] if cands else 120.0
    close = [b_ for b_, sc in cands if sc >= 0.85]
    if not 88 <= pick <= 175:
        pick = next((b_ for b_ in close if 88 <= b_ <= 175), pick)
    related = [b_ for b_, sc in cands if b_ != pick and sc >= 0.6 and any(abs(b_ / pick - r) < 0.03 for r in (0.5, 2, 2 / 3, 1.5))]
    if a.bpm:
        bpm, phase = a.bpm, refine_phase(flux, fr, a.bpm, t0, t1)
    else:
        bpm, phase = refine(flux, fr, pick, t0, t1)
    period = 60 / bpm
    first = phase % period
    beat_frames = period * a.fps
    # downbeat: the beat slot (of 4) with the most low-band onset energy
    slots = []
    for k in range(4):
        bt = np.arange(first + k * period, t1, 4 * period)
        bt = bt[bt >= t0]
        idx = np.clip(np.round(bt * fr).astype(int), 0, len(low_flux) - 1)
        slots.append(float(low_flux[idx].sum()))
    k_down = int(np.argmax(slots))
    down = first + k_down * period
    ranked = sorted(slots, reverse=True)
    sure = ranked[0] > 1.5 * ranked[1] if len(ranked) > 1 and ranked[1] > 0 else True
    # RMS per bar from the downbeat (bar 0 may start before it)
    bar = 4 * period
    start = down - np.ceil(down / bar) * bar if down > 0 else down
    bars, prev = [], None
    b = start
    i = 0
    while b < dur:
        lo, hi = max(0.0, b), min(dur, b + bar)
        r = rms_db(x[int(lo * SR):int(hi * SR)])
        change = prev is not None and abs(r - prev) >= 3
        bars.append({"bar": i, "t": round(b, 3), "frame": round(b * a.fps, 1), "rms_db": round(r, 1), "change": change})
        prev = r
        b += bar
        i += 1
    # strongest onsets
    order = np.argsort(flux)[::-1]
    picked = []
    for j in order:
        if all(abs(j - q) > fr * 0.25 for q in picked):
            picked.append(int(j))
        if len(picked) >= 12:
            break
    onsets = [{"t": round(j / fr, 3), "frame": round(j / fr * a.fps, 1)} for j in sorted(picked)]
    # tail
    tail = [(round(s, 2), round(rms_db(x[int(s * SR):int((s + 0.25) * SR)]), 1)) for s in np.arange(max(0, dur - 6), dur - 0.01, 0.25)]
    end_db = rms_db(x[int(max(0, dur - 0.5) * SR):])
    rep = {
        "file": path, "duration": round(dur, 3), **loud,
        "tempo_candidates": [{"bpm": b_, "score": s_} for b_, s_ in cands], "tempo_related": related, "tempo_forced": bool(a.bpm),
        "bpm": round(bpm, 2), "beat_seconds": round(period, 4), "beat_frames": round(beat_frames, 3),
        "first_beat": {"t": round(first, 3), "frame": round(first * a.fps, 2)},
        "downbeat": {"t": round(down, 3), "frame": round(down * a.fps, 2), "slot_energy": [round(s / max(max(slots), 1e-9), 2) for s in slots], "certain": bool(sure)},
        "beats_frames": [round((first + n * period) * a.fps, 1) for n in range(0, 24)],
        "bars": bars, "onsets": onsets, "tail": tail, "last_half_second_db": round(end_db, 1),
        "ends_in_silence": end_db < -45,
    }
    return rep


def refine_phase(flux, fr, bpm, t0, t1):
    p = 60 / bpm
    phases = np.arange(0, p, 0.002)
    k = np.arange(np.ceil(t0 / p) - 1, np.floor(t1 / p) + 1)
    times = phases[:, None] + k[None, :] * p
    ok = (times >= t0) & (times <= t1)
    idx = np.clip(np.round(times * fr).astype(int), 0, len(flux) - 1)
    vals = np.where(ok, flux[idx], 0).sum(axis=1)
    return float(phases[int(np.argmax(vals))])


def print_music(r):
    print(f"{r['file']}: {r['duration']:.2f} s")
    print(f"loudness {r['lufs']} LUFS integrated, LRA {r['lra']} LU, true peak {r['true_peak']} dBFS "
          f"(final mix target: -14 to -16 LUFS, true peak <= -1 dBTP)")
    print("tempo candidates:", ", ".join(f"{c['bpm']} ({c['score']})" for c in r["tempo_candidates"]))
    if r["tempo_related"] and not r["tempo_forced"]:
        print(f"  note: {', '.join(str(b) for b in r['tempo_related'])} also fits (half/double/triplet feel): "
              f"if the plan asked for another tempo, rerun with --bpm")
    print(f"tempo {r['bpm']} BPM: a beat is {r['beat_seconds']} s = {r['beat_frames']} frames, a bar {r['beat_frames'] * 4:.2f} frames")
    print(f"first beat {r['first_beat']['t']} s (f{r['first_beat']['frame']}); likely downbeat {r['downbeat']['t']} s "
          f"(f{r['downbeat']['frame']}), low-band energy by beat slot {r['downbeat']['slot_energy']}"
          + ("" if r["downbeat"]["certain"] else " <- uncertain: take the bar from the section change (a drop lands on a downbeat) or the strongest onsets"))
    print("beats (frames):", " ".join(f"{b:g}" for b in r["beats_frames"]))
    print("RMS per bar (section changes marked *):")
    row = []
    for b in r["bars"]:
        row.append(f"{'*' if b['change'] else ' '}bar{b['bar']:<2} {b['t']:6.2f}s f{b['frame']:<6g} {b['rms_db']:6.1f}dB")
        if len(row) == 3:
            print("  " + "   ".join(row))
            row = []
    if row:
        print("  " + "   ".join(row))
    print("strongest onsets:", " ".join(f"{o['t']:.2f}s(f{o['frame']:g})" for o in r["onsets"]))
    print("tail (s:dB):", " ".join(f"{t}:{v:.0f}" for t, v in r["tail"]))
    print("ends in silence" if r["ends_in_silence"] else
          f"does NOT end in silence (last 0.5 s at {r['last_half_second_db']} dB): it may cut off; fade it or regenerate with an [Ending] chunk")


def sfx(path):
    x = decode(path, 48000)
    sr = 48000
    dur = len(x) / sr
    peak = float(np.max(np.abs(x)))
    peak_t = float(np.argmax(np.abs(x)) / sr)
    lead = next((i / sr for i, v in enumerate(np.abs(x)) if v > 0.02), 0.0)
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    freqs = np.fft.rfftfreq(len(x), 1 / sr)
    power = spec ** 2
    centroid = float((freqs * power).sum() / max(power.sum(), 1e-12))
    dom = float(freqs[int(np.argmax(spec))])
    band = (freqs > dom * 0.97) & (freqs < dom * 1.03)
    tonal = float(power[band].sum() / max(power.sum(), 1e-12))
    end = float(np.max(np.abs(x[-int(0.005 * sr):]))) if len(x) > sr * 0.01 else 0.0
    rms = rms_db(x)
    win = int(0.05 * sr)
    loudest = max((rms_db(x[i:i + win]) for i in range(0, max(1, len(x) - win), win // 2)), default=rms)
    # how long it stays within 20 dB of its loudest 50 ms: a tone that lasts is what pierces
    env = [rms_db(x[i:i + win]) for i in range(0, max(1, len(x) - win), win // 2)]
    sustained = sum(1 for v in env if v > loudest - 20) * (win / 2) / sr
    flags = []
    if loudest < -30 or peak < 0.063:
        flags.append("near-silent")
    if dom >= 3000 and tonal >= 0.6 and sustained > 0.15:
        flags.append(f"piercing: a sustained {dom:.0f} Hz tone (synthesize the beep instead)")
    elif centroid > 6000 and tonal > 0.3:
        flags.append(f"very bright ({centroid:.0f} Hz): keep it quiet")
    if end > 0.05:
        flags.append("ends hot: click risk (fade the last 30 ms)")
    if peak > 0.99:
        flags.append(f"peaks at {db(peak):+.1f} dBFS: give it a low volume in the mix")
    return {"file": path, "duration": round(dur, 3), "peak_db": round(db(peak), 1), "rms_db": round(rms, 1),
            "peak_at": round(peak_t, 3), "lead_in_frames": round(peak_t * 30, 1), "starts_after": round(lead, 3),
            "dominant_hz": round(dom), "centroid_hz": round(centroid), "tonal": round(tonal, 2), "sustained_s": round(sustained, 2), "flags": flags}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="+")
    ap.add_argument("--sfx", action="store_true", help="sound-effect checks instead of the music report")
    ap.add_argument("--bpm", type=float, help="force the tempo (refines the phase only)")
    ap.add_argument("--min", type=float, default=70, help="lowest tempo to consider")
    ap.add_argument("--max", type=float, default=180, help="highest tempo to consider")
    ap.add_argument("--from", dest="start", type=float, help="analyse from this second (skip a free-time intro)")
    ap.add_argument("--to", dest="end", type=float, help="…to this second (skip the ending)")
    ap.add_argument("--fps", type=float, default=30)
    ap.add_argument("--json", help="also write the report(s) here")
    a = ap.parse_args()
    if a.sfx:
        reps = [sfx(f) for f in a.files]
        for r in reps:
            print(f"{r['file']}: {r['duration']:.2f} s, peak {r['peak_db']} dB at {r['peak_at']} s "
                  f"(start it {r['lead_in_frames']:g} frames before the hit), RMS {r['rms_db']} dB, "
                  f"dominant {r['dominant_hz']} Hz, centroid {r['centroid_hz']} Hz"
                  + (f"  <- {'; '.join(r['flags'])}" if r["flags"] else "  ok"))
    else:
        reps = [music(f, a) for f in a.files]
        for r in reps:
            print_music(r)
    if a.json:
        json.dump(reps if len(reps) > 1 else reps[0], open(a.json, "w"), indent=1)


if __name__ == "__main__":
    main()
