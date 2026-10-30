"""Eight looks for Capling's App Store header and Search card, written as GPT Image 2.5 briefs.

Each look is asked for twice: a 3:2 Search card and a 21:9 header. The model draws everything, the app's screens included, from
the real screens it is shown as references, so these are CONCEPTS: the one the owner picks gets rebuilt with the real pixels (see
scripts/store_art/store_lockup.py and the app-store-connect skill's asset-library.md).

The fixed parts, in every prompt: the brand and Cap's rules (docs/cap/README.md), the palette (Shared/BrandPalette.swift), Apple's
art safe area for the slot (measured from their templates 2026-10-29), and the hard rules for what may appear in store art.
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT_DIR = os.path.join(REPO, "build", "store-art", "gpt")
REFS_DIR = os.path.join(OUT_DIR, "refs")

# What the model is asked for (both sides multiples of 16, under 8.29 MP), and what is kept (the exact ratio of Apple's sizes:
# 3840x2560 and 3840x1646, at half the pixels, so a pick can be re-rendered at full size later).
ASK = {"card": (1920, 1280), "header": (1920, 832)}
KEEP = {"card": (1920, 1280), "header": (1920, 823)}
FULL = {"card": (3840, 2560), "header": (3840, 1646)}
# Apple's art safe areas as fractions of the canvas: x0, y0, x1, y1.
SAFE = {"card": (0.2177, 0.2992, 0.7818, 0.7008), "header": (0.2859, 0.3001, 0.7140, 0.6999)}

STYLE = (
    "BRAND: Capling, a study app for iPhone that turns a photo of your notes into checked questions, grades your answers in your "
    "own words, and shows how ready you are for each exam. Mascot: Cap, a calm, warm capybara who ALWAYS wears a navy mortarboard "
    "with a gold tassel and cream over-ear headphones; tangerine-orange fur, a rounded brown muzzle, closed content arc eyes and a "
    "small closed smile; flat vector style with soft simple shading, a few darker fur strokes and no outline. Keep Cap exactly "
    "on-model as in the character references (same head shape, hat, headphones, fur, proportions). Cap is never sad, angry or "
    "scared, and there are no red alarm colours around him.\n"
    "PALETTE: night navy #14213D, deep night #0B1220, sky blue #7CC8FF, tangerine #FF7A1A, sun yellow #FFCF3F, mint #22C38E, "
    "rose #FF5A78, white.\n"
    "TYPE: bold, friendly, rounded grotesque headlines (Bricolage Grotesque ExtraBold feel), tight leading, sentence case, high "
    "contrast against the background behind them.\n"
    "RULES: spell every quoted word exactly; draw no other words except the small interface text on phone screens that matches "
    "the references; no logos, watermarks, prices, review stars, ratings, awards, store badges or other brands; no people; fill "
    "the whole canvas edge to edge with no border, frame, rounded corners or device mockup around the picture."
)

FORMAT = {
    "card": (
        "FORMAT: 3:2 landscape store card, seen as a small thumbnail in search results. SAFE AREA: every headline word, Cap's "
        "face and the main phone screen must sit inside the central rectangle spanning the middle 56% of the width and the "
        "middle 40% of the height. Outside that rectangle: only scenery and atmosphere, which may be cropped on some devices. "
        "Make the subject as large and bold as that allows."
    ),
    "header": (
        "FORMAT: ultra-wide 21:9 header banner at the top of a product page. SAFE AREA: every headline word, Cap's face and the "
        "main phone screen must sit inside the central rectangle spanning the middle 43% of the width and the middle 40% of the "
        "height. Outside that rectangle: only scenery and atmosphere, which may be cropped on some devices. Arrange the "
        "elements as one horizontal band, as large and bold as that allows."
    ),
}

LOOKS = [
    dict(
        id="night", name="Night telescope",
        idea="The brand mood with the product in it: Cap at his telescope, a textbook page lifting off as a gold constellation, the scan screen beside it.",
        refs=[("cap_front", "Cap, character reference (front view)"), ("cap_stargaze", "Cap with his telescope"),
              ("screen_ideas", "the real Capling screen that reads a page and finds its key ideas")],
        scene=(
            "A deep night sky, navy to violet with a warm amber glow along the horizon, fine stars and a faint Milky Way. At the "
            "lower left Cap sits on a small grassy knoll beside a still lake that mirrors the sky, looking up through a brass "
            "telescope. In the middle a large open textbook page floats upward like a kite; its printed lines lift off the paper "
            "as tiny glowing stars and join into a gold constellation shaped like a graduation cap above it. Leaning against the "
            "floating page is a modern phone (thin bezels, no logos) whose bright screen shows the Capling screen from image 3. "
            "Mood: wonder, calm, magical; painterly flat vector with soft glows."),
        layout={"card": "Full-bleed scene. The headline is centred in the middle of the canvas over a calm darker patch of sky; Cap lower left and the phone lower right, both partly inside the safe rectangle; the floating page and its constellation rise around the headline.",
                "header": "Cap at the left of the band, the floating page and its constellation in the middle, the phone just right of them; the headline on the right half of the safe rectangle, left-aligned, over calm sky."},
        lines=["Snap your notes.", "Know you're ready."], accent="ready.", text_color="white", accent_color="sun yellow #FFCF3F"),
    dict(
        id="tangerine", name="Tangerine poster",
        idea="A bold flat poster, thumbnail-proof: big cheering Cap holding the readiness screen against solid brand orange.",
        refs=[("cap_front", "Cap, character reference (front view)"), ("cap_celebrate", "Cap cheering"),
              ("screen_ready", "the real Capling result screen: readiness ring 78%, Chem 110 Quiz, on track for 80%")],
        scene=(
            "A bold flat graphic poster. The whole background is solid tangerine #FF7A1A with a very subtle lighter radial glow "
            "behind the subject and a few confetti pieces in sky blue, sun yellow and mint. Cap, cheering with one paw raised and "
            "a big joyful closed-eye smile (the pose of image 2), stands large holding a big modern phone (no logos) in front of "
            "him whose screen shows the result screen of image 3: a progress ring at 78%, 'Chem 110 Quiz', '42% to 78% ready, 2 "
            "days left' and a mint pill 'On track for 80%'. Clean, graphic, minimal, very high contrast."),
        layout={"card": "Cap and the phone on the left half, large (their edges may pass the safe rectangle); the headline on the right half inside the safe rectangle, left-aligned.",
                "header": "One band: Cap with the phone at the left, the headline on the right inside the safe rectangle, left-aligned."},
        lines=["See how", "ready you are."], accent="ready", text_color="night navy #14213D",
        accent_color="night navy #14213D, with a thick sun-yellow swoosh underline beneath it"),
    dict(
        id="pagescan", name="Page to questions",
        idea="Product-led and photographic: a phone scans a textbook page and question cards, each tagged with its page, fan out of it.",
        refs=[("page", "the textbook page (keep its layout)"), ("screen_scan", "the real Capling screen where questions come out of the page, tagged p. 87"),
              ("cap_scan", "Cap holding a phone over a book")],
        scene=(
            "A photographic top-down desk scene in soft natural light. On a warm oak desk lies the textbook page of image 1 and a "
            "yellow highlighter. A modern phone (no logos) hovers above the page, scanning it with a thin bright blue scan line "
            "and blue corner brackets framing the page; its screen shows the screen of image 2. From the page five white rounded "
            "question cards rise and fan out toward the viewer in soft focus with gentle shadows; each has a small blue pill "
            "with a page icon and 'p. 87', and short question text such as 'Why do cells divide by mitosis?' and 'What happens "
            "to the nuclear envelope in prophase?'. Cap (image 3), small, sits in the lower left corner of the desk holding his "
            "own phone. A darker night-blue vignette at the edges keeps the headline legible."),
        layout={"card": "The desk scene fills the canvas; the headline is at the left of the safe rectangle over the dark vignette, the phone, page and question cards to its right.",
                "header": "One band: headline at the left over the dark vignette, then the phone above the page, the question cards fanning out to the right."},
        lines=["Snap a page.", "Get questions."], accent="questions.", text_color="white", accent_color="sun yellow #FFCF3F"),
    dict(
        id="ring", name="Readiness ring",
        idea="The unique part, as the hero: a huge glowing readiness ring and frosted glass cards on a dark premium ground, Cap small beside it.",
        refs=[("cap_front", "Cap, character reference (front view)"), ("cap_stargaze", "Cap with his telescope"),
              ("screen_ready", "the real Capling result screen: readiness ring 78%, Chem 110 Quiz, on track for 80%")],
        scene=(
            "A dark, premium product hero. Deep navy background (#0B1220 to #14213D) with a soft scatter of small stars. A huge "
            "luminous progress ring, about three quarters filled, drawn as a thick stroke with rounded ends that glows from sun "
            "yellow to mint; inside it the number '78%' in very large white numerals with the word 'ready' beneath. Around the "
            "ring float three frosted-glass cards (translucent, blurred, rounded, thin white edge) reading 'Chem 110 Quiz', '2 "
            "days left' and 'On track for 80%' (the interface look of image 3). Cap, small, sits at the lower right on the "
            "ring's edge looking up at it through a tiny telescope. Elegant, restrained, lots of dark space."),
        layout={"card": "The ring is large and a little right of centre; the headline is at the left, inside the safe rectangle, over dark space.",
                "header": "One band: headline at the left, the ring in the middle-right, the glass cards around it, Cap at the far right."},
        lines=["Know where", "you stand."], accent="stand.", text_color="white", accent_color="sun yellow #FFCF3F"),
    dict(
        id="steps", name="Three steps", bleed=True,
        idea="The whole product in three illustrated panels: snap the page, answer in your own words, see your readiness.",
        refs=[("cap_scan", "Cap scanning a page with a phone"), ("screen_answer", "the real Capling screen where an own-words answer is graded"),
              ("screen_ready", "the real Capling result screen: readiness ring 78%")],
        scene=(
            "Three equal rounded panels side by side on a soft night-blue backdrop, joined by dotted arrows; each is a clean flat "
            "illustration with a big numeral badge in a tangerine circle. Panel 1: Cap (image 1) holds up a phone toward a "
            "textbook page, blue scan corners around the page. Panel 2: a white answer card with the typed words 'So the body "
            "can grow and repair tissue, making two identical cells.' with mint highlighter on 'grow and repair' and 'two "
            "identical cells', and two green check marks (as in image 2). Panel 3: a readiness ring at 78% with a gold star "
            "lighting up beside it (as in image 3). Friendly, tidy, even spacing."),
        layout={"card": "The three panels fill about 85% of the canvas width and sit in the middle band of the canvas; each caption sits right under its panel. This look deliberately goes past the safe rectangle.",
                "header": "The three panels in one row across about 80% of the band's width, each caption right under its panel. This look deliberately goes past the safe rectangle."},
        lines=[], captions=["Snap your notes", "Answer in your own words", "See your readiness"]),
    dict(
        id="almost", name="Graded in your own words",
        idea="The differentiator, with Cap's warmth: his feedback on an own-words answer, the matching words highlighted.",
        refs=[("cap_front", "Cap, character reference (front view)"), ("cap_point", "Cap pointing at a card"),
              ("screen_answer", "the real Capling screen where an own-words answer is graded: 'Almost.'")],
        scene=(
            "Friendly and light. A soft pale-blue to cream background (#EAF3FF to #FFF6E8) with a few soft floating shapes. On "
            "the left Cap, large, three-quarter view, points one paw at a big white rounded answer card on the right which shows "
            "what image 3 shows: the question 'In your own words: why do cells divide by mitosis?', the typed answer 'So the "
            "body can grow and repair tissue, making two identical cells.' with mint highlights, two checked key ideas "
            "('Growth and repair', 'Genetically identical cells'), and below it a warm yellow feedback panel headed 'Almost.'. "
            "A small speech bubble from Cap reads 'Add the chromosome number.'"),
        layout={"card": "The headline is in the upper left of the safe rectangle; Cap stands below it at the left; the answer card fills the right half.",
                "header": "One band: headline at the left, Cap in the middle, the answer card at the right."},
        lines=["Graded in", "your own words."], accent="own words.", text_color="night navy #14213D", accent_color="tangerine #FF7A1A"),
    dict(
        id="desk", name="Study desk, daylight",
        idea="A bright, warm flat-lay that stands out among dark store art: Cap on the notebook, the phone showing the questions.",
        refs=[("cap_study", "Cap reading a book"), ("cap_threeq", "Cap, character reference (three-quarter view)"),
              ("page", "the textbook page"), ("screen_scan", "the real Capling screen where questions come out of the page")],
        scene=(
            "A bright, warm flat-lay illustration (not a photo) on cream paper (#FFF6E8): a spiral notebook, the textbook page "
            "of image 3 with yellow highlighter stripes, a pencil, a small mug and a sprig of leaves. Cap (images 1 and 2), small, "
            "sits on the notebook holding a pencil with a content smile. A modern phone (no logos) lies on the desk showing the "
            "screen of image 4. Mint check-mark stickers and sky-blue sparkles float above the notes. Friendly doodle texture, "
            "flat vector, soft paper shadows, room to breathe."),
        layout={"card": "The headline is at the left of the safe rectangle on a clean cream area; the desk objects, Cap and the phone fill the right and the edges.",
                "header": "One band: headline at the left on clean cream, then Cap on the notebook, then the phone and the page."},
        lines=["Your notes,", "quizzed."], accent="quizzed.", text_color="night navy #14213D", accent_color="tangerine #FF7A1A"),
    dict(
        id="memory", name="Memory sky",
        idea="The app's own idea as a picture: notes rise as constellations, a few stars fade, Cap relights one.",
        refs=[("cap_front", "Cap, character reference (front view)"), ("cap_stargaze", "Cap with his telescope"),
              ("screen_sky", "the real Capling 'Memory sky' screen")],
        scene=(
            "A dreamy view of a night sky built from notes. At the bottom an open book whose printed lines rise as thin threads "
            "of light and become constellations: bright gold and mint stars joined by fine lines, and a few dim stars drawn as "
            "hollow rings joined by dashed lines (fading memories). Cap sits at the lower left, small, holding up a little "
            "glowing lantern to relight one dim star, which flares gold with a four-point sparkle. A modern phone (no logos) at "
            "the lower right shows the 'Memory sky' screen of image 3. Deep navy to violet, painterly glow, calm and magical."),
        layout={"card": "The headline is centred in the middle in two lines over the calmest part of the sky; constellations around it; Cap lower left, the phone lower right.",
                "header": "One band: Cap and the book at the left, the headline in the middle over calm sky, the phone and the constellations at the right."},
        lines=["Keep every", "memory lit."], accent="lit.", text_color="white", accent_color="sun yellow #FFCF3F"),
]


def text_spec(look):
    """The exact words, as the brief states them."""
    parts = []
    if look.get("lines"):
        quoted = "; ".join(f'line {i + 1}: "{t}"' for i, t in enumerate(look["lines"]))
        n = len(look["lines"])
        parts.append(f'HEADLINE (spell exactly; {n} line{"s" if n > 1 else ""}; set large, as big as fits inside the safe rectangle): '
                     f'{quoted}. Colour: {look["text_color"]}.'
                     + (f' The word "{look["accent"]}" is in {look["accent_color"]}.' if look.get("accent") else ""))
    if look.get("captions"):
        quoted = "; ".join(f'"{t}"' for t in look["captions"])
        parts.append(f"CAPTIONS (spell exactly; bold; one right under each panel, left to right): {quoted}. White.")
    return "\n".join(parts)


def prompt(look, fmt):
    refs = "; ".join(f"image {i + 1} = {what}" for i, (_, what) in enumerate(look["refs"]))
    return (f"{STYLE}\n\n{FORMAT[fmt]}\n\nREFERENCES (in order): {refs}. Cap must match his character references exactly; any phone "
            f"screen must look like the real screen shown, in the same layout and colours.\n\nSCENE: {look['scene']}\n\n"
            f"LAYOUT: {look['layout'][fmt]}\n\n{text_spec(look)}")


def jobs(only=None, fmt=None):
    out = []
    for look in LOOKS:
        if only and look["id"] not in only:
            continue
        for f in ("card", "header"):
            if fmt and f != fmt:
                continue
            out.append(dict(id=f"{look['id']}-{f}", look=look["id"], fmt=f, size=ASK[f], keep=KEEP[f],
                            refs=[os.path.join(REFS_DIR, f"{k}.jpg") for k, _ in look["refs"]], prompt=prompt(look, f)))
    return out
