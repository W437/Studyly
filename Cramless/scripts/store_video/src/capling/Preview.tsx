// The Capling App Store preview: five beats of motion built from the app's own pieces, on the sky the listing art uses.
import React from 'react';
import {AbsoluteFill, useCurrentFrame} from 'remotion';
import {easeOut, Ground, ramp, scatter, SmallLine, Sparkles, useFonts} from './kit';
import {shake} from '../fx';
import {Headline} from './headline';
import {Disc} from './disc';
import {S1} from './s1';
import {S2} from './s2';
import {S3} from './s3';
import {S4} from './s4';
import {S5} from './s5';
import {H, mixSky, SKY_DAWN, SKY_DAY, SKY_NIGHT, T, W} from './theme';

export const meta = {id: 'Preview', width: W, height: H, fps: 30, durationInFrames: T.end};

const ease = (t: number) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
/** The ground's sky over time: day, into night as the plate becomes the memory sky, into dawn as the stars let go. */
export const groundSky = (f: number) => {
  const toNight = ramp(f, 404, 436, ease);
  const toDawn = ramp(f, 538, 580, ease);
  return mixSky(mixSky(SKY_DAY, SKY_NIGHT, toNight), SKY_DAWN, toDawn);
};

/** The second small line under the giant "Ready". */
const SmallOn: React.FC<{f: number}> = ({f}) => {
  if (f < T.s5 + 30) return null;
  return <SmallLine text="on exam day." cy={573} sky={SKY_DAWN} f={f} at={T.s5 + 32} size={64} />;
};

export const Preview: React.FC = () => {
  const ready = useFonts();
  const f = useCurrentFrame();
  if (!ready) return null;
  const ground = groundSky(f);
  const box = {x0: 20, y0: 150, x1: W - 20, y1: 470};
  const sparks = [scatter(5, 14, box), scatter(9, 14, box), scatter(21, 14, box), scatter(33, 14, box)];
  const [dx, dy, dr] = shake(f, [{at: 30, amp: 4}, {at: 230, amp: 5}, {at: 284, amp: 6}, {at: 370, amp: 4}, {at: T.hit, amp: 10}]);
  const zoom = 1 + (Math.abs(dx) + Math.abs(dy)) * 0.0026;
  const sunA = ramp(f, 540, 600, easeOut);
  const sunY = 1980 - 780 * ramp(f, 540, 604, easeOut);
  return (
    <AbsoluteFill style={{background: '#1650d0'}}>
     <div style={{position: 'absolute', inset: 0, transform: `translate(${dx}px, ${dy}px) rotate(${dr}deg) scale(${zoom})`, transformOrigin: '50% 50%'}}>
      <Ground f={f} sky={ground} scroll={f * 0.5} sun={{y: sunY, a: sunA, rays: ramp(f, 576, 620)}} />
      <Sparkles f={f} sparks={sparks[0]} color="#fff" appear={18} out={T.s2 - 4} />
      <Sparkles f={f} sparks={sparks[1]} color="#fff" appear={T.s2 + 10} out={T.s3 - 6} />
      <Sparkles f={f} sparks={sparks[2]} color="#fff" appear={T.s3 + 10} out={T.s4 - 6} />
      <Sparkles f={f} sparks={sparks[3]} color="#FFE9A6" appear={T.s4 + 14} out={T.s5 - 6} />
      <Headline f={f} sky={SKY_DAY} small="Snap pages into" big="Questions" start={-5} kick={T.s2 - 12} seed={3} />
      <Headline f={f} sky={SKY_DAY} small="Answer in your own" big="Words" start={T.s2} kick={T.s3 - 12} seed={8} maxSize={290} fit={0.88} />
      <Headline f={f} sky={SKY_DAY} small="Know your" big="Readiness" start={T.s3 - 2} kick={T.s4 - 12} seed={12} fit={0.9} />
      <Headline f={f} sky={SKY_NIGHT} small="Light up your" big="Memory" start={T.s4 - 4} kick={T.s5 - 12} seed={15} fit={0.9} maxSize={280} />
      <Headline f={f} sky={SKY_DAWN} small="A little every day." big="Ready" start={T.s5 + 6} seed={21} maxSize={330} fit={0.8} hitAt={T.hit} />
      <SmallOn f={f} />
      <S1 f={f} />
      <S2 f={f} />
      <S3 f={f} />
      <Disc f={f} />
      <S4 f={f} />
      <S5 f={f} />
     </div>
    </AbsoluteFill>
  );
};
