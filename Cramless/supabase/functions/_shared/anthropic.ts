// The cloud model, through the official Anthropic TypeScript SDK. Two shapes of call:
// - json: one Messages request with a structured output (output_config.format, a JSON schema derived from the
//   contract), read from the reply's text block and validated again here.
// - tutor: a streamed request over the person's passages as search_result blocks with citations on, read as
//   text deltas and citations (search_result_location) and handed on as the contract's normalized events.
// Claude Sonnet 5.5 calls go through the beta Messages API with server-side refusal fallback ("default").
// Claude Haiku 5.5 has no server-side fallback, so its calls use the plain Messages API.
// Nothing here logs or keeps the person's content.

import Anthropic from "@anthropic-ai/sdk";
import { readUsage, SONNET, type Usage } from "./cost.ts";
import { ApiError } from "./errors.ts";
import { describeIssues, type Schema, validate } from "./schema.ts";

export type Effort = "low" | "medium" | "high";

/** Server-side fallback when Claude Sonnet 5.5 declines (cyber and frontier_llm declines retry on Sonnet 5). */
export const FALLBACK_BETA = "server-side-fallback-2026-07-01";

export interface JsonCall {
  model: string;
  effort: Effort;
  maxTokens: number;
  system: string;
  content: Anthropic.ContentBlockParam[];
  schema: Schema;
  signal?: AbortSignal;
}

export interface JsonResult<T> {
  value: T;
  /** The model that answered (after a fallback, the fallback's). */
  model: string;
  usage: Usage;
}

export interface TutorCall {
  model: string;
  effort: Effort;
  maxTokens: number;
  system: string;
  messages: Anthropic.MessageParam[];
  signal?: AbortSignal;
}

export type TutorStreamEvent =
  | { type: "start"; model: string }
  | { type: "delta"; text: string }
  | { type: "citation"; source: string; quote: string }
  | { type: "done"; model: string; usage: Usage; stop: string };

/** The model API as the routes use it; tests swap in their own. */
export interface Provider {
  json<T>(call: JsonCall): Promise<JsonResult<T>>;
  tutor(call: TutorCall): AsyncGenerator<TutorStreamEvent>;
}

/** The SDK's errors, and the stop reasons we can't use, as the contract's `upstream`. */
export function providerError(error: unknown): ApiError {
  if (error instanceof ApiError) return error;
  if (error instanceof Anthropic.APIUserAbortError) {
    return new ApiError("upstream", "The request was cancelled.", {}, 499);
  }
  if (error instanceof Anthropic.APIConnectionTimeoutError) {
    return new ApiError("upstream", "Cap took too long to answer. Try again in a moment.", {}, 504);
  }
  if (error instanceof Anthropic.RateLimitError) {
    const retry = Number(error.headers?.get?.("retry-after") ?? "");
    return new ApiError("upstream", "Cap is busy right now. Try again in a moment.", {
      retryAfter: Number.isFinite(retry) && retry > 0 ? retry : 20,
    }, 503);
  }
  if (error instanceof Anthropic.InternalServerError || (error instanceof Anthropic.APIError && error.status === 529)) {
    return new ApiError("upstream", "Cap is busy right now. Try again in a moment.", { retryAfter: 15 }, 503);
  }
  if (error instanceof Anthropic.APIError) {
    return new ApiError("upstream", "Cap couldn't answer that. Try again in a moment.", {}, 502);
  }
  return new ApiError("upstream", "Cap couldn't be reached. Try again in a moment.", {}, 502);
}

const cachedSystem = (text: string): Anthropic.TextBlockParam[] => [
  { type: "text", text, cache_control: { type: "ephemeral" } },
];

/** The first text block's JSON, checked against the schema. */
// deno-lint-ignore no-explicit-any
function readJson<T>(content: readonly any[], stop: string | null | undefined, schema: Schema): T {
  if (stop === "refusal") throw new ApiError("upstream", "Cap can't help with that request.", {}, 422);
  if (stop === "max_tokens") throw new ApiError("upstream", "The answer came back cut off. Try again.", {}, 502);
  const block = content.find((b) => b?.type === "text");
  if (!block || typeof block.text !== "string") {
    throw new ApiError("upstream", "The answer came back empty. Try again.", {}, 502);
  }
  let value: unknown;
  try {
    value = JSON.parse(block.text);
  } catch {
    throw new ApiError("upstream", "The answer came back unreadable. Try again.", {}, 502);
  }
  const issues = validate(schema, value);
  if (issues.length > 0) {
    throw new ApiError("upstream", `The answer didn't match the contract (${describeIssues(issues)}).`, {}, 502);
  }
  return value as T;
}

export interface ProviderOptions {
  apiKey: string;
  /** Tests point this at the mock server; empty for the SDK's default. */
  baseURL?: string;
  timeoutMs?: number;
  maxRetries?: number;
  fetch?: typeof fetch;
}

export class AnthropicProvider implements Provider {
  readonly #client: Anthropic;

  constructor(options: ProviderOptions) {
    this.#client = new Anthropic({
      apiKey: options.apiKey,
      ...(options.baseURL ? { baseURL: options.baseURL } : {}),
      timeout: options.timeoutMs ?? 90_000,
      maxRetries: options.maxRetries ?? 1,
      ...(options.fetch ? { fetch: options.fetch } : {}),
    });
  }

  async json<T>(call: JsonCall): Promise<JsonResult<T>> {
    const output_config: Anthropic.OutputConfig = {
      effort: call.effort,
      format: { type: "json_schema", schema: call.schema },
    };
    try {
      if (call.model === SONNET) {
        const message = await this.#client.beta.messages.create({
          model: call.model,
          max_tokens: call.maxTokens,
          betas: [FALLBACK_BETA],
          fallbacks: "default",
          system: cachedSystem(call.system),
          // The beta and GA block params have the same shape for text, image and search_result blocks.
          messages: [{ role: "user", content: call.content as Anthropic.Beta.BetaContentBlockParam[] }],
          output_config,
        }, { signal: call.signal });
        return {
          value: readJson<T>(message.content, message.stop_reason, call.schema),
          model: message.model,
          usage: readUsage(message.usage),
        };
      }
      const message = await this.#client.messages.create({
        model: call.model,
        max_tokens: call.maxTokens,
        system: cachedSystem(call.system),
        messages: [{ role: "user", content: call.content }],
        output_config,
      }, { signal: call.signal });
      return {
        value: readJson<T>(message.content, message.stop_reason, call.schema),
        model: message.model,
        usage: readUsage(message.usage),
      };
    } catch (error) {
      throw providerError(error);
    }
  }

  async *tutor(call: TutorCall): AsyncGenerator<TutorStreamEvent> {
    const stream = this.#client.beta.messages.stream({
      model: call.model,
      max_tokens: call.maxTokens,
      betas: [FALLBACK_BETA],
      fallbacks: "default",
      system: cachedSystem(call.system),
      messages: call.messages as Anthropic.Beta.BetaMessageParam[],
      output_config: { effort: call.effort },
    }, { signal: call.signal });
    let finished = false;
    try {
      for await (const event of stream) {
        if (event.type === "message_start") {
          yield { type: "start", model: event.message.model };
        } else if (event.type === "content_block_delta") {
          if (event.delta.type === "text_delta") {
            if (event.delta.text) yield { type: "delta", text: event.delta.text };
          } else if (event.delta.type === "citations_delta" && event.delta.citation.type === "search_result_location") {
            yield { type: "citation", source: event.delta.citation.source, quote: event.delta.citation.cited_text };
          }
        }
      }
      const final = await stream.finalMessage();
      finished = true;
      yield { type: "done", model: final.model, usage: readUsage(final.usage), stop: final.stop_reason ?? "" };
    } catch (error) {
      throw providerError(error);
    } finally {
      // The consumer stopped early (the person left): close the connection to the model.
      if (!finished) stream.abort();
    }
  }
}

/** A provider that refuses every call: real mode without a key. */
export class MissingKeyProvider implements Provider {
  json<T>(): Promise<JsonResult<T>> {
    return Promise.reject(new ApiError("upstream", "Cloud AI isn't set up on this server.", {}, 503));
  }
  // deno-lint-ignore require-yield
  async *tutor(): AsyncGenerator<TutorStreamEvent> {
    throw new ApiError("upstream", "Cloud AI isn't set up on this server.", {}, 503);
  }
}
