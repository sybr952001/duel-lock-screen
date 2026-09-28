.pragma library

// Duel-puzzle engine for the lock screen.
//
// A duel puzzle is a pre-set board you have to win inside a single turn. The
// opponent sits on an awkward amount of LP with a monster face-up, you get a
// fixed hand and no deck to draw from, and there is exactly one way to cross
// the field and leave them on zero. Any other line fizzles, falls short, or
// overshoots -- and overshooting loses, because the attack was declared for
// lethal and the board was already clear of blockers.
//
// Here the whole puzzle is the chain. You link cards in order and the chain's
// running total is your damage. Damaging links are illegal while the monster
// is up, so the CLEAR has to come first or the chain never starts. When you
// commit, the chain either totals the opponent's exact LP or it does not.
//
// Because the opponent's LP is derived from the solution rather than chosen
// first, the "one way to win" property is structural. The generator still
// re-derives it by walking every chain the hand can form, because a hand can
// reach the same number two different ways (1000 * 2, or 500 * 2 * 1-then-...)
// and a puzzle with two answers is the one failure mode that reads as broken.
//
// Pure logic, no QML types, so the whole thing is unit testable outside the
// shell (see test/duel-model.test.mjs).

// ---------------------------------------------------------------------------
// Card ops
//
// CLEAR is the only card that touches `cleared`; every damaging op is illegal
// before it. The single rule is what makes the monster load-bearing without
// needing a combat simulator.
// ---------------------------------------------------------------------------

var CLEAR  = "clear";
var STRIKE = "strike";
var MULT   = "mult";
var HALVE  = "halve";

var OPS = [CLEAR, STRIKE, MULT, HALVE];

// Ops that are illegal while the opponent's monster is still face-up.
var GATED_OPS = [STRIKE, MULT, HALVE];

// ---------------------------------------------------------------------------
// Card pool
//
// Names are invented rather than lifted from real cards, but they follow the
// genre's grammar: a monster, a spell that answers a monster, a quick-play
// that scales a number, a drain that cuts one in half.
// ---------------------------------------------------------------------------

var CARD_POOL = [
  // CLEAR -- the only way past the face-up monster. Several names so the hand
  // does not read as "the one clear plus four numbers" every single board.
  { name: "Solar Eclipse",    op: CLEAR,  value: 0 },
  { name: "Null Field",       op: CLEAR,  value: 0 },
  { name: "Void Sweep",       op: CLEAR,  value: 0 },
  { name: "Iron Purge",       op: CLEAR,  value: 0 },
  { name: "Gravity Collapse", op: CLEAR,  value: 0 },
  { name: "Blackout",         op: CLEAR,  value: 0 },
  { name: "Starless Sky",     op: CLEAR,  value: 0 },
  { name: "Horizon Break",    op: CLEAR,  value: 0 },

  // STRIKE -- raw damage. A strike is never wrong, only ever the wrong number
  // or in the wrong place, which is what makes the hand full of near-misses.
  //
  // The values run in fine steps on purpose. A coarse ladder (400 / 800 / 1600)
  // gives the pool a handful of distinct op+value pairs, and since a hand may
  // not repeat one, that collapses the board space to a few hundred hands --
  // which a lock screen you unlock every day runs straight through.
  { name: "Gale Rend",      op: STRIKE, value: 300 },
  { name: "Ember Slash",    op: STRIKE, value: 400 },
  { name: "Iron Talon",     op: STRIKE, value: 500 },
  { name: "Stone Breaker",  op: STRIKE, value: 600 },
  { name: "Steel Fang",     op: STRIKE, value: 700 },
  { name: "Tidal Crash",    op: STRIKE, value: 800 },
  { name: "Cataclysm Claw", op: STRIKE, value: 900 },
  { name: "Rift Fang",      op: STRIKE, value: 1000 },
  { name: "Sundering Roar", op: STRIKE, value: 1100 },
  { name: "Pyre Rend",      op: STRIKE, value: 1200 },
  { name: "Obsidian Talon", op: STRIKE, value: 1300 },
  { name: "Glacier Breaker", op: STRIKE, value: 1400 },
  { name: "Thunder Cradle", op: STRIKE, value: 1500 },
  { name: "Wyrm's Verdict", op: STRIKE, value: 1600 },
  { name: "Eclipse Fang",   op: STRIKE, value: 1800 },
  { name: "Annihilation",   op: STRIKE, value: 2000 },
  { name: "Worldbreaker",   op: STRIKE, value: 2400 },

  // MULT -- scales the running total, so where it sits in the chain decides
  // whether it doubles a strike or doubles an already-doubled pair.
  { name: "Twin Fang",     op: MULT, value: 2 },
  { name: "Trident Rise",   op: MULT, value: 3 },
  { name: "Quadra Fang",    op: MULT, value: 4 },
  { name: "Pentacle Seal",  op: MULT, value: 5 },
  { name: "Septuple Seal",  op: MULT, value: 7 },

  // HALVE -- floors, and the floor is the whole reason the arithmetic is not
  // solvable by eye in one pass. Two names, but a hand may only hold one halve
  // (they are the same op at the same value), so this is variety, not depth.
  { name: "Blood Drain",  op: HALVE, value: 0 },
  { name: "Siphon Field", op: HALVE, value: 0 }
];

// ---------------------------------------------------------------------------
// Opponents
//
// `atk` is never printed. A number next to the monster would read as
// arithmetic the chain is supposed to account for, and it is not: the monster
// is a wall, not a damage source. LP is the only number that means anything.
// ---------------------------------------------------------------------------

var OPPONENT_POOL = [
  { name: "Ironclad Knight",   atk: 1900 },
  { name: "Granite Sentinel",  atk: 2100 },
  { name: "Hollow Colossus",   atk: 2600 },
  { name: "Solar Seraph",      atk: 2200 },
  { name: "Ember Construct",   atk: 2500 },
  { name: "Weeping Colossus",  atk: 2300 },
  { name: "Fractured Titan",   atk: 2450 },
  { name: "Sandglass Choir",   atk: 1650 },
  { name: "Crown of Greed",    atk: 2000 },
  { name: "Tempest Herald",    atk: 2050 }
];

// A hand is this wide. Five keeps the chain space around 300 sequences, which
// is small enough to reason about backwards from the LP and far too large to
// brute force by clicking.
var HAND_SIZE = 5;

// Solutions run three to four links. Two links is CLEAR plus a single strike,
// which is not a puzzle -- the target is then literally the number printed on a
// card in your own hand. Three is the shortest line that still forces an
// ordering decision; four needs a real one.
var MIN_LINKS = 3;
var MAX_LINKS = 4;

// Below this the target is reachable by staring at the hand, because a strike
// that lands it outright is sitting right there.
var MIN_TARGET = 1000;

// ---------------------------------------------------------------------------
// Labels
// ---------------------------------------------------------------------------

function opGlyph(op) {
  if (op === CLEAR) return "\u25CE";
  if (op === STRIKE) return "\u2694";
  if (op === MULT) return "\u00D7";
  if (op === HALVE) return "\u00F7";
  return "?";
}

function opLabel(op, value) {
  if (op === CLEAR) return "CLEAR";
  if (op === STRIKE) return "+" + value;
  if (op === MULT) return "\u00D7" + value;
  if (op === HALVE) return "\u00F72";
  return String(op || "").toUpperCase();
}

// One-line description of what a card does, for the card face.
function opDetail(op, value) {
  if (op === CLEAR) return "Banish the face-up monster";
  if (op === STRIKE) return "Deal " + value;
  if (op === MULT) return "Multiply the chain by " + value;
  if (op === HALVE) return "Halve the chain, rounded down";
  return "";
}

// ---------------------------------------------------------------------------
// The rule
// ---------------------------------------------------------------------------

// The single implementation of "what does this link do". The generator, the
// solver walk, and the session all go through it, because the puzzle falls
// apart the moment legality and arithmetic can disagree.
function step(op, value, dmg, cleared) {
  if (op === CLEAR) return { dmg: dmg, cleared: true, legal: true };
  if (GATED_OPS.indexOf(op) === -1) return { dmg: dmg, cleared: cleared, legal: true };
  if (!cleared) return { dmg: dmg, cleared: cleared, legal: false };
  if (op === STRIKE) return { dmg: dmg + value, cleared: cleared, legal: true };
  if (op === MULT) return { dmg: dmg * value, cleared: cleared, legal: true };
  if (op === HALVE) return { dmg: Math.floor(dmg / 2), cleared: cleared, legal: true };
  return { dmg: dmg, cleared: cleared, legal: false };
}

// Hands get their own card objects. Sharing the pool's objects let a session
// scribble state onto a pool entry, and the next board dealt would inherit it.
function cloneCard(card) {
  return { name: card.name, op: card.op, value: card.value };
}

// Cards are identified by name, so the uniqueness walk can compare chains by
// name without depending on the id assignment order.
function sameOpValue(a, b) {
  return a.op === b.op && a.value === b.value;
}

function poolFor(op) {
  return CARD_POOL.filter(function (c) { return c.op === op; });
}

// ---------------------------------------------------------------------------
// Random
// ---------------------------------------------------------------------------

// Deterministic LCG so a seed always rebuilds the same board. Without it a
// board could not be reproduced after a lock/unlock cycle, which makes any
// weird state unreproducible.
//
// The seed is bit-mixed first. Fed straight into an LCG, seeds that differ by
// one produce streams that agree on their first few draws, so nearby seeds
// dealt near-identical boards -- which quietly wrecks any "every board is
// different" sampling done over consecutive seeds.
function mixSeed(seed) {
  var s = seed >>> 0;
  s = (s ^ (s >>> 16)) >>> 0;
  s = Math.imul(s, 2246822507) >>> 0;
  s = (s ^ (s >>> 13)) >>> 0;
  s = Math.imul(s, 3266489909) >>> 0;
  s = (s ^ (s >>> 16)) >>> 0;
  return s;
}

function makeRng(seed) {
  var s = mixSeed(seed);
  return function () {
    s = (Math.imul(s, 1664525) + 1013904223) >>> 0;
    return s / 4294967296;
  };
}

function pick(rng, arr) {
  if (!arr || arr.length === 0) return null;
  return arr[Math.floor(rng() * arr.length) % arr.length];
}

function shuffle(arr, rng) {
  var a = arr.slice();
  for (var i = a.length - 1; i > 0; i--) {
    var j = Math.floor(rng() * (i + 1));
    var t = a[i]; a[i] = a[j]; a[j] = t;
  }
  return a;
}

// Picks `count` entries from `pool` that are not already named in `usedNames`
// and do not duplicate an op+value pair already on the board.
//
// The op+value rule is what stops a board from being ambiguous before the
// uniqueness walk ever runs: two cards that do the same thing at the same
// number are the same link twice, and the player cannot tell which one they
// meant.
function takeFresh(rng, pool, count, hand) {
  var taken = [];
  var chosen = hand.slice();

  for (var i = 0; i < count; i++) {
    var candidates = pool.filter(function (c) {
      for (var j = 0; j < chosen.length; j++) {
        if (chosen[j].name === c.name || sameOpValue(chosen[j], c)) return false;
      }
      return true;
    });
    if (candidates.length === 0) return null;
    var next = pick(rng, candidates);
    taken.push(next);
    chosen.push(next);
  }

  return taken;
}

// ---------------------------------------------------------------------------
// Solving
// ---------------------------------------------------------------------------

// Walks a chain of card objects and reports where it ended up. An illegal link
// is not an error: it is how a chain that forgot the CLEAR fails, so it stops
// there and reports what it had.
function resolve(cards) {
  var dmg = 0;
  var cleared = false;
  var legal = true;
  for (var i = 0; i < cards.length; i++) {
    var r = step(cards[i].op, cards[i].value, dmg, cleared);
    if (!r.legal) { legal = false; break; }
    dmg = r.dmg;
    cleared = r.cleared;
  }
  return { dmg: dmg, cleared: cleared, legal: legal };
}

// Every ordered, non-empty chain the hand can form, as index lists into it.
// Collected into an array rather than yielded: generators are not worth the
// risk in a QML-imported library.
function allChains(hand) {
  var out = [];
  var path = [];

  function walk() {
    for (var i = 0; i < hand.length; i++) {
      if (path.indexOf(i) !== -1) continue;
      path.push(i);
      if (path.length > 0) out.push(path.slice());
      if (path.length < hand.length) walk();
      path.pop();
    }
  }

  walk();
  return out;
}

// Every legal chain that lands exactly on `target`.
//
// This is the uniqueness proof. The generator does not assume the hand has one
// answer; it counts.
function solutionsFor(hand, target) {
  var chains = allChains(hand);
  var hits = [];
  for (var i = 0; i < chains.length; i++) {
    var cards = chains[i].map(function (idx) { return hand[idx]; });
    var r = resolve(cards);
    if (r.legal && r.dmg === target) hits.push(chains[i]);
  }
  return hits;
}

// ---------------------------------------------------------------------------
// Board construction
// ---------------------------------------------------------------------------

// The intended line: a clear plus between one and three damaging links. Links
// are drawn from the whole damaging pool rather than from a fixed template, so
// the interesting shapes (scale-then-add, add-then-scale, halve-then-scale)
// turn up by accident.
function buildSolution(rng) {
  var links = MIN_LINKS + Math.floor(rng() * (MAX_LINKS - MIN_LINKS + 1)) - 1;
  var chain = [pick(rng, poolFor(CLEAR))];
  if (!chain[0]) return null;

  for (var i = 0; i < links; i++) {
    var card = pick(rng, CARD_POOL.filter(function (c) {
      return c.op !== CLEAR && !sameOpValue(c, chain[chain.length - 1]);
    }));
    if (card) chain.push(card);
  }

  return chain.length >= MIN_LINKS ? chain : null;
}

// Fills the hand out to HAND_SIZE with cards that are not on the solution.
function buildHand(rng, solution) {
  var hand = solution.map(cloneCard);
  var decoys = takeFresh(rng, CARD_POOL, HAND_SIZE - hand.length, hand);
  if (!decoys) return null;
  return shuffle(hand.concat(decoys.map(cloneCard)), rng);
}

// Ids are assigned after the hand is sorted into a canonical order, so a seed
// always yields the same id-to-card mapping. A module-level counter would make
// ids depend on how many boards had been generated before and quietly break
// reproducibility.
//
// The canonical order is then thrown away and the hand re-shuffled for display.
// Sorting is what makes ids stable, but it also lines the hand up by op, which
// would show the player a board sorted clear-then-strike-then-mult every single
// time -- a stable, informative arrangement handed over for free.
function assignIds(hand, rng) {
  var ordered = hand.slice().sort(function (a, b) {
    if (a.op !== b.op) return a.op < b.op ? -1 : 1;
    if (a.value !== b.value) return a.value - b.value;
    return a.name < b.name ? -1 : 1;
  });
  for (var i = 0; i < ordered.length; i++) ordered[i].id = i + 1;
  return shuffle(ordered, rng);
}

// ---------------------------------------------------------------------------
// Generation
// ---------------------------------------------------------------------------

function generate(seed) {
  var rng = makeRng(seed === undefined ? Math.floor(Math.random() * 0xffffffff) : seed);

  for (var attempt = 0; attempt < 600; attempt++) {
    var solution = buildSolution(rng);
    if (!solution) continue;

    var outcome = resolve(solution);
    if (!outcome.legal || outcome.dmg < MIN_TARGET) continue;

    var hand = buildHand(rng, solution);
    if (!hand) continue;

    hand = assignIds(hand, rng);
    var target = outcome.dmg;

    // A strike sitting in hand worth exactly the target would let the player
    // clear, play that one card, and win without reading the rest of the board.
    // The uniqueness walk would happily accept it -- it really is the only
    // chain that works -- so the shortcut has to be ruled out by hand.
    var directHit = false;
    for (var h = 0; h < hand.length; h++) {
      if (hand[h].op === STRIKE && hand[h].value === target) { directHit = true; break; }
    }
    if (directHit) continue;

    // Re-derive the answer from the shuffled hand rather than trusting the
    // pre-shuffle chain. The solution and the hand are different objects, and
    // a generator that reported a line the dealt hand cannot actually form is
    // exactly the dead board worth catching here.
    var hits = solutionsFor(hand, target);
    if (hits.length !== 1) continue;

    var answerCards = hits[0].map(function (idx) { return hand[idx]; });
    if (answerCards[0].op !== CLEAR) continue;

    return {
      opponent: pick(rng, OPPONENT_POOL),
      target: target,
      hand: hand,
      // The answer is carried as names, not card objects, so a session holding
      // this puzzle can never mutate the board it was handed.
      solution: answerCards.map(function (c) { return c.name; })
    };
  }

  // Exhausting the search is a generator bug, not a runtime condition worth
  // handling in the UI -- surface it loudly instead of dealing a dead board.
  throw new Error("duel: failed to generate a board with exactly one solution");
}

// ---------------------------------------------------------------------------
// Session
//
// A generated board plus the mutable chain the player is building. The player
// links and unlinks freely and commits when they think they have it; nothing
// is revealed until a commit, so the board is a puzzle rather than a guessing
// game with a miss counter.
//
// QML cannot see a change behind this object. Writes to a plain JavaScript
// object's properties raise no notification, so a QML binding that reads
// `session.chain` is evaluated once and never again -- the whole board froze on
// the first frame while the engine carried on correctly underneath. That is why
// this file is not what the UI binds to: DuelSession.qml mirrors every value
// below into real QML properties after each mutation, and the view reads those.
//
// So the derived values here are maintained as plain properties and recomputed in
// one place, because the mirror and the tests read the same numbers and must not
// be able to disagree about what is on the field. The `total()` / `canLink()`
// accessors are what the tests read; they return the maintained properties
// rather than recomputing.
// ---------------------------------------------------------------------------

function Session(puzzle) {
  this.puzzle = puzzle;
  this.chain = [];
  this.dmg = 0;
  this.cleared = false;
  this.submittable = false;
  this.won = false;
  this.attempts = 0;
  this.lastResult = "";
  this.lastDmg = 0;
  this.broken = false;
  this.refusal = "";
  this.sync();
}

// Recomputes every derived value. The double assignment is not a typo: QML
// drops a binding when the new value is identical to the old, so a chain that
// links two cards worth the same total must still invalidate `submittable`.
Session.prototype.sync = function () {
  var r = resolve(this.chain);
  this.dmg = r.legal ? r.dmg : -1;
  this.cleared = r.cleared;
  this.submittable = !this.won && r.legal && r.cleared && r.dmg > 0;
};

Session.prototype.resetChain = function () {
  this.chain = [];
  this.broken = false;
  this.refusal = "";
  this.sync();
};

// Live total for the chain as currently built. Reads as 0 while the monster is
// still up, because that is the number that would actually be on the field --
// `dmg` is negative for an illegal chain so the UI can tell "nothing yet" from
// "blocked", which it renders differently.
Session.prototype.total = function () {
  return this.dmg < 0 ? 0 : this.dmg;
};

Session.prototype.isLegal = function () {
  return this.dmg >= 0;
};

Session.prototype.hasCard = function (id) {
  for (var i = 0; i < this.chain.length; i++) {
    if (this.chain[i].id === id) return false;
  }
  return true;
};

Session.prototype.cardById = function (id) {
  for (var i = 0; i < this.puzzle.hand.length; i++) {
    if (this.puzzle.hand[i].id === id) return this.puzzle.hand[i];
  }
  return null;
};

Session.prototype.chainIndexOf = function (id) {
  for (var i = 0; i < this.chain.length; i++) {
    if (this.chain[i].id === id) return i;
  }
  return -1;
};

// Links a card. Refused while the monster is up, because a chain that cannot
// start is not worth letting the player build -- the refusal is what makes the
// monster a rule instead of decoration.
//
// A refusal leaves `refusal` set to the reason. That is not polish: four of the
// five cards in the opening position are illegal, and returning a bare false
// made the board indistinguishable from a dead screen -- the player clicks,
// nothing happens, and there is no way to tell a broken lock from a rule they
// have not learned yet.
Session.prototype.add = function (id) {
  var why = this.refusalFor(id);
  this.refusal = why;
  if (why) return false;

  var card = this.cardById(id);
  // Unreachable while refusalFor covers the miss, and kept because the failure
  // it guards is not a wrong answer but a corrupt chain: a null link makes
  // every later resolve() throw, so the board stops totalling at all.
  if (!card) return false;

  this.chain = this.chain.concat([card]);
  this.broken = false;
  this.sync();
  return true;
};

// Whether this card could be linked right now. The hand binds its dimming to
// this, so the one legal link is the only card that looks live instead of every
// card inviting a click that will be thrown away.
Session.prototype.canLink = function (id) {
  return this.refusalFor(id) === "";
};

// Why a link would be refused, in a sentence the board can put on screen. Empty
// string means the link is legal.
Session.prototype.refusalFor = function (id) {
  if (this.won) return "The field is already clear.";

  var card = this.cardById(id);

  // An id the hand does not hold is never linkable, and must never read as
  // legal. Card ids are numbers, and anything that stringifies one on the way
  // in -- a QML `property string` will -- misses every comparison here, so a
  // lookup miss is the one case that most needs saying out loud.
  if (!card) return "That card is not in your hand.";

  if (!this.hasCard(id)) return card.name + " is already in the chain.";

  var probe = step(card.op, card.value, this.total(), this.cleared);
  if (probe.legal) return "";

  // The one rule a first-timer cannot guess, so it gets said outright rather
  // than left for the player to infer from a board that will not move.
  if (!this.cleared) return "The monster is face-up. Nothing can link until it is cleared.";

  return card.name + " will not link there.";
};

// Truncates the chain back to just before `index`. A chain is ordered, so
// pulling a link out of the middle has to take everything after it with it.
Session.prototype.removeAt = function (index) {
  if (this.won || index < 0 || index >= this.chain.length) return false;
  this.chain = this.chain.slice(0, index);
  this.broken = false;
  this.refusal = "";
  this.sync();
  return true;
};

Session.prototype.undo = function () {
  if (this.won || this.chain.length === 0) return false;
  this.chain = this.chain.slice(0, this.chain.length - 1);
  this.broken = false;
  this.refusal = "";
  this.sync();
  return true;
};

// Declares the attack. Returns "win", "short", or "over" -- the split matters
// because "you were 200 short" and "you were 200 over" read very differently
// to someone one step from the answer, and both are progress.
Session.prototype.commit = function () {
  if (!this.submittable) return null;

  var dmg = this.dmg;
  this.attempts += 1;
  this.lastDmg = dmg;

  if (dmg === this.puzzle.target) {
    this.won = true;
    this.lastResult = "win";
    this.sync();
    return "win";
  }

  this.lastResult = dmg < this.puzzle.target ? "short" : "over";
  // resetChain clears `broken`, so the flag has to be raised after it or the
  // UI never learns the last attack failed.
  this.resetChain();
  this.broken = true;
  return this.lastResult;
};
