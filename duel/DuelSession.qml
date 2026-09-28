import QtQuick
import "DuelModel.js" as Duel

// The QML face of the duel engine.
//
// The engine itself stays a plain JavaScript object so it can be unit tested
// outside the shell (see test/duel-model.test.mjs). It cannot also be the thing
// the UI binds to: QML does not track property writes on a plain JS object, so
// a binding that reads `session.chain` is evaluated once and never again. Every
// visual on the board -- the chain, the running total, the dimming, the spent
// cards, the verdict -- was frozen at whatever it held on the first frame. The
// board took clicks perfectly and showed no sign of it, which is exactly what
// "nothing was selectable" looks like from the other side of the screen.
//
// So every value the UI binds to is a real QML property here, and every
// mutation ends in pull(). The arrays are handed over as fresh copies: a
// Repeater is only told to rebuild when its model property is reassigned, and
// assigning the same array back would be a change the UI never sees.
QtObject {
  id: root

  property var engine: null
  readonly property bool ready: engine !== null

  // Fixed for the life of a board. Read by the Repeaters as their models, and
  // by anything that needs the target or the answer.
  property var puzzle: null
  property var hand: []
  property var solution: []
  property var opponentName: ""
  property int target: 0

  // The live values. All reassigned by pull().
  property var chain: []
  property var chainIds: []
  property var linkableIds: []
  property int total: 0
  property int dmg: 0
  property bool cleared: false
  property bool submittable: false
  property bool won: false
  property bool broken: false
  property string refusal: ""
  property string lastResult: ""
  property int lastDmg: 0
  property int attempts: 0

  // Deals a board and makes it the live one. Called on every lock, so a relock
  // can never inherit the previous board's chain.
  function newBoard(dealt) {
    puzzle = dealt
    hand = dealt.hand
    solution = dealt.solution
    opponentName = dealt.opponent.name
    target = dealt.target
    engine = new Duel.Session(dealt)
    pull()
  }

  function pull() {
    if (!engine) return

    // New identities every time, so a Repeater bound to one of these is always
    // notified. A chain that links two cards worth the same total still has to
    // redraw, and reusing the array would not tell it to.
    chain = engine.chain.slice()

    // Filled first, handed over second. Assigning an empty array and pushing
    // into it afterwards notifies every binding while it is still empty, and
    // nothing tells them it changed -- which looks exactly like frozen bindings
    // all over again.
    var ids = []
    for (var i = 0; i < chain.length; i++) ids.push(chain[i].id)
    chainIds = ids

    // Which cards the engine would take right now, computed here rather than
    // left to a binding calling into JS: a binding cannot see a change behind a
    // function call, so `canLink` inside a delegate would freeze on the first
    // frame and the board would never re-dim the hand.
    var open = []
    for (var h = 0; h < hand.length; h++) {
      if (engine.canLink(hand[h].id)) open.push(hand[h].id)
    }
    linkableIds = open

    total = engine.total()
    dmg = engine.dmg
    cleared = engine.cleared
    submittable = engine.submittable
    won = engine.won
    broken = engine.broken
    refusal = engine.refusal
    lastResult = engine.lastResult
    lastDmg = engine.lastDmg
    attempts = engine.attempts
  }

  function add(id) {
    if (!engine) return false
    var linked = engine.add(id)
    pull()
    return linked
  }

  function removeAt(index) {
    if (!engine) return false
    var removed = engine.removeAt(index)
    pull()
    return removed
  }

  function undo() {
    if (!engine) return false
    var undone = engine.undo()
    pull()
    return undone
  }

  // Returns "win", "short", "over", or null.
  function commit() {
    if (!engine) return null
    var result = engine.commit()
    pull()
    return result
  }

  function canLink(id) {
    return engine ? engine.canLink(id) : false
  }

  function refusalFor(id) {
    return engine ? engine.refusalFor(id) : ""
  }

  function hasCard(id) {
    return engine ? engine.hasCard(id) : false
  }
}
