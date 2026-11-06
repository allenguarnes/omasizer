import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Presets.js" as Presets
import "Icons.js" as Icons

// Edit one zone layout. Zones are dragged on a preview of the screen (edges and
// corners resize, the middle moves), split, added and removed, or typed as
// percentages. Emits `done` with { name, zones }, `deleted`, or `cancelled`.
Column {
  id: root

  property var strings: null
  // Height over width of the screen the preview stands for.
  property real aspect: 0.6
  property bool isNew: false

  property string name: ""
  property var zones: []
  property int selected: 0
  // Drags change `zones` in place so the zone under the pointer survives; this tells bindings to re-read it.
  property int revision: 0
  // Typing replaces a field's text binding, so the percent fields are rebuilt when the zone changes another way.
  property int fieldLoads: 0
  property bool fieldsValid: true

  readonly property bool valid: root.fieldsValid && root.revision >= 0
    && Presets.sanitizeLayouts([{ name: root.name, zones: root.zones }]).length === 1
  readonly property var selectedZone: root.revision >= 0 ? root.zones[root.selected] || null : null

  signal done(var layout)
  signal deleted()
  signal cancelled()

  function load(layout, isNew) {
    root.isNew = isNew
    root.name = layout.name
    nameField.text = layout.name
    root.zones = layout.zones.map(function(z) { return z.slice() })
    root.selected = 0
    root.fieldsValid = true
    root.revision++
    root.fieldLoads++
    Qt.callLater(function() { root.focusZone(0) })
  }

  function focusZone(index) {
    var item = zoneRepeater.itemAt(index)
    if (item) item.forceActiveFocus()
  }

  function select(index) {
    if (index === root.selected) return
    root.selected = index
    root.fieldsValid = true
    root.fieldLoads++
  }

  function setZone(index, zone) {
    root.zones[index] = zone
    root.revision++
  }

  // List changes rebuild the zone items; focus follows the zone they concern.
  function setZones(next, focusIndex) {
    if (!next) return
    root.zones = next
    root.selected = Presets.clamp(focusIndex, 0, next.length - 1)
    root.fieldsValid = true
    root.revision++
    root.fieldLoads++
    Qt.callLater(function() { root.focusZone(root.selected) })
  }

  function split(direction) {
    root.setZones(Presets.splitZone(root.zones, root.selected, direction), root.selected)
  }

  function addZone() {
    if (root.zones.length < Presets.MAX_ZONES)
      root.setZones(root.zones.concat([[0.25, 0.25, 0.5, 0.5]]), root.zones.length)
  }

  function removeZone() {
    if (root.zones.length <= 1) return
    var next = root.zones.slice()
    next.splice(root.selected, 1)
    root.setZones(next, root.selected)
  }

  function finish() {
    if (root.valid) root.done({ name: root.name.trim(), zones: Presets.sanitizeLayouts([{ zones: root.zones }])[0].zones })
  }

  // Inside the editor these finish or cancel the layout, not the whole settings screen.
  Keys.onEscapePressed: function(event) { root.cancelled(); event.accepted = true }
  Keys.onReturnPressed: function(event) { root.finish(); event.accepted = true }
  Keys.onEnterPressed: function(event) { root.finish(); event.accepted = true }

  spacing: Style.spacing.md

  component Label: Text {
    textFormat: Text.PlainText
    color: Commons.Color.menu.text
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.body
    verticalAlignment: Text.AlignVCenter
  }

  Header {
    icon: Icons.edit
    title: root.strings.t(root.isNew ? "editor.newTitle" : "editor.title")
    hint: "Esc"
  }

  SectionTitle {
    topPadding: Style.space(6)
    text: root.strings.t("editor.zones")
    trailing: root.strings.t("editor.zonesHint")
  }

  Rectangle {
    id: canvas
    width: parent.width
    height: Math.round(width * root.aspect)
    radius: Style.cornerRadius
    color: "transparent"
    border.width: 1
    border.color: Qt.rgba(Commons.Color.menu.text.r, Commons.Color.menu.text.g, Commons.Color.menu.text.b, 0.25)

    // The snap grid, faint, so drags have something to land on.
    Repeater {
      model: Presets.GRID - 1
      Rectangle {
        required property int index
        visible: (index + 1) % 2 === 0
        x: (index + 1) / Presets.GRID * canvas.width
        width: 1
        height: canvas.height
        color: Qt.rgba(Commons.Color.menu.text.r, Commons.Color.menu.text.g, Commons.Color.menu.text.b, (index + 1) % 6 === 0 ? 0.12 : 0.05)
      }
    }
    Repeater {
      model: Presets.GRID - 1
      Rectangle {
        required property int index
        visible: (index + 1) % 2 === 0
        y: (index + 1) / Presets.GRID * canvas.height
        width: canvas.width
        height: 1
        color: Qt.rgba(Commons.Color.menu.text.r, Commons.Color.menu.text.g, Commons.Color.menu.text.b, (index + 1) % 6 === 0 ? 0.12 : 0.05)
      }
    }

    Repeater {
      id: zoneRepeater
      model: root.zones.length

      Rectangle {
        id: zoneItem
        required property int index
        readonly property var zone: root.revision >= 0 ? root.zones[index] || [0, 0, 0, 0] : [0, 0, 0, 0]
        readonly property bool selected: index === root.selected
        readonly property real inset: 2

        x: zone[0] * canvas.width + inset
        y: zone[1] * canvas.height + inset
        width: Math.max(1, zone[2] * canvas.width - inset * 2)
        height: Math.max(1, zone[3] * canvas.height - inset * 2)
        // The selected zone is drawn over the others so its edges can be grabbed where zones overlap.
        z: selected ? 1 : 0
        radius: Math.max(0, Style.cornerRadius - 1)
        color: selected ? Qt.rgba(Commons.Color.menu.selectedText.r, Commons.Color.menu.selectedText.g, Commons.Color.menu.selectedText.b, 0.3)
          : Commons.Color.menu.selectedBackground
        border.width: selected ? 2 : 1
        border.color: selected ? Commons.Color.menu.selectedText
          : Qt.rgba(Commons.Color.menu.text.r, Commons.Color.menu.text.g, Commons.Color.menu.text.b, 0.35)

        activeFocusOnTab: true
        onActiveFocusChanged: if (activeFocus) root.select(index)

        // Arrows move the zone a grid step; with Shift they move its right or bottom edge. Delete removes it.
        Keys.onPressed: function(event) {
          var step = 1 / Presets.GRID
          var dx = event.key === Qt.Key_Left ? -step : event.key === Qt.Key_Right ? step : 0
          var dy = event.key === Qt.Key_Up ? -step : event.key === Qt.Key_Down ? step : 0
          if (dx || dy) {
            var resize = (event.modifiers & Qt.ShiftModifier) !== 0
            root.setZone(index, Presets.dragZone(zone, resize ? { right: dx !== 0, bottom: dy !== 0 } : {}, dx, dy))
            root.fieldLoads++
            event.accepted = true
          } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
            root.removeZone()
            event.accepted = true
          }
        }

        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: String(zoneItem.index + 1)
          color: zoneItem.selected ? Commons.Color.menu.selectedText : Commons.Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.heading
        }

        // A focus ring for keyboard users, inside the zone's own border.
        Rectangle {
          anchors.fill: parent
          anchors.margins: 3
          visible: zoneItem.activeFocus
          color: "transparent"
          radius: Math.max(0, parent.radius - 2)
          border.width: 1
          border.color: Commons.Color.menu.selectedText
        }

        MouseArea {
          id: dragArea
          anchors.fill: parent
          hoverEnabled: true
          preventStealing: true
          readonly property real grip: Math.min(Style.space(8), zoneItem.width / 3, zoneItem.height / 3)
          property var edges: ({})
          property var hoverEdges: ({})
          property var start: null
          property point pressAt

          function edgesAt(mouse) {
            return { left: mouse.x < grip, right: mouse.x > width - grip, top: mouse.y < grip, bottom: mouse.y > height - grip }
          }

          cursorShape: {
            var e = pressed ? edges : hoverEdges
            if ((e.left && e.top) || (e.right && e.bottom)) return Qt.SizeFDiagCursor
            if ((e.right && e.top) || (e.left && e.bottom)) return Qt.SizeBDiagCursor
            if (e.left || e.right) return Qt.SizeHorCursor
            if (e.top || e.bottom) return Qt.SizeVerCursor
            return pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
          }

          onPressed: function(mouse) {
            zoneItem.forceActiveFocus()
            edges = edgesAt(mouse)
            start = zoneItem.zone.slice()
            pressAt = mapToItem(canvas, mouse.x, mouse.y)
          }
          onPositionChanged: function(mouse) {
            if (!pressed) {
              hoverEdges = edgesAt(mouse)
              return
            }
            var at = mapToItem(canvas, mouse.x, mouse.y)
            root.setZone(zoneItem.index, Presets.dragZone(start, edges, (at.x - pressAt.x) / canvas.width, (at.y - pressAt.y) / canvas.height))
          }
          onReleased: root.fieldLoads++
        }
      }
    }
  }

  // The selected zone as percentages of the screen.
  Row {
    spacing: Style.space(14)

    Repeater {
      model: root.fieldLoads >= 0 ? ["x", "y", "width", "height"] : []

      Row {
        required property string modelData
        required property int index
        spacing: Style.spacing.xs

        Label { height: parent.height; text: root.strings.t("editor." + modelData) }
        TextField {
          id: percentField
          width: Style.space(64)
          text: root.selectedZone ? Presets.percent(root.selectedZone[index]) : ""
          horizontalAlignment: TextInput.AlignHCenter
          validator: DoubleValidator { bottom: 0; top: 100; decimals: 2; notation: DoubleValidator.StandardNotation }
          onTextEdited: {
            var parts = root.selectedZone.map(function(v) { return v * 100 })
            parts[index] = text
            var zone = Presets.zoneFromPercent(parts[0], parts[1], parts[2], parts[3])
            root.fieldsValid = zone !== null
            if (zone) root.setZone(root.selected, zone)
          }
        }
        Label { height: parent.height; text: "%" }
      }
    }
  }

  Flow {
    width: parent.width
    spacing: Style.spacing.sm

    Button { focusable: true; bordered: true; iconText: Icons.splitColumns; text: root.strings.t("editor.splitColumns"); onClicked: root.split("columns") }
    Button { focusable: true; bordered: true; iconText: Icons.splitRows; text: root.strings.t("editor.splitRows"); onClicked: root.split("rows") }
    Button { focusable: true; bordered: true; iconText: Icons.add; text: root.strings.t("editor.addZone"); enabled: root.zones.length < Presets.MAX_ZONES; onClicked: root.addZone() }
    Button { focusable: true; bordered: true; iconText: Icons.remove; text: root.strings.t("editor.removeZone"); enabled: root.zones.length > 1; onClicked: root.removeZone() }
  }

  Row {
    width: parent.width
    spacing: Style.spacing.sm

    Label { id: nameLabel; height: nameField.height; text: root.strings.t("editor.name") }
    TextField {
      id: nameField
      width: parent.width - nameLabel.width - parent.spacing
      placeholderText: root.strings.t("editor.namePlaceholder")
      maximumLength: 40
      onTextEdited: root.name = text
    }
  }

  Item {
    width: parent.width
    height: doneRow.height

    Button {
      anchors.left: parent.left
      visible: !root.isNew
      focusable: true
      bordered: true
      iconText: Icons.remove
      foreground: Commons.Color.urgent
      text: root.strings.t("editor.delete")
      onClicked: root.deleted()
    }

    Row {
      id: doneRow
      anchors.right: parent.right
      spacing: Style.spacing.sm

      Label {
        height: parent.height
        visible: !root.valid
        text: root.strings.t("editor.invalid")
        color: Commons.Color.urgent
      }
      // Cancel and Done share one size, the larger of the two.
      Button {
        id: cancelButton
        focusable: true
        bordered: true
        iconText: Icons.close
        text: root.strings.t("settings.cancel")
        width: Math.max(cancelButton.implicitWidth, doneButton.implicitWidth)
        height: Math.max(cancelButton.implicitHeight, doneButton.implicitHeight)
        onClicked: root.cancelled()
      }
      Button {
        id: doneButton
        width: cancelButton.width
        height: cancelButton.height
        focusable: true
        bordered: true
        selected: true
        iconText: Icons.done
        text: root.strings.t("editor.done")
        enabled: root.valid
        onClicked: root.finish()
      }
    }
  }
}
