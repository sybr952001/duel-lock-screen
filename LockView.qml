import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "duel"

// The lock screen. Two phases, in this order and no other:
//
//   1. A duel puzzle. The opponent is on an awkward amount of LP with a
//      monster face-up; the only way through is one specific chain of cards.
//   2. Once that chain connects, the password field appears and the real
//      credential is checked against PAM.
//
// The order is the point. The password alone does nothing, and a solved puzzle
// alone does nothing -- both are required, and the Service enforces that on the
// session lock, not just here in the view.
Item {
  id: root

  property string backgroundPath: ""
  property int backgroundVersion: 0
  property bool fingerprintConfigured: false
  property bool authenticatingPassword: false
  property string failureMessage: ""
  property int failedAttempts: 0
  property bool inputEnabled: true
  property bool loadBackground: true
  property string passwordText: ""
  property bool syncingPasswordText: false

  // Set by DuelBoard once the lethal line connects. Read by Service.qml, which
  // refuses to start PAM until this is true.
  property bool duelSolved: false

  // Re-emitted so the Service can own `duelSolved` as a signal rather than a
  // binding onto this view -- see the note on that property in Service.qml.
  signal duelWon()

  // The live duel session, exposed so the preview harness can drive the board
  // through a real win without reaching into the item tree by child index.
  readonly property alias duelSession: duelBoard.session

  // The board item itself, so the preview can raise the same `duelWon` signal
  // a click on Declare would, instead of re-implementing the win path.
  readonly property alias duelBoardItem: duelBoard

  readonly property string placeholderText: "Enter Password"
  readonly property int fieldWidth: 381
  readonly property int fieldHeight: 67
  readonly property int outlineThickness: 3
  readonly property int fieldFontSize: Math.round(Style.font.heading * 1.125)
  readonly property int passwordDotFontSize: Math.round(Style.font.heading * 1.33)
  readonly property int passwordDotLetterSpacing: Math.round(Style.font.heading * 0.19)
  readonly property real fingerprintReserve: fingerprintConfigured ? Math.round(fingerprintIcon.implicitWidth + 12) : 0
  readonly property real passwordDotScale: dotMetrics.advanceWidth > 0
    ? Math.min(1, (passwordInput.width - 4) / dotMetrics.advanceWidth)
    : 1
  readonly property bool showPasswordCursor: inputEnabled && duelSolved && !authenticatingPassword && failureMessage.length === 0
  readonly property bool errorState: failureMessage.length > 0
  readonly property var inputBorderSpec: errorState
    ? Border.surfaceSpec("lock", "border-error", Color.lock.borderError, root.outlineThickness, "border-alpha")
    : Border.surfaceSpec("lock", "border-active", Color.lock.borderActive, root.outlineThickness, "border-alpha")

  signal submitPassword(string password)
  signal passwordTextEdited(string password)
  signal clearFailureRequested()
  signal wakeRequested()

  // Cache-busts the lock background by appending `?v=`. Adding a query
  // string keeps Image's loader happy while forcing it to reload when the
  // user picks a new background mid-session.
  function fileUrl(path) {
    if (!path) return ""
    var encoded = String(path).split("/").map(encodeURIComponent).join("/")
    return "file://" + encoded + "?v=" + backgroundVersion
  }

  function forcePasswordFocus() {
    passwordInput.forceActiveFocus()
  }

  function clearPassword() {
    passwordTextEdited("")
  }

  function syncPasswordText() {
    if (passwordInput.text === passwordText) return
    syncingPasswordText = true
    passwordInput.text = passwordText
    syncingPasswordText = false
  }

  function markDuelSolved() {
    if (duelSolved) return
    duelSolved = true
    duelWon()
  }

  // Called by Service on every lock so a relock never reopens a solved duel.
  function resetDuel() {
    duelSolved = false
    if (duelBoard) duelBoard.newBoard()
    if (passwordInput) passwordInput.text = ""
  }

  onPasswordTextChanged: syncPasswordText()
  // The field only takes focus once the duel is won -- tabbing into it earlier
  // would be a password prompt that cannot possibly work.
  onInputEnabledChanged: {
    if (inputEnabled && duelSolved) Qt.callLater(forcePasswordFocus)
  }
  onDuelSolvedChanged: {
    if (duelSolved && inputEnabled) Qt.callLater(forcePasswordFocus)
  }
  Component.onCompleted: {
    syncPasswordText()
    if (inputEnabled && duelSolved) Qt.callLater(forcePasswordFocus)
  }

  // Measures the masked password at full size; passwordDotScale compares this
  // against the field width to decide how far the dots must shrink to fit.
  TextMetrics {
    id: dotMetrics
    font.family: Style.font.family
    font.pixelSize: root.passwordDotFontSize
    font.letterSpacing: root.passwordDotLetterSpacing
    text: "\u25CF".repeat(passwordInput.text.length)
  }

  Rectangle {
    anchors.fill: parent
    color: Color.background

    Image {
      id: wallpaper
      anchors.fill: parent
      source: root.loadBackground ? root.fileUrl(root.backgroundPath) : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      sourceSize.width: width
      sourceSize.height: height
    }

    MultiEffect {
      anchors.fill: wallpaper
      source: wallpaper
      autoPaddingEnabled: false
      blurEnabled: root.loadBackground && wallpaper.status === Image.Ready
      blur: 1.0
      blurMax: 128
      blurMultiplier: 1.25
      contrast: -0.08
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onClicked: { root.wakeRequested(); root.forcePasswordFocus() }
      onPositionChanged: root.wakeRequested()
    }

    // ------------------------------------------------------------- the duel
    DuelBoard {
      id: duelBoard
      anchors.fill: parent
      inputEnabled: root.inputEnabled
      onDuelWon: root.markDuelSolved()
    }

    // ------------------------------------------------------- the credential
    //
    // Sits over the board rather than replacing it, so the duel that earned
    // the prompt is still on screen behind the field.
    Rectangle {
      id: scrim
      anchors.fill: parent
      color: Util.alpha(Color.background, 0.72)
      visible: opacity > 0
      opacity: root.duelSolved ? 1 : 0

      Behavior on opacity {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
      }

      // Swallow clicks so a stray click cannot reach the board underneath.
      MouseArea {
        anchors.fill: parent
        // Also wakes. Once the duel is won this scrim is the topmost thing on
        // screen, and the wake MouseArea further down is buried under the whole
        // board -- so without this a blanked panel never lit up for a move or a
        // click, and the field looked as dead as the puzzle did.
        onClicked: { root.wakeRequested(); root.forcePasswordFocus() }
        onPositionChanged: root.wakeRequested()
      }

      Column {
        anchors.centerIn: parent
        width: root.fieldWidth
        spacing: Style.spacing.lg

        Text {
          width: parent.width
          text: "DUEL WON"
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.letterSpacing: 3
          horizontalAlignment: Text.AlignHCenter
        }

        Text {
          width: parent.width
          text: "Now enter your password to log in."
          color: Color.lock.placeholder
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }

        BorderSurface {
          id: inputField
          width: root.fieldWidth
          height: root.fieldHeight
          color: Color.lock.background
          borderSpec: root.inputBorderSpec
          radius: Style.cornerRadius
          clip: true

          TextInput {
            id: passwordInput
            anchors.fill: parent
            anchors.topMargin: inputField.borderTop
            // Reserve the fingerprint icon's width on both sides so the
            // centered dots stay symmetric and never slide under the icon.
            anchors.rightMargin: inputField.borderRight + 18 + root.fingerprintReserve
            anchors.bottomMargin: inputField.borderBottom
            anchors.leftMargin: inputField.borderLeft + 18 + root.fingerprintReserve
            verticalAlignment: TextInput.AlignVCenter
            horizontalAlignment: TextInput.AlignHCenter
            activeFocusOnPress: true
            clip: true
            enabled: root.inputEnabled && root.duelSolved && !root.authenticatingPassword
            readOnly: root.authenticatingPassword
            echoMode: TextInput.Password
            passwordCharacter: "\u25CF"
            passwordMaskDelay: 0
            color: Color.lock.text
            selectionColor: Color.lock.selection
            selectedTextColor: Color.lock.text
            font.family: Style.font.family
            font.pixelSize: text.length > 0 ? Math.max(1, Math.floor(root.passwordDotFontSize * root.passwordDotScale)) : root.fieldFontSize
            font.letterSpacing: text.length > 0 ? root.passwordDotLetterSpacing * root.passwordDotScale : 0
            cursorVisible: activeFocus && root.showPasswordCursor && text.length > 0
            cursorDelegate: Rectangle {
              width: 2
              color: Color.lock.text
              visible: passwordInput.cursorVisible
            }

            onTextChanged: {
              if (!root.syncingPasswordText) root.passwordTextEdited(text)
              if (text.length > 0) {
                root.wakeRequested()
              }
              if (text.length > 0 && root.failureMessage.length > 0) root.clearFailureRequested()
            }

            onAccepted: {
              var submitted = root.passwordText
              root.passwordTextEdited("")
              if (submitted.length > 0) root.submitPassword(submitted)
            }

            Keys.onPressed: function(event) {
              root.wakeRequested()
              if (event.key === Qt.Key_Escape || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U)) {
                root.passwordTextEdited("")
                event.accepted = true
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            anchors.fill: passwordInput
            text: root.authenticatingPassword ? "Checking…" : (root.failureMessage.length > 0 ? root.failureMessage : root.placeholderText)
            visible: passwordInput.text.length === 0
            color: root.authenticatingPassword ? Color.lock.text : (root.failureMessage.length > 0 ? Color.lock.textError : Color.lock.placeholder)
            font.family: Style.font.family
            font.pixelSize: root.fieldFontSize
            font.italic: !root.authenticatingPassword && root.failureMessage.length > 0
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
          }

          // Fingerprint hint pinned inside the field's right edge when a
          // sensor is enrolled. Only meaningful once the duel is won, since
          // the puzzle has to be solved before any credential is checked.
          Text {
            id: fingerprintIcon
            objectName: "fingerprintIndicator"
            anchors.right: parent.right
            anchors.rightMargin: inputField.borderRight + 18
            anchors.verticalCenter: parent.verticalCenter
            visible: root.fingerprintConfigured
            text: "\uF0237"
            color: Color.lock.placeholder
            font.family: Style.font.family
            font.pixelSize: Math.round(root.fieldFontSize * 1.1)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
          }
        }
      }
    }
  }
}
