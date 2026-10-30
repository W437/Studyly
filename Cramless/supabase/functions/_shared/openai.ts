// Ask Cap's tutor on OpenAI (GPT 6.1 Terra at low reasoning by default; docs/BUILD.md ▸ Ask Cap on OpenAI). It speaks
// the same normalized events as the Claude provider, so the app, the quota and the logs don't change.
//
// What differs from Claude: OpenAI has nothing like search_result blocks, which keep the notes on our side and make the
// model cite spans of them. So the passages go in as tagged text and the model answers in a strict JSON schema,
// {answer, citations: [{source_id, quote}]}. `answer` comes first: its text is read out of the JSON as it arrives and
// sent on as deltas. The quotes are checked here against the passages (a quote that is in none of them is dropped, one
// that is in another passage is credited to that one), and the app checks them again.
// Only the tutor runs here; every other route stays on Claude. Nothing is stored at OpenAI (`store: false`) and
// nothing here logs or keeps the person's content.

import type {
  AssistantCall,
  AssistantStreamEvent,
  JsonResult,
  Provider,
  ResearchCall,
  ResearchStreamEvent,
  TutorCall,
  TutorStreamEvent,
} from "./anthropic.ts";
import type { Usage } from "./cost.ts";
import { ApiError } from "./errors.ts";
import { StringFieldStream } from "./argstream.ts";
import { parseSse } from "./sse.ts";

export const OPENAI_BASE_URL = "https://api.openai.com/v1";

export const REPLY_SCHEMA = {
  type: "object",
  properties: {
    answer: { type: "string" },
    citations: {
      type: "array",
      items: {
        type: "object",
        properties: { source_id: { type: "string" }, quote: { type: "string" } },
        required: ["source_id", "quote"],
        additionalProperties: false,
      },
    },
  },
  required: ["answer", "citations"],
  additionalProperties: false,
};

export const FORMAT = `Reply as JSON with two fields and nothing else:
- "answer": your reply to the student, following all the rules above.
- "citations": the quotes that support what you said. Each has "source_id" (the id of the source) and "quote": a stretch of that source's text copied exactly, character for character, 6 to 30 words long. Give one or two. Use an empty list when the sources don't cover the question or you are only steering the student back to their studies.
Never write a source id (like s1) in the answer. If you point to a source, use its page label (for example "your textbook, p. 87") or say your notes, slides or lecture.`;

// ---- The conversation, from Claude's shape to OpenAI's ----

interface ClaudeBlock {
  type: string;
  text?: string;
  source?: string;
  title?: string;
  content?: { text?: string }[];
}

interface ClaudeMessage {
  role: "user" | "assistant";
  content: string | ClaudeBlock[];
}

export interface Passage {
  id: string;
  /** The text, folded for comparing quotes. */
  folded: string;
}

const attr = (value: string) => value.replace(/["<>]/g, "");

/** Case, accents and runs of white space do not tell two quotes apart. */
export function fold(text: string): string {
  return text.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase().replace(/\s+/g, " ").trim();
}

/** JavaScript's `\s`, by code, so a long run of white space costs a comparison a character and nothing more. */
function isSpace(code: number): boolean {
  return code === 32 || (code >= 9 && code <= 13) || code === 0xa0 || code === 0x1680 ||
    (code >= 0x2000 && code <= 0x200a) || code === 0x2028 || code === 0x2029 || code === 0x202f ||
    code === 0x205f || code === 0x3000 || code === 0xfeff;
}

/** A space after every "<" that, past any white space and a slash, begins `source` or `sources` (in any case): the ways a
 * passage could close its own tag or open one of ours. One pass over the text; each run of white space is read once, however
 * long, so nothing a student pastes makes this slow (a pattern with `\s*` on both sides of the slash takes quadratic time,
 * and a bounded one lets a run of nine spaces through). */
export function defangTags(text: string): string {
  let out = "";
  let from = 0;
  for (let at = text.indexOf("<"); at !== -1; at = text.indexOf("<", at + 1)) {
    let i = at + 1;
    while (i < text.length && isSpace(text.charCodeAt(i))) i++;
    if (text[i] === "/") {
      i++;
      while (i < text.length && isSpace(text.charCodeAt(i))) i++;
    }
    if (/^sources?\b/i.test(text.slice(i, i + 8))) {
      out += text.slice(from, at + 1) + " ";
      from = at + 1;
    }
  }
  return out + text.slice(from);
}

/** The passages as tagged text for the model, and each passage's folded text for checking quotes. A passage cannot close
 * its own tag, or open one of ours, in any case. */
export function taggedSources(
  items: { id: string; title: string; text: string }[],
): { text: string; passages: Passage[] } {
  const passages: Passage[] = [];
  const blocks = items.map((s) => {
    passages.push({ id: s.id, folded: fold(s.text) });
    return `<source id="${attr(s.id)}" title="${attr(s.title)}">\n${defangTags(s.text)}\n</source>`;
  });
  return { text: "<sources>\n" + blocks.join("\n") + "\n</sources>", passages };
}

/** The relay's tutor messages (earlier turns as text; the last turn with the passages as search results) as OpenAI input:
 * the passages become tagged text ahead of the rest of the turn, as in the test that chose this model. */
export function fromClaude(messages: unknown): { input: { role: string; content: string }[]; passages: Passage[] } {
  const input: { role: string; content: string }[] = [];
  const passages: Passage[] = [];
  for (const m of messages as ClaudeMessage[]) {
    if (typeof m.content === "string") {
      input.push({ role: m.role, content: m.content });
      continue;
    }
    const found = m.content.filter((b) => b.type === "search_result");
    const texts = m.content.filter((b) => b.type === "text").map((b) => b.text ?? "");
    let sources = "";
    if (found.length > 0) {
      const tagged = taggedSources(found.map((b) => ({
        id: b.source ?? "",
        title: b.title ?? "",
        text: (b.content ?? []).map((c) => c.text ?? "").join(" "),
      })));
      sources = tagged.text;
      passages.push(...tagged.passages);
    }
    input.push({ role: m.role, content: [sources, ...texts].filter((part) => part !== "").join("\n\n") });
  }
  return { input, passages };
}

// ---- Reading the reply ----

/** Reads the "answer" string out of a JSON object as the object arrives, and hands on the text decoded so far. An
 * escape (or half of a surrogate pair) split across two chunks waits for its other half. If the object does not begin
 * with the answer, nothing is streamed and the whole reply is read at the end. */
export class AnswerStream extends StringFieldStream {
  constructor() {
    super("answer", true);
  }
}

export interface Reply {
  answer: string;
  citations: { source_id: string; quote: string }[];
}

/** The first JSON object in the text, if it is whole. A model that keeps writing after its object ended (it has happened,
 * with no reasoning) does not spoil the answer. */
function firstObject(text: string): string | null {
  const start = text.indexOf("{");
  if (start < 0) return null;
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let i = start; i < text.length; i++) {
    const ch = text[i];
    if (inString) {
      if (escaped) escaped = false;
      else if (ch === "\\") escaped = true;
      else if (ch === '"') inString = false;
      continue;
    }
    if (ch === '"') inString = true;
    else if (ch === "{") depth++;
    else if (ch === "}" && --depth === 0) return text.slice(start, i + 1);
  }
  return null;
}

export function parseReply(text: string): Reply | null {
  const json = firstObject(text);
  if (!json) return null;
  let value: { answer?: unknown; citations?: unknown };
  try {
    value = JSON.parse(json);
  } catch {
    return null;
  }
  if (typeof value.answer !== "string" || !Array.isArray(value.citations)) return null;
  const citations = value.citations.flatMap((c: { source_id?: unknown; quote?: unknown }) =>
    typeof c?.source_id === "string" && typeof c?.quote === "string"
      ? [{ source_id: c.source_id, quote: c.quote.trim() }]
      : []
  );
  return { answer: value.answer, citations };
}

/** The passage a quote belongs to: the one the model named if the quote is in it, else any passage that holds it. */
export function creditedSource(passages: Passage[], named: string, quote: string): string | null {
  const q = fold(quote);
  if (q.length < 4) return null;
  const first = passages.find((p) => p.id === named);
  if (first?.folded.includes(q)) return first.id;
  return passages.find((p) => p.folded.includes(q))?.id ?? null;
}

/** What of a finished reply has not been sent yet: the rest of the answer (when the object did not begin with it, or
 * the escapes were odd), then its quotes that are in a passage, each credited to the passage that holds it. */
export function* answerEvents(
  reply: Reply,
  streamed: string,
  passages: Passage[],
): Generator<{ type: "delta"; text: string } | { type: "citation"; source: string; quote: string }> {
  if (reply.answer.length > streamed.length && reply.answer.startsWith(streamed)) {
    yield { type: "delta", text: reply.answer.slice(streamed.length) };
  }
  const seen = new Set<string>();
  for (const c of reply.citations.slice(0, 6)) {
    const source = creditedSource(passages, c.source_id, c.quote);
    const key = `${source}\u0000${c.quote}`;
    if (source === null || seen.has(key)) continue;
    seen.add(key);
    yield { type: "citation", source, quote: c.quote };
  }
}

// ---- Errors ----

export function httpError(status: number, retryAfter: string | null): ApiError {
  if (status === 429) {
    const seconds = Number(retryAfter ?? "");
    return new ApiError("upstream", "Cap is busy right now. Try again in a moment.", {
      retryAfter: Number.isFinite(seconds) && seconds > 0 ? seconds : 20,
    }, 503);
  }
  if (status === 408 || status === 504) {
    return new ApiError("upstream", "Cap took too long to answer. Try again in a moment.", {}, 504);
  }
  if (status >= 500) {
    return new ApiError("upstream", "Cap is busy right now. Try again in a moment.", { retryAfter: 15 }, 503);
  }
  return new ApiError("upstream", "Cap couldn't answer that. Try again in a moment.", {}, 502);
}

/** An error event in the stream: the code says whether to call it busy or failed. */
export function streamError(code: unknown): ApiError {
  const c = typeof code === "string" ? code : "";
  if (/rate_limit|overloaded|server_error|timeout|unavailable/.test(c)) {
    return new ApiError("upstream", "Cap is busy right now. Try again in a moment.", { retryAfter: 15 }, 503);
  }
  return new ApiError("upstream", "Cap couldn't answer that. Try again in a moment.", {}, 502);
}

export const NETWORK = new ApiError("upstream", "Cap couldn't be reached. Try again in a moment.", {}, 502);

export function thrown(error: unknown, caller?: AbortSignal): ApiError {
  if (error instanceof ApiError) return error;
  if (caller?.aborted) return new ApiError("upstream", "The request was cancelled.", {}, 499);
  if (error instanceof DOMException && (error.name === "TimeoutError" || error.name === "AbortError")) {
    return new ApiError("upstream", "Cap took too long to answer. Try again in a moment.", {}, 504);
  }
  return NETWORK;
}

// ---- The provider ----

export interface OpenAIOptions {
  apiKey: string;
  /** Tests point this at the mock server; empty for OpenAI's. */
  baseURL?: string;
  timeoutMs?: number;
  /** Tries again this many times when nothing has been sent on yet and OpenAI was busy or unreachable. */
  maxRetries?: number;
  retryDelayMs?: number;
  fetch?: typeof fetch;
}

export class OpenAIProvider implements Provider {
  protected readonly apiKey: string;
  protected readonly baseURL: string;
  protected readonly timeoutMs: number;
  protected readonly maxRetries: number;
  protected readonly retryDelayMs: number;
  protected readonly fetcher: typeof fetch;

  constructor(options: OpenAIOptions) {
    this.apiKey = options.apiKey;
    this.baseURL = (options.baseURL || OPENAI_BASE_URL).replace(/\/+$/, "");
    this.timeoutMs = options.timeoutMs ?? 90_000;
    this.maxRetries = options.maxRetries ?? 1;
    this.retryDelayMs = options.retryDelayMs ?? 800;
    this.fetcher = options.fetch ?? fetch;
  }

  json<T>(): Promise<JsonResult<T>> {
    return Promise.reject(new ApiError("upstream", "Cloud AI isn't set up for this on this server.", {}, 503));
  }

  // The assistant and web research are OpenAIAssistantProvider's (openai_assistant.ts).
  // deno-lint-ignore require-yield
  async *assistant(_call: AssistantCall): AsyncGenerator<AssistantStreamEvent> {
    throw new ApiError("upstream", "Cloud AI isn't set up for this on this server.", {}, 503);
  }

  // deno-lint-ignore require-yield
  async *research(_call: ResearchCall): AsyncGenerator<ResearchStreamEvent> {
    throw new ApiError("upstream", "Cloud AI isn't set up for this on this server.", {}, 503);
  }

  async *tutor(call: TutorCall): AsyncGenerator<TutorStreamEvent> {
    const { input, passages } = fromClaude(call.messages);
    const body = JSON.stringify({
      model: call.model,
      instructions: `${call.system}\n\n${FORMAT}`,
      input,
      reasoning: { effort: call.effort },
      text: { format: { type: "json_schema", name: "cap_reply", strict: true, schema: REPLY_SCHEMA } },
      max_output_tokens: call.maxTokens,
      stream: true,
      store: false,
    });
    yield* this.attempts(
      call.signal,
      (signal, markSent) => this.#once(body, signal, call.model, passages, markSent),
    );
  }

  /** One call to the model with the timeout and, while nothing has reached the person, one more try when OpenAI was busy
   * or unreachable. Stops the request when the consumer stops early (the person left). */
  protected async *attempts<E>(
    external: AbortSignal | undefined,
    once: (signal: AbortSignal, markSent: () => void) => AsyncGenerator<E>,
    timeoutMs = this.timeoutMs,
  ): AsyncGenerator<E> {
    const abort = new AbortController();
    const timer = setTimeout(
      () => abort.abort(new DOMException("Cap took too long to answer.", "TimeoutError")),
      timeoutMs,
    );
    const signal = external ? AbortSignal.any([abort.signal, external]) : abort.signal;
    let sent = false;
    try {
      for (let attempt = 0;; attempt++) {
        try {
          yield* once(signal, () => (sent = true));
          return;
        } catch (error) {
          const failure = thrown(error, external);
          const transient = failure.status === 503 || failure.status === 504 || failure === NETWORK;
          if (sent || !transient || attempt >= this.maxRetries || signal.aborted) throw failure;
          await new Promise((resolve) => setTimeout(resolve, this.retryDelayMs));
        }
      }
    } finally {
      clearTimeout(timer);
      abort.abort();
    }
  }

  /** POSTs a Responses request; a refusal by the API becomes the contract's error. */
  protected async open(body: string, signal: AbortSignal): Promise<ReadableStream<Uint8Array>> {
    const res = await this.fetcher(`${this.baseURL}/responses`, {
      method: "POST",
      headers: { "Authorization": `Bearer ${this.apiKey}`, "Content-Type": "application/json" },
      body,
      signal,
    });
    if (!res.ok || !res.body) {
      const failure = httpError(res.status, res.headers.get("retry-after"));
      await res.body?.cancel();
      throw failure;
    }
    return res.body;
  }

  async *#once(
    body: string,
    signal: AbortSignal,
    requested: string,
    passages: Passage[],
    markSent: () => void,
  ): AsyncGenerator<TutorStreamEvent> {
    const stream = await this.open(body, signal);
    const answer = new AnswerStream();
    let model = requested;
    let raw = "";
    let streamed = "";
    let started = false;
    let refusal = false;
    let finished = false;
    let status = "completed";
    let usage: Usage = { inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0 };
    const start = (): TutorStreamEvent[] => {
      if (started) return [];
      started = true;
      return [{ type: "start", model }];
    };

    for await (const message of parseSse(stream)) {
      // deno-lint-ignore no-explicit-any
      let e: any;
      try {
        e = JSON.parse(message.data);
      } catch {
        continue;
      }
      if (e.type === "response.created") {
        if (typeof e.response?.model === "string" && e.response.model) model = e.response.model;
      } else if (e.type === "response.output_text.delta" && typeof e.delta === "string") {
        raw += e.delta;
        const piece = answer.push(e.delta);
        if (piece) {
          for (const event of start()) yield event;
          markSent();
          streamed += piece;
          yield { type: "delta", text: piece };
        }
      } else if (e.type === "response.refusal.delta") {
        refusal = true;
      } else if (e.type === "response.completed" || e.type === "response.incomplete") {
        finished = true;
        const r = e.response ?? {};
        if (typeof r.model === "string" && r.model) model = r.model;
        if (e.type === "response.incomplete") status = r.incomplete_details?.reason ?? "incomplete";
        const u = r.usage ?? {};
        const cached = Math.max(0, u.input_tokens_details?.cached_tokens ?? 0);
        usage = {
          inputTokens: Math.max(0, (u.input_tokens ?? 0) - cached),
          outputTokens: Math.max(0, u.output_tokens ?? 0),
          cacheReadTokens: cached,
          cacheWriteTokens: 0,
        };
      } else if (e.type === "response.failed") {
        throw streamError(e.response?.error?.code);
      } else if (e.type === "error") {
        throw streamError(e.code ?? e.error?.code);
      }
    }
    if (!finished) {
      // Nothing had reached the person: worth trying again. Otherwise keep what arrived and say so.
      throw streamed === ""
        ? NETWORK
        : new ApiError("upstream", "Cap lost the connection part way. Try again.", {}, 502);
    }

    const reply = parseReply(raw);
    const stop = refusal || status === "content_filter"
      ? "refusal"
      : status === "max_output_tokens"
      ? "max_tokens"
      : "end_turn";
    // An answer cut off by the token limit keeps the part that arrived, as it does on Claude.
    if (reply === null && stop !== "refusal" && !(stop === "max_tokens" && streamed !== "")) {
      const unreadable = new ApiError("upstream", "The answer came back unreadable. Try again.", {}, 502);
      unreadable.usage = usage; // OpenAI billed it all the same
      throw unreadable;
    }
    for (const event of start()) yield event;
    markSent();
    if (reply !== null) yield* answerEvents(reply, streamed, passages);
    yield { type: "done", model, usage, stop };
  }
}

/** The tutor on one provider and every other route on another. */
class SplitProvider implements Provider {
  constructor(private readonly base: Provider, private readonly tutorProvider: Provider) {}

  json<T>(call: Parameters<Provider["json"]>[0]): Promise<JsonResult<T>> {
    return this.base.json<T>(call);
  }

  tutor(call: TutorCall): AsyncGenerator<TutorStreamEvent> {
    return this.tutorProvider.tutor(call);
  }

  assistant(call: AssistantCall): AsyncGenerator<AssistantStreamEvent> {
    return this.tutorProvider.assistant(call);
  }

  research(call: ResearchCall): AsyncGenerator<ResearchStreamEvent> {
    return this.tutorProvider.research(call);
  }
}

export function withTutor(base: Provider, tutorProvider: Provider): Provider {
  return new SplitProvider(base, tutorProvider);
}
