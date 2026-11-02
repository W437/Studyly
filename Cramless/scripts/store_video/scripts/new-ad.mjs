#!/usr/bin/env node
// Scaffolds ad N before an agent starts on it, so agents working in parallel each own
// their own files and never touch shared ones:
//   npm run new-ad -- <N> <slug> [--size 1080x1920] [--seconds 20]
// Makes src/Ad<N>.tsx (a bare stub exporting ad<N>Meta), src/entries/ad<N>.tsx,
// public/v<N>/, sources/v<N>/, a line in src/Root.tsx and the render:<N> / preview:<N>
// scripts. Existing files are left alone.
import fs from 'node:fs';
import path from 'node:path';

const args = process.argv.slice(2);
const opt = (name, dflt) => {
  const i = args.indexOf(name);
  if (i < 0) return dflt;
  const v = args[i + 1];
  args.splice(i, 2);
  return v;
};
const size = opt('--size', '1080x1920');
const seconds = Number(opt('--seconds', '20'));
const [n, slug = 'ad'] = args;
if (!n || !/^\d+$/.test(n)) {
  console.error('usage: npm run new-ad -- <N> <slug> [--size 1080x1920] [--seconds 20]');
  process.exit(1);
}
const [w, h] = size.split('x').map(Number);
const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const at = (...p) => path.join(root, ...p);
const writeOnce = (file, text) => {
  if (fs.existsSync(file)) return console.log(`kept ${path.relative(root, file)}`);
  fs.mkdirSync(path.dirname(file), {recursive: true});
  fs.writeFileSync(file, text);
  console.log(`made ${path.relative(root, file)}`);
};

writeOnce(at('src', `Ad${n}.tsx`), `// Ad ${n}, "${slug}". Beat grid, landmarks and honest notes go here as you build it.
import React from 'react';
import {AbsoluteFill, useCurrentFrame} from 'remotion';
import {beatGrid, C, useBrandFont, Words} from './parts';

export const ad${n}Meta = {durationInFrames: ${Math.round(seconds * 30)}, width: ${w}, height: ${h}};

const pub = (p: string) => \`v${n}/\${p}\`; // this ad's assets live in public/v${n}/
const G = beatGrid(120, 0); // replace with the analysed tempo and first beat of this ad's track

export const Ad${n}: React.FC = () => {
  useBrandFont();
  const f = useCurrentFrame();
  return (
    <AbsoluteFill style={{background: C.ground}}>
      <Words f={f} from={4} to={G.bars(2)} text="Ad ${n}: *${slug}*" />
    </AbsoluteFill>
  );
};
`);

writeOnce(at('src', 'entries', `ad${n}.tsx`), `// Renders ad ${n} on its own, so work on another ad can't break this one's bundle.
import React from 'react';
import {Composition, registerRoot} from 'remotion';
import {Ad${n}, ad${n}Meta} from '../Ad${n}';

registerRoot(() => <Composition id="Ad${n}" component={Ad${n}} fps={30} {...ad${n}Meta} />);
`);

for (const d of [at('public', `v${n}`), at('sources', `v${n}`), at('out', `v${n}`)]) fs.mkdirSync(d, {recursive: true});

const rootFile = at('src', 'Root.tsx');
let rootSrc = fs.readFileSync(rootFile, 'utf8');
if (!rootSrc.includes(`from './Ad${n}'`)) {
  rootSrc = rootSrc
    .replace('// @ads-imports', `import {Ad${n}, ad${n}Meta} from './Ad${n}';\n// @ads-imports`)
    .replace('{/* @ads-compositions */}', `<Composition id="Ad${n}" component={Ad${n}} fps={30} {...ad${n}Meta} />\n    {/* @ads-compositions */}`);
  fs.writeFileSync(rootFile, rootSrc);
  console.log('added to src/Root.tsx');
}

const pkgFile = at('package.json');
const pkg = JSON.parse(fs.readFileSync(pkgFile, 'utf8'));
const app = pkg.config?.appSlug ?? 'App';
pkg.scripts[`render:${n}`] = `scripts/one-at-a-time.sh remotion render src/entries/ad${n}.tsx Ad${n} renders/${app}-ad-${n}-${slug}.mp4 --codec=h264 --crf=16 --audio-bitrate=256k`;
pkg.scripts[`preview:${n}`] = `scripts/one-at-a-time.sh remotion render src/entries/ad${n}.tsx Ad${n} out/v${n}/preview.mp4 --scale=0.4 --crf=30`;
fs.writeFileSync(pkgFile, JSON.stringify(pkg, null, 2) + '\n');
console.log(`scripts render:${n}, preview:${n}`);
