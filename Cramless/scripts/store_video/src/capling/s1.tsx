// Beat 1, "Snap pages into Questions": Cap snaps a page, the scanner sweeps it, the page docks and three kinds of question fly out of it.
import React from 'react';
import {Cap, capRise, capSquash, clamp01, easeIn, easeOut, hits, lerp, pop, ramp, Star4, springAt} from './kit';
import {CardCloze, CardMC, CardShell, CARD_W, CLOZE_H, CornerBrackets, MC_H, OWN_H, Paper, PAGE_H, PAGE_MARKS, PAGE_W} from './elements';
import {H, T, W} from './theme';

// where things rest (screen px, centre of each)
export const SLOT = {
  mc: {cx: W / 2, top: 500, h: MC_H},
  cloze: {cx: W / 2, top: 500 + MC_H + 22, h: CLOZE_H},
  own: {cx: W / 2, top: 500 + MC_H + CLOZE_H + 44, h: OWN_H},
};
const PAGE_BIG = {x: W / 2, y: 905, s: 1.15, r: -2.5};
export const PAGE_DOCK = {x: 215, y: 1665, s: 0.6, r: -8};

/** Sweep timing: the scanner line crosses the page between these frames. */
const SWEEP = [32, 60];
const markAt = (i: number) => lerp(SWEEP[0], SWEEP[1], PAGE_MARKS[i].y / PAGE_H);

export const pagePose = (f: number) => {
  const enter = springAt(f, -3, 200, 17);
  const dock = springAt(f, 62, 150, 15);
  const leave = ramp(f, T.s2 - 12, T.s2 + 8, easeIn);
  const x = lerp(1250, PAGE_BIG.x, enter);
  const bx = lerp(x, PAGE_DOCK.x, dock);
  const by = lerp(PAGE_BIG.y, PAGE_DOCK.y, dock);
  return {
    x: bx - leave * 600, y: by + leave * 500, s: lerp(PAGE_BIG.s, PAGE_DOCK.s, dock), r: lerp(18, PAGE_BIG.r, enter) + (PAGE_DOCK.r - PAGE_BIG.r) * dock - leave * 18,
  };
};

export const cardMove = (f: number, start: number, slot: {cx: number; top: number; h: number}, fromX: number, fromY: number, spin: number) => {
  const p = springAt(f, start, 205, 16.5);
  const cy = slot.top + slot.h / 2;
  const x = lerp(fromX, slot.cx, p);
  const y = lerp(fromY, cy, p);
  const prev = springAt(f - 1, start, 205, 16.5);
  const speed = Math.hypot((p - prev) * (slot.cx - fromX), (p - prev) * (cy - fromY));
  return {x, y, s: lerp(0.3, 1, p), r: (1 - p) * spin, o: clamp01((f - start) / 3), blur: Math.min(14, speed * 0.2), p};
};

export const S1: React.FC<{f: number}> = ({f}) => {
  const page = pagePose(f);
  const snap = 30;
  const marks = PAGE_MARKS.map((_, i) => ramp(f, markAt(i) - 2, markAt(i) + 7, easeOut));
  const flash = 0.85 * hits(f, [snap], 3.5) * (f >= snap ? 1 : 0);
  const scan = ramp(f, SWEEP[0], SWEEP[1], (t) => t);
  const bracketFly = ramp(f, 14, snap, easeOut);
  const bracketFlare = 0.9 * hits(f, [snap], 5) * (f >= snap ? 1 : 0);
  const bracketOut = 1 - ramp(f, 58, 66);
  // Cap: rises centre, moves right once the page docks, sinks as the beat ends
  const capDock = springAt(f, 64, 150, 15);
  const capLeave = ramp(f, T.s2 - 14, T.s2 + 4, easeIn);
  const capH = lerp(600, 480, capDock);

  const A = cardMove(f, 66, SLOT.mc, PAGE_DOCK.x, PAGE_DOCK.y - 40, -16);
  const B = cardMove(f, 73, SLOT.cloze, PAGE_DOCK.x, PAGE_DOCK.y - 40, 14);
  const mcT = springAt(f, 92, 200, 18);
  const clozeT = springAt(f, 100, 200, 16);
  const leaveA = ramp(f, T.s2 - 8, T.s2 + 10, easeIn);

  const cards: {k: string; m: ReturnType<typeof cardMove>; slot: typeof SLOT.mc; body: React.ReactNode; leave: number; dir: number}[] = [
    {k: 'mc', m: A, slot: SLOT.mc, body: <CardMC t={mcT} />, leave: leaveA, dir: -1},
    {k: 'cloze', m: B, slot: SLOT.cloze, body: <CardCloze t={clozeT} />, leave: ramp(f, T.s2 - 4, T.s2 + 14, easeIn), dir: 1},
  ];
  return (
    <>
      {/* the page, its brackets, flash and sweep */}
      {page.x > -400 ? (
        <div style={{position: 'absolute', left: page.x - PAGE_W / 2, top: page.y - PAGE_H / 2, width: PAGE_W, height: PAGE_H, transform: `rotate(${page.r}deg) scale(${page.s})`, transformOrigin: '50% 50%'}}>
          <Paper marks={marks} flash={flash} scan={f >= SWEEP[0] && f <= SWEEP[1] + 2 ? scan : -1} />
          <div style={{position: 'absolute', left: 0, top: 0, width: PAGE_W, height: PAGE_H, opacity: bracketOut}}>
            <CornerBrackets x={-26} y={-26} w={PAGE_W + 52} h={PAGE_H + 52} fly={bracketFly} flare={bracketFlare} stroke={9 / page.s} len={64 / page.s} />
          </div>
        </div>
      ) : null}
      {/* the sparkle burst on the snap */}
      {f >= snap && f < snap + 22 ? [0, 1, 2, 3, 4, 5].map((i) => {
        const a = (i / 6) * Math.PI * 2 + 0.4;
        const p = ramp(f, snap, snap + 20, easeOut);
        return <Star4 key={i} x={PAGE_BIG.x + Math.cos(a) * (250 + p * 150)} y={PAGE_BIG.y + Math.sin(a) * (320 + p * 120)} r={22 * (1 - p) + 4} color="#fff" opacity={1 - p} rot={p * 90} />;
      }) : null}
      <Cap pose="scan" cx={lerp(W / 2, 705, capDock)} bottom={1912 + capLeave * 520} height={capH} f={f} rise={capRise(f, -2)} squash={capSquash(f, snap)} clip={{start: 0, until: 65}} />
      {/* the three questions */}
      {cards.map(({k, m, slot, body, leave, dir}) => m.o > 0.01 && leave < 1 ? (
        <div key={k} style={{position: 'absolute', left: m.x - CARD_W / 2 + dir * leave * 1100, top: m.y - slot.h / 2 - leave * 160, opacity: m.o,
          transform: `rotate(${m.r + dir * leave * 14}deg) scale(${m.s})`, filter: m.blur > 0.8 ? `blur(${m.blur}px)` : undefined}}>
          <CardShell h={slot.h}>{body}</CardShell>
        </div>
      ) : null)}
      <div style={{display: 'none'}}>{pop(f, 0) + H}</div>
    </>
  );
};
