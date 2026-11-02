// Renders the Capling preview on its own: npm run still:preview / render:preview.
import React from 'react';
import {Composition, registerRoot} from 'remotion';
import {meta, Preview} from '../capling/Preview';

registerRoot(() => <Composition id={meta.id} component={Preview} fps={meta.fps} width={meta.width} height={meta.height} durationInFrames={meta.durationInFrames} />);
