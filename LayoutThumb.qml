import QtQuick
import qs.Commons
import qs.Commons as Commons

// A layout drawn as a small screen. The menu picks single zones from it; the
// settings list treats the whole thumbnail as one control.
Rectangle {
  id: root

  property var zones: []
  property int selectedZone: -1
  // Highlights the frame, for a thumbnail that has keyboard focus as a whole.
  property bool highlighted: false
  // Marks the layout holding the menu's selection, more quietly than `highlighted`.
  property bool active: false
  property bool zonesInteractive: false

  signal zoneHovered(int index, var item, var mouse)
  signal zoneClicked(int index)

  readonly property color faint: Qt.rgba(Commons.Color.menu.text.r, Commons.Color.menu.text.g, Commons.Color.menu.text.b, 0.25)

  radius: Style.cornerRadius
  color: highlighted ? Commons.Color.menu.selectedBackground : "transparent"
  border.width: highlighted ? 2 : 1
  border.color: highlighted ? Commons.Color.menu.selectedText
    : active ? Qt.rgba(Commons.Color.menu.selectedText.r, Commons.Color.menu.selectedText.g, Commons.Color.menu.selectedText.b, 0.6)
    : root.faint

  Repeater {
    model: root.zones

    Rectangle {
      id: zoneRect
      required property var modelData
      required property int index
      readonly property bool selected: index === root.selectedZone
      readonly property real inset: 2

      x: modelData[0] * root.width + inset
      y: modelData[1] * root.height + inset
      width: Math.max(1, modelData[2] * root.width - inset * 2)
      height: Math.max(1, modelData[3] * root.height - inset * 2)
      radius: Math.max(0, Style.cornerRadius - 1)
      color: selected ? Commons.Color.menu.selectedText : Commons.Color.menu.selectedBackground
      border.width: 1
      border.color: selected ? Commons.Color.menu.selectedText
        : Qt.rgba(Commons.Color.menu.text.r, Commons.Color.menu.text.g, Commons.Color.menu.text.b, 0.35)

      MouseArea {
        anchors.fill: parent
        enabled: root.zonesInteractive
        hoverEnabled: true
        onPositionChanged: function(mouse) { root.zoneHovered(zoneRect.index, zoneRect, mouse) }
        onClicked: root.zoneClicked(zoneRect.index)
      }
    }
  }
}
