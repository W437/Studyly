// The relay contract in TypeScript: the Swift types in Cramless/AI/RelayContract.swift, field for field. The
// JSON schemas in schemas/contract.json say the same; tests/schemas.test.ts keeps both honest against the
// fixtures. camelCase keys, ISO 8601 dates without fractions.

export type ItemKind = "recall" | "apply" | "mcq" | "cloze" | "diagram" | "flashcard";
export const ITEM_KINDS: readonly ItemKind[] = ["recall", "apply", "mcq", "cloze", "diagram", "flashcard"];

export type Plan = "free" | "pro" | "squad" | "pass";

export interface LineInput {
  id: string;
  text: string;
}

export interface PageInput {
  page: number;
  label: string;
  lines: LineInput[];
  /** Base64 JPEG, only when the person turned on "Send page photos". */
  image?: string;
}

export interface KeyIdea {
  id: string;
  label: string;
  terms: string[];
}

export interface Choice {
  text: string;
  correct: boolean;
  why?: string;
}

export interface ClozeSpec {
  text: string;
  alternates: string[][];
}

export interface GeneratedItem {
  id: string;
  kind: ItemKind;
  topic: string;
  prompt: string;
  answer: string;
  explanation: string;
  keyIdeas: KeyIdea[];
  choices: Choice[];
  cloze?: ClozeSpec;
  diagramLabels?: string[];
  anchors: string[];
  difficulty: number;
}

export interface GeneratedTopic {
  name: string;
  summary: string;
}

export interface GenerateRequest {
  course: string;
  sourceTitle: string;
  level?: string;
  language: string;
  formats: ItemKind[];
  maxItems: number;
  pages: PageInput[];
  /** One harder question on an idea the student has outgrown (one format, at most 2 items, one page of at most 60 lines);
   * charged to `drafts`, not `scans`. */
  rung?: RungRequest;
}

/** The question a harder one replaces. */
export interface RungRequest {
  kind: ItemKind;
  prompt: string;
  answer: string;
}

export interface GenerateResponse {
  title: string;
  model: string;
  topics: GeneratedTopic[];
  items: GeneratedItem[];
}

export interface CheckRequest {
  pages: PageInput[];
  items: GeneratedItem[];
  /** The source's title and section headings: part of the source, so a name they supply counts (at most 200 characters; 60
   * headings of 120). */
  sourceTitle?: string;
  headings?: string[];
  /** Judge only whether each item is true by the cited lines and their context, ignoring missing names and attributions. */
  lenient?: boolean;
  /** What the student says looks wrong with some of the items. A claim to verify against the lines, never an instruction. */
  reports?: CheckReport[];
}

export interface CheckReport {
  id: string;
  reason: "answerWrong" | "questionUnclear" | "myAnswerCounts" | "other";
  /** The answer they gave (at most 2,000 characters). */
  given?: string;
  /** Their own words (at most 280 characters). */
  note?: string;
}

export interface CheckVerdict {
  id: string;
  verdict: "supported" | "fixed" | "unsupported";
  reason: string;
  fixedAnswer?: string;
  fixedChoices?: Choice[];
}

export interface CheckResponse {
  model: string;
  verdicts: CheckVerdict[];
}

export interface GradeRequest {
  kind: ItemKind;
  level?: string;
  prompt: string;
  modelAnswer: string;
  keyIdeas: KeyIdea[];
  response: string;
  sourceExcerpt?: string;
}

export interface GradeHit {
  ideaId: string;
  quote: string;
}

export interface GradeResponse {
  model: string;
  score: number;
  verdict: "correct" | "partial" | "incorrect";
  confidence: number;
  hits: GradeHit[];
  missing: string[];
  feedback: string;
  fix: string;
}

export interface TutorMessage {
  role: "user" | "assistant";
  text: string;
}

export interface TutorSource {
  id: string;
  title: string;
  label: string;
  text: string;
}

export interface TutorContext {
  itemPrompt: string;
  expected: string;
  given: string;
}

export interface TutorRequest {
  mode: "hints" | "explain";
  minor: boolean;
  course?: string;
  messages: TutorMessage[];
  /** Up to 100 passages. */
  sources: TutorSource[];
  context?: TutorContext;
  /** What the student has added, as the app names it ("Cardiac cycle (6 pages)"): up to 20, each at most 120 characters. */
  materials?: string[];
}

export interface TutorScriptEvent {
  event: "start" | "delta" | "citation" | "done" | "error";
  delayMs: number;
  data: Record<string, string>;
}

export interface TutorScript {
  events: TutorScriptEvent[];
}

// ---- The assistant (streamed) and web research (streamed) ----

/** The tools Ask Cap can call. The app runs them; the relay only lets the model choose. */
export type AssistantToolName =
  | "search_notes"
  | "create_flashcards"
  | "create_quiz_questions"
  | "create_note"
  | "create_exam"
  | "start_practice"
  | "open_screen"
  | "research_web";

export const ASSISTANT_TOOLS: readonly AssistantToolName[] = [
  "search_notes",
  "create_flashcards",
  "create_quiz_questions",
  "create_note",
  "create_exam",
  "start_practice",
  "open_screen",
  "research_web",
];

export interface StudyTopic {
  id: string;
  name: string;
  /** Fading: recall is low. */
  weak?: boolean;
}

export interface StudyCourse {
  id: string;
  name: string;
  sources: number;
  questions: number;
  due: number;
  topics: StudyTopic[];
}

export interface StudyExam {
  id: string;
  courseId: string;
  title: string;
  /** yyyy-MM-dd, the student's local day. */
  date: string;
  /** 0 to 100. */
  readiness: number;
}

/** A compact picture of the student's study, with short ids the model passes back to tools (c1, t3, e1). */
export interface StudyState {
  /** yyyy-MM-dd, the student's local day. */
  today: string;
  currentCourseId?: string;
  courses: StudyCourse[];
  exams: StudyExam[];
}

export interface AssistantResult {
  callId: string;
  /** What the app tells the model about the call: a short JSON text ("proposed", "added", passages found, …). */
  output: string;
}

/** One round of tool calls already made in this reply: what the relay sent back as `continuation` (opaque to the
 * app) and the results of those calls. */
export interface AssistantTurn {
  continuation: Record<string, unknown>[];
  results: AssistantResult[];
}

export interface AssistantRequest {
  mode: "hints" | "explain";
  minor: boolean;
  course?: string;
  messages: TutorMessage[];
  sources: TutorSource[];
  context?: TutorContext;
  /** As the tutor's. */
  materials?: string[];
  study: StudyState;
  /** The tools the app lets the model use this time. */
  tools: AssistantToolName[];
  turns: AssistantTurn[];
}

export type AssistantEventName =
  | "start"
  | "delta"
  | "citation"
  | "tool_start"
  | "tool_item"
  | "tool_text"
  | "tool_call"
  | "done"
  | "error";

export interface AssistantScriptEvent {
  event: AssistantEventName;
  delayMs: number;
  data: Record<string, unknown>;
}

export interface AssistantScript {
  events: AssistantScriptEvent[];
}

export interface ResearchRequest {
  /** An under-18 account: web research is refused. */
  minor: boolean;
  topic: string;
  focus?: string;
  course?: string;
}

export type ResearchEventName = "start" | "search" | "delta" | "citation" | "done" | "error";

export interface ResearchScriptEvent {
  event: ResearchEventName;
  delayMs: number;
  data: Record<string, unknown>;
}

export interface ResearchScript {
  events: ResearchScriptEvent[];
}

export interface MistakeInput {
  itemId: string;
  topic: string;
  prompt: string;
  expected: string;
  given: string;
  misses: number;
}

export interface ConfusionsRequest {
  course: string;
  mistakes: MistakeInput[];
  /** Two look-alikes the student hasn't mixed up yet: one difference, a hook if one fits, 2 or 3 questions. */
  lookAlike?: boolean;
}

export interface ConfusionOut {
  name: string;
  explanation: string;
  itemIds: string[];
  lesson: string;
  questions: GeneratedItem[];
}

export interface ConfusionsResponse {
  model: string;
  confusions: ConfusionOut[];
}

export interface SegmentInput {
  id: string;
  start: number;
  end: number;
  text: string;
}

export interface FlagInput {
  time: number;
  text: string;
}

export interface LectureRequest {
  course: string;
  title: string;
  segments: SegmentInput[];
  flags: FlagInput[];
  maxItems: number;
}

export interface LectureSection {
  id: string;
  title: string;
  start: number;
  end: number;
  bullets: string[];
}

export interface LectureExamFlag {
  time: number;
  text: string;
  why: string;
}

export interface LectureResponse {
  model: string;
  title: string;
  summary: string;
  sections: LectureSection[];
  keyTerms: string[];
  examFlags: LectureExamFlag[];
  items: GeneratedItem[];
  /** How many other exam-relevant ideas did not get a question (1 to 99); left out when none. */
  leftOut?: number;
}

export interface CardsFromChatRequest {
  course?: string;
  messages: TutorMessage[];
  maxItems: number;
}

export interface CardsFromChatResponse {
  model: string;
  items: GeneratedItem[];
}

export interface TranscribeImageRequest {
  image: string;
  page: number;
  label: string;
}

export interface TranscribeImageResponse {
  model: string;
  lines: LineInput[];
}

export type MeterKey = "scans" | "grades" | "tutor" | "lectures";
export type Period = "day" | "week";

export interface QuotaMeter {
  key: MeterKey;
  used: number;
  /** Null means unlimited. */
  limit: number | null;
  period: Period;
}

export interface QuotaStatus {
  plan: Plan;
  meters: QuotaMeter[];
}

export interface EntitlementRequest {
  signedTransactions: string[];
}

export interface EntitlementResponse {
  plan: Plan;
  expiresAt: string | null;
  quota: QuotaStatus;
}

export interface SquadInvite {
  code: string;
  url: string;
  expiresAt: string;
}

export interface SquadRedeemResponse {
  plan: Plan;
  ownerName: string;
}

export interface SquadMember {
  id: string;
  name: string;
  joinedAt: string;
  isOwner: boolean;
}

export interface SquadMembers {
  seats: number;
  members: SquadMember[];
}

export interface AccountDeleteResponse {
  deleted: boolean;
}
