// The contract's schemas, ready to use: one self-contained schema per type (the type's definition inlined at the
// root, with only the $defs it reaches), the request schemas, and the structured-output schemas sent to the
// model, derived from the contract types by leaving out what the relay fills in itself (`model`).

import { CONTRACT_SCHEMA, REQUEST_SCHEMA } from "./generated.ts";
import { describeIssues, type Schema, validate } from "./schema.ts";
import { badRequest } from "./errors.ts";

function refsOf(node: unknown, out: Set<string>): void {
  if (Array.isArray(node)) {
    for (const child of node) refsOf(child, out);
  } else if (node && typeof node === "object") {
    for (const [key, value] of Object.entries(node)) {
      if (key === "$ref" && typeof value === "string") out.add(value.replace("#/$defs/", ""));
      else refsOf(value, out);
    }
  }
}

/** A definition with every definition it reaches, as one schema (root inlined). */
function selfContained(defs: Record<string, Schema>, name: string, root?: Schema): Schema {
  const start = root ?? defs[name];
  if (!start) throw new Error(`No schema named ${name}`);
  const reached = new Set<string>();
  const queue: string[] = [];
  const seed = new Set<string>();
  refsOf(start, seed);
  queue.push(...seed);
  while (queue.length > 0) {
    const next = queue.shift()!;
    if (reached.has(next)) continue;
    if (!defs[next]) throw new Error(`Unresolved $ref ${next} in ${name}`);
    reached.add(next);
    const inner = new Set<string>();
    refsOf(defs[next], inner);
    for (const r of inner) if (!reached.has(r)) queue.push(r);
  }
  const out: Schema = structuredClone(start);
  if (reached.size > 0) {
    out.$defs = Object.fromEntries([...reached].sort().map((r) => [r, structuredClone(defs[r])]));
  }
  return out;
}

const contractCache = new Map<string, Schema>();
const requestCache = new Map<string, Schema>();
const providerCache = new Map<string, Schema>();

/** The contract schema of a reply type ("GenerateResponse", "QuotaStatus", …). */
export function contractSchema(name: string): Schema {
  let schema = contractCache.get(name);
  if (!schema) {
    schema = selfContained(CONTRACT_SCHEMA.$defs, name);
    contractCache.set(name, schema);
  }
  return schema;
}

/** The request schema of an endpoint's body ("GenerateRequest", …). */
export function requestSchema(name: string): Schema {
  let schema = requestCache.get(name);
  if (!schema) {
    schema = selfContained(REQUEST_SCHEMA.$defs, name);
    requestCache.set(name, schema);
  }
  return schema;
}

/** The structured-output schema the model fills for a reply type: the contract type without `model`, which the
 * relay sets from the provider's answer. */
export function providerSchema(name: string): Schema {
  let schema = providerCache.get(name);
  if (!schema) {
    const root: Schema = structuredClone(CONTRACT_SCHEMA.$defs[name]);
    if (root.properties?.model) {
      delete root.properties.model;
      root.required = (root.required as string[]).filter((r) => r !== "model");
    }
    schema = selfContained(CONTRACT_SCHEMA.$defs, name, root);
    providerCache.set(name, schema);
  }
  return schema;
}

/** The most text the passages of one tutor or assistant request may hold in all, in characters. The schema limits each passage
 * (20,000) and their number (100) but not the sum, so under the body limit one hand-built request could carry a million
 * characters and cost 26 cents on the tutor (52 on the assistant, whose body may be twice as big). The app sends about 40,000 at
 * most (6,000 words). */
export const MAX_SOURCE_CHARS = 200_000;

/** The passages hold no more than MAX_SOURCE_CHARS in all, or a plain `bad_request` (413). Checked before anything is metered
 * or the model is asked, so a refused request costs nothing. */
export function requireSourceBudget(sources: readonly { text: string }[]): void {
  let total = 0;
  for (const source of sources) total += source.text.length;
  if (total > MAX_SOURCE_CHARS) {
    throw badRequest(
      "That's more of your notes than Cap can read in one question. Try asking about one part of them.",
      413,
    );
  }
}

/** Validates a request body against its schema; a 400 naming the first problem otherwise. */
export function requireValid<T>(name: string, value: unknown): T {
  const issues = validate(requestSchema(name), value);
  if (issues.length > 0) throw badRequest(`The request isn't valid: ${describeIssues(issues)}.`);
  return value as T;
}
