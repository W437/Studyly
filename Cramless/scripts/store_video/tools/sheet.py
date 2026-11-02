"""Tiles frames rendered by `tools/frames.mjs --keep` (out/<dir>/<name>-NNNN.png) into one labelled sheet.
   python3 tools/sheet.py out/cap/all out/cap/s5a.png 548,560,575 [--cols 4] [--w 360]"""
import sys
from PIL import Image, ImageDraw

prefix, out, frames = sys.argv[1], sys.argv[2], [int(x) for x in sys.argv[3].split(',')]
cols = int(sys.argv[sys.argv.index('--cols') + 1]) if '--cols' in sys.argv else 4
tw = int(sys.argv[sys.argv.index('--w') + 1]) if '--w' in sys.argv else 360
ims = []
for f in frames:
    im = Image.open(f'{prefix}-{f:04d}.png').convert('RGB')
    ims.append(im.resize((tw, round(im.height * tw / im.width)), Image.LANCZOS))
th = ims[0].height
rows = (len(ims) + cols - 1) // cols
sheet = Image.new('RGB', (cols * (tw + 6), rows * (th + 20)), (18, 18, 18))
d = ImageDraw.Draw(sheet)
for i, (f, im) in enumerate(zip(frames, ims)):
    x, y = (i % cols) * (tw + 6), (i // cols) * (th + 20)
    sheet.paste(im, (x, y + 20))
    d.text((x + 6, y + 4), f'f{f}  ({f / 30:.2f}s)', fill=(255, 255, 255))
sheet.save(out, quality=90)
print(out)
