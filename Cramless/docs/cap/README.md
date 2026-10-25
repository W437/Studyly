# Cap: the character sheet and his clips

`cap-character-sheet.png` is Cap, written down: the turnaround, ten faces, close-ups of his teeth, tongue, eyes, paws and
hat, the palette (sampled from the art) and what he always and never does. `panels/` holds its 19 pictures, which are what the
video model is shown. `picks.json` says which panels define him as a character (front, three-quarter, side, a laugh) and
which are extra references. Every clip in the app was made from these.

## The rules

Always:
- He wears the navy mortarboard with its gold tassel and the cream headphones, in every frame (the mortarboard stays on his
  head even when he cheers).
- His default face has closed, content arc eyes and a small closed smile.
- Open eyes are large, round and dark brown with one small white highlight, and **no white ring around them**. (A video
  model draws googly eyes unless told his eyes stay closed.)
- A laugh or a yawn shows exactly two small cream upper front teeth and a soft pink tongue.
- Flat vector shapes, soft simple shading, a few darker fur strokes, no outline.
- Calm, warm and kind, even when the answer is not yet.

Never: sad, angry, scared or guilt-tripping; red or alarming colours around him; more teeth, fangs or a hanging tongue
outside a laugh or a yawn; a baked-in shadow, background or frame; text or logos drawn in; a different hat, headphones or fur
from one scene to the next.

## The clips

`Cramless/Resources/CapClips/` has two transparent clips for each of the 19 poses (HEVC with alpha, 720 px, 24 fps; 38 files, 16 MB)
and `cap-clips.json`: the pose's own (an idle loop or a performance, 4 to 5 s, `<pose>.mov`) and its **poke** (3 s, what he does
when he is tapped, `<pose>Poke.mov`, role `poke` in the manifest). A clip starts and ends exactly on its pose's drawing, so the drawing hands to the clip
and back with nothing visible. The app plays them (`DesignSystem/Components/CapClips.swift` and `CapClipPlayer.swift`;
`docs/design.md` ▸ Cap has the rules for when).

A poke clip is made like any other: an entry in `clips.json` with id `<pose>Poke`, `"role": "poke"`, 3 seconds, and `gen pin` so it
starts and ends on the drawing and can play from whatever he was doing. Write what he does as a reaction to being touched, mostly
with his face, ears and paws: a big jump lifts his mortarboard, and the squash and bounce are added in code on top.

### Making or remaking one

Needs `FAL_KEY` and the Python tools in `scripts/cap_anim/` (Pillow and NumPy; ffmpeg with `hevc_videotoolbox`; Xcode's `swift`).

1. Write or edit the pose's entry in `scripts/cap_anim/clips.json` (what he does, how long, what his eyes do).
2. `python3 produce.py prompts <id>` prints the prompt and the cost, spending nothing.
3. `python3 produce.py gen pin <id> --take N` (the drawing as first and last frame; recommended) or `gen ref <id>` (Cap
   defined by the sheet, with the drawing as the first frame only). $0.157 a second of video. The tool refuses to pass its
   budget (`BUDGET` in `produce.py`) and records every run in `build/cap-clips/ledger.jsonl`.
4. `python3 produce.py check <id>-<mode>-<N>` keys the video off its flat background and judges it; `look` makes a strip of
   twelve frames to read. Look at it. The checks catch a clip that doesn't start on its drawing, never comes back to it, leaves
   pink behind, or has drifted in colour; they don't see a wrong eye or an extra tooth.
5. `python3 produce.py finalize <id> <clip>` ends it on the frame nearest its drawing, eases it onto the drawing, grades its
   colour onto the drawing's, encodes HEVC with alpha and verifies it with Apple's decoder.
6. `python3 produce.py install` copies the finals and the manifest into the app.
7. `python3 produce.py audit` reads every clip in the app and fails any with colour under its transparent pixels. (`reencode`
   encodes the finished clips again from their saved frames, for free, after a change to how they are encoded.)

### Traps (all learned the hard way)

- **Colour under transparency.** A clip is stored premultiplied (black where it is transparent) and a player draws the colour as it
  is, so any colour left under a transparent pixel is added to what is behind Cap: a lighter rectangle the size of the clip on a
  dark screen, and a halo round him. The first encode fed straight-alpha frames to the encoder (the keyer leaves colour under
  alpha 0, up to full white beside the outline) and macOS, which multiplies it away when it reads BGRA, hid it from every check.
  `produce.py` now premultiplies before it encodes and refuses a clip whose planes aren't black under its transparency
  (`produce.py audit` re-reads what is in the app; `hevc_planes.swift` shows the raw planes). Judge a new clip on a dark
  background as well as a light one.
- **Open eyes in a poke.** 4 of 19 first takes (celebrate, nice, proud, stargaze) opened his eyes with a white ring round them. A
  poke that shouldn't open them says so (`"eyes": "shut"`), and a reaction with a laugh or a gasp is worded without "wide" or
  "gasp". Look at the faces at full size, not only the strips: `build/cap-clips/frames/<clip>/rgba` has the keyed frames.

- `ref` mode has the best identity but treats the starting picture as a suggestion: on 9 of 19 first takes it zoomed in, turned
  to face front or landed in another pose. `pin` always starts on the drawing; describe his eyes and teeth in the prompt.
- A model that opens his eyes in a closed-eye pose draws googly white-ringed ones; say that they stay closed.
- A hop lifts the mortarboard off his head however the prompt is worded; make the cheer with only his arm and head.
- Kling re-colours the flat background per clip (magenta, raspberry, dusty rose) and adds a soft ground shadow; the keyer
  (`cap_anim.py` `key_frame`) treats anything on the line from black to the background colour, and anything of a magenta hue
  (Cap has none between 262 and 350 degrees), as background. Test a keyer on video-like composites (`keyer_check.py`), and
  count what is left over with `pink_audit.py`.
- A fast paw smears: motion blur mixes it with the background into mauve and salmon that the keyer cannot tell from Cap's own
  browns (the shipped scanPoke had 4 such frames). `residue_audit.py` finds them on the finished clips; `produce.py scrub <take>
  <first>-<last> <box>` recolours one from the fur beside it and keeps its shape. Drawing the frame again from its neighbours
  does not help (the blur is in their moving edge too), and dissolving the two neighbours ghosts the paw.
- HEVC below quality 55 softens his fur strokes; 65 with alpha quality 0.75 is crisp at about 1 MB for 5 s.
- NumPy 2.2 on Python 3.14 can change an array in place under `~a`, `a | b` and `a - b`. Use ufunc calls.
