#!/usr/bin/env python3
"""A phone driven the way a person uses it, for tour films (record.sh runs a script of these moves while it records).

It wraps `mobilecli` (the driver behind the `mobile` MCP tools): a real tap or drag on the Simulator, found by the control's
accessibility label, so a script survives layout changes. Taps are real touches, so the app answers exactly as it does to a finger.

    from phone import Phone
    p = Phone("<udid>")
    p.tap("Study")                   # waits for the control, taps near its middle
    p.dwell(1.5)                     # a person reading
    p.scroll(350)                    # drag the page up by 350 points, slowly enough to follow
    p.type("Cells divide to make...") # typed in short bursts, like a person
    p.mark("The answer is graded")   # a caption at this moment: the page turns marks into chapters

Exploring a screen: `python3 phone.py <udid> dump` lists what is on it; `... tap "Today"`, `... swipe 201,600,201,300`.
Coordinates are points (402 x 874 on an iPhone 17 Pro).

The first call to mobilecli on a simulator starts its agent, and that sends the app to the background: warm it up (`dump`) before
the app is launched, or launch the app again after the first call.
"""
from __future__ import annotations

import glob
import json
import os
import random
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass

# Points, not pixels: 402 x 874 is an iPhone 17 Pro. Another device: JOURNEY_SCREEN=375x667.
SCREEN_W, SCREEN_H = (int(n) for n in os.environ.get("JOURNEY_SCREEN", "402x874").split("x"))
SPRINGBOARD = "Home screen icons"


def find_mobilecli() -> str:
    """The mobilecli binary: $MOBILECLI, a global install, or the copy the mobile MCP server keeps in the npx cache."""
    if os.environ.get("MOBILECLI"):
        return os.environ["MOBILECLI"]
    on_path = shutil.which("mobilecli")
    if on_path:
        return on_path
    hits = glob.glob(os.path.expanduser("~/.npm/_npx/*/node_modules/@mobilenext/mobilecli-darwin-arm64/mobilecli-darwin-arm64"))
    if hits:
        return max(hits, key=os.path.getmtime)
    raise SystemExit("mobilecli not found: set MOBILECLI, or run the mobile MCP server once (npx @mobilenext/mobile-mcp)")


@dataclass
class El:
    ref: str
    type: str
    label: str
    ident: str
    value: str
    x: float
    y: float
    w: float
    h: float
    depth: int = 0

    @property
    def cx(self) -> float:
        return self.x + self.w / 2

    @property
    def cy(self) -> float:
        return self.y + self.h / 2

    def on_screen(self, top: float = 0, bottom: float = SCREEN_H) -> bool:
        return self.w > 0 and self.h > 0 and self.cy >= top and self.cy <= bottom and self.cx >= 0 and self.cx <= SCREEN_W

    def __str__(self) -> str:
        return f"{self.type} '{self.label}' ({self.x:.0f},{self.y:.0f} {self.w:.0f}x{self.h:.0f})"


class Phone:
    def __init__(self, udid: str | None = None, pace: float = 1.0, seed: int = 7):
        self.udid = udid or os.environ.get("JOURNEY_UDID") or ""
        if not self.udid:
            raise SystemExit("no simulator: pass a udid or set JOURNEY_UDID")
        self.cli = find_mobilecli()
        self.pace = pace
        self.rng = random.Random(seed)
        self.marks_path = os.environ.get("JOURNEY_MARKS")
        self.shots_dir = os.environ.get("JOURNEY_SHOTS")   # set while rehearsing: a screenshot at every mark
        self.shot_count = 0
        self.t0 = time.time()
        self.chatty = os.environ.get("JOURNEY_QUIET") != "1"
        self.screen_h = SCREEN_H
        self.stall_after = 4.0

    # -- the driver ---------------------------------------------------------------------------------------------------

    def _run(self, *args: str, timeout: float = 70, retries: int = 2, normal: float = 1.8, tail: float = 0.1) -> dict:
        """One mobilecli call. The agent waits for the app to be idle before it reads the screen or touches it, and an app with a
        looping animation never is: the call comes back after 20 s or so. `normal` is how long the call takes when it is not
        waiting, `tail` how much of its end is the real thing (the touch, the drag). A call that took much longer than `normal` is
        written to the marks as a cut, so the film can drop the wait."""
        last = ""
        for attempt in range(retries + 1):
            began = time.time()
            try:
                out = subprocess.run([self.cli, *args, "--device", self.udid], capture_output=True, text=True, timeout=timeout)
            except subprocess.TimeoutExpired:
                last = f"timed out after {timeout:.0f} s"
                self._stalled(began, time.time(), args, tail)
                continue
            if time.time() - began > normal + 3:
                self._stalled(began, time.time(), args, tail)
            try:
                return json.loads(out.stdout)
            except json.JSONDecodeError:
                last = f"{out.stdout[:160]} {out.stderr[:160]}"
                time.sleep(1)
        raise RuntimeError(f"mobilecli {' '.join(args)}: {last}")

    def _stalled(self, began: float, ended: float, args, tail: float) -> None:
        if self.chatty:
            print(f"  [{ended - self.t0:6.1f}s] STALL {ended - began:.1f}s in {' '.join(args[:2])}", flush=True)
        if self.marks_path:
            with open(self.marks_path, "a") as f:
                f.write(json.dumps({"t": began + 0.3, "cue": "_cut", "until": ended - tail}) + "\n")

    def dump(self) -> list[El]:
        data = self._run("dump", "ui")["data"]["elements"]
        flat: list[El] = []

        def walk(e: dict, depth: int) -> None:
            r = e.get("rect") or {}
            flat.append(El(e.get("ref", ""), e.get("type", ""), (e.get("label") or e.get("name") or "").strip(),
                           e.get("identifier") or "", str(e.get("value") or ""),
                           r.get("x", 0), r.get("y", 0), r.get("width", 0), r.get("height", 0), depth))
            for c in e.get("children") or []:
                walk(c, depth + 1)

        for e in data:
            walk(e, 0)
        return flat

    def warm(self) -> None:
        """Starts the simulator's agent (the first call does; it takes a few seconds)."""
        try:
            self.dump()
        except Exception:
            pass

    def in_app(self, els: list[El] | None = None) -> bool:
        """The app is in front and has drawn something (a launch screen has no elements; the home screen is "Home screen icons")."""
        els = els if els is not None else self.dump()
        return len(els) >= 4 and els[0].label != SPRINGBOARD

    def wait_app(self, timeout: float = 25) -> None:
        """Wait until the app is on screen. The moment is written to the marks as `_ready`: record.sh starts the film a beat before it,
        so the launch (a white screen for a second or two) is not in the film."""
        end = time.time() + timeout
        while time.time() < end:
            try:
                if self.in_app():
                    if self.marks_path:
                        with open(self.marks_path, "a") as f:
                            f.write(json.dumps({"t": time.time(), "cue": "_ready"}) + "\n")
                    return
            except Exception:
                pass
            time.sleep(0.5)
        raise TimeoutError("the app did not come to the front")

    # -- finding ------------------------------------------------------------------------------------------------------

    @staticmethod
    def _match(el: El, query: str) -> int:
        """0 = no match, 2 = the whole label, 1 = part of it. `re:` prefix: a regular expression."""
        label = el.label
        if query.startswith("re:"):
            return 1 if re.search(query[3:], label, re.I) else 0
        if label.lower() == query.lower():
            return 2
        return 1 if query.lower() in label.lower() else 0

    def find(self, query: str, *, type: str | None = None, nth: int = 0, top: float = 0, bottom: float = SCREEN_H,
             els: list[El] | None = None) -> El | None:
        els = els if els is not None else self.dump()
        # The floating tab bar covers the bottom of a page: a control behind it can't be tapped (a tap there is the tab's).
        bar = next((e for e in els if e.type == "TabBar"), None)
        tabs = self.tab_labels(els)

        def covered(e: El) -> bool:
            return bar is not None and e.cy >= bar.y and e.label.lower() not in tabs

        hits = [(self._match(e, query), e) for e in els
                if (type is None or e.type == type) and e.on_screen(top, bottom) and not covered(e)]
        hits = [(score, e) for score, e in hits if score]
        if not hits:
            return None
        best = max(score for score, _ in hits)
        ordered = sorted((e for score, e in hits if score == best), key=lambda e: (round(e.y / 8), e.x))
        return ordered[nth] if nth < len(ordered) else None

    @staticmethod
    def tab_labels(els: list[El]) -> set[str]:
        """The tab bar's own buttons (lowercased), read from the bar's children, whatever the app calls its tabs."""
        for i, bar in enumerate(els):
            if bar.type == "TabBar":
                names = set()
                for child in els[i + 1:]:
                    if child.depth <= bar.depth:
                        break
                    if child.type == "Button" and child.label:
                        names.add(child.label.lower())
                return names
        return set()

    def wait(self, query: str, timeout: float = 12, **kw) -> El:
        end = time.time() + timeout
        last: list[El] = []
        while True:
            last = self.dump()
            el = self.find(query, els=last, **kw)
            if el:
                return el
            if time.time() > end:
                raise TimeoutError(f"'{query}' never showed. On screen:\n{self.describe(last, limit=22)}")
            time.sleep(0.35)

    def wait_gone(self, query: str, timeout: float = 12, **kw) -> None:
        end = time.time() + timeout
        while self.find(query, **kw):
            if time.time() > end:
                raise TimeoutError(f"'{query}' never went away")
            time.sleep(0.35)

    def headline(self, els: list[El] | None = None, min_y: float = 100) -> str:
        """The screen's biggest piece of text (its title), on one line: captions that quote the app's own words."""
        els = els if els is not None else self.dump()
        texts = [e for e in els if e.type == "StaticText" and e.on_screen() and e.y >= min_y and len(e.label) > 6]
        if not texts:
            return ""
        top = max(texts, key=lambda e: (e.h, -e.y))
        return " ".join(top.label.split())

    def has(self, query: str, **kw) -> bool:
        return self.find(query, **kw) is not None

    def describe(self, els: list[El] | None = None, texts: bool = True, limit: int = 60) -> str:
        els = els if els is not None else self.dump()
        keep = {"Button", "TextField", "SecureTextField", "TextView", "Switch", "Slider", "Link", "Cell", "Tab", "SegmentedControl",
                "Stepper", "Picker", "PickerWheel", "SearchField", "Alert", "Sheet", "NavigationBar"}
        containers = [e for e in els if e.type in keep and e.label and e.w > 0]
        lines = []
        for e in els:
            if not e.on_screen() or not e.label and e.type not in keep:
                continue
            if e.type not in keep:
                if not texts or e.type != "StaticText":
                    continue
                # A text that a button above already says (its own label) is not worth a line.
                if any(c is not e and c.x - 1 <= e.x and c.y - 1 <= e.y and c.x + c.w + 1 >= e.x + e.w and c.y + c.h + 1 >= e.y + e.h
                       and e.label.lower() in c.label.lower() for c in containers):
                    continue
            lines.append(f"  {e.type[:7]:7} {e.label[:78]!r:82} ({e.x:.0f},{e.y:.0f} {e.w:.0f}x{e.h:.0f})")
        more = f"\n  … {len(lines) - limit} more" if len(lines) > limit else ""
        return "\n".join(lines[:limit]) + more

    # -- acting -------------------------------------------------------------------------------------------------------

    def _point(self, target, jitter: bool = True) -> tuple[float, float]:
        if isinstance(target, El):
            dx = self.rng.uniform(-0.18, 0.18) * min(target.w, 120) if jitter else 0
            dy = self.rng.uniform(-0.15, 0.15) * min(target.h, 60) if jitter else 0
            return target.cx + dx, target.cy + dy
        return float(target[0]), float(target[1])

    def tap(self, target, *, after: float = 0.7, timeout: float = 12, **kw) -> El | None:
        """Tap a control by label (waits for it), an El, or a point (x, y)."""
        el = None
        if isinstance(target, str):
            el = self.wait(target, timeout=timeout, **kw)
            x, y = self._point(el)
        else:
            x, y = self._point(target)
            el = target if isinstance(target, El) else None
        if self.chatty:
            print(f"  [{time.time() - self.t0:6.1f}s] tap {el.label[:50]!r} at ({x:.0f},{y:.0f})" if el else f"  tap ({x:.0f},{y:.0f})", flush=True)
        self._run("io", "tap", f"{x:.0f},{y:.0f}", normal=1.6, tail=0.7)
        self.dwell(after)
        return el

    def long_press(self, target, **kw) -> None:
        el = self.wait(target, **kw) if isinstance(target, str) else target
        x, y = self._point(el)
        self._run("io", "longpress", f"{x:.0f},{y:.0f}", normal=2.2, tail=1.2)
        self.dwell(0.8)

    def swipe(self, x1: float, y1: float, x2: float, y2: float, ms: int = 450, after: float = 0.5) -> None:
        """A drag. Keep both ends clear of the bottom edge (a swipe that ends there opens the app switcher)."""
        if self.chatty:
            print(f"  [{time.time() - self.t0:6.1f}s] swipe ({x1:.0f},{y1:.0f}) -> ({x2:.0f},{y2:.0f}) {ms} ms", flush=True)
        self._run("io", "swipe", f"{x1:.0f},{y1:.0f},{x2:.0f},{y2:.0f}", "--duration", str(ms), normal=ms / 1000 + 1.8, tail=ms / 1000 + 0.6)
        self.dwell(after)

    def back(self, **kw) -> El | None:
        """The back button of a pushed screen: the button at the top left, whatever the previous screen is called ("Back", "Settings")."""
        els = self.dump()
        cands = sorted((e for e in els if e.type == "Button" and 50 < e.cy < 120 and e.x < 70 and e.w < 90), key=lambda e: e.x)
        if not cands:
            raise TimeoutError("no back button. On screen:\n" + self.describe(els, limit=18))
        return self.tap(cands[0], **kw)

    def dismiss(self) -> None:
        """Close a sheet the way a person does: drag it down from its top."""
        self.swipe(201, 120, 201, 700, ms=380, after=0.8)

    def tab(self, name: str, **kw) -> El | None:
        """One of the tab bar's buttons: Today, Library, Ask, Progress or Add. The bar folds to the current tab and Add when a page is
        scrolled down (and stays folded after coming back from a pushed screen); a tap on the folded tab opens it again, as it does
        for a person."""
        els = self.dump()
        if not self.find(name, type="Button", top=self.screen_h - 100, els=els):
            # Folded: the bar shows only the current tab (and a plus), low on the screen. Tap the current tab to open it.
            folded = [e for e in els if e.type == "Button" and e.x < 70 and e.w < 70 and e.cy > self.screen_h - 90 and e.label]   # at the left edge
            if folded:
                self.tap(folded[0], after=1.0)
            else:
                self.scroll(-260, after=0.9)
        return self.tap(name, type="Button", **kw)

    def scroll(self, points: float = 380, *, x: float = 201, start: float | None = None, ms: int | None = None, after: float = 0.6) -> None:
        """Move the page up by about `points` (a finger dragging up); negative moves it down. A drag that is not too slow and not
        too fast: slower and the page overshoots (the release counts as a flick), faster and it flies. How far a page actually
        moves differs by page, so aim at something with `scroll_to` and look where it landed."""
        points = float(points)
        if start is None:
            start = 640 if points > 0 else 230
        end = min(max(start - points, 110), 790)
        ms = ms or (550 if abs(points) <= 220 else int(500 + abs(points) * 0.5))
        self.swipe(x, start, x, end, ms=ms, after=after)

    def scroll_to(self, query: str, *, top: float = 120, bottom: float = 700, tries: int = 9, points: float = 300, **kw) -> El:
        """Scroll until the control sits in the band between `top` and `bottom`, steering by where it is when the page draws it."""
        mid = (top + bottom) / 2
        for _ in range(tries):
            els = self.dump()
            hit = self.find(query, top=top, bottom=bottom, els=els, **kw)
            if hit:
                return hit
            drawn = self.find(query, top=-4000, bottom=6000, els=els, **kw)
            if drawn:      # small steps: a release now and then counts as a flick and runs on, and a big correction would run on twice as far
                self.scroll(max(-200, min(200, (drawn.cy - mid) * 0.7)), after=1.1)
            else:
                self.scroll(min(points, 200), after=1.1)
        raise TimeoutError(f"never scrolled to '{query}'. On screen:\n{self.describe(limit=22)}")

    def type(self, text: str, *, burst: int = 10) -> None:
        """Type in short bursts. Each `io text` call costs about 1.4 s however short, then types at about 30 characters a second, so
        10 characters a call comes to roughly 4 a second: a typist who looks up between words."""
        i = 0
        while i < len(text):
            self._run("io", "text", text[i:i + burst], normal=3.0, tail=1.2)
            i += burst
        if self.chatty:
            print(f"  [{time.time() - self.t0:6.1f}s] typed {text[:40]!r}", flush=True)

    def key(self, *keys: str) -> None:
        self._run("io", "keys", *keys)

    def dwell(self, seconds: float) -> None:
        """A beat: reading, looking, waiting for an animation to land."""
        time.sleep(max(0.0, seconds) * self.pace)

    # -- the film's captions ------------------------------------------------------------------------------------------

    def mark(self, caption: str) -> None:
        """A caption at this moment. film.sh turns it into a time in the finished film (chapters and subtitles on the page)."""
        now = time.time()
        if self.marks_path:
            with open(self.marks_path, "a") as f:
                f.write(json.dumps({"t": now, "cue": caption}) + "\n")
        if self.chatty:
            print(f"[{now - self.t0:6.1f}s] ## {caption}", flush=True)
        if self.shots_dir:
            self.shot(caption)

    def shot(self, caption: str = "") -> None:
        """A screenshot, while rehearsing without a recording."""
        if not self.shots_dir:
            return
        os.makedirs(self.shots_dir, exist_ok=True)
        self.shot_count += 1
        slug = re.sub(r"[^a-z0-9]+", "-", caption.lower()).strip("-")[:48]
        subprocess.run(["xcrun", "simctl", "io", self.udid, "screenshot", "--type=jpeg",
                        f"{self.shots_dir}/{self.shot_count:02d}-{slug}.jpg"], capture_output=True)


def main() -> None:
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    udid, cmd, rest = sys.argv[1], sys.argv[2], sys.argv[3:]
    p = Phone(udid)
    if cmd == "dump":
        print(p.describe())
    elif cmd == "tap":
        p.tap(rest[0] if not re.fullmatch(r"\d+,\d+", rest[0]) else tuple(map(float, rest[0].split(","))))
    elif cmd == "tab":
        p.tab(rest[0])
    elif cmd == "swipe":
        x1, y1, x2, y2 = map(float, rest[0].split(","))
        p.swipe(x1, y1, x2, y2, ms=int(rest[1]) if len(rest) > 1 else 450)
    elif cmd == "scroll":
        p.scroll(float(rest[0]))
    elif cmd == "type":
        p.type(" ".join(rest))
    else:
        raise SystemExit(f"unknown command {cmd}")


if __name__ == "__main__":
    main()
