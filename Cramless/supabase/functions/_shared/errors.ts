// The contract's error envelope: {"error": {"code", "message", "retryAfter"?, "quota"?}} with an HTTP status.
// Five codes only (the app maps them in RelayError.from); the status says more where it helps (404, 405, 413,
// 500, 504). Messages are short, safe to show and never carry the person's content.

import type { QuotaStatus } from "./contract.ts";
import type { Usage } from "./cost.ts";

export type ErrorCode = "unauthorized" | "quota_exceeded" | "entitlement_required" | "bad_request" | "upstream";

const DEFAULT_STATUS: Record<ErrorCode, number> = {
  unauthorized: 401,
  quota_exceeded: 429,
  entitlement_required: 403,
  bad_request: 400,
  upstream: 502,
};

export interface ErrorExtra {
  /** Seconds until a retry can work (fair-use limits, a busy model). */
  retryAfter?: number;
  /** The plan and the meter that ran out (quota_exceeded). */
  quota?: QuotaStatus;
}

export class ApiError extends Error {
  readonly code: ErrorCode;
  readonly status: number;
  readonly extra: ErrorExtra;
  /** Tokens a call was billed for even though it failed (a reply that could not be read), so the cost is still recorded. */
  usage?: Usage;

  constructor(code: ErrorCode, message: string, extra: ErrorExtra = {}, status?: number) {
    super(message);
    this.name = "ApiError";
    this.code = code;
    this.extra = extra;
    this.status = status ?? DEFAULT_STATUS[code];
  }

  /** The `error` object: the body of an error response and the data of an SSE `error` event. */
  toObject(): Record<string, unknown> {
    const out: Record<string, unknown> = { code: this.code, message: this.message };
    if (this.extra.retryAfter !== undefined) out.retryAfter = this.extra.retryAfter;
    if (this.extra.quota !== undefined) out.quota = this.extra.quota;
    return out;
  }
}

export function errorResponse(error: ApiError): Response {
  const headers = new Headers({ "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" });
  if (error.extra.retryAfter !== undefined) {
    headers.set("Retry-After", String(Math.max(1, Math.ceil(error.extra.retryAfter))));
  }
  return new Response(JSON.stringify({ error: error.toObject() }), { status: error.status, headers });
}

/** Anything thrown, as an ApiError: unknown errors are a bare 500 that says nothing about the cause. */
export function toApiError(error: unknown): ApiError {
  if (error instanceof ApiError) return error;
  return new ApiError("upstream", "Something went wrong on our side. Try again in a moment.", {}, 500);
}

export const badRequest = (message: string, status = 400) => new ApiError("bad_request", message, {}, status);
