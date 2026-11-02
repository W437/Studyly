// Effects: particles, shake, flashes, whip streaks, a see-through-safe motion blur,
// hand-drawn marks and a before/after slider. Pure functions of the frame, seeded,
// so every render of a frame is identical.
import React from 'react';
import {AbsoluteFill, Freeze, useCurrentFrame, useVideoConfig} from 'remotion';
import {noise2D} from '@remotion/noise';
import {evolvePath} from '@remotion/paths';
import {C, clamp01, easeOut, font, glow, lerp, Pt} from './parts';

/** A small seeded random generator (never Math.random(): frames must render the same every time). */
export const rng = (seed: number) => {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
};

/**
 * Shards / confetti out of a point, `t` frames after the hit. Each piece has its own
 * speed, drag, gravity, spin and life, and fades over the back half of it (nothing pops
 * out of existence). Confetti: gravity ~0.6, drag 0.93, spread 2π, bigger `size`.
 */
export const Burst: React.FC<{
  seed: number; x: number; y: number; count: number; t: number;
  speed?: [number, number]; life?: [number, number]; gravity?: number; drag?: number; size?: [number, number];
  dir?: number; spread?: number; colors?: string[]; glowPx?: number;
}> = ({seed, x, y, count, t, speed = [10, 26], life = [16, 30], gravity = 0.9, drag = 0.9, size = [8, 22],
  dir = 0, spread = Math.PI * 2, colors = [C.accent, C.sweepEdge, C.accentDeep, '#ffffff'], glowPx = 10}) => {
  if (t < 0) return null;
  const r = rng(seed);
  const parts: React.ReactNode[] = [];
  for (let i = 0; i < count; i++) {
    const a = dir + (r() - 0.5) * spread;
    const v0 = speed[0] + r() * (speed[1] - speed[0]);
    const lf = life[0] + r() * (life[1] - life[0]);
    const sz = size[0] + r() * (size[1] - size[0]);
    const sliver = r() < 0.55;
    const spin0 = r() * 360;
    const spinV = (r() - 0.5) * 40;
    const col = colors[Math.floor(r() * colors.length)];
    const tt = t - r() * 2;
    if (tt < 0 || tt > lf) continue;
    const dist = drag === 1 ? v0 * tt : (v0 * (1 - Math.pow(drag, tt))) / (1 - drag);
    const px = x + Math.cos(a) * dist;
    const py = y + Math.sin(a) * dist + 0.5 * gravity * tt * tt;
    const fade = 1 - clamp01((tt - lf * 0.45) / (lf * 0.55));
    const pop = clamp01(tt / 2);
    const w = sliver ? sz * 0.34 : sz * 0.62;
    const h = sliver ? sz * 1.5 : sz * 0.62;
    parts.push(
      <div key={i} style={{position: 'absolute', left: px - w / 2, top: py - h / 2, width: w, height: h, background: col, borderRadius: 3,
        opacity: fade * pop, transform: `rotate(${spin0 + spinV * tt}deg) scale(${0.6 + 0.4 * pop})`,
        boxShadow: glowPx ? `0 0 ${glowPx}px ${col}` : undefined}} />,
    );
  }
  return <>{parts}</>;
};

/** Screen shake: decaying noise after each hit. Returns [dx, dy, degrees]; apply to the world, not the captions. */
export const shake = (f: number, hitList: {at: number; amp: number}[]) => {
  let dx = 0, dy = 0, rot = 0;
  hitList.forEach((h, i) => {
    const t = f - h.at;
    if (t < 0 || t > 16) return;
    const k = h.amp * Math.exp(-t / 3.6);
    dx += noise2D(`sx${i}`, t * 0.55, 0) * k;
    dy += noise2D(`sy${i}`, t * 0.55, 3) * k;
    rot += noise2D(`sr${i}`, t * 0.5, 7) * k * 0.035;
  });
  return [dx, dy, rot] as const;
};

/** A full-frame flash that decays after `at` (0.1–0.4 for a split, 0.6 for the big one). */
export const Flash: React.FC<{f: number; at: number; amount?: number; decay?: number; color?: string}> = ({f, at, amount = 0.3, decay = 3, color = '#f4f8ff'}) => {
  const a = f >= at ? amount * Math.exp(-(f - at) / decay) : 0;
  return a > 0.01 ? <AbsoluteFill style={{background: color, opacity: a, pointerEvents: 'none'}} /> : null;
};

/** The frame's edges light up in the accent after a hit. */
export const EdgeGlow: React.FC<{f: number; at: number[]; decay?: number; color?: string}> = ({f, at, decay = 6, color = C.glow}) => {
  const v = at.reduce((m, a) => (f >= a && f - a < 30 ? Math.max(m, Math.exp(-(f - a) / decay)) : m), 0);
  return v > 0.01 ? <AbsoluteFill style={{boxShadow: `inset 0 0 140px 30px rgba(${color},${0.55 * v})`, pointerEvents: 'none'}} /> : null;
};

/** Speed lines along a whip's direction for ~14 frames from `at`. */
export const Streaks: React.FC<{f: number; at: number; dir: 'up' | 'down' | 'left' | 'right'; count?: number; seed?: number}> = ({f, at, dir, count = 22, seed = 1}) => {
  const {width: W, height: H} = useVideoConfig();
  const t = f - at;
  if (t < 0 || t > 14) return null;
  const r = rng(at * 7 + seed);
  const a = Math.sin(clamp01(t / 14) * Math.PI);
  const horizontal = dir === 'left' || dir === 'right';
  const lines: React.ReactNode[] = [];
  for (let i = 0; i < count; i++) {
    const len = 220 + r() * 520, lane = r(), sp = 90 + r() * 120, th = 2 + r() * 4, o = (0.25 + r() * 0.55) * a;
    const d = t * sp - r() * 400;
    const grad = `linear-gradient(${horizontal ? (dir === 'left' ? 90 : 270) : dir === 'up' ? 180 : 0}deg, ${glow(0)}, ${glow(0.9)}, rgba(255,255,255,0))`;
    const style: React.CSSProperties = horizontal
      ? {left: dir === 'left' ? W + 120 - d : -600 + d, top: 300 + lane * (H - 600), width: len, height: th}
      : {left: 80 + lane * (W - 160), top: dir === 'up' ? H + 80 - d : -600 + d, width: th, height: len};
    lines.push(<div key={i} style={{position: 'absolute', ...style, borderRadius: th, opacity: o, background: grad}} />);
  }
  return <>{lines}</>;
};

/**
 * Motion blur that keeps 3D-transformed layers solid: the same layer drawn a few
 * sub-frames back, fainter, under the sharp current one. Remotion's <CameraMotionBlur>
 * averages whole frames, which makes 3D-transformed (preserve-3d / perspective) layers
 * see-through in Chrome; use this instead. Only wrap what moves fast (it renders the
 * children `samples` times).
 */
export const Smear: React.FC<{samples?: number; span?: number; children: React.ReactNode}> = ({samples = 6, span = 1.3, children}) => {
  const f = useCurrentFrame();
  return (
    <AbsoluteFill>
      {Array.from({length: samples}).map((_, i) => {
        const k = samples - 1 - i;
        const o = k === 0 ? 1 : 0.42 * (1 - k / samples);
        return <AbsoluteFill key={i} style={{opacity: o}}><Freeze frame={f - (k / (samples - 1)) * span}>{children}</Freeze></AbsoluteFill>;
      })}
    </AbsoluteFill>
  );
};

// ------------------------------------------------------------ hand-drawn marks
/** A smooth path through points (Catmull-Rom as cubic Béziers). */
export const smoothPath = (pts: Pt[]) => {
  let d = `M ${pts[0][0].toFixed(1)} ${pts[0][1].toFixed(1)}`;
  for (let i = 0; i < pts.length - 1; i++) {
    const p0 = pts[Math.max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[Math.min(pts.length - 1, i + 2)];
    const c1: Pt = [p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6];
    const c2: Pt = [p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6];
    d += ` C ${c1[0].toFixed(1)} ${c1[1].toFixed(1)} ${c2[0].toFixed(1)} ${c2[1].toFixed(1)} ${p2[0].toFixed(1)} ${p2[1].toFixed(1)}`;
  }
  return d;
};

/** A quick marker loop round (cx, cy): a bit more than one turn, wobbly, overshooting its start. */
export const Loop: React.FC<{cx: number; cy: number; rx: number; ry: number; progress: number; opacity?: number; seed?: number; width?: number; color?: string; halo?: string}> = ({
  cx, cy, rx, ry, progress, opacity = 1, seed = 1, width = 16, color = C.accent, halo = 'rgba(255,255,255,0.9)',
}) => {
  if (progress <= 0 || opacity <= 0) return null;
  const pts: Pt[] = [];
  const start = -Math.PI * 0.7 + seed * 0.13;
  for (let i = 0; i <= 48; i++) {
    const t = i / 48;
    const a = start + t * 1.16 * Math.PI * 2;
    const wob = 1 + 0.05 * Math.sin(a * 2 + seed * 1.7) + 0.03 * Math.sin(a * 3 + seed * 2.9);
    const grow = 0.96 + 0.1 * t;
    pts.push([cx + Math.cos(a) * rx * wob * grow, cy + Math.sin(a) * ry * wob * grow - t * ry * 0.06]);
  }
  const d = smoothPath(pts);
  const ev = evolvePath(clamp01(progress), d);
  return (
    <svg style={{position: 'absolute', left: 0, top: 0, overflow: 'visible', pointerEvents: 'none', opacity}} width={1} height={1}>
      <path d={d} fill="none" stroke={halo} strokeWidth={width + 10} strokeLinecap="round" strokeLinejoin="round"
        strokeDasharray={ev.strokeDasharray} strokeDashoffset={ev.strokeDashoffset} opacity={0.75} />
      <path d={d} fill="none" stroke={color} strokeWidth={width} strokeLinecap="round" strokeLinejoin="round"
        strokeDasharray={ev.strokeDasharray} strokeDashoffset={ev.strokeDashoffset} />
    </svg>
  );
};

/** A hand-drawn arrow from a to b, bowed by `bend`; the head draws last. */
export const Arrow: React.FC<{a: Pt; b: Pt; bend?: number; progress: number; opacity?: number; width?: number; color?: string; head?: number}> = ({
  a, b, bend = 0.25, progress, opacity = 1, width = 12, color = C.accent, head = 44,
}) => {
  if (progress <= 0 || opacity <= 0) return null;
  const mx = (a[0] + b[0]) / 2, my = (a[1] + b[1]) / 2;
  const dx = b[0] - a[0], dy = b[1] - a[1];
  const c: Pt = [mx - dy * bend, my + dx * bend];
  const shaft = `M ${a[0]} ${a[1]} Q ${c[0]} ${c[1]} ${b[0]} ${b[1]}`;
  const tx = b[0] - c[0], ty = b[1] - c[1];
  const tl = Math.hypot(tx, ty) || 1;
  const ux = tx / tl, uy = ty / tl;
  const rot = (x: number, y: number, ang: number): Pt => [x * Math.cos(ang) - y * Math.sin(ang), x * Math.sin(ang) + y * Math.cos(ang)];
  const h1 = rot(-ux * head, -uy * head, 0.5), h2 = rot(-ux * head, -uy * head, -0.5);
  const headD = `M ${b[0] + h1[0]} ${b[1] + h1[1]} L ${b[0]} ${b[1]} L ${b[0] + h2[0]} ${b[1] + h2[1]}`;
  const e1 = evolvePath(clamp01(progress / 0.75), shaft);
  const ph = clamp01((progress - 0.72) / 0.28);
  const e2 = evolvePath(ph, headD);
  const common = {fill: 'none', stroke: color, strokeWidth: width, strokeLinecap: 'round' as const, strokeLinejoin: 'round' as const};
  return (
    <svg style={{position: 'absolute', left: 0, top: 0, overflow: 'visible', pointerEvents: 'none', opacity}} width={1} height={1}>
      <g style={{filter: `drop-shadow(0 0 10px ${glow(0.55)})`}}>
        <path d={shaft} {...common} strokeDasharray={e1.strokeDasharray} strokeDashoffset={e1.strokeDashoffset} />
        {ph > 0 ? <path d={headD} {...common} strokeDasharray={e2.strokeDasharray} strokeDashoffset={e2.strokeDashoffset} /> : null}
      </g>
    </svg>
  );
};

/** A fingertip: comes down, presses at `at`, a ring spreads. Say in the ad's notes that touches are drawn. */
export const Tap: React.FC<{f: number; at: number; x: number; y: number; r?: number}> = ({f, at, x, y, r = 58}) => {
  const t = f - at;
  if (t < -8 || t > 16) return null;
  const come = clamp01((t + 8) / 6);
  const press = t < 0 ? 1 : t < 3 ? 1 - 0.18 * (t / 3) : 0.82 + 0.18 * clamp01((t - 3) / 5);
  const leave = clamp01((t - 6) / 8);
  const ring = clamp01(t / 14);
  const R = r * (1 + ring * 1.6);
  return (
    <div style={{position: 'absolute', left: 0, top: 0, pointerEvents: 'none'}}>
      {t >= 0 ? <div style={{position: 'absolute', left: x - R, top: y - R, width: R * 2, height: R * 2, borderRadius: '50%',
        border: `${8 * (1 - ring) + 2}px solid ${glow(0.9 * (1 - ring))}`}} /> : null}
      <div style={{position: 'absolute', left: x - r, top: y - r, width: r * 2, height: r * 2, borderRadius: '50%',
        background: 'rgba(255,255,255,0.55)', border: '5px solid rgba(20,30,40,0.25)', boxShadow: '0 6px 20px rgba(0,0,0,0.25)',
        opacity: come * (1 - leave), transform: `scale(${press * (1.25 - 0.25 * come)})`}} />
    </div>
  );
};

/**
 * A before/after slider over a whole w×h screen (native px): `after` left of the divider,
 * `before` right of it. Drive `x` with a spring: sweep in, hold, sweep back.
 */
export const BeforeAfter: React.FC<{x: number; w: number; h: number; before: React.ReactNode; after: React.ReactNode; handleY?: number; opacity?: number}> = ({
  x, w, h, before, after, handleY = h * 0.6, opacity = 1,
}) => {
  const label = (text: string, side: 'left' | 'right') => (
    <div style={{position: 'absolute', top: handleY + 150, height: 100, padding: '0 40px', borderRadius: 50, background: 'rgba(5,8,10,0.85)',
      color: '#fff', display: 'flex', alignItems: 'center', whiteSpace: 'nowrap', ...font(58, {letterSpacing: 3}),
      ...(side === 'right' ? {right: w - x + 30} : {left: x + 30})}}>{text}</div>
  );
  return (
    <div style={{position: 'absolute', left: 0, top: 0, width: w, height: h, overflow: 'hidden'}}>
      {after}
      <div style={{position: 'absolute', inset: 0, clipPath: `inset(0 0 0 ${x}px)`}}>{before}</div>
      <div style={{position: 'absolute', inset: 0, opacity}}>
        <div style={{position: 'absolute', left: x - 6, top: 0, width: 12, height: h, background: '#fff',
          boxShadow: `0 0 18px 4px ${glow(0.9)}, 0 0 60px 10px ${glow(0.45)}`}} />
        <div style={{position: 'absolute', left: x - 86, top: handleY - 86, width: 172, height: 172, borderRadius: '50%', background: '#fff',
          boxShadow: `0 10px 30px rgba(0,0,0,0.3), 0 0 0 10px ${glow(0.9)}`, display: 'flex', alignItems: 'center', justifyContent: 'center',
          ...font(80, {color: C.accentDeep, letterSpacing: 8})}}>‹ ›</div>
        {label('AFTER', 'right')}
        {label('BEFORE', 'left')}
      </div>
    </div>
  );
};

/** A slider position: sweeps from the right edge to `to`, holds, sweeps back (frames). */
export const sliderX = (f: number, w: number, inAt: number, holdTo: number, to = w * 0.36) => {
  if (f < inAt) return w;
  if (f < holdTo) return lerp(w, to, clamp01(easeOut(clamp01((f - inAt) / 14))));
  return lerp(to, w, clamp01((f - holdTo) / 14));
};
