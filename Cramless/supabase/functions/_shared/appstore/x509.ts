// Ported from Plainsum (the owner's production relay).
// X.509 certificates: parsing and signature checks with WebCrypto. Supports the algorithms
// Apple's App Store chain uses (ECDSA P-256/P-384 with SHA-256/384) plus RSA PKCS#1 v1.5, so
// any of Apple's three roots can anchor a chain.

import {
  Asn1Error,
  bytesEqual,
  children,
  content,
  ctx,
  encoded,
  expect,
  parseRoot,
  readBitString,
  readBoolean,
  readOid,
  readTime,
  readTlv,
  TAG,
  type Tlv,
} from "./asn1.ts";

export const OID = {
  ecPublicKey: "1.2.840.10045.2.1",
  rsaEncryption: "1.2.840.113549.1.1.1",
  p256: "1.2.840.10045.3.1.7",
  p384: "1.3.132.0.34",
  p521: "1.3.132.0.35",
  ecdsaSha256: "1.2.840.10045.4.3.2",
  ecdsaSha384: "1.2.840.10045.4.3.3",
  ecdsaSha512: "1.2.840.10045.4.3.4",
  rsaSha256: "1.2.840.113549.1.1.11",
  rsaSha384: "1.2.840.113549.1.1.12",
  rsaSha512: "1.2.840.113549.1.1.13",
  basicConstraints: "2.5.29.19",
  extKeyUsage: "2.5.29.37",
  authorityInfoAccess: "1.3.6.1.5.5.7.1.1",
  ocspAccess: "1.3.6.1.5.5.7.48.1",
  ocspSigning: "1.3.6.1.5.5.7.3.9",
  sha256: "2.16.840.1.101.3.4.2.1",
  sha1: "1.3.14.3.2.26",
  ocspBasic: "1.3.6.1.5.5.7.48.1.1",
  /** Apple's marker on the App Store receipt-signing leaf. */
  appleLeaf: "1.2.840.113635.100.6.11.1",
  /** Apple's marker on the WWDR intermediate. */
  appleIntermediate: "1.2.840.113635.100.6.2.1",
} as const;

export interface Certificate {
  der: Uint8Array;
  tbs: Uint8Array;
  signatureAlgorithm: string;
  signature: Uint8Array;
  serial: Uint8Array;
  issuer: Uint8Array;
  subject: Uint8Array;
  notBefore: Date;
  notAfter: Date;
  /** The whole SubjectPublicKeyInfo, for WebCrypto import. */
  spki: Uint8Array;
  /** The subjectPublicKey BIT STRING contents (for OCSP key hashes). */
  publicKeyBits: Uint8Array;
  keyAlgorithm: string;
  /** Curve OID for EC keys. */
  curve: string | null;
  extensions: Map<string, { critical: boolean; value: Uint8Array }>;
  isCA: boolean;
  ocspUrl: string | null;
  extendedKeyUsage: string[];
}

function parseExtensions(node: Tlv): Map<string, { critical: boolean; value: Uint8Array }> {
  const map = new Map<string, { critical: boolean; value: Uint8Array }>();
  const list = expect(children(node)[0], TAG.SEQUENCE);
  for (const ext of children(list)) {
    const parts = children(expect(ext, TAG.SEQUENCE));
    const id = readOid(parts[0]);
    let critical = false;
    let valueNode = parts[1];
    if (valueNode?.tag === TAG.BOOLEAN) {
      critical = readBoolean(valueNode);
      valueNode = parts[2];
    }
    if (map.has(id)) throw new Asn1Error("duplicate extension");
    map.set(id, { critical, value: content(expect(valueNode, TAG.OCTET_STRING)) });
  }
  return map;
}

export function parseCertificate(der: Uint8Array): Certificate {
  const root = parseRoot(der);
  const [tbsNode, algNode, sigNode] = children(expect(root, TAG.SEQUENCE));
  const tbsParts = children(expect(tbsNode, TAG.SEQUENCE));
  let i = 0;
  if (tbsParts[i]?.tag === ctx(0)) i++; // version
  const serial = content(expect(tbsParts[i++], TAG.INTEGER));
  i++; // inner signature algorithm
  const issuer = encoded(expect(tbsParts[i++], TAG.SEQUENCE));
  const validity = children(expect(tbsParts[i++], TAG.SEQUENCE));
  const subject = encoded(expect(tbsParts[i++], TAG.SEQUENCE));
  const spkiNode = expect(tbsParts[i++], TAG.SEQUENCE);
  const [spkiAlg, spkiKey] = children(spkiNode);
  const spkiAlgParts = children(expect(spkiAlg, TAG.SEQUENCE));
  const keyAlgorithm = readOid(spkiAlgParts[0]);
  const curve = keyAlgorithm === OID.ecPublicKey && spkiAlgParts[1]?.tag === TAG.OID ? readOid(spkiAlgParts[1]) : null;

  let extensions = new Map<string, { critical: boolean; value: Uint8Array }>();
  for (; i < tbsParts.length; i++) {
    if (tbsParts[i].tag === ctx(3)) extensions = parseExtensions(tbsParts[i]);
  }

  let isCA = false;
  const bc = extensions.get(OID.basicConstraints);
  if (bc) {
    const fields = children(expect(readTlv(bc.value, 0), TAG.SEQUENCE));
    if (fields[0]?.tag === TAG.BOOLEAN) isCA = readBoolean(fields[0]);
  }

  let ocspUrl: string | null = null;
  const aia = extensions.get(OID.authorityInfoAccess);
  if (aia) {
    for (const desc of children(expect(readTlv(aia.value, 0), TAG.SEQUENCE))) {
      const [method, location] = children(expect(desc, TAG.SEQUENCE));
      if (readOid(method) === OID.ocspAccess && location?.tag === ctx(6, false)) {
        ocspUrl = new TextDecoder().decode(content(location));
      }
    }
  }

  const extendedKeyUsage: string[] = [];
  const eku = extensions.get(OID.extKeyUsage);
  if (eku) {
    for (const usage of children(expect(readTlv(eku.value, 0), TAG.SEQUENCE))) extendedKeyUsage.push(readOid(usage));
  }

  return {
    der,
    tbs: encoded(tbsNode),
    signatureAlgorithm: readOid(children(expect(algNode, TAG.SEQUENCE))[0]),
    signature: readBitString(sigNode),
    serial,
    issuer,
    subject,
    notBefore: readTime(validity[0]),
    notAfter: readTime(validity[1]),
    spki: encoded(spkiNode),
    publicKeyBits: readBitString(spkiKey),
    keyAlgorithm,
    curve,
    extensions,
    isCA,
    ocspUrl,
    extendedKeyUsage,
  };
}

const CURVES: Record<string, { name: string; size: number }> = {
  [OID.p256]: { name: "P-256", size: 32 },
  [OID.p384]: { name: "P-384", size: 48 },
  [OID.p521]: { name: "P-521", size: 66 },
};

const SIGNATURE_HASH: Record<string, { kind: "ecdsa" | "rsa"; hash: string }> = {
  [OID.ecdsaSha256]: { kind: "ecdsa", hash: "SHA-256" },
  [OID.ecdsaSha384]: { kind: "ecdsa", hash: "SHA-384" },
  [OID.ecdsaSha512]: { kind: "ecdsa", hash: "SHA-512" },
  [OID.rsaSha256]: { kind: "rsa", hash: "SHA-256" },
  [OID.rsaSha384]: { kind: "rsa", hash: "SHA-384" },
  [OID.rsaSha512]: { kind: "rsa", hash: "SHA-512" },
};

/** An ECDSA-Sig-Value (SEQUENCE of r and s) as the fixed-size r‖s WebCrypto verifies. */
export function ecdsaDerToRaw(der: Uint8Array, size: number): Uint8Array | null {
  try {
    const [r, s] = children(expect(parseRoot(der), TAG.SEQUENCE));
    const out = new Uint8Array(size * 2);
    for (const [index, node] of [r, s].entries()) {
      let bytes = content(expect(node, TAG.INTEGER));
      while (bytes.length > size && bytes[0] === 0) bytes = bytes.subarray(1);
      if (bytes.length > size) return null;
      out.set(bytes, index * size + (size - bytes.length));
    }
    return out;
  } catch {
    return null;
  }
}

const keyCache = new WeakMap<Certificate, Map<string, Promise<CryptoKey>>>();

/** The certificate's public key, imported for verifying with `hash`. */
export function publicKey(cert: Certificate, hash: string): Promise<CryptoKey> {
  let byHash = keyCache.get(cert);
  if (!byHash) {
    byHash = new Map();
    keyCache.set(cert, byHash);
  }
  let key = byHash.get(hash);
  if (!key) {
    if (cert.keyAlgorithm === OID.ecPublicKey) {
      const curve = cert.curve ? CURVES[cert.curve] : undefined;
      if (!curve) return Promise.reject(new Error("unsupported curve"));
      key = crypto.subtle.importKey(
        "spki",
        cert.spki as BufferSource,
        { name: "ECDSA", namedCurve: curve.name },
        false,
        ["verify"],
      );
    } else if (cert.keyAlgorithm === OID.rsaEncryption) {
      key = crypto.subtle.importKey(
        "spki",
        cert.spki as BufferSource,
        { name: "RSASSA-PKCS1-v1_5", hash },
        false,
        ["verify"],
      );
    } else {
      return Promise.reject(new Error("unsupported key algorithm"));
    }
    byHash.set(hash, key);
  }
  return key;
}

/** Verifies `signature` (DER form for ECDSA) over `data` with `signer`'s key. Never throws. */
export async function verifyWith(
  signer: Certificate,
  algorithmOid: string,
  data: Uint8Array,
  signature: Uint8Array,
): Promise<boolean> {
  const alg = SIGNATURE_HASH[algorithmOid];
  if (!alg) return false;
  try {
    if (alg.kind === "ecdsa") {
      if (signer.keyAlgorithm !== OID.ecPublicKey || !signer.curve) return false;
      const curve = CURVES[signer.curve];
      const raw = curve ? ecdsaDerToRaw(signature, curve.size) : null;
      if (!raw) return false;
      const key = await publicKey(signer, alg.hash);
      return await crypto.subtle.verify(
        { name: "ECDSA", hash: alg.hash },
        key,
        raw as BufferSource,
        data as BufferSource,
      );
    }
    if (signer.keyAlgorithm !== OID.rsaEncryption) return false;
    const key = await publicKey(signer, alg.hash);
    return await crypto.subtle.verify(
      { name: "RSASSA-PKCS1-v1_5" },
      key,
      signature as BufferSource,
      data as BufferSource,
    );
  } catch {
    return false;
  }
}

/** True when `issuer` signed `cert` and their names chain. */
export async function isIssuedBy(cert: Certificate, issuer: Certificate): Promise<boolean> {
  if (!bytesEqual(cert.issuer, issuer.subject)) return false;
  return await verifyWith(issuer, cert.signatureAlgorithm, cert.tbs, cert.signature);
}

export function base64ToBytes(text: string): Uint8Array {
  const clean = text.replace(/[\s]/g, "");
  const binary = atob(clean);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

export async function sha256(bytes: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", bytes as BufferSource));
}

export async function sha1(bytes: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-1", bytes as BufferSource));
}
