// Small HTTP helpers shared by the functions.

import { ApiError, badRequest } from "./errors.ts";

/** JSON with the contract's dates: ISO 8601 in UTC without fractions ("2026-11-05T00:00:00Z"), which the app's
 * JSONDecoder (`.iso8601`) reads. */
export function json(body: unknown, status = 200, headers: HeadersInit = {}): Response {
  const h = new Headers(headers);
  if (!h.has("Content-Type")) h.set("Content-Type", "application/json; charset=utf-8");
  if (!h.has("Cache-Control")) h.set("Cache-Control", "no-store");
  return new Response(JSON.stringify(body), { status, headers: h });
}

/** The raw bytes of a fixture or another pre-serialized body, unchanged. */
export function rawJson(text: string, status = 200): Response {
  return new Response(text, {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

/** A date as the contract writes it: "2026-11-05T00:00:00Z". */
export function isoDate(value: Date | string | number | null | undefined): string | null {
  if (value === null || value === undefined) return null;
  const ms = value instanceof Date ? value.getTime() : typeof value === "number" ? value : Date.parse(value);
  if (!Number.isFinite(ms)) return null;
  return new Date(ms).toISOString().replace(/\.\d{3}Z$/, "Z");
}

/**
 * The route inside a function: the path after the function's name, so `/functions/v1/ai/generate` and
 * `/ai/generate` both give `/generate`. `/` for the function root.
 */
export function routeOf(url: string, functionName: string): string {
  const parts = new URL(url).pathname.split("/").filter((p) => p.length > 0);
  const index = parts.indexOf(functionName);
  const rest = index >= 0 ? parts.slice(index + 1) : parts;
  return "/" + rest.join("/");
}

/** Reads the body with a hard size cap, without trusting Content-Length. */
export async function readBytes(req: Request, maxBytes: number): Promise<Uint8Array> {
  const declared = Number(req.headers.get("content-length") ?? "NaN");
  if (Number.isFinite(declared) && declared > maxBytes) throw badRequest("The request is too large.", 413);
  if (!req.body) return new Uint8Array(0);
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxBytes) {
      await reader.cancel().catch(() => {});
      throw badRequest("The request is too large.", 413);
    }
    chunks.push(value);
  }
  const out = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return out;
}

/** Reads a JSON body; a missing body is `{}` when `allowEmpty`. */
export async function readJson(req: Request, maxBytes: number, allowEmpty = false): Promise<unknown> {
  const bytes = await readBytes(req, maxBytes);
  if (bytes.byteLength === 0) {
    if (allowEmpty) return {};
    throw badRequest("The request needs a JSON body.");
  }
  try {
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    throw badRequest("The body isn't valid JSON.");
  }
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** The bearer token of a request, or null. */
export function bearer(req: Request): string | null {
  const header = req.headers.get("authorization") ?? "";
  const m = /^Bearer\s+(\S+)$/i.exec(header.trim());
  return m ? m[1] : null;
}

export function methodNotAllowed(): ApiError {
  return badRequest("That method isn't supported here.", 405);
}

export function notFound(): ApiError {
  return badRequest("There's no such endpoint.", 404);
}
