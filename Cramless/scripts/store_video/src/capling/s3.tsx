// Beat 3, "Know your Readiness": the three check marks fly out of the answer card and become a readiness ring that fills to 53% and climbs to 91%,
// as the path to 90% draws itself and ends on the same 91% (a projection, labelled so, never a promise). The numbers are the app's own for the demo
// world's Bio 101 Midterm with its clock pinned (CRAMLESS_NOW=2026-11-06T14:00:00-05:00): "Today 53%", "Exam day 91%", the goal reached by Nov 29.
import React from 'react';
import {Cap, capRise, capSquash, Check, clamp01, easeIn, easeOut, F, hits, lerp, Pill, pop, ramp, rng, sfStyle, springAt, Star4} from './kit';
import {Icon} from './elements';
import {IDEA_DONE, ideaPos, LIFT_AT} from './s2';
import {COL, T, W} from './theme';

export const PLATE = {cx: W / 2, cy: 830, r: 284};
export const BORN_AT = 285;
const RING = {r: 214, stroke: 46};
const BORN = BORN_AT; // the check marks arrive and the plate pops
/** Where the ring starts, and where it stops and the path ends on exam day: the same numbers on the ring, the chart and its labels. */
export const START_VALUE = 0.53;
export const END_VALUE = 0.91;
const GOAL = 0.9;
// The path card's curve. y300 is START_VALUE and the goal line (y138) is GOAL, so END_VALUE ends just above that line.
const END_Y = 300 - ((END_VALUE - START_VALUE) / (GOAL - START_VALUE)) * (300 - 138);
const CURVE = `M30 300 C 150 296, 230 284, 330 250 S 520 ${END_Y + 46}, 700 ${END_Y}`;
type Pt2 = [number, number];
const SEGS: Pt2[][] = [
  [[30, 300], [150, 296], [230, 284], [330, 250]],
  [[330, 250], [430, 216], [520, END_Y + 46], [700, END_Y]], // the S command's first control is the mirror of the one before it
];
const bez = (p: Pt2[], t: number): Pt2 => {
  const u = 1 - t;
  return [u * u * u * p[0][0] + 3 * u * u * t * p[1][0] + 3 * u * t * t * p[2][0] + t * t * t * p[3][0],
    u * u * u * p[0][1] + 3 * u * u * t * p[1][1] + 3 * u * t * t * p[2][1] + t * t * t * p[3][1]];
};
/** [share of the curve's length, share of its climb] along the curve, so the ring can read the height of the line's drawing head. */
const PROFILE: Pt2[] = (() => {
  const pts: Pt2[] = [];
  let len = 0;
  let prev: Pt2 | null = null;
  for (const seg of SEGS) {
    for (let i = 0; i <= 120; i++) {
      const q = bez(seg, i / 120);
      if (prev) len += Math.hypot(q[0] - prev[0], q[1] - prev[1]);
      pts.push([len, (300 - q[1]) / (300 - END_Y)]);
      prev = q;
    }
  }
  return pts.map(([l, h]) => [l / len, h] as Pt2);
})();
const pathHeight = (s: number) => {
  const x = clamp01(s);
  let lo = 0, hi = PROFILE.length - 1;
  while (hi - lo > 1) {
    const mid = (lo + hi) >> 1;
    if (PROFILE[mid][0] < x) lo = mid; else hi = mid;
  }
  const [x0, h0] = PROFILE[lo], [x1, h1] = PROFILE[hi];
  return x1 > x0 ? lerp(h0, h1, (x - x0) / (x1 - x0)) : h1;
};
/** How much of the path is drawn (0 to 1): the line draws between f360 and f390. */
export const PATH_DRAW_AT = 360;
export const pathDraw = (f: number) => ramp(f, PATH_DRAW_AT, 390, (t) => 1 - Math.pow(1 - t, 3));
const ease = (t: number) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);

/** The ring's value over time: fills to START_VALUE (the chart's "Today"), holds, then climbs with the path being drawn: at every moment it reads the
 *  height of the line's drawing head, so it ends on the number the path ends on and the two never disagree. */
export const ringValue = (f: number) => {
  if (f < BORN + 4) return 0;
  if (f < 330) return START_VALUE * easeOut(clamp01((f - BORN - 4) / (330 - BORN - 4)));
  if (f < PATH_DRAW_AT) return START_VALUE;
  return lerp(START_VALUE, END_VALUE, pathHeight(pathDraw(f)));
};
/** Readiness colour: rose below 50, sun to 79, mint from 80 (the app's rule), blended over a few points so the change isn't a jump. */
const hex = (h: string) => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];
const readinessColour = (v: number) => {
  const a = hex(COL.rose), b = hex(COL.sun), c = hex(COL.mint);
  const s1 = clamp01((v - 0.485) / 0.03), s2 = clamp01((v - 0.795) / 0.02);
  const m = (x: number[], y: number[], t: number) => x.map((q, i) => Math.round(lerp(q, y[i], t)));
  const col = s2 > 0 ? m(b, c, s2) : m(a, b, s1);
  return `rgb(${col.join(',')})`;
};

/** The three check marks lifting out of the card and flying to where the ring will be. */
const IdeaFlight: React.FC<{f: number}> = ({f}) => {
  const out: React.ReactNode[] = [];
  for (let i = 0; i < 3; i++) {
    const start = LIFT_AT + i * 3;
    const end = BORN - 2 + i * 1.5;
    if (f < start - 1 || f > end + 1) continue;
    const t = ramp(f, start, end, (x) => x * x * (3 - 2 * x));
    const from = ideaPos(i);
    const to = {x: PLATE.cx + (i - 1) * 4, y: PLATE.cy};
    // an arc: out to the left first, then in
    const bend = Math.sin(t * Math.PI) * (i === 1 ? 170 : i === 0 ? -140 : 120);
    const x = lerp(from.x, to.x, t) + bend;
    const y = lerp(from.y, to.y, t) - Math.sin(t * Math.PI) * 90;
    const s = lerp(1.25, 1.9, Math.sin(t * Math.PI)) * (1 - 0.35 * t);
    const trail = [1, 2, 3].map((k) => ({k, t: clamp01(t - k * 0.05)}));
    out.push(
      <React.Fragment key={i}>
        {trail.map(({k, t: tt}) => {
          const b2 = Math.sin(tt * Math.PI) * (i === 1 ? 170 : i === 0 ? -140 : 120);
          return <div key={k} style={{position: 'absolute', left: lerp(from.x, to.x, tt) + b2 - 17 * s, top: lerp(from.y, to.y, tt) - Math.sin(tt * Math.PI) * 90 - 17 * s, width: 34 * s, height: 34 * s, borderRadius: '50%', background: COL.mint, opacity: 0.22 / k}} />;
        })}
        <div style={{position: 'absolute', left: x - 17 * s, top: y - 17 * s, width: 34 * s, height: 34 * s, borderRadius: '50%', background: COL.mint, boxShadow: '0 6px 18px rgba(8,30,100,0.3), 0 0 26px rgba(34,195,142,0.75)', display: 'flex', alignItems: 'center', justifyContent: 'center'}}>
          <Check size={22 * s} color="#fff" stroke={3.6} />
        </div>
      </React.Fragment>,
    );
  }
  return <>{out}</>;
};

/** The ring, the number and the label, drawn in a box of 2 x PLATE.r; the disc (disc.tsx) is the plate behind it. */
export const RingContent: React.FC<{f: number; opacity?: number}> = ({f, opacity = 1}) => {
  const v = ringValue(f);
  const C = 2 * Math.PI * RING.r;
  const col = readinessColour(v);
  const pct = Math.round(v * 100);
  const angle = v * Math.PI * 2 - Math.PI / 2;
  const hx = PLATE.r + Math.cos(angle) * RING.r;
  const hy = PLATE.r + Math.sin(angle) * RING.r;
  const moving = v > 0.01 && v < END_VALUE - 0.002 && !(f >= 330 && f < PATH_DRAW_AT);
  const num = clamp01((f - BORN - 3) / 6);
  const bump = 1 + 0.05 * hits(f, [375], 6) * (f >= 375 ? 1 : 0);
  return (
    <div style={{position: 'absolute', left: 0, top: 0, width: PLATE.r * 2, height: PLATE.r * 2, opacity, transform: `scale(${bump})`}}>
      <svg width={PLATE.r * 2} height={PLATE.r * 2} style={{position: 'absolute', left: 0, top: 0, overflow: 'visible'}}>
        <circle cx={PLATE.r} cy={PLATE.r} r={RING.r} fill="none" stroke="#EDF1F7" strokeWidth={RING.stroke} />
        <circle cx={PLATE.r} cy={PLATE.r} r={RING.r} fill="none" stroke={col} strokeWidth={RING.stroke} strokeLinecap="round" strokeDasharray={`${Math.max(0.001, v * C)} ${C}`} transform={`rotate(-90 ${PLATE.r} ${PLATE.r})`}
          style={{filter: `drop-shadow(0 0 ${6 + 10 * (moving ? 1 : 0)}px ${col})`}} />
      </svg>
      {moving ? <Star4 x={hx} y={hy} r={16} color="#fff" opacity={0.95} rot={f * 6} glowAmt={0.9} /> : null}
      <div style={{position: 'absolute', left: 0, right: 0, top: PLATE.r - 118, textAlign: 'center', fontFamily: F.rounded, fontWeight: 800, fontVariantNumeric: 'tabular-nums', color: COL.ink, lineHeight: 1, opacity: num}}>
        <span style={{fontSize: 176, letterSpacing: -4}}>{pct}</span><span style={{fontSize: 74, marginLeft: 4, fontWeight: 700, verticalAlign: 'top', position: 'relative', top: 30}}>%</span>
      </div>
      <div style={{position: 'absolute', left: 0, right: 0, top: PLATE.r + 76, textAlign: 'center', ...sfStyle(46, 500), color: COL.ink2, opacity: num}}>ready</div>
    </div>
  );
};

/** The path card: a title, the exam flag, a goal line and the climb to it, drawn on. */
const PATH = {left: 63, top: 1176, w: 760, h: 418};
const PathCard: React.FC<{f: number}> = ({f}) => {
  const p = springAt(f, 345, 170, 17);
  const leave = ramp(f, T.s4 - 14, T.s4 + 6, easeIn);
  if (p <= 0.003) return null;
  const draw = pathDraw(f);
  const dot = pop(f, 390, 260, 12);
  const label = pop(f, 394, 240, 15);
  const tail = ramp(f, 390, 402);
  return (
    <div style={{position: 'absolute', left: PATH.left, top: PATH.top + (1 - Math.min(1.08, p)) * 600 + leave * 900, width: PATH.w, height: PATH.h, borderRadius: 34, background: '#fff', boxShadow: '0 30px 70px rgba(8,30,100,0.32), 0 6px 16px rgba(8,30,100,0.14)', overflow: 'hidden', opacity: clamp01(p * 2)}}>
      <div style={{position: 'absolute', left: 30, top: 24, ...sfStyle(35, 720), color: COL.ink}}>Your path to 90%</div>
      <div style={{position: 'absolute', right: 26, top: 22}}><Pill text="Nov 29" bg={COL.mintSoft} fg={COL.mintInk} size={23} icon={<Icon name="scope" size={22} color={COL.mintInk} stroke={2.4} />} /></div>
      <svg width={PATH.w} height={PATH.h} style={{position: 'absolute', left: 0, top: 0, overflow: 'visible'}}>
        <line x1={30} y1={130 + 8} x2={PATH.w - 30} y2={130 + 8} stroke={COL.mint} strokeWidth={3} strokeDasharray="3 10" strokeLinecap="round" opacity={clamp01(p * 2)} />
        <text x={30} y={130 - 8} style={{...sfStyle(21, 650)}} fill={COL.mintInk}>90% goal</text>
        <defs>
          <linearGradient id="pathfill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor={COL.tangerine} stopOpacity={0.28} /><stop offset="1" stopColor={COL.tangerine} stopOpacity={0} /></linearGradient>
          <clipPath id="pathclip"><rect x={0} y={0} width={30 + 670 * draw} height={PATH.h} /></clipPath>
        </defs>
        <path d={`${CURVE} L700 340 L30 340 Z`} fill="url(#pathfill)" clipPath="url(#pathclip)" />
        <path d={CURVE} fill="none" stroke={COL.tangerine} strokeWidth={9} strokeLinecap="round" pathLength={1} strokeDasharray={1} strokeDashoffset={1 - draw} style={{filter: 'drop-shadow(0 4px 6px rgba(255,122,26,0.35))'}} />
        <circle cx={30} cy={300} r={10} fill="#fff" stroke={COL.tangerine} strokeWidth={5} />
        <circle cx={700} cy={END_Y} r={16 * dot} fill={COL.tangerine} opacity={dot > 0 ? 1 : 0} />
        <circle cx={700} cy={END_Y} r={16 + 22 * tail} fill="none" stroke={COL.tangerine} strokeWidth={4} opacity={0.5 * (1 - tail) * (dot > 0 ? 1 : 0)} />
      </svg>
      <div style={{position: 'absolute', left: 30, top: 318, ...sfStyle(23, 600), color: COL.ink3}}>Today {Math.round(START_VALUE * 100)}%</div>
      <div style={{position: 'absolute', right: 30, top: 318, ...sfStyle(23, 700), color: COL.ink, opacity: clamp01(label * 2)}}>Exam day {Math.round(END_VALUE * 100)}%</div>
      <div style={{position: 'absolute', left: 30, top: 366, ...sfStyle(21, 500), color: COL.ink3}}>Projected, if you follow the plan</div>
    </div>
  );
};

export const S3: React.FC<{f: number}> = ({f}) => {
  const rise = capRise(f, 346);
  const leave = ramp(f, T.s4 - 16, T.s4 + 2, easeIn);
  const burst = f >= 375 && f < 405;
  const rand = rng(14);
  return (
    <>
      <IdeaFlight f={f} />
      {burst ? Array.from({length: 9}, (_, i) => {
        const a = (i / 9) * Math.PI * 2 + rand();
        const p = ramp(f, 375, 399, easeOut);
        const r0 = 300 + rand() * 60;
        return <Star4 key={i} x={PLATE.cx + Math.cos(a) * (r0 + p * 90)} y={PLATE.cy + Math.sin(a) * (r0 + p * 90)} r={(10 + rand() * 12) * (1 - p) + 3} color="#fff" opacity={1 - p} rot={p * 120} />;
      }) : null}
      <PathCard f={f} />
      <Cap pose="point" cx={700} bottom={1912 + leave * 500} height={316} f={f} rise={rise} squash={capSquash(f, 350)} clip={{start: 346}} />
      <div style={{display: 'none'}}>{IDEA_DONE.length + T.s3}</div>
    </>
  );
};
