// Ported from Plainsum. A test certificate authority shaped like the App Store's: a self-signed root, an
// intermediate carrying Apple's WWDR marker, and a leaf carrying the receipt-signing marker, each pointing at a
// local OCSP responder. Tests inject the root into the verifiers and sign StoreKit-shaped JWS with the leaf.

import {
  bitString,
  boolean,
  children,
  concat,
  content,
  ctx,
  expect,
  explicit,
  generalizedTime,
  ia5String,
  integer,
  nullValue,
  octets,
  oid,
  parseRoot,
  seq,
  set,
  TAG,
  tlv,
  utcTime,
  utf8String,
} from "../_shared/appstore/asn1.ts";
import { OID, parseCertificate, sha1, sha256 } from "../_shared/appstore/x509.ts";

const EC = { name: "ECDSA", namedCurve: "P-256" } as const;
const SIGN = { name: "ECDSA", hash: "SHA-256" } as const;

export interface Issued {
  der: Uint8Array;
  keys: CryptoKeyPair;
  serial: Uint8Array;
  subjectName: Uint8Array;
}

function name(cn: string): Uint8Array {
  return seq(set(seq(oid("2.5.4.3"), utf8String(cn))));
}

/** WebCrypto's r‖s signature as the DER ECDSA-Sig-Value certificates and OCSP carry. */
export function rawToDer(raw: Uint8Array): Uint8Array {
  return seq(integer(raw.subarray(0, 32)), integer(raw.subarray(32, 64)));
}

async function signDer(key: CryptoKey, data: Uint8Array): Promise<Uint8Array> {
  const raw = new Uint8Array(await crypto.subtle.sign(SIGN, key, data as BufferSource));
  return rawToDer(raw);
}

function extension(id: string, critical: boolean, value: Uint8Array): Uint8Array {
  return critical ? seq(oid(id), boolean(true), octets(value)) : seq(oid(id), octets(value));
}

function aia(ocspUrl: string): Uint8Array {
  // AccessDescription with a uniformResourceIdentifier [6] IMPLICIT IA5String.
  const uri = ia5String(ocspUrl);
  const implicitUri = concat(new Uint8Array([ctx(6, false)]), uri.subarray(1));
  return seq(seq(oid(OID.ocspAccess), implicitUri));
}

let serialCounter = 1000;

export interface CertOptions {
  cn: string;
  issuer?: Issued;
  ca: boolean;
  notBefore: Date;
  notAfter: Date;
  markers?: string[];
  ocspUrl?: string;
  ocspSigning?: boolean;
  keys?: CryptoKeyPair;
}

export async function issue(o: CertOptions): Promise<Issued> {
  const keys = o.keys ?? (await crypto.subtle.generateKey(EC, true, ["sign", "verify"]) as CryptoKeyPair);
  const spki = new Uint8Array(await crypto.subtle.exportKey("spki", keys.publicKey));
  const serial = new Uint8Array([0x01, (serialCounter >> 8) & 0xff, serialCounter & 0xff]);
  serialCounter++;
  const subjectName = name(o.cn);
  const issuerName = o.issuer ? o.issuer.subjectName : subjectName;
  const exts: Uint8Array[] = [
    extension(OID.basicConstraints, true, o.ca ? seq(boolean(true)) : seq()),
  ];
  for (const marker of o.markers ?? []) exts.push(extension(marker, false, nullValue()));
  if (o.ocspUrl) exts.push(extension(OID.authorityInfoAccess, false, aia(o.ocspUrl)));
  if (o.ocspSigning) exts.push(extension(OID.extKeyUsage, false, seq(oid(OID.ocspSigning))));
  const tbs = seq(
    explicit(0, integer(2)),
    integer(serial),
    seq(oid(OID.ecdsaSha256)),
    issuerName,
    seq(utcTime(o.notBefore), utcTime(o.notAfter)),
    subjectName,
    spki,
    explicit(3, seq(...exts)),
  );
  const signer = o.issuer ? o.issuer.keys.privateKey : keys.privateKey;
  const signature = await signDer(signer, tbs);
  const der = seq(tbs, seq(oid(OID.ecdsaSha256)), bitString(signature));
  parseCertificate(der); // fail fast if the encoding is off
  return { der, keys, serial, subjectName };
}

export function b64(bytes: Uint8Array): string {
  let s = "";
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(s);
}

export function b64url(bytes: Uint8Array | string): string {
  const data = typeof bytes === "string" ? new TextEncoder().encode(bytes) : bytes;
  return b64(data).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export interface Chain {
  root: Issued;
  intermediate: Issued;
  leaf: Issued;
}

const DAY = 86_400_000;

export interface ChainOptions {
  now?: Date;
  ocspUrl?: string;
  leafValidity?: { notBefore: Date; notAfter: Date };
  leafMarker?: boolean;
  intermediateMarker?: boolean;
  root?: Issued;
}

/** A root → intermediate → leaf chain with Apple's markers, valid around `now`. */
export async function makeChain(o: ChainOptions = {}): Promise<Chain> {
  const now = o.now ?? new Date();
  const root = o.root ?? await issue({
    cn: "Capling Test Root CA",
    ca: true,
    notBefore: new Date(now.getTime() - 3650 * DAY),
    notAfter: new Date(now.getTime() + 3650 * DAY),
  });
  const intermediate = await issue({
    cn: "Capling Test WWDR Intermediate",
    issuer: root,
    ca: true,
    notBefore: new Date(now.getTime() - 365 * DAY),
    notAfter: new Date(now.getTime() + 365 * DAY),
    markers: o.intermediateMarker === false ? [] : [OID.appleIntermediate],
    ocspUrl: o.ocspUrl ? `${o.ocspUrl}/root` : undefined,
  });
  const leaf = await issue({
    cn: "Capling Test App Store Signing",
    issuer: intermediate,
    ca: false,
    notBefore: o.leafValidity?.notBefore ?? new Date(now.getTime() - 30 * DAY),
    notAfter: o.leafValidity?.notAfter ?? new Date(now.getTime() + 30 * DAY),
    markers: o.leafMarker === false ? [] : [OID.appleLeaf],
    ocspUrl: o.ocspUrl ? `${o.ocspUrl}/intermediate` : undefined,
  });
  return { root, intermediate, leaf };
}

/** A JWS in StoreKit's form: ES256, the x5c chain leaf first, signed by the leaf. */
export async function signJws(chain: Chain, payload: Record<string, unknown>): Promise<string> {
  const header = b64url(
    JSON.stringify({ alg: "ES256", x5c: [chain.leaf.der, chain.intermediate.der, chain.root.der].map(b64) }),
  );
  const body = b64url(JSON.stringify(payload));
  const raw = new Uint8Array(
    await crypto.subtle.sign(
      SIGN,
      chain.leaf.keys.privateKey,
      new TextEncoder().encode(`${header}.${body}`) as BufferSource,
    ),
  );
  return `${header}.${body}.${b64url(raw)}`;
}

/** An Xcode-environment JWS: StoreKit Testing in Xcode signs with a local key the App Store never saw. */
export async function signXcodeJws(payload: Record<string, unknown>): Promise<string> {
  const keys = await crypto.subtle.generateKey(EC, true, ["sign", "verify"]) as CryptoKeyPair;
  const header = b64url(JSON.stringify({ alg: "ES256", kid: "Apple_Xcode_Key" }));
  const body = b64url(JSON.stringify(payload));
  const raw = new Uint8Array(
    await crypto.subtle.sign(SIGN, keys.privateKey, new TextEncoder().encode(`${header}.${body}`) as BufferSource),
  );
  return `${header}.${body}.${b64url(raw)}`;
}

// ---- A local OCSP responder ----

interface OcspIssuer {
  cert: Issued;
}

export interface OcspResponder {
  url: string;
  /** Serials (hex) to answer `revoked` for. */
  revoked: Set<string>;
  /** When true, the responder answers 500 (Apple's service unreachable). */
  down: boolean;
  /** When true, responses carry no nextUpdate. */
  omitNextUpdate: boolean;
  /** How long before now thisUpdate is (default one minute). */
  thisUpdateAgeMs: number;
  requests: number;
  /** Answers for certificates whose OCSP URL ends in `/<issuerPath>`. */
  register(issuerPath: string, issuer: Issued): void;
  close(): Promise<void>;
}

export function hex(bytes: Uint8Array): string {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

function stripSign(bytes: Uint8Array): Uint8Array {
  let i = 0;
  while (i < bytes.length - 1 && bytes[i] === 0) i++;
  return bytes.subarray(i);
}

/**
 * Answers RFC 6960 requests for certificates issued by the registered issuers, signing each
 * response with the issuer's own key (responder by key hash).
 */
export function startOcspResponder(now: () => Date = () => new Date()): OcspResponder {
  const issuers = new Map<string, OcspIssuer>();
  const state = {
    revoked: new Set<string>(),
    down: false,
    requests: 0,
    omitNextUpdate: false,
    thisUpdateAgeMs: 60_000,
  };
  const server = Deno.serve({ hostname: "127.0.0.1", port: 0, onListen() {} }, async (req) => {
    state.requests++;
    if (state.down) return new Response("unavailable", { status: 500 });
    const path = new URL(req.url).pathname.replace(/^\//, "");
    const issuer = issuers.get(path);
    if (!issuer) return new Response("unknown issuer", { status: 404 });
    const body = new Uint8Array(await req.arrayBuffer());
    // OCSPRequest → tbsRequest → requestList → Request → reqCert (CertID)
    const certId = children(children(children(children(expect(parseRoot(body), TAG.SEQUENCE))[0])[0])[0])[0];
    const certIdBytes = body.subarray(certId.start, certId.end);
    const serial = stripSign(content(children(certId)[3]));
    const issuerCert = parseCertificate(issuer.cert.der);
    const at = now();
    const status = state.revoked.has(hex(serial))
      ? tlv(ctx(1, true), generalizedTime(new Date(at.getTime() - DAY)))
      : new Uint8Array([ctx(0, false), 0x00]);
    const single = state.omitNextUpdate
      ? seq(certIdBytes.slice(), status, generalizedTime(new Date(at.getTime() - state.thisUpdateAgeMs)))
      : seq(
        certIdBytes.slice(),
        status,
        generalizedTime(new Date(at.getTime() - state.thisUpdateAgeMs)),
        explicit(0, generalizedTime(new Date(at.getTime() + DAY))),
      );
    const keyHash = await sha1(issuerCert.publicKeyBits);
    const tbsResponseData = seq(explicit(2, octets(keyHash)), generalizedTime(at), seq(single));
    const signature = await signDer(issuer.cert.keys.privateKey, tbsResponseData);
    const basic = seq(tbsResponseData, seq(oid(OID.ecdsaSha256)), bitString(signature));
    const response = seq(
      tlv(TAG.ENUMERATED, new Uint8Array([0])),
      explicit(0, seq(oid(OID.ocspBasic), octets(basic))),
    );
    return new Response(response as BodyInit, { headers: { "Content-Type": "application/ocsp-response" } });
  });
  const addr = server.addr as Deno.NetAddr;
  return {
    url: `http://127.0.0.1:${addr.port}`,
    get revoked() {
      return state.revoked;
    },
    get down() {
      return state.down;
    },
    set down(value: boolean) {
      state.down = value;
    },
    get omitNextUpdate() {
      return state.omitNextUpdate;
    },
    set omitNextUpdate(value: boolean) {
      state.omitNextUpdate = value;
    },
    get thisUpdateAgeMs() {
      return state.thisUpdateAgeMs;
    },
    set thisUpdateAgeMs(value: number) {
      state.thisUpdateAgeMs = value;
    },
    get requests() {
      return state.requests;
    },
    register(issuerPath, cert) {
      issuers.set(issuerPath, { cert });
    },
    async close() {
      await server.shutdown();
    },
  };
}

/** SHA-256 of a DER certificate as the uppercase colon-separated fingerprint Apple publishes. */
export async function fingerprint(der: Uint8Array): Promise<string> {
  return hex(await sha256(der)).toUpperCase().match(/../g)!.join(":");
}
