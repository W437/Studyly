// Ported from Plainsum (the owner's production relay). App Store signed-data verification with the semantics
// of Apple's App Store Server Library `SignedDataVerifier`: a three-certificate x5c chain anchored in one of
// Apple's roots, Apple's marker extensions on the leaf and intermediate, validity dates with a
// one-minute skew, OCSP for both links when online checks are on, an ES256 signature from the
// leaf, and then the bundle ID, app Apple ID and environment checks for each payload type.
// Xcode-environment data isn't signed by the App Store and is only decoded, exactly as the
// library does; the relay enables that environment only with CRAMLESS_ALLOW_XCODE_JWS=1 on a local stack.
//
// Why not the library itself: on Deno (2.6 locally, the 2.1-based Supabase Edge Runtime),
// node:crypto's X509Certificate doesn't implement verify(), raw, toString() or infoAccess,
// which the library's chain check needs. This port uses WebCrypto instead.

import { APPLE_ROOTS } from "../generated.ts";
import { base64ToBytes, type Certificate, isIssuedBy, OID, parseCertificate } from "./x509.ts";
import { checkOcsp, MAX_SKEW_MS } from "./ocsp.ts";

export type Environment = "Production" | "Sandbox" | "Xcode" | "LocalTesting";

/** The library's VerificationStatus values. */
export enum VerificationStatus {
  OK = 0,
  VERIFICATION_FAILURE = 1,
  RETRYABLE_VERIFICATION_FAILURE = 2,
  INVALID_APP_IDENTIFIER = 3,
  INVALID_ENVIRONMENT = 4,
  INVALID_CHAIN_LENGTH = 5,
  INVALID_CERTIFICATE = 6,
  FAILURE = 7,
}

export type FailureReason =
  | "signature"
  | "chain"
  | "expired"
  | "revoked"
  | "bundle"
  | "app_apple_id"
  | "environment"
  | "payload"
  | "unavailable";

export class VerificationException extends Error {
  constructor(readonly status: VerificationStatus, readonly reason: FailureReason) {
    super(`App Store verification failed: ${VerificationStatus[status]} (${reason})`);
    this.name = "VerificationException";
  }
}

// deno-lint-ignore no-explicit-any
export type Payload = Record<string, any>;

export interface VerifierOptions {
  roots: Uint8Array[];
  onlineChecks: boolean;
  environment: Environment;
  bundleId: string;
  /** Required in Production. */
  appAppleId?: number;
  fetch?: typeof fetch;
  now?: () => Date;
}

function b64urlToBytes(text: string): Uint8Array {
  const b64 = text.replace(/-/g, "+").replace(/_/g, "/");
  return base64ToBytes(b64 + "=".repeat((4 - (b64.length % 4)) % 4));
}

/** Decodes a JWS payload without verifying it: only to choose the verifier by environment. */
export function decodePayloadUnverified(jws: string): Payload | null {
  try {
    const parts = jws.split(".");
    if (parts.length !== 3) return null;
    const payload = JSON.parse(new TextDecoder().decode(b64urlToBytes(parts[1])));
    return payload && typeof payload === "object" && !Array.isArray(payload) ? payload : null;
  } catch {
    return null;
  }
}

const STRING_FIELDS = [
  "originalTransactionId",
  "transactionId",
  "bundleId",
  "productId",
  "appAccountToken",
  "appTransactionId",
  "environment",
  "receiptType",
  "notificationType",
  "subtype",
  "notificationUUID",
  "type",
];
const NUMBER_FIELDS = [
  "purchaseDate",
  "originalPurchaseDate",
  "expiresDate",
  "revocationDate",
  "signedDate",
  "receiptCreationDate",
  "gracePeriodExpiresDate",
  "appAppleId",
  "quantity",
];

/** The library's payload validators: typed fields must have their types when present. */
function payloadValid(payload: Payload): boolean {
  for (const f of STRING_FIELDS) {
    if (f in payload && payload[f] !== undefined && typeof payload[f] !== "string") return false;
  }
  for (const f of NUMBER_FIELDS) {
    if (f in payload && payload[f] !== undefined && typeof payload[f] !== "number") return false;
  }
  return true;
}

interface CacheEntry {
  key: CryptoKey;
  expires: number;
}

const CACHE_TIME_MS = 15 * 60 * 1000;
const MAX_CACHE = 32;

export class SignedDataVerifier {
  readonly environment: Environment;
  readonly #roots: Certificate[];
  readonly #online: boolean;
  readonly #bundleId: string;
  readonly #appAppleId?: number;
  readonly #fetch: typeof fetch;
  readonly #now: () => Date;
  readonly #cache = new Map<string, CacheEntry>();

  constructor(options: VerifierOptions) {
    if (options.environment === "Production" && options.appAppleId === undefined) {
      throw new Error("appAppleId is required when the environment is Production");
    }
    this.environment = options.environment;
    this.#roots = options.roots.map((der) => parseCertificate(der));
    this.#online = options.onlineChecks;
    this.#bundleId = options.bundleId;
    this.#appAppleId = options.appAppleId;
    this.#fetch = options.fetch ?? fetch;
    this.#now = options.now ?? (() => new Date());
  }

  async verifyAndDecodeTransaction(jws: string): Promise<Payload> {
    const p = await this.#verifyJws(jws, (d) => d.signedDate);
    if (p.bundleId !== this.#bundleId) {
      throw new VerificationException(VerificationStatus.INVALID_APP_IDENTIFIER, "bundle");
    }
    if (p.environment !== this.environment) {
      throw new VerificationException(VerificationStatus.INVALID_ENVIRONMENT, "environment");
    }
    return p;
  }

  async verifyAndDecodeRenewalInfo(jws: string): Promise<Payload> {
    const p = await this.#verifyJws(jws, (d) => d.signedDate);
    if (p.environment !== this.environment) {
      throw new VerificationException(VerificationStatus.INVALID_ENVIRONMENT, "environment");
    }
    return p;
  }

  async verifyAndDecodeAppTransaction(jws: string): Promise<Payload> {
    const p = await this.#verifyJws(jws, (d) => d.receiptCreationDate);
    if (p.bundleId !== this.#bundleId) {
      throw new VerificationException(VerificationStatus.INVALID_APP_IDENTIFIER, "bundle");
    }
    if (this.environment === "Production" && p.appAppleId !== this.#appAppleId) {
      throw new VerificationException(VerificationStatus.INVALID_APP_IDENTIFIER, "app_apple_id");
    }
    if (p.receiptType !== this.environment) {
      throw new VerificationException(VerificationStatus.INVALID_ENVIRONMENT, "environment");
    }
    return p;
  }

  async verifyAndDecodeNotification(jws: string): Promise<Payload> {
    const p = await this.#verifyJws(jws, (d) => d.signedDate);
    const info = notificationTarget(p);
    if (info.bundleId !== this.#bundleId) {
      throw new VerificationException(VerificationStatus.INVALID_APP_IDENTIFIER, "bundle");
    }
    if (this.environment === "Production" && info.appAppleId !== this.#appAppleId) {
      throw new VerificationException(VerificationStatus.INVALID_APP_IDENTIFIER, "app_apple_id");
    }
    if (info.environment !== this.environment) {
      throw new VerificationException(VerificationStatus.INVALID_ENVIRONMENT, "environment");
    }
    return p;
  }

  async #verifyJws(jws: string, signedDate: (p: Payload) => number | undefined): Promise<Payload> {
    const parts = jws.split(".");
    if (parts.length !== 3) throw new VerificationException(VerificationStatus.VERIFICATION_FAILURE, "payload");
    const payload = decodePayloadUnverified(jws);
    if (!payload || !payloadValid(payload)) {
      throw new VerificationException(VerificationStatus.FAILURE, "payload");
    }
    if (this.environment === "Xcode" || this.environment === "LocalTesting") {
      // Not signed by the App Store; the environment is checked by the caller's method.
      return payload;
    }

    let header: Payload;
    let leaf: Certificate;
    let intermediate: Certificate;
    try {
      header = JSON.parse(new TextDecoder().decode(b64urlToBytes(parts[0])));
      const chain = Array.isArray(header?.x5c) ? header.x5c : [];
      if (chain.length !== 3) throw new VerificationException(VerificationStatus.INVALID_CHAIN_LENGTH, "chain");
      leaf = parseCertificate(base64ToBytes(String(chain[0])));
      intermediate = parseCertificate(base64ToBytes(String(chain[1])));
    } catch (error) {
      if (error instanceof VerificationException) throw error;
      throw new VerificationException(VerificationStatus.INVALID_CERTIFICATE, "chain");
    }
    if (header.alg !== "ES256") throw new VerificationException(VerificationStatus.VERIFICATION_FAILURE, "signature");

    const signed = signedDate(payload);
    const effective = this.#online ? this.#now() : new Date(typeof signed === "number" ? signed : Date.now());
    const key = await this.#verifyChain(leaf, intermediate, effective);

    const signature = b64urlToBytes(parts[2]);
    const ok = signature.length === 64 &&
      await crypto.subtle.verify(
        { name: "ECDSA", hash: "SHA-256" },
        key,
        signature as BufferSource,
        new TextEncoder().encode(`${parts[0]}.${parts[1]}`) as BufferSource,
      ).catch(() => false);
    if (!ok) throw new VerificationException(VerificationStatus.VERIFICATION_FAILURE, "signature");
    return payload;
  }

  async #verifyChain(leaf: Certificate, intermediate: Certificate, effective: Date): Promise<CryptoKey> {
    const cacheKey = this.#online ? cacheId(leaf, intermediate) : null;
    if (cacheKey) {
      const hit = this.#cache.get(cacheKey);
      if (hit && hit.expires > this.#now().getTime()) return hit.key;
    }

    let root: Certificate | null = null;
    for (const candidate of this.#roots) {
      if (await isIssuedBy(intermediate, candidate)) {
        root = candidate;
        break;
      }
    }
    let valid = root !== null && await isIssuedBy(leaf, intermediate);
    valid = valid && intermediate.isCA;
    valid = valid && leaf.extensions.has(OID.appleLeaf) && intermediate.extensions.has(OID.appleIntermediate);
    if (!valid || !root) throw new VerificationException(VerificationStatus.VERIFICATION_FAILURE, "signature");

    for (const cert of [leaf, intermediate, root]) {
      if (
        cert.notBefore.getTime() > effective.getTime() + MAX_SKEW_MS ||
        cert.notAfter.getTime() < effective.getTime() - MAX_SKEW_MS
      ) {
        throw new VerificationException(VerificationStatus.INVALID_CERTIFICATE, "expired");
      }
    }

    if (this.#online) {
      const now = this.#now();
      const outcomes = await Promise.all([
        checkOcsp(leaf, intermediate, now, this.#fetch),
        checkOcsp(intermediate, root, now, this.#fetch),
      ]);
      if (outcomes.includes("revoked")) throw new VerificationException(VerificationStatus.FAILURE, "revoked");
      if (outcomes.includes("unavailable")) {
        throw new VerificationException(VerificationStatus.RETRYABLE_VERIFICATION_FAILURE, "unavailable");
      }
      if (outcomes.some((o) => o !== "good")) throw new VerificationException(VerificationStatus.FAILURE, "signature");
    }

    if (leaf.keyAlgorithm !== OID.ecPublicKey || leaf.curve !== OID.p256) {
      throw new VerificationException(VerificationStatus.VERIFICATION_FAILURE, "signature");
    }
    const key = await crypto.subtle.importKey(
      "spki",
      leaf.spki as BufferSource,
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      [
        "verify",
      ],
    );
    if (cacheKey) {
      this.#cache.set(cacheKey, { key, expires: this.#now().getTime() + CACHE_TIME_MS });
      if (this.#cache.size > MAX_CACHE) {
        const now = this.#now().getTime();
        for (const [k, v] of this.#cache) if (v.expires <= now) this.#cache.delete(k);
        while (this.#cache.size > MAX_CACHE) this.#cache.delete(this.#cache.keys().next().value!);
      }
    }
    return key;
  }
}

function cacheId(leaf: Certificate, intermediate: Certificate): string {
  const hex = (b: Uint8Array) => Array.from(b.subarray(0, 4096), (x) => x.toString(16).padStart(2, "0")).join("");
  return hex(leaf.der) + ":" + hex(intermediate.der);
}

/** Where a notification's bundle, app and environment live (data, summary, token or appData). */
export function notificationTarget(p: Payload): { bundleId?: string; appAppleId?: number; environment?: string } {
  if (p.data) return { bundleId: p.data.bundleId, appAppleId: p.data.appAppleId, environment: p.data.environment };
  if (p.summary) {
    return { bundleId: p.summary.bundleId, appAppleId: p.summary.appAppleId, environment: p.summary.environment };
  }
  if (p.externalPurchaseToken) {
    const t = p.externalPurchaseToken;
    const environment = typeof t.externalPurchaseId === "string" && t.externalPurchaseId.startsWith("SANDBOX")
      ? "Sandbox"
      : "Production";
    return { bundleId: t.bundleId, appAppleId: t.appAppleId, environment };
  }
  if (p.appData) {
    return { bundleId: p.appData.bundleId, appAppleId: p.appData.appAppleId, environment: p.appData.environment };
  }
  return {};
}

/** The environment a JWS claims, before verification: it picks the verifier. */
export function claimedEnvironment(payload: Payload | null): string | null {
  if (!payload) return null;
  if (typeof payload.environment === "string") return payload.environment;
  if (typeof payload.receiptType === "string") return payload.receiptType;
  const target = notificationTarget(payload);
  return target.environment ?? null;
}

/** Apple's three public roots, committed in _shared/apple/ and bundled into _shared/generated.ts. */
export function appleRoots(): Uint8Array[] {
  return Object.values(APPLE_ROOTS).map(base64ToBytes);
}

export interface Verifiers {
  Production: SignedDataVerifier;
  Sandbox: SignedDataVerifier;
  /** Only when CRAMLESS_ALLOW_XCODE_JWS=1 on a local stack. */
  Xcode: SignedDataVerifier | null;
}

export function buildVerifiers(options: {
  roots: Uint8Array[];
  bundleId: string;
  appAppleId: number;
  allowXcode: boolean;
  onlineChecks?: boolean;
  fetch?: typeof fetch;
  now?: () => Date;
}): Verifiers {
  const common = {
    roots: options.roots,
    onlineChecks: options.onlineChecks ?? true,
    bundleId: options.bundleId,
    fetch: options.fetch,
    now: options.now,
  };
  return {
    Production: new SignedDataVerifier({ ...common, environment: "Production", appAppleId: options.appAppleId }),
    Sandbox: new SignedDataVerifier({ ...common, environment: "Sandbox" }),
    Xcode: options.allowXcode ? new SignedDataVerifier({ ...common, environment: "Xcode", onlineChecks: false }) : null,
  };
}

/** The verifier for a JWS's claimed environment, or null when that environment isn't enabled. */
export function verifierFor(verifiers: Verifiers, jws: string, allowXcode = true): SignedDataVerifier | null {
  const env = claimedEnvironment(decodePayloadUnverified(jws));
  if (env === "Production") return verifiers.Production;
  if (env === "Sandbox") return verifiers.Sandbox;
  if (env === "Xcode" && allowXcode) return verifiers.Xcode;
  return null;
}
