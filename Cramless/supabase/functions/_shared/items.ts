// What the relay does to a model's reply before the app sees it. The rule that matters most: an item whose
// anchors aren't real line or segment ids from the request is dropped (it can't be shown against its source),
// and so is an item that isn't well formed for its kind. Everything else is tidied (trimmed text, clamped numbers,
// unique ids), never invented.

import type {
  CheckVerdict,
  ConfusionOut,
  GeneratedItem,
  GeneratedTopic,
  GradeHit,
  GradeRequest,
  GradeResponse,
  ItemKind,
  KeyIdea,
  LectureExamFlag,
  LectureSection,
  LineInput,
  PageInput,
} from "./contract.ts";

export interface ItemRules {
  /** The ids an anchor may name: the request's line or segment ids (empty when the request has none). */
  validAnchors: ReadonlySet<string>;
  /** Grounded items need at least one anchor (generate, lecture). */
  requireAnchors: boolean;
  /** An anchor not in validAnchors drops the item ("drop"), or is removed from it ("strip": confusions, whose
   * request carries no line ids at all). */
  unknownAnchor: "drop" | "strip";
  /** The formats the request asked for; others are dropped. */
  formats?: ReadonlySet<ItemKind>;
  /** At most this many items. */
  maxItems?: number;
}

export const lineIdsOf = (pages: PageInput[]): Set<string> => new Set(pages.flatMap((p) => p.lines.map((l) => l.id)));

const clamp01 = (n: unknown, fallback: number) =>
  typeof n === "number" && Number.isFinite(n) ? Math.min(1, Math.max(0, n)) : fallback;

const text = (s: unknown) => (typeof s === "string" ? s.trim() : "");

function cleanKeyIdeas(ideas: KeyIdea[]): KeyIdea[] {
  const seen = new Set<string>();
  const out: KeyIdea[] = [];
  for (const idea of ideas) {
    const id = text(idea.id);
    const label = text(idea.label);
    if (!id || !label || seen.has(id)) continue;
    seen.add(id);
    const terms = [...new Set(idea.terms.map((t) => text(t).toLowerCase()).filter((t) => t.length > 0))];
    out.push({ id, label, terms });
  }
  return out;
}

const BLANK = /\{\{([^{}]+)\}\}/g;

/** One item, cleaned, or null when it can't be kept. */
export function sanitizeItem(raw: GeneratedItem, rules: ItemRules): GeneratedItem | null {
  const kind = raw.kind;
  if (rules.formats && !rules.formats.has(kind)) return null;
  const prompt = text(raw.prompt);
  const answer = text(raw.answer);
  if (!prompt) return null;

  let anchors = [...new Set((raw.anchors ?? []).map(text).filter((a) => a.length > 0))];
  const unknown = anchors.filter((a) => !rules.validAnchors.has(a));
  if (unknown.length > 0) {
    if (rules.unknownAnchor === "drop") return null;
    anchors = anchors.filter((a) => rules.validAnchors.has(a));
  }
  if (rules.requireAnchors && anchors.length === 0) return null;

  const item: GeneratedItem = {
    id: text(raw.id) || "item",
    kind,
    topic: text(raw.topic),
    prompt,
    answer,
    explanation: text(raw.explanation),
    keyIdeas: cleanKeyIdeas(raw.keyIdeas ?? []),
    choices: [],
    anchors,
    difficulty: clamp01(raw.difficulty, 0.5),
  };

  switch (kind) {
    case "recall":
    case "apply":
      if (!answer || item.keyIdeas.length === 0) return null;
      break;
    case "mcq": {
      const choices = (raw.choices ?? [])
        .map((c) => ({ text: text(c.text), correct: c.correct === true, why: text(c.why) }))
        .filter((c) => c.text.length > 0);
      const texts = new Set(choices.map((c) => c.text.toLowerCase()));
      const correct = choices.filter((c) => c.correct);
      if (choices.length < 2 || choices.length > 6 || correct.length !== 1 || texts.size !== choices.length) {
        return null;
      }
      item.choices = choices.map((c) => (c.why ? c : { text: c.text, correct: c.correct }));
      item.answer = correct[0].text;
      break;
    }
    case "cloze": {
      const clozeText = text(raw.cloze?.text);
      const blanks = [...clozeText.matchAll(BLANK)].map((m) => m[1].trim());
      if (blanks.length === 0 || blanks.some((b) => b.length === 0)) return null;
      const alternates = blanks.map((
        _,
        i,
      ) => [...new Set((raw.cloze?.alternates?.[i] ?? []).map(text).filter((a) => a.length > 0))]);
      item.cloze = { text: clozeText, alternates };
      if (!item.answer) item.answer = blanks.join(", ");
      break;
    }
    case "diagram": {
      const labels = [...new Set((raw.diagramLabels ?? []).map(text).filter((l) => l.length > 0))];
      if (labels.length === 0 || labels.some((l) => !rules.validAnchors.has(l))) return null;
      item.diagramLabels = labels;
      item.anchors = [...new Set([...item.anchors, ...labels])];
      break;
    }
    case "flashcard":
      if (!answer) return null;
      break;
  }
  return item;
}

/** A list of items, cleaned, with unique ids, at most maxItems. */
export function sanitizeItems(raw: GeneratedItem[], rules: ItemRules): GeneratedItem[] {
  const out: GeneratedItem[] = [];
  const ids = new Set<string>();
  for (const candidate of raw ?? []) {
    if (rules.maxItems !== undefined && out.length >= rules.maxItems) break;
    const item = sanitizeItem(candidate, rules);
    if (!item) continue;
    let id = item.id;
    for (let n = 2; ids.has(id); n++) id = `${item.id}-${n}`;
    ids.add(id);
    out.push({ ...item, id });
  }
  return out;
}

/** Topics that are named and unique; the ones the kept items use come first. */
export function sanitizeTopics(raw: GeneratedTopic[], items: GeneratedItem[]): GeneratedTopic[] {
  const seen = new Set<string>();
  const topics: GeneratedTopic[] = [];
  for (const t of raw ?? []) {
    const name = text(t.name);
    if (!name || seen.has(name.toLowerCase())) continue;
    seen.add(name.toLowerCase());
    topics.push({ name, summary: text(t.summary) });
  }
  for (const item of items) {
    if (item.topic && !seen.has(item.topic.toLowerCase())) {
      seen.add(item.topic.toLowerCase());
      topics.push({ name: item.topic, summary: "" });
    }
  }
  return topics;
}

/** The check's verdicts, one per request item, in request order. Items whose anchors weren't real were never
 * sent to the model and are unsupported; an item the model skipped is unsupported too (the check is strict). */
export function sanitizeVerdicts(
  items: GeneratedItem[],
  modelVerdicts: CheckVerdict[],
  ungrounded: ReadonlySet<string>,
): CheckVerdict[] {
  const byId = new Map<string, CheckVerdict>();
  for (const v of modelVerdicts ?? []) if (!byId.has(v.id)) byId.set(v.id, v);
  return items.map((item): CheckVerdict => {
    if (ungrounded.has(item.id)) {
      return { id: item.id, verdict: "unsupported", reason: "Its source lines weren't sent with the check." };
    }
    const v = byId.get(item.id);
    if (!v) return { id: item.id, verdict: "unsupported", reason: "The check didn't return a verdict for it." };
    const reason = text(v.reason);
    if (v.verdict === "fixed") {
      const fixedAnswer = text(v.fixedAnswer);
      const fixedChoices = (v.fixedChoices ?? [])
        .map((c) => ({ text: text(c.text), correct: c.correct === true, ...(text(c.why) ? { why: text(c.why) } : {}) }))
        .filter((c) => c.text.length > 0);
      const choicesOk = fixedChoices.length >= 2 && fixedChoices.filter((c) => c.correct).length === 1;
      if (!fixedAnswer && !choicesOk) return { id: item.id, verdict: "supported", reason };
      return {
        id: item.id,
        verdict: "fixed",
        reason,
        ...(fixedAnswer ? { fixedAnswer } : {}),
        ...(choicesOk ? { fixedChoices } : {}),
      };
    }
    return { id: item.id, verdict: v.verdict === "supported" ? "supported" : "unsupported", reason };
  });
}

/** Hits name real key ideas (one hit per idea); `missing` is every other idea; numbers in 0…1. The app highlights
 * a quote only where it finds it verbatim in the answer. */
export function sanitizeGrade(
  reply: Omit<GradeResponse, "model">,
  request: GradeRequest,
): Omit<GradeResponse, "model"> {
  const ideas = new Set(request.keyIdeas.map((k) => k.id));
  const hits: GradeHit[] = [];
  const hit = new Set<string>();
  for (const h of reply.hits ?? []) {
    const ideaId = text(h.ideaId);
    const quote = text(h.quote);
    if (!ideas.has(ideaId) || hit.has(ideaId) || !quote) continue;
    hit.add(ideaId);
    hits.push({ ideaId, quote });
  }
  const verdict = reply.verdict === "correct" || reply.verdict === "partial" ? reply.verdict : "incorrect";
  return {
    score: clamp01(reply.score, 0),
    verdict,
    confidence: clamp01(reply.confidence, 0.5),
    hits,
    missing: request.keyIdeas.map((k) => k.id).filter((id) => !hit.has(id)),
    feedback: text(reply.feedback),
    fix: text(reply.fix),
  };
}

/** Confusions explain real mistakes (item ids from the request); their practice questions carry no anchors. */
export function sanitizeConfusions(raw: ConfusionOut[], mistakeIds: ReadonlySet<string>): ConfusionOut[] {
  const out: ConfusionOut[] = [];
  for (const c of raw ?? []) {
    const itemIds = [...new Set((c.itemIds ?? []).map(text).filter((id) => mistakeIds.has(id)))];
    const name = text(c.name);
    if (!name || itemIds.length === 0) continue;
    out.push({
      name,
      explanation: text(c.explanation),
      itemIds,
      lesson: text(c.lesson),
      questions: sanitizeItems(c.questions ?? [], {
        validAnchors: new Set(),
        requireAnchors: false,
        unknownAnchor: "strip",
        formats: new Set<ItemKind>(["mcq", "recall", "cloze", "flashcard"]),
        maxItems: 4,
      }),
    });
  }
  return out.slice(0, 3);
}

/** Lecture sections and flags inside the recording, in order. */
export function sanitizeSections(raw: LectureSection[], duration: number): LectureSection[] {
  return (raw ?? [])
    .map((s, i) => {
      const start = Math.max(0, Math.min(duration, Number(s.start) || 0));
      const end = Math.max(start, Math.min(duration, Number(s.end) || start));
      return {
        id: text(s.id) || `n${i + 1}`,
        title: text(s.title),
        start,
        end,
        bullets: (s.bullets ?? []).map(text).filter((b) => b.length > 0),
      };
    })
    .filter((s) => s.title.length > 0)
    .sort((a, b) => a.start - b.start);
}

export function sanitizeExamFlags(raw: LectureExamFlag[], duration: number): LectureExamFlag[] {
  return (raw ?? [])
    .map((f) => ({ time: Math.max(0, Math.min(duration, Number(f.time) || 0)), text: text(f.text), why: text(f.why) }))
    .filter((f) => f.text.length > 0)
    .sort((a, b) => a.time - b.time);
}

/** How many exam-relevant ideas a lecture's questions left out, as a whole number from 1 to 99. Nothing when the model said
 * none (or said something that is not a number): the field is left out of the reply, as the contract's other optional fields
 * are. */
export function sanitizeLeftOut(raw: unknown): number | undefined {
  if (typeof raw !== "number" || !Number.isFinite(raw)) return undefined;
  const n = Math.min(99, Math.round(raw));
  return n > 0 ? n : undefined;
}

/** Transcribed lines with the relay's own ids (p<page>.c<n>): cloud transcription has no geometry. */
export function sanitizeLines(raw: LineInput[], page: number): LineInput[] {
  return (raw ?? [])
    .map((l) => text(l.text))
    .filter((t) => t.length > 0)
    .slice(0, 400)
    .map((t, i) => ({ id: `p${page}.c${i}`, text: t }));
}
