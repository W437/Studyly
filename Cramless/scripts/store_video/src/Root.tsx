// Every ad as a composition, for the Studio. `npm run new-ad -- <N> <slug>` adds lines at
// the two markers; keep them.
import React from 'react';
import {Composition} from 'remotion';
import {AdExample, exampleMeta} from './AdExample';
// @ads-imports

export const RemotionRoot: React.FC = () => (
  <>
    <Composition id="AdExample" component={AdExample} fps={30} {...exampleMeta} />
    {/* @ads-compositions */}
  </>
);
