// Capling's colours (Shared/BrandPalette.swift, light appearance), the three skies the preview passes through, and the timeline.
// Everything is in frames at 30 fps on an 886 x 1920 canvas (the App Store's portrait preview size).

export const FPS = 30;
export const W = 886;
export const H = 1920;

export const COL = {
  night: '#14213D', sky: '#7CC8FF', tangerine: '#FF7A1A', tangerineEdge: '#D45A04', sun: '#FFCF3F', sunEdge: '#D6A511',
  mint: '#22C38E', mintEdge: '#14966B', rose: '#FF5A78', roseEdge: '#D93659', capy: '#E0884A', white: '#FFFFFF',
  bg: '#F1F5FA', surface: '#FFFFFF', surface2: '#F4F7FB', surface3: '#E8EEF6', surfaceEdge: '#CBD5E2',
  ink: '#14213D', ink2: '#56627A', ink3: '#6B7489', ink4: '#8E98AB', hairline: 'rgba(20,33,61,0.09)',
  mintInk: '#0B7F5A', roseInk: '#C8213F', sunInk: '#8A6200', skyInk: '#1866AE', tangerineInk: '#B84A00',
  mintSoft: 'rgba(34,195,142,0.14)', roseSoft: 'rgba(255,90,120,0.12)', sunSoft: 'rgba(255,207,63,0.22)', skySoft: 'rgba(124,200,255,0.22)',
  tangerineSoft: 'rgba(255,122,26,0.12)',
  markHit: 'rgba(34,195,142,0.30)', markKey: 'rgba(255,207,63,0.55)',
};

export type RGB = [number, number, number];
const rgb = (c: RGB, a = 1) => `rgba(${Math.round(c[0])},${Math.round(c[1])},${Math.round(c[2])},${a})`;
export const css = rgb;
const mix = (a: RGB, b: RGB, t: number): RGB => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];

// A sky: the gradient stops (top to bottom), the two pixel fields (colour, alpha range 0..255 as in the listing art), the word's face and edge.
export type Sky = {
  stops: [number, RGB][];
  pixA: {c: RGB; lo: number; hi: number};
  pixB: {c: RGB; lo: number; hi: number};
  small: RGB; faceTop: RGB; faceBottom: RGB; edge: RGB; shadow: RGB; spark: RGB;
};

export const SKY_DAY: Sky = {
  stops: [[0, [22, 92, 220]], [0.55, [62, 148, 250]], [1, [138, 206, 255]]],
  pixA: {c: [255, 255, 255], lo: 8, hi: 26}, pixB: {c: [6, 30, 120], lo: 12, hi: 34},
  small: [255, 255, 255], faceTop: [255, 255, 255], faceBottom: [208, 236, 255], edge: [8, 58, 170], shadow: [4, 30, 116], spark: [255, 255, 255],
};
export const SKY_NIGHT: Sky = {
  stops: [[0, [5, 9, 22]], [0.55, [16, 27, 52]], [1, [34, 52, 98]]],
  pixA: {c: [255, 255, 255], lo: 4, hi: 14}, pixB: {c: [0, 0, 10], lo: 14, hi: 40},
  small: [255, 255, 255], faceTop: [255, 240, 190], faceBottom: [255, 196, 92], edge: [150, 60, 6], shadow: [1, 4, 14], spark: [255, 226, 140],
};
export const SKY_DAWN: Sky = {
  stops: [[0, [30, 98, 228]], [0.5, [78, 156, 252]], [1, [150, 210, 255]]],
  pixA: {c: [255, 255, 255], lo: 8, hi: 26}, pixB: {c: [14, 70, 190], lo: 10, hi: 28},
  small: [255, 255, 255], faceTop: [255, 255, 255], faceBottom: [222, 240, 255], edge: [10, 64, 176], shadow: [24, 54, 130], spark: [255, 255, 255],
};

/** Gradient stops sampled at a position, so two skies with different numbers of stops can be mixed. */
const sample = (stops: [number, RGB][], p: number): RGB => {
  if (p <= stops[0][0]) return stops[0][1];
  for (let i = 1; i < stops.length; i++) {
    if (p <= stops[i][0]) return mix(stops[i - 1][1], stops[i][1], (p - stops[i - 1][0]) / (stops[i][0] - stops[i - 1][0]));
  }
  return stops[stops.length - 1][1];
};
const POS = [0, 0.25, 0.5, 0.75, 1];
export const mixSky = (a: Sky, b: Sky, t: number): Sky => {
  if (t <= 0) return a;
  if (t >= 1) return b;
  const stops = POS.map((p) => [p, mix(sample(a.stops, p), sample(b.stops, p), t)] as [number, RGB]);
  const pf = (x: Sky['pixA'], y: Sky['pixA']) => ({c: mix(x.c, y.c, t), lo: x.lo + (y.lo - x.lo) * t, hi: x.hi + (y.hi - x.hi) * t});
  return {
    stops, pixA: pf(a.pixA, b.pixA), pixB: pf(a.pixB, b.pixB), small: mix(a.small, b.small, t), faceTop: mix(a.faceTop, b.faceTop, t),
    faceBottom: mix(a.faceBottom, b.faceBottom, t), edge: mix(a.edge, b.edge, t), shadow: mix(a.shadow, b.shadow, t), spark: mix(a.spark, b.spark, t),
  };
};
export const skyGradient = (s: Sky) => `linear-gradient(180deg, ${s.stops.map(([p, c]) => `${rgb(c)} ${p * 100}%`).join(', ')})`;

// ---- the timeline (120 BPM: a beat is 15 frames, a bar 60) -----------------------------------------------------------------------
export const BEAT = 15;
export const BAR = 60;
export const T = {
  s1: 0,       // Snap pages into Questions
  s2: 120,     // Answer in your own Words
  s3: 300,     // Know your Readiness
  s4: 420,     // Light up your Memory
  s5: 540,     // Ready on exam day
  hit: 660,    // the final hit: the lockup lands
  end: 750,
};
