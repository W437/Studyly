// The models under test and what they cost. USD per million tokens, standard tier, from OpenAI's pricing page and
// each model's page on 2026-10-26 (the three agree). Reasoning tokens are billed as output.

export interface Config {
  id: string;
  model: string;
  effort: "none" | "low" | "medium";
}

export const PRICES: Record<string, { input: number; cachedInput: number; output: number }> = {
  "gpt-6.1-sol": { input: 2.0, cachedInput: 0.10, output: 10.0 },
  "gpt-6.1-terra": { input: 1.0, cachedInput: 0.05, output: 5.0 },
  "gpt-6-luna": { input: 0.10, cachedInput: 0.01, output: 0.50 },
};

// Sol has no "none". The first config is the one the owner picked.
export const CONFIGS: Config[] = [
  { id: "sol-medium", model: "gpt-6.1-sol", effort: "medium" },
  { id: "sol-low", model: "gpt-6.1-sol", effort: "low" },
  { id: "terra-medium", model: "gpt-6.1-terra", effort: "medium" },
  { id: "terra-low", model: "gpt-6.1-terra", effort: "low" },
  { id: "terra-none", model: "gpt-6.1-terra", effort: "none" },
  { id: "luna-medium", model: "gpt-6-luna", effort: "medium" },
  { id: "luna-low", model: "gpt-6-luna", effort: "low" },
  { id: "luna-none", model: "gpt-6-luna", effort: "none" },
];

export interface Usage {
  input: number;
  cached: number;
  output: number;
  reasoning: number;
}

export function costUsd(model: string, u: Usage): number {
  const p = PRICES[model];
  return ((u.input - u.cached) * p.input + u.cached * p.cachedInput + u.output * p.output) / 1_000_000;
}
