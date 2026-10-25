// Ported from Plainsum. OCSP revocation checks (RFC 6960) for the App Store signing chain, as Apple's
// SignedDataVerifier does with online checks on: a SHA-256 CertID request to the responder
// named in the certificate, a signed response from the issuer (or a delegate it certified for
// OCSP signing), and a `good` status that's current.

import {
  bytesEqual,
  children,
  content,
  ctx,
  encoded,
  expect,
  integer,
  nullValue,
  octets,
  oid,
  parseRoot,
  readBitString,
  readOid,
  readTime,
  seq,
  TAG,
  type Tlv,
} from "./asn1.ts";
import { type Certificate, isIssuedBy, OID, parseCertificate, sha1, sha256, verifyWith } from "./x509.ts";

export const MAX_SKEW_MS = 60_000;
/** Without nextUpdate, a response is good only while thisUpdate is this recent. */
export const MAX_AGE_WITHOUT_NEXT_UPDATE_MS = 7 * 24 * 3600 * 1000;

export type OcspOutcome = "good" | "revoked" | "invalid" | "unavailable";

export async function buildOcspRequest(cert: Certificate, issuer: Certificate): Promise<Uint8Array<ArrayBuffer>> {
  const certId = seq(
    seq(oid(OID.sha256), nullValue()),
    octets(await sha256(issuer.subject)),
    octets(await sha256(issuer.publicKeyBits)),
    integer(cert.serial),
  );
  return seq(seq(seq(seq(certId))));
}

interface SingleResponse {
  hashAlgorithm: string;
  issuerNameHash: Uint8Array;
  issuerKeyHash: Uint8Array;
  serial: Uint8Array;
  status: "good" | "revoked" | "unknown";
  thisUpdate: Date;
  nextUpdate: Date | null;
}

function parseSingle(node: Tlv): SingleResponse {
  const parts = children(expect(node, TAG.SEQUENCE));
  const certId = children(expect(parts[0], TAG.SEQUENCE));
  const hashAlgorithm = readOid(children(expect(certId[0], TAG.SEQUENCE))[0]);
  const statusTag = parts[1].tag;
  const status = statusTag === ctx(0, false) ? "good" : statusTag === ctx(1, true) ? "revoked" : "unknown";
  const thisUpdate = readTime(expect(parts[2], TAG.GENERALIZED_TIME));
  let nextUpdate: Date | null = null;
  for (const extra of parts.slice(3)) {
    if (extra.tag === ctx(0)) nextUpdate = readTime(expect(children(extra)[0], TAG.GENERALIZED_TIME));
  }
  return {
    hashAlgorithm,
    issuerNameHash: content(expect(certId[1], TAG.OCTET_STRING)),
    issuerKeyHash: content(expect(certId[2], TAG.OCTET_STRING)),
    serial: content(expect(certId[3], TAG.INTEGER)),
    status,
    thisUpdate,
    nextUpdate,
  };
}

/**
 * Checks an OCSP response for `cert` issued by `issuer`. `now` is the verification time.
 * Returns "good", "revoked" or "invalid" (anything unverifiable).
 */
export async function evaluateOcspResponse(
  der: Uint8Array,
  cert: Certificate,
  issuer: Certificate,
  now: Date,
): Promise<OcspOutcome> {
  try {
    const top = children(expect(parseRoot(der), TAG.SEQUENCE));
    if (content(expect(top[0], TAG.ENUMERATED))[0] !== 0) return "invalid";
    const responseBytes = children(expect(children(expect(top[1], ctx(0)))[0], TAG.SEQUENCE));
    if (readOid(responseBytes[0]) !== OID.ocspBasic) return "invalid";
    const basic = children(expect(parseRoot(content(expect(responseBytes[1], TAG.OCTET_STRING))), TAG.SEQUENCE));
    const tbsNode = expect(basic[0], TAG.SEQUENCE);
    const sigAlg = readOid(children(expect(basic[1], TAG.SEQUENCE))[0]);
    const signature = readBitString(basic[2]);
    const included: Certificate[] = [];
    if (basic[3]?.tag === ctx(0)) {
      for (const certNode of children(expect(children(basic[3])[0], TAG.SEQUENCE))) {
        included.push(parseCertificate(encoded(certNode).slice()));
      }
    }

    const data = children(tbsNode);
    let j = 0;
    if (data[j]?.tag === ctx(0)) j++; // version
    const responder = data[j++];
    j++; // producedAt
    const responses = children(expect(data[j], TAG.SEQUENCE)).map(parseSingle);

    // Who signed: by key hash (SHA-1 of the public key bits) or by name.
    const candidates = [issuer, ...included];
    let signer: Certificate | null = null;
    if (responder.tag === ctx(2)) {
      const keyHash = content(expect(children(responder)[0], TAG.OCTET_STRING));
      for (const c of candidates) {
        if (bytesEqual(await sha1(c.publicKeyBits), keyHash)) signer = c;
      }
    } else if (responder.tag === ctx(1)) {
      const name = encoded(children(responder)[0]);
      for (const c of candidates) {
        if (bytesEqual(c.subject, name)) signer = c;
      }
    }
    if (!signer) return "invalid";
    if (signer !== issuer && !(bytesEqual(signer.spki, issuer.spki) && bytesEqual(signer.subject, issuer.subject))) {
      // A delegated responder: issued by the issuer, marked for OCSP signing, currently valid.
      if (!(await isIssuedBy(signer, issuer))) return "invalid";
      if (!signer.extendedKeyUsage.includes(OID.ocspSigning)) return "invalid";
      if (signer.notBefore.getTime() > now.getTime() + MAX_SKEW_MS) return "invalid";
      if (signer.notAfter.getTime() < now.getTime() - MAX_SKEW_MS) return "invalid";
    }
    if (!(await verifyWith(signer, sigAlg, encoded(tbsNode), signature))) return "invalid";

    const nameHash = await sha256(issuer.subject);
    const keyHash = await sha256(issuer.publicKeyBits);
    for (const single of responses) {
      if (single.hashAlgorithm !== OID.sha256) continue;
      if (!bytesEqual(single.issuerNameHash, nameHash) || !bytesEqual(single.issuerKeyHash, keyHash)) continue;
      if (!bytesEqual(stripSign(single.serial), stripSign(cert.serial))) continue;
      if (single.status === "revoked") return "revoked";
      if (single.status !== "good") return "invalid";
      if (single.thisUpdate.getTime() > now.getTime() + MAX_SKEW_MS) return "invalid";
      if (single.nextUpdate && single.nextUpdate.getTime() < now.getTime() - MAX_SKEW_MS) return "invalid";
      if (!single.nextUpdate && single.thisUpdate.getTime() < now.getTime() - MAX_AGE_WITHOUT_NEXT_UPDATE_MS) {
        return "invalid";
      }
      return "good";
    }
    return "invalid";
  } catch {
    return "invalid";
  }
}

function stripSign(bytes: Uint8Array): Uint8Array {
  let i = 0;
  while (i < bytes.length - 1 && bytes[i] === 0) i++;
  return bytes.subarray(i);
}

/** Asks the certificate's OCSP responder. "unavailable" when the responder can't be reached. */
export async function checkOcsp(
  cert: Certificate,
  issuer: Certificate,
  now: Date,
  fetchFn: typeof fetch = fetch,
  timeoutMs = 10_000,
): Promise<OcspOutcome> {
  if (!cert.ocspUrl) return "invalid";
  const request = await buildOcspRequest(cert, issuer);
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  let body: Uint8Array;
  try {
    const res = await fetchFn(cert.ocspUrl, {
      method: "POST",
      headers: { "Content-Type": "application/ocsp-request", Accept: "application/ocsp-response" },
      body: request,
      signal: controller.signal,
    });
    if (!res.ok) {
      await res.body?.cancel();
      return "unavailable";
    }
    body = new Uint8Array(await res.arrayBuffer());
  } catch {
    return "unavailable";
  } finally {
    clearTimeout(timer);
  }
  return await evaluateOcspResponse(body, cert, issuer, now);
}
