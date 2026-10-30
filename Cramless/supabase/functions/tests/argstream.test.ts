// The readers that pull finished cards, questions and a note's body out of a tool call's arguments while they are
// still being written (_shared/argstream.ts): the same result however the text is cut up.

import { assert, assertEquals } from "@std/assert";
import { ArrayItemStream, StringFieldStream } from "../_shared/argstream.ts";

/** A small seeded generator, so a failure repeats. */
function seeded(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function cut(text: string, random: () => number, max: number): string[] {
  const out: string[] = [];
  for (let i = 0; i < text.length;) {
    const n = 1 + Math.floor(random() * max);
    out.push(text.slice(i, i + n));
    i += n;
  }
  return out;
}

const TRICKY = [
  'a "quoted" word',
  "braces { } and [ ] inside a string",
  "back\\slash and a newline\nand a tab\t",
  "emoji 😀 and accents é ü, a CJK 字",
  '"cards": [ not a real key',
  "plain",
];

function cardsJson(random: () => number, count: number): string {
  const cards = Array.from({ length: count }, (_, i) => ({
    front: `${TRICKY[Math.floor(random() * TRICKY.length)]} ${i}`,
    back: TRICKY[Math.floor(random() * TRICKY.length)],
    evidence: random() < 0.3
      ? null
      : { source_id: `s${1 + (i % 3)}`, quote: TRICKY[Math.floor(random() * TRICKY.length)] },
  }));
  return JSON.stringify({ course_id: "c1", topic: TRICKY[Math.floor(random() * TRICKY.length)], cards });
}

Deno.test("ArrayItemStream: every element arrives once, in order, whatever the chunking", () => {
  for (let seed = 1; seed <= 300; seed++) {
    const random = seeded(seed);
    const text = cardsJson(random, Math.floor(random() * 9));
    const expected = JSON.parse(text).cards;
    const reader = new ArrayItemStream("cards");
    const got: unknown[] = [];
    for (const piece of cut(text, random, 1 + Math.floor(random() * 40))) got.push(...reader.push(piece));
    assertEquals(got, expected, `seed ${seed}`);
  }
});

Deno.test("ArrayItemStream: an element is sent when it is whole, not before", () => {
  const text = '{"course_id":"c1","cards":[{"front":"A","back":"B"},{"front":"C","back":"D"}]}';
  const reader = new ArrayItemStream("cards");
  const seen: unknown[][] = [];
  for (const ch of text) seen.push(reader.push(ch));
  const firstAt = seen.findIndex((s) => s.length > 0);
  assertEquals(text.slice(0, firstAt + 1), '{"course_id":"c1","cards":[{"front":"A","back":"B"}');
  assertEquals(seen.flat(), [{ front: "A", back: "B" }, { front: "C", back: "D" }]);
});

Deno.test("ArrayItemStream: the array may follow other properties, and nested arrays do not end an element", () => {
  const text = JSON.stringify({
    topic: "x",
    questions: [
      { type: "multiple_choice", options: ["a", "b", ["c"]], evidence: { quote: "q]}" } },
      { type: "fill_blank", options: null },
    ],
    after: [{ not: "this" }],
  });
  const reader = new ArrayItemStream("questions");
  const got: unknown[] = [];
  for (const piece of cut(text, seeded(7), 5)) got.push(...reader.push(piece));
  assertEquals(got, JSON.parse(text).questions);
});

Deno.test("ArrayItemStream: text that is not what it expects yields nothing and does not throw", () => {
  for (
    const text of [
      '{"cards":["a","b"]}',
      '{"cards":[{"a":1,}]}',
      '{"other":[{"a":1}]}',
      "not json at all",
      "",
      '{"cards":[]}',
    ]
  ) {
    const reader = new ArrayItemStream("cards");
    const got: unknown[] = [];
    for (const piece of cut(text, seeded(3), 4)) got.push(...reader.push(piece));
    assertEquals(got, [], text);
  }
  // A malformed element stops the reader; the complete arguments are what the app acts on.
  const reader = new ArrayItemStream("cards");
  assertEquals(reader.push('{"cards":[{"a":1},{"b":,},{"c":3}]}'), [{ a: 1 }]);
  assertEquals(reader.push('{"c":3}'), []);
  // A long preamble without the key is given up on.
  const long = new ArrayItemStream("cards");
  assertEquals(long.push("x".repeat(5000)), []);
  assertEquals(long.push('"cards":[{"a":1}]'), []);
});

Deno.test("StringFieldStream: a field that is not first arrives decoded, however the text is cut", () => {
  for (let seed = 1; seed <= 300; seed++) {
    const random = seeded(seed + 1000);
    const body = Array.from({ length: Math.floor(random() * 6) }, () => TRICKY[Math.floor(random() * TRICKY.length)])
      .join(
        "\n",
      );
    const text = JSON.stringify({ course_id: "c1", title: TRICKY[Math.floor(random() * TRICKY.length)], body });
    const reader = new StringFieldStream("body");
    let got = "";
    for (const piece of cut(text, random, 1 + Math.floor(random() * 30))) got += reader.push(piece);
    assertEquals(got, body, `seed ${seed}`);
  }
});

Deno.test("StringFieldStream: \\u escapes and surrogate pairs split across chunks wait for their other half", () => {
  const text = '{"body":"caf\\u00e9 \\ud83d\\ude00 done"}';
  const reader = new StringFieldStream("body");
  let got = "";
  const seen: string[] = [];
  for (const ch of text) {
    const piece = reader.push(ch);
    got += piece;
    seen.push(piece);
  }
  assertEquals(got, "café 😀 done");
  assert(seen.every((p) => !/[\ud800-\udbff]$/.test(p)), "a lone half of a pair was never sent");
});

Deno.test("StringFieldStream: a first-field reader refuses an object that starts with something else", () => {
  const reader = new StringFieldStream("answer", true);
  assertEquals(reader.push('{"citations":[],"answer":"late"}'), "");
  const ok = new StringFieldStream("answer", true);
  assertEquals(ok.push('{"answer":"hi'), "hi");
  assertEquals(ok.push(' there","citations":[]}'), " there");
});
