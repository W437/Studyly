// The Studio's entry: every ad in one place (npm run studio). Renders use the per-ad
// entries in src/entries/, so one ad's half-written file can't break another's bundle.
import {registerRoot} from 'remotion';
import {RemotionRoot} from './Root';

registerRoot(RemotionRoot);
