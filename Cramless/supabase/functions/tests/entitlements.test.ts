// Entitlement sync: StoreKit's signed transactions verified with the ported App Store verifier against a test
// certificate chain (and a local OCSP responder), then saved and turned into the plan and quota.

import { assert, assertEquals } from "@std/assert";
import { buildVerifiers, VerificationException } from "../_shared/appstore/verifier.ts";
import { rowFromTransaction } from "../_shared/entitlements.ts";
import { APP_APPLE_ID, BUNDLE_ID, errorOf, fixtureJson, NOW, rig } from "./_harness.ts";
import { type Chain, makeChain, signJws, signXcodeJws, startOcspResponder } from "./_pki.ts";

const now = new Date(NOW);
const DAY = 86_400_000;

function transaction(o: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    transactionId: "2000000111",
    originalTransactionId: "2000000100",
    bundleId: BUNDLE_ID,
    productId: "com.loopware.Capling.pro.yearly",
    purchaseDate: Date.parse("2026-10-29T00:00:00Z") - 365 * DAY,
    originalPurchaseDate: Date.parse("2026-10-01T00:00:00Z"),
    expiresDate: Date.parse("2027-10-29T00:00:00Z"),
    quantity: 1,
    type: "Auto-Renewable Subscription",
    inAppOwnershipType: "PURCHASED",
    signedDate: now.getTime() - 60_000,
    environment: "Sandbox",
    transactionReason: "PURCHASE",
    storefront: "USA",
    ...o,
  };
}

async function setup(o: { allowXcode?: boolean; online?: boolean } = {}) {
  const ocsp = startOcspResponder(() => now);
  const chain = await makeChain({ now, ocspUrl: ocsp.url });
  ocsp.register("root", chain.root);
  ocsp.register("intermediate", chain.intermediate);
  const verifiers = buildVerifiers({
    roots: [chain.root.der],
    bundleId: BUNDLE_ID,
    appAppleId: APP_APPLE_ID,
    allowXcode: o.allowXcode ?? false,
    onlineChecks: o.online ?? true,
    now: () => now,
  });
  const r = rig({ verifiers });
  r.store.addUser("user-1", "Maya");
  return { r, chain, ocsp, verifiers };
}

async function sync(r: ReturnType<typeof rig>, signedTransactions: string[], user = "user-1") {
  return await r.account("entitlements", { user, body: { signedTransactions } });
}

Deno.test("a verified Pro subscription makes the plan Pro, with its expiry and quota", async () => {
  const { r, chain, ocsp } = await setup();
  try {
    const res = await sync(r, [await signJws(chain, transaction({ environment: "Production" }))]);
    assertEquals(res.status, 200);
    assertEquals(await res.json(), fixtureJson("entitlement"));
    assertEquals(r.store.entitlements.length, 1);
    assertEquals(r.store.entitlements[0].originalTransactionId, "2000000100");
    assert(ocsp.requests >= 2, "both links of the chain were checked online");
    // GET returns the stored plan without a sync.
    assertEquals(await (await r.account("entitlements")).json(), fixtureJson("entitlement"));
  } finally {
    await ocsp.close();
  }
});

Deno.test("the Exam Pass lasts 30 days from purchase; Squad is its own plan", async () => {
  const { r, chain, ocsp } = await setup();
  try {
    const bought = now.getTime() - 3 * DAY;
    const pass = await signJws(
      chain,
      transaction({
        productId: "com.loopware.Capling.exampass",
        originalTransactionId: "pass-1",
        transactionId: "pass-1",
        type: "Non-Renewing Subscription",
        purchaseDate: bought,
        expiresDate: undefined,
      }),
    );
    const body = await (await sync(r, [pass])).json();
    assertEquals(body.plan, "pass");
    assertEquals(body.expiresAt, new Date(bought + 30 * DAY).toISOString().replace(".000Z", "Z"));

    const squad = await signJws(
      chain,
      transaction({ productId: "com.loopware.Capling.squad.yearly", originalTransactionId: "sq-1" }),
    );
    assertEquals((await (await sync(r, [squad, pass])).json()).plan, "squad", "the best active plan wins");
  } finally {
    await ocsp.close();
  }
});

Deno.test("expired, revoked, unknown-product and other-app transactions don't grant anything", async () => {
  const { r, chain, ocsp } = await setup();
  try {
    const expired = await signJws(
      chain,
      transaction({ originalTransactionId: "old", expiresDate: now.getTime() - DAY }),
    );
    const refunded = await signJws(
      chain,
      transaction({ originalTransactionId: "refunded", revocationDate: now.getTime() - DAY }),
    );
    const tip = await signJws(
      chain,
      transaction({ originalTransactionId: "tip", productId: "com.loopware.Capling.tip" }),
    );
    const other = await signJws(chain, transaction({ originalTransactionId: "other", bundleId: "com.example.other" }));
    const body = await (await sync(r, [expired, refunded, tip, other])).json();
    assertEquals(body.plan, "free");
    assertEquals(body.expiresAt, null);
    assertEquals(r.store.entitlements.map((e) => e.originalTransactionId).sort(), ["old", "refunded"]);
  } finally {
    await ocsp.close();
  }
});

Deno.test("a forged or broken signature rejects the whole sync", async () => {
  const { r, chain, ocsp } = await setup();
  try {
    const good = await signJws(chain, transaction());
    const [h, p] = good.split(".");
    const forgedPayload = btoa(JSON.stringify(transaction({ productId: "com.loopware.Capling.squad.yearly" })))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    const forged = `${h}.${forgedPayload}.${good.split(".")[2]}`;
    const res = await sync(r, [good, forged]);
    assertEquals(res.status, 422);
    assertEquals((await errorOf(res)).code, "bad_request");
    assertEquals(r.store.entitlements.length, 0, "nothing saved");
    assertEquals((await sync(r, ["not.a.jws-but-long-enough"])).status, 422);
    assertEquals(p.length > 0, true);
  } finally {
    await ocsp.close();
  }
});

Deno.test("a chain from another root, or a revoked certificate, fails; Apple's responder being down is retryable", async () => {
  const { r, ocsp, chain } = await setup();
  try {
    const stranger: Chain = await makeChain({ now, ocspUrl: ocsp.url });
    assertEquals((await sync(r, [await signJws(stranger, transaction())])).status, 422);

    ocsp.down = true;
    const down = await sync(r, [await signJws(chain, transaction())]);
    assertEquals(down.status, 503);
    assertEquals((await errorOf(down)).code, "upstream");
    ocsp.down = false;

    ocsp.revoked.add(Array.from(chain.leaf.serial, (b) => b.toString(16).padStart(2, "0")).join(""));
    assertEquals((await sync(r, [await signJws(chain, transaction())])).status, 422);
  } finally {
    await ocsp.close();
  }
});

Deno.test("Xcode StoreKit testing transactions count only when the local switch allows them", async () => {
  const xcode = await signXcodeJws(transaction({ environment: "Xcode", originalTransactionId: "xc-1" }));
  const off = await setup();
  try {
    const body = await (await sync(off.r, [xcode])).json();
    assertEquals(body.plan, "free", "skipped: this server doesn't accept Xcode transactions");
  } finally {
    await off.ocsp.close();
  }
  const on = await setup({ allowXcode: true });
  try {
    assertEquals((await (await sync(on.r, [xcode])).json()).plan, "pro");
  } finally {
    await on.ocsp.close();
  }
});

Deno.test("the switch is honoured only on a local stack", async () => {
  const { testEnv } = await import("./_harness.ts");
  assertEquals(testEnv({ CRAMLESS_ALLOW_XCODE_JWS: "1" }).allowXcodeJws, true);
  const hosted = testEnv({
    CRAMLESS_ALLOW_XCODE_JWS: "1",
    SUPABASE_URL: "https://abcd.supabase.co",
    APPLE_APP_ID: "123",
  });
  assertEquals(hosted.allowXcodeJws, false);
  assert(hosted.faults.includes("xcode_jws_ignored"));
});

Deno.test("a purchase synced from a new install moves to that account", async () => {
  const { r, chain, ocsp } = await setup();
  try {
    r.store.addUser("user-2");
    const jws = await signJws(chain, transaction());
    assertEquals((await (await sync(r, [jws])).json()).plan, "pro");
    assertEquals((await (await sync(r, [jws], "user-2")).json()).plan, "pro");
    assertEquals((await (await r.account("entitlements")).json()).plan, "free", "the first account lost it");
    // An older transaction of the same purchase doesn't roll the row back.
    const older = await signJws(
      chain,
      transaction({
        transactionId: "1999",
        purchaseDate: Date.parse("2025-01-01T00:00:00Z"),
        expiresDate: Date.parse("2026-01-01T00:00:00Z"),
      }),
    );
    await sync(r, [older], "user-2");
    assertEquals(
      (await (await r.account("entitlements", { user: "user-2" })).json()).expiresAt,
      "2027-10-29T00:00:00Z",
    );
  } finally {
    await ocsp.close();
  }
});

Deno.test("transaction payloads map to rows; malformed ones don't", () => {
  assertEquals(rowFromTransaction(transaction())?.plan, "pro");
  assertEquals(rowFromTransaction(transaction({ productId: "com.loopware.Capling.pro.monthly" }))?.plan, "pro");
  assertEquals(rowFromTransaction(transaction({ expiresDate: undefined })), null, "a subscription needs an expiry");
  assertEquals(rowFromTransaction(transaction({ environment: "Staging" })), null);
  assertEquals(rowFromTransaction(transaction({ purchaseDate: "yesterday" })), null);
});

Deno.test("the verifier itself refuses the wrong bundle and the wrong environment", async () => {
  const { chain, verifiers, ocsp } = await setup();
  try {
    const wrongBundle = await signJws(chain, transaction({ bundleId: "com.example.other" }));
    const e1 = await verifiers.Sandbox.verifyAndDecodeTransaction(wrongBundle).catch((e) => e);
    assert(e1 instanceof VerificationException && e1.reason === "bundle");
    const production = await signJws(chain, transaction({ environment: "Production" }));
    const e2 = await verifiers.Sandbox.verifyAndDecodeTransaction(production).catch((e) => e);
    assert(e2 instanceof VerificationException && e2.reason === "environment");
  } finally {
    await ocsp.close();
  }
});
