// MOCK mode (CRAMLESS_MOCK=1): the AI routes answer with the canned replies in _shared/fixtures, the same files
// the iOS app bundles for its own mock transport, byte for byte, after the same auth, validation and quota logic,
// with believable latency. The tutor replays its script's delays. Real-mode output processing (anchor filtering)
// doesn't apply: the fixtures are the reference answers.

import type { AssistantRequest, GradeRequest, TutorRequest } from "./contract.ts";
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

/** A problem from a photo, then "Explain my mistake", then hints first (always for a minor), else the explaining script. The app's
 * mock transport (MockRelayTransport.swift) chooses the same way. */
export function tutorFixture(req: TutorRequest): "tutor-photo" | "tutor-mistake" | "tutor-hints" | "tutor-explain" {
  if (req.fromPhoto) return "tutor-photo";
  if (req.context) return "tutor-mistake";
  return req.minor || req.mode === "hints" ? "tutor-hints" : "tutor-explain";
}

/** The canned reply an assistant request gets in MOCK mode. The first round is chosen by what the student asked; after
 * a round of tool calls, by the tool the model last called (a lookup leads on to drafting cards, anything else to its
 * wrap-up; a call that failed, or cards made after a lookup, have wrap-ups of their own). The app's mock transport (MockRelayTransport.swift) chooses the same way, and both are tested on one table. */
export function assistantFixture(req: AssistantRequest): string {
  const asked = (req.messages[req.messages.length - 1]?.text ?? "").toLowerCase();
  if (req.turns.length > 0) {
    const turn = req.turns[req.turns.length - 1];
    // A call that failed gets a wrap-up that says so, whichever tool it was.
    if (turn.results.some((r) => /"error"\s*:/.test(r.output))) return "assistant-failed-final";
    const last = turn.continuation.find((i) => i.type === "function_call");
    const afterLookup = req.turns.slice(0, -1).some((t) =>
      t.continuation.some((i) => i.type === "function_call" && i.name === "search_notes")
    );
    switch (last?.name) {
      case "search_notes":
        return "assistant-multi-2";
      case "create_flashcards":
        return afterLookup ? "assistant-multi-final" : "assistant-cards-final";
      case "create_quiz_questions":
        return "assistant-quiz-final";
      case "create_note":
        return "assistant-note-final";
      case "create_exam":
        return "assistant-exam-final";
      case "start_practice":
        return "assistant-practice-final";
      case "open_screen":
        return "assistant-open-final";
      case "research_web":
        return "assistant-research-final";
      default:
        return "assistant-answer";
    }
  }
  if (asked.includes("#fail")) return "assistant-error";
  if (asked.includes("#limit")) return "assistant-limit";
  if (/\b(research|on the web|online|web search)\b|search the web/.test(asked)) return "assistant-research";
  if (/look (it )?up|look through|check my notes|search my notes/.test(asked) && /\bcards?\b/.test(asked)) {
    return "assistant-multi-1";
  }
  if (/\b(exam|midterm)\b/.test(asked) && /\b(plan|add|schedule|create|set|put|draft)\b/.test(asked)) {
    return "assistant-exam";
  }
  if (/flash\s?cards?|\bcards\b/.test(asked)) return "assistant-cards";
  if (/\b(quiz|questions?)\b/.test(asked)) return "assistant-quiz";
  if (/\b(practice|practise|drill)\b/.test(asked)) return "assistant-practice";
  if (/\b(notes?|summary|study sheet)\b/.test(asked) && /\b(make|write|add|create|draft)\b/.test(asked)) {
    return "assistant-note";
  }
  if (/\b(open|show me|go to)\b.*\b(progress|sky|library|today)\b/.test(asked)) return "assistant-open";
  return "assistant-answer";
}

/** Web research in MOCK mode: one canned summary, or the error when the topic asks for it. */
export function researchFixture(topic: string): string {
  return topic.toLowerCase().includes("#fail") ? "research-error" : "research-mitosis";
}

/** A test hook, MOCK mode only: `X-Cramless-Fixture: grade-incorrect` (or `tutor-error`, …) picks another canned
 * reply of the same route, so the app can show every state against a local relay. */
export function fixtureOverride(req: Request, route: string): string | null {
  const asked = req.headers.get("x-cramless-fixture")?.trim();
  if (!asked || FIXTURES[asked] === undefined || asked.startsWith("requests/")) return null;
  if (route === "grade") return asked.startsWith("grade-") ? asked : null;
  if (route === "tutor") return asked.startsWith("tutor-") ? asked : null;
  if (route === "assistant") return asked.startsWith("assistant-") ? asked : null;
  if (route === "research") return asked.startsWith("research-") ? asked : null;
  return asked === MOCK_FIXTURE[route] ? asked : null;
}
