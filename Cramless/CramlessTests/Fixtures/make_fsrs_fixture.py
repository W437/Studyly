"""Writes reference review histories from py-fsrs (fuzz off) for the Swift FSRS-6 port's parity test.

Usage: venv/bin/python -I make_fsrs_fixture.py <output.json>
"""

import json
import random
import sys
from datetime import datetime, timedelta, timezone
from importlib.metadata import version

from fsrs import Card, Rating, Scheduler

T0 = datetime(2026, 1, 5, 9, 0, 0, tzinfo=timezone.utc)


def iso(d):
    return d.isoformat()


def ts(d):
    return d.timestamp()


def make_scheduler(**kw):
    return Scheduler(enable_fuzzing=False, **kw)


def run(name, scheduler, steps, note=""):
    """steps: list of (when, rating). when = seconds after the previous review (first: after T0),
    'due' (the card's due time), or ('due', seconds) (due + seconds, negative for early)."""
    card = Card(card_id=1, due=T0)
    t = T0
    reviews = []
    for when, rating in steps:
        if when == "due":
            t = card.due
        elif isinstance(when, tuple) and when[0] == "due":
            t = card.due + timedelta(seconds=when[1])
        else:
            t = t + timedelta(seconds=when)
        r_before = scheduler.get_card_retrievability(card, current_datetime=t)
        card, _ = scheduler.review_card(card, Rating(rating), review_datetime=t)
        reviews.append(
            {
                "at": ts(t),
                "atISO": iso(t),
                "rating": rating,
                "retrievabilityBefore": r_before,
                "state": card.state.value,
                "step": card.step,
                "stability": card.stability,
                "difficulty": card.difficulty,
                "due": ts(card.due),
                "dueISO": iso(card.due),
            }
        )
    # Retrievability after the last review, at a few later times.
    samples = []
    for hours in [0, 5, 23.9, 24, 36, 72, 24 * 10, 24 * 45, 24 * 400]:
        at = t + timedelta(hours=hours)
        samples.append({"at": ts(at), "r": scheduler.get_card_retrievability(card, current_datetime=at)})
    return {
        "name": name,
        "note": note,
        "desiredRetention": scheduler.desired_retention,
        "maximumInterval": scheduler.maximum_interval,
        "learningSteps": [s.total_seconds() for s in scheduler.learning_steps],
        "relearningSteps": [s.total_seconds() for s in scheduler.relearning_steps],
        "start": ts(T0),
        "reviews": reviews,
        "retrievabilitySamples": samples,
    }


def main(out_path):
    default = make_scheduler()
    histories = [
        run("new-good-path", default,
            [(0, 3), (600, 3), ("due", 3), ("due", 3), ("due", 3), ("due", 4), ("due", 2), ("due", 3)],
            "New card through the learning steps, then on-time reviews."),
        run("new-easy", default, [(0, 4), ("due", 3), ("due", 3), ("due", 1), (600, 3), ("due", 3)],
            "Easy on a new card skips the learning steps."),
        run("learning-again-hard", default,
            [(0, 1), (60, 2), (330, 3), (600, 2), (600, 3), ("due", 3)],
            "Again and Hard inside the learning steps (Hard at step 0 = 5.5 min, at step 1 = 10 min)."),
        run("lapse-relearn", default,
            [(0, 3), (600, 3), ("due", 3), ("due", 1), (600, 2), (900, 1), (600, 3), ("due", 3), ("due", 3)],
            "A lapse, then Hard (15 min) and Again inside relearning, then back to review."),
        run("same-day-reviews", default,
            [(0, 3), (600, 3), ("due", 3), (7200, 3), (10800, 4), (3600, 1), (600, 3), ("due", 2)],
            "Short-term stability for same-day reviews in review and relearning."),
        run("overdue-and-forgotten", default,
            [(0, 3), (600, 3), ("due", 3), (("due", 60 * 86400), 3), (200 * 86400, 1), (600, 3), ("due", 3)],
            "Reviewed 60 days late, then forgotten after 200 days."),
        run("early-review", default,
            [(0, 3), (600, 3), ("due", 3), (86400, 3), (2 * 86400, 2), ("due", 4), (("due", -86400 * 2), 3)],
            "Reviews well before the due date."),
        run("learning-next-day", default, [(0, 3), (2 * 86400, 3), ("due", 3)],
            "A learning card reviewed two days later uses the long-term update."),
        run("new-again-days-later", default, [(0, 1), (3 * 86400, 3), (600, 3), ("due", 3)],
            "Again on a new card, then three days later."),
        run("hard-chain", default, [(0, 2), (330, 2), (600, 3)] + [("due", 2)] * 6,
            "Hard on time: difficulty climbs toward 10."),
        run("easy-chain", default, [(0, 4)] + [("due", 4)] * 12,
            "Easy on time: difficulty falls to 1, intervals grow."),
        run("again-chain", default, [(0, 3), (600, 3)] + [("due", 1), (600, 3)] * 5,
            "Repeated lapses: difficulty to 10, stability shrinks."),
        run("clock-skew", default, [(0, 3), (600, 3), ("due", 3), (-3600, 3), ("due", 3)],
            "A review stamped an hour before the last one (negative elapsed time)."),
        run("retention-0.85", make_scheduler(desired_retention=0.85),
            [(0, 3), (600, 3), ("due", 3), ("due", 3), ("due", 2), ("due", 1), (600, 3), ("due", 3)],
            "Lower desired retention: longer intervals."),
        run("retention-0.95", make_scheduler(desired_retention=0.95),
            [(0, 3), (600, 3), ("due", 3), ("due", 3), ("due", 4), ("due", 3)],
            "Higher desired retention: shorter intervals."),
        run("max-interval-365", make_scheduler(maximum_interval=365), [(0, 4)] + [("due", 4)] * 8,
            "Intervals capped at the maximum."),
    ]

    # Seeded random histories for breadth: ratings weighted like real use, times on time, early, late or same day.
    rng = random.Random(20261022)
    for k in range(24):
        retention = rng.choice([0.8, 0.85, 0.9, 0.9, 0.9, 0.95])
        sched = make_scheduler(desired_retention=retention)
        steps = []
        n = rng.randint(4, 14)
        for i in range(n):
            rating = rng.choices([1, 2, 3, 4], weights=[15, 15, 60, 10])[0]
            if i == 0:
                steps.append((rng.randint(0, 3600), rating))
                continue
            mode = rng.random()
            if mode < 0.45:
                steps.append(("due", rating))
            elif mode < 0.65:
                steps.append((("due", rng.randint(-3 * 86400, 20 * 86400)), rating))
            elif mode < 0.85:
                steps.append((rng.randint(60, 20 * 3600), rating))
            else:
                steps.append((rng.randint(86400, 30 * 86400), rating))
        histories.append(run(f"random-{k:02d}", sched, steps, f"Seeded random history (retention {retention})."))

    # next_interval for a range of stabilities and retentions (banker's rounding, clamps).
    intervals = []
    for retention in [0.7, 0.8, 0.85, 0.9, 0.95, 0.97]:
        s = make_scheduler(desired_retention=retention)
        for stability in [0.001, 0.1, 0.4, 0.5, 1.0, 1.5, 2.3065, 2.5, 3.5, 7.0, 10.0, 33.3, 100.0, 1000.0, 50000.0]:
            intervals.append({"retention": retention, "stability": stability,
                              "interval": s._next_interval(stability=stability)})

    fixture = {
        "generator": "py-fsrs (PyPI fsrs) Scheduler with enable_fuzzing=False",
        "fsrsVersion": version("fsrs"),
        "pythonVersion": sys.version.split()[0],
        "parameters": list(default.parameters),
        "histories": histories,
        "intervals": intervals,
    }
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(fixture, f, indent=1, sort_keys=True)
        f.write("\n")
    print(f"wrote {len(histories)} histories, {sum(len(h['reviews']) for h in histories)} reviews, "
          f"{len(intervals)} intervals (fsrs {fixture['fsrsVersion']}) to {out_path}")


if __name__ == "__main__":
    main(sys.argv[1])
