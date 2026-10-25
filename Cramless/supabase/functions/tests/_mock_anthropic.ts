// A local stand-in for the Anthropic Messages API, for testing the real path without a key: the SDK's baseURL
// points here. It checks each request's shape the way the API would refuse it (key, version, model, max_tokens,
// messages, no sampling parameters on API version 2026-10-21, structured outputs not mixed with citations),
// records it, and answers with the next canned reply: a Messages JSON body, a server-sent event stream, or an error.
//
//   deno task mock-anthropic     runs it on 127.0.0.1:58499 (answers every call with a canned generate reply)

export interface RecordedRequest {
  path: string;
  search: string;
  headers: Record<string, string>;
  // deno-lint-ignore no-explicit-any
  body: any;
}

export type MockAnswer =
  | { json: unknown; status?: number }
  | { sse: { event: string; data: unknown }[] }
  | { status: number; error: { type: string; message: string }; headers?: Record<string, string> };

export interface MockAnthropic {
  url: string;
  requests: RecordedRequest[];
  /** Queues the reply to the next request. */
  answer(reply: MockAnswer): void;
  close(): Promise<void>;
}

export const TEST_API_KEY = "test-anthropic-key";

function apiError(status: number, type: string, message: string): Response {
  return new Response(JSON.stringify({ type: "error", error: { type, message } }), {
    status,
    headers: { "content-type": "application/json" },
  });
}

/** What the real API would refuse, as a message; null when the request is well formed. */
// deno-lint-ignore no-explicit-any
export function shapeProblem(headers: Record<string, string>, body: any): string | null {
  // SDK 1.x sends the key as `Authorization: Bearer <key>`; older clients send x-api-key.
  if (headers["authorization"] !== `Bearer ${TEST_API_KEY}` && headers["x-api-key"] !== TEST_API_KEY) {
    return "the API key is missing or wrong";
  }
  if (!headers["anthropic-version"]) return "anthropic-version header is missing";
  if (typeof body?.model !== "string" || !body.model) return "model: required";
  if (!Number.isInteger(body.max_tokens) || body.max_tokens < 1) return "max_tokens: required";
  if (!Array.isArray(body.messages) || body.messages.length === 0) return "messages: required";
  if (body.messages[0].role !== "user") return "messages: the first message must be from the user";
  if (body.messages[body.messages.length - 1].role !== "user") return "messages: assistant prefill isn't supported";
  for (const key of ["temperature", "top_p", "top_k"]) {
    if (key in body && headers["anthropic-version"] === "2026-10-21") return `${key}: not supported on 2026-10-21`;
  }
  if (body.thinking?.type === "enabled") return "thinking.type.enabled isn't supported for this model";
  const format = body.output_config?.format;
  if (format !== undefined) {
    if (format.type !== "json_schema" || typeof format.schema !== "object") {
      return "output_config.format: expected {type: json_schema, schema}";
    }
    const withCitations = JSON.stringify(body.messages).includes('"citations":{"enabled":true}');
    if (withCitations) return "citations cannot be used together with output_config.format";
  }
  if (body.fallbacks !== undefined) {
    const betas = headers["anthropic-beta"] ?? "";
    if (body.fallbacks === "default" && !betas.includes("server-side-fallback-2026-07-01")) {
      return 'fallbacks: "default" needs the server-side-fallback-2026-07-01 beta';
    }
    if (String(body.model).startsWith("claude-haiku-5-5")) return "fallbacks aren't supported for this model";
  }
  return null;
}

export function startMockAnthropic(defaultAnswer?: () => MockAnswer, port = 0): MockAnthropic {
  const queue: MockAnswer[] = [];
  const requests: RecordedRequest[] = [];
  const server = Deno.serve({ hostname: "127.0.0.1", port, onListen() {} }, async (req) => {
    const url = new URL(req.url);
    const headers: Record<string, string> = {};
    req.headers.forEach((value, key) => (headers[key.toLowerCase()] = value));
    // deno-lint-ignore no-explicit-any
    let body: any = null;
    try {
      body = await req.json();
    } catch {
      return apiError(400, "invalid_request_error", "body: invalid JSON");
    }
    requests.push({ path: url.pathname, search: url.search, headers, body });
    if (req.method !== "POST" || url.pathname !== "/v1/messages") {
      return apiError(404, "not_found_error", `No route ${req.method} ${url.pathname}`);
    }
    const problem = shapeProblem(headers, body);
    if (problem) return apiError(400, "invalid_request_error", problem);

    const next = queue.shift() ?? defaultAnswer?.();
    if (!next) return apiError(500, "api_error", "The mock has no reply queued.");
    if ("error" in next) {
      return new Response(JSON.stringify({ type: "error", error: next.error }), {
        status: next.status,
        headers: { "content-type": "application/json", ...(next.headers ?? {}) },
      });
    }
    if ("sse" in next) {
      if (body.stream !== true) {
        return apiError(400, "invalid_request_error", "the mock queued a stream for a non-stream call");
      }
      const text = next.sse.map((e) => `event: ${e.event}\ndata: ${JSON.stringify(e.data)}\n\n`).join("");
      return new Response(text, { headers: { "content-type": "text/event-stream" } });
    }
    if (body.stream === true) return apiError(400, "invalid_request_error", "the mock queued JSON for a stream call");
    return new Response(JSON.stringify(next.json), {
      status: next.status ?? 200,
      headers: { "content-type": "application/json", "request-id": `req_mock_${requests.length}` },
    });
  });
  const addr = server.addr as Deno.NetAddr;
  return {
    url: `http://127.0.0.1:${addr.port}`,
    requests,
    answer: (reply) => queue.push(reply),
    close: () => server.shutdown(),
  };
}

export interface UsageNumbers {
  input_tokens?: number;
  output_tokens?: number;
  cache_read_input_tokens?: number;
  cache_creation_input_tokens?: number;
}

/** A Messages API reply whose text block is `value` as JSON (a structured output). */
export function messageJson(
  value: unknown,
  o: { model?: string; stop?: string; usage?: UsageNumbers; raw?: string; thinking?: boolean } = {},
): MockAnswer {
  const content: unknown[] = [];
  if (o.thinking) content.push({ type: "thinking", thinking: "", signature: "sig" });
  content.push({ type: "text", text: o.raw ?? JSON.stringify(value) });
  return {
    json: {
      id: "msg_mock",
      type: "message",
      role: "assistant",
      model: o.model ?? "claude-haiku-5-5",
      content,
      stop_reason: o.stop ?? "end_turn",
      stop_sequence: null,
      stop_details: null,
      usage: {
        input_tokens: o.usage?.input_tokens ?? 1200,
        output_tokens: o.usage?.output_tokens ?? 800,
        cache_read_input_tokens: o.usage?.cache_read_input_tokens ?? 0,
        cache_creation_input_tokens: o.usage?.cache_creation_input_tokens ?? 0,
      },
    },
  };
}

export type StreamPart = { text: string } | { cite: { source: string; title: string; cited_text: string } } | {
  error: { type: string; message: string };
};

/** A streamed Messages reply: text deltas and search-result citations in one text block, then the stop. */
export function messageStream(
  parts: StreamPart[],
  o: { model?: string; stop?: string; usage?: UsageNumbers } = {},
): MockAnswer {
  const model = o.model ?? "claude-sonnet-5-5";
  const sse: { event: string; data: unknown }[] = [{
    event: "message_start",
    data: {
      type: "message_start",
      message: {
        id: "msg_mock_stream",
        type: "message",
        role: "assistant",
        model,
        content: [],
        stop_reason: null,
        stop_sequence: null,
        usage: { input_tokens: o.usage?.input_tokens ?? 2400, output_tokens: 1 },
      },
    },
  }, {
    event: "content_block_start",
    data: { type: "content_block_start", index: 0, content_block: { type: "text", text: "", citations: [] } },
  }];
  for (const part of parts) {
    if ("text" in part) {
      sse.push({
        event: "content_block_delta",
        data: { type: "content_block_delta", index: 0, delta: { type: "text_delta", text: part.text } },
      });
    } else if ("cite" in part) {
      sse.push({
        event: "content_block_delta",
        data: {
          type: "content_block_delta",
          index: 0,
          delta: {
            type: "citations_delta",
            citation: {
              type: "search_result_location",
              source: part.cite.source,
              title: part.cite.title,
              cited_text: part.cite.cited_text,
              search_result_index: 0,
              start_block_index: 0,
              end_block_index: 1,
            },
          },
        },
      });
    } else {
      sse.push({ event: "error", data: { type: "error", error: part.error } });
      return { sse };
    }
  }
  sse.push(
    { event: "content_block_stop", data: { type: "content_block_stop", index: 0 } },
    {
      event: "message_delta",
      data: {
        type: "message_delta",
        delta: { stop_reason: o.stop ?? "end_turn", stop_sequence: null },
        usage: { output_tokens: o.usage?.output_tokens ?? 180 },
      },
    },
    { event: "message_stop", data: { type: "message_stop" } },
  );
  return { sse };
}

if (import.meta.main) {
  const generate = JSON.parse(await Deno.readTextFile(new URL("../_shared/fixtures/generate.json", import.meta.url)));
  delete generate.model;
  const mock = startMockAnthropic(() => messageJson(generate), 58499);
  // deno-lint-ignore no-console
  console.log(`Mock Anthropic API on ${mock.url} (key ${TEST_API_KEY}); every call gets the generate fixture.`);
}
