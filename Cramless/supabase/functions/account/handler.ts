// The `account` function: entitlements, Squad and deletion. Every route needs a Supabase session (anonymous
// users allowed) and answers in the contract's shapes and error envelope.
//   POST /account/entitlements     {signedTransactions} → EntitlementResponse (verify, save, then the plan)
//   GET  /account/entitlements     → EntitlementResponse (the plan as stored)
//   POST /account/squad/invite     → SquadInvite (only an active Squad purchaser; 4 seats)
//   POST /account/squad/redeem     {code} → SquadRedeemResponse
//   GET  /account/squad/members    → SquadMembers
//   POST /account/squad/remove     {memberId} → SquadMembers (the owner removes, or a member leaves)
//   POST /account/delete-ai-data   → {deleted: true}
//   POST /account/delete           → {deleted: true} (every row, the storage folder and the auth user)

import { unauthorized } from "../_shared/auth.ts";
import type {
  AccountDeleteResponse,
  EntitlementRequest,
  EntitlementResponse,
  SquadInvite,
  SquadMembers,
  SquadRedeemResponse,
} from "../_shared/contract.ts";
import type { Deps } from "../_shared/deps.ts";
import { verifyTransactions } from "../_shared/entitlements.ts";
import { ApiError, badRequest, errorResponse, toApiError } from "../_shared/errors.ts";
import { isoDate, json, methodNotAllowed, notFound, readJson, routeOf } from "../_shared/http.ts";
import { log } from "../_shared/log.ts";
import {
  enforcedLimit,
  METERS,
  periodStart,
  quotaError,
  quotaStatus,
  SHOWN_METERS,
  usageKeys,
} from "../_shared/plans.ts";
import { requireValid } from "../_shared/schemas.ts";
import { SQUAD_SEATS, type UserContext } from "../_shared/store.ts";
import type { Caller } from "../_shared/auth.ts";

const ROUTES: Record<string, "GET" | "POST"> = {
  "/entitlements": "POST",
  "/squad/invite": "POST",
  "/squad/redeem": "POST",
  "/squad/members": "GET",
  "/squad/remove": "POST",
  "/delete-ai-data": "POST",
  "/delete": "POST",
};

const INVITE_DAYS = 14;
const CODE_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";

interface Ctx {
  req: Request;
  deps: Deps;
  caller: Caller;
  user: UserContext;
  now: Date;
}

async function entitlementResponse(c: Ctx, user: UserContext): Promise<EntitlementResponse> {
  const usage = await c.deps.store.usage(c.caller.userId, usageKeys(SHOWN_METERS, c.now, user.timeZone));
  return { plan: user.plan, expiresAt: user.expiresAt, quota: quotaStatus(user.plan, usage) };
}

async function syncEntitlements(c: Ctx): Promise<Response> {
  const body = requireValid<EntitlementRequest>("EntitlementRequest", await readJson(c.req, 700 * 1024));
  const rows = await verifyTransactions(c.deps.verifiers, body.signedTransactions);
  await c.deps.store.saveEntitlements(c.caller.userId, rows, c.now);
  const user = await c.deps.store.context(c.caller.userId, c.now);
  return json(await entitlementResponse(c, user));
}

export function inviteCode(random: () => number): string {
  let code = "CAP-";
  for (let i = 0; i < 4; i++) code += CODE_ALPHABET[Math.floor(random() * CODE_ALPHABET.length)];
  return code;
}

async function invite(c: Ctx): Promise<Response> {
  await readJson(c.req, 4 * 1024, true);
  const expiresAt = new Date(c.now.getTime() + INVITE_DAYS * 86_400_000);
  for (let attempt = 0; attempt < 6; attempt++) {
    const code = inviteCode(c.deps.random);
    const r = await c.deps.store.squadInvite(c.caller.userId, code, expiresAt, c.now);
    if (r.ok) {
      return json(
        { code, url: `${c.deps.env.inviteBaseUrl}${code}`, expiresAt: isoDate(expiresAt)! } satisfies SquadInvite,
      );
    }
    if (r.reason === "not_owner") {
      throw new ApiError("entitlement_required", "Only the person who bought Squad can invite friends.");
    }
    if (r.reason === "full") throw badRequest(`Your Squad is full: ${SQUAD_SEATS} of ${SQUAD_SEATS} seats.`, 409);
  }
  throw new ApiError("upstream", "Couldn't make an invite code. Try again.", {}, 503);
}

const REDEEM_ERRORS: Record<string, ApiError> = {
  not_found: badRequest("That invite code doesn't exist. Check it with your friend.", 404),
  used: badRequest("That invite code was already used. Ask your friend for a new one.", 409),
  expired: badRequest("That invite code has expired. Ask your friend for a new one.", 410),
  own_squad: badRequest("That's your own Squad's code. Send it to a friend.", 409),
  other_squad: badRequest("You're already in a Squad. Leave it first to join this one.", 409),
  owner_lapsed: new ApiError("entitlement_required", "This Squad's subscription has ended."),
  full: badRequest("That Squad is full.", 409),
};

async function redeem(c: Ctx): Promise<Response> {
  const body = requireValid<{ code: string }>("SquadRedeemRequest", await readJson(c.req, 4 * 1024));
  // A few attempts a day per person, so codes can't be guessed.
  const period = periodStart(METERS.redeems.period, c.now, c.user.timeZone);
  const attempt = await c.deps.store.consume(c.caller.userId, "redeems", period, 1, enforcedLimit("redeems", "free"));
  if (!attempt.allowed) throw quotaError("redeems", c.user.plan, attempt.used, c.now, c.user.timeZone);
  const r = await c.deps.store.squadRedeem(c.caller.userId, body.code, c.now);
  if (!r.ok) throw REDEEM_ERRORS[r.reason] ?? REDEEM_ERRORS.not_found;
  return json({ plan: "squad", ownerName: r.ownerName } satisfies SquadRedeemResponse);
}

async function membersOf(c: Ctx): Promise<SquadMembers> {
  const r = await c.deps.store.squadMembers(c.caller.userId);
  if (!r.ok) throw badRequest("You're not in a Squad yet.", 404);
  return {
    seats: SQUAD_SEATS,
    members: r.members.map((m) => ({
      id: m.id,
      name: m.name.trim() || (m.isOwner ? "Squad owner" : "Squad member"),
      joinedAt: m.joinedAt,
      isOwner: m.isOwner,
    })),
  };
}

async function remove(c: Ctx): Promise<Response> {
  const body = requireValid<{ memberId: string }>("SquadRemoveRequest", await readJson(c.req, 4 * 1024));
  const r = await c.deps.store.squadRemove(c.caller.userId, body.memberId.toLowerCase());
  if (!r.ok) {
    throw r.reason === "not_allowed"
      ? badRequest("Only the Squad's owner can remove someone else.", 403)
      : badRequest("That person isn't in your Squad.", 404);
  }
  // A member who left has no Squad to list any more.
  if (body.memberId.toLowerCase() === c.caller.userId) {
    return json({ seats: SQUAD_SEATS, members: [] } satisfies SquadMembers);
  }
  return json(await membersOf(c));
}

async function handle(req: Request, deps: Deps, route: string): Promise<Response> {
  const method = route === "/entitlements" && req.method === "GET" ? "GET" : ROUTES[route];
  if (!method) throw notFound();
  if (req.method !== method) throw methodNotAllowed();
  const caller = await deps.authenticate(req);
  const now = deps.now();
  const user = await deps.store.context(caller.userId, now);
  // Deleting twice is fine: the second call finds nothing and says so the same way.
  if (!user.exists && route !== "/delete") throw unauthorized("This account was deleted.");
  const c: Ctx = { req, deps, caller, user, now };

  switch (route) {
    case "/entitlements":
      return req.method === "GET" ? json(await entitlementResponse(c, user)) : await syncEntitlements(c);
    case "/squad/invite":
      return await invite(c);
    case "/squad/redeem":
      return await redeem(c);
    case "/squad/members":
      return json(await membersOf(c));
    case "/squad/remove":
      return await remove(c);
    case "/delete-ai-data":
      await readJson(req, 4 * 1024, true);
      await deps.store.deleteAiData(caller.userId);
      return json({ deleted: true } satisfies AccountDeleteResponse);
    case "/delete":
      await readJson(req, 4 * 1024, true);
      await deps.store.deleteAccount(caller.userId);
      return json({ deleted: true } satisfies AccountDeleteResponse);
  }
  throw notFound();
}

/** The account function's request handler, with its dependencies built once per instance. */
export function accountHandler(deps: Deps): (req: Request) => Promise<Response> {
  return async (req) => {
    const startedAt = performance.now();
    const route = routeOf(req.url, "account");
    let status = 200;
    let code: string | null = null;
    try {
      const res = await handle(req, deps, route);
      status = res.status;
      return res;
    } catch (error) {
      const err = toApiError(error);
      status = err.status;
      code = err.code;
      return errorResponse(err);
    } finally {
      log({
        fn: "account",
        route: route in ROUTES ? route : "unknown",
        status,
        code,
        latency_ms: Math.round(performance.now() - startedAt),
      });
    }
  };
}
