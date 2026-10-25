// POST /appstore-notify: App Store Server Notifications V2 (Production and Sandbox; never Xcode). Apple's signed
// payload is the authentication. A renewal, expiry, refund or revocation updates the entitlement row of its
// original transaction when we know it; a transaction we've never seen is ignored (the app syncs it when it next
// runs). Anything that verifies answers 200, so Apple doesn't retry it; an unverifiable payload answers 400.

import type { Deps } from "../_shared/deps.ts";
import { rowFromTransaction } from "../_shared/entitlements.ts";
import { badRequest, errorResponse, toApiError } from "../_shared/errors.ts";
import { isRecord, json, readJson } from "../_shared/http.ts";
import { log } from "../_shared/log.ts";
import type { NotificationUpdate } from "../_shared/store.ts";
import { type Payload, verifierFor } from "../_shared/appstore/verifier.ts";

async function notify(req: Request, deps: Deps): Promise<Response> {
  if (req.method !== "POST") throw badRequest("POST only.", 405);
  const body = await readJson(req, 64 * 1024);
  if (!isRecord(body) || typeof body.signedPayload !== "string" || body.signedPayload.length > 60_000) {
    throw badRequest('Expected {"signedPayload": …}.');
  }
  const verifier = verifierFor(deps.verifiers, body.signedPayload, false);
  if (!verifier) throw badRequest("The notification names an environment this server doesn't accept.");

  let payload: Payload;
  try {
    payload = await verifier.verifyAndDecodeNotification(body.signedPayload);
  } catch {
    throw badRequest("The notification's signature didn't verify.");
  }

  const data = isRecord(payload.data) ? payload.data : {};
  if (typeof data.signedTransactionInfo !== "string") {
    return json({ ok: true, outcome: "ignored", type: String(payload.notificationType ?? "") });
  }
  let row;
  try {
    row = rowFromTransaction(await verifier.verifyAndDecodeTransaction(data.signedTransactionInfo));
  } catch {
    return json({ ok: true, outcome: "ignored", type: String(payload.notificationType ?? "") });
  }
  if (!row) return json({ ok: true, outcome: "ignored", type: String(payload.notificationType ?? "") });

  const update: NotificationUpdate = {
    environment: row.environment,
    originalTransactionId: row.originalTransactionId,
    transactionId: row.transactionId,
    productId: row.productId,
    plan: row.plan,
    purchaseDate: row.purchaseDate,
    expiresAt: row.expiresAt,
    revokedAt: row.revokedAt,
  };
  const outcome = await deps.store.applyNotification(update, deps.now());
  return json({ ok: true, outcome, type: String(payload.notificationType ?? "") });
}

export function appstoreNotifyHandler(deps: Deps): (req: Request) => Promise<Response> {
  return async (req) => {
    const startedAt = performance.now();
    let status = 200;
    let code: string | null = null;
    try {
      const res = await notify(req, deps);
      status = res.status;
      return res;
    } catch (error) {
      const err = toApiError(error);
      status = err.status;
      code = err.code;
      return errorResponse(err);
    } finally {
      log({ fn: "appstore-notify", route: "/", status, code, latency_ms: Math.round(performance.now() - startedAt) });
    }
  };
}
