// A small but complete ad that shows the parts working together. Copy it as the start
// of a new ad (or run `npm run new-ad -- <N> <slug>` for a bare one).
//
// It plays whatever is in public/example/: `screen.mp4` (a constant-30-fps app clip from
// the gallery, ≥ 4 s), `music.mp3` (a 120 BPM track), `sfx-whoosh.mp3`, `sfx-pop.mp3`,
// `sfx-chime.mp3`. Anything missing falls back (a clearly marked placeholder screen,
// silence), so the example renders on a fresh copy.
//
// The beat grid: 120 BPM from frame 0 = a beat every 15 frames, a bar every 60.
//   f0    the hook, already on screen: the first frame is the thumbnail (headline set,
//         the phone mid-rise, smeared while it moves fast)
//   f60   bar 1: kick, flash, shards; "Real footage."
//   f120  bar 2: whip to shot B (directional blur, streaks, shake); the signature sweep
//         reveals the new look on bar 2's third beat
//   f180  bar 3: a hand-drawn loop and a tap point at the detail
//   f234  the phone whips up and out; f240 bar 4: the end card builds (badge settled ≈ f292),
//         then holds 1.75 s to the end
import React from 'react';
import {AbsoluteFill, Audio, Sequence, staticFile, useCurrentFrame} from 'remotion';
import {
  beatGrid, C, clamp01, ease, EndCard, Footage, font, glow, hasFile, hits, lerp, Phone, Pose, poseBlur, ramp,
  SCREEN, springAt, SweepReveal, useBrandFont, W, Words,
} from './parts';
import {Burst, EdgeGlow, Flash, Loop, shake, Smear, Streaks, Tap} from './fx';

export const exampleMeta = {durationInFrames: 345, width: 1080, height: 1920};

const G = beatGrid(120, 0);
const A = G.bars(1); // 60
const B = G.bars(2); // 120
const REVEAL = G.b(10); // 150
const DETAIL = G.bars(3); // 180
const OUT = G.bars(4) - 6; // 234
const END = G.bars(4); // 240

const CLIP = 'example/screen.mp4';
const REST = {x: W / 2, y: 1165, s: 0.5};

// ---- the screen: the real clip if there is one, else a placeholder that says so
const Placeholder: React.FC<{tint: number}> = ({tint}) => (
  <div style={{position: 'absolute', inset: 0, background: tint ? '#eef2ff' : '#f5f6f8', padding: '180px 70px'}}>
    <div style={{...font(96, {color: '#12151a'})}}>Placeholder</div>
    {[0, 1, 2, 3, 4].map((i) => (
      <div key={i} style={{marginTop: 60, height: 300, borderRadius: 48, background: i === 1 ? `linear-gradient(135deg, ${C.accent}, ${C.accentDeep})` : '#ffffff',
        boxShadow: '0 10px 30px rgba(0,0,0,0.08)'}} />
    ))}
    <div style={{position: 'absolute', left: 70, right: 70, bottom: 150, padding: 40, borderRadius: 32, background: '#12151a', color: '#fff',
      ...font(52, {letterSpacing: 0, lineHeight: 1.25})}}>Not the app. Drop a real clip at public/{CLIP}</div>
  </div>
);
const Screen: React.FC<{f: number; keys: [number, number][]; tint?: number}> = ({f, keys, tint = 0}) =>
  hasFile(CLIP) ? <Footage src={CLIP} keys={keys} f={f} /> : <Placeholder tint={tint} />;

// ---- poses: rise, rest with a sway, a kick on each landing, whips between shots
const sway = (f: number) => ({ry: 5 * Math.sin(f / 23), rx: 2 * Math.sin(f / 31 + 0.8)});
const kick = (f: number) => 1 + 0.03 * hits(f, [A, B + 6, DETAIL], 5);

const poseA = (f: number): Pose => {
  const rise = springAt(f, -5, 120, 14); // started before frame 0: the first frame already has the phone
  const out = Math.pow(clamp01((f - (B - 4)) / 8), 2.2); // gathers speed and leaves at full speed
  return {...REST, ...sway(f), y: lerp(2700, REST.y, rise), x: REST.x - 1500 * out, rz: -14 * out, s: REST.s * kick(f) * (1 - 0.06 * out),
    rx: (1 - clamp01(rise)) * -18 + sway(f).rx};
};
const poseB = (f: number): Pose => {
  const inn = springAt(f, B - 2, 230, 21); // a whip that lands clean
  const out = Math.pow(clamp01((f - OUT) / 10), 2.2);
  return {...REST, ...sway(f), x: lerp(W + 1500, REST.x, inn), y: REST.y - 2300 * out, rz: lerp(14, 0, clamp01(inn)),
    s: REST.s * kick(f) * (1 - 0.06 * out)};
};

// the rise is fast: draw it smeared (a see-through-safe motion blur)
const RisingPhone: React.FC = () => {
  const f = useCurrentFrame();
  return <Phone id="rise" pose={poseA(f)}><Screen f={f} keys={[[0, 0.2], [A, 0.2], [B, 2.4]]} /></Phone>;
};

export const AdExample: React.FC = () => {
  useBrandFont();
  const f = useCurrentFrame();
  const [sx, sy, sr] = shake(f, [{at: A, amp: 10}, {at: B + 6, amp: 16}, {at: DETAIL, amp: 8}]);
  const beat = G.pulse(f, 6);
  const halo = 0.8 + 0.2 * beat;
  // the new look: shot B desaturated until the sweep passes (a stand-in for a filter the app applies)
  const reveal = ramp(f, REVEAL, REVEAL + 24, (t) => t);
  const keysB: [number, number][] = [[B, 2.4], [OUT + 12, 4.4]];
  const loopP = ramp(f, DETAIL + 2, DETAIL + 18, ease);

  return (
    <AbsoluteFill style={{background: C.ground, overflow: 'hidden'}}>
      {/* the room: light pooled behind the phone, breathing on the beat */}
      <AbsoluteFill style={{background: `radial-gradient(110% 70% at 50% 60%, ${C.groundLit} 0%, ${C.ground} 70%)`}} />
      <div style={{position: 'absolute', left: -140, top: 560, width: 1360, height: 1300, borderRadius: '50%', opacity: halo * (1 - ramp(f, OUT, END + 10)),
        background: `radial-gradient(closest-side, ${glow(0.34)}, ${glow(0)})`}} />

      {/* the world shakes; captions and the end card don't */}
      <AbsoluteFill style={{transform: `translate(${sx}px, ${sy}px) rotate(${sr}deg)`}}>
        <Streaks f={f} at={B - 4} dir="left" />
        <Streaks f={f} at={OUT} dir="up" seed={2} />
        {f < 20 ? <Smear><RisingPhone /></Smear> : null}
        {f >= 20 && f < B + 8 ? (
          <Phone id="a" pose={poseA(f)} blur={poseBlur(poseA, f)}>
            <Screen f={f} keys={[[0, 0.2], [A, 0.2], [B, 2.4]]} />
          </Phone>
        ) : null}
        {f >= B - 3 && f < OUT + 14 ? (
          <Phone id="b" pose={poseB(f)} blur={poseBlur(poseB, f)} glowAmt={hits(f, [REVEAL + 24], 10) * 0.8}>
            <SweepReveal p={reveal} w={SCREEN.w} h={SCREEN.h}
              before={<div style={{position: 'absolute', inset: 0, filter: 'grayscale(1) brightness(0.92) contrast(0.85)'}}><Screen f={f} keys={keysB} /></div>}
              after={<Screen f={f} keys={keysB} tint={1} />} />
            <Loop cx={SCREEN.w / 2} cy={SCREEN.h * 0.52} rx={440} ry={250} seed={3} progress={loopP} opacity={1 - ramp(f, OUT - 12, OUT - 4)} />
            <Tap f={f} at={DETAIL + 26} x={SCREEN.w / 2} y={SCREEN.h * 0.52} />
          </Phone>
        ) : null}
        <Burst seed={A} x={W / 2} y={560} count={26} t={f - A} dir={-Math.PI / 2} spread={Math.PI * 1.2} gravity={0.5} />
        <Burst seed={DETAIL} x={W / 2} y={1180} count={20} t={f - (DETAIL + 26)} speed={[6, 16]} gravity={0.2} />
      </AbsoluteFill>

      <Words f={f} from={-18} step={5} to={A - 2} text="Your app, | *in motion.*" size={120} cy={330} />
      <Words f={f} from={A + 2} to={B - 4} text="Real *footage.*" cy={300} />
      <Words f={f} from={B + 4} to={DETAIL - 4} text="Cut on the *beat.*" cy={300} />
      <Words f={f} from={DETAIL + 2} to={OUT - 2} text="Every *detail.*" cy={300} />
      <EndCard f={f} at={END} />

      <Flash f={f} at={A} amount={0.22} />
      <Flash f={f} at={END} amount={0.3} decay={4} />
      <EdgeGlow f={f} at={[A, B + 6, REVEAL + 24]} />
      <AbsoluteFill style={{background: 'radial-gradient(120% 90% at 50% 50%, rgba(0,0,0,0) 60%, rgba(0,0,0,0.5) 100%)', pointerEvents: 'none'}} />

      {hasFile('example/music.mp3') ? <Audio src={staticFile('example/music.mp3')} volume={(fr) => 0.8 * (1 - ramp(fr, 322, 345))} /> : null}
      {SFX.filter(([, name]) => hasFile(`example/sfx-${name}.mp3`)).map(([at, name, vol], i) => (
        <Sequence key={i} from={at} layout="none"><Audio src={staticFile(`example/sfx-${name}.mp3`)} volume={vol} /></Sequence>
      ))}
    </AbsoluteFill>
  );
};

// [frame, sound, volume]: a whoosh starts ~4 frames before its whip so its peak lands on the cut.
const SFX: [number, string, number][] = [
  [A, 'pop', 0.6], [B - 6, 'whoosh', 0.35], [REVEAL, 'whoosh', 0.15], [DETAIL + 26, 'pop', 0.5], [OUT - 4, 'whoosh', 0.3], [END + 2, 'chime', 0.35],
];

