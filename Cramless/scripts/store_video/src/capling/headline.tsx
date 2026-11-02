// The headline of a beat: a small line and a giant toy-sign word. Letters drop in on the beat and are kicked off the top when the next beat starts.
import React from 'react';
import {dropIn, fitSize, kickOut, SmallLine, Word3D} from './kit';
import {Sky, W} from './theme';

export const Headline: React.FC<{f: number; sky: Sky; small: string; big: string; start: number; kick?: number; seed?: number; maxSize?: number; smallY?: number; bigY?: number; fit?: number; hitAt?: number}> = ({
  f, sky, small, big, start, kick = 1e9, seed = 3, maxSize = 270, smallY = 190, bigY = 365, fit = 0.95, hitAt = 1e9,
}) => {
  if (f < start - 2 || f > kick + 40) return null;
  const size = fitSize(big, W * fit, maxSize);
  return (
    <>
      <SmallLine text={small} cy={smallY} sky={sky} f={f} at={start + 8} out={kick - 2} />
      <Word3D text={big} size={size} cx={W / 2} cy={bigY} sky={sky} seed={seed} letter={(i) => {
        const m = f >= kick ? kickOut(f, kick, i) : dropIn(f, start + 2, i);
        const t = f - hitAt - i * 1.2;
        return t >= 0 ? {...m, y: (m.y ?? 0) - 16 * Math.exp(-t / 5) * Math.abs(Math.cos(t * 0.55))} : m;
      }} />
    </>
  );
};
