// Who is calling: a Supabase session token (anonymous users included), checked with Supabase Auth itself
// (`auth.getUser(jwt)`), which works with every JWT signing scheme and refuses deleted users. Answers are
// cached for a minute per token, so a tutor conversation doesn't ask Auth on every turn.

import { ApiError } from "./errors.ts";
import { bearer } from "./http.ts";
import type { Admin } from "./store_postgres.ts";

export interface Caller {
  userId: string;
  isAnonymous: boolean;
  email: string | null;
}

export type Authenticate = (req: Request) => Promise<Caller>;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const CACHE_MS = 60_000;
const CACHE_MAX = 500;

export function unauthorized(message = "Sign in again to use this."): ApiError {
  return new ApiError("unauthorized", message);
}

async function tokenKey(token: string): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token)));
  return Array.from(digest.subarray(0, 16), (b) => b.toString(16).padStart(2, "0")).join("");
}

/** The production authenticator. `now` is injectable for the cache's sake. */
export function goTrueAuthenticator(admin: Admin, now: () => number = Date.now): Authenticate {
  const cache = new Map<string, { caller: Caller; until: number }>();
  return async (req) => {
    const token = bearer(req);
    if (!token) throw unauthorized("This needs a session token.");
    const key = await tokenKey(token);
    const hit = cache.get(key);
    if (hit && hit.until > now()) return hit.caller;

    const { data, error } = await admin.auth.getUser(token);
    const user = data?.user;
    if (error || !user || !UUID.test(user.id)) throw unauthorized();
    const caller: Caller = {
      userId: user.id.toLowerCase(),
      isAnonymous: user.is_anonymous === true,
      email: user.email ?? null,
    };
    if (cache.size >= CACHE_MAX) {
      for (const [k, v] of cache) if (v.until <= now()) cache.delete(k);
      while (cache.size >= CACHE_MAX) cache.delete(cache.keys().next().value!);
    }
    cache.set(key, { caller, until: now() + CACHE_MS });
    return caller;
  };
}
