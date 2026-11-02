// The preview's shared pieces: fonts, the sky ground, the toy-sign 3D lettering, sparkles, Cap, and the motion helpers.
// Everything is a pure function of the frame (no state, no Math.random), so any frame renders the same in any order.
import React, {useEffect, useState} from 'react';
import {continueRender, delayRender, Img, staticFile} from 'remotion';
import {clamp01, easeIn, easeOut, ramp, springAt, track, hits} from '../parts';
import {CAP_BOX} from './capBoxes';
import {COL, css, FPS, H, Sky, W} from './theme';

export {clamp01, easeIn, easeOut, ramp, springAt, track, hits};
export const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

// ---- seeded noise ----------------------------------------------------------------------------------------------------------------------
/** A deterministic 0..1 from a few integers (no state, so frames render in any order). */
export const hash = (...n: number[]) => {
  let h = 2166136261;
  for (const v of n) {
    h ^= Math.floor(v * 1000) + 0x9e3779b9;
    h = Math.imul(h, 16777619);
    h ^= h >>> 13;
  }
  h = Math.imul(h ^ (h >>> 15), 2246822507);
  h = Math.imul(h ^ (h >>> 13), 3266489909);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
};
export const rng = (seed: number) => {
  let i = 0;
  return () => hash(seed, i++);
};

// ---- fonts -----------------------------------------------------------------------------------------------------------------------------
export const F = {
  sf: "'SFVar', -apple-system, system-ui, sans-serif",
  rounded: "'SFRounded', ui-rounded, -apple-system, sans-serif",
  display: "'BricoDisplay', 'SFVar', sans-serif",
  title: "'BricoTitle', 'SFVar', sans-serif",
  heading: "'BricoHeading', 'SFVar', sans-serif",
};
/** Loads every face before the first frame renders; returns false until then (render nothing, so measures see the real fonts). */
export const useFonts = () => {
  const [handle] = useState(() => delayRender('capling fonts'));
  const [ready, setReady] = useState(false);
  useEffect(() => {
    const faces = [
      new FontFace('SFVar', `url(${staticFile('fonts/SFNS.ttf')})`, {weight: '1 1000', stretch: '30% 150%'}),
      new FontFace('SFRounded', `url(${staticFile('fonts/SFNSRounded.ttf')})`, {weight: '1 1000'}),
      new FontFace('BricoDisplay', `url(${staticFile('fonts/BricolageGrotesque-Display.ttf')})`),
      new FontFace('BricoTitle', `url(${staticFile('fonts/BricolageGrotesque-Title.ttf')})`),
      new FontFace('BricoHeading', `url(${staticFile('fonts/BricolageGrotesque-Heading.ttf')})`),
    ];
    Promise.all(faces.map((f) => f.load()))
      .then((loaded) => {
        loaded.forEach((f) => document.fonts.add(f));
        setReady(true);
        continueRender(handle);
      })
      .catch((e) => {
        console.warn('font load failed', e);
        setReady(true);
        continueRender(handle);
      });
  }, [handle]);
  return ready;
};
/** SF Pro at an exact weight and optical size (the same axes the listing art uses). */
export const sfStyle = (size: number, weight = 600, extra: React.CSSProperties = {}): React.CSSProperties => ({
  fontFamily: F.sf, fontSize: size, fontWeight: weight, fontVariationSettings: `'wght' ${weight}, 'wdth' 100, 'opsz' ${size >= 110 ? 96 : Math.max(17, Math.min(96, size * 0.8))}`,
  lineHeight: 1.12, ...extra,
});

// ---- the ground ------------------------------------------------------------------------------------------------------------------------
const CELL = 49; // 72 px on the 1290 px listing art
/**
 * The sky: a gradient and two fields of soft squares that drift upward and twinkle. `scroll` is the camera's climb in px.
 * `glow` lays a warm light on the horizon (the sunrise); 0..1.
 */
export const Ground: React.FC<{f: number; sky: Sky; scroll: number; sun?: {y: number; a: number; rays?: number}; dim?: number}> = ({f, sky, scroll, sun, dim = 0}) => {
  const rows = Math.ceil(H / CELL) + 2;
  const cols = Math.ceil(W / CELL) + 1;
  const row0 = Math.floor(scroll / CELL);
  const frac = scroll - row0 * CELL;
  const cells: React.ReactNode[] = [];
  const fields = [
    {sky: sky.pixA, seed: 7, density: 0.5},
    {sky: sky.pixB, seed: 17, density: 0.4},
  ];
  for (const fld of fields) {
    for (let r = 0; r < rows; r++) {
      const rowId = r + row0;
      for (let c = 0; c < cols; c++) {
        const u = hash(fld.seed, rowId, c);
        if (u > fld.density) continue;
        const a0 = fld.sky.lo + (fld.sky.hi - fld.sky.lo) * hash(fld.seed + 1, rowId, c);
        const tw = 0.7 + 0.3 * Math.sin(f * (0.03 + 0.04 * hash(fld.seed + 2, rowId, c)) + hash(fld.seed + 3, rowId, c) * 6.28);
        cells.push(<rect key={`${fld.seed}-${r}-${c}`} x={c * CELL} y={r * CELL - frac} width={CELL} height={CELL} fill={css(fld.sky.c, (a0 / 255) * tw * 1.5)} />);
      }
    }
  }
  const a = sun ? clamp01(sun.a) : 0;
  return (
    <div style={{position: 'absolute', left: 0, top: 0, width: W, height: H, overflow: 'hidden', background: `linear-gradient(180deg, ${sky.stops.map(([p, c]) => `${css(c)} ${p * 100}%`).join(', ')})`}}>
      <svg width={W} height={H} style={{position: 'absolute', left: 0, top: 0}}>{cells}</svg>
      {sun && a > 0 ? (
        <>
          <div style={{position: 'absolute', left: W / 2 - 190, top: sun.y - 190, width: 380, height: 380, borderRadius: '50%', opacity: a,
            background: 'radial-gradient(circle, rgba(255,253,238,1) 0%, rgba(255,242,196,0.96) 36%, rgba(255,218,128,0) 72%)'}} />
          <div style={{position: 'absolute', left: W / 2 - 520, top: sun.y - 520, width: 1040, height: 1040, borderRadius: '50%', opacity: a * 0.85,
            background: 'radial-gradient(circle, rgba(255,196,120,0.55) 0%, rgba(255,164,110,0.32) 38%, rgba(255,140,120,0) 70%)'}} />
          <div style={{position: 'absolute', left: 0, top: 0, width: W, height: H, opacity: a,
            background: `radial-gradient(circle 760px at 50% ${sun.y}px, rgba(255,246,205,0.95) 0%, rgba(255,224,150,0.62) 22%, rgba(255,200,120,0.26) 46%, rgba(255,190,110,0) 72%)`}} />
          {sun.rays ? (
            <div style={{position: 'absolute', left: 0, top: 0, width: W, height: H, opacity: a * sun.rays,
              background: `repeating-conic-gradient(from ${f * 0.35}deg at 50% ${sun.y}px, rgba(255,255,255,0.26) 0deg 7deg, rgba(255,255,255,0) 7deg 20deg)`,
              WebkitMaskImage: `radial-gradient(circle 900px at 50% ${sun.y}px, #000 0%, rgba(0,0,0,0.5) 40%, transparent 78%)`, maskImage: `radial-gradient(circle 900px at 50% ${sun.y}px, #000 0%, rgba(0,0,0,0.5) 40%, transparent 78%)`}} />
          ) : null}
        </>
      ) : null}
      {dim > 0 ? <div style={{position: 'absolute', inset: 0, background: `rgba(4,9,22,${dim})`}} /> : null}
    </div>
  );
};

// ---- stars -----------------------------------------------------------------------------------------------------------------------------
/** The four-point star with concave sides: the app's sparkle, the memory-sky star and the dot of the wordmark's i. */
export const starPath = (r: number, inner = 0.3) => {
  const pts: string[] = [];
  for (let k = 0; k < 8; k++) {
    const rad = k % 2 === 0 ? r : r * inner;
    const a = (k * Math.PI) / 4 - Math.PI / 2;
    pts.push(`${(rad * Math.cos(a)).toFixed(2)},${(rad * Math.sin(a)).toFixed(2)}`);
  }
  return `M${pts.join('L')}Z`;
};
export const Star4: React.FC<{x: number; y: number; r: number; color?: string; rot?: number; opacity?: number; glowAmt?: number; inner?: number}> = ({
  x, y, r, color = '#fff', rot = 0, opacity = 1, glowAmt = 0.6, inner = 0.3,
}) => {
  if (opacity <= 0.01 || r <= 0.3) return null;
  return (
    <svg width={r * 6} height={r * 6} viewBox={`${-r * 3} ${-r * 3} ${r * 6} ${r * 6}`} style={{position: 'absolute', left: x - r * 3, top: y - r * 3, opacity, overflow: 'visible', pointerEvents: 'none'}}>
      {glowAmt > 0 ? <circle r={r * 2.2} fill={color} opacity={0.22 * glowAmt} style={{filter: `blur(${r * 0.7}px)`}} /> : null}
      <path d={starPath(r, inner)} fill={color} transform={`rotate(${rot})`} strokeLinejoin="round" stroke={color} strokeWidth={r * 0.08} />
    </svg>
  );
};

/** The same star for use inside an <svg> (nested <svg> elements ignore left/top): a group at (x, y). */
export const Star4G: React.FC<{x: number; y: number; r: number; color?: string; rot?: number; opacity?: number; glowAmt?: number; inner?: number}> = ({
  x, y, r, color = '#fff', rot = 0, opacity = 1, glowAmt = 0.6, inner = 0.3,
}) => {
  if (opacity <= 0.01 || r <= 0.3) return null;
  return (
    <g transform={`translate(${x.toFixed(1)} ${y.toFixed(1)})`} opacity={opacity}>
      {glowAmt > 0 ? <circle r={r * 2} fill={color} opacity={0.28 * glowAmt} style={{filter: `blur(${(r * 0.8).toFixed(1)}px)`}} /> : null}
      <path d={starPath(r, inner)} fill={color} transform={`rotate(${rot.toFixed(1)})`} strokeLinejoin="round" stroke={color} strokeWidth={r * 0.08} />
    </g>
  );
};

export type Spark = {x: number; y: number; r: number; phase: number; speed: number; rot: number};
/** Sparkles scattered round a box (the headline), never inside it: seeded, so a scene always gets the same sky. */
export const scatter = (seed: number, count: number, keepOut: {x0: number; y0: number; x1: number; y1: number}, area = {x0: 30, y0: 40, x1: W - 30, y1: 620}): Spark[] => {
  const rand = rng(seed);
  const out: Spark[] = [];
  let guard = 0;
  while (out.length < count && guard++ < 400) {
    const x = lerp(area.x0, area.x1, rand());
    const y = lerp(area.y0, area.y1, rand());
    const r = 10 + rand() * rand() * 30;
    const m = 26 + r;
    if (x > keepOut.x0 - m && x < keepOut.x1 + m && y > keepOut.y0 - m && y < keepOut.y1 + m) continue;
    if (out.some((s) => Math.hypot(s.x - x, s.y - y) < 70 + s.r + r)) continue;
    out.push({x, y, r, phase: rand() * 6.28, speed: 0.07 + rand() * 0.07, rot: (rand() - 0.5) * 40});
  }
  return out;
};
export const Sparkles: React.FC<{f: number; sparks: Spark[]; color: string; appear?: number; out?: number; stagger?: number}> = ({f, sparks, color, appear = 0, out = 1e9, stagger = 2}) => (
  <>
    {sparks.map((s, i) => {
      const inn = springAt(f, appear + i * stagger, 220, 13);
      const outP = ramp(f, out + i * 1.2, out + i * 1.2 + 10, easeIn);
      const tw = 0.62 + 0.38 * Math.sin(f * s.speed + s.phase);
      const k = Math.max(0, inn) * (1 - outP) * tw;
      return <Star4 key={i} x={s.x} y={s.y} r={s.r * k} color={color} rot={s.rot + Math.sin(f * s.speed * 0.6 + s.phase) * 14} opacity={clamp01(inn * 3) * (1 - outP)} />;
    })}
  </>
);

// ---- the toy-sign lettering ------------------------------------------------------------------------------------------------------------
/** The listing's chunky word: SF Pro Black, each letter a little off its line, a thick extruded side down and right, a pale gradient face. */
export type LetterMove = {x?: number; y?: number; s?: number; sx?: number; sy?: number; r?: number; o?: number; blur?: number};
const extrusion = (size: number, edge: [number, number, number]) => {
  const depth = Math.max(4, Math.round(size * 0.07));
  const out: string[] = [];
  for (let k = depth; k >= 1; k--) {
    const t = (1 - k / depth) * 0.4;
    const c = edge.map((v) => Math.round(v + (Math.min(255, v * 1.5 + 30) - v) * t));
    out.push(`${(k * 0.62).toFixed(2)}px ${(k * 0.78).toFixed(2)}px 0 rgb(${c.join(',')})`);
  }
  return out.join(',');
};
let measureCanvas: HTMLCanvasElement | null = null;
/** The width of a string in SF Pro Black at `size` (a canvas measure: close enough to size a word to the frame). */
export const wordWidth = (text: string, size: number) => {
  if (!measureCanvas) measureCanvas = document.createElement('canvas');
  const ctx = measureCanvas.getContext('2d')!;
  ctx.font = `900 ${size}px SFVar`;
  return ctx.measureText(text).width * 0.97;
};
/** The size at which a word fills `maxW`, never above `maxSize`. */
export const fitSize = (text: string, maxW: number, maxSize: number) => Math.min(maxSize, (maxW / wordWidth(text, 100)) * 100);
export const Word3D: React.FC<{
  text: string; size: number; cx: number; cy: number; sky: Sky; seed?: number; letter?: (i: number, n: number) => LetterMove; shadow?: boolean; weight?: number;
}> = ({text, size, cx, cy, sky, seed = 3, letter, shadow = true, weight = 900}) => {
  const chars = [...text];
  const rand = rng(seed * 101 + chars.length);
  const edge = sky.edge as [number, number, number];
  const ext = extrusion(size, edge);
  const faceCss = `linear-gradient(180deg, ${css(sky.faceTop)} 22%, ${css(sky.faceBottom)} 82%)`;
  const base: React.CSSProperties = {
    fontFamily: F.sf, fontSize: size, lineHeight: 1, fontWeight: weight, fontVariationSettings: `'wght' ${weight}, 'wdth' 100, 'opsz' 96`,
    letterSpacing: -size * 0.03, whiteSpace: 'pre',
  };
  return (
    <div style={{position: 'absolute', left: cx, top: cy, width: 0, height: 0, filter: shadow ? `drop-shadow(0px ${size * 0.07}px ${size * 0.09}px ${css(sky.shadow, 0.4)})` : undefined}}>
      <div style={{position: 'absolute', left: 0, top: 0, display: 'flex', transform: 'translate(-50%, -52%)', alignItems: 'flex-start'}}>
        {chars.map((ch, i) => {
          const ang = (rand() - 0.5) * 6.4;
          const dy = (rand() - 0.5) * size * 0.07;
          const m = letter ? letter(i, chars.length) : {};
          const o = m.o ?? 1;
          if (o <= 0.003) return <span key={i} style={{...base, visibility: 'hidden'}}>{ch}</span>;
          const s = m.s ?? 1;
          return (
            <span key={i} style={{position: 'relative', display: 'inline-block', opacity: o,
              transform: `translate(${m.x ?? 0}px, ${(m.y ?? 0) + dy}px) rotate(${ang + (m.r ?? 0)}deg) scale(${s * (m.sx ?? 1)}, ${s * (m.sy ?? 1)})`,
              transformOrigin: '50% 70%', filter: m.blur ? `blur(${m.blur}px)` : undefined}}>
              <span style={{...base, position: 'absolute', left: 0, top: 0, color: css(edge), textShadow: ext}}>{ch}</span>
              <span style={{...base, position: 'relative', color: 'transparent', backgroundImage: faceCss, WebkitBackgroundClip: 'text', backgroundClip: 'text'}}>{ch}</span>
            </span>
          );
        })}
      </div>
    </div>
  );
};

/** One letter of a word dropping in: falls from above with a small bounce and a squash on landing. Returns the move for Word3D. */
export const dropIn = (f: number, start: number, i: number, stagger = 1.6, from = -620): LetterMove => {
  const at = start + i * stagger;
  const s = springAt(f, at, 230, 20);
  const land = hits(f, [at + 7], 4);
  if (f < at - 0.5) return {o: 0};
  return {y: (1 - s) * from, sy: 1 - 0.13 * land * (s > 0.5 ? 1 : 0), sx: 1 + 0.08 * land * (s > 0.5 ? 1 : 0), r: (1 - s) * (i % 2 ? 9 : -9), o: clamp01((f - at) / 2), blur: Math.max(0, (1 - s) * 5)};
};
/** One letter leaving: kicked upward off the frame, staggered. */
export const kickOut = (f: number, start: number, i: number, stagger = 1.2): LetterMove => {
  const at = start + i * stagger;
  const p = ramp(f, at, at + 12, easeIn);
  return {y: -p * 900, r: p * (i % 2 ? 22 : -22), s: 1 - 0.25 * p, o: 1 - clamp01((p - 0.6) / 0.4), blur: p * 8};
};

/** The small line above a word (SF Pro Heavy, white). */
export const SmallLine: React.FC<{text: string; cy: number; sky: Sky; f: number; at: number; out?: number; size?: number}> = ({text, cy, sky, f, at, out = 1e9, size = 64}) => {
  const words = text.split(' ');
  return (
    <div style={{position: 'absolute', left: 0, top: cy, width: W, display: 'flex', justifyContent: 'center', gap: size * 0.28, transform: 'translateY(-50%)'}}>
      {words.map((w, i) => {
        const s = springAt(f, at + i * 2.5, 260, 17);
        const o = ramp(f, out + i * 2, out + i * 2 + 9, easeIn);
        return (
          <span key={i} style={{...sfStyle(size, 800), color: css(sky.small), display: 'inline-block', opacity: clamp01(s * 3) * (1 - o),
            transform: `translateY(${(1 - s) * 40 - o * 60}px) scale(${0.6 + 0.4 * s})`, textShadow: `0 4px 14px ${css(sky.shadow, 0.25)}`}}>{w}</span>
        );
      })}
    </div>
  );
};

// ---- Cap -------------------------------------------------------------------------------------------------------------------------------
export type CapPose = keyof typeof CAP_BOX;
/**
 * A Cap pose sized by its visible art: `height` is the art's height in px, (cx, bottom) where its feet/bottom edge sits.
 * `rise` 0..1 brings him up from below the edge of his stage; idle motion breathes; `squash` is a decaying landing squash.
 */
// Cap's own animation clips: the app's transparent videos (`Cramless/Resources/CapClips/cap-<pose>.mov`, 24 fps, 720 px canvas with the pose at its
// true 600 px in the middle), decoded to PNG frames with alpha by `scripts/capclips.sh` into public/capclips/<pose>/0001.png ... A clip starts and
// ends exactly on its pose's drawing, so the drawing hands over to the clip and back with nothing visible (the same trick the app uses).
export const CAP_CLIP_FRAMES: Record<string, number> = {scan: 72, think: 97, nice: 97, point: 97, stargaze: 120, celebrate: 121};
const CLIP_FPS = 24;
const CLIP_CANVAS = 720;
const CLIP_MARGIN = (CLIP_CANVAS - 600) / 2;
export type ClipPlay = {
  /** The edit frame the clip's first picture is on. */
  start: number;
  /** 1 plays him at the app's speed; the 24 fps pictures are held on the 30 fps edit (every fifth one twice), never blended. */
  rate?: number;
  /** Shifts which pictures are held twice (in clip frames, 0 to 1). */
  phase?: number;
  /** The last picture to use (0-based). A clip ends by dissolving onto its pose's drawing, and where the two differ that shows as a double image for
   *  a few pictures; the edit stops on the last clean picture instead. */
  until?: number;
};
const clipSpeed = (c: ClipPlay) => (CLIP_FPS / FPS) * (c.rate ?? 1);
/** Which picture of a pose's clip is on screen at edit frame `f` (a 0-based index), or null before it starts. After the last picture, the last stays. */
export const clipFrame = (pose: string, c: ClipPlay | undefined, f: number): number | null => {
  const n = CAP_CLIP_FRAMES[pose];
  if (!c || !n || f < c.start) return null;
  return Math.min(c.until ?? n - 1, Math.floor((f - c.start) * clipSpeed(c) + (c.phase ?? 0) + 1e-6));
};
/** The edit frame the clip's last picture is reached on. */
export const clipEnd = (pose: string, c: ClipPlay) => c.start + (c.until ?? CAP_CLIP_FRAMES[pose] - 1) / clipSpeed(c);

export const Cap: React.FC<{pose: CapPose; cx: number; bottom: number; height: number; f: number; flip?: boolean; rise?: number; squash?: number; rot?: number; opacity?: number; dy?: number; idle?: number; shadow?: boolean; z?: number; clip?: ClipPlay}> = ({
  pose, cx, bottom, height, f, flip = false, rise = 1, squash = 0, rot = 0, opacity = 1, dy = 0, idle = 1, shadow = true, clip,
}) => {
  const [x0, y0, x1, y1] = CAP_BOX[pose];
  const k = height / (y1 - y0);
  const w = (x1 - x0) * k;
  // With a clip, the clip does the moving (he breathes and sways in it); the code's own breathing comes back only once it is over.
  const idleNow = clip ? idle * clamp01((f - clipEnd(pose, clip)) / 12) : idle;
  const breathe = 1 + 0.012 * idleNow * Math.sin(f / 17);
  const sway = 0.7 * idleNow * Math.sin(f / 41);
  const ci = clipFrame(pose, clip, f);
  if (opacity <= 0.003) return null;
  return (
    <div style={{position: 'absolute', left: cx - w / 2, top: bottom - height + dy + (1 - rise) * (height + 160), width: w, height, opacity,
      transform: `rotate(${rot + sway}deg) scale(${(flip ? -1 : 1) * (1 + squash * 0.5) * 1}, ${breathe * (1 - squash)})`, transformOrigin: '50% 100%',
      filter: shadow ? 'drop-shadow(0 22px 26px rgba(4,30,116,0.28))' : undefined}}>
      <div style={{position: 'absolute', left: -x0 * k, top: -y0 * k, width: 600 * k, height: 600 * k}}>
        {ci === null ? (
          <Img src={staticFile(`cap/${pose}.png`)} style={{width: 600 * k, height: 600 * k}} />
        ) : (
          <Img src={staticFile(`capclips/${pose}/${String(ci + 1).padStart(4, '0')}.png`)}
            style={{position: 'absolute', left: -CLIP_MARGIN * k, top: -CLIP_MARGIN * k, width: CLIP_CANVAS * k, height: CLIP_CANVAS * k}} />
        )}
      </div>
    </div>
  );
};
export const capRise = (f: number, at: number) => springAt(f, at, 190, 15);
export const capSquash = (f: number, at: number) => 0.1 * hits(f, [at], 5) * (f >= at ? 1 : 0);

// ---- small shared UI -------------------------------------------------------------------------------------------------------------------
export const shadowCard = '0 18px 40px rgba(8,30,100,0.20), 0 4px 10px rgba(8,30,100,0.10)';
/** A pop 0..1 with overshoot, for things that appear. */
export const pop = (f: number, at: number, stiff = 240, damp = 15) => Math.max(0, springAt(f, at, stiff, damp));
export const Pill: React.FC<{text: string; bg: string; fg: string; size?: number; icon?: React.ReactNode; pad?: number; weight?: number}> = ({text, bg, fg, size = 26, icon, pad = 16, weight = 700}) => (
  <div style={{display: 'inline-flex', alignItems: 'center', gap: size * 0.3, background: bg, color: fg, borderRadius: 999, padding: `${size * 0.28}px ${pad}px`, ...sfStyle(size, weight), whiteSpace: 'nowrap'}}>
    {icon}{text}
  </div>
);
export const Check: React.FC<{size: number; color?: string; stroke?: number; progress?: number}> = ({size, color = '#fff', stroke = 3, progress = 1}) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={stroke} strokeLinecap="round" strokeLinejoin="round">
    <path d="M5 12.5l4.5 4.5L19 7.5" pathLength={1} strokeDasharray={1} strokeDashoffset={1 - clamp01(progress)} />
  </svg>
);
