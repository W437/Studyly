// The one circle that is a plate for the readiness ring, then grows into the memory sky.
import React from 'react';
import {clamp01, easeIn, hits, lerp, ramp, springAt} from './kit';
import {BORN_AT, PLATE, RingContent} from './s3';
import {MORPH, SKY_CY, SKY_R, SkyContent} from './s4';
import {T, W} from './theme';

const ease = (t: number) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);

export const Disc: React.FC<{f: number}> = ({f}) => {
  const born = springAt(f, BORN_AT, 190, 13);
  if (born <= 0.003) return null;
  const m = ramp(f, MORPH[0], MORPH[1], ease);
  const leave = ramp(f, 532, 560, easeIn);
  if (leave >= 1) return null;
  const r = lerp(PLATE.r, SKY_R, m);
  const cy = lerp(PLATE.cy, SKY_CY, m) - (f < MORPH[0] ? ramp(f, T.s4 - 16, T.s4 + 4, easeIn) * 0 : 0);
  const flash = hits(f, [BORN_AT], 4) * (f >= BORN_AT ? 1 : 0);
  const ringOut = 1 - ramp(f, MORPH[0] - 2, MORPH[0] + 10);
  const skyIn = ramp(f, MORPH[0] + 8, MORPH[0] + 20);
  const lift = leave * 160;
  const iris = r * 1.02 * ramp(f, MORPH[0] + 4, MORPH[0] + 26, (t) => 1 - Math.pow(1 - t, 3));
  return (
    <div style={{position: 'absolute', left: W / 2 - r, top: cy - r - lift, width: r * 2, height: r * 2, transform: `scale(${Math.max(0, born) * (1 - 0.1 * leave)})`, opacity: 1 - leave}}>
      <div style={{position: 'absolute', inset: 0, borderRadius: '50%', background: '#fff', overflow: 'hidden', boxShadow: `0 ${34 - 10 * m}px ${80 - 20 * m}px rgba(8,18,50,${0.34 + 0.2 * m}), 0 6px 18px rgba(8,30,100,0.16), 0 0 ${90 * m}px rgba(110,150,255,${0.3 * m})`}}>
        <div style={{position: 'absolute', left: r - iris, top: r - iris, width: iris * 2, height: iris * 2, borderRadius: '50%', background: '#1A2A52'}} />
      </div>
      {ringOut > 0.01 ? (
        <div style={{position: 'absolute', left: r - PLATE.r, top: r - PLATE.r, width: PLATE.r * 2, height: PLATE.r * 2}}><RingContent f={f} opacity={ringOut} /></div>
      ) : null}
      {skyIn > 0.01 ? (
        <div style={{position: 'absolute', left: r - SKY_R, top: r - SKY_R, width: SKY_R * 2, height: SKY_R * 2}}><SkyContent f={f} opacity={skyIn} k={r / SKY_R} /></div>
      ) : null}
      {flash > 0.02 ? <div style={{position: 'absolute', inset: -30, borderRadius: '50%', border: `${14 * flash}px solid rgba(255,255,255,${0.9 * flash})`, transform: `scale(${1 + (1 - flash) * 0.5})`}} /> : null}
    </div>
  );
};
