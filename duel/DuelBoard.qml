import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "DuelModel.js" as Duel

// The duel itself: the opponent, the chain, the hand, and the attack button.
//
// Solves the puzzle by exact lethal. The opponent's LP is derived from the one
// chain that reaches it, so the board always has exactly one answer and the
// player is never brute-forcing a guess.
//
// Laid out as one centred column rather than as anchors hung off each screen
// edge. Anchored-from-both-edges looks fine on one resolution and falls apart
// on the next: this panel is authored for whatever the laptop's scaled mode
// happens to be (1368x912 logical on a 2x eDP here), and a column cannot
// overlap itself or drift off the bottom.
Item {
  id: root

  // Bumped on every deal so anything watching the board can tell a re-deal
  // from an in-place edit.
  property int boardId: 0
  property bool inputEnabled: true
  property bool won: false

  // Named `duelWon` rather than `wonChanged`: QML auto-generates a
  // `<property>Changed` signal for `won`, and declaring that name by hand
  // collides with the auto-generated one.
  signal duelWon()

  // The live session. A DuelSession, not the raw engine: the engine is a plain
  // JavaScript object and QML cannot see a change behind one, so every binding
  // that read it directly was frozen on the first frame. See DuelSession.qml.
  readonly property alias session: duelSession

  DuelSession {
    id: duelSession
  }

  // The card whose click was just refused, so it can flash. A separate property
  // rather than per-delegate state because the click that sets it is the one
  // thing that is not visible from the delegate.
  //
  // `var`, not `string`: card ids are numbers, and a string property would turn
  // the id into text so the delegate's `flashId === modelData.id` never matched
  // and the refusal flashed nothing.
  property var flashId: null

  Timer {
    id: flashTimer
    interval: 420
    repeat: false
    onTriggered: root.flashId = null
  }

  // `won` is cleared here rather than left to the caller. A relock re-deals
  // through this path, and a fresh session left sitting on a won board would
  // come back with its hand dimmed and its attack button dead.
  function newBoard() {
    duelSession.newBoard(Duel.generate())
    root.won = false
    root.flashId = null
    root.boardId += 1
  }

  // Every card click goes through here. A refused link is the common case in the
  // opening position -- four of five cards cannot link while the monster is up
  // -- so it has to produce something on screen. Returning quietly made the
  // whole board read as broken.
  function link(id) {
    if (!root.session.ready) return
    if (root.session.add(id)) return

    // Cleared first so a second refusal of the same card flashes again instead
    // of setting a value that is already set.
    root.flashId = null
    Qt.callLater(function() {
      root.flashId = id
      flashTimer.restart()
    })
  }

  Component.onCompleted: root.newBoard()

  // --------------------------------------------------------------- metrics
  //
  // Everything below is derived from the available width so the hand shrinks
  // rather than overflowing on a narrow screen. Five cards at the preferred
  // size need 814px; below that they get narrower instead of clipping.
  readonly property int maxColumnWidth: 940
  readonly property int edgeMargin: Style.space(28)
  readonly property int columnWidth: Math.max(240, Math.min(maxColumnWidth, width - edgeMargin * 2))
  readonly property int cardGap: Style.spacing.sm
  readonly property int cardWidth: Math.max(96, Math.floor((columnWidth - cardGap * 4) / 5))
  readonly property int cardHeight: Math.round(cardWidth * 0.66)
  readonly property int opponentWidth: Math.min(columnWidth, Style.space(320))
  readonly property int opponentHeight: Math.round(Math.min(Style.space(104), cardHeight * 1.15))

  // The one line of text under the board. Kept as one string so the reveal, the
  // attack verdict, and a refused link cannot all be showing at once.
  //
  // A refusal outranks the attack verdict: it is the more recent thing the
  // player did, and the verdict is still on the chain's own numbers if they
  // look back at the total.
  readonly property string message: {
    if (!session.ready) return ""
    if (session.won) return "The field is clear. You win."
    if (session.broken) {
      return session.lastResult === "over"
        ? "Declared for lethal and went over by " + (session.lastDmg - session.target) + ". It does not connect."
        : "The attack stopped short by " + (session.target - session.lastDmg) + ". Try another line."
    }
    if (session.refusal) return session.refusal
    return ""
  }

  readonly property bool messageIsProblem: session.broken || session.refusal.length > 0

  Column {
    id: column
    objectName: "duelColumn"
    width: root.columnWidth
    anchors.centerIn: parent
    spacing: Style.spacing.md

    // ---------------------------------------------------------------- header
    Text {
      width: parent.width
      text: "DUEL PUZZLE"
      color: Commons.Color.lock.placeholder
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.letterSpacing: 3
      horizontalAlignment: Text.AlignHCenter
    }

    // -------------------------------------------------------------- opponent
    BorderSurface {
      objectName: "opponentCard"
      width: root.opponentWidth
      height: root.opponentHeight
      color: Commons.Color.lock.background
      borderSpec: Border.surfaceSpec("lock", "border", Commons.Color.lock.border, 1, "border-alpha")
      radius: Style.cornerRadius
      clip: true

      Column {
        // Qualified through `parent`: inside this Column an unqualified
        // `contentLeftInset` resolves against the Column, which does not have
        // one, and silently collapses the margin to nothing.
        anchors.left: parent.left
        anchors.leftMargin: parent.contentLeftInset + Style.spacing.md
        anchors.right: parent.right
        anchors.rightMargin: parent.contentRightInset + Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Text {
          width: parent.width
          text: "OPPONENT"
          color: Commons.Color.lock.placeholder
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1.6
        }

        Text {
          width: parent.width
          text: root.session.opponentName
          color: Commons.Color.lock.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        // "FACE-UP" rather than an ATK number. The monster is a wall, not a
        // damage source, and printing a number next to it invites the player
        // to do arithmetic with a value the engine never uses.
        Text {
          width: parent.width
          text: "FACE-UP \u00B7 BLOCKS DAMAGE"
          color: Commons.Color.urgent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.letterSpacing: 0.6
          elide: Text.ElideRight
        }
      }
    }

    // The LP counter, deliberately the loudest number on the board: it is the
    // answer the chain has to reach.
    Row {
      objectName: "lpRow"
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.spacing.xs

      Text {
        anchors.baseline: lpValue.baseline
        text: "LP"
        color: Commons.Color.lock.placeholder
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.letterSpacing: 1.2
      }

      Text {
        id: lpValue
        text: root.session.ready ? root.session.target : 0
        color: Commons.Color.lock.text
        font.family: Style.font.family
        font.pixelSize: Style.font.heading * 1.75
        font.weight: Font.DemiBold
      }
    }

    // ------------------------------------------------------------------ chain
    //
    // No explicit height: ChainTrack reports its own implicitHeight, so the
    // column here can never be given a height that clips it.
    ChainTrack {
      objectName: "chainTrack"
      width: parent.width
      session: root.session
    }

    // ---------------------------------------------------------------- verdict
    Text {
      objectName: "verdict"
      width: parent.width
      // One line is always reserved. A message that appears and disappears with
      // its content would re-centre the column and slide the hand out from
      // under the pointer in the middle of a puzzle.
      height: Math.max(implicitHeight, Math.round(Style.font.bodySmall * 1.5))
      verticalAlignment: Text.AlignVCenter
      text: root.message
      color: root.messageIsProblem ? Commons.Color.urgent : Commons.Color.accent
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
    }

    // ------------------------------------------------------------------- hand
    Text {
      width: parent.width
      objectName: "handLabel"
      // States the rule while the monster is up, rather than leaving a player
      // to click four dead cards to find out why nothing moves.
      text: {
        if (!root.session.ready) return ""
        if (root.session.won) return "HAND"
        if (!root.session.cleared) return "YOUR HAND \u2014 CLEAR THE MONSTER FIRST"
        return "YOUR HAND \u2014 CLICK TO LINK, LEFT TO RIGHT"
      }
      color: Commons.Color.lock.placeholder
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1.4
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
    }

    Row {
      objectName: "handRow"
      width: parent.width
      spacing: root.cardGap

      Repeater {
        // The model is the hand array itself, so a re-deal replaces it outright
        // and the delegates are rebuilt. No re-keying key is needed.
        model: root.session.hand

        delegate: DuelCard {
          required property var modelData
          objectName: "handCard"

          // Off the mirrored id lists, not off a call into the engine: a
          // binding cannot see a change that happens inside a function call, so
          // a spent card would never dim and the hand would look untouched.
          readonly property bool played: root.session.chainIds.indexOf(modelData.id) !== -1

          width: root.cardWidth
          height: root.cardHeight
          card: modelData
          role: "hand"
          spent: played
          // Asks the engine, rather than re-deriving the rule here: the board
          // and the click handler must agree on what is legal or the card
          // promises a link the engine is about to refuse.
          linkable: root.session.linkableIds.indexOf(modelData.id) !== -1
          flash: root.flashId === modelData.id
          // The clear is the one card that must be linked first, so it is the
          // only one that lights up while the monster is still up.
          highlighted: root.session.ready && !played && !root.won
            && modelData.op === Duel.CLEAR && !root.session.cleared
          interactive: root.inputEnabled && !root.won && !played

          onClicked: root.link(modelData.id)

          // The hand settles back a touch on the win so the field reads as over.
          scale: root.won ? 0.96 : 1

          Behavior on scale {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
          }
        }
      }
    }

    // ---------------------------------------------------------------- buttons
    Row {
      objectName: "buttonsRow"
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.spacing.lg

      Button {
        width: Style.space(104)
        height: Style.space(38)
        text: "Undo"
        bordered: true
        foreground: Commons.Color.lock.text
        background: "transparent"
        fontSize: Style.font.body
        visible: root.session.chain.length > 0
        onClicked: root.session.undo()
      }

      Button {
        width: Style.space(224)
        height: Style.space(38)
        text: root.won ? "Field Cleared" : "Declare Attack"
        bordered: true
        foreground: root.won ? Commons.Color.accent : Commons.Color.lock.text
        background: "transparent"
        fontSize: Style.font.body
        // Disabled until the chain is legal and has crossed the field, so an
        // illegal line can never be committed in the first place.
        enabled: root.inputEnabled && !root.won && root.session.submittable
        onClicked: {
          if (!root.session.ready) return
          if (root.session.commit() === "win") {
            root.won = true
            root.duelWon()
          }
        }
      }
    }
  }
}
