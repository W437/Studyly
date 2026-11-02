// Renders chosen frames of a composition through ONE bundle and ONE browser, then tiles them with their frame numbers.
//   node tools/frames.mjs --frames 28,34,46 [--entry src/entries/preview.tsx] [--id Preview] [--scale 0.5] [--cols 4] [--out out/s/sheet.png] [--keep]
import path from 'node:path';
import fs from 'node:fs';
import {execFileSync} from 'node:child_process';
import {bundle} from '@remotion/bundler';
import {openBrowser, renderStill, selectComposition} from '@remotion/renderer';

const arg = (k, d) => { const i = process.argv.indexOf(`--${k}`); return i >= 0 ? process.argv[i + 1] : d; };
const frames = arg('frames', '0').split(',').map(Number);
const entry = arg('entry', 'src/entries/preview.tsx');
const id = arg('id', 'Preview');
const scale = Number(arg('scale', '0.5'));
const cols = Number(arg('cols', '4'));
const out = arg('out', 'out/s/sheet.png');
fs.mkdirSync(path.dirname(out), {recursive: true});
const serveUrl = await bundle({entryPoint: path.resolve(entry), onProgress: () => {}});
const browser = await openBrowser('chrome');
const composition = await selectComposition({serveUrl, id, puppeteerInstance: browser});
const files = [];
for (const frame of frames) {
  const file = path.join(path.dirname(out), `${path.basename(out, '.png')}-${String(frame).padStart(4, '0')}.png`);
  await renderStill({composition, serveUrl, output: file, frame, scale, puppeteerInstance: browser});
  files.push(file);
}
await browser.close({silent: true});
execFileSync('python3', ['-P', '-c', `
import sys
from PIL import Image, ImageDraw
files=sys.argv[3:]; cols=int(sys.argv[1]); out=sys.argv[2]
ims=[Image.open(f).convert("RGB") for f in files]
w,h=ims[0].size; rows=(len(ims)+cols-1)//cols
sheet=Image.new("RGB",(cols*(w+8),rows*(h+22)),(18,18,18)); d=ImageDraw.Draw(sheet)
for i,(f,im) in enumerate(zip(files,ims)):
    x=(i%cols)*(w+8); y=(i//cols)*(h+22)
    sheet.paste(im,(x,y+22)); d.text((x+6,y+5),"f"+str(int(f[-8:-4])),fill=(255,255,255))
sheet.save(out)
`, String(cols), out, ...files]);
if (!process.argv.includes('--keep')) for (const f of files) fs.unlinkSync(f);
console.log(out, `${frames.length} frames`);
