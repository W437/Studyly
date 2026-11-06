// What the relay does to a model's reply about an exam's scope, before the app sees it: a syllabus read and the check of a date heard
// in a lecture. Ids and dates must come from the request; everything else is tidied, never invented. The app checks again what it can
// see for itself (a date's quote on the page, a day within reach), because a date is the one thing a student would act on unread.

import type {
  ExamMentionRequest,
  ExamMentionVerdict,
  LastLookRequest,
  LastLookSentence,
  PageInput,
  SyllabusExam,
  SyllabusFormat,
  SyllabusRequest,
  SyllabusTopic,
} from "./contract.ts";
import { lineIdsOf } from "./items.ts";

const text = (s: unknown) => (typeof s === "string" ? s.trim() : "");

/** A real day, as yyyy-MM-dd. */
export function isRealDay(day: unknown): day is string {
  if (typeof day !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(day)) return false;
  const at = new Date(`${day}T00:00:00Z`);
  return !Number.isNaN(at.getTime()) && at.toISOString().slice(0, 10) === day;
}

const isClockTime = (time: unknown): time is string =>
  typeof time === "string" && /^([01]\d|2[0-3]):[0-5]\d$/.test(time);

const inRange = (n: unknown, low: number, high: number): number | undefined =>
  typeof n === "number" && Number.isInteger(n) && n >= low && n <= high ? n : undefined;

function cleanFormat(raw: SyllabusFormat | undefined): SyllabusFormat {
  const out: SyllabusFormat = {};
  if (typeof raw?.multipleChoice === "boolean") out.multipleChoice = raw.multipleChoice;
  if (typeof raw?.shortAnswer === "boolean") out.shortAnswer = raw.shortAnswer;
  if (typeof raw?.essay === "boolean") out.essay = raw.essay;
  const count = inRange(raw?.questionCount, 1, 500);
  if (count !== undefined) out.questionCount = count;
  const minutes = inRange(raw?.minutes, 1, 600);
  if (minutes !== undefined) out.minutes = minutes;
  const notes = text(raw?.notes).slice(0, 200);
  if (notes) out.notes = notes;
  return out;
}

function cleanTopics(
  raw: SyllabusTopic[] | undefined,
  known: ReadonlySet<string>,
  lines: ReadonlySet<string>,
): SyllabusTopic[] {
  const seen = new Set<string>();
  const out: SyllabusTopic[] = [];
  for (const topic of raw ?? []) {
    const name = text(topic.name).slice(0, 120);
    const key = name.toLowerCase();
    if (!name || seen.has(key)) continue;
    seen.add(key);
    const id = text(topic.topicId);
    out.push({
      name,
      ...(known.has(id) ? { topicId: id } : {}),
      lineIds: [...new Set((topic.lineIds ?? []).map(text).filter((l) => lines.has(l)))],
    });
    if (out.length === 60) break;
  }
  return out;
}

/** At most 4 exams. A topic id or a line id the request didn't have goes, a date that isn't a day from today on goes (with its quote and
 * time), names are unique within an exam, and an exam left with no topics and no date says nothing, so it goes too. */
export function sanitizeSyllabus(raw: SyllabusExam[] | undefined, req: SyllabusRequest): SyllabusExam[] {
  const known = new Set(req.topics.map((t) => t.id));
  const lines = lineIdsOf(req.pages);
  const out: SyllabusExam[] = [];
  for (const exam of raw ?? []) {
    const topics = cleanTopics(exam.topics, known, lines);
    const day = isRealDay(exam.date) && exam.date >= req.today ? exam.date : undefined;
    if (topics.length === 0 && !day) continue;
    const dateQuote = text(exam.dateQuote);
    const formatQuote = text(exam.formatQuote);
    out.push({
      title: text(exam.title).slice(0, 120) || "Exam",
      ...(day ? { date: day } : {}),
      ...(day && isClockTime(exam.time) ? { time: exam.time } : {}),
      ...(day && dateQuote ? { dateQuote } : {}),
      topics,
      format: cleanFormat(exam.format),
      ...(formatQuote ? { formatQuote } : {}),
    });
    if (out.length === 4) break;
  }
  return out;
}

/** The longest last-look sentence kept, in characters. */
export const LAST_LOOK_MAX_SENTENCE = 300;

/** One verdict per mention the request had. A date has to be one the app's detector read from that sentence (the model may choose
 * among them, never make one up), a topic has to be one of the course's, in the course's spelling. */
export function sanitizeExamMentions(
  raw: ExamMentionVerdict[] | undefined,
  req: ExamMentionRequest,
): ExamMentionVerdict[] {
  const asked = new Map(req.mentions.map((m) => [m.id, m]));
  const topicNames = new Map(req.topics.map((t) => [t.trim().toLowerCase(), t]));
  const seen = new Set<string>();
  const out: ExamMentionVerdict[] = [];
  for (const verdict of raw ?? []) {
    const id = text(verdict.id);
    const mention = asked.get(id);
    if (!mention || seen.has(id)) continue;
    seen.add(id);
    const isExam = verdict.isExam === true;
    const day = isExam && mention.candidates.includes(text(verdict.date)) ? text(verdict.date) : undefined;
    const title = text(verdict.title).slice(0, 120);
    const scopePhrase = text(verdict.scopePhrase).slice(0, 200);
    const topics = [...new Set((verdict.topics ?? []).map((t) => topicNames.get(text(t).toLowerCase())))]
      .filter((t): t is string => t !== undefined);
    out.push({
      id,
      isExam,
      ...(isExam && title ? { title } : {}),
      ...(day ? { date: day } : {}),
      ...(day && isClockTime(verdict.time) ? { time: verdict.time } : {}),
      ...(isExam && scopePhrase ? { scopePhrase } : {}),
      topics: isExam ? topics : [],
    });
  }
  return out;
}

/** One sentence per idea the request had, on one line and short enough to read in a breath. An empty sentence goes (the app says the question
 * and its answer instead), and so does any that runs far over: a sentence that long has stopped being one idea. */
export function sanitizeLastLook(raw: LastLookSentence[] | undefined, req: LastLookRequest): LastLookSentence[] {
  const asked = new Set(req.ideas.map((idea) => idea.id));
  const seen = new Set<string>();
  const out: LastLookSentence[] = [];
  for (const entry of raw ?? []) {
    const id = text(entry.id);
    if (!asked.has(id) || seen.has(id)) continue;
    const sentence = text(entry.sentence).replace(/\s+/g, " ");
    if (!sentence || sentence.length > LAST_LOOK_MAX_SENTENCE) continue;
    seen.add(id);
    out.push({ id, sentence });
  }
  return out;
}

/** The pages as text alone: a syllabus scan never sends a photo, and one a request carries anyway is not passed on. */
export const textOnly = (pages: PageInput[]): PageInput[] => pages.map(({ image: _image, ...page }) => page);
