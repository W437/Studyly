#!/usr/bin/env python3
"""The tour of Capling for a reviewer who can't install it: one short film per thing a student does, each driven with real taps.

    python3 scripts/journeys/tour.py list                      the journeys
    python3 scripts/journeys/tour.py try <name> <udid>         rehearse one on a simulator, no recording: a screenshot at every mark
                                                                (build/tour-try/<name>/), the steps printed as they happen
    simq run media -- scripts/journey_film.sh <udid> build/tour <name>       film one (film.sh records, lays the app's sounds over it,
                                                                and `package` makes the small copy for the page)
    python3 scripts/journeys/tour.py env <name>                the launch variables a journey needs (journey_film.sh reads them)
    python3 scripts/journeys/tour.py package <name> <out-dir>  the web-sized film, poster, captions and chapters of a finished film

A journey is a function of a `Phone` (phone.py): taps found by label, slow drags, typed answers, and `p.mark("...")` for each beat
worth a caption (the page turns the marks into clickable chapters and subtitles). Each one starts from a fresh launch of the app
in the demo world: Maya, a student with Bio 101, Chem 110 (a quiz in two days), AP Psychology and Spanish II, a 12-day streak.
The clock is frozen on an afternoon (after 22:00 the app keeps celebrations calm), the AI is the app's offline one (the simulator
has no Apple Intelligence; the Ask Cap assistant journeys, j_assistant.py, use the app's scripted demo server instead, because the
assistant runs only through a server), the sounds are the app's own, laid over the film by film.sh from the app's cue log.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from phone import Phone  # noqa: E402

import importlib

from registry import BUNDLE, COMMON_ENV, JOURNEYS  # noqa: E402,F401

# Every j_*.py next to this file registers its journeys on import.
for _module in sorted(Path(__file__).parent.glob("j_*.py")):
    importlib.import_module(_module.stem)


# ---------------------------------------------------------------------------------------------------------------------------------
# The runner
# ---------------------------------------------------------------------------------------------------------------------------------

APP = "build/Build/Products/Debug-iphonesimulator/Cramless.app"


def fresh(udid: str) -> None:
    """A clean install, so every film starts from what a new person has: no permissions granted, no leftovers."""
    subprocess.run(["xcrun", "simctl", "terminate", udid, BUNDLE], capture_output=True)
    subprocess.run(["xcrun", "simctl", "uninstall", udid, BUNDLE], capture_output=True)
    subprocess.run(["xcrun", "simctl", "install", udid, os.environ.get("JOURNEY_APP", APP)], check=True)


def launch(udid: str, name: str) -> None:
    """Rehearsal: the launch film.sh makes (priming launch first: the harness shows the welcome on the first launch after an install)."""
    env = {f"SIMCTL_CHILD_{k}": v for k, v in JOURNEYS[name]["env"].items()}
    for _ in range(2):
        subprocess.run(["xcrun", "simctl", "terminate", udid, BUNDLE], capture_output=True)
        subprocess.run(["xcrun", "simctl", "launch", udid, BUNDLE], env={**os.environ, **env}, capture_output=True)
        time.sleep(3.5)


def run(name: str, udid: str, pace: float = 1.0) -> None:
    p = Phone(udid, pace=pace)
    p.wait_app()
    p.dwell(0.8)
    JOURNEYS[name]["fn"](p)
    p.dwell(1.0)


def package(name: str, out: str) -> None:
    """The page's copy of a finished film: 540 px wide, small, with its poster, subtitles (WebVTT) and chapters (JSON): package.py."""
    from package import package as make
    out_dir = Path(out)
    journey_ = JOURNEYS.get(name, {})
    make(out_dir / f"{name}.mp4", out_dir / "web", name, out_dir / f"{name}.marks.json", journey_.get("title", name), journey_.get("blurb", ""))


def main() -> None:
    cmd = sys.argv[1] if len(sys.argv) > 1 else "list"
    if cmd == "list":
        for name, j in JOURNEYS.items():
            print(f"{name:14} {j['title']}")
    elif cmd == "exists":
        if sys.argv[2] not in JOURNEYS:
            raise SystemExit(f"no journey {sys.argv[2]}; try: {', '.join(JOURNEYS)}")
    elif cmd == "env":
        for k, v in JOURNEYS[sys.argv[2]]["env"].items():
            print(f"{k}={v}")
    elif cmd == "run":
        run(sys.argv[2], os.environ["JOURNEY_UDID"], float(os.environ.get("JOURNEY_PACE", "1")))
    elif cmd == "try":
        name, udid = sys.argv[2], sys.argv[3]
        os.environ["JOURNEY_SHOTS"] = f"build/tour-try/{name}"
        subprocess.run(["rm", "-rf", os.environ["JOURNEY_SHOTS"]])
        if os.environ.get("JOURNEY_FRESH", "1") == "1":
            fresh(udid)
        launch(udid, name)
        subprocess.run([sys.executable, __file__, "warm", udid])
        subprocess.run(["xcrun", "simctl", "terminate", udid, BUNDLE], capture_output=True)
        env = {f"SIMCTL_CHILD_{k}": v for k, v in JOURNEYS[name]["env"].items()}
        subprocess.run(["xcrun", "simctl", "launch", udid, BUNDLE], env={**os.environ, **env}, capture_output=True)
        started = time.time()
        os.environ["JOURNEY_MARKS"] = f"build/tour-try/{name}.marks.jsonl"
        Path(os.environ["JOURNEY_MARKS"]).unlink(missing_ok=True)
        run(name, udid, float(os.environ.get("JOURNEY_PACE", "1")))
        print(f"done in {time.time() - started:.0f}s; screenshots in {os.environ['JOURNEY_SHOTS']}")
    elif cmd == "fresh":
        fresh(sys.argv[2])
    elif cmd == "warm":
        Phone(sys.argv[2]).warm()
    elif cmd == "package":
        package(sys.argv[2], sys.argv[3])
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
