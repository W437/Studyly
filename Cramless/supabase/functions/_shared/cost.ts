// What a model call cost, from its token usage, in exact integer nano-dollars (no floating-point money).
// List prices per million tokens (October 2026): Claude Haiku 5.5 $0.10 in / $0.50 out for prompts up to 100K
// tokens ($0.50 / $2.50 above), Claude Sonnet 5.5 $2 / $10. Cache reads cost 0.1× input, 5-minute cache writes
// 1.25× input. Ask Cap's tutor on OpenAI (standard tier, prompts up to 272K tokens): GPT 6.1 Terra $1 / $5 with cached
// input at $0.05, GPT 6.1 Sol $2 / $10 with $0.10, GPT 6 Luna $0.10 / $0.50 with $0.01; thinking tokens are billed as
// output, and a cache write costs the same as other input. A web search costs $10 per 1,000 on top of the tokens it
// reads. Mock replies cost nothing.

export const HAIKU = "claude-haiku-5-5";
export const SONNET = "claude-sonnet-5-5";
export const TERRA = "gpt-6.1-terra";
export const SOL = "gpt-6.1-sol";
export const LUNA = "gpt-6-luna";

/** Nano-dollars per token: $1 per million tokens is 1,000 nano-dollars per token. */
interface Rates {
  input: bigint;
  output: bigint;
  cacheRead: bigint;
  cacheWrite: bigint;
}

function rates(inputPerMillion: number, outputPerMillion: number): Rates {
  const n = (dollars: number) => BigInt(Math.round(dollars * 1000));
  return {
    input: n(inputPerMillion),
    output: n(outputPerMillion),
    cacheRead: n(inputPerMillion * 0.1),
    cacheWrite: n(inputPerMillion * 1.25),
  };
}

function openaiRates(inputPerMillion: number, cachedPerMillion: number, outputPerMillion: number): Rates {
  const n = (dollars: number) => BigInt(Math.round(dollars * 1000));
  return {
    input: n(inputPerMillion),
    output: n(outputPerMillion),
    cacheRead: n(cachedPerMillion),
    cacheWrite: n(inputPerMillion),
  };
}

const PRICES: Record<string, { standard: Rates; longPrompt?: Rates; longFrom?: number }> = {
  [HAIKU]: { standard: rates(0.10, 0.50), longPrompt: rates(0.50, 2.50), longFrom: 100_000 },
  [SONNET]: { standard: rates(2, 10) },
  [TERRA]: { standard: openaiRates(1, 0.05, 5) },
  [SOL]: { standard: openaiRates(2, 0.10, 10) },
  [LUNA]: { standard: openaiRates(0.10, 0.01, 0.50) },
};

export interface Usage {
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheWriteTokens: number;
  /** Web searches the call made: OpenAI bills each on top of the tokens it reads ($10 per 1,000). */
  webSearches?: number;
}

/** What one web search costs, in nano-dollars: $10 per 1,000 calls. */
export const WEB_SEARCH_NANO = 10_000_000n;

export const ZERO_USAGE: Usage = { inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0 };

/** The SDK's usage object (input_tokens excludes cached tokens) in our shape. */
// deno-lint-ignore no-explicit-any
export function readUsage(usage: any): Usage {
  const n = (v: unknown) => (typeof v === "number" && Number.isFinite(v) && v >= 0 ? Math.floor(v) : 0);
  return {
    inputTokens: n(usage?.input_tokens),
    outputTokens: n(usage?.output_tokens),
    cacheReadTokens: n(usage?.cache_read_input_tokens),
    cacheWriteTokens: n(usage?.cache_creation_input_tokens),
  };
}

export function addUsage(a: Usage, b: Usage): Usage {
  return {
    inputTokens: a.inputTokens + b.inputTokens,
    outputTokens: a.outputTokens + b.outputTokens,
    cacheReadTokens: a.cacheReadTokens + b.cacheReadTokens,
    cacheWriteTokens: a.cacheWriteTokens + b.cacheWriteTokens,
    ...((a.webSearches ?? 0) + (b.webSearches ?? 0) > 0
      ? { webSearches: (a.webSearches ?? 0) + (b.webSearches ?? 0) }
      : {}),
  };
}

/** The cost in nano-dollars. Unknown models (a server-side fallback to another model) are priced as Sonnet. */
export function costNano(model: string, u: Usage): bigint {
  const price = PRICES[model] ?? PRICES[Object.keys(PRICES).find((m) => model.startsWith(m)) ?? SONNET] ??
    PRICES[SONNET];
  const prompt = u.inputTokens + u.cacheReadTokens + u.cacheWriteTokens;
  const r = price.longPrompt && price.longFrom !== undefined && prompt > price.longFrom
    ? price.longPrompt
    : price.standard;
  return BigInt(u.inputTokens) * r.input + BigInt(u.outputTokens) * r.output +
    BigInt(u.cacheReadTokens) * r.cacheRead + BigInt(u.cacheWriteTokens) * r.cacheWrite +
    BigInt(Math.max(0, Math.floor(u.webSearches ?? 0))) * WEB_SEARCH_NANO;
}

/** Nano-dollars as a decimal string with nine places: 1234n → "0.000001234". */
export function formatUsd(nano: bigint): string {
  const digits = nano.toString().padStart(10, "0");
  return `${digits.slice(0, -9)}.${digits.slice(-9)}`;
}

/** Decimal dollars, at most nine places, as nano-dollars: "0.10" → 100000000n. The inverse of formatUsd; null when the text isn't one. */
export function parseUsd(text: string): bigint | null {
  const m = /^(\d{1,6})(?:\.(\d{1,9}))?$/.exec(text.trim());
  if (!m) return null;
  return BigInt(m[1]) * 1_000_000_000n + BigInt((m[2] ?? "").padEnd(9, "0"));
}

/** What one person's model calls may cost in a day before the relay stops taking requests for them until local midnight: 10¢.
 * A safety net under the meters, which count requests and not money (a Pro subscriber's fair-use ceilings alone would cost more than
 * a yearly plan nets, about 12¢ a day). A normal day costs a few cents. It starts as a guess to tune from real use
 * (DAILY_COST_CAP_USD; 0 turns it off). */
export const DEFAULT_DAILY_COST_CAP_NANO = 100_000_000n;
