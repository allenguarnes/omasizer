import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Presets.js" as Presets

// Records a keyboard shortcut: focus it and press the combination. Backspace or
// Delete clears it; Tab moves on as usual. It listens while focused, so recording,
// clearing or Escape hands focus on to the next control. Combinations Hyprland already binds
// never reach it, since Hyprland acts on them first.
BorderSurface {
  id: root

  // In Hyprland's "SUPER + ALT + Z" form, or "" for none.
  property string shortcut: ""
  // Records modifiers for the arrow keys instead: press them together and let go; `shortcut` is the
  // modifiers. Hyprland already binds most arrows with Super, and a bound arrow never arrives here.
  property bool arrows: false
  // Every modifier held since the last one was let go.
  property var heldModifiers: []
  property string offText: ""
  property string listeningText: ""

  signal edited(string shortcut)

  readonly property bool listening: root.activeFocus
  readonly property var keys: root.shortcut ? root.shortcut.split(" + ").concat(root.arrows ? ["←↑→↓"] : []) : []
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

  function finish(shortcut) {
    if (shortcut !== undefined) root.edited(shortcut)
    root.nextItemInFocusChain(true).forceActiveFocus()
  }

  onActiveFocusChanged: root.heldModifiers = []

  function modifiersOf(event) {
    var mods = []
    if (event.modifiers & Qt.MetaModifier) mods.push("SUPER")
    if (event.modifiers & Qt.ControlModifier) mods.push("CTRL")
    if (event.modifiers & Qt.AltModifier) mods.push("ALT")
    if (event.modifiers & Qt.ShiftModifier) mods.push("SHIFT")
    return mods
  }

  // The modifier a key is, or "".
  function modifierKey(key) {
    if (key === Qt.Key_Meta || key === Qt.Key_Super_L || key === Qt.Key_Super_R) return "SUPER"
    if (key === Qt.Key_Control) return "CTRL"
    if (key === Qt.Key_Alt) return "ALT"
    if (key === Qt.Key_Shift) return "SHIFT"
    return ""
  }

  // For `arrows`: once the last modifier is let go, the ones held are the result.
  Keys.onReleased: function(event) {
    var released = root.modifierKey(event.key)
    if (!root.arrows || !released || event.isAutoRepeat) return
    event.accepted = true
    if (root.modifiersOf(event).some(function(m) { return m !== released })) return
    var modifiers = Presets.normalizeModifiers(root.heldModifiers.join(" + "))
    root.heldModifiers = []
    if (modifiers) root.finish(modifiers)
  }

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) return
    event.accepted = true
    if (event.key === Qt.Key_Escape) {
      root.finish()
      return
    }
    if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) && !event.modifiers) {
      root.finish("")
      return
    }
    var mods = root.modifiersOf(event)
    // Modifiers alone, or a key without one, keep listening. For `arrows`, modifiers are gathered
    // until let go, and an arrow that does arrive ends it at once.
    var key = root.keyName(event)
    if (root.arrows) {
      var pressed = root.modifierKey(event.key)
      var held = root.heldModifiers.concat(mods, pressed ? [pressed] : [])
      root.heldModifiers = held.filter(function(m, i) { return held.indexOf(m) === i })
      var modifiers = Presets.ARROWS.indexOf(key) >= 0 ? Presets.normalizeModifiers(mods.join(" + ")) : null
      if (modifiers) root.finish(modifiers)
      return
    }
    var combo = Presets.normalizeShortcut(mods.concat([key]).join(" + "))
    if (combo) root.finish(combo)
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
      // Never wider than the field.
      width: Math.min(implicitWidth, root.width - Style.spacing.controlPaddingX * 2)
      elide: Text.ElideRight
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
