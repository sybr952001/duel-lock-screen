import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "DuelModel.js" as Duel

// The chain the player is building, plus the running total against the LP they
// have to hit.
//
// The total is the only number that matters on this screen, so it is the
// largest thing here and it sits directly under the opponent's LP -- the player
// should never have to remember one number to compare against another.

Item {
  id: root

  property var session: null

  readonly property bool ready: session !== null && session.ready
  readonly property int target: ready ? session.target : 0
  readonly property int total: ready ? session.total : 0
  readonly property bool empty: ready && session.chain.length === 0
  readonly property bool over: ready && !empty && total > target
  readonly property bool exact: ready && !empty && total === target

  // The total is urgent when the chain has already overshot, because a chain
  // past lethal is a dead line no matter what gets linked after it.
  readonly property color totalColor: exact
    ? Commons.Color.accent
    : (over ? Commons.Color.urgent : Commons.Color.lock.text)

  Text {
    id: label
    objectName: "chainLabel"
    anchors.left: parent.left
    anchors.top: parent.top
    text: "CHAIN"
    color: Commons.Color.lock.placeholder
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1.2
  }

  Text {
    id: totalText
    objectName: "chainTotal"
    anchors.right: parent.right
    anchors.top: parent.top
    text: root.empty ? "—" : root.total
    color: root.totalColor
    font.family: Style.font.family
    font.pixelSize: Style.font.displayLarge
    font.weight: Font.DemiBold

    Behavior on color {
      ColorAnimation { duration: 140 }
    }
  }

  Text {
    id: caption
    objectName: "chainTarget"
    anchors.right: parent.right
    anchors.top: totalText.bottom
    anchors.topMargin: -Style.spacing.xxs
    text: "of " + root.target + " LP"
    color: Commons.Color.lock.placeholder
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  // Empty state. Without it the row is just blank space and there is nothing
  // telling a first-timer that the hand below is clickable.
  Text {
    anchors.left: parent.left
    anchors.right: totalText.left
    anchors.rightMargin: Style.spacing.lg
    anchors.verticalCenter: parent.verticalCenter
    visible: root.empty
    text: root.ready && !root.session.cleared
      ? "The monster is face-up. Clear it before anything can deal damage."
      : "Link your hand left to right. Click a link to cut the chain there."
    color: Commons.Color.lock.placeholder
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    font.italic: true
    wrapMode: Text.WordWrap
    elide: Text.ElideRight
    maximumLineCount: 2
  }

  // Chain cards scale off this item's own width instead of a fixed size, so a
  // four-card chain still fits on a narrow screen. The 120px reserve is the
  // total plus its "of N LP" caption sitting on the right.
  readonly property int cardWidth: Math.max(80, Math.min(Style.space(158), Math.floor((width - Style.space(120)) / 4)))
  readonly property int cardHeight: Math.round(cardWidth * 0.62)

  // Grown by the taller of the two columns it holds: the label over the chain,
  // or the total over its caption. Lets the parent column size me by content
  // instead of guessing a height that only fits one resolution.
  implicitHeight: Math.max(
    label.height + Style.spacing.sm + cardHeight,
    totalText.height + caption.height
  ) + Style.spacing.xs

  Row {
    id: chainRow
    objectName: "chainRow"
    anchors.left: parent.left
    anchors.right: totalText.left
    anchors.rightMargin: Style.spacing.md
    anchors.top: label.bottom
    anchors.topMargin: Style.spacing.sm
    spacing: Style.spacing.xs

    Repeater {
      // DuelSession hands over a fresh array on every link and unlink precisely
      // so this model rebuilds; see the note in DuelSession.qml.
      model: root.session.chain

      delegate: DuelCard {
        required property var modelData
        required property int index
        objectName: "chainCard"

        width: root.cardWidth
        height: root.cardHeight
        card: modelData
        role: "chain"
        interactive: root.ready && !root.session.won

        onClicked: root.session.removeAt(index)
      }
    }
  }

  // Connector between the chain and the total, so a linked row reads
  // left-to-right as one expression rather than as a pile of cards.
  Text {
    anchors.left: chainRow.right
    anchors.leftMargin: Style.spacing.xs
    anchors.verticalCenter: chainRow.verticalCenter
    visible: root.ready && root.session.chain.length > 0
    text: "="
    color: Commons.Color.lock.placeholder
    font.family: Style.font.family
    font.pixelSize: Style.font.title
  }
}
