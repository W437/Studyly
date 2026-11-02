// Beat 4, "Light up your Memory": the readiness plate becomes the memory sky. Every card is a star that dims as you start to forget it;
// a review lights it again. Cap watches through his telescope, and the counter ticks down the dim stars.
import React from 'react';
import {Cap, capRise, capSquash, clamp01, easeIn, easeOut, F, hash, lerp, pop, ramp, rng, sfStyle, springAt, Star4G} from './kit';
import {COL, T, W} from './theme';

export const SKY_R = 372;
export const SKY_CY = 1010;
export const MORPH = [404, 434] as const; // the plate grows into the sky

type Pt = [number, number];
// Constellations in disc units (-1..1). `lit`: bright from the start; `dim`: dimming, relit at the given frame (0 = stays dim); the rest are not yet lit.
type Star = {p: Pt; state: 'lit' | 'dim' | 'off'; relit?: number; r?: number};
type Cluster = {stars: Star[]; edges: [number, number][]};
const CLUSTERS: Cluster[] = [
  {stars: [{p: [-0.46, -0.46], state: 'lit', r: 11}, {p: [-0.3, -0.33], state: 'lit', r: 13}, {p: [-0.16, -0.5], state: 'dim'}, {p: [-0.1, -0.24], state: 'lit', r: 10}, {p: [-0.38, -0.12], state: 'dim'}],
    edges: [[0, 1], [1, 2], [1, 3], [1, 4]]},
  {stars: [{p: [0.2, -0.56], state: 'lit', r: 10}, {p: [0.38, -0.4], state: 'lit', r: 14}, {p: [0.3, -0.2], state: 'dim'}, {p: [0.55, -0.22], state: 'lit', r: 9}, {p: [0.1, -0.36], state: 'off'}],
    edges: [[0, 1], [1, 2], [1, 3], [0, 4]]},
  // the one a review relights, one star at a time on the beat
  {stars: [{p: [-0.08, 0.0], state: 'dim', relit: 480, r: 14}, {p: [0.14, 0.1], state: 'dim', relit: 487.5, r: 12}, {p: [0.02, 0.28], state: 'dim', relit: 495, r: 13}, {p: [-0.22, 0.2], state: 'dim', relit: 502.5, r: 11}, {p: [0.3, -0.04], state: 'dim', relit: 510, r: 12}],
    edges: [[0, 1], [1, 2], [2, 3], [3, 0], [1, 4]]},
  {stars: [{p: [-0.56, 0.22], state: 'lit', r: 9}, {p: [-0.4, 0.38], state: 'dim'}, {p: [-0.52, 0.52], state: 'lit', r: 11}, {p: [-0.22, 0.54], state: 'off'}],
    edges: [[0, 1], [1, 2], [1, 3]]},
  {stars: [{p: [0.44, 0.22], state: 'lit', r: 12}, {p: [0.52, 0.4], state: 'off'}, {p: [0.34, 0.52], state: 'dim'}, {p: [0.18, 0.44], state: 'lit', r: 9}, {p: [0.62, 0.1], state: 'dim'}],
    edges: [[0, 1], [1, 2], [2, 3], [0, 4]]},
];
export const DIM_START = 17;
/** Every star that is lit by the end (lit from the start, or relit), with its size, for the stars that rise into the dawn. */
export const CLUSTERS_LIT = CLUSTERS.flatMap((c) => c.stars.filter((st) => st.state === 'lit' || st.relit).map((st) => ({p: st.p, r: st.r ?? 9})));
const RELIGHT = CLUSTERS[2].stars.map((s) => s.relit ?? 0);

const FIELD = Array.from({length: 110}, (_, i) => ({a: hash(3, i) * Math.PI * 2, d: Math.sqrt(hash(4, i)) * 0.92, r: 1 + hash(5, i) * 2, ph: hash(6, i) * 6.28}));

/** What sits inside the disc once it has become the sky. `k` scales it with the disc while it grows. */
export const SkyContent: React.FC<{f: number; opacity?: number; k?: number}> = ({f, opacity = 1, k = 1}) => {
  const R = SKY_R;
  const pt = (p: Pt): Pt => [R + p[0] * R * 1.05, R + p[1] * R * 1.05 - 6];
  const lines: React.ReactNode[] = [];
  const stars: React.ReactNode[] = [];
  const fx: React.ReactNode[] = [];
  const reveal = ramp(f, 414, 440, easeOut);
  const rising = 1 - ramp(f, 534, 546);
  CLUSTERS.forEach((cl, ci) => {
    cl.edges.forEach(([a, b], ei) => {
      const A = cl.stars[a], B = cl.stars[b];
      const lit = (s: Star) => s.state === 'lit' || (s.relit && f >= s.relit);
      const both = lit(A) && lit(B);
      const [x1, y1] = pt(A.p), [x2, y2] = pt(B.p);
      const own = clamp01(reveal * 1.4 - ((ci + ei) % 5) * 0.08);
      lines.push(<line key={`${ci}-${ei}`} x1={x1} y1={y1} x2={lerp(x1, x2, own)} y2={lerp(y1, y2, own)} stroke={both ? 'rgba(255,238,180,0.85)' : 'rgba(160,190,255,0.42)'} strokeWidth={both ? 3.2 : 2.2} strokeLinecap="round" />);
    });
    cl.stars.forEach((s, si) => {
      const [x, y] = pt(s.p);
      const appear = clamp01(reveal * 1.5 - ((ci * 3 + si) % 7) * 0.07);
      const re = s.relit ?? 0;
      const t = re ? clamp01((f - re) / 12) : s.state === 'lit' ? 1 : 0;
      const sp = re && f >= re ? springAt(f, re, 260, 11) : 0;
      const base = s.r ?? 9;
      if (s.state === 'off' && !re) {
        stars.push(<circle key={`${ci}-${si}`} cx={x} cy={y} r={3.2 * appear} fill="rgba(255,255,255,0.22)" />);
        return;
      }
      const lit = s.state === 'lit' || (re && f >= re);
      const rr = (lit ? base * (re ? 0.7 + 0.3 * Math.min(1.7, sp) : 1) * (1 + 0.1 * Math.sin(f * 0.1 + ci * 2 + si)) : base * 0.62) * 1.45;
      const col = lit ? `rgb(255,${Math.round(lerp(236, 244, t))},${Math.round(lerp(190, 200, t))})` : 'rgba(150,185,255,0.55)';
      stars.push(<Star4G key={`${ci}-${si}`} x={x} y={y} r={rr * appear} color={col} rot={lit ? Math.sin(f * 0.05 + si) * 8 : 0} opacity={(lit ? 1 : 0.75) * (lit ? rising : 1)} glowAmt={lit ? 1 : 0} />);
      if (re && f >= re && f < re + 26) {
        const p = ramp(f, re, re + 22, easeOut);
        fx.push(<circle key={`ring-${ci}-${si}`} cx={x} cy={y} r={14 + p * 74} fill="none" stroke="rgba(255,238,180,1)" strokeWidth={4 * (1 - p)} opacity={1 - p} />);
        fx.push(<Star4G key={`fl-${ci}-${si}`} x={x} y={y} r={46 * (1 - p) + 8} color="#FFF6D0" rot={45} opacity={0.9 * (1 - p)} inner={0.12} glowAmt={0.3} />);
        const rand = rng(40 + si);
        for (let j = 0; j < 5; j++) {
          const a = rand() * Math.PI * 2;
          fx.push(<Star4G key={`sp-${ci}-${si}-${j}`} x={x + Math.cos(a) * (30 + p * 80)} y={y + Math.sin(a) * (30 + p * 80)} r={6 * (1 - p) + 1.5} color="#FFF0B8" opacity={1 - p} rot={p * 200} glowAmt={0.4} />);
        }
      }
    });
  });
  const relit = RELIGHT.filter((r) => f >= r + 4).length;
  const dim = DIM_START - relit;
  const tick = Math.max(0, ...RELIGHT.map((r) => (f >= r + 4 ? Math.exp(-(f - r - 4) / 5) : 0)));
  return (
    <div style={{position: 'absolute', left: 0, top: 0, width: R * 2, height: R * 2, opacity, transform: `scale(${k})`, transformOrigin: '50% 50%'}}>
      <div style={{position: 'absolute', inset: 0, borderRadius: '50%', overflow: 'hidden', background: 'radial-gradient(circle at 50% 46%, #2A4478 0%, #1A2A52 45%, #0E1832 100%)', boxShadow: 'inset 0 0 0 2px rgba(160,195,255,0.28), inset 0 0 90px rgba(70,110,220,0.35)'}}>
        {FIELD.map((d, i) => (
          <div key={i} style={{position: 'absolute', left: R + Math.cos(d.a) * d.d * R - d.r, top: R + Math.sin(d.a) * d.d * R - d.r, width: d.r * 2, height: d.r * 2, borderRadius: '50%', background: '#fff',
            opacity: reveal * (0.3 + 0.3 * Math.sin(f * 0.06 + d.ph))}} />
        ))}
        <svg width={R * 2} height={R * 2} style={{position: 'absolute', left: 0, top: 0, overflow: 'visible'}}>
          <circle cx={R} cy={R} r={R - 24} fill="none" stroke="rgba(255,255,255,0.18)" strokeWidth={2.5} strokeDasharray="2 10" strokeLinecap="round" />
          {lines}{stars}{fx}
        </svg>
        <div style={{position: 'absolute', left: 0, right: 0, bottom: 56, textAlign: 'center', ...sfStyle(19, 650), letterSpacing: 5, color: 'rgba(255,255,255,0.5)', textTransform: 'uppercase', opacity: reveal}}>Bio 101 midterm</div>
      </div>
      <div style={{position: 'absolute', left: R - 215, top: 30, width: 430, height: 56, borderRadius: 28, background: 'rgba(255,255,255,0.13)', display: 'flex', alignItems: 'center', justifyContent: 'center', opacity: reveal,
        ...sfStyle(25, 650), color: '#fff', whiteSpace: 'nowrap', gap: 10}}>
        <span>63 stars</span><span style={{opacity: 0.5}}>·</span>
        <span style={{display: 'inline-block', transform: `scale(${1 + 0.18 * tick})`, color: tick > 0.1 ? '#FFE9A6' : '#fff', fontFamily: F.sf}}>{dim} dim</span><span style={{opacity: 0.5}}>·</span><span>11 not yet lit</span>
      </div>
    </div>
  );
};

/** Where a star sits on screen (the disc is centred at W/2, SKY_CY). */
export const screenOf = (p: Pt): Pt => [W / 2 + p[0] * SKY_R * 1.05, SKY_CY + p[1] * SKY_R * 1.05 - 6];

/** Cap with his telescope under the disc; a soft beam from the lens to the star being lit while the review runs. */
export const S4: React.FC<{f: number}> = ({f}) => {
  const rise = capRise(f, 440);
  const leave = ramp(f, 524, 544, easeIn);
  const stars = CLUSTERS[2].stars;
  const idx = Math.max(0, RELIGHT.findIndex((r) => f < r + 8));
  const prev = Math.max(0, idx - 1);
  const swing = ramp(f, RELIGHT[prev] + 2, RELIGHT[idx] - 6, (t) => t * t * (3 - 2 * t));
  const a = screenOf(stars[prev].p), b = screenOf(stars[idx].p);
  const target = f < RELIGHT[0] ? b : [lerp(a[0], b[0], swing), lerp(a[1], b[1], swing)];
  const pulse = Math.max(0, ...RELIGHT.map((r) => (f >= r - 6 ? Math.exp(-(Math.abs(f - r)) / 6) : 0)));
  const beam = ramp(f, 466, 476) * (1 - ramp(f, 512, 526)) * (0.35 + 0.65 * pulse) * 0.8;
  const lens = {x: 586, y: 1426};
  return (
    <>
      {beam > 0.01 ? (
        <svg width={W} height={1920} style={{position: 'absolute', left: 0, top: 0, mixBlendMode: 'screen', opacity: beam, filter: 'blur(3px)', pointerEvents: 'none'}}>
          <defs><linearGradient id="beam" gradientUnits="userSpaceOnUse" x1={lens.x} y1={lens.y} x2={target[0]} y2={target[1]}><stop offset="0" stopColor="#FFE9A6" stopOpacity={0.75} /><stop offset="1" stopColor="#FFD97A" stopOpacity={0.06} /></linearGradient></defs>
          <polygon points={`${lens.x - 7},${lens.y + 5} ${lens.x + 7},${lens.y - 5} ${target[0] + 34},${target[1] - 14} ${target[0] - 34},${target[1] + 14}`} fill="url(#beam)" />
        </svg>
      ) : null}
      <Cap pose="stargaze" cx={400} bottom={1914 + leave * 560} height={500} f={f} rise={rise} squash={capSquash(f, 446)} clip={{start: 440}} />
      <div style={{display: 'none'}}>{T.s4 + W + pop(f, 0)}</div>
    </>
  );
};
