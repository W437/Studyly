// The app's own pieces, redrawn as live vector motion (no screenshots): the scanned page, the scanner's brackets, and the question cards.
import React from 'react';
import {clamp01, easeIn, easeOut, hash, lerp, pop, ramp, sfStyle, shadowCard, springAt, Check, F} from './kit';
import {COL} from './theme';

// ---- icons (simple, drawn here; the app uses SF Symbols) -----------------------------------------------------------------------------------
export const Icon: React.FC<{name: 'list' | 'cursor' | 'pencil' | 'speaker' | 'doc' | 'cards' | 'camera' | 'mic' | 'bolt' | 'scope'; size: number; color: string; stroke?: number}> = ({name, size, color, stroke = 2}) => {
  const p = {fill: 'none', stroke: color, strokeWidth: stroke, strokeLinecap: 'round' as const, strokeLinejoin: 'round' as const};
  return (
    <svg width={size} height={size} viewBox="0 0 24 24">
      {name === 'list' ? (<><path {...p} d="M9 6h11M9 12h11M9 18h11" /><circle cx="4.5" cy="6" r="1.2" fill={color} /><circle cx="4.5" cy="12" r="1.2" fill={color} /><circle cx="4.5" cy="18" r="1.2" fill={color} /></>) : null}
      {name === 'cursor' ? (<><path {...p} d="M5 18V6.5M3.5 6.5h3M3.5 18h3" /><path {...p} d="M10 17l3.2-9 3.2 9M11 14.2h4.4" /></>) : null}
      {name === 'pencil' ? (<><path {...p} d="M4 20l1-4L16.5 4.5a2.1 2.1 0 013 3L8 19z" /><path {...p} d="M14.5 6.5l3 3" /></>) : null}
      {name === 'speaker' ? (<><path {...p} d="M4 9.5h3.5L12 6v12l-4.5-3.5H4z" /><path {...p} d="M15.5 9a4 4 0 010 6M18 6.5a7.5 7.5 0 010 11" /></>) : null}
      {name === 'doc' ? (<><path {...p} d="M7 3.5h7l4 4v13H7z" /><path {...p} d="M14 3.5v4h4M9.5 12h6M9.5 15.5h6" /></>) : null}
      {name === 'cards' ? (<><rect {...p} x="3.5" y="7" width="13" height="10" rx="2" /><path {...p} d="M7 4.5h12a1.5 1.5 0 011.5 1.5v9" /></>) : null}
      {name === 'camera' ? (<><path {...p} d="M4 8.5h3l1.5-2.5h7L17 8.5h3v10H4z" /><circle {...p} cx="12" cy="13.2" r="3.2" /></>) : null}
      {name === 'mic' ? (<><rect {...p} x="9" y="3.5" width="6" height="11" rx="3" /><path {...p} d="M5.5 11.5a6.5 6.5 0 0013 0M12 18v3" /></>) : null}
      {name === 'bolt' ? <path {...p} d="M13 3L5.5 13.5H12L11 21l7.5-10.5H12z" /> : null}
      {name === 'scope' ? (<><circle {...p} cx="12" cy="12" r="7" /><path {...p} d="M12 2.5v4M12 17.5v4M2.5 12h4M17.5 12h4" /></>) : null}
    </svg>
  );
};

// ---- the scanned page ------------------------------------------------------------------------------------------------------------------
export const PAGE_W = 380;
export const PAGE_H = 510;
/** Y centres of the three lines the app would highlight (page-local px). */
export const PAGE_MARKS = [
  {y: 316, w: 250}, {y: 404, w: 292}, {y: 448, w: 214},
];
/** A textbook page drawn as greeked text with a diagram: title, a row of cell drawings, paragraphs. `marks` 0..1 each: how far each marker has swept. */
export const Paper: React.FC<{marks?: number[]; flash?: number; scan?: number}> = ({marks = [0, 0, 0], flash = 0, scan = -1}) => {
  const lines: React.ReactNode[] = [];
  let y = 232;
  for (let i = 0; i < 12; i++) {
    const gap = i === 4 || i === 8 ? 16 : 0;
    y += gap;
    const w = 312 - hash(4, i) * 70 - (i % 4 === 3 ? 120 : 0);
    const isMark = PAGE_MARKS.findIndex((m) => Math.abs(m.y - (y + 4)) < 12);
    lines.push(<rect key={i} x={34} y={y} width={w} height={9} rx={4.5} fill="#D3DBE8" />);
    y += 22;
    void isMark;
  }
  return (
    <div style={{position: 'relative', width: PAGE_W, height: PAGE_H, borderRadius: 18, background: '#FFFFFF', boxShadow: shadowCard, overflow: 'hidden'}}>
      <svg width={PAGE_W} height={PAGE_H} style={{position: 'absolute', left: 0, top: 0}}>
        <rect x={34} y={34} width={236} height={20} rx={10} fill={COL.ink} opacity={0.88} />
        <rect x={34} y={64} width={150} height={10} rx={5} fill="#A9B5C9" />
        {[0, 1, 2, 3].map((i) => {
          const cx = 74 + i * 78;
          return (
            <g key={i}>
              <circle cx={cx} cy={150} r={30} fill="#F4F7FB" stroke="#B7C3D6" strokeWidth={2.5} />
              <path d={`M${cx - 14} ${150 + (i % 2 ? 8 : -8)}q7 -10 14 0t14 0`} fill="none" stroke={i === 1 ? COL.rose : '#6E8FD6'} strokeWidth={3.5} strokeLinecap="round" />
              {i === 1 ? <path d={`M${cx - 18} 150h36`} stroke={COL.rose} strokeWidth={3.5} strokeLinecap="round" /> : <path d={`M${cx - 5} ${150 - 12}v24`} stroke="#6E8FD6" strokeWidth={3.5} strokeLinecap="round" />}
              <rect x={cx - 24} y={196} width={48} height={7} rx={3.5} fill="#D3DBE8" />
            </g>
          );
        })}
        {lines}
        {PAGE_MARKS.map((m, i) => (
          <rect key={i} x={26} y={m.y - 11} width={(m.w + 18) * clamp01(marks[i] ?? 0)} height={22} rx={7} fill={COL.sun} opacity={0.62} style={{mixBlendMode: 'multiply'}} />
        ))}
      </svg>
      {scan >= 0 && scan <= 1.02 ? (
        <>
          <div style={{position: 'absolute', left: 0, right: 0, top: scan * PAGE_H - 160, height: 160, background: 'linear-gradient(180deg, rgba(124,200,255,0), rgba(124,200,255,0.30))'}} />
          <div style={{position: 'absolute', left: -4, right: -4, top: scan * PAGE_H - 3, height: 6, borderRadius: 3, background: '#fff', boxShadow: '0 0 18px 4px rgba(124,200,255,0.95), 0 0 46px 12px rgba(124,200,255,0.55)'}} />
        </>
      ) : null}
      {flash > 0 ? <div style={{position: 'absolute', inset: 0, background: `rgba(255,255,255,${flash})`}} /> : null}
    </div>
  );
};

/** The scanner's focus brackets round a box; they fly in from outside (fly 0..1) and breathe once on the snap (flare). */
export const CornerBrackets: React.FC<{x: number; y: number; w: number; h: number; fly: number; flare?: number; color?: string; len?: number; stroke?: number; opacity?: number}> = ({
  x, y, w, h, fly, flare = 0, color = '#fff', len = 62, stroke = 9, opacity = 1,
}) => {
  const out = (1 - fly) * 130 + flare * 12;
  const L = len * (1 + flare * 0.25);
  const corners: {cx: number; cy: number; sx: number; sy: number}[] = [
    {cx: x - out, cy: y - out, sx: 1, sy: 1}, {cx: x + w + out, cy: y - out, sx: -1, sy: 1}, {cx: x + w + out, cy: y + h + out, sx: -1, sy: -1}, {cx: x - out, cy: y + h + out, sx: 1, sy: -1},
  ];
  return (
    <svg width={886} height={1920} style={{position: 'absolute', left: 0, top: 0, overflow: 'visible', opacity, pointerEvents: 'none'}}>
      {corners.map((c, i) => (
        <path key={i} d={`M${c.cx + c.sx * L} ${c.cy} L${c.cx} ${c.cy} L${c.cx} ${c.cy + c.sy * L}`} fill="none" stroke={color} strokeWidth={stroke} strokeLinecap="round" strokeLinejoin="round"
          style={{filter: `drop-shadow(0 0 ${8 + flare * 14}px rgba(124,200,255,0.95))`}} />
      ))}
    </svg>
  );
};

// ---- question cards --------------------------------------------------------------------------------------------------------------------
export const CARD_W = 720;
const Header: React.FC<{icon: React.ComponentProps<typeof Icon>['name']; label: string; size?: number}> = ({icon, label, size = 17}) => (
  <div style={{display: 'flex', alignItems: 'center', gap: 12, height: 44}}>
    <Icon name={icon} size={24} color={COL.ink2} stroke={2.2} />
    <div style={{...sfStyle(size, 650), color: COL.ink2, letterSpacing: 1.4, textTransform: 'uppercase', flex: 1, whiteSpace: 'nowrap'}}>{label}</div>
    <div style={{width: 42, height: 42, borderRadius: 21, background: COL.surface3, display: 'flex', alignItems: 'center', justifyContent: 'center'}}><Icon name="speaker" size={23} color={COL.ink2} /></div>
  </div>
);
export const SourceChip: React.FC<{text?: string; scale?: number}> = ({text = 'p. 87 · Bio 101', scale = 1}) => (
  <div style={{display: 'inline-flex', alignItems: 'center', gap: 10, background: COL.skySoft, color: COL.skyInk, borderRadius: 999, padding: '8px 18px 8px 14px', ...sfStyle(22 * scale, 650), whiteSpace: 'nowrap'}}>
    <Icon name="doc" size={24 * scale} color={COL.skyInk} stroke={2.2} />{text}
  </div>
);

/** The white card itself: floats with a shadow; children are the face. */
export const CardShell: React.FC<{w?: number; h: number; children?: React.ReactNode; style?: React.CSSProperties}> = ({w = CARD_W, h, children, style}) => (
  <div style={{width: w, height: h, borderRadius: 34, background: '#fff', boxShadow: '0 30px 70px rgba(8,30,100,0.32), 0 6px 16px rgba(8,30,100,0.14)', overflow: 'hidden', position: 'relative', ...style}}>{children}</div>
);

export const MC_H = 336;
/** Multiple choice, compact: the question and its four options. `t` 0..1: the right one is chosen (it turns mint, the rest dim). */
export const CardMC: React.FC<{t?: number}> = ({t = 0}) => {
  const sel = clamp01(t);
  const opts = ['Anaphase', 'Metaphase', 'Prophase', 'Telophase'];
  return (
    <div style={{padding: '22px 28px 0'}}>
      <Header icon="list" label="Multiple choice · Phases of mitosis" />
      <div style={{...sfStyle(33, 720), color: COL.ink, marginTop: 8, lineHeight: 1.16}}>In which phase do chromosomes line up at the equator of the cell?</div>
      <div style={{display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginTop: 16}}>
        {opts.map((o, i) => {
          const right = i === 1;
          const g = right ? sel : 0;
          const on = right && g > 0.45;
          return (
            <div key={o} style={{height: 54, borderRadius: 16, display: 'flex', alignItems: 'center', padding: '0 12px', gap: 11,
              background: right && g > 0.02 ? `rgb(${lerp(232, 34, g)},${lerp(238, 195, g)},${lerp(246, 142, g)})` : COL.surface3,
              boxShadow: `0 4px 0 ${on ? COL.mintEdge : COL.surfaceEdge}`, opacity: right ? 1 : 1 - sel * 0.5, transform: `translateY(${right ? sel * 2 : 0}px)`}}>
              <div style={{width: 30, height: 30, borderRadius: 15, background: on ? 'rgba(255,255,255,0.3)' : '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', ...sfStyle(18, 700), color: on ? '#fff' : COL.ink3}}>{'ABCD'[i]}</div>
              <div style={{...sfStyle(26, 650), color: on ? '#fff' : COL.ink2, flex: 1}}>{o}</div>
              {right ? <div style={{opacity: clamp01(g * 2 - 0.6), transform: `scale(${0.4 + 0.6 * clamp01(g)})`}}><Check size={26} color="#fff" stroke={3.6} progress={clamp01(g * 1.5 - 0.3)} /></div> : null}
            </div>
          );
        })}
      </div>
    </div>
  );
};

export const CLOZE_H = 262;
/** Fill in the blank, compact. `t` 0..1: the blank fills with its word. */
export const CardCloze: React.FC<{t?: number}> = ({t = 0}) => {
  const fill = clamp01(t);
  return (
    <div style={{padding: '22px 28px 0'}}>
      <Header icon="cursor" label="Fill in · Phases of mitosis" />
      <div style={{...sfStyle(35, 600), color: COL.ink, marginTop: 12, lineHeight: 1.4}}>
        During{' '}
        <span style={{display: 'inline-block', position: 'relative', width: 196, height: 46, verticalAlign: 'middle', transform: `scale(${1 + 0.08 * Math.sin(fill * Math.PI)})`}}>
          <span style={{position: 'absolute', inset: 0, borderRadius: 13, background: fill > 0.02 ? `rgba(124,200,255,${0.16 + 0.3 * fill})` : COL.surface3, boxShadow: fill > 0.02 ? 'none' : `inset 0 -3px 0 ${COL.surfaceEdge}`}} />
          <span style={{position: 'absolute', inset: 0, textAlign: 'center', lineHeight: '46px', color: COL.skyInk, opacity: clamp01(fill * 1.6 - 0.3), transform: `translateY(${(1 - fill) * 8}px)`}}>telophase</span>
        </span>
        , new nuclear envelopes form around each set of chromosomes.
      </div>
    </div>
  );
};

/** "In your own words", the card that becomes the next scene's. `k` 0..1 grows it from the compact teaser to the full answer card. */
export const OWN_H = 300;
export const CardOwnHead: React.FC<{k?: number}> = ({k = 0}) => (
  <div style={{padding: `22px 28px 0`}}>
    <Header icon="pencil" label="In your own words · Why mitosis matters" />
    <div style={{...sfStyle(lerp(33, 38, k), 720), color: COL.ink, marginTop: 8, lineHeight: 1.16}}>In your own words: why do cells divide by mitosis?</div>
  </div>
);

void pop; void ramp; void easeIn; void easeOut; void springAt; void F;
