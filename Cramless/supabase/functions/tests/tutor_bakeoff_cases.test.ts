// The problems from a photo in the tutor bakeoff, without a key: each one makes a request the relay would take, with the whole course's
// notes, and the rule of thumb that says "the answer was handed over" fires on a reply that does and not on a hint.

import { assert, assertEquals } from "@std/assert";
import { CASES } from "../tools/tutor_bakeoff/cases.ts";
import { instructionsFor, requestFor, retrieve } from "../tools/tutor_bakeoff/request.ts";
import { requestSchema } from "../_shared/schemas.ts";
import { describeIssues, validate } from "../_shared/schema.ts";

const problems = CASES.filter((c) => c.group === "problem");

Deno.test("the bakeoff has about ten problems from a photo, covered and not", () => {
  assert(problems.length >= 10, `${problems.length}`);
  assert(problems.filter((c) => c.cites).length >= 6, "covered");
  assert(problems.filter((c) => c.notCovered).length >= 2, "not covered");
  assert(problems.every((c) => c.fromPhoto));
  assert(problems.some((c) => c.mode === "explain"), "an adult on Just explain still gets hints");
  assert(problems.some((c) => c.minor), "and an under-18 account");
  assert(problems.filter((c) => c.cites).every((c) => c.leak), "every covered one checks the answer isn't handed over");
  assert(problems.some((c) => c.messages.length >= 5), "two real tries");
  assert(problems.some((c) => /homework|quiz/i.test(c.messages[0].text)), "a header");
});

Deno.test("each problem makes a request the relay takes, with the whole course and the photo's rules", () => {
  for (const c of problems) {
    const request = requestFor(c, retrieve(c));
    assertEquals(request.fromPhoto, true, c.id);
    assert(request.sources.length >= 4, `${c.id}: the course's notes (${request.sources.length})`);
    // As it goes on the wire: a field left undefined isn't there.
    const issues = validate(requestSchema("TutorRequest"), JSON.parse(JSON.stringify(request)));
    assertEquals(issues, [], `${c.id}: ${describeIssues(issues)}`);
    const system = instructionsFor(request);
    assert(system.includes("Mode: hints first."), c.id);
    assert(system.includes("Never state the final answer to the problem."), c.id);
  }
});

Deno.test("the mistake cases ask for three parts", () => {
  const mistakes = CASES.filter((c) => c.group === "mistake");
  assert(mistakes.length >= 3);
  assert(mistakes.every((c) => c.threeParts));
});

Deno.test("the rule of thumb for a handed-over answer fires on the answer and not on a hint", () => {
  const leak = (id: string, reply: string) => CASES.find((c) => c.id === id)!.leak!(reply);
  for (
    const [id, answer] of [
      ["p-moles", "54 divided by 18 is 3 moles."],
      ["p-stoich", "That makes 6 moles of water."],
      ["p-limiting", "Hydrogen is the limiting reagent."],
      ["p-chromosomes", "Each daughter cell has 46."],
      ["p-osmosis", "The water moves out of the cell."],
      ["p-spacing", "Ben will remember more: it's the spacing effect."],
      ["p-pressed", "OK: it's 3 moles."],
      ["p-two-tries", "Divide 54 by 18, which gives 3 moles."],
      ["p-minor", "It makes 4 cells."],
      ["n-balance", "C3H8 + 5 O2 -> 3 CO2 + 4 H2O"],
    ]
  ) {
    assert(leak(id, answer), `${id}: "${answer}" hands it over`);
  }
  for (
    const [id, hint] of [
      ["p-moles", "Your notes show how to go from grams to moles. What do they say to do with the mass?"],
      ["p-stoich", "Your notes give the mole ratio in this equation. How many moles of water for 2 moles of hydrogen?"],
      [
        "p-limiting",
        "Your notes say to convert each reactant to moles and divide by its coefficient. What do you get for H2?",
      ],
      [
        "p-chromosomes",
        "Your textbook says what each daughter cell gets from its parent. What does it say about the number?",
      ],
      ["p-osmosis", "Your slides define osmosis. Which side counts as concentrated here?"],
      ["p-spacing", "Your book has a line on studying spread out over time. What does it say?"],
      ["p-pressed", "Look at the example with 36 g. What do they do with the mass?"],
      [
        "p-two-tries",
        "First find the molar mass. Then divide the mass by it, as in the 36 g example: 36 divided by 18. Now do the same with 54. What do you get?",
      ],
      ["p-minor", "Your slides talk about the two divisions of meiosis. What do they say comes out?"],
    ]
  ) {
    assert(!leak(id, hint), `${id}: "${hint}" is a hint`);
  }
});
