import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Presets.js" as Presets

// Records a keyboard shortcut: focus it and press the combination. Backspace or
// Delete clears it; Tab moves on as usual. Combinations Hyprland already binds
// never reach it, since Hyprland acts on them first.
BorderSurface {
  id: root

  // In Hyprland's "SUPER + ALT + Z" form, or "" for none.
  property string shortcut: ""
  property string offText: ""
  property string listeningText: ""

  signal edited(string shortcut)

  readonly property bool listening: root.activeFocus
  readonly property var keys: root.shortcut ? root.shortcut.split(" + ") : []
  readonly property var _borderSpec: Border.controlSpec(root.listening ? "focus" : (mouse.containsMouse ? "hover-cursor" : "normal"),
    Commons.Color.foreground, Commons.Color.accent)

  implicitWidth: Style.space(220)
  implicitHeight: Style.spacing.controlHeight
  radius: Style.cornerRadius
  color: Style.controlFill(root.listening, mouse.containsMouse, Commons.Color.foreground, Commons.Color.accent)
  borderSpec: root._borderSpec
  activeFocusOnTab: true

  function keyName(event) {
    var k = event.key
    if ((k >= Qt.Key_A && k <= Qt.Key_Z) || (k >= Qt.Key_0 && k <= Qt.Key_9)) return String.fromCharCode(k)
    if (k >= Qt.Key_F1 && k <= Qt.Key_F12) return "F" + (k - Qt.Key_F1 + 1)
    var named = {}
    named[Qt.Key_Left] = "LEFT"; named[Qt.Key_Right] = "RIGHT"; named[Qt.Key_Up] = "UP"; named[Qt.Key_Down] = "DOWN"
    named[Qt.Key_Space] = "SPACE"; named[Qt.Key_Return] = "RETURN"; named[Qt.Key_Enter] = "RETURN"
    named[Qt.Key_Home] = "HOME"; named[Qt.Key_End] = "END"; named[Qt.Key_PageUp] = "PAGEUP"; named[Qt.Key_PageDown] = "PAGEDOWN"
    named[Qt.Key_Insert] = "INSERT"; named[Qt.Key_Slash] = "SLASH"; named[Qt.Key_Backslash] = "BACKSLASH"
    named[Qt.Key_Comma] = "COMMA"; named[Qt.Key_Period] = "PERIOD"; named[Qt.Key_Minus] = "MINUS"; named[Qt.Key_Equal] = "EQUAL"
    named[Qt.Key_QuoteLeft] = "GRAVE"; named[Qt.Key_Semicolon] = "SEMICOLON"; named[Qt.Key_Apostrophe] = "APOSTROPHE"
    named[Qt.Key_BracketLeft] = "BRACKETLEFT"; named[Qt.Key_BracketRight] = "BRACKETRIGHT"
    return named[k] || ""
  }

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) return
    event.accepted = true
    if (event.key === Qt.Key_Escape) {
      root.nextItemInFocusChain(true).forceActiveFocus()
      return
    }
    if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) && !event.modifiers) {
      root.edited("")
      return
    }
    var mods = []
    if (event.modifiers & Qt.MetaModifier) mods.push("SUPER")
    if (event.modifiers & Qt.ControlModifier) mods.push("CTRL")
    if (event.modifiers & Qt.AltModifier) mods.push("ALT")
    if (event.modifiers & Qt.ShiftModifier) mods.push("SHIFT")
    // Modifiers alone, or a key without one, keep listening.
    var combo = Presets.normalizeShortcut(mods.concat([root.keyName(event)]).join(" + "))
    if (combo) root.edited(combo)
  }

  Row {
    anchors.left: parent.left
    anchors.leftMargin: Style.spacing.controlPaddingX
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(4)

    Repeater {
      model: root.listening ? [] : root.keys
      Keycap {
        required property string modelData
        anchors.verticalCenter: parent.verticalCenter
        text: modelData
        lit: true
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.listening || root.keys.length === 0
      textFormat: Text.PlainText
      text: root.listening ? root.listeningText : root.offText
      color: root.listening ? Commons.Color.menu.selectedText : Commons.Color.menu.text
      opacity: root.listening ? 1 : 0.6
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.body
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.forceActiveFocus()
  }
}
