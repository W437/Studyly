// The `ai` function: the relay the app's HTTP transport calls. One function, routed by path:
//   POST /ai/generate, /ai/check, /ai/grade, /ai/tutor (server-sent events), /ai/confusions, /ai/lecture,
//        /ai/cards-from-chat, /ai/transcribe-image, /ai/assistant (server-sent events: Ask Cap with tools),
//        /ai/research (server-sent events: web research, Pro)
//   GET  /ai/quota
// Every route checks the caller's Supabase session (anonymous users allowed), resolves their plan (an active
// entitlement or Squad membership), validates the body, meters the free quotas (scans, grades, tutor, lectures;
// a failed request gives its quota back) and answers in the contract's shapes and error envelope. MOCK mode
// (CRAMLESS_MOCK=1) answers with the fixtures; real mode calls Claude (Haiku 5.5, Sonnet 5.5 for grading `apply` and
// long answers, and for the tutor unless OPENAI_API_KEY puts the tutor on OpenAI) and cleans every reply (items must
// anchor to real line or segment ids).

import { type JsonResult, providerError } from "../_shared/anthropic.ts";
import { unauthorized } from "../_shared/auth.ts";
import type {
  AssistantRequest,
  AssistantScript,
  CardsFromChatRequest,
  CardsFromChatResponse,
  CheckRequest,
  CheckResponse,
  ConfusionsRequest,
  ConfusionsResponse,
  GenerateRequest,
  GenerateResponse,
  GradeRequest,
  GradeResponse,
  ItemKind,
  LectureRequest,
  LectureResponse,
  ResearchRequest,
  ResearchScript,
  TranscribeImageRequest,
  TranscribeImageResponse,
  TutorRequest,
  TutorScript,
} from "../_shared/contract.ts";
import {
  allowedTools,
  assistantInput,
  checkTurns,
  DRAFT_TOOLS,
  MAX_ROUNDS,
  toolDefinitions,
} from "../_shared/assistant.ts";
import { addUsage, costNano, formatUsd, HAIKU, SONNET, type Usage, ZERO_USAGE } from "../_shared/cost.ts";
import type { Deps } from "../_shared/deps.ts";
import { ApiError, badRequest, errorResponse, toApiError } from "../_shared/errors.ts";
import { json, methodNotAllowed, notFound, rawJson, readJson, routeOf } from "../_shared/http.ts";
import {
  lineIdsOf,
  sanitizeConfusions,
  sanitizeExamFlags,
  sanitizeGrade,
  sanitizeItems,
  sanitizeLines,
  sanitizeSections,
  sanitizeTopics,
  sanitizeVerdicts,
} from "../_shared/items.ts";
import { log } from "../_shared/log.ts";
import {
  assistantFixture,
  fixtureOverride,
  fixtureText,
  gradeFixture,
  MOCK_LATENCY_MS,
  researchFixture,
  tutorFixture,
} from "../_shared/mock.ts";
import {
  dailyCostError,
  enforcedLimit,
  isPaid,
  localMidnight,
  type Meter,
  METERS,
  PAGES_PER_SCAN,
  periodStart,
  quotaError,
  quotaStatus,
  SCAN_WINDOW_MINUTES,
  SHOWN_METERS,
  usageKeys,
} from "../_shared/plans.ts";
import {
  assistantSystem,
  cardsContent,
  checkContent,
  confusionsContent,
  generateContent,
  gradeContent,
  lectureContent,
  researchInput,
  researchSystem,
  systemFor,
  transcribeContent,
  tutorMessages,
  tutorSystem,
} from "../_shared/prompts.ts";
import { providerSchema, requireValid } from "../_shared/schemas.ts";
import { EventStream, type TutorEventData } from "../_shared/sse.ts";
import type { ScanKind, UserContext } from "../_shared/store.ts";
import type { Caller } from "../_shared/auth.ts";

type RouteName =
  | "generate"
  | "check"
  | "grade"
  | "tutor"
  | "confusions"
  | "lecture"
  | "cards-from-chat"
  | "transcribe-image"
  | "assistant"
  | "research"
  | "quota";

const KB = 1024;
const MB = 1024 * 1024;

const ROUTES: Record<RouteName, { method: "GET" | "POST"; schema?: string; maxBytes: number }> = {
  generate: { method: "POST", schema: "GenerateRequest", maxBytes: 24 * MB },
  check: { method: "POST", schema: "CheckRequest", maxBytes: 24 * MB },
  grade: { method: "POST", schema: "GradeRequest", maxBytes: 256 * KB },
  tutor: { method: "POST", schema: "TutorRequest", maxBytes: MB },
  confusions: { method: "POST", schema: "ConfusionsRequest", maxBytes: 512 * KB },
  lecture: { method: "POST", schema: "LectureRequest", maxBytes: 4 * MB },
  "cards-from-chat": { method: "POST", schema: "CardsFromChatRequest", maxBytes: MB },
  "transcribe-image": { method: "POST", schema: "TranscribeImageRequest", maxBytes: 12 * MB },
  assistant: { method: "POST", schema: "AssistantRequest", maxBytes: 2 * MB },
  research: { method: "POST", schema: "ResearchRequest", maxBytes: 16 * KB },
  quota: { method: "GET", maxBytes: 0 },
};

/** What one request did, for the log line and the ai_requests row. */
interface Meta {
  plan?: string;
  model?: string;
  mock?: boolean;
  usage?: Usage;
}

interface Ctx {
  req: Request;
  deps: Deps;
  route: RouteName;
  caller: Caller;
  user: UserContext;
  now: Date;
  meta: Meta;
  startedAt: number;
}

/** What a request consumed, so a failure can give it back. */
interface Charge {
  meter: Meter;
  period: string;
  scan?: { kind: ScanKind; pages: number; counted: boolean };
}

type ChargeSpec = { meter: Exclude<Meter, "scans"> } | { scan: ScanKind; pages: number };

async function consume(c: Ctx, spec: ChargeSpec): Promise<Charge> {
  const { store } = c.deps;
  const { plan, timeZone } = c.user;
  if ("scan" in spec) {
    const period = periodStart(METERS.scans.period, c.now, timeZone);
    const maxPages = isPaid(plan) ? PAGES_PER_SCAN.paid : PAGES_PER_SCAN.free;
    const r = await store.consumeScan(
      c.caller.userId,
      spec.scan,
      spec.pages,
      period,
      enforcedLimit("scans", plan),
      c.now,
      SCAN_WINDOW_MINUTES,
      maxPages,
    );
    if (!r.allowed) throw quotaError("scans", plan, r.used, c.now, timeZone);
    return { meter: "scans", period, scan: { kind: spec.scan, pages: spec.pages, counted: r.counted } };
  }
  const period = periodStart(METERS[spec.meter].period, c.now, timeZone);
  const r = await store.consume(c.caller.userId, spec.meter, period, 1, enforcedLimit(spec.meter, plan));
  if (!r.allowed) throw quotaError(spec.meter, plan, r.used, c.now, timeZone);
  return { meter: spec.meter, period };
}

async function refund(c: Ctx, charge: Charge): Promise<void> {
  try {
    if (charge.scan) {
      await c.deps.store.refundScan(
        c.caller.userId,
        charge.scan.kind,
        charge.scan.pages,
        charge.period,
        charge.scan.counted,
      );
    } else {
      await c.deps.store.refund(c.caller.userId, charge.meter, charge.period, 1);
    }
  } catch {
    // A failed refund must not hide the original error; the person loses one use at worst.
  }
}

/** The ai_requests row: route, model, tokens and cost, never content. Written after the response. */
function record(c: Ctx, model: string, usage: Usage, status: number): void {
  const cost = c.deps.env.mock ? 0n : costNano(model, usage);
  c.deps.background(
    c.deps.store.logRequest({
      userId: c.caller.userId,
      route: c.route,
      model,
      plan: c.user.plan,
      status,
      mock: c.deps.env.mock,
      inputTokens: usage.inputTokens,
      outputTokens: usage.outputTokens,
      cacheReadTokens: usage.cacheReadTokens,
      cacheWriteTokens: usage.cacheWriteTokens,
      costUsd: formatUsd(cost),
      latencyMs: Math.round(performance.now() - c.startedAt),
      createdAt: c.now.toISOString(),
    }).catch(() => {}),
  );
}

/** The day's cost cap: once the person's model calls today have cost the cap, no AI route answers until their local midnight. A safety
 * net under the meters, which count requests and not money. The sum is read from the request log, which is written after each
 * response, so what is still running isn't in it yet: a burst can pass the cap by what is in flight. MOCK replies cost nothing. If
 * the sum can't be read the request goes ahead (the meters still hold) and the failure is logged. */
async function checkDailyCost(c: Ctx): Promise<void> {
  const cap = c.deps.env.dailyCostCapNano;
  if (cap <= 0n || c.deps.env.mock) return;
  let spent: bigint;
  try {
    const since = localMidnight(periodStart("day", c.now, c.user.timeZone), c.user.timeZone);
    spent = await c.deps.store.spentSince(c.caller.userId, since);
  } catch {
    log({ fn: "ai", route: `/${c.route}`, status: 500, code: "daily_cost_check_failed", plan: c.user.plan });
    return;
  }
  if (spent >= cap) throw dailyCostError(c.user.plan, c.now, c.user.timeZone);
}

interface RealResult<T> {
  body: T;
  model: string;
  usage: Usage;
}

/** A JSON route: charge, then the fixture (MOCK) or the model, then the cleaned reply; a failure refunds. */
async function jsonRoute<T>(
  c: Ctx,
  charge: ChargeSpec | null,
  mockFixture: () => string,
  real: () => Promise<RealResult<T>>,
): Promise<Response> {
  const charged = charge ? await consume(c, charge) : null;
  try {
    if (c.deps.env.mock) {
      const fixture = fixtureOverride(c.req, c.route) ?? mockFixture();
      await c.deps.sleep(MOCK_LATENCY_MS[c.route] ?? 1000, c.req.signal);
      c.meta.model = "mock";
      record(c, "mock", ZERO_USAGE, 200);
      return rawJson(fixtureText(fixture));
    }
    const out = await real();
    c.meta.model = out.model;
    c.meta.usage = out.usage;
    record(c, out.model, out.usage, 200);
    return json(out.body);
  } catch (error) {
    if (charged) await refund(c, charged);
    const err = providerError(error);
    if (c.meta.model) record(c, c.meta.model, c.meta.usage ?? ZERO_USAGE, err.status);
    throw err;
  }
}

function call<T>(c: Ctx, result: JsonResult<T>): JsonResult<T> {
  c.meta.model = result.model;
  c.meta.usage = addUsage(c.meta.usage ?? ZERO_USAGE, result.usage);
  return result;
}

// ---- Routes ----

async function generate(c: Ctx, body: GenerateRequest): Promise<Response> {
  const max = isPaid(c.user.plan) ? PAGES_PER_SCAN.paid : PAGES_PER_SCAN.free;
  if (body.pages.length > max) {
    if (!isPaid(c.user.plan)) {
      throw new ApiError(
        "entitlement_required",
        `Scans of more than ${PAGES_PER_SCAN.free} pages are part of Capling Pro. Split it into smaller scans, or upgrade.`,
      );
    }
    throw badRequest(`One scan holds up to ${max} pages.`, 413);
  }
  if (body.pages.every((p) => p.lines.length === 0 && !p.image)) throw badRequest("These pages have no text yet.");
  return await jsonRoute<GenerateResponse>(
    c,
    { scan: "generate", pages: body.pages.length },
    () => "generate",
    async () => {
      c.meta.model = HAIKU;
      const res = call(
        c,
        await c.deps.provider.json<Omit<GenerateResponse, "model">>({
          model: HAIKU,
          effort: "medium",
          maxTokens: 16_000,
          system: systemFor("generate"),
          content: generateContent(body),
          schema: providerSchema("GenerateResponse"),
          signal: c.req.signal,
        }),
      );
      const items = sanitizeItems(res.value.items, {
        validAnchors: lineIdsOf(body.pages),
        requireAnchors: true,
        unknownAnchor: "drop",
        formats: new Set<ItemKind>(body.formats),
        maxItems: body.maxItems,
      });
      if (items.length === 0) {
        throw new ApiError("upstream", "Cap couldn't write questions from these pages. Try a clearer scan.", {}, 502);
      }
      return {
        body: {
          title: res.value.title.trim() || body.sourceTitle,
          model: res.model,
          topics: sanitizeTopics(res.value.topics, items),
          items,
        },
        model: res.model,
        usage: c.meta.usage ?? res.usage,
      };
    },
  );
}

async function check(c: Ctx, body: CheckRequest): Promise<Response> {
  return await jsonRoute<CheckResponse>(c, { meter: "extras" }, () => "check", async () => {
    const lineIds = lineIdsOf(body.pages);
    const seen = new Set<string>();
    const items = body.items.filter((i) => !seen.has(i.id) && seen.add(i.id));
    const ungrounded = new Set(
      items.filter((i) => !i.anchors?.length || i.anchors.some((a) => !lineIds.has(a))).map((i) => i.id),
    );
    const grounded = items.filter((i) => !ungrounded.has(i.id));
    if (grounded.length === 0) {
      return {
        body: { model: "relay", verdicts: sanitizeVerdicts(items, [], ungrounded) },
        model: "relay",
        usage: ZERO_USAGE,
      };
    }
    c.meta.model = HAIKU;
    const res = call(
      c,
      await c.deps.provider.json<Omit<CheckResponse, "model">>({
        model: HAIKU,
        effort: "medium",
        maxTokens: 12_000,
        system: systemFor("check"),
        content: checkContent(body.pages, grounded),
        schema: providerSchema("CheckResponse"),
        signal: c.req.signal,
      }),
    );
    return {
      body: { model: res.model, verdicts: sanitizeVerdicts(items, res.value.verdicts, ungrounded) },
      model: res.model,
      usage: res.usage,
    };
  });
}

/** Long answers and `apply` questions are graded by Claude Sonnet 5.5; the rest by Claude Haiku 5.5. */
export function gradeModel(body: GradeRequest): string {
  return body.kind === "apply" || body.response.length > 700 ? SONNET : HAIKU;
}

async function grade(c: Ctx, body: GradeRequest): Promise<Response> {
  if (!c.deps.env.mock && body.response.trim().length === 0) {
    // Nothing to grade: no model call and no quota.
    return json(
      {
        model: "relay",
        score: 0,
        verdict: "incorrect",
        confidence: 1,
        hits: [],
        missing: body.keyIdeas.map((k) => k.id),
        feedback: "There's no answer to grade yet. Give it a go in your own words.",
        fix: "",
      } satisfies GradeResponse,
    );
  }
  return await jsonRoute<GradeResponse>(c, { meter: "grades" }, () => gradeFixture(body), async () => {
    const model = gradeModel(body);
    const sonnet = model === SONNET;
    c.meta.model = model;
    const res = call(
      c,
      await c.deps.provider.json<Omit<GradeResponse, "model">>({
        model,
        effort: sonnet ? "medium" : "low",
        maxTokens: sonnet ? 8_000 : 4_000,
        system: systemFor("grade"),
        content: gradeContent(body),
        schema: providerSchema("GradeResponse"),
        signal: c.req.signal,
      }),
    );
    return { body: { model: res.model, ...sanitizeGrade(res.value, body) }, model: res.model, usage: res.usage };
  });
}

async function confusions(c: Ctx, body: ConfusionsRequest): Promise<Response> {
  return await jsonRoute<ConfusionsResponse>(c, { meter: "extras" }, () => "confusions", async () => {
    c.meta.model = HAIKU;
    const res = call(
      c,
      await c.deps.provider.json<Omit<ConfusionsResponse, "model">>({
        model: HAIKU,
        effort: "low",
        maxTokens: 10_000,
        system: systemFor("confusions"),
        content: confusionsContent(body),
        schema: providerSchema("ConfusionsResponse"),
        signal: c.req.signal,
      }),
    );
    const ids = new Set(body.mistakes.map((m) => m.itemId));
    return {
      body: { model: res.model, confusions: sanitizeConfusions(res.value.confusions, ids) },
      model: res.model,
      usage: res.usage,
    };
  });
}

async function lecture(c: Ctx, body: LectureRequest): Promise<Response> {
  return await jsonRoute<LectureResponse>(c, { meter: "lectures" }, () => "lecture", async () => {
    c.meta.model = HAIKU;
    const res = call(
      c,
      await c.deps.provider.json<Omit<LectureResponse, "model">>({
        model: HAIKU,
        effort: "medium",
        maxTokens: 16_000,
        system: systemFor("lecture"),
        content: lectureContent(body),
        schema: providerSchema("LectureResponse"),
        signal: c.req.signal,
      }),
    );
    const duration = Math.max(0, ...body.segments.map((s) => s.end));
    const items = sanitizeItems(res.value.items, {
      validAnchors: new Set(body.segments.map((s) => s.id)),
      requireAnchors: true,
      unknownAnchor: "drop",
      formats: new Set<ItemKind>(["recall", "apply", "mcq", "cloze", "flashcard"]),
      maxItems: body.maxItems,
    });
    const keyTerms = [...new Set(res.value.keyTerms.map((t) => t.trim()).filter((t) => t.length > 0))].slice(0, 20);
    return {
      body: {
        model: res.model,
        title: res.value.title.trim() || body.title,
        summary: res.value.summary.trim(),
        sections: sanitizeSections(res.value.sections, duration),
        keyTerms,
        examFlags: sanitizeExamFlags(res.value.examFlags, duration),
        items,
      },
      model: res.model,
      usage: res.usage,
    };
  });
}

async function cardsFromChat(c: Ctx, body: CardsFromChatRequest): Promise<Response> {
  return await jsonRoute<CardsFromChatResponse>(c, { meter: "extras" }, () => "cards-from-chat", async () => {
    c.meta.model = HAIKU;
    const res = call(
      c,
      await c.deps.provider.json<Omit<CardsFromChatResponse, "model">>({
        model: HAIKU,
        effort: "low",
        maxTokens: 6_000,
        system: systemFor("cards"),
        content: cardsContent(body),
        schema: providerSchema("CardsFromChatResponse"),
        signal: c.req.signal,
      }),
    );
    const items = sanitizeItems(res.value.items, {
      validAnchors: new Set(),
      requireAnchors: false,
      unknownAnchor: "drop",
      formats: new Set<ItemKind>(["flashcard", "mcq", "recall", "cloze"]),
      maxItems: body.maxItems,
    });
    return { body: { model: res.model, items }, model: res.model, usage: res.usage };
  });
}

async function transcribeImage(c: Ctx, body: TranscribeImageRequest): Promise<Response> {
  return await jsonRoute<TranscribeImageResponse>(
    c,
    { scan: "transcribe", pages: 1 },
    () => "transcribe-image",
    async () => {
      c.meta.model = HAIKU;
      const res = call(
        c,
        await c.deps.provider.json<Omit<TranscribeImageResponse, "model">>({
          model: HAIKU,
          effort: "low",
          maxTokens: 6_000,
          system: systemFor("transcribe"),
          content: transcribeContent(body),
          schema: providerSchema("TranscribeImageResponse"),
          signal: c.req.signal,
        }),
      );
      return {
        body: { model: res.model, lines: sanitizeLines(res.value.lines, body.page) },
        model: res.model,
        usage: res.usage,
      };
    },
  );
}

// ---- The tutor (server-sent events) ----

async function tutor(c: Ctx, body: TutorRequest): Promise<Response> {
  if (body.messages[body.messages.length - 1].role !== "user") {
    throw badRequest("The last message must be the student's.");
  }
  const ids = new Set<string>();
  body.sources = body.sources.filter((s) => !ids.has(s.id) && ids.add(s.id));
  const charge = await consume(c, { meter: "tutor" });

  const stream = new EventStream(c.deps.pingIntervalMs);
  const abort = new AbortController();
  stream.onCancel(() => abort.abort());
  c.req.signal?.addEventListener("abort", () => abort.abort(), { once: true });
  const run = c.deps.env.mock
    ? mockTutor(c, body, stream, abort.signal, charge)
    : realTutor(c, body, stream, abort.signal, charge);
  c.deps.background(run);
  return stream.response;
}

async function mockTutor(c: Ctx, body: TutorRequest, stream: EventStream, signal: AbortSignal, charge: Charge) {
  const name = fixtureOverride(c.req, "tutor") ?? tutorFixture(body);
  const script = JSON.parse(fixtureText(name)) as TutorScript;
  let sentDelta = false;
  let status = 200;
  try {
    for (const event of script.events) {
      await c.deps.sleep(event.delayMs, signal);
      if (signal.aborted || stream.closed) break;
      if (event.event === "delta") sentDelta = true;
      if (event.event === "error") {
        status = 502;
        if (!sentDelta) await refund(c, charge);
      }
      stream.send(event.event, event.data as TutorEventData);
    }
  } finally {
    stream.close();
    finishTutor(c, "mock", ZERO_USAGE, status);
  }
}

async function realTutor(c: Ctx, body: TutorRequest, stream: EventStream, signal: AbortSignal, charge: Charge) {
  const sources = new Map(body.sources.map((s) => [s.id, s]));
  const cited = new Set<string>();
  let sentDelta = false;
  let model = c.deps.tutorModel;
  let usage = ZERO_USAGE;
  let status = 200;
  try {
    const events = c.deps.provider.tutor({
      model: c.deps.tutorModel,
      effort: c.deps.tutorEffort,
      maxTokens: 8_000,
      system: tutorSystem(body),
      messages: tutorMessages(body),
      signal,
    });
    for await (const event of events) {
      if (stream.closed) break;
      switch (event.type) {
        case "start":
          model = event.model || model;
          stream.send("start", { model });
          break;
        case "delta":
          sentDelta = true;
          stream.send("delta", { text: event.text });
          break;
        case "citation": {
          const source = sources.get(event.source);
          const key = `${event.source}\u0000${event.quote}`;
          if (!source || cited.has(key)) break;
          cited.add(key);
          stream.send("citation", { sourceId: source.id, label: source.label, quote: event.quote });
          break;
        }
        case "done":
          model = event.model || model;
          usage = event.usage;
          if (event.stop === "refusal") {
            status = 422;
            if (!sentDelta) await refund(c, charge);
            stream.send("error", {
              code: "upstream",
              message: "Cap can't help with that one. Try asking about your notes.",
            });
          } else {
            stream.send("done", { model });
          }
          break;
      }
    }
  } catch (error) {
    const err = providerError(error);
    status = err.status;
    if (err.usage) usage = err.usage;
    if (!sentDelta) await refund(c, charge);
    stream.send("error", { code: err.code, message: err.message });
  } finally {
    stream.close();
    finishTutor(c, model, usage, status);
  }
}

// ---- The assistant (server-sent events): Ask Cap with tools ----

/** One reply is up to MAX_ROUNDS requests. The first is a tutor message; each round after tool calls counts against `rounds`,
 * and the relay refuses one when `rounds` would pass three for each tutor message that day, so a request made up by hand (a
 * forged or replayed continuation, with no first round behind it) costs what an honest reply does. Drafting (cards, questions,
 * notes, exams) is its own daily allowance: 3 on the free plan, taken before the model is asked, so parallel requests cannot all
 * pass, and given back if the reply drafts nothing. When the allowance is spent the draft tools stay on offer: the model reaching
 * for one is how we know the student asked for something, and that ends the reply with `limit: "drafts"` (a plain question
 * never meets the limit). Web research is a separate route and a Pro feature. */
async function assistant(c: Ctx, body: AssistantRequest): Promise<Response> {
  if (body.messages[body.messages.length - 1].role !== "user") {
    throw badRequest("The last message must be the student's.");
  }
  const turns = checkTurns(body.turns);
  const ids = new Set<string>();
  body.sources = body.sources.filter((s) => !ids.has(s.id) && ids.add(s.id));
  const charge = await chargeRound(c, turns.length);
  let reserved = false;
  try {
    // The app asking for no drafting tools needs no draft; with them, it takes one of the day's drafts (or learns there is none).
    if (body.tools.some((t) => DRAFT_TOOLS.has(t))) reserved = await reserveDraft(c);
  } catch (error) {
    await refund(c, charge);
    throw error;
  }
  const tools = allowedTools(body.tools, { minor: body.minor });

  const stream = new EventStream(c.deps.pingIntervalMs);
  const abort = new AbortController();
  stream.onCancel(() => abort.abort());
  c.req.signal?.addEventListener("abort", () => abort.abort(), { once: true });
  const run = c.deps.env.mock
    ? mockAssistant(c, { ...body, turns }, stream, abort.signal, charge, { reserved })
    : realAssistant(c, { ...body, turns }, tools, stream, abort.signal, charge, { reserved });
  c.deps.background(run);
  return stream.response;
}

/** A round after a reply's first: it counts against `rounds`, and only while `rounds` stays within three for each tutor
 * message counted today (the tutor message is what the first round pays). */
async function chargeRound(c: Ctx, round: number): Promise<Charge> {
  if (round === 0) return await consume(c, { meter: "tutor" });
  const period = periodStart("day", c.now, c.user.timeZone);
  const used = await c.deps.store.usage(c.caller.userId, [{ meter: "tutor", period }, { meter: "rounds", period }]);
  const first = used.tutor ?? 0;
  if ((used.rounds ?? 0) >= (MAX_ROUNDS - 1) * first) {
    throw quotaError("tutor", c.user.plan, first, c.now, c.user.timeZone);
  }
  return await consume(c, { meter: "rounds" });
}

/** Takes one of the day's drafts for this request, if there is one (atomic: the database decides). */
async function reserveDraft(c: Ctx): Promise<boolean> {
  const period = periodStart(METERS.drafts.period, c.now, c.user.timeZone);
  const r = await c.deps.store.consume(c.caller.userId, "drafts", period, 1, enforcedLimit("drafts", c.user.plan));
  return r.allowed;
}

async function releaseDraft(c: Ctx): Promise<void> {
  try {
    const period = periodStart(METERS.drafts.period, c.now, c.user.timeZone);
    await c.deps.store.refund(c.caller.userId, "drafts", period, 1);
  } catch {
    // The student loses one draft for today at worst.
  }
}

interface Drafts {
  /** One of the day's drafts was taken for this request. */
  reserved: boolean;
}

/** What the reply says when the model reaches for a draft tool and the day's drafts are used up: the app writes the words
 * (in the student's language) and, on the free plan, offers Pro. */
const DRAFTS_LIMIT = { stop: "end_turn", limit: "drafts" } as const;

/** An error that needs no quota back: the model was asked and billed, or the student walked away. */
function keepsCharge(err: ApiError): boolean {
  return err.status === 499 || err.usage !== undefined;
}

async function mockAssistant(
  c: Ctx,
  body: AssistantRequest,
  stream: EventStream,
  signal: AbortSignal,
  charge: Charge,
  drafts: Drafts,
) {
  const name = fixtureOverride(c.req, "assistant") ?? assistantFixture(body);
  const script = JSON.parse(fixtureText(name)) as AssistantScript;
  let shown = false;
  let status = 200;
  let drafted = false;
  try {
    for (const event of script.events) {
      await c.deps.sleep(event.delayMs, signal);
      if (signal.aborted || stream.closed) break;
      if (event.event === "error") {
        status = 502;
        if (!shown) await refund(c, charge);
      } else if (event.event !== "start") {
        shown = true;
      }
      // The script reaches for a draft the day's allowance doesn't cover: the reply ends here, as the real one does.
      if (event.event === "tool_start" && !drafts.reserved && DRAFT_TOOLS.has(event.data.name as never)) {
        stream.send("done", { model: "mock", ...DRAFTS_LIMIT });
        break;
      }
      if (event.event === "tool_call" && DRAFT_TOOLS.has(event.data.name as never)) drafted = true;
      stream.send(event.event, event.data);
    }
  } finally {
    // A draft taken for a reply that made none is given back.
    if (drafts.reserved && !drafted) await releaseDraft(c);
    stream.close();
    finishTutor(c, "mock", ZERO_USAGE, status);
  }
}

async function realAssistant(
  c: Ctx,
  body: AssistantRequest,
  tools: ReturnType<typeof allowedTools>,
  stream: EventStream,
  signal: AbortSignal,
  charge: Charge,
  drafts: Drafts,
) {
  const sources = new Map(body.sources.map((s) => [s.id, s]));
  const cited = new Set<string>();
  let shown = false;
  let drafted = false;
  let limited = false;
  let model = c.deps.tutorModel;
  let usage = ZERO_USAGE;
  let status = 200;
  try {
    const { input, passages } = assistantInput(body);
    const events = c.deps.provider.assistant({
      model: c.deps.tutorModel,
      effort: c.deps.tutorEffort,
      maxTokens: 8_000,
      system: assistantSystem(body),
      input,
      tools: toolDefinitions(tools),
      passages,
      signal,
    });
    for await (const event of events) {
      if (stream.closed) break;
      switch (event.type) {
        case "start":
          model = event.model || model;
          stream.send("start", { model });
          break;
        case "delta":
          shown = true;
          stream.send("delta", { text: event.text });
          break;
        case "citation": {
          const source = sources.get(event.source);
          const key = `${event.source}\u0000${event.quote}`;
          if (!source || cited.has(key)) break;
          cited.add(key);
          stream.send("citation", { sourceId: source.id, label: source.label, quote: event.quote });
          break;
        }
        case "tool_start":
          if (!drafts.reserved && DRAFT_TOOLS.has(event.name as never)) {
            // The student asked for something to be made and the day's drafts are used up: stop the model here (it was
            // not told it could not) and let the app say so.
            limited = true;
            break;
          }
          shown = true;
          stream.send("tool_start", { callId: event.callId, name: event.name });
          break;
        case "tool_item":
          stream.send("tool_item", { callId: event.callId, index: event.index, item: event.item });
          break;
        case "tool_text":
          stream.send("tool_text", { callId: event.callId, text: event.text });
          break;
        case "tool_call":
          if (DRAFT_TOOLS.has(event.name as never)) drafted = true;
          stream.send("tool_call", { callId: event.callId, name: event.name, arguments: event.arguments });
          break;
        case "done":
          model = event.model || model;
          usage = event.usage;
          if (event.stop === "refusal") {
            status = 422;
            if (!shown) await refund(c, charge);
            stream.send("error", {
              code: "upstream",
              message: "Cap can't help with that one. Try asking about your notes.",
            });
          } else {
            stream.send("done", {
              model,
              stop: event.stop === "tool_calls" ? "tool_calls" : "end_turn",
              ...(event.continuation ? { continuation: event.continuation } : {}),
            });
          }
          break;
      }
      if (limited) break; // (leaving the loop closes the model's stream)
    }
    if (limited) stream.send("done", { model, ...DRAFTS_LIMIT });
  } catch (error) {
    const err = providerError(error);
    status = err.status;
    if (err.usage) usage = err.usage;
    if (!shown && !keepsCharge(err)) await refund(c, charge);
    stream.send("error", { code: err.code, message: err.message });
  } finally {
    // A draft taken for a reply that made none (an answer, a failure) is given back.
    if (drafts.reserved && !drafted) await releaseDraft(c);
    stream.close();
    finishTutor(c, model, usage, status);
  }
}

// ---- Web research (server-sent events): Pro only, trusted study sites only ----

async function research(c: Ctx, body: ResearchRequest): Promise<Response> {
  if (body.minor) throw badRequest("Web research isn't available for this account.", 403);
  if (!isPaid(c.user.plan)) throw new ApiError("entitlement_required", "Web research is part of Capling Pro.");
  const charge = await consume(c, { meter: "research" });
  const stream = new EventStream(c.deps.pingIntervalMs);
  const abort = new AbortController();
  stream.onCancel(() => abort.abort());
  c.req.signal?.addEventListener("abort", () => abort.abort(), { once: true });
  const run = c.deps.env.mock
    ? mockResearch(c, body, stream, abort.signal, charge)
    : realResearch(c, body, stream, abort.signal, charge);
  c.deps.background(run);
  return stream.response;
}

async function mockResearch(c: Ctx, body: ResearchRequest, stream: EventStream, signal: AbortSignal, charge: Charge) {
  const name = fixtureOverride(c.req, "research") ?? researchFixture(body.topic);
  const script = JSON.parse(fixtureText(name)) as ResearchScript;
  let shown = false;
  let status = 200;
  try {
    for (const event of script.events) {
      await c.deps.sleep(event.delayMs, signal);
      if (signal.aborted || stream.closed) break;
      if (event.event === "error") {
        status = 502;
        if (!shown) await refund(c, charge);
      } else if (event.event !== "start") {
        shown = true;
      }
      stream.send(event.event, event.data);
    }
  } finally {
    stream.close();
    finishTutor(c, "mock", ZERO_USAGE, status);
  }
}

async function realResearch(c: Ctx, body: ResearchRequest, stream: EventStream, signal: AbortSignal, charge: Charge) {
  let shown = false;
  let model = c.deps.tutorModel;
  let usage = ZERO_USAGE;
  let status = 200;
  try {
    const events = c.deps.provider.research({
      model: c.deps.tutorModel,
      effort: c.deps.tutorEffort,
      maxTokens: 4_000,
      system: researchSystem(),
      input: researchInput(body),
      domains: c.deps.env.researchDomains,
      maxSearches: 3,
      signal,
    });
    for await (const event of events) {
      if (stream.closed) break;
      switch (event.type) {
        case "start":
          model = event.model || model;
          stream.send("start", { model });
          break;
        case "search":
          shown = true;
          stream.send("search", {
            id: event.id,
            phase: event.phase,
            ...(event.queries ? { queries: event.queries } : {}),
            ...(event.sources ? { sources: event.sources } : {}),
          });
          break;
        case "delta":
          shown = true;
          stream.send("delta", { text: event.text });
          break;
        case "citation":
          stream.send("citation", { url: event.url, title: event.title, domain: event.domain });
          break;
        case "done":
          model = event.model || model;
          usage = event.usage;
          stream.send("done", { model, searches: event.searches });
          break;
      }
    }
  } catch (error) {
    const err = providerError(error);
    status = err.status;
    if (err.usage) usage = err.usage;
    if (!shown && !keepsCharge(err)) await refund(c, charge);
    stream.send("error", { code: err.code, message: err.message });
  } finally {
    stream.close();
    finishTutor(c, model, usage, status);
  }
}

function finishTutor(c: Ctx, model: string, usage: Usage, status: number): void {
  record(c, model, usage, status);
  log({
    fn: "ai",
    route: `/${c.route}/done`,
    status,
    latency_ms: Math.round(performance.now() - c.startedAt),
    plan: c.user.plan,
    model,
    mock: c.deps.env.mock,
    input_tokens: usage.inputTokens,
    output_tokens: usage.outputTokens,
    cache_read_tokens: usage.cacheReadTokens,
    cache_write_tokens: usage.cacheWriteTokens,
    cost_usd: c.deps.env.mock ? undefined : formatUsd(costNano(model, usage)),
  });
}

// ---- Dispatch ----

async function handle(req: Request, deps: Deps, name: string, meta: Meta, startedAt: number): Promise<Response> {
  if (!(name in ROUTES)) throw notFound();
  const route = name as RouteName;
  const spec = ROUTES[route];
  if (req.method !== spec.method) throw methodNotAllowed();

  const caller = await deps.authenticate(req);
  const now = deps.now();
  const user = await deps.store.context(caller.userId, now);
  if (!user.exists) throw unauthorized("This account was deleted.");
  meta.plan = user.plan;
  meta.mock = deps.env.mock;
  const c: Ctx = { req, deps, route, caller, user, now, meta, startedAt };

  if (route === "quota") {
    const usage = await deps.store.usage(caller.userId, usageKeys(SHOWN_METERS, now, user.timeZone));
    return json(quotaStatus(user.plan, usage));
  }

  await checkDailyCost(c);

  const body = requireValid<unknown>(spec.schema!, await readJson(req, spec.maxBytes));
  switch (route) {
    case "generate":
      return await generate(c, body as GenerateRequest);
    case "check":
      return await check(c, body as CheckRequest);
    case "grade":
      return await grade(c, body as GradeRequest);
    case "tutor":
      return await tutor(c, body as TutorRequest);
    case "confusions":
      return await confusions(c, body as ConfusionsRequest);
    case "lecture":
      return await lecture(c, body as LectureRequest);
    case "cards-from-chat":
      return await cardsFromChat(c, body as CardsFromChatRequest);
    case "transcribe-image":
      return await transcribeImage(c, body as TranscribeImageRequest);
    case "assistant":
      return await assistant(c, body as AssistantRequest);
    case "research":
      return await research(c, body as ResearchRequest);
  }
  throw notFound();
}

/** The `ai` function's request handler, with its dependencies built once per instance. */
export function aiHandler(deps: Deps): (req: Request) => Promise<Response> {
  return async (req) => {
    const startedAt = performance.now();
    const route = routeOf(req.url, "ai");
    const name = route.slice(1);
    const meta: Meta = {};
    let status = 200;
    let code: string | null = null;
    try {
      const res = await handle(req, deps, name, meta, startedAt);
      status = res.status;
      return res;
    } catch (error) {
      const err = toApiError(error);
      status = err.status;
      code = err.code;
      return errorResponse(err);
    } finally {
      const usage = meta.usage;
      log({
        fn: "ai",
        route: name in ROUTES ? route : "unknown",
        status,
        code,
        latency_ms: Math.round(performance.now() - startedAt),
        plan: meta.plan,
        model: meta.model,
        mock: meta.mock,
        input_tokens: usage?.inputTokens,
        output_tokens: usage?.outputTokens,
        cache_read_tokens: usage?.cacheReadTokens,
        cache_write_tokens: usage?.cacheWriteTokens,
        cost_usd: usage && meta.model && !meta.mock ? formatUsd(costNano(meta.model, usage)) : undefined,
      });
    }
  };
}
