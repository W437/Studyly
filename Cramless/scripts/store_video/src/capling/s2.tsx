// Beat 2, "Answer in your own Words": the compact question card grows into the answer card, an answer types itself and its key ideas light up,
// Check is pressed, and the "Nice!" panel rises with Cap. The three check marks then leave for the ring of the next beat.
import React from 'react';
import {Cap, capRise, capSquash, Check, clamp01, easeIn, F, hits, lerp, Pill, pop, ramp, rng, sfStyle, springAt, Star4, track} from './kit';
import {CardOwnHead, CardShell, SourceChip} from './elements';
import {cardMove, SLOT} from './s1';
import {COL, W} from './theme';

const ANSWER = 'To grow and repair tissue. Mitosis copies the chromosomes so each new cell is identical, with the same number of chromosomes.';
const PHRASES = ['grow and repair', 'identical', 'same number of chromosomes'].map((p) => ({text: p, from: ANSWER.indexOf(p), to: ANSWER.indexOf(p) + p.length}));
const IDEAS = ['Growth and repair', 'Genetically identical cells', 'Same number of chromosomes'];

// the typing: [frame, characters typed], piecewise linear so it speeds and slows like a person
const TYPE_KEYS: [number, number][] = [[146, 0], [157.5, PHRASES[0].to], [176, ANSWER.indexOf('Mitosis')], [195, PHRASES[1].to], [210, ANSWER.length]];
export const IDEA_DONE = [158, 195, 210];
export const typedChars = (f: number) => Math.floor(track(f, TYPE_KEYS, (t) => t));

export const FULL = {left: 63, top: 588, w: 760, h: 626};
export const COMPACT = {left: 83, top: SLOT.own.top, w: 720, h: SLOT.own.h};
const BTN = {top: FULL.top + FULL.h + 38, h: 90};
const CHECK_AT = 225; // Check is pressed (beat 15)
const PANEL_AT = 228; // the panel rises
export const LIFT_AT = 264; // the three check marks leave the card for the ring
/** Where the three idea marks sit inside the full card (for the hand-off to the ring). */
export const ideaPos = (i: number) => ({x: FULL.left + 28 + 17, y: FULL.top + 22 + 44 + 10 + 88 + 20 + 40 + 10 + 196 + 20 + 25 + i * 50});

const Typed: React.FC<{n: number; f: number}> = ({n, f}) => {
  const nodes: React.ReactNode[] = [];
  let i = 0;
  const caret = (
    <span key="caret" style={{display: 'inline-block', width: 0, height: 0, position: 'relative'}}>
      <span style={{position: 'absolute', left: 1, top: -30, width: 3, height: 36, borderRadius: 2, background: COL.tangerine, opacity: n >= ANSWER.length ? 0 : Math.floor(f / 15) % 2 === 0 || n > 0 ? 1 : 0}} />
    </span>
  );
  const seg = (from: number, to: number, hi: number) => {
    const chars: React.ReactNode[] = [];
    for (let j = from; j < to; j++) {
      if (j === n) chars.push(caret);
      chars.push(<span key={j} style={{opacity: j < n ? 1 : 0}}>{ANSWER[j]}</span>);
    }
    if (to === ANSWER.length && n >= to) chars.push(caret);
    if (hi < 0) return <span key={`s${from}`}>{chars}</span>;
    const done = n >= PHRASES[hi].to;
    const p = done ? springAt(f, IDEA_DONE[hi], 260, 12) : 0;
    return (
      <span key={`h${from}`} style={{position: 'relative', display: 'inline', borderRadius: 9, padding: '2px 4px', margin: '0 -4px',
        background: done ? `rgba(34,195,142,${0.34 * clamp01(p * 1.6)})` : 'transparent', boxDecorationBreak: 'clone', WebkitBoxDecorationBreak: 'clone',
        boxShadow: done ? `0 0 0 ${3 * Math.max(0, 1 - p)}px rgba(34,195,142,${0.5 * Math.max(0, 1 - p)})` : undefined}}>{chars}</span>
    );
  };
  for (let h = 0; h < PHRASES.length; h++) {
    nodes.push(seg(i, PHRASES[h].from, -1));
    nodes.push(seg(PHRASES[h].from, PHRASES[h].to, h));
    i = PHRASES[h].to;
  }
  nodes.push(seg(i, ANSWER.length, -1));
  return <>{nodes}</>;
};

export const OwnCard: React.FC<{f: number}> = ({f}) => {
  const enter = cardMove(f, 80, SLOT.own, 215, 1625, -10);
  const k = springAt(f, 108, 150, 17);
  const leave = ramp(f, 270, 292, easeIn);
  if (enter.o < 0.01 || leave >= 1) return null;
  const squeeze = springAt(f, PANEL_AT - 3, 170, 18);
  const top = lerp(COMPACT.top, FULL.top, k);
  const left = lerp(COMPACT.left, FULL.left, k);
  const w = lerp(COMPACT.w, FULL.w, k);
  const h = lerp(COMPACT.h, FULL.h, k);
  const settled = f < 110 ? enter : null;
  const typed = typedChars(f);
  const count = IDEA_DONE.filter((d) => f >= d).length;
  const placeholder = 1 - clamp01((f - 146) / 4);
  const chipBg = count === 3 ? COL.mintSoft : count > 0 ? COL.sunSoft : COL.surface3;
  const chipFg = count === 3 ? COL.mintInk : count > 0 ? COL.sunInk : COL.ink3;
  const chipPop = 1 + 0.12 * Math.max(0, ...IDEA_DONE.map((d) => hits(f, [d], 4) * (f >= d ? 1 : 0)));
  const x = settled ? settled.x - w / 2 : left;
  const y = settled ? settled.y - h / 2 : top;
  return (
    <div style={{position: 'absolute', left: x, top: y - leave * 900, width: w, height: h, transform: `translateY(${-14 * squeeze}px) rotate(${(settled ? settled.r : 0) - leave * 10}deg) scale(${(settled ? settled.s : 1) * (1 - 0.07 * squeeze)})`, transformOrigin: '50% 0%', opacity: enter.o,
      filter: settled && settled.blur > 0.8 ? `blur(${settled.blur}px)` : undefined}}>
      <CardShell w={w} h={h}>
        <CardOwnHead k={k} />
        <div style={{margin: `${lerp(0, 20, k)}px 28px 0`, height: 40 * k, opacity: clamp01(k * 1.6 - 0.4), display: 'flex', alignItems: 'center', justifyContent: 'space-between', overflow: 'hidden'}}>
          <div style={{...sfStyle(19, 650), color: COL.ink3, letterSpacing: 1.5, textTransform: 'uppercase'}}>Your answer</div>
          <div style={{transform: `scale(${chipPop})`, transformOrigin: '100% 50%'}}><Pill text={`${count} of 3 key ideas`} bg={chipBg} fg={chipFg} size={22} /></div>
        </div>
        <div style={{margin: `${lerp(14, 10, k)}px 28px 0`, height: lerp(80, 196, k), borderRadius: 20, background: COL.surface2, padding: '18px 22px', position: 'relative', overflow: 'hidden'}}>
          <div style={{...sfStyle(34, 500), color: COL.ink, lineHeight: 1.3}}>
            <Typed n={typed} f={f} />
          </div>
          <div style={{position: 'absolute', left: 22, top: 18, ...sfStyle(31, 500), color: COL.ink4, opacity: placeholder * (k > 0.5 ? 1 : 0.0)}}>Write it the way you'd say it</div>
        </div>
        <div style={{margin: `${lerp(0, 20, k)}px 28px 0`, height: 150 * k, opacity: clamp01(k * 1.6 - 0.6), overflow: 'hidden'}}>
          {IDEAS.map((label, i) => {
            const on = f >= IDEA_DONE[i] && f < LIFT_AT + i * 3;
            const p = on ? springAt(f, IDEA_DONE[i], 240, 13) : 0;
            return (
              <div key={label} style={{height: 50, display: 'flex', alignItems: 'center', gap: 16}}>
                <div style={{width: 34, height: 34, borderRadius: 17, boxSizing: 'border-box', border: `3px solid ${on ? COL.mint : COL.ink4}`, background: on ? COL.mint : 'transparent', display: 'flex', alignItems: 'center', justifyContent: 'center',
                  transform: `scale(${on ? 0.6 + 0.4 * Math.min(1.25, p) : 1})`}}>
                  {on ? <Check size={22} color="#fff" stroke={3.6} progress={clamp01(p * 1.4)} /> : null}
                </div>
                <div style={{...sfStyle(31, 600), color: on ? COL.ink : COL.ink3}}>{label}</div>
              </div>
            );
          })}
        </div>
      </CardShell>
    </div>
  );
};

/** The tangerine Check button under the card: pops in when the answer is complete, presses, and is covered by the panel. */
export const CheckButton: React.FC<{f: number}> = ({f}) => {
  const p = pop(f, 211, 230, 14);
  const press = ramp(f, CHECK_AT, CHECK_AT + 3) * (1 - ramp(f, CHECK_AT + 6, CHECK_AT + 10));
  const leave = ramp(f, CHECK_AT + 8, CHECK_AT + 18, easeIn);
  if (p <= 0.01 || leave >= 1) return null;
  const depth = 7 * (1 - press);
  return (
    <div style={{position: 'absolute', left: FULL.left, top: BTN.top + (1 - p) * 140 + press * 6 + leave * 60, width: FULL.w, height: BTN.h, opacity: clamp01(p * 2) * (1 - leave), transform: `scale(${(0.8 + 0.2 * Math.min(1.1, p)) * (1 - 0.1 * leave)})`}}>
      <div style={{position: 'absolute', inset: 0, borderRadius: 28, background: COL.tangerine, boxShadow: `0 ${depth}px 0 ${COL.tangerineEdge}, 0 24px 40px rgba(8,30,100,0.28)`,
        display: 'flex', alignItems: 'center', justifyContent: 'center', ...sfStyle(40, 720), color: COL.night}}>Check</div>
    </div>
  );
};

/** Little confetti: seeded pieces thrown up from a point, falling with gravity. */
export const Confetti: React.FC<{f: number; at: number; x: number; y: number; count?: number; seed?: number; spread?: number; power?: number}> = ({f, at, x, y, count = 30, seed = 2, spread = 1, power = 1}) => {
  const t = f - at;
  if (t < 0 || t > 70) return null;
  const rand = rng(seed);
  const cols = [COL.mint, COL.sun, COL.tangerine, COL.sky, '#fff', COL.rose];
  return (
    <>
      {Array.from({length: count}, (_, i) => {
        const a = -Math.PI / 2 + (rand() - 0.5) * 2.4 * spread;
        const v = (9 + rand() * 13) * power;
        const px = x + Math.cos(a) * v * t * 0.62;
        const py = y + Math.sin(a) * v * t * 0.62 + 0.5 * 0.55 * t * t;
        const o = 1 - ramp(f, at + 40, at + 70);
        const c = cols[i % cols.length];
        const r = rand() * 360 + t * (rand() - 0.5) * 24;
        const sz = 9 + rand() * 12;
        if (i % 4 === 0) return <Star4 key={i} x={px} y={py} r={sz * 0.9} color={c === '#fff' ? '#FFF6C8' : c} rot={r} opacity={o} glowAmt={0.4} />;
        return <div key={i} style={{position: 'absolute', left: px - sz / 2, top: py - sz * 0.3, width: sz, height: sz * 0.6, borderRadius: 3, background: c, opacity: o, transform: `rotate(${r}deg) scaleY(${Math.cos(t * 0.3 + i)})`}} />;
      })}
    </>
  );
};

export const PANEL_TOP = 1362;
/** The mint "Nice!" panel the app shows after a right answer. */
export const NicePanel: React.FC<{f: number}> = ({f}) => {
  const p = springAt(f, PANEL_AT, 175, 17);
  const leave = ramp(f, 272, 294, easeIn);
  if (p <= 0.003 || leave >= 1) return null;
  const top = lerp(1990, PANEL_TOP, p) + leave * 700;
  const word = pop(f, PANEL_AT + 5, 280, 13);
  const body = pop(f, PANEL_AT + 9, 240, 16);
  const chip = pop(f, PANEL_AT + 12, 240, 16);
  const btn = pop(f, PANEL_AT + 15, 240, 16);
  return (
    <>
      <Cap pose="nice" cx={690} bottom={top + 64} height={296} f={f} rise={1} dy={(1 - clamp01(p)) * 120} opacity={clamp01(p * 3)} clip={{start: 214}} />
      <div style={{position: 'absolute', left: 0, top, width: W, height: 640, borderRadius: '48px 48px 0 0', background: '#D8F5E8', boxShadow: '0 -18px 50px rgba(8,30,100,0.22)'}}>
        <div style={{position: 'absolute', left: 54, top: 52, ...({fontFamily: F.title, fontSize: 88, lineHeight: 1, color: COL.mintInk, letterSpacing: -2} as React.CSSProperties), transform: `scale(${0.4 + 0.6 * word}) rotate(${(1 - word) * -6}deg)`, transformOrigin: '0 100%', opacity: clamp01(word * 3)}}>Nice!</div>
        <div style={{position: 'absolute', left: 56, top: 168, ...sfStyle(34, 500), color: COL.ink, opacity: clamp01(body * 2), transform: `translateY(${(1 - body) * 20}px)`}}>Every key idea is there.</div>
        <div style={{position: 'absolute', left: 54, top: 232, opacity: clamp01(chip * 2), transform: `translateY(${(1 - chip) * 20}px)`}}><SourceChip text="p. 87 · Checked on your iPhone" scale={1.05} /></div>
        <div style={{position: 'absolute', left: 40, top: 330, width: W - 80, height: 96, opacity: clamp01(btn * 2), transform: `translateY(${(1 - btn) * 30}px)`}}>
          <div style={{position: 'absolute', inset: 0, borderRadius: 30, background: COL.mint, boxShadow: `0 8px 0 ${COL.mintEdge}`, display: 'flex', alignItems: 'center', justifyContent: 'center', ...sfStyle(40, 720), color: COL.night}}>Continue</div>
        </div>
      </div>
    </>
  );
};

export const S2: React.FC<{f: number}> = ({f}) => {
  // Cap, thinking, bottom-left while the answer types; he leaves as the panel arrives
  const rise = capRise(f, 128);
  const leave = ramp(f, PANEL_AT - 6, PANEL_AT + 8, easeIn);
  const enterWhip = 1;
  return (
    <>
      <Cap pose="think" cx={178} bottom={1912 + leave * 560} height={430} f={f} rise={rise * enterWhip} squash={capSquash(f, 132)} opacity={f < 124 ? 0 : 1} clip={{start: 128}} />
      <OwnCard f={f} />
      <CheckButton f={f} />
      <NicePanel f={f} />
      <Confetti f={f} at={PANEL_AT + 3} x={W / 2} y={PANEL_TOP + 40} count={36} seed={5} spread={1.25} power={1.05} />
    </>
  );
};
