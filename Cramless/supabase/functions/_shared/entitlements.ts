// StoreKit transactions as entitlements. The products are Cramless.storekit's: Pro yearly and monthly, Squad
// yearly (the purchaser owns a Squad of four), and the Exam Pass (a non-renewing 30 days, whose end the server
// computes because non-renewing transactions carry no expiry).

import { ApiError, badRequest } from "./errors.ts";
import { isoDate } from "./http.ts";
import type { EntitlementRow, Environment } from "./store.ts";
import {
  decodePayloadUnverified,
  type Payload,
  VerificationException,
  VerificationStatus,
  verifierFor,
  type Verifiers,
} from "./appstore/verifier.ts";

export const PRODUCTS: Record<string, { plan: EntitlementRow["plan"]; passDays?: number }> = {
  "com.loopware.Capling.pro.yearly": { plan: "pro" },
  "com.loopware.Capling.pro.monthly": { plan: "pro" },
  "com.loopware.Capling.squad.yearly": { plan: "squad" },
  "com.loopware.Capling.exampass": { plan: "pass", passDays: 30 },
};

const DAY_MS = 86_400_000;

function environmentOf(value: unknown): Environment | null {
  return value === "Production" || value === "Sandbox" || value === "Xcode" ? value : null;
}

/** A verified transaction payload as a row, or null for a product Capling doesn't sell or a malformed one. */
export function rowFromTransaction(t: Payload): EntitlementRow | null {
  const product = PRODUCTS[String(t.productId ?? "")];
  const environment = environmentOf(t.environment);
  if (!product || !environment) return null;
  if (typeof t.originalTransactionId !== "string" || typeof t.transactionId !== "string") return null;
  if (typeof t.purchaseDate !== "number") return null;
  let expires: number | null;
  if (product.passDays !== undefined) {
    expires = t.purchaseDate + product.passDays * DAY_MS;
  } else {
    if (typeof t.expiresDate !== "number") return null;
    expires = t.expiresDate;
  }
  return {
    plan: product.plan,
    productId: String(t.productId),
    originalTransactionId: t.originalTransactionId,
    transactionId: t.transactionId,
    purchaseDate: isoDate(t.purchaseDate)!,
    expiresAt: isoDate(expires),
    revokedAt: typeof t.revocationDate === "number" ? isoDate(t.revocationDate) : null,
    environment,
  };
}

/** Verifies each signed transaction with the verifier its payload names. A transaction for another app, or for an
 * environment this server doesn't accept (Xcode on a hosted project), is skipped; any other failure rejects the
 * whole request, so the app never half-syncs. */
export async function verifyTransactions(verifiers: Verifiers, signed: string[]): Promise<EntitlementRow[]> {
  const rows: EntitlementRow[] = [];
  for (const jws of signed) {
    if (!decodePayloadUnverified(jws)) throw badRequest("A purchase didn't pass verification.", 422);
    const verifier = verifierFor(verifiers, jws);
    if (!verifier) continue;
    let payload: Payload;
    try {
      payload = await verifier.verifyAndDecodeTransaction(jws);
    } catch (error) {
      if (error instanceof VerificationException) {
        if (error.reason === "bundle") continue;
        if (error.status === VerificationStatus.RETRYABLE_VERIFICATION_FAILURE) {
          throw new ApiError("upstream", "Apple's certificate service couldn't be reached. Try again soon.", {
            retryAfter: 60,
          }, 503);
        }
      }
      throw badRequest("A purchase didn't pass verification.", 422);
    }
    const row = rowFromTransaction(payload);
    if (row) rows.push(row);
  }
  return rows;
}
