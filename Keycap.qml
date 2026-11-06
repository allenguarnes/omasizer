import QtQuick
import qs.Commons
import qs.Commons as Commons

// A key the user can press, drawn as a small keycap.
Rectangle {
  id: root

  property string text: ""
  property bool lit: false

  readonly property color tint: root.lit ? Commons.Color.menu.selectedText : Commons.Color.menu.text

  implicitWidth: Math.max(label.implicitWidth + Style.space(10), implicitHeight)
  implicitHeight: Style.font.caption + Style.space(8)
  radius: Math.min(Style.space(4), Style.cornerRadius + 2)
  color: "transparent"
  border.width: 1
  border.color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, root.lit ? 0.8 : 0.3)

  Text {
    id: label
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: root.text
    color: root.tint
    opacity: root.lit ? 1 : 0.7
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.caption
    font.bold: true
  }
}
