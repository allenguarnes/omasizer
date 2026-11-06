import QtQuick
import qs.Commons
import qs.Commons as Commons

// The title line of a view: an icon in the accent color, a title, and the keys that close it.
Item {
  id: root

  property string icon: ""
  property string title: ""
  property string hint: ""

  width: parent ? parent.width : implicitWidth
  implicitHeight: Math.max(titleText.implicitHeight, keycap.implicitHeight) + Style.space(6)

  Text {
    id: iconText
    anchors.left: parent.left
    anchors.verticalCenter: titleText.verticalCenter
    textFormat: Text.PlainText
    text: root.icon
    color: Commons.Color.menu.selectedText
    font.family: Style.font.family
    font.pixelSize: Style.font.iconLarge
  }

  Text {
    id: titleText
    anchors.left: iconText.right
    anchors.leftMargin: Style.space(10)
    anchors.right: keycap.left
    anchors.rightMargin: Style.space(8)
    anchors.top: parent.top
    textFormat: Text.PlainText
    elide: Text.ElideRight
    text: root.title
    color: Commons.Color.menu.text
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.heading
    font.bold: true
  }

  Keycap {
    id: keycap
    anchors.right: parent.right
    anchors.verticalCenter: titleText.verticalCenter
    visible: root.hint !== ""
    text: root.hint
  }
}
