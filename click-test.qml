// Click audit: can the player actually select a card?
//
// preview-test.qml proves the engine works and the layout fits. Neither of those
// is what "nothing was selectable" means: a board can be perfectly laid out,
// unit-test clean, and still be a dead screen, because nothing checked whether
// a click on a card reaches that card's MouseArea. This file checks that
// directly, by hit-testing the real item tree.
//
// Three separate failures look identical from the desk, and they need different
// fixes, so they are reported apart:
//   1. unreachable -- something painted above the card swallows the click
//   2. disabled    -- the card's own MouseArea is off
//   3. refused     -- the click lands, but the engine rejects the link in
//                     silence, so the board looks exactly like case 1 or 2
//
// Run from the plugin directory:
//   quickshell -p /usr/share/omarchy/shell -p . click-test.qml

import QtQuick
import QtQuick.Window
import qs.Commons
import qs.Ui
import "duel/DuelModel.js" as Duel

Window {
  id: win
  visible: true
  width: 1368
  height: 912
  color: "black"
  title: "duel-lock-click-audit"

  LockView {
    id: view
    anchors.fill: parent
    backgroundPath: ""
    backgroundVersion: 1
    fingerprintConfigured: false
    // The real lock passes inputEnabled: lockRequested, which is true for the
    // whole lock. Anything less and this audit would be measuring the harness.
    inputEnabled: true
    loadBackground: false
  }

  // ------------------------------------------------------------------ helpers

  function collectMouseAreas(item, out) {
    // Pre-order. Qt paints a parent's own content before its children and each
    // sibling before the next, so the last item in a pre-order walk is the top
    // one -- the one a click at that point actually hits. Nothing in this plugin
    // sets `z`, so paint order is declaration order and this is exact.
    out.push(item)
    var kids = item.children
    for (var i = 0; i < kids.length; i++) collectMouseAreas(kids[i], out)
    return out
  }

  function effectiveVisible(item) {
    for (var i = item; i !== null && i !== undefined; i = i.parent) {
      if (i.visible === false) return false
    }
    return true
  }

  // The MouseArea a click at (x, y) in view coordinates would land on, or null.
  function topMouseAt(x, y) {
    var list = collectMouseAreas(view, [])
    for (var i = list.length - 1; i >= 0; i--) {
      var m = list[i]
      if (!(m instanceof MouseArea)) continue
      if (!m.enabled || !m.acceptedButtons) continue
      if (!effectiveVisible(m) || m.width <= 0 || m.height <= 0) continue
      var p = m.mapToItem(view, 0, 0)
      if (x >= p.x && y >= p.y && x <= p.x + m.width && y <= p.y + m.height) return m
    }
    return null
  }

  function describe(item) {
    if (!item) return "nothing"
    if (item.objectName) return item.objectName
    return "<" + item.toString().split("(")[0] + ">"
  }

  function findAll(root, name, out) {
    if (root.objectName === name) out.push(root)
    var kids = root.children
    for (var i = 0; i < kids.length; i++) findAll(kids[i], name, out)
    return out
  }

  function hitAreaOf(card) {
    var kids = card.children
    for (var i = 0; i < kids.length; i++) {
      if (kids[i] instanceof MouseArea) return kids[i]
    }
    return null
  }

  // -------------------------------------------------------------------- audit

  property int problems: 0
  property int silentRefusals: 0

  function auditClicks(tag) {
    var session = view.duelSession
    if (!session) {
      console.error("CLICK FAIL " + tag + ": no session")
      problems++
      return
    }

    var cards = findAll(view, "handCard", [])
    console.log("CLICK " + tag + ": inputEnabled=" + view.inputEnabled +
      " cleared=" + session.cleared + " chain=" + session.chain.length +
      " hand cards=" + cards.length + " target=" + session.puzzle.target)

    if (cards.length !== session.puzzle.hand.length) {
      console.error("CLICK FAIL " + tag + ": " + cards.length + " card items for a " +
        session.puzzle.hand.length + " card hand")
      problems++
    }

    for (var i = 0; i < cards.length; i++) {
      var card = cards[i]
      var hit = hitAreaOf(card)
      var top = card.mapToItem(view, 0, 0)
      var cx = top.x + card.width / 2
      var cy = top.y + card.height / 2
      var landed = topMouseAt(cx, cy)

      // A card already in the chain is drawn as spent, and the chain copy of it
      // sits over its old slot. Both are correct: it must be inert in the hand,
      // and the thing on top of that slot is the card you unlink with.
      if (card.spent) {
        if (hit && hit.enabled) {
          console.error("CLICK FAIL " + tag + ": spent card " + i + " (" + card.cardName + ") is still clickable")
          problems++
        }
        continue
      }

      // 1. unreachable
      if (landed !== hit) {
        console.error("CLICK FAIL " + tag + ": card " + i + " (" + card.cardName + ") at " +
          Math.round(cx) + "," + Math.round(cy) + " is covered by " + describe(landed))
        problems++
      }

      // 2. disabled
      if (!hit || !hit.enabled) {
        console.error("CLICK FAIL " + tag + ": card " + i + " (" + card.cardName + ") hit area is disabled")
        problems++
        continue
      }

      // 3. refused, silently. The engine is asked directly what it would do
      // with this click right now, so the audit reports the same dead end the
      // player hits.
      var probe = Duel.step(card.card.op, card.card.value, session.total, session.cleared)
      var playable = session.hasCard(card.card.id) && probe.legal
      if (!playable) {
        silentRefusals++
        console.log("  REFUSED " + tag + ": card " + i + " (" + card.cardName + " " +
          card.card.op + " " + card.card.value + ") reachable and enabled, but the engine " +
          "refuses the link -- probe.legal=" + probe.legal +
          " alreadyChained=" + !session.hasCard(card.card.id))
      }
    }
  }

  // -------------------------------------------------------------------- phases

  // `var`, not `string`: card ids are numbers, and a string property would
  // hand the engine an id it cannot find -- which it must refuse, not obey.
  property var blockedId: null
  property string blockedName: ""
  property real handYBefore: 0
  property real handYAfter: 0

  function handRowY() {
    var row = findAll(view, "handRow", [])[0]
    return row ? row.mapToItem(view, 0, 0).y : -1
  }

  // Clicks a card the engine is going to refuse. `link()` is exactly what a
  // click on a card calls, so this exercises the whole response path apart from
  // Qt's event delivery -- which auditClicks already covers by hit-test.
  function clickBlockedCard() {
    var cards = findAll(view, "handCard", [])
    var blocked = -1
    var open = -1

    for (var i = 0; i < cards.length; i++) {
      if (!cards[i].linkable && blocked < 0) blocked = i
      if (cards[i].linkable && open < 0) open = i
    }

    // The board has to show which card is live before it is clicked, not only
    // complain afterwards.
    if (blocked < 0) {
      console.error("CLICK FAIL: no card is dimmed, so nothing signals the rule")
      problems++
      return
    }
    if (open < 0) {
      console.error("CLICK FAIL: no card in hand can be linked")
      problems++
      return
    }

    console.log("  AFFORDANCE: card " + open + " (" + cards[open].cardName +
      ") is live, card " + blocked + " (" + cards[blocked].cardName + ") is dimmed")

    blockedId = cards[blocked].card.id
    blockedName = cards[blocked].cardName
    handYBefore = handRowY()
    view.duelBoardItem.link(blockedId)
  }

  // Read after a frame, not immediately: `message` is a binding and the flash
  // goes through Qt.callLater, so neither has happened yet at the call site.
  // Asserting synchronously here would pass a board that never shows anything.
  function auditFeedback() {
    var board = view.duelBoardItem
    var session = view.duelSession

    if (session.refusal.length === 0) {
      console.error("CLICK FAIL: a refused click left no reason on the session")
      problems++
    }
    if (board.message.length === 0) {
      console.error("CLICK FAIL: a refused click put nothing on screen")
      problems++
    }
    if (!board.messageIsProblem) {
      console.error("CLICK FAIL: the refusal is not marked as a problem")
      problems++
    }
    if (String(board.flashId) !== String(blockedId)) {
      console.error("CLICK FAIL: the refused card did not flash (flashId=" + board.flashId + ")")
      problems++
    }
    if (board.message.indexOf(blockedName) < 0 && session.refusal.indexOf(blockedName) < 0
        && session.refusal.indexOf("face-up") < 0) {
      console.error("CLICK FAIL: the refusal does not explain itself: " + board.message)
      problems++
    }
    console.log("  FEEDBACK: \"" + board.message + "\" (flash " + board.flashId + ")")
  }

  // Does a QML binding actually see the session change? The whole board is drawn
  // from bindings onto a plain JavaScript object, and a binding that never
  // re-evaluates leaves a board that accepts clicks and shows no sign of it --
  // which is exactly "nothing was selectable". Every other audit reads the
  // engine directly, so only this one can catch it.
  function auditBindings(tag) {
    var session = view.duelSession
    var track = findAll(view, "chainTrack", [])[0]
    var totalText = findAll(view, "chainTotal", [])[0]
    var chainCards = findAll(view, "chainCard", [])
    var message = view.duelBoardItem.message

    console.log("  BINDINGS " + tag + ": engine total=" + session.total +
      " chain=" + session.chain.length +
      " | ChainTrack.total=" + (track ? track.total : "no track") +
      " chainTotal text=" + (totalText ? totalText.text : "no text") +
      " chainCard items=" + chainCards.length +
      " | board.message=\"" + message + "\"")
    console.log("  IDS " + tag + ": hand=" + session.hand.map(function (c) {
      return c.id + "(" + typeof c.id + ")"
    }).join(",") + " chainIds=" + JSON.stringify(session.chainIds) +
      " linkable=" + JSON.stringify(session.linkableIds) +
      " canLink(1)=" + session.canLink(1))

    if (!track) {
      console.error("CLICK FAIL " + tag + ": no chainTrack in the view")
      problems++
      return
    }
    if (track.total !== session.total) {
      console.error("CLICK FAIL " + tag + ": ChainTrack.total is " + track.total +
        " but the engine says " + session.total + " -- the total on screen is stale")
      problems++
    }
    if (chainCards.length !== session.chain.length) {
      console.error("CLICK FAIL " + tag + ": " + chainCards.length + " chain cards drawn for a " +
        session.chain.length + " card chain -- the board is not following the engine")
      problems++
    }
    if (chainCards.length > 0 && chainCards[0].cardName !== session.chain[0].name) {
      console.error("CLICK FAIL " + tag + ": the first chain card is " +
        chainCards[0].cardName + ", engine says " + session.chain[0].name)
      problems++
    }
  }

  Timer {
    interval: 700
    running: true
    repeat: false
    onTriggered: {
      console.log("=== phase 1: fresh board, nothing linked ===")
      win.auditClicks("fresh")
      console.log("=== phase 1b: clicking a card that cannot link ===")
      win.clickBlockedCard()
      feedbackSettle.restart()
    }
  }

  // Long enough for the callLater and the next polish pass, short enough to
  // catch the board before the 420ms flash is due to clear.
  Timer {
    id: feedbackSettle
    interval: 150
    repeat: false
    onTriggered: {
      if (win.blockedId === null) {
        // clickBlockedCard bailed out; there is no click to audit.
        console.log("CLICK skipped: nothing was clicked")
        settle2.restart()
        return
      }

      win.auditFeedback()
      win.handYAfter = win.handRowY()
      if (Math.abs(win.handYAfter - win.handYBefore) > 0.5) {
        console.error("CLICK FAIL: the hand jumped " +
          Math.round(Math.abs(win.handYAfter - win.handYBefore)) +
          "px when the refusal message appeared")
        win.problems++
      } else {
        console.log("CLICK OK: the message line is reserved, the hand does not move")
      }

      console.log("=== phase 2: after the clear is linked ===")
      var session = view.duelSession
      var clear = session.puzzle.hand.filter(function (c) { return c.op === Duel.CLEAR })[0]
      if (!session.add(clear.id)) {
        console.error("CLICK FAIL: the engine refused the clear card on a fresh board")
        win.problems++
      }
      if (session.refusal.length !== 0) {
        console.error("CLICK FAIL: a legal link left a stale refusal on screen: " + session.refusal)
        win.problems++
      }
      settle2.restart()
    }
  }

  Timer {
    id: settle2
    interval: 150
    repeat: false
    onTriggered: {
      var session = view.duelSession
      if (!session.cleared) {
        console.error("CLICK FAIL: linking the clear did not set cleared")
        win.problems++
      }
      win.auditClicks("cleared")
      win.auditBindings("cleared")

      console.log("=== phase 3: the won board, password field up ===")
      for (var i = 0; i < session.puzzle.solution.length; i++) {
        var name = session.puzzle.solution[i]
        var card = session.puzzle.hand.filter(function (c) { return c.name === name })[0]
        // The clear is already linked from phase 2, and re-adding it is a
        // refusal, not a step of the solution.
        if (!session.canLink(card.id)) continue
        if (!session.add(card.id)) {
          console.error("CLICK FAIL: the engine refused its own solution at " + name)
          win.problems++
          break
        }
      }
      if (session.commit() !== "win") {
        console.error("CLICK FAIL: the solution did not win")
        win.problems++
      }
      view.duelBoardItem.won = true
      view.duelBoardItem.duelWon()
      settle3.restart()
    }
  }

  Timer {
    id: settle3
    interval: 300
    repeat: false
    onTriggered: {
      // On the won board the scrim and its click-swallowing MouseArea are up.
      // A card under the scrim is not a bug -- the field is meant to take the
      // input then -- but the hand must not be *enabled* under it, or the
      // cursor still says "click me" over a scrim.
      var cards = findAll(view, "handCard", [])
      var liveUnderScrim = 0
      for (var i = 0; i < cards.length; i++) {
        var hit = hitAreaOf(cards[i])
        if (hit && hit.enabled) liveUnderScrim++
      }
      console.log("CLICK won: " + liveUnderScrim + " hand hit areas still enabled under the scrim")
      if (liveUnderScrim > 0) win.problems++

      if (win.silentRefusals === 0) {
        console.error("CLICK FAIL: no card was ever refused, so this audit never exercised the refusal path")
        win.problems++
      }

      if (win.problems > 0) {
        console.error("CLICK FAIL: " + win.problems + " problems, " +
          win.silentRefusals + " silent refusals reachable by a real click")
        Qt.exit(1)
        return
      }
      console.log("CLICK OK: every card reachable, enabled, and refusals are reachable to audit")
      Qt.exit(0)
    }
  }

  Timer {
    interval: 25000
    running: true
    onTriggered: {
      console.error("CLICK TIMEOUT")
      Qt.exit(1)
    }
  }
}
