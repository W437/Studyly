// A small JSON Schema validator for the subset Capling's schemas use (ported from Plainsum's). The relay
// validates request bodies and every structured model reply with it; no third-party validator.
//
// Supported: $ref (#/$defs/X), type (a name or a list), const, enum, anyOf, properties, required,
// additionalProperties, items, minItems, maxItems, minLength, maxLength (code points), pattern (Unicode), format
// (date, date-time), minimum, maximum. Annotations ($comment, description, title, $defs) are ignored. Any other
// keyword is a programming error and throws.

export interface SchemaIssue {
  path: string;
  message: string;
}

// deno-lint-ignore no-explicit-any
export type Schema = Record<string, any>;

const ANNOTATIONS = new Set(["$comment", "description", "title", "$defs", "examples"]);
const KEYWORDS = new Set([
  "$ref",
  "type",
  "const",
  "enum",
  "anyOf",
  "properties",
  "required",
  "additionalProperties",
  "items",
  "minItems",
  "maxItems",
  "minLength",
  "maxLength",
  "pattern",
  "format",
  "minimum",
  "maximum",
]);

const patternCache = new Map<string, RegExp>();

function regex(pattern: string): RegExp {
  let re = patternCache.get(pattern);
  if (!re) {
    re = new RegExp(pattern, "u");
    patternCache.set(pattern, re);
  }
  return re;
}

function typeOf(value: unknown): string {
  if (value === null) return "null";
  if (Array.isArray(value)) return "array";
  if (typeof value === "number") return Number.isInteger(value) ? "integer" : "number";
  return typeof value;
}

function matchesType(value: unknown, type: string): boolean {
  const actual = typeOf(value);
  if (type === "number") return actual === "number" || actual === "integer";
  return actual === type;
}

function isIsoDate(text: string): boolean {
  const m = /^([0-9]{4})-([0-9]{2})-([0-9]{2})$/.exec(text);
  if (!m) return false;
  const month = Number(m[2]);
  const day = Number(m[3]);
  if (month < 1 || month > 12 || day < 1) return false;
  return day <= new Date(Date.UTC(Number(m[1]), month, 0)).getUTCDate();
}

function isDateTime(text: string): boolean {
  if (!/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}(:[0-9]{2}(\.[0-9]+)?)?(Z|[+-][0-9]{2}:[0-9]{2})$/.test(text)) {
    return false;
  }
  return isIsoDate(text.slice(0, 10)) && !Number.isNaN(Date.parse(text));
}

function codePoints(text: string): number {
  let n = 0;
  for (const _ of text) n++;
  return n;
}

function resolveRef(root: Schema, ref: string): Schema {
  const m = /^#\/\$defs\/([A-Za-z0-9_]+)$/.exec(ref);
  if (!m) throw new Error(`Unsupported $ref ${ref}`);
  const target = root.$defs?.[m[1]];
  if (!target) throw new Error(`Unresolved $ref ${ref}`);
  return target;
}

function check(schema: Schema, value: unknown, root: Schema, path: string, issues: SchemaIssue[]): void {
  for (const key of Object.keys(schema)) {
    if (!KEYWORDS.has(key) && !ANNOTATIONS.has(key)) {
      throw new Error(`Unsupported schema keyword "${key}" at ${path || "/"}`);
    }
  }

  if (schema.$ref) {
    check(resolveRef(root, schema.$ref), value, root, path, issues);
    return;
  }

  if (schema.anyOf) {
    const ok = (schema.anyOf as Schema[]).some((branch) => {
      const inner: SchemaIssue[] = [];
      check(branch, value, root, path, inner);
      return inner.length === 0;
    });
    if (!ok) issues.push({ path, message: "matches none of the allowed forms" });
    return;
  }

  if (schema.type !== undefined) {
    const types: string[] = Array.isArray(schema.type) ? schema.type : [schema.type];
    if (!types.some((t) => matchesType(value, t))) {
      issues.push({ path, message: `expected ${types.join(" or ")}` });
      return;
    }
  }

  if ("const" in schema && value !== schema.const) {
    issues.push({ path, message: `expected ${JSON.stringify(schema.const)}` });
    return;
  }

  if (schema.enum && !schema.enum.includes(value)) {
    issues.push({ path, message: "isn't one of the allowed values" });
    return;
  }

  if (typeof value === "string") {
    if (schema.minLength !== undefined || schema.maxLength !== undefined) {
      const n = codePoints(value);
      if (schema.minLength !== undefined && n < schema.minLength) {
        issues.push({ path, message: `is shorter than ${schema.minLength}` });
      }
      if (schema.maxLength !== undefined && n > schema.maxLength) {
        issues.push({ path, message: `is longer than ${schema.maxLength}` });
      }
    }
    if (schema.pattern !== undefined && !regex(schema.pattern).test(value)) {
      issues.push({ path, message: "doesn't match the pattern" });
    }
    if (schema.format === "date" && !isIsoDate(value)) issues.push({ path, message: "isn't a yyyy-MM-dd date" });
    if (schema.format === "date-time" && !isDateTime(value)) {
      issues.push({ path, message: "isn't an ISO 8601 date-time" });
    }
  }

  if (typeof value === "number") {
    if (!Number.isFinite(value)) issues.push({ path, message: "isn't a finite number" });
    if (schema.minimum !== undefined && value < schema.minimum) {
      issues.push({ path, message: `is below ${schema.minimum}` });
    }
    if (schema.maximum !== undefined && value > schema.maximum) {
      issues.push({ path, message: `is above ${schema.maximum}` });
    }
  }

  if (Array.isArray(value)) {
    if (schema.minItems !== undefined && value.length < schema.minItems) {
      issues.push({ path, message: `has fewer than ${schema.minItems} items` });
    }
    if (schema.maxItems !== undefined && value.length > schema.maxItems) {
      issues.push({ path, message: `has more than ${schema.maxItems} items` });
      return;
    }
    if (schema.items) value.forEach((item, i) => check(schema.items, item, root, `${path}/${i}`, issues));
  }

  if (typeOf(value) === "object") {
    const obj = value as Record<string, unknown>;
    const props: Record<string, Schema> = schema.properties ?? {};
    for (const name of schema.required ?? []) {
      if (!(name in obj)) issues.push({ path: `${path}/${name}`, message: "is required" });
    }
    for (const [name, child] of Object.entries(obj)) {
      if (name in props) {
        check(props[name], child, root, `${path}/${name}`, issues);
      } else if (schema.additionalProperties === false) {
        issues.push({ path: `${path}/${name}`, message: "isn't allowed" });
      }
    }
  }
}

/** Validates `value` against `schema` (whose `$defs` resolve its refs); returns the problems found. */
export function validate(schema: Schema, value: unknown): SchemaIssue[] {
  const issues: SchemaIssue[] = [];
  check(schema, value, schema, "", issues);
  return issues;
}

/** One line naming the first problem (paths only, never values), for error messages. */
export function describeIssues(issues: SchemaIssue[]): string {
  if (issues.length === 0) return "valid";
  const first = issues[0];
  const more = issues.length > 1 ? ` (and ${issues.length - 1} more)` : "";
  return `${first.path || "body"} ${first.message}${more}`;
}
