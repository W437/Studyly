// Shared pieces for every ad. Import freely. While ad agents run in parallel, nobody
// edits this file (a half-edit would break every ad); change it between rounds.
//
// Everything is a pure function of the frame: no state, no timers, no Math.random().
// That is what lets Remotion render any frame in any order, and what lets a motion
// blur sample a fractional frame.
import React, {useEffect, useState} from 'react';
import {continueRender, delayRender, Easing, Freeze, getStaticFiles, Img, OffthreadVideo, staticFile, useVideoConfig} from 'remotion';

// ============================================================ brand (fill in per app)
// Take these from the app itself: its asset catalog / theme file for colours, its
// bundled font for the face, its 1024 px App Store icon. Never invent a palette.
export const BRAND = {
  name: 'Your App', // the name exactly as on the store listing (the end card's wordmark)
  tagline: 'Your one honest line.', // the end card's line; a callback to the ad's joke works best
  font: 'BrandFace', // the CSS family name useBrandFont registers
  fontFile: 'fonts/Manrope-ExtraBold.ttf', // under public/: a stand-in (OFL) until the app's own face is copied in
  fontWeight: 800,
  icon: 'art/appicon.png', // the App Store icon, 1024 px, under public/
  badge: 'art/appstore-badge.svg', // Apple's official badge, never modified (Google Play: its own official badge)
};

// Colour tokens. `glow` is the accent as "r,g,b" so it can go into rgba() at any alpha.
export const C = {
  ground: '#07090d', // the dark room most ads play in
  groundLit: '#131a26', // the light pooled behind the phone
  ink: '#f4f6f8',
  inkSoft: '#a4adb8',
  accent: '#6d8dff', // the app's accent: key words, the sweep, glows
  accentDeep: '#3a5ce0',
  sweepEdge: '#9db3ff', // the signature sweep's rim
  glow: '109,141,255',
};
export const glow = (a: number) => `rgba(${C.glow},${a})`;
export const font = (size: number, extra: React.CSSProperties = {}): React.CSSProperties => ({
  fontFamily: `${BRAND.font}, -apple-system, system-ui, sans-serif`, fontWeight: BRAND.fontWeight, fontSize: size,
  letterSpacing: -size * 0.025, lineHeight: 1.06, ...extra,
});

// ============================================================ canvas and footage size
// W and H are the 9:16 canvas for layout math; shared components read the real size from
// useVideoConfig(), so they also work in a square (1080×1080) or landscape ad.
export const FPS = 30;
export const W = 1080;
export const H = 1920;
// The captured screen in native pixels. iPhone 17 Simulator: 1206×2622 (radius ≈168).
// iPhone 17 Pro Max: 1320×2868. Read it off a gallery clip with ffprobe.
export const SCREEN = {w: 1206, h: 2622, radius: 168};

/** Is this file in public/? (Studio and renders both know.) Lets an ad fall back while art is missing. */
export const hasFile = (name: string) => {
  try {
    return getStaticFiles().some((s) => s.name === name);
  } catch {
    return false;
  }
};

// ============================================================ time: easing, springs, tracks
export const clamp01 = (v: number) => Math.max(0, Math.min(1, v));
export const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
export const ease = Easing.bezier(0.65, 0, 0.35, 1); // in-out, for moves between two rests
export const easeOut = Easing.bezier(0.16, 1, 0.3, 1); // arrivals: fast, then a long settle
export const easeIn = Easing.bezier(0.55, 0, 0.8, 0.35); // exits: gathers speed, leaves at full speed
export const backOut = Easing.bezier(0.2, 1.25, 0.35, 1); // a small overshoot

/** 0→1 between frames a and b with an easing (clamped both ends). */
export const ramp = (f: number, a: number, b: number, e: (t: number) => number = ease) =>
  b <= a ? (f >= b ? 1 : 0) : e(clamp01((f - a) / (b - a)));

/**
 * A damped spring 0→1 starting at frame `start`, closed form, so fractional frames work
 * (motion blur samples between frames). stiffness 170 / damping 14 overshoots a little;
 * 240/21 is a whip that lands clean; 120/17 is soft.
 */
export const springAt = (f: number, start: number, stiffness = 170, damping = 14) => {
  const t = (f - start) / FPS;
  if (t <= 0) return 0;
  const w0 = Math.sqrt(stiffness);
  const zeta = damping / (2 * w0);
  if (zeta < 1) {
    const wd = w0 * Math.sqrt(1 - zeta * zeta);
    return 1 - Math.exp(-zeta * w0 * t) * (Math.cos(wd * t) + ((zeta * w0) / wd) * Math.sin(wd * t));
  }
  return 1 - Math.exp(-w0 * t) * (1 + w0 * t);
};

/** A value through keyframes [frame, value], eased between each pair, held at both ends. */
export const track = (f: number, keys: [number, number][], e: (t: number) => number = ease) => {
  if (f <= keys[0][0]) return keys[0][1];
  for (let i = 1; i < keys.length; i++) {
    const [f1, v1] = keys[i];
    const [f0, v0] = keys[i - 1];
    if (f <= f1) return lerp(v0, v1, e(clamp01((f - f0) / (f1 - f0))));
  }
  return keys[keys.length - 1][1];
};

/** The strongest of decaying hits (1 on the hit frame, e^-t/decay after): kicks, flashes, glows. */
export const hits = (f: number, at: number[], decay = 5) =>
  at.reduce((m, a) => (f >= a ? Math.max(m, Math.exp(-(f - a) / decay)) : m), 0);

/** A quick swell that peaks `peak` frames after a landing and settles: the "bump" of a thing clicking into place. */
export const swell = (t: number, k = 0.02, peak = 4) => (t < 0 ? 0 : k * (t / peak) * Math.exp(1 - t / peak));

// ============================================================ the beat grid
// Cut, land and pop on the music. Analyse the track first (tools/analyse_audio.py gives
// the BPM and the first beat's frame), then build every timing from the grid.
export type Grid = {
  bpm: number;
  beat: number; // frames per beat (can be fractional: 120.25 BPM = 14.97)
  bar: number; // frames per bar
  at: (beats: number) => number; // exact frame of beat n (fractional)
  b: (beats: number) => number; // rounded: use for Sequence `from`
  bars: (n: number) => number; // rounded frame of bar n's downbeat
  pulse: (f: number, decay?: number) => number; // 1 on each beat, decaying after
};
export const beatGrid = (bpm: number, firstBeat = 0, beatsPerBar = 4): Grid => {
  const beat = (60 / bpm) * FPS;
  const at = (n: number) => firstBeat + n * beat;
  return {
    bpm, beat, bar: beat * beatsPerBar, at,
    b: (n) => Math.round(at(n)),
    bars: (n) => Math.round(at(n * beatsPerBar)),
    pulse: (f, decay = 4) => {
      const p = (f - firstBeat) / beat;
      return p < 0 ? 0 : Math.exp(-((p - Math.floor(p)) * beat) / decay);
    },
  };
};

// ============================================================ homography
// A CSS matrix3d that maps a w×h box onto any four corners: pages lying on a desk,
// screens in exact perspective, a lifted page that must start exactly on the phone.
export type Pt = [number, number];
export type Quad = [Pt, Pt, Pt, Pt]; // top-left, top-right, bottom-right, bottom-left
function adj(m: number[]) {
  return [
    m[4] * m[8] - m[5] * m[7], m[2] * m[7] - m[1] * m[8], m[1] * m[5] - m[2] * m[4],
    m[5] * m[6] - m[3] * m[8], m[0] * m[8] - m[2] * m[6], m[2] * m[3] - m[0] * m[5],
    m[3] * m[7] - m[4] * m[6], m[1] * m[6] - m[0] * m[7], m[0] * m[4] - m[1] * m[3],
  ];
}
function mm(a: number[], b: number[]) {
  const c = new Array(9).fill(0);
  for (let i = 0; i < 3; i++) for (let j = 0; j < 3; j++) {
    let s = 0;
    for (let k = 0; k < 3; k++) s += a[3 * i + k] * b[3 * k + j];
    c[3 * i + j] = s;
  }
  return c;
}
function mv(m: number[], v: number[]) {
  return [m[0] * v[0] + m[1] * v[1] + m[2] * v[2], m[3] * v[0] + m[4] * v[1] + m[5] * v[2], m[6] * v[0] + m[7] * v[1] + m[8] * v[2]];
}
function basis(p: number[]) {
  const m = [p[0], p[2], p[4], p[1], p[3], p[5], 1, 1, 1];
  const v = mv(adj(m), [p[6], p[7], 1]);
  return mm(m, [v[0], 0, 0, 0, v[1], 0, 0, 0, v[2]]);
}
/** Use on an element with `transformOrigin: '0 0'`, positioned at left 0, top 0. */
export function quadMatrix(w: number, h: number, q: Quad) {
  const s = basis([0, 0, w, 0, 0, h, w, h]);
  const d = basis([q[0][0], q[0][1], q[1][0], q[1][1], q[3][0], q[3][1], q[2][0], q[2][1]]);
  const t = mm(d, adj(s));
  for (let i = 0; i < 9; i++) t[i] /= t[8];
  return `matrix3d(${t[0]},${t[3]},0,${t[6]},${t[1]},${t[4]},0,${t[7]},0,0,1,0,${t[2]},${t[5]},0,${t[8]})`;
}
export const lerpQuad = (a: Quad, b: Quad, t: number): Quad => a.map((p, i) => [lerp(p[0], b[i][0], t), lerp(p[1], b[i][1], t)]) as Quad;

// ============================================================ footage
/** [ad frame, seconds into the clip file]: a piecewise-linear time map (speed up, hold, slow down). */
export type TimeKey = [number, number];
/** Seconds into the clip at frame f: held before the first key, continuing at the last segment's rate after the last. */
export const clipSeconds = (keys: TimeKey[], f: number, len?: number) => {
  let t: number;
  if (keys.length === 1 || f <= keys[0][0]) t = keys[0][1];
  else {
    let i = 0;
    while (i < keys.length - 2 && f > keys[i + 1][0]) i++;
    const [f0, t0] = keys[i];
    const [f1, t1] = keys[i + 1];
    t = t0 + ((t1 - t0) * (f - f0)) / (f1 - f0);
  }
  return Math.max(0, len ? Math.min(len - 1 / FPS, t) : t);
};

/**
 * The real app: exactly one frame of a constant-30-fps clip per ad frame, at native size.
 * Freeze + OffthreadVideo shows the frame the time map asks for, so holds and speed ramps
 * are exact. Keep speed-ups within ~2× (faster reads as fake). Pass `len` (the clip's
 * seconds, from the gallery manifest) so the last frame holds instead of running off the end.
 */
export const Footage: React.FC<{src: string; keys: TimeKey[]; f: number; len?: number; w?: number; h?: number}> = ({
  src, keys, f, len, w = SCREEN.w, h = SCREEN.h,
}) => (
  <Freeze frame={Math.round(clipSeconds(keys, f, len) * FPS)}>
    <OffthreadVideo src={staticFile(src)} muted style={{position: 'absolute', left: 0, top: 0, width: w, height: h}} />
  </Freeze>
);

/** A still of the app (a gallery still or a single clip frame), at native size. */
export const Still: React.FC<{src: string; w?: number; h?: number}> = ({src, w = SCREEN.w, h = SCREEN.h}) => (
  <Img src={staticFile(src)} style={{position: 'absolute', left: 0, top: 0, width: w, height: h}} />
);

// ============================================================ the phone presenter
// The owner's rule: the WHOLE screen is always on show. Scale it, tilt it, fly it,
// never crop into part of it. Children are drawn in native screen pixels.
export type Pose = {x: number; y: number; s: number; rx?: number; ry?: number; rz?: number; o?: number};

/** Motion blur for a moving pose: [x, y] blur from its speed between f-1 and f. */
export const poseBlur = (poseAt: (f: number) => Pose, f: number, k = 0.3, max = 70): [number, number] => {
  const a = poseAt(f), b = poseAt(f - 1);
  return [Math.min(max, Math.abs(a.x - b.x) * k), Math.min(max, Math.abs(a.y - b.y) * k)];
};

/** An SVG filter that blurs along x and y separately (a whip's directional blur). Reference it with `url(#id)`. */
export const DirBlur: React.FC<{id: string; x: number; y: number}> = ({id, x, y}) => (
  <svg width={0} height={0} style={{position: 'absolute'}}>
    <defs>
      <filter id={id} x="-30%" y="-30%" width="160%" height="160%" colorInterpolationFilters="sRGB">
        <feGaussianBlur stdDeviation={`${Math.max(0.01, x).toFixed(2)} ${Math.max(0.01, y).toFixed(2)}`} />
      </filter>
    </defs>
  </svg>
);

export const Phone: React.FC<{
  pose: Pose;
  children: React.ReactNode;
  id: string; // unique per phone on screen (names its blur filter)
  blur?: [number, number];
  bezel?: number; // native px; 0 with shell 'none' = just the screen with rounded corners
  shell?: 'dark' | 'light' | 'none';
  glowAmt?: number; // 0..1: accent light round the phone on a payoff
  sheen?: boolean;
  outside?: React.ReactNode; // drawn in native px outside the screen (badges above the phone…)
}> = ({pose, children, id, blur, bezel = 30, shell = 'dark', glowAmt = 0, sheen = true, outside}) => {
  const {x, y, s, rx = 0, ry = 0, rz = 0, o = 1} = pose;
  if (o <= 0.002 || s <= 0.005) return null;
  const pw = SCREEN.w + bezel * 2;
  const ph = SCREEN.h + bezel * 2;
  const blurred = !!blur && (blur[0] > 0.5 || blur[1] > 0.5);
  const shellBg = shell === 'light'
    ? 'linear-gradient(140deg, #fdfefe 0%, #d9dfdc 26%, #f4f6f5 52%, #c6ccc9 78%, #eef1f0 100%)'
    : 'linear-gradient(150deg, #3b413e 0%, #151816 28%, #0a0b0b 70%, #2e3431 100%)';
  return (
    <>
      {blurred ? <DirBlur id={`blur-${id}`} x={blur![0] / s} y={blur![1] / s} /> : null}
      <div style={{position: 'absolute', left: x - (pw * s) / 2, top: y - (ph * s) / 2, width: pw * s, height: ph * s, opacity: clamp01(o),
        transform: `perspective(2600px) rotateX(${rx}deg) rotateY(${ry}deg) rotateZ(${rz}deg)`}}>
        <div style={{position: 'absolute', left: 0, top: 0, width: pw, height: ph, transform: `scale(${s})`, transformOrigin: '0 0',
          filter: blurred ? `url(#blur-${id})` : undefined}}>
          {shell !== 'none' ? (
            <div style={{position: 'absolute', inset: 0, borderRadius: SCREEN.radius + bezel, background: shellBg,
              boxShadow: `0 90px 190px rgba(0,0,0,0.55), 0 30px 70px rgba(0,0,0,0.45), inset 0 0 0 3px rgba(255,255,255,0.12)${glowAmt > 0 ? `, 0 0 ${260 * glowAmt}px ${60 * glowAmt}px ${glow(0.5 * glowAmt)}` : ''}`}} />
          ) : null}
          <div style={{position: 'absolute', left: bezel, top: bezel, width: SCREEN.w, height: SCREEN.h, borderRadius: SCREEN.radius, overflow: 'hidden', background: '#000'}}>
            {children}
            {sheen ? <div style={{position: 'absolute', inset: 0, background: 'linear-gradient(125deg, rgba(255,255,255,0.10) 0%, rgba(255,255,255,0) 32%)'}} /> : null}
          </div>
          {outside}
        </div>
      </div>
    </>
  );
};

// ============================================================ captions
/**
 * Creator-style captions: words pop in one by one (`step` frames apart: an eighth note is
 * beat/2), `*starred*` words in the accent, `|` breaks the line. Centred on `cy`. They
 * lift and fade over their last 8 frames (never vanish). Keep them above or below the
 * phone, never over the part of the screen that proves the point.
 */
export const Words: React.FC<{f: number; from: number; to: number; text: string; step?: number; size?: number; cy?: number; maxW?: number; color?: string}> = ({
  f, from, to, text, step = 7.5, size = 96, cy = 330, maxW = 980, color = C.ink,
}) => {
  const {width} = useVideoConfig();
  if (f < from - 1 || f > to + 1) return null;
  const words = text.split(' ').filter(Boolean).map((w) => ({t: w.replace(/\*/g, ''), key: w.includes('*')}));
  const out = ramp(f, to - 8, to, easeIn);
  let n = -1;
  return (
    <div style={{position: 'absolute', left: (width - Math.min(maxW, width - 60)) / 2, width: Math.min(maxW, width - 60), top: cy, display: 'flex', flexWrap: 'wrap', justifyContent: 'center',
      columnGap: size * 0.25, rowGap: size * 0.04, opacity: 1 - out, transform: `translateY(-50%) translateY(${-40 * out}px) scale(${1 - 0.05 * out})`}}>
      {words.map((w, i) => {
        if (w.t === '|') return <div key={i} style={{flexBasis: '100%', height: 0}} />;
        n += 1;
        const at = from + n * step;
        const s = springAt(f, at, 320, 14);
        const shown = clamp01((f - at + 1) / 3);
        return (
          <span key={i} style={{...font(size), display: 'inline-block', color: w.key ? C.accent : color, opacity: shown,
            transform: `translateY(${(1 - s) * 34}px) scale(${0.5 + 0.5 * s}) rotate(${w.key ? (1 - s) * -8 : 0}deg)`,
            textShadow: w.key ? `0 0 34px ${glow(0.5)}, 0 8px 28px rgba(0,0,0,0.6)` : '0 8px 28px rgba(0,0,0,0.6)'}}>{w.t}</span>
        );
      })}
    </div>
  );
};

// ============================================================ the signature sweep
// Every app has one signature flourish (a scan line, a ripple, a check that draws itself,
// a card flip). Find it in the app and make it the ad's connective tissue: transitions,
// reveals, the end card. This is a generic light sweep: a bright core line, a lit grid
// trailing behind it and a soft wash. Put it in an overflow:hidden box and move `y`.
export const SignatureSweep: React.FC<{width: number; y: number; band?: number; thickness?: number; opacity?: number; grid?: number}> = ({
  width, y, band = 260, thickness = 10, opacity = 1, grid = 48,
}) => {
  const top = y - band;
  const off = ((-top % grid) + grid) % grid;
  return (
    <div style={{position: 'absolute', left: 0, top, width, height: band + thickness * 2, opacity, pointerEvents: 'none'}}>
      <div style={{position: 'absolute', left: 0, right: 0, top: 0, height: band,
        background: `linear-gradient(to bottom, ${glow(0)} 0%, ${glow(0.1)} 65%, ${glow(0.3)} 100%)`}} />
      {grid > 0 ? (
        <div style={{position: 'absolute', left: 0, right: 0, top: 0, height: band,
          backgroundImage: `linear-gradient(${glow(0.5)} 2px, transparent 2px), linear-gradient(90deg, ${glow(0.5)} 2px, transparent 2px)`,
          backgroundSize: `${grid}px ${grid}px`, backgroundPosition: `0px ${off}px`,
          WebkitMaskImage: 'linear-gradient(to bottom, transparent 0%, rgba(0,0,0,0.85) 100%)',
          maskImage: 'linear-gradient(to bottom, transparent 0%, rgba(0,0,0,0.85) 100%)'}} />
      ) : null}
      <div style={{position: 'absolute', left: -thickness, right: -thickness, top: band - thickness / 2, height: thickness, borderRadius: thickness,
        background: `linear-gradient(to bottom, ${C.sweepEdge}, #ffffff 40%, #ffffff 60%, ${C.accentDeep})`,
        boxShadow: `0 0 ${thickness * 2}px ${thickness * 0.5}px ${glow(0.95)}, 0 0 ${thickness * 7}px ${thickness * 1.6}px ${glow(0.45)}`}} />
    </div>
  );
};

/**
 * A new look sweeping in over the old: `after` is revealed above the sweep line.
 * `p` 0→1 is the sweep's travel down the w×h box.
 */
export const SweepReveal: React.FC<{p: number; w: number; h: number; before: React.ReactNode; after: React.ReactNode; band?: number}> = ({p, w, h, before, after, band = 520}) => (
  <div style={{position: 'absolute', left: 0, top: 0, width: w, height: h, overflow: 'hidden'}}>
    {p < 1 ? before : null}
    {p > 0 ? <div style={{position: 'absolute', inset: 0, clipPath: p < 1 ? `inset(0 0 ${(1 - p) * 100}% 0)` : undefined}}>{after}</div> : null}
    {p > 0 && p < 1 ? <SignatureSweep width={w} y={p * h} band={band} thickness={18} grid={72} /> : null}
  </div>
);

/** Focus brackets on any four points: they fly in (`fly` 0→1) and flare once (`flare` 0→1→0). */
export const Brackets: React.FC<{quad: Quad; len?: number; stroke?: number; opacity?: number; fly?: number; flare?: number; color?: string}> = ({
  quad, len = 64, stroke = 10, opacity = 1, fly = 1, flare = 0, color = C.accent,
}) => {
  const {width, height} = useVideoConfig();
  const cx = quad.reduce((s, p) => s + p[0], 0) / 4;
  const cy = quad.reduce((s, p) => s + p[1], 0) / 4;
  const paths = quad.map((p, i) => {
    const unit = (a: Pt) => {
      const dx = a[0] - p[0], dy = a[1] - p[1];
      const l = Math.hypot(dx, dy) || 1;
      return [dx / l, dy / l];
    };
    const a = unit(quad[(i + 1) % 4]), b = unit(quad[(i + 3) % 4]);
    const k = (1 - fly) * 1.4 + flare * 0.06;
    const px = p[0] + (p[0] - cx) * k, py = p[1] + (p[1] - cy) * k;
    const L = len * (1 + flare * 0.35);
    return `M ${px + a[0] * L} ${py + a[1] * L} L ${px} ${py} L ${px + b[0] * L} ${py + b[1] * L}`;
  });
  return (
    <svg width={width} height={height} style={{position: 'absolute', left: 0, top: 0, opacity, overflow: 'visible', pointerEvents: 'none'}}>
      {paths.map((d, i) => (
        <path key={i} d={d} fill="none" stroke={color} strokeWidth={stroke} strokeLinecap="round" strokeLinejoin="round"
          style={{filter: `drop-shadow(0 0 ${8 + flare * 12}px ${glow(0.9)})`}} />
      ))}
    </svg>
  );
};

// ============================================================ the end card
/**
 * The app icon, the name in the brand face (printed by the signature sweep), the line,
 * the official store badge, unmodified. Pieces spring in one after another from `at`;
 * hold it at least 1.5 s. `light` for ads that end on a light ground.
 */
export const EndCard: React.FC<{f: number; at: number; tagline?: string; light?: boolean; iconSize?: number; y?: number}> = ({
  f, at, tagline = BRAND.tagline, light = false, iconSize = 300, y,
}) => {
  const {width, height} = useVideoConfig();
  if (f < at - 2) return null;
  // y: the icon's centre; by default the block (≈ icon + 560 px) sits a little above the middle
  y = y ?? Math.round(height / 2 - 240);
  const icon = springAt(f, at, 190, 13);
  const print = ramp(f, at + 10, at + 34, (t) => t);
  const line = springAt(f, at + 30, 170, 16);
  const badge = springAt(f, at + 40, 150, 16);
  const halo = ramp(f, at, at + 24) * (0.85 + 0.15 * Math.sin(f / 13));
  const nameTop = y + iconSize / 2 + 70;
  const nameH = 150;
  const ink = light ? '#101418' : C.ink;
  const soft = light ? '#4d5661' : C.inkSoft;
  const hasIcon = hasFile(BRAND.icon);
  const hasBadge = hasFile(BRAND.badge);
  return (
    <>
      <div style={{position: 'absolute', left: width / 2 - 520, top: y - 470, width: 1040, height: 1040, borderRadius: '50%', opacity: halo,
        background: `radial-gradient(closest-side, ${glow(light ? 0.3 : 0.4)}, ${glow(0)})`}} />
      <div style={{position: 'absolute', left: width / 2 - iconSize / 2, top: y - iconSize / 2, width: iconSize, height: iconSize,
        borderRadius: iconSize * 0.2237, overflow: 'hidden', opacity: clamp01(icon * 3),
        transform: `scale(${Math.max(0, icon)}) rotate(${(1 - icon) * -14}deg)`,
        boxShadow: `0 40px 90px rgba(0,0,0,${light ? 0.22 : 0.55}), 0 0 80px ${glow(0.4)}`}}>
        {hasIcon ? <Img src={staticFile(BRAND.icon)} style={{width: iconSize, height: iconSize}} /> : (
          <div style={{width: '100%', height: '100%', background: `linear-gradient(150deg, ${C.accent}, ${C.accentDeep})`, display: 'flex',
            alignItems: 'center', justifyContent: 'center', ...font(iconSize * 0.5, {color: '#fff'})}}>{BRAND.name.slice(0, 1)}</div>
        )}
      </div>
      <div style={{position: 'absolute', left: 0, right: 0, top: nameTop, height: nameH, clipPath: `inset(0 0 ${(1 - print) * 100}% 0)`,
        display: 'flex', alignItems: 'center', justifyContent: 'center'}}>
        <span style={{...font(116), color: ink, whiteSpace: 'nowrap'}}>{BRAND.name}</span>
      </div>
      {print > 0 && print < 1 ? (
        <div style={{position: 'absolute', left: 90, top: nameTop, width: width - 180, height: nameH}}>
          <SignatureSweep width={width - 180} y={print * nameH} band={150} thickness={9} grid={38} />
        </div>
      ) : null}
      {tagline ? (
        <div style={{position: 'absolute', left: 0, right: 0, top: nameTop + nameH + 20, textAlign: 'center', opacity: clamp01(line * 2),
          transform: `translateY(${(1 - line) * 30}px)`, ...font(60, {color: soft, letterSpacing: -1.2})}}>{tagline}</div>
      ) : null}
      <div style={{position: 'absolute', left: 0, right: 0, top: nameTop + nameH + 150, display: 'flex', justifyContent: 'center',
        opacity: clamp01(badge * 1.5), transform: `translateY(${(1 - badge) * 40}px)`}}>
        {hasBadge ? <Img src={staticFile(BRAND.badge)} style={{height: 128}} /> : (
          <div style={{height: 128, width: 380, borderRadius: 24, border: `4px dashed ${soft}`, display: 'flex', alignItems: 'center',
            justifyContent: 'center', ...font(34, {color: soft, letterSpacing: 0})}}>official store badge</div>
        )}
      </div>
    </>
  );
};

// ============================================================ the brand face
/** Loads BRAND.fontFile before any frame renders (a missing file falls back to the system face, with a warning). */
export const useBrandFont = () => {
  const [handle] = useState(() => delayRender(`font ${BRAND.fontFile}`));
  useEffect(() => {
    const face = new FontFace(BRAND.font, `url(${staticFile(BRAND.fontFile)})`, {weight: String(BRAND.fontWeight)});
    face.load().then(() => {
      document.fonts.add(face);
      continueRender(handle);
    }).catch((e) => {
      console.warn(`Brand font ${BRAND.fontFile} failed to load: ${e}`);
      continueRender(handle);
    });
  }, [handle]);
};
