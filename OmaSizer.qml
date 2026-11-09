import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Presets.js" as Presets
import "Icons.js" as Icons

// The preset menu. Opened by the keybind it is centered and acts on the focused
// window; opened by a right-click (hypr/omasizer.lua) it sits at the cursor and
// acts on the window clicked, with a payload of { address, zone, x, y, width, height }.
// The arrow keys summon it with { move: direction }: it moves the focused window
// to the next zone of its layout and shows nothing.
Item {
  id: root

  property var shell: null
  property var manifest: null
  // OmaSizer's service, handed over by the shell; it registers the keyboard shortcut.
  property var service: null

  property bool opened: false
  property string view: "menu"
  property var settings: Presets.fromShellConfig("")
  property int selectedIndex: 0

  // The right-clicked window, and the cursor in global layout coordinates.
  property string address: ""
  property bool atCursor: false
  property real cursorX: 0
  property real cursorY: 0
  property int windowWidth: 0
  property int windowHeight: 0

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")
  readonly property string shellConfigPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omarchy/shell.json"
  // Every zone of every layout, flattened in reading order: each is one stop for the selection.
  readonly property var zoneItems: {
    var items = []
    var layouts = root.settings.layouts
    for (var l = 0; l < layouts.length; l++)
      for (var z = 0; z < layouts[l].zones.length; z++)
        items.push({ layout: l, zone: z, rect: layouts[l].zones[z] })
    return items
  }
  // The selection runs through the zones, then the presets, then Settings….
  readonly property int zoneStart: 0
  readonly property int presetStart: root.zoneItems.length
  readonly property int settingsIndex: root.presetStart + root.settings.presets.length
  readonly property int rowCount: root.settingsIndex + 1
  readonly property var selectedZone: root.selectedIndex < root.presetStart ? root.zoneItems[root.selectedIndex - root.zoneStart] : null
  readonly property int rowHeight: Style.font.title + Style.spacing.controlPaddingY * 2
  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int layoutColumns: Presets.menuColumns(root.settings.layouts.length)
  // A fifth column of layouts widens the menu by one thumbnail, so thumbnails keep their size.
  readonly property real menuWidth: Style.space(400) + (root.layoutColumns - 4)
    * ((Style.space(400) - root.contentMargin * 2 - Style.spacing.lg * 3) / 4 + Style.spacing.lg)
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", Commons.Color.menu.border, Math.max(1, Style.space(2)))

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") || ({}) } catch (e) { payload = ({}) }

    if (["left", "right", "up", "down"].indexOf(payload.move) >= 0) {
      // Pressed while the menu or settings are open (say, to record new keys), it changes nothing.
      if (root.opened) return
      // Read now: the overlay may have loaded for this keypress, before the file's own load arrived.
      var current = Presets.fromShellConfig(settingsFile.text())
      var spec = { layouts: current.layouts.map(function(l) { return l.zones }),
        starred: Math.max(0, Presets.starredIndex(current.layouts)) }
      root.dismiss()
      // Detached, so it outlives the overlay; bin/omasizer runs one at a time and caps each run at 5 s.
      if (spec.layouts.length) Quickshell.execDetached([root.pluginDir + "bin/omasizer", "--move", payload.move, JSON.stringify(spec)])
      return
    }

    // hypr/omasizer.lua sends every titlebar and border right-click; the settings decide which open the menu.
    if ((payload.zone === "titlebar" && !root.settings.titlebarClick)
        || (payload.zone === "border" && !root.settings.borderClick)) {
      root.dismiss()
      return
    }

    // Hyprland addresses are hex; anything else is not passed on to the resize command.
    root.address = /^0x[0-9a-f]+$/.test(String(payload.address || "")) ? payload.address : ""
    root.atCursor = root.address !== "" && typeof payload.x === "number" && typeof payload.y === "number"
      && isFinite(payload.x) && isFinite(payload.y)
    root.cursorX = root.atCursor ? payload.x : 0
    root.cursorY = root.atCursor ? payload.y : 0
    root.windowWidth = Presets.validSize(payload.width) ? payload.width : 0
    root.windowHeight = Presets.validSize(payload.height) ? payload.height : 0

    root.view = "menu"
    root.selectedIndex = 0
    hoverGate.reset()
    root.opened = true
    if (payload.view === "settings") root.openSettings()
    else Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "omasizer")
  }

  function activate(index) {
    if (index === root.settingsIndex) {
      root.openSettings()
      return
    }
    var command = [root.pluginDir + "bin/omasizer"]
    var item = index < root.presetStart ? root.zoneItems[index - root.zoneStart] : null
    var preset = item ? null : root.settings.presets[index - root.presetStart]
    // The layout goes along, so the window's arrow keys keep to it.
    if (item) command = command.concat(["--layout", JSON.stringify(root.settings.layouts[item.layout].zones), "--zone"],
      item.rect.map(function(v) { return v.toFixed(6) }))
    else if (preset) command = command.concat([String(preset.width), String(preset.height)])
    else return
    if (root.address) command.push(root.address)
    root.dismiss()
    // Detached, so it outlives the overlay; bin/omasizer runs one at a time and caps each run at 5 s.
    Quickshell.execDetached(command)
  }

  function openSettings() {
    settingsView.newWidth = root.windowWidth || 1280
    settingsView.newHeight = root.windowHeight || 720
    settingsView.load(root.settings)
    root.view = "settings"
    Qt.callLater(function() { settingsView.focusFirst() })
  }

  function save(next) {
    if (!root.shell || typeof root.shell.updateEntryInline !== "function") return
    // It returns false when nothing changed, which is still a save.
    root.shell.updateEntryInline("omasizer", next)
    root.settings = next
    root.view = "menu"
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function move(delta) {
    root.selectedIndex = (root.selectedIndex + delta + root.rowCount) % root.rowCount
  }

  FileView {
    id: settingsFile
    path: root.shellConfigPath
    // A move can arrive the moment the overlay loads, before the file would load on its own.
    blockLoading: true
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.settings = Presets.fromShellConfig(text())
    onLoadFailed: root.settings = Presets.fromShellConfig("")
  }

  PointerMoveGate { id: hoverGate; referenceItem: card }

  OverlayWindow {
    id: panel
    shown: root.opened
    WlrLayershell.namespace: "omasizer"

    // A right-click menu reads as part of the window it came from, so it skips the scrim.
    Rectangle {
      anchors.fill: parent
      color: root.atCursor && root.view === "menu" ? "transparent" : Commons.Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      readonly property var monitor: panel.targetMonitor
      readonly property bool placeAtCursor: root.atCursor && root.view === "menu" && !!monitor

      width: Math.min(root.view === "settings" ? Style.space(580) : root.menuWidth, panel.width - Style.gapsOut * 2)
      height: root.contentMargin * 2 + (root.view === "settings" ? settingsView.implicitHeight : menuColumn.implicitHeight)
      x: placeAtCursor
        ? Math.max(Style.gapsOut, Math.min(root.cursorX - monitor.x, panel.width - width - Style.gapsOut))
        : (panel.width - width) / 2
      y: placeAtCursor
        ? Math.max(Style.gapsOut, Math.min(root.cursorY - monitor.y, panel.height - height - Style.gapsOut))
        : (panel.height - height) / 2
      radius: Style.cornerRadius
      color: Commons.Color.menu.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: root.view === "menu"

        Keys.onPressed: function(event) {
          var digit = event.key - Qt.Key_1
          if (event.key === Qt.Key_Escape) root.dismiss()
          else if (event.key === Qt.Key_Up || event.key === Qt.Key_K || event.key === Qt.Key_Left || event.key === Qt.Key_H || event.key === Qt.Key_Backtab) root.move(-1)
          else if (event.key === Qt.Key_Down || event.key === Qt.Key_J || event.key === Qt.Key_Right || event.key === Qt.Key_L || event.key === Qt.Key_Tab) root.move(1)
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.activate(root.selectedIndex)
          else if (event.key === Qt.Key_S) root.openSettings()
          else if (digit >= 0 && digit <= 8 && digit < root.settings.presets.length) root.activate(root.presetStart + digit)
          else return
          event.accepted = true
        }
      }

      // One selectable line: a keycap, an icon or the outline of a size, a label, and a detail at the end.
      component Row_: Rectangle {
        id: menuRow
        property int rowIndex: 0
        property string key: ""
        property string icon: ""
        // A size preset, drawn as a small outline of its shape.
        property real shapeWidth: 0
        property real shapeHeight: 0
        property string label: ""
        property string detail: ""
        readonly property bool selected: rowIndex === root.selectedIndex
        readonly property color tint: selected ? Commons.Color.menu.selectedText : Commons.Color.menu.text

        width: parent.width
        height: root.rowHeight
        radius: Style.cornerRadius
        color: selected ? Commons.Color.menu.selectedBackground : "transparent"

        Row {
          id: lead
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.controlPaddingX
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(10)

          Keycap {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(implicitWidth, Style.space(20))
            text: menuRow.key
            lit: menuRow.selected
            opacity: menuRow.key !== "" ? 1 : 0
          }

          Item {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.font.iconLarge
            height: Style.font.iconLarge

            Text {
              anchors.centerIn: parent
              visible: menuRow.icon !== ""
              textFormat: Text.PlainText
              text: menuRow.icon
              color: menuRow.tint
              font.family: Style.font.family
              font.pixelSize: Style.font.icon
            }

            Rectangle {
              readonly property real fit: menuRow.shapeWidth > 0
                ? Math.min(parent.width / menuRow.shapeWidth, parent.height * 0.7 / menuRow.shapeHeight) : 0
              anchors.centerIn: parent
              visible: menuRow.shapeWidth > 0
              width: Math.round(menuRow.shapeWidth * fit)
              height: Math.max(3, Math.round(menuRow.shapeHeight * fit))
              radius: 2
              color: "transparent"
              border.width: 1.5
              border.color: menuRow.tint
              opacity: menuRow.selected ? 1 : 0.7
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: menuRow.label
            color: menuRow.tint
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.title
          }
        }

        Text {
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.controlPaddingX
          anchors.left: lead.right
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignRight
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: menuRow.detail
          color: menuRow.tint
          opacity: menuRow.selected ? 1 : 0.6
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.title
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          onPositionChanged: function(mouse) { if (hoverGate.moved(menuRow, mouse)) root.selectedIndex = menuRow.rowIndex }
          onClicked: root.activate(menuRow.rowIndex)
        }
      }

      Column {
        id: menuColumn
        visible: root.view === "menu"
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.sm

        Header {
          icon: Icons.app
          title: "OmaSizer"
          hint: "Esc"
        }

        SectionTitle {
          visible: root.zoneItems.length > 0
          topPadding: Style.space(6)
          text: strings.t("zones")
          trailing: root.selectedZone ? root.settings.layouts[root.selectedZone.layout].name : ""
          trailingAccent: true
        }

        // Each layout is drawn as a small screen; picking one of its zones places the window there.
        Flow {
          id: layoutFlow
          visible: root.zoneItems.length > 0
          readonly property int columns: root.layoutColumns
          readonly property real thumbWidth: Math.floor((width - spacing * (columns - 1)) / columns)
          width: parent.width
          spacing: Style.spacing.lg

          Repeater {
            model: root.settings.layouts

            LayoutThumb {
              required property var modelData
              required property int index
              // Zones before this layout's, to map its zones onto the flat selection.
              readonly property int firstItem: {
                var count = 0
                for (var l = 0; l < index; l++) count += root.settings.layouts[l].zones.length
                return root.zoneStart + count
              }

              width: layoutFlow.thumbWidth
              height: Math.round(width * panel.height / Math.max(1, panel.width))
              zones: modelData.zones
              selectedZone: root.selectedIndex - firstItem
              active: selectedZone >= 0 && selectedZone < modelData.zones.length
              zonesInteractive: true
              onZoneHovered: function(zone, item, mouse) { if (hoverGate.moved(item, mouse)) root.selectedIndex = firstItem + zone }
              onZoneClicked: function(zone) { root.activate(firstItem + zone) }
            }
          }
        }

        SectionTitle {
          topPadding: Style.space(10)
          text: strings.t("sizes")
          trailing: root.settings.presets.length ? "" : strings.t("empty")
        }

        Repeater {
          model: root.settings.presets

          Row_ {
            required property var modelData
            required property int index
            rowIndex: root.presetStart + index
            key: index < 9 ? String(index + 1) : ""
            shapeWidth: modelData.width
            shapeHeight: modelData.height
            label: modelData.label
            detail: modelData.width + " × " + modelData.height
          }
        }

        Item { width: 1; height: Style.space(4) }

        Row_ {
          rowIndex: root.settingsIndex
          key: "S"
          icon: Icons.settings
          label: strings.t("openSettings")
        }
      }

      Settings {
        id: settingsView
        visible: root.view === "settings"
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        strings: strings
        aspect: panel.height / Math.max(1, panel.width)
        maxHeight: panel.height - Style.gapsOut * 2 - root.contentMargin * 2
        service: root.service
        onSaved: function(next) { root.save(next) }
        onCancelled: {
          root.view = "menu"
          Qt.callLater(function() { keyCatcher.forceActiveFocus() })
        }
        Keys.onEscapePressed: cancelled()
      }
    }
  }
}
