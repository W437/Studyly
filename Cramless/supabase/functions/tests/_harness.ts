// Shared test setup. The handlers run in-process with injected dependencies: a fixed clock, a sleeper that
// records instead of waiting, the in-memory store, an authenticator that knows test tokens, and either a scripted
// provider or the real OpenAI provider pointed at the local mock server.

import {
  type AssistantCall,
  type AssistantStreamEvent,
  type Effort,
  type JsonCall,
  type JsonResult,
  type Provider,
  type ResearchCall,
  type ResearchStreamEvent,
  type TutorCall,
  type TutorStreamEvent,
} from "../_shared/provider.ts";
import type { Authenticate, Caller } from "../_shared/auth.ts";
import type { QuotaStatus } from "../_shared/contract.ts";
import { TERRA, ZERO_USAGE } from "../_shared/cost.ts";
import type { Deps } from "../_shared/deps.ts";
import { type Env, envFrom } from "../_shared/env.ts";
import { ApiError } from "../_shared/errors.ts";
import { FIXTURES } from "../_shared/generated.ts";
import { setLogSink } from "../_shared/log.ts";
import { parseSse } from "../_shared/sse.ts";
import { buildVerifiers, type Verifiers } from "../_shared/appstore/verifier.ts";
import { aiHandler } from "../ai/handler.ts";
import { accountHandler } from "../account/handler.ts";
import { appstoreNotifyHandler } from "../appstore-notify/handler.ts";
import { MemoryStore } from "./_memory_store.ts";
import { TEST_OPENAI_KEY } from "./_mock_openai.ts";
import { OpenAIAssistantProvider } from "../_shared/openai_assistant.ts";

/** Thursday 22 October 2026, 09:00 UTC. The week started on Monday the 19th. */
export const NOW = "2026-10-22T09:00:00Z";
export const BUNDLE_ID = "com.loopware.Capling";
export const APP_APPLE_ID = 6_700_000_001;

// Log lines go nowhere in tests; capture them where a test needs to read them.
export const logLines: string[] = [];
setLogSink((line) => logLines.push(line));

export class TestClock {
  #ms: number;
  constructor(start = NOW) {
    this.#ms = Date.parse(start);
  }
  now = (): Date => new Date(this.#ms);
  set(at: string): void {
    this.#ms = Date.parse(at);
  }
  advance(ms: number): void {
    this.#ms += ms;
  }
}

export function testEnv(vars: Record<string, string> = {}): Env {
  const all: Record<string, string> = {
    SUPABASE_URL: "http://127.0.0.1:58421",
    SUPABASE_SERVICE_ROLE_KEY: "service-role-key",
    OPENAI_API_KEY: TEST_OPENAI_KEY,
    ...vars,
  };
  return envFrom((name) => all[name] ?? "");
}

/** Test tokens are `token-<user id>`; anything else is refused. */
export function tokenAuthenticator(anonymous: Set<string> = new Set()): Authenticate {
  return (req: Request): Promise<Caller> => {
    const header = req.headers.get("authorization") ?? "";
    const m = /^Bearer token-(.+)$/.exec(header);
    if (!m) return Promise.reject(new ApiError("unauthorized", "Sign in again to use this."));
    return Promise.resolve({ userId: m[1], isAnonymous: anonymous.has(m[1]), email: null });
  };
}

/** A provider that answers from a script and records every call. */
export class ScriptedProvider implements Provider {
  readonly jsonCalls: JsonCall[] = [];
  readonly tutorCalls: TutorCall[] = [];
  readonly assistantCalls: AssistantCall[] = [];
  readonly researchCalls: ResearchCall[] = [];
  readonly #json: (JsonResult<unknown> | Error)[] = [];
  readonly #tutor: (TutorStreamEvent | Error)[][] = [];
  readonly #assistant: (AssistantStreamEvent | Error)[][] = [];
  readonly #research: (ResearchStreamEvent | Error)[][] = [];

  replyJson(value: unknown, model = TERRA): void {
    this.#json.push({
      value,
      model,
      usage: { inputTokens: 1000, outputTokens: 500, cacheReadTokens: 0, cacheWriteTokens: 0 },
    });
  }
  failJson(error: Error): void {
    this.#json.push(error);
  }
  replyTutor(events: (TutorStreamEvent | Error)[]): void {
    this.#tutor.push(events);
  }
  replyAssistant(events: (AssistantStreamEvent | Error)[]): void {
    this.#assistant.push(events);
  }
  replyResearch(events: (ResearchStreamEvent | Error)[]): void {
    this.#research.push(events);
  }

  json<T>(call: JsonCall): Promise<JsonResult<T>> {
    this.jsonCalls.push(call);
    const next = this.#json.shift();
    if (!next) return Promise.reject(new Error("no scripted reply"));
    if (next instanceof Error) return Promise.reject(next);
    return Promise.resolve(next as JsonResult<T>);
  }

  async *tutor(call: TutorCall): AsyncGenerator<TutorStreamEvent> {
    this.tutorCalls.push(call);
    for (const event of this.#tutor.shift() ?? []) {
      await Promise.resolve();
      if (event instanceof Error) throw event;
      yield event;
    }
  }

  async *assistant(call: AssistantCall): AsyncGenerator<AssistantStreamEvent> {
    this.assistantCalls.push(call);
    for (const event of this.#assistant.shift() ?? []) {
      await Promise.resolve();
      if (event instanceof Error) throw event;
      yield event;
    }
  }

  async *research(call: ResearchCall): AsyncGenerator<ResearchStreamEvent> {
    this.researchCalls.push(call);
    for (const event of this.#research.shift() ?? []) {
      await Promise.resolve();
      if (event instanceof Error) throw event;
      yield event;
    }
  }
}

export interface TestRig {
  deps: Deps;
  store: MemoryStore;
  clock: TestClock;
  provider: Provider;
  sleeps: number[];
  /** Waits for the work handlers left running after their response (the tutor stream, ai_requests rows). */
  settle(): Promise<void>;
  ai(path: string, init?: RequestOptions): Promise<Response>;
  account(path: string, init?: RequestOptions): Promise<Response>;
  notify(body: unknown): Promise<Response>;
}

export interface RequestOptions {
  method?: string;
  /** A user id (sent as `token-<id>`), or null for no Authorization header. */
  user?: string | null;
  body?: unknown;
  rawBody?: string;
  headers?: Record<string, string>;
  signal?: AbortSignal;
}

export interface RigOptions {
  env?: Record<string, string>;
  provider?: Provider;
  /** The model that answers the tutor (Terra unless a test says otherwise) and how hard it thinks. */
  tutorModel?: string;
  tutorEffort?: Effort;
  verifiers?: Verifiers;
  random?: () => number;
  anonymous?: Set<string>;
  store?: MemoryStore;
}

export function rig(o: RigOptions = {}): TestRig {
  const store = o.store ?? new MemoryStore();
  const clock = new TestClock();
  const sleeps: number[] = [];
  const pending: Promise<unknown>[] = [];
  const provider = o.provider ?? new ScriptedProvider();
  const deps: Deps = {
    env: testEnv(o.env),
    store,
    provider,
    tutorModel: o.tutorModel ?? TERRA,
    tutorEffort: o.tutorEffort ?? "low",
    authenticate: tokenAuthenticator(o.anonymous),
    verifiers: o.verifiers ??
      buildVerifiers({ roots: [], bundleId: BUNDLE_ID, appAppleId: APP_APPLE_ID, allowXcode: false }),
    now: clock.now,
    sleep: (ms) => {
      sleeps.push(ms);
      return Promise.resolve();
    },
    random: o.random ?? Math.random,
    background: (task) => {
      pending.push(task.catch(() => {}));
    },
    pingIntervalMs: 60_000,
  };
  const ai = aiHandler(deps);
  const account = accountHandler(deps);
  const notify = appstoreNotifyHandler(deps);
  const request = (base: string, path: string, init: RequestOptions = {}) => {
    const headers = new Headers(init.headers ?? {});
    const user = init.user === undefined ? "user-1" : init.user;
    if (user !== null) headers.set("authorization", `Bearer token-${user}`);
    let body: string | undefined = init.rawBody;
    if (init.body !== undefined) {
      body = JSON.stringify(init.body);
      headers.set("content-type", "application/json");
    }
    const method = init.method ?? (body !== undefined ? "POST" : "GET");
    return new Request(`http://localhost/functions/v1/${base}/${path}`, { method, headers, body, signal: init.signal });
  };
  return {
    deps,
    store,
    clock,
    provider,
    sleeps,
    settle: async () => {
      while (pending.length > 0) await pending.shift();
    },
    ai: (path, init) => ai(request("ai", path, init)),
    account: (path, init) => account(request("account", path, init)),
    notify: (body) =>
      notify(
        new Request("http://localhost/functions/v1/appstore-notify", { method: "POST", body: JSON.stringify(body) }),
      ),
  };
}

/** The relay's real provider pointed at the mock server; no retries, short timeout. */
export function mockedProvider(mockUrl: string): OpenAIAssistantProvider {
  return new OpenAIAssistantProvider({
    apiKey: TEST_OPENAI_KEY,
    baseURL: `${mockUrl}/v1`,
    maxRetries: 0,
    retryDelayMs: 0,
    timeoutMs: 10_000,
  });
}

export function fixture(name: string): string {
  const text = FIXTURES[name];
  if (text === undefined) throw new Error(`no fixture ${name}`);
  return text;
}

// deno-lint-ignore no-explicit-any
export function fixtureJson(name: string): any {
  return JSON.parse(fixture(name));
}

/** The SSE events of a response, data parsed. */
// deno-lint-ignore no-explicit-any
export async function sseEvents(res: Response): Promise<{ event: string; data: Record<string, any> }[]> {
  // deno-lint-ignore no-explicit-any
  const out: { event: string; data: Record<string, any> }[] = [];
  for await (const message of parseSse(res.body!)) {
    out.push({ event: message.event ?? "message", data: JSON.parse(message.data) });
  }
  return out;
}

export async function errorOf(
  res: Response,
): Promise<{ code: string; message: string; quota?: QuotaStatus; retryAfter?: number }> {
  const body = await res.json();
  return body.error;
}

export { ZERO_USAGE };
