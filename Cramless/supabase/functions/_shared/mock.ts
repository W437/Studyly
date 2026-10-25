// MOCK mode (CRAMLESS_MOCK=1): the AI routes answer with the canned replies in _shared/fixtures, the same files
// the iOS app bundles for its own mock transport, byte for byte, after the same auth, validation and quota logic,
// with believable latency. The tutor replays its script's delays. Real-mode output processing (anchor filtering)
// doesn't apply: the fixtures are the reference answers.

import type { GradeRequest, TutorRequest } from "./contract.ts";
import { FIXTURES } from "./generated.ts";

/** How long each route "thinks" in MOCK mode. */
export const MOCK_LATENCY_MS: Record<string, number> = {
  generate: 2500,
  check: 1500,
  grade: 900,
  confusions: 1800,
  lecture: 2500,
  "cards-from-chat": 1200,
  "transcribe-image": 1500,
};

/** The fixture a route replies with by default. */
export const MOCK_FIXTURE: Record<string, string> = {
  generate: "generate",
  check: "check",
  confusions: "confusions",
  lecture: "lecture",
  "cards-from-chat": "cards-from-chat",
  "transcribe-image": "transcribe-image",
};

export function fixtureText(name: string): string {
  const text = FIXTURES[name];
  if (text === undefined) throw new Error(`Missing fixture ${name}`);
  return text;
}

/** The grade a simple term match would give: every key idea named → correct, some → partial, none → incorrect.
 * The fixture request (fixtures/requests/grade.json) hits two of three ideas, so it gets grade-partial. */
export function gradeFixture(req: GradeRequest): "grade-correct" | "grade-partial" | "grade-incorrect" {
  const answer = req.response.toLowerCase();
  const hit =
    req.keyIdeas.filter((idea) =>
      [...idea.terms, idea.label].some((t) => t.trim().length > 0 && answer.includes(t.trim().toLowerCase()))
    ).length;
  if (req.keyIdeas.length > 0 && hit === req.keyIdeas.length) return "grade-correct";
  return hit > 0 ? "grade-partial" : "grade-incorrect";
}

/** Hints first (always for a minor), else the explaining script. */
export function tutorFixture(req: TutorRequest): "tutor-hints" | "tutor-explain" {
  return req.minor || req.mode === "hints" ? "tutor-hints" : "tutor-explain";
}

/** A test hook, MOCK mode only: `X-Cramless-Fixture: grade-incorrect` (or `tutor-error`, …) picks another canned
 * reply of the same route, so the app can show every state against a local relay. */
export function fixtureOverride(req: Request, route: string): string | null {
  const asked = req.headers.get("x-cramless-fixture")?.trim();
  if (!asked || FIXTURES[asked] === undefined || asked.startsWith("requests/")) return null;
  if (route === "grade") return asked.startsWith("grade-") ? asked : null;
  if (route === "tutor") return asked.startsWith("tutor-") ? asked : null;
  return asked === MOCK_FIXTURE[route] ? asked : null;
}
