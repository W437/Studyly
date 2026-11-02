// Renders the example on its own. Each ad gets one of these (npm run new-ad makes it):
// an agent's broken half-edit of another ad can never break this bundle.
import React from 'react';
import {Composition, registerRoot} from 'remotion';
import {AdExample, exampleMeta} from '../AdExample';

registerRoot(() => <Composition id="AdExample" component={AdExample} fps={30} {...exampleMeta} />);
