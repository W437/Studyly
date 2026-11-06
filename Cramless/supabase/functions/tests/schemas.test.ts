// The contract's schemas against the fixtures, the Swift types and the structured-outputs subset.

import { assert, assertEquals } from "@std/assert";
import { CONTRACT_SCHEMA, FIXTURES, REQUEST_SCHEMA } from "../_shared/generated.ts";
import { contractSchema, providerSchema, requestSchema } from "../_shared/schemas.ts";
import { describeIssues, type Schema, validate } from "../_shared/schema.ts";

/** Every fixture and the type it is an example of. */
export const FIXTURE_TYPES: Record<string, string> = {
  "account-delete": "AccountDeleteResponse",
  "assistant-answer": "AssistantScript",
  "assistant-cards": "AssistantScript",
  "assistant-cards-final": "AssistantScript",
  "assistant-error": "AssistantScript",
  "assistant-exam": "AssistantScript",
  "assistant-exam-final": "AssistantScript",
  "assistant-failed-final": "AssistantScript",
  "assistant-limit": "AssistantScript",
  "assistant-multi-1": "AssistantScript",
  "assistant-multi-2": "AssistantScript",
  "assistant-multi-final": "AssistantScript",
  "assistant-note": "AssistantScript",
  "assistant-note-final": "AssistantScript",
  "assistant-open": "AssistantScript",
  "assistant-open-final": "AssistantScript",
  "assistant-practice": "AssistantScript",
  "assistant-practice-final": "AssistantScript",
  "assistant-quiz": "AssistantScript",
  "assistant-quiz-final": "AssistantScript",
  "assistant-research": "AssistantScript",
  "assistant-research-final": "AssistantScript",
  "cards-from-chat": "CardsFromChatResponse",
  check: "CheckResponse",
  confusions: "ConfusionsResponse",
  "confusions-lookalike": "ConfusionsResponse",
  entitlement: "EntitlementResponse",
  "error-quota": "RelayErrorBody",
  generate: "GenerateResponse",
  "grade-correct": "GradeResponse",
  "grade-incorrect": "GradeResponse",
  "grade-partial": "GradeResponse",
  lecture: "LectureResponse",
  "quota-free": "QuotaStatus",
  "research-error": "ResearchScript",
  "research-mitosis": "ResearchScript",
  "quota-pro": "QuotaStatus",
  "squad-invite": "SquadInvite",
  "squad-members": "SquadMembers",
  "squad-redeem": "SquadRedeemResponse",
  "transcribe-image": "TranscribeImageResponse",
  "tutor-error": "TutorScript",
  "tutor-explain": "TutorScript",
  "tutor-hints": "TutorScript",
  "check-reported": "CheckResponse",
  "generate-rung": "GenerateResponse",
  "tutor-mistake": "TutorScript",
  "tutor-photo": "TutorScript",
  "tutor-photo-uncited": "TutorScript",
  syllabus: "SyllabusResponse",
  "exam-mention": "ExamMentionResponse",
  "requests/syllabus": "SyllabusRequest",
  "requests/exam-mention": "ExamMentionRequest",
  "requests/assistant": "AssistantRequest",
  "requests/generate": "GenerateRequest",
  "requests/grade": "GradeRequest",
  "requests/research": "ResearchRequest",
  "requests/tutor": "TutorRequest",
};

Deno.test("every fixture has a type and validates against it", () => {
  assertEquals(
    Object.keys(FIXTURES).sort(),
    Object.keys(FIXTURE_TYPES).sort(),
    "a fixture without a type, or a type without a fixture",
  );
  for (const [name, type] of Object.entries(FIXTURE_TYPES)) {
    const schema = name.startsWith("requests/") ? requestSchema(type) : contractSchema(type);
    const issues = validate(schema, JSON.parse(FIXTURES[name]));
    assertEquals(issues, [], `${name}: ${describeIssues(issues)}`);
  }
});

Deno.test("the schemas refuse what the Swift decoder would refuse", () => {
  const generate = JSON.parse(FIXTURES.generate);
  generate.items[0].kind = "essay";
  assert(validate(contractSchema("GenerateResponse"), generate).length > 0);
  const grade = JSON.parse(FIXTURES["grade-partial"]);
  delete grade.confidence;
  assert(validate(contractSchema("GradeResponse"), grade).length > 0);
  const quota = JSON.parse(FIXTURES["quota-free"]);
  quota.meters[0].period = "month";
  assert(validate(contractSchema("QuotaStatus"), quota).length > 0);
  const invite = JSON.parse(FIXTURES["squad-invite"]);
  invite.expiresAt = "next week";
  assert(validate(contractSchema("SquadInvite"), invite).length > 0);
});

// ---- Parity with the Swift types ----

interface SwiftField {
  name: string;
  optional: boolean;
}

/** The stored properties of each top-level `struct` in a Swift file (computed properties and nested types
 * excluded). */
function swiftStructs(source: string): Map<string, SwiftField[]> {
  const out = new Map<string, SwiftField[]>();
  const re = /^(\s*)struct (\w+)[^{]*\{/gm;
  let m: RegExpExecArray | null;
  while ((m = re.exec(source))) {
    const name = m[2];
    let depth = 1;
    let i = re.lastIndex;
    const start = i;
    while (i < source.length && depth > 0) {
      if (source[i] === "{") depth++;
      else if (source[i] === "}") depth--;
      i++;
    }
    const body = source.slice(start, i - 1);
    const fields: SwiftField[] = [];
    let level = 0;
    for (const line of body.split("\n")) {
      if (level === 0) {
        const f = /^\s*var (\w+): ([^={]+?)\s*(=.*)?$/.exec(line);
        if (f && !line.includes("{")) fields.push({ name: f[1], optional: f[2].trim().endsWith("?") });
      }
      for (const ch of line) {
        if (ch === "{") level++;
        else if (ch === "}") level--;
      }
    }
    out.set(name, fields);
  }
  return out;
}

const ROOT = new URL("../../../", import.meta.url);

/** Fields the relay accepts or returns before the app's Swift types have them (all optional, so the shipped build is
 * unaffected). The parity tests below leave these out of the comparison whether or not the Swift type has them yet, so the
 * relay and the app can land in either order. Delete an entry once its Swift field exists. */
const RELAY_AHEAD: Record<string, string[]> = {
  TutorRequest: ["materials"],
  CheckRequest: ["sourceTitle", "headings", "lenient"],
  LectureResponse: ["leftOut"],
};
const ahead = (type: string, fields: string[]) => fields.filter((f) => !(RELAY_AHEAD[type] ?? []).includes(f)).sort();

const SWIFT_TO_SCHEMA: Record<string, string> = {
  LineInput: "LineInput",
  GeneratedItem: "GeneratedItem",
  GeneratedTopic: "GeneratedTopic",
  GenerateResponse: "GenerateResponse",
  CheckVerdict: "CheckVerdict",
  CheckResponse: "CheckResponse",
  GradeHit: "GradeHit",
  GradeResponse: "GradeResponse",
  TutorScript: "TutorScript",
  ConfusionOut: "ConfusionOut",
  ConfusionsResponse: "ConfusionsResponse",
  LectureExamFlag: "LectureExamFlag",
  LectureResponse: "LectureResponse",
  CardsFromChatResponse: "CardsFromChatResponse",
  TranscribeImageResponse: "TranscribeImageResponse",
  QuotaMeter: "QuotaMeter",
  QuotaStatus: "QuotaStatus",
  EntitlementResponse: "EntitlementResponse",
  SquadInvite: "SquadInvite",
  SquadRedeemResponse: "SquadRedeemResponse",
  SquadMember: "SquadMember",
  SquadMembers: "SquadMembers",
  AccountDeleteResponse: "AccountDeleteResponse",
  KeyIdea: "KeyIdea",
  Choice: "Choice",
  ClozeSpec: "ClozeSpec",
  Section: "LectureSection",
  SyllabusTopic: "SyllabusTopic",
  SyllabusFormat: "SyllabusFormat",
  SyllabusExam: "SyllabusExam",
  SyllabusResponse: "SyllabusResponse",
  ExamMentionVerdict: "ExamMentionVerdict",
  ExamMentionResponse: "ExamMentionResponse",
};

const SWIFT_REQUESTS = [
  "PageInput",
  "GenerateRequest",
  "CheckRequest",
  "GradeRequest",
  "TutorMessage",
  "TutorRequest",
  "ConfusionsRequest",
  "LectureRequest",
  "CardsFromChatRequest",
  "TranscribeImageRequest",
  "EntitlementRequest",
  "SquadRedeemRequest",
  "SquadRemoveRequest",
  "SyllabusRequest",
  "ExamMentionRequest",
];

Deno.test("contract.json has the Swift reply types' fields, and their optionality", async () => {
  const swift = new Map([
    ...swiftStructs(await Deno.readTextFile(new URL("Cramless/AI/RelayContract.swift", ROOT))),
    ...swiftStructs(await Deno.readTextFile(new URL("Cramless/Model/ModelTypes.swift", ROOT))),
  ]);
  for (const [swiftName, schemaName] of Object.entries(SWIFT_TO_SCHEMA)) {
    const fields = swift.get(swiftName);
    assert(fields && fields.length > 0, `Swift struct ${swiftName} not found`);
    const def = CONTRACT_SCHEMA.$defs[schemaName];
    assertEquals(
      ahead(schemaName, Object.keys(def.properties)),
      ahead(schemaName, fields.map((f) => f.name)),
      `${schemaName} fields`,
    );
    const required = new Set<string>(def.required);
    for (const f of fields) {
      assertEquals(!required.has(f.name), f.optional, `${schemaName}.${f.name}: optional in Swift ↔ not required`);
    }
  }
});

Deno.test("requests.json has the Swift request types' fields; it requires none the Swift type makes optional", async () => {
  const swift = swiftStructs(await Deno.readTextFile(new URL("Cramless/AI/RelayContract.swift", ROOT)));
  for (const name of SWIFT_REQUESTS) {
    const fields = swift.get(name);
    assert(fields && fields.length > 0, `Swift struct ${name} not found`);
    const def = REQUEST_SCHEMA.$defs[name];
    assertEquals(ahead(name, Object.keys(def.properties)), ahead(name, fields.map((f) => f.name)), `${name} fields`);
    for (const r of def.required as string[]) {
      assert(!fields.find((f) => f.name === r)!.optional, `${name}.${r} is optional in Swift but required here`);
    }
  }
});

Deno.test("the fields the relay has ahead of the app are all optional", () => {
  for (const [type, fields] of Object.entries(RELAY_AHEAD)) {
    const def = type.endsWith("Request") ? REQUEST_SCHEMA.$defs[type] : CONTRACT_SCHEMA.$defs[type];
    for (const field of fields) {
      assert(field in def.properties, `${type}.${field} is in the schema`);
      assert(!(def.required as string[]).includes(field), `${type}.${field} must stay optional`);
    }
  }
});

// ---- The structured-outputs subset ----

const PROVIDER_TYPES = [
  "GenerateResponse",
  "CheckResponse",
  "GradeResponse",
  "ConfusionsResponse",
  "LectureResponse",
  "CardsFromChatResponse",
  "TranscribeImageResponse",
  "SyllabusResponse",
  "ExamMentionResponse",
];
const UNSUPPORTED = [
  "minLength",
  "maxLength",
  "minimum",
  "maximum",
  "maxItems",
  "pattern",
  "uniqueItems",
  "multipleOf",
  "format",
];

function walk(node: unknown, visit: (n: Schema) => void): void {
  if (Array.isArray(node)) node.forEach((n) => walk(n, visit));
  else if (node && typeof node === "object") {
    visit(node as Schema);
    for (const [key, value] of Object.entries(node)) {
      // `properties` and `$defs` map names to schemas: a property may be called "format" without being the keyword.
      if (key === "properties" || key === "$defs") Object.values(value as object).forEach((v) => walk(v, visit));
      else walk(value, visit);
    }
  }
}

Deno.test("structured-output schemas stay inside the subset the API compiles", () => {
  for (const type of PROVIDER_TYPES) {
    const schema = providerSchema(type);
    assertEquals(schema.type, "object", type);
    assert(!("model" in schema.properties), `${type}: the relay sets model itself`);
    let optional = 0;
    let unions = 0;
    walk(schema, (n) => {
      for (const key of UNSUPPORTED) assert(!(key in n), `${type}: ${key} isn't supported`);
      if (Array.isArray(n.type)) throw new Error(`${type}: type arrays count as unions; use anyOf`);
      if (n.anyOf) unions++;
      if (n.minItems !== undefined) assert(n.minItems === 0 || n.minItems === 1, `${type}: minItems`);
      if (n.type === "object") {
        assertEquals(n.additionalProperties, false, `${type}: every object needs additionalProperties: false`);
        optional += Object.keys(n.properties ?? {}).filter((p) => !(n.required ?? []).includes(p)).length;
      }
    });
    assert(optional <= 24, `${type}: ${optional} optional properties (the API allows 24)`);
    assert(unions <= 16, `${type}: ${unions} unions (the API allows 16)`);
    // No recursion: a definition never reaches itself.
    for (const [name, def] of Object.entries(schema.$defs ?? {})) {
      assert(!JSON.stringify(def).includes(`"#/$defs/${name}"`), `${type}: ${name} is recursive`);
    }
  }
});

Deno.test("the provider schema is the contract type without model", () => {
  const contract = contractSchema("GradeResponse");
  const provider = providerSchema("GradeResponse");
  const expected = structuredClone(contract);
  delete expected.properties.model;
  expected.required = expected.required.filter((r: string) => r !== "model");
  assertEquals(provider, expected);
  const reply = JSON.parse(FIXTURES["grade-partial"]);
  delete reply.model;
  assertEquals(validate(provider, reply), []);
});
