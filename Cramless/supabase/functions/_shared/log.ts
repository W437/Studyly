// The only module that writes to the console (tests/hygiene.test.ts checks it). One JSON line per request, with
// an allow-list of fields. Never logged: request or response bodies, prompts, the person's material or answers,
// user ids, tokens, IPs.

export interface LogFields {
  fn: string;
  route: string;
  status: number;
  code?: string | null;
  latency_ms?: number;
  plan?: string;
  model?: string;
  mock?: boolean;
  input_tokens?: number;
  output_tokens?: number;
  cache_read_tokens?: number;
  cache_write_tokens?: number;
  cost_usd?: string;
  stop?: string;
  upstream?: string;
}

const ALLOWED: ReadonlySet<string> = new Set([
  "fn",
  "route",
  "status",
  "code",
  "latency_ms",
  "plan",
  "model",
  "mock",
  "input_tokens",
  "output_tokens",
  "cache_read_tokens",
  "cache_write_tokens",
  "cost_usd",
  "stop",
  "upstream",
]);

type Sink = (line: string) => void;

// deno-lint-ignore no-console
let sink: Sink = (line) => console.log(line);

/** Tests replace the sink to capture or silence log lines. Returns the previous one. */
export function setLogSink(next: Sink): Sink {
  const previous = sink;
  sink = next;
  return previous;
}

/** Writes one JSON line holding only the allowed fields (strings capped at 64 characters). */
export function log(fields: LogFields): void {
  const line: Record<string, unknown> = { t: new Date().toISOString() };
  for (const [key, value] of Object.entries(fields)) {
    if (!ALLOWED.has(key) || value === undefined || value === null) continue;
    if (typeof value === "string" && value.length > 64) continue;
    line[key] = value;
  }
  sink(JSON.stringify(line));
}

/** A configuration problem, logged at every cold start until it's fixed. */
export function logFault(fn: string, code: string): void {
  log({ fn, route: "fault", status: 0, code });
}
