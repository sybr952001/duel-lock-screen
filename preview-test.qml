// Preview LockView in a standalone Quickshell run to catch load-time QML
// errors -- a bad property, a missing import, a typo'd singleton -- without
// taking the live lock screen down or locking the session.
//
// Run from the plugin directory:
//   quickshell -p /usr/share/omarchy/shell -p . preview-test.qml
//
// `-p /usr/share/omarchy/shell` is what puts qs.Commons and qs.Ui on the
// import path, the same way the real shell is launched.
//
// Two passes:
//   1. Functional -- drives the real engine through a wrong line and then the
//      published solution, proving the win reaches the password phase and that
//      a relock deals a fresh board.
//   2. Geometry -- lays the view out at several window sizes and reports any
//      item that falls outside its bounds or overlaps the item above it. This
//      is what catches the layout bugs a screenshot cannot be trusted on: the
//      author's resolution is not the resolution the lock screen will open at.

import QtQuick
import QtQuick.Window
import qs.Commons
import qs.Ui

Window {
  id: win
  visible: true
  width: 1368
  height: 912
  color: "black"
  title: "duel-lock-preview"

  LockView {
    id: view
    anchors.fill: parent
    backgroundPath: ""
    backgroundVersion: 1
    fingerprintConfigured: false
    inputEnabled: true
    loadBackground: false
  }

  // ---------------------------------------------------------------- helpers

  // Everything visible must sit inside the view. A lock screen that renders its
  // own hand off the bottom edge is still a working lock screen as far as the
  // auth wiring is concerned, which is exactly why it needs its own check.
  function auditBounds(tag) {
    var bad = []
    var checked = 0

    function walk(item) {
      var kids = item.children
      for (var i = 0; i < kids.length; i++) {
        var k = kids[i]
        if (k.visible === false) continue
        if (typeof k.mapToItem !== "function") continue
        var w = k.width
        var h = k.height
        if (w > 0 && h > 0) {
          checked++
          var p = k.mapToItem(view, 0, 0)
          var name = k.objectName || ("<" + (k.toString ? k.toString().split("(")[0] : "?") + ">")
          if (p.x < -0.5 || p.y < -0.5 || p.x + w > view.width + 0.5 || p.y + h > view.height + 0.5) {
            bad.push(name + " " + Math.round(p.x) + "," + Math.round(p.y) +
              " " + Math.round(w) + "x" + Math.round(h) +
              " vs " + Math.round(view.width) + "x" + Math.round(view.height))
          }
        }
        walk(k)
      }
    }

    walk(view)
    console.log("AUDIT " + tag + ": checked " + checked + " items, " + bad.length + " out of bounds")
    for (var j = 0; j < bad.length; j++) console.log("  OVERFLOW " + tag + ": " + bad[j])
    return bad.length
  }

  // The board is a single centred column, so its own children must march
  // downwards in order. A column cannot overlap itself, but it can be given a
  // child that grows past the column's share of the screen, and that shows up
  // as the content height exceeding the space available.
  function auditColumn(tag) {
    var column = findByObjectName(view, "duelColumn")
    if (!column) {
      console.log("AUDIT " + tag + ": FAIL no duelColumn")
      return 1
    }

    var problems = 0
    var prevBottom = -1
    var kids = column.children
    for (var i = 0; i < kids.length; i++) {
      var k = kids[i]
      if (k.visible === false) continue
      if (k.width <= 0 || k.height <= 0) continue
      var p = k.mapToItem(view, 0, 0)
      var name = k.objectName || ("<" + k.toString().split("(")[0] + ">")
      if (p.y < prevBottom - 0.5) {
        console.log("  OVERLAP " + tag + ": " + name + " starts at y=" + Math.round(p.y) +
          " but the previous item ends at " + Math.round(prevBottom))
        problems++
      }
      prevBottom = p.y + k.height
    }

    var top = column.mapToItem(view, 0, 0).y
    var bottom = top + column.height
    console.log("AUDIT " + tag + ": column " + Math.round(column.width) + "x" +
      Math.round(column.height) + " spans y=" + Math.round(top) + ".." + Math.round(bottom) +
      " of " + Math.round(view.height))

    if (top < -0.5 || bottom > view.height + 0.5) {
      console.log("  OVERFLOW " + tag + ": column does not fit vertically by " +
        Math.round(Math.max(0, -top) + Math.max(0, bottom - view.height)) + "px")
      problems++
    }
    if (column.width > view.width + 0.5) {
      console.log("  OVERFLOW " + tag + ": column wider than the view by " +
        Math.round(column.width - view.width) + "px")
      problems++
    }
    return problems
  }

  function findByObjectName(root, name) {
    if (root.objectName === name) return root
    var kids = root.children
    for (var i = 0; i < kids.length; i++) {
      var found = findByObjectName(kids[i], name)
      if (found) return found
    }
    return null
  }

  function auditAll(tag) {
    return auditBounds(tag) + auditColumn(tag)
  }

  // ------------------------------------------------------------------ phase 1

  // The engine is pure logic, so the preview can drive it directly: solve a
  // board with the real solution and assert the win actually flips the view
  // into its password phase. A QML file that loads but never wires the win
  // through would pass a visual check and still be a broken lock screen.
  Timer {
    interval: 600
    running: true
    repeat: false
    onTriggered: {
      var session = view.duelSession
      if (!session) {
        console.error("PREVIEW FAIL: no session on the board")
        Qt.exit(1)
        return
      }

      console.log("PREVIEW target=" + session.puzzle.target +
        " opponent=" + session.puzzle.opponent.name +
        " hand=" + session.puzzle.hand.length)

      // One deliberately wrong line, to prove a miss does not unlock.
      var clear = session.puzzle.hand.filter(function (c) { return c.op === "clear" })[0]
      var strike = session.puzzle.hand.filter(function (c) { return c.op === "strike" })[0]
      session.add(clear.id)
      session.add(strike.id)
      if (session.dmg === session.puzzle.target) {
        console.error("PREVIEW FAIL: a single strike already reached lethal")
        Qt.exit(1)
        return
      }
      var miss = session.commit()
      if (miss === "win" || view.duelSolved) {
        console.error("PREVIEW FAIL: a wrong line opened the password field")
        Qt.exit(1)
        return
      }
      console.log("PREVIEW miss rejected: " + miss + " for " + session.lastDmg)

      // Now the real line.
      for (var i = 0; i < session.puzzle.solution.length; i++) {
        var name = session.puzzle.solution[i]
        var card = session.puzzle.hand.filter(function (c) { return c.name === name })[0]
        if (!session.add(card.id)) {
          console.error("PREVIEW FAIL: the engine refused its own solution")
          Qt.exit(1)
          return
        }
      }
      if (session.dmg !== session.puzzle.target) {
        console.error("PREVIEW FAIL: solution totalled " + session.dmg +
          ", expected " + session.puzzle.target)
        Qt.exit(1)
        return
      }
      if (session.commit() !== "win") {
        console.error("PREVIEW FAIL: solution did not win")
        Qt.exit(1)
        return
      }
      console.log("PREVIEW win on " + session.dmg)

      // Hand the win up the way a real click does, then confirm the field
      // opened and the password input is live.
      view.duelBoardItem.won = true
      view.duelBoardItem.duelWon()
      if (!view.duelSolved) {
        console.error("PREVIEW FAIL: duelSolved did not latch")
        Qt.exit(1)
        return
      }
      console.log("PREVIEW OK: password phase reachable")

      // Deliberately audited from here, while the board is in its WON state:
      // a full solution chain plus the verdict line plus the password scrim is
      // the tallest the layout ever gets. Auditing the empty board would pass
      // while the state a player actually reaches falls off the bottom.
      geometryIndex = 0
      geometryProblems = 0
      geometryTimer.running = true
    }
  }

  // ------------------------------------------------------------------ phase 2

  // The resolutions the board has to survive. The first is this machine's real
  // logical size; the rest are the shapes it would meet on a scale change, a
  // different panel, or a nested window.
  property var sizes: [
    { w: 1368, h: 912, tag: "laptop-2x" },
    { w: 1920, h: 1080, tag: "desktop-1x" },
    { w: 2560, h: 1440, tag: "wide-qhd" },
    { w: 1024, h: 768, tag: "small" },
    { w: 800, h: 600, tag: "tiny" },
    { w: 640, h: 480, tag: "very-tiny" }
  ]

  property int geometryIndex: 0
  property int geometryProblems: 0
  property int boardIdBefore: -1

  Timer {
    id: geometryTimer
    interval: 220
    repeat: true
    running: false
    onTriggered: {
      if (geometryIndex >= win.sizes.length) {
        geometryTimer.running = false
        if (geometryProblems > 0) {
          console.error("PREVIEW FAIL: " + geometryProblems + " layout problems")
          Qt.exit(1)
          return
        }
        console.log("PREVIEW OK: layout clean at all " + win.sizes.length + " sizes")

        // Relock must deal a fresh, playable board. Leaving the won flag set
        // would bring the lock screen back with a dead attack button, and
        // leaving duelSolved latched would skip the duel entirely -- which is
        // the one way the puzzle could stop gating anything.
        win.boardIdBefore = view.duelBoardItem.boardId
        view.resetDuel()
        if (view.duelSolved) {
          console.error("PREVIEW FAIL: duelSolved survived resetDuel")
          Qt.exit(1)
          return
        }
        if (view.duelBoardItem.won) {
          console.error("PREVIEW FAIL: the board came back already won")
          Qt.exit(1)
          return
        }
        if (!view.duelSession.ready) {
          console.error("PREVIEW FAIL: no live board after resetDuel")
          Qt.exit(1)
          return
        }
        // The board id is what proves this is a *new* board and not the old
        // session still sitting there: the session object is permanent, so only
        // the deal is fresh.
        if (view.duelBoardItem.boardId === win.boardIdBefore) {
          console.error("PREVIEW FAIL: resetDuel did not deal a new board")
          Qt.exit(1)
          return
        }
        // `submittable` is what gates Declare Attack, so a board that came back
        // without it is a board nobody can attack on.
        if (view.duelSession.submittable === undefined) {
          console.error("PREVIEW FAIL: fresh session has no submittable flag")
          Qt.exit(1)
          return
        }
        if (view.duelSession.won || view.duelSession.chain.length !== 0) {
          console.error("PREVIEW FAIL: the fresh session carried state over")
          Qt.exit(1)
          return
        }
        if (view.duelSession.puzzle.hand.length !== 5) {
          console.error("PREVIEW FAIL: the fresh board is not a full hand")
          Qt.exit(1)
          return
        }
        console.log("PREVIEW OK: relock deals a fresh playable board")
        Qt.exit(0)
        return
      }

      var size = win.sizes[geometryIndex]
      win.width = size.w
      win.height = size.h
      geometryIndex++
      // Let the resize settle before measuring: a Column reflows on the next
      // polish pass, and auditing the stale geometry would pass a broken
      // layout or fail a good one.
      settle.restart()
    }
  }

  Timer {
    id: settle
    interval: 120
    repeat: false
    onTriggered: geometryProblems += auditAll(win.sizes[geometryIndex - 1].tag)
  }

  // Backstop so a thrown error still exits instead of hanging the preview.
  Timer {
    interval: 20000
    running: true
    onTriggered: {
      console.error("PREVIEW TIMEOUT")
      Qt.exit(1)
    }
  }
}
