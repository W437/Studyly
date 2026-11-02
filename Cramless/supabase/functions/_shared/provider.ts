// The model API as the relay's routes use it: the call shapes, the events they stream back and the Provider interface.
// OpenAI implements it (openai.ts for the JSON routes and the tutor, openai_assistant.ts for the assistant and web
// research); tests swap in their own. Nothing here talks to a network, and nothing logs or keeps the person's content.

import type { Usage } from "./cost.ts";
import { ApiError } from "./errors.ts";
import type { Schema } from "./schema.ts";

export type Effort = "low" | "medium" | "high";

/** A piece of a model request: text, or a photo (base64 image data and its media type). */
export type ContentBlock =
  | { type: "text"; text: string }
  | { type: "image"; mediaType: string; data: string }
  /** A passage of the person's material for the tutor: its id, a title and its text in sentence-sized blocks. */
  | { type: "search_result"; source: string; title: string; content: { type: "text"; text: string }[] };

/** One turn of the tutor's conversation: plain text, or blocks (the last turn carries the passages). */
export interface Message {
  role: "user" | "assistant";
  content: string | ContentBlock[];
}

export interface JsonCall {
  model: string;
  effort: Effort;
  maxTokens: number;
  system: string;
  content: ContentBlock[];
  schema: Schema;
  signal?: AbortSignal;
}

export interface JsonResult<T> {
  value: T;
  /** The model that answered. */
  model: string;
  usage: Usage;
}

export interface TutorCall {
  model: string;
  effort: Effort;
  maxTokens: number;
  system: string;
  messages: Message[];
  signal?: AbortSignal;
}

export type TutorStreamEvent =
  | { type: "start"; model: string }
  | { type: "delta"; text: string }
  | { type: "citation"; source: string; quote: string }
  | { type: "done"; model: string; usage: Usage; stop: string };

/** One round of the assistant: the model's input already built (instructions, the chat with its passages, the earlier
 * rounds' items and results) and the function tools it may call. */
export interface AssistantCall {
  model: string;
  effort: Effort;
  maxTokens: number;
  system: string;
  input: Record<string, unknown>[];
  /** OpenAI function tools (strict); empty when the model may only answer. */
  tools: Record<string, unknown>[];
  /** The passages the app sent, to check the quotes the model cites. */
  passages: { id: string; folded: string }[];
  signal?: AbortSignal;
}

export type AssistantStreamEvent =
  | { type: "start"; model: string }
  | { type: "delta"; text: string }
  | { type: "citation"; source: string; quote: string }
  /** The model began a call. */
  | { type: "tool_start"; callId: string; name: string }
  /** One finished element of the call's streamed array (a card, a question). */
  | { type: "tool_item"; callId: string; index: number; item: unknown }
  /** A piece of the call's streamed text (a note's body). */
  | { type: "tool_text"; callId: string; text: string }
  /** The call, whole. */
  | { type: "tool_call"; callId: string; name: string; arguments: Record<string, unknown> }
  | {
    type: "done";
    model: string;
    usage: Usage;
    stop: string;
    /** After tool calls: the items the next round needs, opaque to the app. */
    continuation?: Record<string, unknown>[];
  };

export interface ResearchCall {
  model: string;
  effort: Effort;
  maxTokens: number;
  system: string;
  input: string;
  /** The only sites the search may read. */
  domains: readonly string[];
  maxSearches: number;
  signal?: AbortSignal;
}

export type ResearchStreamEvent =
  | { type: "start"; model: string }
  | {
    type: "search";
    id: string;
    phase: "started" | "searching" | "done";
    queries?: string[];
    sources?: { url: string; domain: string }[];
  }
  | { type: "delta"; text: string }
  | { type: "citation"; url: string; title: string; domain: string }
  | { type: "done"; model: string; usage: Usage; searches: number };

/** The model API as the routes use it; tests swap in their own. */
export interface Provider {
  json<T>(call: JsonCall): Promise<JsonResult<T>>;
  tutor(call: TutorCall): AsyncGenerator<TutorStreamEvent>;
  assistant(call: AssistantCall): AsyncGenerator<AssistantStreamEvent>;
  research(call: ResearchCall): AsyncGenerator<ResearchStreamEvent>;
}

/** The model API as the routes use it; tests swap in their own. */
export interface Provider {
  json<T>(call: JsonCall): Promise<JsonResult<T>>;
  tutor(call: TutorCall): AsyncGenerator<TutorStreamEvent>;
  assistant(call: AssistantCall): AsyncGenerator<AssistantStreamEvent>;
  research(call: ResearchCall): AsyncGenerator<ResearchStreamEvent>;
}

/** Anything thrown by a provider, as the contract's `upstream`: errors already mapped pass through. */
export function providerError(error: unknown): ApiError {
  if (error instanceof ApiError) return error;
  return new ApiError("upstream", "Cap couldn't be reached. Try again in a moment.", {}, 502);
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
  // deno-lint-ignore require-yield
  async *assistant(): AsyncGenerator<AssistantStreamEvent> {
    throw new ApiError("upstream", "Cloud AI isn't set up on this server.", {}, 503);
  }
  // deno-lint-ignore require-yield
  async *research(): AsyncGenerator<ResearchStreamEvent> {
    throw new ApiError("upstream", "Cloud AI isn't set up on this server.", {}, 503);
  }
}
