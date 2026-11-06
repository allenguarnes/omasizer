import QtQuick
import qs.Commons
import qs.Commons as Commons

// A section label in the style of Omarchy's panels, with an optional note at its far end.
Item {
  id: root

  property string text: ""
  property string trailing: ""
  property bool trailingAccent: false
  property real topPadding: 0

  width: parent ? parent.width : implicitWidth
  implicitHeight: root.topPadding + title.implicitHeight + Style.space(4)
  height: implicitHeight

  Text {
    id: title
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    textFormat: Text.PlainText
    text: root.text
    color: Qt.darker(Commons.Color.menu.text, 1.4)
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 0.6
  }

  Text {
    anchors.right: parent.right
    anchors.left: title.right
    anchors.leftMargin: Style.space(12)
    anchors.baseline: title.baseline
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideLeft
    textFormat: Text.PlainText
    text: root.trailing
    color: root.trailingAccent ? Commons.Color.menu.selectedText : Qt.darker(Commons.Color.menu.text, 1.4)
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.caption
  }
}
