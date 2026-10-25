// Ported from Plainsum (the owner's production relay).
// A minimal DER reader and writer: enough ASN.1 for X.509 certificates, OCSP requests and
// OCSP responses. Only definite lengths (DER); anything malformed throws.

export class Asn1Error extends Error {}

export interface Tlv {
  /** The identifier octet. */
  tag: number;
  /** Offset of the identifier octet in `buf`. */
  start: number;
  /** Offset of the first content octet. */
  contentStart: number;
  /** Offset just past the last content octet. */
  end: number;
  buf: Uint8Array;
}

export const TAG = {
  BOOLEAN: 0x01,
  INTEGER: 0x02,
  BIT_STRING: 0x03,
  OCTET_STRING: 0x04,
  NULL: 0x05,
  OID: 0x06,
  ENUMERATED: 0x0a,
  UTF8_STRING: 0x0c,
  PRINTABLE_STRING: 0x13,
  IA5_STRING: 0x16,
  UTC_TIME: 0x17,
  GENERALIZED_TIME: 0x18,
  SEQUENCE: 0x30,
  SET: 0x31,
} as const;

/** Context-specific tag number n, constructed (explicit tagging) or primitive. */
export function ctx(n: number, constructed = true): number {
  return 0x80 | (constructed ? 0x20 : 0) | n;
}

export function readTlv(buf: Uint8Array, offset = 0, limit = buf.length): Tlv {
  if (offset + 2 > limit) throw new Asn1Error("truncated");
  const tag = buf[offset];
  if ((tag & 0x1f) === 0x1f) throw new Asn1Error("high tag numbers aren't used");
  let length = buf[offset + 1];
  let contentStart = offset + 2;
  if (length & 0x80) {
    const count = length & 0x7f;
    if (count === 0 || count > 4) throw new Asn1Error("unsupported length");
    if (contentStart + count > limit) throw new Asn1Error("truncated length");
    length = 0;
    for (let i = 0; i < count; i++) length = length * 256 + buf[contentStart + i];
    contentStart += count;
  }
  const end = contentStart + length;
  if (end > limit) throw new Asn1Error("content runs past its container");
  return { tag, start: offset, contentStart, end, buf };
}

/** The TLVs inside a constructed value. */
export function children(node: Tlv): Tlv[] {
  const out: Tlv[] = [];
  let offset = node.contentStart;
  while (offset < node.end) {
    const child = readTlv(node.buf, offset, node.end);
    out.push(child);
    offset = child.end;
  }
  return out;
}

export function expect(node: Tlv | undefined, tag: number): Tlv {
  if (!node || node.tag !== tag) {
    throw new Asn1Error(`expected tag 0x${tag.toString(16)}, got ${node ? "0x" + node.tag.toString(16) : "nothing"}`);
  }
  return node;
}

export function content(node: Tlv): Uint8Array {
  return node.buf.subarray(node.contentStart, node.end);
}

/** The whole encoding (identifier, length and content). */
export function encoded(node: Tlv): Uint8Array {
  return node.buf.subarray(node.start, node.end);
}

export function parseRoot(der: Uint8Array): Tlv {
  const root = readTlv(der, 0);
  if (root.end !== der.length) throw new Asn1Error("trailing bytes");
  return root;
}

export function readOid(node: Tlv): string {
  const bytes = content(expect(node, TAG.OID));
  if (bytes.length === 0) throw new Asn1Error("empty OID");
  const parts: number[] = [];
  let value = 0;
  for (let i = 0; i < bytes.length; i++) {
    value = value * 128 + (bytes[i] & 0x7f);
    if ((bytes[i] & 0x80) === 0) {
      if (parts.length === 0) {
        const first = value < 80 ? Math.floor(value / 40) : 2;
        parts.push(first, value - first * 40);
      } else {
        parts.push(value);
      }
      value = 0;
    }
  }
  return parts.join(".");
}

/** UTCTime or GeneralizedTime (Zulu forms, as DER requires). */
export function readTime(node: Tlv): Date {
  const text = new TextDecoder().decode(content(node));
  let m: RegExpExecArray | null;
  if (node.tag === TAG.UTC_TIME) {
    m = /^([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})Z$/.exec(text);
    if (!m) throw new Asn1Error("bad UTCTime");
    const yy = Number(m[1]);
    const year = yy >= 50 ? 1900 + yy : 2000 + yy;
    return new Date(Date.UTC(year, Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6])));
  }
  if (node.tag === TAG.GENERALIZED_TIME) {
    m = /^([0-9]{4})([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})(?:\.[0-9]+)?Z$/.exec(text);
    if (!m) throw new Asn1Error("bad GeneralizedTime");
    return new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6])));
  }
  throw new Asn1Error("not a time");
}

/** BIT STRING contents without the unused-bits octet (which must be 0 here). */
export function readBitString(node: Tlv): Uint8Array {
  const bytes = content(expect(node, TAG.BIT_STRING));
  if (bytes.length === 0 || bytes[0] !== 0) throw new Asn1Error("unsupported BIT STRING");
  return bytes.subarray(1);
}

export function readBoolean(node: Tlv): boolean {
  const bytes = content(expect(node, TAG.BOOLEAN));
  if (bytes.length !== 1) throw new Asn1Error("bad BOOLEAN");
  return bytes[0] !== 0;
}

export function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

// ---- Writer ----

function lengthBytes(length: number): number[] {
  if (length < 0x80) return [length];
  const out: number[] = [];
  let n = length;
  while (n > 0) {
    out.unshift(n & 0xff);
    n = Math.floor(n / 256);
  }
  return [0x80 | out.length, ...out];
}

/** A fresh `ArrayBuffer`-backed array, so encoded values can go straight into a fetch body (`BodyInit`). */
export function concat(...parts: Uint8Array[]): Uint8Array<ArrayBuffer> {
  const total = parts.reduce((n, p) => n + p.length, 0);
  const out = new Uint8Array(total);
  let offset = 0;
  for (const p of parts) {
    out.set(p, offset);
    offset += p.length;
  }
  return out;
}

export function tlv(tag: number, ...contents: Uint8Array[]): Uint8Array<ArrayBuffer> {
  const body = concat(...contents);
  return concat(new Uint8Array([tag, ...lengthBytes(body.length)]), body);
}

export const seq = (...items: Uint8Array[]) => tlv(TAG.SEQUENCE, ...items);
export const set = (...items: Uint8Array[]) => tlv(TAG.SET, ...items);
export const octets = (bytes: Uint8Array) => tlv(TAG.OCTET_STRING, bytes);
export const nullValue = () => tlv(TAG.NULL);
export const bitString = (bytes: Uint8Array) => tlv(TAG.BIT_STRING, new Uint8Array([0]), bytes);
export const boolean = (value: boolean) => tlv(TAG.BOOLEAN, new Uint8Array([value ? 0xff : 0]));
export const explicit = (n: number, inner: Uint8Array) => tlv(ctx(n, true), inner);

/** An INTEGER from its unsigned big-endian magnitude. */
export function integer(magnitude: Uint8Array | number): Uint8Array {
  let bytes: Uint8Array;
  if (typeof magnitude === "number") {
    const out: number[] = [];
    let n = magnitude;
    do {
      out.unshift(n & 0xff);
      n = Math.floor(n / 256);
    } while (n > 0);
    bytes = new Uint8Array(out);
  } else {
    let i = 0;
    while (i < magnitude.length - 1 && magnitude[i] === 0) i++;
    bytes = magnitude.subarray(i);
  }
  if (bytes[0] & 0x80) bytes = concat(new Uint8Array([0]), bytes);
  return tlv(TAG.INTEGER, bytes);
}

export function oid(dotted: string): Uint8Array {
  const parts = dotted.split(".").map(Number);
  const out: number[] = [];
  for (const part of [parts[0] * 40 + parts[1], ...parts.slice(2)]) {
    const chunk: number[] = [];
    let n = part;
    chunk.unshift(n & 0x7f);
    n = Math.floor(n / 128);
    while (n > 0) {
      chunk.unshift((n & 0x7f) | 0x80);
      n = Math.floor(n / 128);
    }
    out.push(...chunk);
  }
  return tlv(TAG.OID, new Uint8Array(out));
}

function two(n: number): string {
  return String(n).padStart(2, "0");
}

export function utcTime(date: Date): Uint8Array {
  const text = `${two(date.getUTCFullYear() % 100)}${two(date.getUTCMonth() + 1)}${two(date.getUTCDate())}` +
    `${two(date.getUTCHours())}${two(date.getUTCMinutes())}${two(date.getUTCSeconds())}Z`;
  return tlv(TAG.UTC_TIME, new TextEncoder().encode(text));
}

export function generalizedTime(date: Date): Uint8Array {
  const text = `${date.getUTCFullYear()}${two(date.getUTCMonth() + 1)}${two(date.getUTCDate())}` +
    `${two(date.getUTCHours())}${two(date.getUTCMinutes())}${two(date.getUTCSeconds())}Z`;
  return tlv(TAG.GENERALIZED_TIME, new TextEncoder().encode(text));
}

export function utf8String(text: string): Uint8Array {
  return tlv(TAG.UTF8_STRING, new TextEncoder().encode(text));
}

export function ia5String(text: string): Uint8Array {
  return tlv(TAG.IA5_STRING, new TextEncoder().encode(text));
}
