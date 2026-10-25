// What a model call cost, from its token usage, in exact integer nano-dollars (no floating-point money).
// List prices per million tokens (October 2026): Claude Haiku 5.5 $0.10 in / $0.50 out for prompts up to 100K
// tokens ($0.50 / $2.50 above), Claude Sonnet 5.5 $2 / $10. Cache reads cost 0.1× input, 5-minute cache writes
// 1.25× input. Mock replies cost nothing.

export const HAIKU = "claude-haiku-5-5";
export const SONNET = "claude-sonnet-5-5";

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

const PRICES: Record<string, { standard: Rates; longPrompt?: Rates; longFrom?: number }> = {
  [HAIKU]: { standard: rates(0.10, 0.50), longPrompt: rates(0.50, 2.50), longFrom: 100_000 },
  [SONNET]: { standard: rates(2, 10) },
};

export interface Usage {
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheWriteTokens: number;
}

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
    BigInt(u.cacheReadTokens) * r.cacheRead + BigInt(u.cacheWriteTokens) * r.cacheWrite;
}

/** Nano-dollars as a decimal string with nine places: 1234n → "0.000001234". */
export function formatUsd(nano: bigint): string {
  const digits = nano.toString().padStart(10, "0");
  return `${digits.slice(0, -9)}.${digits.slice(-9)}`;
}
