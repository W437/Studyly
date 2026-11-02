// Beat 5, "Ready on exam day": the stars rise into a dawn, Cap celebrates, and the lockup builds on the music's last hit: the app icon, the
// word "capling", and a star that lands where the i's dot goes (the wordmark's own idea: a memory kept lit).
import React from 'react';
import {Cap, capRise, clamp01, clipEnd, ClipPlay, easeIn, easeOut, F, hits, lerp, pop, ramp, springAt, Star4} from './kit';
import {Confetti} from './s2';
import {CLUSTERS_LIT, screenOf} from './s4';
import {Img, staticFile} from 'remotion';
import {COL, T, W} from './theme';

let canvas: HTMLCanvasElement | null = null;
const measure = (text: string, font: string, size: number) => {
  if (!canvas) canvas = document.createElement('canvas');
  const ctx = canvas.getContext('2d')!;
  ctx.font = `${size}px ${font}`;
  return ctx.measureText(text).width;
};

export const LOCK = {size: 150, icon: 150, gap: 34, cy: 1672};
// Cap's own celebrate clip (5.04 s): he floats up and lands at f618 while the wordmark is built, stands and watches it spell, then leaps on the
// last hit (f660, the star landing) because the clip's second jump starts 116 edit frames in. After the clip (f694) the code's beat hop takes over.
const CAP_CLIP: ClipPlay = {start: 544, until: 114};
const WM = ['c', 'a', 'p', 'l', 'ı', 'n', 'g'];

/** Where the i's dot goes, and the lockup's left edge, from measured letter widths. */
export const lockLayout = () => {
  const spacing = -LOCK.size * 0.02;
  const widths = WM.map((ch) => measure(ch, "'BricoDisplay'", LOCK.size) + spacing);
  const wm = widths.reduce((a, b) => a + b, 0);
  const total = LOCK.icon + LOCK.gap + wm;
  const left = (W - total) / 2;
  const wmLeft = left + LOCK.icon + LOCK.gap;
  const xs = widths.map((_, i) => wmLeft + widths.slice(0, i).reduce((a, b) => a + b, 0));
  return {left, wmLeft, widths, xs, iX: xs[4] + widths[4] / 2, iY: LOCK.cy - LOCK.size * 0.42};
};

/** The stars of the sky let go and drift up into the light. */
const RisingStars: React.FC<{f: number}> = ({f}) => (
  <>
    {CLUSTERS_LIT.map((s, i) => {
      const start = 534 + (i % 9) * 1.8;
      const t = ramp(f, start, start + 46, (x) => x * x);
      if (f < start || t >= 1) return null;
      const [x, y] = screenOf(s.p);
      return <Star4 key={i} x={x + Math.sin(i * 1.7) * 60 * t} y={y - t * (520 + (i % 5) * 80)} r={s.r * 1.45 * (1 + 0.5 * t)} color="#FFEFB8" opacity={1 - Math.pow(t, 3)} rot={t * 160} glowAmt={1} />;
    })}
  </>
);

export const S5: React.FC<{f: number}> = ({f}) => {
  const L = lockLayout();
  const iconP = pop(f, 628, 220, 13);
  const land = T.hit;
  const flight = ramp(f, 628, land, (x) => x * x * (3 - 2 * x));
  const star0 = {x: 800, y: 700};
  const ctrl = {x: 880, y: 1180};
  const sx = (1 - flight) * (1 - flight) * star0.x + 2 * (1 - flight) * flight * ctrl.x + flight * flight * L.iX;
  const sy = (1 - flight) * (1 - flight) * star0.y + 2 * (1 - flight) * flight * ctrl.y + flight * flight * L.iY;
  const landed = f >= land;
  const hit = hits(f, [land], 6) * (landed ? 1 : 0);
  const wmHit = 1 + 0.05 * hits(f, [land], 5) * (landed ? 1 : 0);
  const clipDone = clipEnd('celebrate', CAP_CLIP);
  const hop = Math.pow(Math.sin(Math.PI * ((f / 15) % 1)), 2) * 16 * clamp01((f - clipDone) / 12);
  const capIn = capRise(f, CAP_CLIP.start);
  return (
    <>
      <RisingStars f={f} />
      {/* thrown from behind him, so nothing lands on his face (the clip has its own confetti too) */}
      <Confetti f={f} at={582} x={W / 2} y={1050} count={44} seed={11} spread={1.5} power={1.15} />
      <Cap pose="celebrate" cx={W / 2} bottom={1452} height={760} f={f} rise={capIn} dy={-hop} opacity={f < CAP_CLIP.start - 2 ? 0 : 1} idle={0.6} clip={CAP_CLIP} />
      <Confetti f={f} at={land} x={W / 2} y={LOCK.cy - 20} count={48} seed={19} spread={1.7} power={1.5} />
      {/* the lockup: icon, then the wordmark letter by letter */}
      <div style={{position: 'absolute', left: L.left, top: LOCK.cy - LOCK.icon / 2, width: LOCK.icon, height: LOCK.icon, borderRadius: LOCK.icon * 0.2237, overflow: 'hidden', opacity: clamp01(iconP * 3),
        transform: `scale(${Math.max(0, iconP) * wmHit}) rotate(${(1 - iconP) * -14}deg)`, boxShadow: '0 22px 48px rgba(10,30,100,0.35), 0 0 60px rgba(255,214,120,0.35)'}}>
        <Img src={staticFile('art/appicon.png')} style={{width: LOCK.icon, height: LOCK.icon}} />
      </div>
      {WM.map((ch, i) => {
        const p = pop(f, 636 + i * 2.2, 260, 13);
        if (p <= 0.01) return null;
        const wmW = L.xs[WM.length - 1] + L.widths[WM.length - 1] - L.wmLeft;
        const band = lerp(-160, wmW + 160, ramp(f, land + 30, land + 56, (x) => x * x * (3 - 2 * x)));
        const ox = L.xs[i] - L.wmLeft;
        const type: React.CSSProperties = {fontFamily: F.display, fontSize: LOCK.size, lineHeight: 1, letterSpacing: -LOCK.size * 0.02, whiteSpace: 'pre'};
        return (
          <div key={i} style={{position: 'absolute', left: L.xs[i], top: LOCK.cy - LOCK.size * 0.62, opacity: clamp01(p * 3), transform: `translateY(${(1 - p) * 50}px) scale(${(0.5 + 0.5 * p) * wmHit})`, transformOrigin: '50% 80%'}}>
            <div style={{...type, color: '#fff', textShadow: '0 8px 26px rgba(10,40,120,0.45)'}}>{ch}</div>
            {f >= land + 30 && f < land + 58 ? (
              <div style={{...type, position: 'absolute', left: 0, top: 0, color: 'transparent', WebkitBackgroundClip: 'text', backgroundClip: 'text',
                backgroundImage: `linear-gradient(100deg, rgba(255,200,60,0) ${band - ox - 70}px, rgba(255,196,50,1) ${band - ox}px, rgba(255,200,60,0) ${band - ox + 70}px)`}}>{ch}</div>
            ) : null}
          </div>
        );
      })}
      {/* the star comes down from the sky and becomes the dot of the i */}
      {f >= 626 && f < land ? [3, 2, 1].map((k) => {
        const fk = Math.max(0, flight - k * 0.035);
        const x = (1 - fk) * (1 - fk) * star0.x + 2 * (1 - fk) * fk * ctrl.x + fk * fk * L.iX;
        const y = (1 - fk) * (1 - fk) * star0.y + 2 * (1 - fk) * fk * ctrl.y + fk * fk * L.iY;
        return <Star4 key={k} x={x} y={y} r={20 - k * 3} color="#FFE9A6" opacity={0.35 / k * clamp01((f - 626) / 4)} glowAmt={0.4} />;
      }) : null}
      {f >= 626 ? (
        <Star4 x={landed ? L.iX : sx} y={landed ? L.iY : sy} r={landed ? lerp(30, 27, clamp01((f - land) / 10)) * (1 + 0.55 * hit) : lerp(16, 30, flight)} color="#FFD45E" rot={landed ? Math.sin(f * 0.07) * 6 : flight * 300} glowAmt={1.2 + hit * 1.5} />
      ) : null}
      {landed && f < land + 28 ? (
        <>
          <div style={{position: 'absolute', left: L.iX - 200, top: L.iY - 200, width: 400, height: 400, borderRadius: '50%', border: `${10 * (1 - ramp(f, land, land + 24))}px solid rgba(255,244,200,${0.9 * (1 - ramp(f, land, land + 24))})`,
            transform: `scale(${0.1 + 0.9 * ramp(f, land, land + 24, easeOut)})`}} />
          {Array.from({length: 10}, (_, i) => {
            const a = (i / 10) * Math.PI * 2 + 0.3;
            const p = ramp(f, land, land + 26, easeOut);
            return <Star4 key={i} x={L.iX + Math.cos(a) * (50 + p * 190)} y={L.iY + Math.sin(a) * (50 + p * 190)} r={(14 - (i % 3) * 3) * (1 - p) + 2} color={i % 2 ? '#FFF3C4' : '#fff'} opacity={1 - p} rot={p * 180} glowAmt={0.6} />;
          })}
        </>
      ) : null}
      <div style={{display: 'none'}}>{COL.ink}</div>
    </>
  );
};
