import QtQuick
import qs.Commons
import qs.Ui
import "DuelModel.js" as Duel

// One card, used both in the hand and in the chain. The same component draws
// both so a linked card is visibly the same object you picked up, rather than
// a different-looking chip the board invented.
Item {
  id: root

  property var card: null
  // A card already in the chain is drawn as spent, which is what tells the
  // player their hand is not infinite.
  property bool spent: false
  property bool interactive: true
  property bool highlighted: false
  property string role: "hand"

  // A hand card the engine would refuse right now. Drawn dimmed with a plain
  // cursor, so the board says which card is live instead of inviting a click
  // that is going to be thrown away. It stays clickable on purpose: the click
  // is what produces the sentence explaining the refusal.
  property bool linkable: true

  // Brief urgent outline when a click on this card was refused.
  property bool flash: false

  // Named for the click audit in click-test.qml, which has to tell "the card
  // refused the click" apart from "the click never reached the card".
  readonly property string cardName: valid ? String(card.name) : "?"

  signal clicked()

  readonly property bool valid: card !== null && card !== undefined

  // A card in hand that cannot link yet reads as unavailable, distinctly from
  // one that has been spent: spent is also unclickable, but it is a card the
  // player has already used.
  readonly property bool dimmed: role === "hand" && !linkable && !spent

  // Op colour. CLEAR is the one card that is always wanted, so it wears the
  // accent; a strike is the damage, so it wears the urgent colour. Everything
  // else stays in the theme's text ramp rather than inventing a palette.
  readonly property color tone: {
    if (!valid) return Color.lock.placeholder
    if (card.op === Duel.CLEAR) return Color.accent
    if (card.op === Duel.STRIKE) return Color.urgent
    if (card.op === Duel.MULT) return Color.lock.text
    return Color.lock.placeholder
  }

  readonly property color label: spent || dimmed
    ? Color.lock.placeholder
    : (highlighted ? Color.lock.text : tone)

  readonly property var borderSpec: Border.surfaceSpec(
    "lock",
    highlighted ? "border-active" : "border",
    highlighted ? Color.lock.borderActive : Color.lock.border,
    highlighted ? 2 : 1,
    "border-alpha"
  )

  BorderSurface {
    id: frame
    anchors.fill: parent
    color: Color.lock.background
    borderSpec: root.borderSpec
    radius: Style.cornerRadius
    clip: true
    opacity: root.spent ? 0.45 : (root.dimmed ? 0.62 : 1)

    Behavior on opacity {
      NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
    }

    // Refusal flash. Anchored rather than laid out, so it can fire on a card
    // without the hand reflowing around it.
    Rectangle {
      anchors.fill: parent
      anchors.margins: -2
      radius: Style.cornerRadius
      color: "transparent"
      border.width: 2
      border.color: Color.urgent
      opacity: root.flash ? 1 : 0
      visible: opacity > 0

      Behavior on opacity {
        NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
      }
    }

    // Glyph, top-left.
    Text {
      id: glyph
      anchors.left: parent.left
      anchors.leftMargin: frame.borderLeft + Style.spacing.sm
      anchors.top: parent.top
      anchors.topMargin: frame.borderTop + Style.spacing.xs
      text: root.valid ? Duel.opGlyph(card.op) : "?"
      color: root.label
      font.family: Style.font.family
      font.pixelSize: Style.font.subtitle
      opacity: root.spent ? 0.5 : 0.85
    }

    // The number, top-right. This is the whole card: a strike's value, a
    // multiplier, or the word CLEAR.
    Text {
      anchors.right: parent.right
      anchors.rightMargin: frame.borderRight + Style.spacing.sm
      anchors.top: parent.top
      anchors.topMargin: frame.borderTop + Style.spacing.xs
      text: root.valid ? Duel.opLabel(card.op, card.value) : ""
      color: root.label
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      font.weight: Font.DemiBold
      elide: Text.ElideRight
    }

    Text {
      anchors.left: parent.left
      anchors.leftMargin: frame.borderLeft + Style.spacing.sm
      anchors.right: parent.right
      anchors.rightMargin: frame.borderRight + Style.spacing.sm
      anchors.verticalCenter: parent.verticalCenter
      text: root.valid ? card.name : ""
      color: root.spent || root.dimmed ? Color.lock.placeholder : Color.lock.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      maximumLineCount: 2
      wrapMode: Text.WordWrap
    }

    Text {
      anchors.left: parent.left
      anchors.leftMargin: frame.borderLeft + Style.spacing.sm
      anchors.right: parent.right
      anchors.rightMargin: frame.borderRight + Style.spacing.sm
      anchors.bottom: parent.bottom
      anchors.bottomMargin: frame.borderBottom + Style.spacing.xs
      text: root.valid ? Duel.opDetail(card.op, card.value) : ""
      color: Color.lock.placeholder
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      opacity: root.spent ? 0 : 0.85
    }
  }

  MouseArea {
    id: hit
    objectName: "cardHit"
    anchors.fill: parent
    // Deliberately still enabled when the card cannot link: the click is what
    // gets the board to say why. Only a spent card is inert.
    enabled: root.interactive && root.valid && !root.spent
    hoverEnabled: true
    // A dimmed hand card gets a plain cursor, so the pointer agrees with the
    // card about whether this is the one to pick up.
    cursorShape: enabled && !root.dimmed ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.clicked()
  }
}
