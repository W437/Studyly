// Ask Cap's assistant and web research on OpenAI, built on the tutor's provider (same key, retries and error mapping).
//
// assistant(): one round of the model with function tools. The model either answers (the tutor's strict JSON, read as it
// arrives) or calls tools. A call's arguments are read while they are written: the finished cards or questions in them
// are sent on as they exist, a note's body as it grows, and the whole call once it is complete. After tool calls the
// round ends with `done` carrying the `continuation` (the model's own reasoning and call items, nothing else), which the
// app returns with the tool results. Nothing is stored at OpenAI (`store: false`).
//
// research(): one request with OpenAI's web search, limited to the sites the relay allows, forced to search at least
// once. It reports the search as it happens (started, searching, the sources found), then the summary as text with the
// pages it rests on.

import type { AssistantCall, AssistantStreamEvent, ResearchCall, ResearchStreamEvent } from "./anthropic.ts";
import { ArrayItemStream, StringFieldStream } from "./argstream.ts";
import { isToolName, MAX_CALLS_PER_ROUND, TOOL_SPECS } from "./assistant.ts";
import type { AssistantToolName } from "./contract.ts";
import type { Usage } from "./cost.ts";
import { ApiError } from "./errors.ts";
import {
  answerEvents,
  AnswerStream,
  FORMAT,
  NETWORK,
  OpenAIProvider,
  parseReply,
  REPLY_SCHEMA,
  streamError,
} from "./openai.ts";
import { parseSse } from "./sse.ts";

interface OpenCall {
  callId: string;
  name: AssistantToolName;
  args: string;
  items?: ArrayItemStream;
  text?: StringFieldStream;
  count: number;
}

/** A page the research may show: https, on one of the allowed sites (or a subdomain of one). The search is limited to them
 * at OpenAI; this keeps the relay from passing on anything else that comes back. */
export function onAllowedSite(url: string, domains: readonly string[]): boolean {
  try {
    const u = new URL(url);
    if (u.protocol !== "https:") return false;
    const host = u.hostname.toLowerCase().replace(/^www\./, "");
    return domains.some((d) => host === d || host.endsWith(`.${d}`));
  } catch {
    return false;
  }
}

const hostOf = (url: string): string => {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return "";
  }
};

/** A page's address without the tracking OpenAI adds. */
export function cleanUrl(url: string): string {
  try {
    const u = new URL(url);
    u.searchParams.delete("utm_source");
    return u.toString().replace(/\?$/, "");
  } catch {
    return url;
  }
}

/** A search as the student reads it: the model's `site:` operators and quotes are not for people. */
export function readableQuery(query: string): string {
  return query.replace(/\bsite:\S+/gi, "").replace(/[“”"]/g, "").replace(/\s+/g, " ").trim();
}

export class OpenAIAssistantProvider extends OpenAIProvider {
  override async *assistant(call: AssistantCall): AsyncGenerator<AssistantStreamEvent> {
    const body = JSON.stringify({
      model: call.model,
      instructions: `${call.system}\n\n${FORMAT}`,
      input: call.input,
      ...(call.tools.length > 0 ? { tools: call.tools, tool_choice: "auto", parallel_tool_calls: true } : {}),
      reasoning: { effort: call.effort },
      include: ["reasoning.encrypted_content"],
      text: { format: { type: "json_schema", name: "cap_reply", strict: true, schema: REPLY_SCHEMA } },
      max_output_tokens: call.maxTokens,
      stream: true,
      store: false,
    });
    yield* this.attempts(
      call.signal,
      (signal, markSent) => this.#assistantOnce(body, signal, call, markSent),
    );
  }

  async *#assistantOnce(
    body: string,
    signal: AbortSignal,
    call: AssistantCall,
    markSent: () => void,
  ): AsyncGenerator<AssistantStreamEvent> {
    const stream = await this.open(body, signal);
    const answer = new AnswerStream();
    // The model may name any tool it has been told of in a long enough chat; only those offered this time are passed on.
    const offered = new Set<string>(call.tools.map((t) => String(t.name)));
    const calls = new Map<number, OpenCall>();
    const kept: Record<string, unknown>[] = [];
    let model = call.model;
    let raw = "";
    let streamed = "";
    let started = false;
    let refusal = false;
    let finished = false;
    let sawCall = false;
    let status = "completed";
    let usage: Usage = { inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0 };
    const start = (): AssistantStreamEvent[] => {
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
      switch (e.type) {
        case "response.created":
          if (typeof e.response?.model === "string" && e.response.model) model = e.response.model;
          break;
        case "response.output_item.added": {
          const item = e.item;
          const toolName: unknown = item?.name;
          if (
            item?.type === "function_call" && isToolName(toolName) && offered.has(toolName) &&
            typeof item.call_id === "string"
          ) {
            sawCall = true;
            if (calls.size >= MAX_CALLS_PER_ROUND) break;
            const spec = TOOL_SPECS[toolName];
            calls.set(e.output_index, {
              callId: item.call_id,
              name: toolName,
              args: "",
              items: spec.arrayKey ? new ArrayItemStream(spec.arrayKey) : undefined,
              text: spec.textKey ? new StringFieldStream(spec.textKey) : undefined,
              count: 0,
            });
            for (const event of start()) yield event;
            markSent();
            yield { type: "tool_start", callId: item.call_id, name: toolName };
          }
          break;
        }
        case "response.function_call_arguments.delta": {
          const open = calls.get(e.output_index);
          if (!open || typeof e.delta !== "string") break;
          open.args += e.delta;
          if (open.items) {
            for (const item of open.items.push(e.delta)) {
              yield { type: "tool_item", callId: open.callId, index: open.count++, item };
            }
          }
          if (open.text) {
            const piece = open.text.push(e.delta);
            if (piece) yield { type: "tool_text", callId: open.callId, text: piece };
          }
          break;
        }
        case "response.function_call_arguments.done": {
          const open = calls.get(e.output_index);
          if (open && typeof e.arguments === "string") open.args = e.arguments;
          break;
        }
        case "response.output_item.done": {
          const item = e.item;
          if (item?.type === "reasoning" && typeof item.encrypted_content === "string") {
            kept.push({ type: "reasoning", encrypted_content: item.encrypted_content, summary: [] });
          } else if (item?.type === "function_call" && calls.has(e.output_index)) {
            const open = calls.get(e.output_index)!;
            if (typeof item.arguments === "string") open.args = item.arguments;
            kept.push({ type: "function_call", call_id: open.callId, name: open.name, arguments: open.args });
          }
          break;
        }
        case "response.output_text.delta": {
          if (typeof e.delta !== "string") break;
          raw += e.delta;
          if (sawCall) break; // words after a call are not the answer; the next round writes it
          const piece = answer.push(e.delta);
          if (piece) {
            for (const event of start()) yield event;
            markSent();
            streamed += piece;
            yield { type: "delta", text: piece };
          }
          break;
        }
        case "response.refusal.delta":
          refusal = true;
          break;
        case "response.completed":
        case "response.incomplete": {
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
          break;
        }
        case "response.failed":
          throw streamError(e.response?.error?.code);
        case "error":
          throw streamError(e.code ?? e.error?.code);
      }
    }
    if (!finished) {
      throw streamed === "" && calls.size === 0
        ? NETWORK
        : new ApiError("upstream", "Cap lost the connection part way. Try again.", {}, 502);
    }

    const unreadable = () => {
      const error = new ApiError("upstream", "The answer came back unreadable. Try again.", {}, 502);
      error.usage = usage; // OpenAI billed it all the same
      return error;
    };

    if (calls.size > 0 && !refusal) {
      // The round's calls, whole. Every one is read before the app is told of any: a call cut off by the token limit makes
      // the round unusable, and half of it must not have been acted on.
      const ordered = [...calls.entries()].sort((a, b) => a[0] - b[0]).map(([, c]) => c);
      const parsed: { open: OpenCall; args: Record<string, unknown> }[] = [];
      for (const open of ordered) {
        let args: unknown;
        try {
          args = JSON.parse(open.args);
        } catch {
          throw unreadable();
        }
        if (args === null || typeof args !== "object" || Array.isArray(args)) throw unreadable();
        parsed.push({ open, args: args as Record<string, unknown> });
      }
      for (const { open, args } of parsed) {
        yield { type: "tool_call", callId: open.callId, name: open.name, arguments: args };
      }
      const names = new Set(ordered.map((c) => c.callId));
      const callItems = kept.filter((i) => i.type === "function_call" && names.has(i.call_id as string));
      // What the next round needs: the calls, and the thinking that led to them, within what the relay accepts back.
      const thinking = kept.filter((i) => i.type === "reasoning").slice(0, 2 * MAX_CALLS_PER_ROUND - callItems.length);
      const continuation = kept.filter((i) => callItems.includes(i) || thinking.includes(i));
      yield { type: "done", model, usage, stop: "tool_calls", continuation };
      return;
    }

    const reply = parseReply(raw);
    const stop = refusal || status === "content_filter"
      ? "refusal"
      : status === "max_output_tokens"
      ? "max_tokens"
      : "end_turn";
    if (reply === null && stop !== "refusal" && !(stop === "max_tokens" && streamed !== "")) throw unreadable();
    for (const event of start()) yield event;
    markSent();
    if (reply !== null) yield* answerEvents(reply, streamed, call.passages);
    yield { type: "done", model, usage, stop };
  }

  override async *research(call: ResearchCall): AsyncGenerator<ResearchStreamEvent> {
    const body = JSON.stringify({
      model: call.model,
      instructions: call.system,
      input: [{ role: "user", content: call.input }],
      tools: [{
        type: "web_search",
        search_context_size: "low",
        filters: { allowed_domains: [...call.domains] },
      }],
      tool_choice: "required",
      max_tool_calls: call.maxSearches,
      include: ["web_search_call.action.sources"],
      reasoning: { effort: call.effort },
      max_output_tokens: call.maxTokens,
      stream: true,
      store: false,
    });
    yield* this.attempts(call.signal, (signal, markSent) => this.#researchOnce(body, signal, call, markSent), 150_000);
  }

  async *#researchOnce(
    body: string,
    signal: AbortSignal,
    call: ResearchCall,
    markSent: () => void,
  ): AsyncGenerator<ResearchStreamEvent> {
    const stream = await this.open(body, signal);
    let model = call.model;
    let started = false;
    let finished = false;
    let status = "completed";
    let text = "";
    let held = "";
    let searches = 0;
    let usage: Usage = { inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0 };
    const cited = new Set<string>();
    const start = (): ResearchStreamEvent[] => {
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
      switch (e.type) {
        case "response.created":
          if (typeof e.response?.model === "string" && e.response.model) model = e.response.model;
          break;
        case "response.output_item.added":
          if (e.item?.type === "web_search_call") {
            for (const event of start()) yield event;
            markSent();
            yield { type: "search", id: String(e.item.id ?? e.output_index), phase: "started" };
          }
          break;
        case "response.web_search_call.searching":
          yield { type: "search", id: String(e.item_id ?? e.output_index), phase: "searching" };
          break;
        case "response.output_item.done":
          if (e.item?.type === "web_search_call") {
            searches++;
            const action = e.item.action ?? {};
            const queries: string[] = (Array.isArray(action.queries) ? action.queries : [action.query])
              .filter((q: unknown): q is string => typeof q === "string")
              .map(readableQuery)
              .filter((q: string) => q.length > 0);
            const seen = new Set<string>();
            const sources = (Array.isArray(action.sources) ? action.sources : [])
              .flatMap((s: { url?: unknown }) => typeof s?.url === "string" ? [cleanUrl(s.url)] : [])
              .filter((url: string) => onAllowedSite(url, call.domains) && !seen.has(url) && seen.add(url))
              .slice(0, 12)
              .map((url: string) => ({ url, domain: hostOf(url) }));
            yield { type: "search", id: String(e.item.id ?? e.output_index), phase: "done", queries, sources };
            if (held) {
              yield { type: "delta", text: held };
              held = "";
            }
          }
          break;
        case "response.output_text.delta":
          if (typeof e.delta === "string" && e.delta) {
            text += e.delta;
            // Words written before any search has finished are not research: they wait to see whether one follows.
            if (searches > 0) {
              for (const event of start()) yield event;
              markSent();
              yield { type: "delta", text: e.delta };
            } else {
              held += e.delta;
            }
          }
          break;
        case "response.output_text.annotation.added": {
          const a = e.annotation;
          if (a?.type === "url_citation" && typeof a.url === "string" && onAllowedSite(a.url, call.domains)) {
            const url = cleanUrl(a.url);
            if (!cited.has(url)) {
              cited.add(url);
              yield {
                type: "citation",
                url,
                title: typeof a.title === "string" ? a.title : hostOf(url),
                domain: hostOf(url),
              };
            }
          }
          break;
        }
        case "response.completed":
        case "response.incomplete": {
          finished = true;
          const r = e.response ?? {};
          if (typeof r.model === "string" && r.model) model = r.model;
          if (e.type === "response.incomplete") status = r.incomplete_details?.reason ?? "incomplete";
          const u = r.usage ?? {};
          const cachedTokens = Math.max(0, u.input_tokens_details?.cached_tokens ?? 0);
          usage = {
            inputTokens: Math.max(0, (u.input_tokens ?? 0) - cachedTokens),
            outputTokens: Math.max(0, u.output_tokens ?? 0),
            cacheReadTokens: cachedTokens,
            cacheWriteTokens: 0,
          };
          break;
        }
        case "response.failed":
          throw streamError(e.response?.error?.code);
        case "error":
          throw streamError(e.code ?? e.error?.code);
      }
    }
    if (!finished) {
      if (text === "" && searches === 0) throw NETWORK;
      // The searches ran and were billed whether or not the summary arrived.
      const cut = new ApiError("upstream", "Cap lost the connection part way. Try again.", {}, 502);
      cut.usage = { ...usage, webSearches: searches };
      throw cut;
    }
    usage = { ...usage, webSearches: searches };
    if (searches === 0 || text.trim() === "" || status === "content_filter") {
      const empty = new ApiError(
        "upstream",
        "Cap couldn't find anything on those sites for that. Try different words.",
        {},
        502,
      );
      empty.usage = usage;
      throw empty;
    }
    yield { type: "done", model, usage, searches };
  }
}
