// Everything a function needs, injectable, so tests swap the clock, the sleeper, the store, the authenticator,
// the model provider (or only its base URL) and the App Store roots.

import { AnthropicProvider, type Effort, MissingKeyProvider, type Provider } from "./anthropic.ts";
import { type Authenticate, goTrueAuthenticator } from "./auth.ts";
import { SONNET } from "./cost.ts";
import { type Env, envFromDeno } from "./env.ts";
import { withTutor } from "./openai.ts";
import { OpenAIAssistantProvider } from "./openai_assistant.ts";
import { createAdmin, PostgresStore } from "./store_postgres.ts";
import type { Store } from "./store.ts";
import { appleRoots, buildVerifiers, type Verifiers } from "./appstore/verifier.ts";

export interface Deps {
  env: Env;
  store: Store;
  provider: Provider;
  /** The model that answers the tutor and how hard it thinks: OpenAI's when the key is set, else Claude Sonnet. */
  tutorModel: string;
  tutorEffort: Effort;
  authenticate: Authenticate;
  verifiers: Verifiers;
  now: () => Date;
  /** Resolves after `ms`, or early when the signal aborts. */
  sleep: (ms: number, signal?: AbortSignal) => Promise<void>;
  /** 0 ≤ x < 1, for invite codes. */
  random: () => number;
  /** Work that finishes after the response (EdgeRuntime.waitUntil on the platform). */
  background: (task: Promise<unknown>) => void;
  pingIntervalMs: number;
}

export function realSleep(ms: number, signal?: AbortSignal): Promise<void> {
  return new Promise((resolve) => {
    if (ms <= 0 || signal?.aborted) return resolve();
    const timer = setTimeout(done, ms);
    function done() {
      clearTimeout(timer);
      signal?.removeEventListener("abort", done);
      resolve();
    }
    signal?.addEventListener("abort", done, { once: true });
  });
}

/** EdgeRuntime.waitUntil when the platform has it; otherwise the task just runs. */
export function platformBackground(task: Promise<unknown>): void {
  const settled = task.catch(() => {});
  // deno-lint-ignore no-explicit-any
  const edge = (globalThis as any).EdgeRuntime;
  if (typeof edge?.waitUntil === "function") edge.waitUntil(settled);
}

export function cryptoRandom(): number {
  const buf = new Uint32Array(1);
  crypto.getRandomValues(buf);
  return buf[0] / 0x1_0000_0000;
}

/** The production wiring, from the environment the platform provides. */
export function defaultDeps(overrides: Partial<Deps> = {}): Deps {
  const env = overrides.env ?? envFromDeno();
  const admin = createAdmin(env.supabaseUrl, env.serviceRoleKey);
  const claude = env.anthropicApiKey
    ? new AnthropicProvider({ apiKey: env.anthropicApiKey, baseURL: env.anthropicBaseUrl || undefined })
    : new MissingKeyProvider();
  // With an OpenAI key the tutor, the assistant and web research run on OpenAI; every other route stays on Claude.
  const openai = env.openaiApiKey !== "";
  const provider = overrides.provider ??
    (openai
      ? withTutor(claude, new OpenAIAssistantProvider({ apiKey: env.openaiApiKey, baseURL: env.openaiBaseUrl }))
      : claude);
  return {
    env,
    store: overrides.store ?? new PostgresStore(admin),
    provider,
    tutorModel: overrides.tutorModel ?? (openai ? env.tutorModel : SONNET),
    tutorEffort: overrides.tutorEffort ?? (openai ? env.tutorEffort : "low"),
    authenticate: overrides.authenticate ?? goTrueAuthenticator(admin),
    verifiers: overrides.verifiers ??
      buildVerifiers({
        roots: appleRoots(),
        bundleId: env.bundleId,
        // The Production verifier needs a value; without the secret, Production notifications fail the app check
        // (a cold-start fault says so) while transactions, which carry no app ID, still verify.
        appAppleId: env.appAppleId ?? 0,
        allowXcode: env.allowXcodeJws,
      }),
    now: overrides.now ?? (() => new Date()),
    sleep: overrides.sleep ?? realSleep,
    random: overrides.random ?? cryptoRandom,
    background: overrides.background ?? platformBackground,
    pingIntervalMs: overrides.pingIntervalMs ?? 10_000,
  };
}
