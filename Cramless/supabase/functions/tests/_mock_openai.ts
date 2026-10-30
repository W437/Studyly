// A local stand-in for OpenAI's Responses API, for testing the tutor's OpenAI path without a key: the provider's base
// URL points here. It refuses a request the way the API would (the key, the model, the instructions, a strict JSON schema,
// nothing stored, streaming), records it, and answers with the next canned reply: a server-sent event stream or an error.

export const TEST_OPENAI_KEY = "test-openai-key";

export interface RecordedOpenAI {
  path: string;
  headers: Record<string, string>;
  // deno-lint-ignore no-explicit-any
  body: any;
}

export type MockOpenAIAnswer =
  | { sse: { event: string; data: unknown }[]; hang?: boolean }
  | { status: number; error: { message: string; type: string; code?: string }; headers?: Record<string, string> };

export interface MockOpenAI {
  url: string;
  requests: RecordedOpenAI[];
  /** Streams that were still open when the client went away (a `hang` reply whose reader left). */
  readonly dropped: number;
  /** Queues the reply to the next request. */
  answer(reply: MockOpenAIAnswer): void;
  close(): Promise<void>;
}

const EFFORTS = ["none", "minimal", "low", "medium", "high", "xhigh", "max"];

/** Every object in a strict schema lists all its properties as required and allows no others. */
// deno-lint-ignore no-explicit-any
function strictProblem(schema: any, path: string): string | null {
  if (schema === null || typeof schema !== "object") return null;
  const types = Array.isArray(schema.type) ? schema.type : [schema.type];
  if (types.includes("object")) {
    if (schema.additionalProperties !== false) return `${path}: additionalProperties must be false`;
    const keys = Object.keys(schema.properties ?? {});
    if (keys.some((k) => !(schema.required ?? []).includes(k))) return `${path}: every property must be required`;
    for (const [k, v] of Object.entries(schema.properties ?? {})) {
      const inner = strictProblem(v, `${path}.${k}`);
      if (inner) return inner;
    }
  }
  if (types.includes("array")) return strictProblem(schema.items, `${path}[]`);
  return null;
}

/** What the real API would refuse, as a message; null when the request is well formed. */
// deno-lint-ignore no-explicit-any
export function shapeProblem(headers: Record<string, string>, body: any): string | null {
  if (headers["authorization"] !== `Bearer ${TEST_OPENAI_KEY}`) return "the API key is missing or wrong";
  if (typeof body?.model !== "string" || !body.model) return "model: required";
  if (typeof body.instructions !== "string" || !body.instructions) return "instructions: required";
  if (!Array.isArray(body.input) || body.input.length === 0) return "input: required";
  if (body.store !== false) return "store: the relay keeps nothing at OpenAI";
  if (body.stream !== true) return "stream: the relay streams";
  if (!EFFORTS.includes(body.reasoning?.effort)) return "reasoning.effort: unknown";
  if (!Number.isInteger(body.max_output_tokens) || body.max_output_tokens < 1) return "max_output_tokens: required";
  for (const key of ["temperature", "top_p"]) if (key in body) return `${key}: not supported with reasoning`;
  const search = (body.tools ?? []).some((t: { type?: string }) => t.type === "web_search");
  if (search) return researchProblem(body);
  if (Array.isArray(body.tools) || body.include !== undefined) return assistantProblem(body);
  if (body.input[body.input.length - 1].role !== "user") return "input: the last message must be from the user";
  const format = body.text?.format;
  if (format?.type !== "json_schema" || format.strict !== true || typeof format.name !== "string") {
    return "text.format: expected a strict json_schema with a name";
  }
  return strictProblem(format.schema, "schema");
}

// deno-lint-ignore no-explicit-any
function assistantProblem(body: any): string | null {
  const format = body.text?.format;
  if (format?.type !== "json_schema" || format.strict !== true) return "text.format: expected a strict json_schema";
  const formatProblem = strictProblem(format.schema, "schema");
  if (formatProblem) return formatProblem;
  if (!body.include?.includes("reasoning.encrypted_content")) return "include: reasoning.encrypted_content is needed";
  if (body.tools !== undefined) {
    if (body.tool_choice !== "auto") return "tool_choice: auto";
    for (const tool of body.tools) {
      if (tool.type !== "function" || typeof tool.name !== "string" || tool.strict !== true) {
        return `tools: ${tool.name}: expected a strict function`;
      }
      const inner = strictProblem(tool.parameters, `tools.${tool.name}`);
      if (inner) return inner;
    }
  }
  // Every call the input holds is answered, and every answer follows its call.
  const calls = new Set<string>();
  for (const item of body.input) {
    if (item.type === "function_call") {
      if (typeof item.call_id !== "string" || typeof item.name !== "string" || typeof item.arguments !== "string") {
        return "input: a function_call needs call_id, name and arguments";
      }
      calls.add(item.call_id);
    } else if (item.type === "function_call_output") {
      if (!calls.delete(item.call_id)) return "input: a function_call_output has no call before it";
      if (typeof item.output !== "string") return "input: output must be a string";
    } else if (item.type === "reasoning") {
      if (typeof item.encrypted_content !== "string") return "input: a reasoning item needs encrypted_content";
    } else if (typeof item.role !== "string" || typeof item.content !== "string") {
      return "input: expected a message, a call, a result or a reasoning item";
    }
  }
  if (calls.size > 0) return "input: a function_call has no function_call_output";
  const last = body.input[body.input.length - 1];
  if (last.role !== "user" && last.type !== "function_call_output") {
    return "input: the last item must be the student's or a result";
  }
  return null;
}

// deno-lint-ignore no-explicit-any
function researchProblem(body: any): string | null {
  const tool = body.tools.find((t: { type?: string }) => t.type === "web_search");
  const domains = tool.filters?.allowed_domains;
  if (!Array.isArray(domains) || domains.length === 0 || domains.length > 100) return "allowed_domains: 1 to 100";
  if (domains.some((d: unknown) => typeof d !== "string" || !/^[a-z0-9.-]+\.[a-z]{2,}$/.test(d))) {
    return "allowed_domains: Invalid domain";
  }
  if (body.tool_choice !== "required") return "tool_choice: web research must search";
  if (!body.include?.includes("web_search_call.action.sources")) return "include: web_search_call.action.sources";
  if (!Number.isInteger(body.max_tool_calls) || body.max_tool_calls < 1) return "max_tool_calls: required";
  if (body.input.length !== 1 || body.input[0].role !== "user") return "input: one user message";
  return null;
}

function apiError(
  status: number,
  error: { message: string; type: string; code?: string },
  extra: Record<string, string> = {},
) {
  return new Response(JSON.stringify({ error }), { status, headers: { "content-type": "application/json", ...extra } });
}

export function startMockOpenAI(port = 0): MockOpenAI {
  const queue: MockOpenAIAnswer[] = [];
  const requests: RecordedOpenAI[] = [];
  let dropped = 0;
  const server = Deno.serve({ hostname: "127.0.0.1", port, onListen() {} }, async (req) => {
    const url = new URL(req.url);
    const headers: Record<string, string> = {};
    req.headers.forEach((value, key) => (headers[key.toLowerCase()] = value));
    // deno-lint-ignore no-explicit-any
    let body: any = null;
    try {
      body = await req.json();
    } catch {
      return apiError(400, { message: "body: invalid JSON", type: "invalid_request_error" });
    }
    requests.push({ path: url.pathname, headers, body });
    if (req.method !== "POST" || url.pathname !== "/v1/responses") {
      return apiError(404, { message: `No route ${req.method} ${url.pathname}`, type: "invalid_request_error" });
    }
    const problem = shapeProblem(headers, body);
    if (problem) return apiError(400, { message: problem, type: "invalid_request_error" });
    const next = queue.shift();
    if (!next) return apiError(500, { message: "The mock has no reply queued.", type: "server_error" });
    if ("error" in next) return apiError(next.status, next.error, next.headers);
    const text = next.sse.map((e) => `event: ${e.event}\ndata: ${JSON.stringify(e.data)}\n\n`).join("");
    if (!next.hang) return new Response(text, { headers: { "content-type": "text/event-stream" } });
    // Sends the events, then stays open until the reader leaves.
    const encoder = new TextEncoder();
    return new Response(
      new ReadableStream({
        start(controller) {
          controller.enqueue(encoder.encode(text));
        },
        cancel() {
          dropped++;
        },
      }),
      { headers: { "content-type": "text/event-stream" } },
    );
  });
  const addr = server.addr as Deno.NetAddr;
  return {
    url: `http://127.0.0.1:${addr.port}`,
    requests,
    get dropped() {
      return dropped;
    },
    answer: (reply) => queue.push(reply),
    close: () => server.shutdown(),
  };
}

export interface MockUsage {
  input?: number;
  cached?: number;
  output?: number;
  reasoning?: number;
}

type Event = { event: string; data: unknown };

const usageOf = (u: MockUsage = {}) => ({
  input_tokens: u.input ?? 900,
  input_tokens_details: { cached_tokens: u.cached ?? 0 },
  output_tokens: u.output ?? 150,
  output_tokens_details: { reasoning_tokens: u.reasoning ?? 0 },
  total_tokens: (u.input ?? 900) + (u.output ?? 150),
});

const created = (model: string): Event => ({
  event: "response.created",
  data: { type: "response.created", response: { id: "resp_mock", model, status: "in_progress" } },
});

const completed = (model: string, o: { usage?: MockUsage; reason?: string }): Event => ({
  event: o.reason ? "response.incomplete" : "response.completed",
  data: {
    type: o.reason ? "response.incomplete" : "response.completed",
    response: {
      id: "resp_mock",
      model,
      status: o.reason ? "incomplete" : "completed",
      ...(o.reason ? { incomplete_details: { reason: o.reason } } : {}),
      usage: usageOf(o.usage),
    },
  },
});

const delta = (text: string): Event => ({
  event: "response.output_text.delta",
  data: { type: "response.output_text.delta", item_id: "msg_mock", output_index: 0, content_index: 0, delta: text },
});

export interface StreamOptions {
  model?: string;
  /** Characters per text delta. */
  chunk?: number;
  usage?: MockUsage;
  /** An incomplete response, with this reason ("max_output_tokens", "content_filter"). */
  reason?: string;
  /** End the stream with an error event after the text (or the part of it that was sent), instead of completing. */
  failWith?: string;
  /** Stop after this many characters of the JSON, and end the stream without completing it. */
  cutAt?: number;
}

/** A streamed Responses reply whose text is `reply` as JSON (or `raw`, as is), cut into small deltas. */
export function replyStream(
  reply: { answer: string; citations?: { source_id: string; quote: string }[] } | { raw: string },
  o: StreamOptions = {},
): MockOpenAIAnswer {
  const model = o.model ?? "gpt-6.1-terra";
  const text = "raw" in reply ? reply.raw : JSON.stringify({ answer: reply.answer, citations: reply.citations ?? [] });
  const shown = o.cutAt === undefined ? text : text.slice(0, o.cutAt);
  const sse: Event[] = [created(model)];
  for (let i = 0; i < shown.length; i += o.chunk ?? 9) sse.push(delta(shown.slice(i, i + (o.chunk ?? 9))));
  if (o.failWith) {
    sse.push({
      event: "error",
      data: { type: "error", code: o.failWith, message: "Something happened.", param: null },
    });
  } else if (o.cutAt === undefined || o.reason) {
    // A cut text still ends in a response.incomplete when there is a reason (the token limit hit mid-answer).
    if (o.cutAt === undefined) {
      sse.push({ event: "response.output_text.done", data: { type: "response.output_text.done", text } });
    }
    sse.push(completed(model, o));
  }
  return { sse };
}

/** A reply that never starts and ends in an error event. */
export function replyFailure(code: string): MockOpenAIAnswer {
  return replyStream({ raw: "" }, { failWith: code });
}

/** A response that failed, as the API reports it inside the stream. */
export function replyFailed(code: string): MockOpenAIAnswer {
  return {
    sse: [
      created("gpt-6.1-terra"),
      {
        event: "response.failed",
        data: {
          type: "response.failed",
          response: { id: "resp_mock", status: "failed", error: { code, message: "It failed." } },
        },
      },
    ],
  };
}

/** A refusal in place of the JSON. */
export function replyRefusal(text: string, o: StreamOptions = {}): MockOpenAIAnswer {
  const model = o.model ?? "gpt-6.1-terra";
  return {
    sse: [
      created(model),
      { event: "response.refusal.delta", data: { type: "response.refusal.delta", delta: text } },
      { event: "response.refusal.done", data: { type: "response.refusal.done", refusal: text } },
      completed(model, o),
    ],
  };
}

/** Sends some of the text and then keeps the connection open, as a slow model does. */
export function replyHanging(answerStart: string): MockOpenAIAnswer {
  return { sse: [created("gpt-6.1-terra"), delta(`{"answer":"${answerStart}`)], hang: true };
}

export interface ToolCallSpec {
  name: string;
  /** The arguments as an object (sent as JSON text in small pieces) or as raw text. */
  args: unknown;
  /** Characters per delta of the arguments. */
  chunk?: number;
  callId?: string;
  /** Stop after this many characters of the arguments (the token limit hit mid-call). */
  cutAt?: number;
}

const itemEvent = (type: string, index: number, item: unknown): Event => ({
  event: `response.output_item.${type}`,
  data: { type: `response.output_item.${type}`, output_index: index, item },
});

/** A round in which the model calls tools: reasoning (encrypted), then each call with its arguments streamed. */
export function replyToolCalls(
  calls: ToolCallSpec[],
  o: StreamOptions & { reasoning?: boolean; text?: string; lead?: string } = {},
): MockOpenAIAnswer {
  const model = o.model ?? "gpt-6.1-terra";
  const sse: Event[] = [created(model)];
  let index = 0;
  if (o.reasoning !== false) {
    sse.push(itemEvent("added", index, { id: "rs_mock", type: "reasoning", summary: [] }));
    sse.push(
      itemEvent("done", index, {
        id: "rs_mock",
        type: "reasoning",
        summary: [],
        encrypted_content: "gAAAA-mock-encrypted",
      }),
    );
    index++;
  }
  // Words the model writes before it calls anything (`text` is what it writes after).
  if (o.lead !== undefined) { for (let i = 0; i < o.lead.length; i += 9) sse.push(delta(o.lead.slice(i, i + 9))); }
  calls.forEach((c, n) => {
    const callId = c.callId ?? `call_mock_${n + 1}`;
    const text = typeof c.args === "string" ? c.args : JSON.stringify(c.args);
    const shown = c.cutAt === undefined ? text : text.slice(0, c.cutAt);
    sse.push(
      itemEvent("added", index, {
        id: `fc_mock_${n}`,
        type: "function_call",
        status: "in_progress",
        call_id: callId,
        name: c.name,
        arguments: "",
      }),
    );
    for (let i = 0; i < shown.length; i += c.chunk ?? 11) {
      sse.push({
        event: "response.function_call_arguments.delta",
        data: {
          type: "response.function_call_arguments.delta",
          item_id: `fc_mock_${n}`,
          output_index: index,
          delta: shown.slice(i, i + (c.chunk ?? 11)),
        },
      });
    }
    if (c.cutAt === undefined) {
      sse.push({
        event: "response.function_call_arguments.done",
        data: {
          type: "response.function_call_arguments.done",
          item_id: `fc_mock_${n}`,
          output_index: index,
          arguments: text,
        },
      });
    }
    sse.push(
      itemEvent("done", index, {
        id: `fc_mock_${n}`,
        type: "function_call",
        status: "completed",
        call_id: callId,
        name: c.name,
        arguments: shown,
      }),
    );
    index++;
  });
  if (o.text !== undefined) {
    for (let i = 0; i < o.text.length; i += 9) sse.push(delta(o.text.slice(i, i + 9)));
  }
  sse.push(completed(model, o));
  return { sse };
}

/** A web search turn: the search, its sources, then the summary with the pages it cites. */
export function replyWebSearch(
  o: {
    searches?: { queries: string[]; sources: string[] }[];
    text: string;
    cites?: { url: string; title: string }[];
    model?: string;
    usage?: MockUsage;
    chunk?: number;
  },
): MockOpenAIAnswer {
  const model = o.model ?? "gpt-6.1-terra";
  const sse: Event[] = [created(model)];
  let index = 0;
  for (const [n, search] of (o.searches ?? []).entries()) {
    const id = `ws_mock_${n}`;
    sse.push(itemEvent("added", index, { id, type: "web_search_call", status: "in_progress" }));
    for (const phase of ["in_progress", "searching", "completed"]) {
      sse.push({
        event: `response.web_search_call.${phase}`,
        data: { type: `response.web_search_call.${phase}`, item_id: id, output_index: index },
      });
    }
    sse.push(
      itemEvent("done", index, {
        id,
        type: "web_search_call",
        status: "completed",
        action: {
          type: "search",
          queries: search.queries,
          query: search.queries[0],
          sources: search.sources.map((url) => ({ type: "url", url })),
        },
      }),
    );
    index++;
  }
  sse.push(
    itemEvent("added", index, {
      id: "msg_mock",
      type: "message",
      status: "in_progress",
      content: [],
      role: "assistant",
    }),
  );
  for (let i = 0; i < o.text.length; i += o.chunk ?? 13) sse.push(delta(o.text.slice(i, i + (o.chunk ?? 13))));
  for (const cite of o.cites ?? []) {
    sse.push({
      event: "response.output_text.annotation.added",
      data: {
        type: "response.output_text.annotation.added",
        annotation: { type: "url_citation", url: cite.url, title: cite.title, start_index: 0, end_index: 10 },
      },
    });
  }
  sse.push(itemEvent("done", index, { id: "msg_mock", type: "message", status: "completed", role: "assistant" }));
  sse.push(completed(model, { usage: o.usage ?? { input: 8000, output: 200 } }));
  return { sse };
}
