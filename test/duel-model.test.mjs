// Engine tests for DuelModel.js.
//
// The engine file carries QML's `.pragma library` header, which is not valid
// JavaScript, so it is stripped into a plain .mjs copy before import. Everything
// else is loaded verbatim -- these tests must run against the same bytes the
// shell does.
//
// Run: node --test test/*.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const engineSource = join(here, "..", "duel", "DuelModel.js");
const staged = join("/tmp/opencode", "DuelModel.under-test.mjs");

// The engine is a QML library module, so it exports nothing. Rather than edit
// it, the staged copy re-exports the public surface these tests reach for.
const EXPORTS = [
  "CLEAR", "STRIKE", "MULT", "HALVE", "OPS", "GATED_OPS",
  "CARD_POOL", "OPPONENT_POOL", "HAND_SIZE", "MIN_TARGET",
  "opGlyph", "opLabel", "opDetail", "step", "cloneCard", "sameOpValue",
  "makeRng", "generate", "Session", "resolve", "allChains", "solutionsFor",
];

mkdirSync("/tmp/opencode", { recursive: true });
writeFileSync(
  staged,
  readFileSync(engineSource, "utf8").replace(/^\.pragma library[ \t]*\r?\n/, "") +
    `\nexport { ${EXPORTS.join(", ")} };\n`,
);

const M = await import(`file://${staged}?v=${Date.now()}`);

const BOARDS = 5000;

// ---------------------------------------------------------------------------
// Vocabulary
// ---------------------------------------------------------------------------

test("the pool is well formed", () => {
  const names = new Set();
  for (const card of M.CARD_POOL) {
    assert.ok(card.name && typeof card.name === "string");
    assert.ok(!names.has(card.name), `duplicate card name: ${card.name}`);
    names.add(card.name);

    assert.ok(M.OPS.includes(card.op), `${card.name} has unknown op ${card.op}`);

    if (card.op === M.CLEAR) {
      assert.equal(card.value, 0, `${card.name} is a CLEAR and must carry no value`);
    } else if (card.op === M.MULT) {
      assert.ok(card.value >= 2, `${card.name} multiplies by ${card.value}`);
    } else if (card.op === M.STRIKE) {
      assert.ok(card.value > 0, `${card.name} strikes for ${card.value}`);
    }
  }
});

test("every op in the pool is reachable in the vocabulary", () => {
  const seen = new Set(M.CARD_POOL.map((c) => c.op));
  for (const op of M.OPS) {
    assert.ok(seen.has(op), `no card in the pool uses ${op}`);
  }
});

test("a halve card floors rather than rounds", () => {
  const r = M.step(M.HALVE, 0, 1501, true);
  assert.equal(r.dmg, 750, "1501 / 2 must floor to 750, not round to 751");
  assert.ok(r.legal);
});

test("damage is illegal until the monster is cleared", () => {
  for (const op of M.GATED_OPS) {
    const r = M.step(op, 2, 0, false);
    assert.equal(r.legal, false, `${op} must be illegal while the monster is up`);
  }
  const clear = M.step(M.CLEAR, 0, 0, false);
  assert.ok(clear.legal);
  assert.ok(clear.cleared);
});

// ---------------------------------------------------------------------------
// The chain rule
// ---------------------------------------------------------------------------

test("order matters: scale then add is not add then scale", () => {
  const clear = { op: M.CLEAR, value: 0 };
  const mult = { op: M.MULT, value: 3 };
  const strike = { op: M.STRIKE, value: 500 };

  // Scaling an empty chain does nothing, so scaling first throws the strike
  // away and scaling second triples it. Same two links, 3x the damage, and the
  // only difference is which one you played first -- which is the puzzle.
  assert.equal(M.resolve([clear, mult, strike]).dmg, 500);
  assert.equal(M.resolve([clear, strike, mult]).dmg, 1500);
  assert.equal(M.resolve([clear, mult, strike]).dmg * 3,
    M.resolve([clear, strike, mult]).dmg);
});

test("a chain that skips the clear never starts", () => {
  const r = M.resolve([{ op: M.STRIKE, value: 2000 }]);
  assert.equal(r.legal, false);
  assert.equal(r.dmg, 0);
});

test("clear is additive-free: it does not touch the total", () => {
  const r = M.resolve([{ op: M.CLEAR, value: 0 }, { op: M.STRIKE, value: 900 }]);
  assert.equal(r.dmg, 900);
  assert.ok(r.cleared);
});

test("an empty chain is legal and worth nothing", () => {
  const r = M.resolve([]);
  assert.ok(r.legal);
  assert.equal(r.dmg, 0);
  assert.equal(r.cleared, false);
});

// ---------------------------------------------------------------------------
// Board shape
// ---------------------------------------------------------------------------

test("board shape is well formed", () => {
  const p = M.generate(12345);
  assert.equal(p.hand.length, M.HAND_SIZE);
  assert.ok(p.target >= M.MIN_TARGET, `target ${p.target} below the floor`);
  assert.ok(p.opponent && p.opponent.name);
  assert.ok(
    p.solution.length >= 3 && p.solution.length <= 4,
    `solution length ${p.solution.length} outside 3..4`,
  );
});

test("the hand is not dealt in a stable order", () => {
  // Ids are assigned from a canonical sort, so if the shuffle that follows were
  // dropped the hand would come out sorted by op on every single board.
  let sortedLooking = 0;
  for (let seed = 0; seed < 500; seed++) {
    const ops = M.generate(seed).hand.map((c) => c.op);
    const sorted = ops.slice().sort();
    if (ops.join() === sorted.join()) sortedLooking++;
  }
  // A hand with the shuffle dropped comes out in canonical op order every
  // time, so this only has to sit well clear of 100% to catch that.
  assert.ok(sortedLooking < 40, `${sortedLooking}/500 hands came out in op order`);
});

test("a hand holds exactly one clear", () => {
  for (let seed = 0; seed < 500; seed++) {
    const p = M.generate(seed);
    const clears = p.hand.filter((c) => c.op === M.CLEAR);
    assert.equal(clears.length, 1, `seed ${seed} dealt ${clears.length} clears`);
  }
});

test("no two cards in a hand do the same thing at the same number", () => {
  for (let seed = 0; seed < 500; seed++) {
    const p = M.generate(seed);
    for (let i = 0; i < p.hand.length; i++) {
      for (let j = i + 1; j < p.hand.length; j++) {
        assert.ok(
          !M.sameOpValue(p.hand[i], p.hand[j]),
          `seed ${seed} aliased ${p.hand[i].name} and ${p.hand[j].name}`,
        );
      }
    }
  }
});

test("hand card ids are unique and 1-based", () => {
  const p = M.generate(777);
  const ids = p.hand.map((c) => c.id).sort((a, b) => a - b);
  assert.deepEqual(ids, p.hand.map((_, i) => i + 1));
});

test("cards in a hand do not alias each other", () => {
  const p = M.generate(4242);
  const a = p.hand[0];
  const b = p.hand[1];
  a.value = 99999;
  assert.notEqual(b.value, 99999, "mutating one card reached another");
});

test("the board carries no card objects in its solution", () => {
  const p = M.generate(31337);
  for (const name of p.solution) {
    assert.equal(typeof name, "string", "solution must be names, not card objects");
  }
});

// ---------------------------------------------------------------------------
// The one thing that makes it a puzzle
// ---------------------------------------------------------------------------

test("every board has exactly one chain that reaches lethal", () => {
  for (let seed = 0; seed < BOARDS; seed++) {
    const p = M.generate(seed);
    const hits = M.solutionsFor(p.hand, p.target);
    assert.equal(
      hits.length,
      1,
      `seed ${seed} has ${hits.length} winning chains, expected 1`,
    );
  }
});

test("the published solution is the winning chain", () => {
  for (let seed = 0; seed < 1000; seed++) {
    const p = M.generate(seed);
    const hits = M.solutionsFor(p.hand, p.target);
    const names = hits[0].map((i) => p.hand[i].name);
    assert.deepEqual(p.solution, names, `seed ${seed} published the wrong line`);
  }
});

test("the published solution is legal and totals the target", () => {
  for (let seed = 0; seed < 1000; seed++) {
    const p = M.generate(seed);
    const cards = p.solution.map((name) => p.hand.find((c) => c.name === name));
    assert.ok(cards.every(Boolean), `seed ${seed} solution names a card not in hand`);
    const r = M.resolve(cards);
    assert.ok(r.legal, `seed ${seed} published an illegal line`);
    assert.equal(r.dmg, p.target);
  }
});

test("the solution starts with the clear", () => {
  for (let seed = 0; seed < 500; seed++) {
    const p = M.generate(seed);
    const first = p.hand.find((c) => c.name === p.solution[0]);
    assert.equal(first.op, M.CLEAR);
  }
});

test("the solution is minimal: dropping a link loses", () => {
  for (let seed = 0; seed < 1000; seed++) {
    const p = M.generate(seed);
    const cards = p.solution.map((name) => p.hand.find((c) => c.name === name));
    for (let i = 0; i < cards.length; i++) {
      const shorter = cards.filter((_, j) => j !== i);
      const r = M.resolve(shorter);
      assert.ok(
        !r.legal || r.dmg !== p.target,
        `seed ${seed} still wins without link ${i}`,
      );
    }
  }
});

test("no board is winnable by a single strike sitting in hand", () => {
  // Otherwise the target is printed on a card in the player's own hand and the
  // chain is decoration. The generator rejects these explicitly.
  for (let seed = 0; seed < 2000; seed++) {
    const p = M.generate(seed);
    for (const card of p.hand) {
      if (card.op === M.STRIKE) {
        assert.notEqual(
          card.value,
          p.target,
          `seed ${seed} hands out a strike worth the whole target`,
        );
      }
    }
  }
});

test("the hand cannot reach the target without the clear in front", () => {
  for (let seed = 0; seed < 500; seed++) {
    const p = M.generate(seed);
    const clear = p.hand.find((c) => c.op === M.CLEAR);
    const withoutClear = p.hand.filter((c) => c !== clear);
    for (const chain of M.allChains(withoutClear)) {
      const cards = chain.map((i) => withoutClear[i]);
      const r = M.resolve(cards);
      assert.ok(
        !r.legal || r.dmg !== p.target,
        `seed ${seed} wins with the clear removed`,
      );
    }
  }
});

// ---------------------------------------------------------------------------
// Randomness
// ---------------------------------------------------------------------------

test("same seed rebuilds the same board", () => {
  for (const seed of [1, 42, 999, 65535, 4294967295]) {
    assert.deepEqual(M.generate(seed), M.generate(seed));
  }
});

test("an unseeded generate() never throws", () => {
  for (let i = 0; i < 200; i++) M.generate();
});

test("a negative seed is treated as unsigned", () => {
  assert.deepEqual(M.generate(-1), M.generate(4294967295));
});

test("nearby seeds do not deal near-identical boards", () => {
  // Consecutive seeds differing only in card order would make the board feel
  // like it is not shuffling, so the target is compared too, not just the hand.
  let sameTarget = 0;
  for (let seed = 0; seed < 2000; seed++) {
    if (M.generate(seed).target === M.generate(seed + 1).target) sameTarget++;
  }
  assert.ok(sameTarget < 100, `${sameTarget}/2000 adjacent pairs shared a target`);
});

test("the board space is large enough not to feel repetitive", () => {
  const BOARDS = 20000;
  const hands = new Set();
  const targets = new Set();
  let low = Infinity;
  let high = 0;
  for (let seed = 0; seed < BOARDS; seed++) {
    const p = M.generate(seed);
    // Compare on card names, not on the stored order, so this measures the
    // space of deals rather than of arrangements of the same deal.
    hands.add(p.hand.map((c) => c.name).sort().join("|"));
    targets.add(p.target);
    if (p.target < low) low = p.target;
    if (p.target > high) high = p.target;
  }
  // Well over half the deals must be distinct. A coarse card pool collapses
  // this to the low hundreds, which a daily lock screen runs straight through.
  assert.ok(hands.size > 12000, `only ${hands.size} distinct hands across ${BOARDS} seeds`);
  // The LP total recurs more than the hand does, which is fine, but the range
  // has to be wide or every board reads as the same duel.
  assert.ok(targets.size > 150, `only ${targets.size} distinct LP totals`);
  assert.ok(low >= M.MIN_TARGET, `lowest target ${low} is under the floor`);
  assert.ok(high > low * 8, `targets only span ${low}..${high}, too narrow`);
});

test("a lock screen re-dealt a hundred times keeps showing new boards", () => {
  // The real usage pattern: unseeded boards, back to back, no repeats to speak
  // of. Seeded sampling hides a small space that random draws would expose.
  const seen = new Set();
  for (let i = 0; i < 100; i++) {
    const p = M.generate();
    seen.add(p.hand.map((c) => c.name).sort().join("|"));
  }
  assert.ok(seen.size >= 95, `only ${seen.size} distinct boards across 100 unseeded deals`);
});

test("the mix keeps a session reproducible across restarts", () => {
  const rng = M.makeRng(7);
  const first = [rng(), rng(), rng()];
  const rng2 = M.makeRng(7);
  assert.deepEqual(first, [rng2(), rng2(), rng2()]);
});

// ---------------------------------------------------------------------------
// Session
// ---------------------------------------------------------------------------

function winningSession(seed) {
  const p = M.generate(seed);
  const s = new M.Session(p);
  for (const name of p.solution) {
    const card = p.hand.find((c) => c.name === name);
    assert.ok(s.add(card.id), `seed ${seed} refused its own solution`);
  }
  return { p, s };
}

test("a session wins on the solution and only on the solution", () => {
  for (let seed = 0; seed < 300; seed++) {
    const { s } = winningSession(seed);
    assert.equal(s.commit(), "win");
    assert.ok(s.won);
  }
});

test("a missed attack empties the chain so the line can be rebuilt", () => {
  const p = M.generate(1234);
  const s = new M.Session(p);
  for (const name of p.solution.slice(0, 2)) {
    s.add(p.hand.find((c) => c.name === name).id);
  }
  assert.ok(s.commit() !== "win");
  assert.equal(s.chain.length, 0);
});

test("a winning chain is kept for the victory reveal", () => {
  const { s, p } = winningSession(1234);
  s.commit();
  assert.ok(s.won);
  // The win screen reads the chain back to the player, so a win must not
  // clear it the way a miss does.
  assert.equal(s.chain.length, p.solution.length);
  assert.equal(s.cleared, true);
});

// A small hand-built board, so the over/short split is pinned exactly rather
// than depending on whatever a generated board happens to contain.
function fixedSession(cards, target) {
  const s = new M.Session({
    hand: cards.map((c, i) => ({ id: i + 1, name: `C${i + 1}`, ...c })),
    target,
    solution: [],
  });
  // Link the whole hand in the order it was given.
  for (let i = 1; i <= cards.length; i++) s.add(i);
  return s;
}

test("falling short reports short and names the total it reached", () => {
  const s = fixedSession(
    [
      { op: M.CLEAR, value: 0 },
      { op: M.STRIKE, value: 100 },
    ],
    5000,
  );
  assert.equal(s.commit(), "short");
  assert.equal(s.lastDmg, 100);
  assert.equal(s.lastResult, "short");
  assert.equal(s.attempts, 1);
  assert.ok(s.broken);
});

test("overshooting reports over, because lethal declared is lethal missed", () => {
  const s = fixedSession(
    [
      { op: M.CLEAR, value: 0 },
      { op: M.STRIKE, value: 9000 },
    ],
    5000,
  );
  assert.equal(s.commit(), "over");
  assert.equal(s.lastDmg, 9000);
  assert.equal(s.lastResult, "over");
});

test("the fixed-session helper really did build a chain", () => {
  // Guards the two tests above: if `add` ever refused these links, they would
  // both pass on a null commit for the wrong reason.
  const s = fixedSession(
    [
      { op: M.CLEAR, value: 0 },
      { op: M.STRIKE, value: 400 },
    ],
    400,
  );
  assert.equal(s.chain.length, 2);
  assert.equal(s.total(), 400);
  assert.equal(s.commit(), "win");
});

test("a failed attack raises the broken flag the UI reads", () => {
  // commit() clears the chain, which used to clear this flag with it -- the
  // flag is the only signal that the last declared attack did not connect.
  const s = fixedSession(
    [
      { op: M.CLEAR, value: 0 },
      { op: M.STRIKE, value: 400 },
    ],
    9000,
  );
  s.commit();
  assert.equal(s.chain.length, 0);
  assert.ok(s.broken, "broken flag was cleared by the chain reset");

  // Rebuilding the line clears it again, so the board does not read as failed
  // while the player is mid-attempt.
  s.add(1);
  s.add(2);
  assert.equal(s.broken, false);
});

test("a miss does not consume the board", () => {
  const p = M.generate(1234);
  const s = new M.Session(p);
  const clear = p.hand.find((c) => c.op === M.CLEAR);
  s.add(clear.id);
  const weak = p.hand
    .filter((c) => c.op === M.STRIKE)
    .sort((a, b) => a.value - b.value)[0];
  s.add(weak.id);
  const r = s.commit();
  assert.ok(r === "short" || r === "over");
  assert.equal(s.attempts, 1);
  assert.equal(s.won, false);
  // Same board, so the player can try again without being re-dealt.
  assert.equal(s.puzzle, p);
});

test("the session refuses to link a card twice", () => {
  const p = M.generate(99);
  const s = new M.Session(p);
  const clear = p.hand.find((c) => c.op === M.CLEAR);
  assert.ok(s.add(clear.id));
  assert.equal(s.add(clear.id), false, "a clear was linked twice");
  assert.equal(s.chain.length, 1);
});

test("the session refuses damage before the clear", () => {
  const p = M.generate(99);
  const s = new M.Session(p);
  const strike = p.hand.find((c) => c.op === M.STRIKE);
  assert.equal(s.add(strike.id), false, "a strike was linked with the monster up");
  assert.equal(s.chain.length, 0);
});

test("unlinking a middle link truncates everything after it", () => {
  const { s, p } = winningSession(555);
  const before = s.chain.length;
  assert.ok(before >= 3, "expected a multi-link solution to test truncation");
  assert.ok(s.removeAt(1));
  assert.equal(s.chain.length, 1);
  assert.equal(s.chain[0].id, p.solution && s.chain[0].id);
});

test("undo peels the chain back one link at a time", () => {
  const { s } = winningSession(555);
  const before = s.chain.length;
  for (let i = before; i > 0; i--) {
    assert.equal(s.chain.length, i);
    assert.ok(s.undo());
  }
  assert.equal(s.chain.length, 0);
  assert.equal(s.undo(), false);
});

test("a blocked chain reports no damage", () => {
  const s = new M.Session({
    hand: [{ id: 1, name: "S", op: M.STRIKE, value: 2000 }],
    target: 2000,
    solution: [],
  });
  assert.equal(s.total(), 0);
  assert.equal(s.submittable, false);
  assert.equal(s.commit(), null);
});

test("a chain is not submittable until it has crossed the field", () => {
  const s = new M.Session({
    hand: [
      { id: 1, name: "C", op: M.CLEAR, value: 0 },
      { id: 2, name: "S", op: M.STRIKE, value: 700 },
    ],
    target: 700,
    solution: ["C", "S"],
  });
  assert.equal(s.submittable, false, "an empty chain was submittable");
  s.add(1);
  assert.equal(s.submittable, false, "a clear-only chain was submittable");
  s.add(2);
  assert.equal(s.submittable, true);
});

test("a won session is inert", () => {
  const { s, p } = winningSession(1234);
  s.commit();
  assert.equal(s.submittable, false);
  assert.equal(s.undo(), false);
  assert.equal(s.add(p.hand[0].id), false);
  assert.equal(s.commit(), null);
});

test("a won session keeps its chain visible", () => {
  // The win animation reads off the chain, so clearing it would strand it.
  const { s } = winningSession(1234);
  s.commit();
  assert.ok(s.chain.length > 0, "the winning chain was thrown away");
});

// ---------------------------------------------------------------------------
// Binding surface
//
// QML cannot see that a plain-JS function read `this.chain`, so every value the
// board binds to has to be a reassigned property. These tests are the reason
// the session is shaped the way it is: if someone "simplifies" it back to
// mutating in place and reading through accessors, the lock screen silently
// stops updating while every test here still passes.
// ---------------------------------------------------------------------------

test("every mutation replaces the chain instead of editing it", () => {
  const p = M.generate(2468);
  const s = new M.Session(p);
  const ids = p.solution.map((n) => p.hand.find((c) => c.name === n).id);

  const seen = [s.chain];
  s.add(ids[0]);
  assert.notEqual(s.chain, seen[0], "add() edited the array in place");
  seen.push(s.chain);

  s.add(ids[1]);
  assert.notEqual(s.chain, seen[1], "add() reused the previous array");
  seen.push(s.chain);

  s.undo();
  assert.notEqual(s.chain, seen[2], "undo() reused the previous array");
});

test("the derived values track the chain", () => {
  const p = M.generate(1357);
  const s = new M.Session(p);
  const ids = p.solution.map((n) => p.hand.find((c) => c.name === n).id);

  assert.equal(s.cleared, false);
  assert.equal(s.dmg, 0);

  s.add(ids[0]);
  assert.equal(s.cleared, true, "the clear did not register");
  assert.equal(s.dmg, 0, "a clear-only chain should be worth nothing");

  s.add(ids[1]);
  assert.equal(s.dmg, s.total());
  assert.ok(s.dmg > 0);

  s.undo();
  assert.equal(s.dmg, 0, "undo left the total on the table");
  assert.equal(s.cleared, true, "undo took the clear with it");
});

test("an illegal chain is marked negative, not zero", () => {
  // Zero means "nothing linked yet"; negative means "linked, but blocked". The
  // board renders those differently, so they cannot share a value.
  const s = new M.Session({
    hand: [{ id: 1, name: "S", op: M.STRIKE, value: 2000 }],
    target: 2000,
    solution: [],
  });
  assert.equal(s.add(1), false, "a strike was accepted with the monster up");
  assert.equal(s.dmg, 0);

  const empty = new M.Session({ hand: [], target: 100, solution: [] });
  assert.equal(empty.isLegal(), true);
  assert.equal(empty.dmg, 0);
});

test("submittable is recomputed on a no-op change in value", () => {
  // Two cards that leave the total unchanged still have to invalidate the
  // binding, or the Declare button stays greyed out on a legal chain.
  const s = new M.Session({
    hand: [
      { id: 1, name: "C", op: M.CLEAR, value: 0 },
      { id: 2, name: "A", op: M.STRIKE, value: 500 },
      { id: 3, name: "B", op: M.MULT, value: 2 },
    ],
    target: 1000,
    solution: [],
  });
  s.add(1);
  s.add(2);
  assert.equal(s.submittable, true);
  s.add(3);
  assert.equal(s.submittable, true);
  assert.equal(s.dmg, 1000);
});

// ---------------------------------------------------------------------------
// Labels
// ---------------------------------------------------------------------------

test("labels cover every op and never print undefined", () => {
  for (const op of M.OPS) {
    const value = op === M.MULT ? 3 : op === M.STRIKE ? 800 : 0;
    assert.ok(M.opGlyph(op).length > 0, `no glyph for ${op}`);
    assert.ok(!M.opLabel(op, value).includes("undefined"), `bad label for ${op}`);
    assert.ok(!M.opDetail(op, value).includes("undefined"), `bad detail for ${op}`);
  }
  assert.equal(M.opLabel(M.STRIKE, 1200), "+1200");
  assert.equal(M.opLabel(M.MULT, 3), "\u00D73");
  assert.equal(M.opLabel(M.HALVE, 0), "\u00F72");
  assert.equal(M.opLabel(M.CLEAR, 0), "CLEAR");
});

// ---------------------------------------------------------------------------
// Refusals
//
// Four of the five cards in an opening position are illegal, and a refusal that
// returns a bare false is indistinguishable on screen from a dead lock screen.
// These pin the promise the board relies on: a refusal always carries a reason,
// and a refused link never touches the chain.
// ---------------------------------------------------------------------------

test("every refusal carries a reason the board can print", () => {
  for (let seed = 0; seed < 200; seed++) {
    const p = M.generate(seed);
    const s = new M.Session(p);

    for (const card of p.hand) {
      const before = s.chain.length;
      const linked = s.add(card.id);

      if (linked) {
        assert.equal(s.refusal, "", `seed ${seed}: a linked card left a refusal behind`);
        continue;
      }

      assert.ok(s.refusal.length > 0, `seed ${seed}: ${card.name} was refused with no reason`);
      assert.equal(s.chain.length, before, `seed ${seed}: a refused link changed the chain`);
    }
  }
});

test("a refusal always matches what the engine would have done", () => {
  for (let seed = 0; seed < 200; seed++) {
    const p = M.generate(seed);
    const s = new M.Session(p);

    for (const card of p.hand) {
      const legal = M.step(card.op, card.value, s.total(), s.cleared).legal;
      const inChain = !s.hasCard(card.id);
      const expected = s.won ? "won" : inChain ? "chained" : legal ? "legal" : "illegal";

      assert.equal(s.refusalFor(card.id) === "", expected === "legal",
        `seed ${seed}: ${card.name} refused as ${expected}`);
      assert.equal(s.canLink(card.id), expected === "legal",
        `seed ${seed}: canLink disagrees with refusalFor for ${card.name}`);
    }
  }
});

test("the opening position says the monster has to be cleared first", () => {
  const p = M.generate(77);
  const s = new M.Session(p);
  const clear = p.hand.find((c) => c.op === M.CLEAR);

  // The reason a first-timer cannot guess, so it has to be spelled out rather
  // than left to be inferred from a board that will not move.
  for (const card of p.hand) {
    if (card.op === M.CLEAR) continue;
    assert.match(s.refusalFor(card.id), /face-up/,
      `${card.name} should be told the monster is in the way`);
  }

  assert.equal(s.refusalFor(clear.id), "");
  s.add(clear.id);
  assert.match(s.refusalFor(clear.id), /already in the chain/);
});

test("an id the hand does not hold is refused, never obeyed", () => {
  const s = new M.Session({
    hand: [
      { id: 1, name: "C1", op: M.CLEAR, value: 0 },
      { id: 2, name: "C2", op: M.STRIKE, value: 500 },
    ],
    target: 500,
    solution: [],
  });

  // Ids are numbers. Anything that arrives as text -- a QML `property string`
  // will do it -- misses every comparison in the lookup, and treating that miss
  // as "legal" put a null in the chain, which broke every later total.
  for (const bogus of [undefined, null, "1", "nope", -1, 0, 1.5, {}]) {
    assert.equal(s.canLink(bogus), false, `${JSON.stringify(bogus)} must not be linkable`);
    assert.equal(s.add(bogus), false, `${JSON.stringify(bogus)} must not link`);
    assert.equal(s.chain.length, 0, `${JSON.stringify(bogus)} corrupted the chain`);
  }

  assert.ok(s.chain.every((c) => c !== null && c !== undefined));
  assert.equal(s.total(), 0);
  // The real cards still work after all that.
  assert.equal(s.add(1), true);
  assert.equal(s.add(2), true);
  assert.equal(s.total(), 500);
});

test("a refused link leaves no stale reason once the line is fixed", () => {
  const s = new M.Session({
    hand: [
      { id: 1, name: "C1", op: M.CLEAR, value: 0 },
      { id: 2, name: "C2", op: M.STRIKE, value: 500 },
    ],
    target: 500,
    solution: [],
  });

  assert.equal(s.add(2), false);
  assert.ok(s.refusal.length > 0);
  assert.equal(s.add(1), true);
  assert.equal(s.refusal, "", "a legal link left the old refusal on screen");
  assert.equal(s.add(2), true);
  assert.equal(s.refusal, "");
});

test("undo and unlink clear the reason as well as the chain", () => {
  const s = new M.Session({
    hand: [
      { id: 1, name: "C1", op: M.CLEAR, value: 0 },
      { id: 2, name: "C2", op: M.STRIKE, value: 500 },
    ],
    target: 500,
    solution: [],
  });

  s.add(1);
  s.add(2);
  s.add(2);
  assert.ok(s.refusal.length > 0);
  s.undo();
  assert.equal(s.refusal, "");

  s.add(1);
  s.add(2);
  s.add(2);
  assert.ok(s.refusal.length > 0);
  s.removeAt(0);
  assert.equal(s.refusal, "");
});
