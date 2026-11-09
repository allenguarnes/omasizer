import QtQuick
import QtQuick.Window
import QtQuick.Controls as QQC
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Presets.js" as Presets
import "Icons.js" as Icons

// Edit the preset list, the layouts and the options. Emits `saved` with the whole
// settings entry, or `cancelled`; the caller stores it.
Column {
  id: root

  property var strings: null
  // A new preset starts at the size of the window the menu was opened for.
  property int newWidth: 1280
  property int newHeight: 720

  property var draft: []
  property bool center: true
  property bool clamp: true
  property bool titlebarClick: true
  property bool borderClick: true
  property bool swap: true
  property string shortcut: ""
  // OmaSizer's service: it registers the shortcut and knows what else is bound.
  property var service: null
  readonly property string shortcutHolder: !root.service || !root.shortcut ? ""
    : root.service.conflictFor(root.shortcut) || (Presets.ownConflict(root.shortcut, root.moveKeys) ? Presets.MOVE_DESCRIPTION : "")
  // The modifiers that move a window between zones with the arrows, and what already uses them.
  property string moveKeys: ""
  readonly property string moveHolder: root.service && root.moveKeys ? root.service.moveConflictFor(root.moveKeys) || "" : ""
  property var layouts: []
  // The tallest the form may be before it scrolls.
  property real maxHeight: 100000
  // Height over width of the screen, for drawing layouts.
  property real aspect: 0.6
  // The layout open in the editor: its index, -1 for a new one, -2 for none.
  property int editingIndex: -2
  readonly property bool editing: root.editingIndex !== -2
  // The layout under the pointer or keyboard focus in the list, named in its header.
  property string layoutHint: ""
  // While a thumbnail is dragged, the layout it would land on.
  property int dropIndex: -1
  // The layout being dragged (-1 for none), where the pointer is in the form, and where it grabbed the thumbnail.
  property int dragFrom: -1
  property point dragPoint
  property point dragGrab
  readonly property bool layoutsAreDefault: JSON.stringify(root.layouts) === JSON.stringify(Presets.defaultLayouts())
  // Zone gaps as typed. Until they are saved they start from Hyprland's gaps_out
  // and twice gaps_in, Omarchy's spacing; once saved they are OmaSizer's own.
  property string outerGap: ""
  property string innerGap: ""
  // Typing replaces a field's text binding, so the gap fields are rebuilt whenever their values are reloaded.
  property int gapLoads: 0

  // Bumped by field edits, which change the draft in place: notifying `draft` would rebuild the rows and drop focus.
  property int edits: 0
  readonly property bool valid: root.edits >= 0 && Presets.sanitize(root.draft).length === root.draft.length
    && Presets.gap(Number(root.outerGap)) !== null && Presets.gap(Number(root.innerGap)) !== null
    && root.outerGap !== "" && root.innerGap !== ""
  readonly property int fieldWidth: Style.space(64)

  signal saved(var settings)
  signal cancelled()

  function trySave() {
    if (root.valid) root.saved({ presets: Presets.sanitize(root.draft), center: root.center, clamp: root.clamp,
      titlebarClick: root.titlebarClick, borderClick: root.borderClick, swap: root.swap, shortcut: root.shortcut, moveKeys: root.moveKeys, layouts: root.layouts,
      outerGap: Number(root.outerGap), innerGap: Number(root.innerGap) })
  }

  // Tab walks every field, button and switch; Escape cancels; Enter saves. A text
  // field passes Enter on after emitting `accepted`, so Enter is handled here only, once.
  // Shift+Tab can arrive as Tab with Shift held rather than as Backtab.
  Keys.onTabPressed: function(event) { root.Window.activeFocusItem.nextItemInFocusChain(!(event.modifiers & Qt.ShiftModifier)).forceActiveFocus() }
  Keys.onBacktabPressed: root.Window.activeFocusItem.nextItemInFocusChain(false).forceActiveFocus()
  Keys.onReturnPressed: root.trySave()
  Keys.onEnterPressed: root.trySave()

  function load(settings) {
    root.draft = settings.presets.map(function(p) { return { label: p.label, width: p.width, height: p.height } })
    root.center = settings.center
    root.clamp = settings.clamp
    root.titlebarClick = settings.titlebarClick
    root.borderClick = settings.borderClick
    root.swap = settings.swap
    root.shortcut = settings.shortcut
    root.moveKeys = settings.moveKeys
    if (root.service) root.service.refreshBinds()
    root.layouts = settings.layouts
    root.editingIndex = -2
    root.outerGap = settings.outerGap === null ? "" : String(settings.outerGap)
    root.innerGap = settings.innerGap === null ? "" : String(settings.innerGap)
    root.gapLoads++
    if (settings.outerGap === null || settings.innerGap === null) hyprlandGaps.running = true
  }

  function setField(index, key, value) {
    root.draft[index][key] = key === "label" ? value : Number(value)
    root.edits++
  }

  function moveRow(index, delta) {
    var next = root.draft.slice()
    var target = index + delta
    if (target < 0 || target >= next.length) return
    var row = next[index]
    next[index] = next[target]
    next[target] = row
    root.draft = next
    root.focusRow(target, delta < 0 ? "up" : "down")
  }

  function removeRow(index) {
    var next = root.draft.slice()
    next.splice(index, 1)
    root.draft = next
    if (next.length) root.focusRow(Math.min(index, next.length - 1), "remove")
    else addButton.forceActiveFocus()
  }

  function addRow() {
    if (root.draft.length >= Presets.MAX_PRESETS) return
    root.draft = root.draft.concat([{ label: "", width: root.newWidth, height: root.newHeight }])
    root.focusRow(root.draft.length - 1, "label")
  }

  // Changing the list rebuilds the rows, which drops focus; put it back on the
  // same control of the row it concerns, or the row's label if that control is now disabled.
  function focusRow(index, control) {
    Qt.callLater(function() {
      var row = rowRepeater.itemAt(index)
      if (row) row.focusControl(control)
    })
  }

  function editLayout(index) {
    if (index < 0 && root.layouts.length >= Presets.MAX_LAYOUTS) return
    root.editingIndex = index
    editor.load(index >= 0 ? root.layouts[index] : { name: "", zones: [[0, 0, 1, 1]] }, index < 0)
  }

  // Back to the settings list, with focus on the layout just edited, or New layout.
  function closeEditor(index) {
    root.editingIndex = -2
    Qt.callLater(function() {
      var thumb = index >= 0 ? layoutRepeater.itemAt(index) : null
      if (thumb) thumb.forceActiveFocus()
      else newLayoutButton.forceActiveFocus()
    })
  }

  function moveLayout(from, to) {
    var next = Presets.moveItem(root.layouts, from, to)
    if (next === root.layouts) return
    root.layouts = next
    Qt.callLater(function() { var thumb = layoutRepeater.itemAt(to); if (thumb) thumb.forceActiveFocus() })
  }

  function layoutIndexAt(point) {
    for (var i = 0; i < layoutRepeater.count; i++) {
      var thumb = layoutRepeater.itemAt(i)
      if (point.x >= thumb.x && point.x < thumb.x + thumb.width && point.y >= thumb.y && point.y < thumb.y + thumb.height) return i
    }
    return -1
  }

  // Star the layout at `index`, the one the arrow keys use for windows not yet placed from a layout.
  function starLayout(index) {
    root.layouts = Presets.starLayout(root.layouts, index)
    Qt.callLater(function() { var thumb = layoutRepeater.itemAt(index); if (thumb) thumb.forceActiveFocus() })
  }

  // Restoring only changes the list here; Save keeps it and Cancel undoes it.
  function restoreLayouts() {
    root.layouts = Presets.defaultLayouts()
    Qt.callLater(function() { var thumb = layoutRepeater.itemAt(0); if (thumb) thumb.forceActiveFocus() })
  }

  function focusFirst() {
    if (rowRepeater.count > 0) rowRepeater.itemAt(0).focusControl("label")
    else addButton.forceActiveFocus()
  }

  // Keep whatever has keyboard focus in the preset list scrolled into view.
  function reveal(item) {
    for (var p = item; p; p = p.parent) {
      if (p === form) {
        var top = item.mapToItem(form, 0, 0).y
        if (top < flick.contentY) flick.contentY = top
        else if (top + item.height > flick.contentY + flick.height) flick.contentY = top + item.height - flick.height
        return
      }
    }
  }

  // Hyprland reports gaps as CSS-style sides; the first side stands for all of them.
  Process {
    id: hyprlandGaps
    command: ["bash", "-c", "hyprctl getoption general:gaps_out -j | jq -r '.css // .int'; hyprctl getoption general:gaps_in -j | jq -r '.css // .int'"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = text.trim().split("\n")
        var outer = parseInt(lines[0], 10), inner = parseInt(lines[1], 10)
        if (root.outerGap === "") root.outerGap = String(Presets.gap(outer) === null ? 10 : outer)
        if (root.innerGap === "") root.innerGap = String(Presets.gap(inner * 2) === null ? 10 : inner * 2)
        root.gapLoads++
      }
    }
  }

  Connections {
    target: root.Window.window
    function onActiveFocusItemChanged() {
      if (root.visible && root.Window.activeFocusItem) root.reveal(root.Window.activeFocusItem)
    }
  }

  spacing: Style.spacing.md

  // A setting that is on or off: its label, and a switch bound to root[key].
  component SwitchRow: Item {
    id: switchRow
    property string key: ""
    property string text: ""
    width: root.width
    height: toggle.height

    Label {
      anchors.left: parent.left
      anchors.right: toggle.left
      anchors.verticalCenter: parent.verticalCenter
      text: switchRow.text
      elide: Text.ElideRight
    }

    ToggleSwitch {
      id: toggle
      anchors.right: parent.right
      checked: root[switchRow.key]
      onToggled: root[switchRow.key] = !root[switchRow.key]
      // The kit's switch has no keyboard handling; Tab reaches it and Space or Enter flips it.
      activeFocusOnTab: true
      hasCursor: activeFocus
      Keys.onSpacePressed: toggled()
      Keys.onReturnPressed: toggled()
      Keys.onEnterPressed: toggled()
    }
  }

  component Label: Text {
    textFormat: Text.PlainText
    color: Commons.Color.menu.text
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.body
    verticalAlignment: Text.AlignVCenter
  }

  // The whole form scrolls once it is taller than the screen allows.
  Flickable {
    id: flick
    width: parent.width
    height: Math.min(form.implicitHeight, root.maxHeight)
    contentHeight: form.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    visible: !root.editing
    QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

  Column {
    id: form
    width: flick.width
    spacing: Style.spacing.md

    Header {
      icon: Icons.settings
      title: root.strings.t("settings.title")
      hint: "Esc"
    }

    SectionTitle {
      topPadding: Style.space(6)
      text: root.strings.t("settings.presets")
    }

    Column {
      id: rows
      width: parent.width
      spacing: Style.spacing.sm

      Repeater {
        id: rowRepeater
        model: root.draft

        Row {
          id: row
          required property var modelData
          required property int index
          spacing: Style.spacing.sm

          function focusControl(control) {
            var target = { label: labelField, up: upButton, down: downButton, remove: removeButton }[control] || labelField
            if (!target.enabled) target = control === "up" ? downButton : upButton
            if (!target.enabled) target = labelField
            target.forceActiveFocus()
          }

          TextField {
            id: labelField
            width: rows.width - root.fieldWidth * 2 - sizeX.width - buttons.width - row.spacing * 4
            text: row.modelData.label
            placeholderText: root.strings.t("settings.labelPlaceholder")
            maximumLength: 40
            onTextEdited: root.setField(row.index, "label", text)
          }

          TextField {
            width: root.fieldWidth
            text: String(row.modelData.width)
            horizontalAlignment: TextInput.AlignHCenter
            validator: IntValidator { bottom: 1; top: Presets.MAX_SIZE }
            onTextEdited: root.setField(row.index, "width", text)
          }

          Label { id: sizeX; height: parent.height; text: "×" }

          TextField {
            width: root.fieldWidth
            text: String(row.modelData.height)
            horizontalAlignment: TextInput.AlignHCenter
            validator: IntValidator { bottom: 1; top: Presets.MAX_SIZE }
            onTextEdited: root.setField(row.index, "height", text)
          }

          Row {
            id: buttons
            Button { id: upButton; focusable: true; iconText: Icons.up; tooltipText: root.strings.t("settings.moveUp"); enabled: row.index > 0; opacity: enabled ? 1 : 0.3; onClicked: root.moveRow(row.index, -1) }
            Button { id: downButton; focusable: true; iconText: Icons.down; tooltipText: root.strings.t("settings.moveDown"); enabled: row.index < root.draft.length - 1; opacity: enabled ? 1 : 0.3; onClicked: root.moveRow(row.index, 1) }
            Button { id: removeButton; focusable: true; iconText: Icons.remove; tooltipText: root.strings.t("settings.remove"); onClicked: root.removeRow(row.index) }
          }
        }
      }
    }

    Button {
      id: addButton
      focusable: true
      iconText: Icons.add
      text: root.strings.t("settings.add")
      bordered: true
      enabled: root.draft.length < Presets.MAX_PRESETS
      onClicked: root.addRow()
    }

    SwitchRow { key: "center"; text: root.strings.t("settings.center") }
    SwitchRow { key: "clamp"; text: root.strings.t("settings.clamp") }

    SectionTitle {
      topPadding: Style.space(10)
      text: root.strings.t("settings.layouts")
      trailing: root.layoutHint || root.strings.t("settings.layoutsHint")
      trailingAccent: root.layoutHint !== ""
    }

    // Each layout as a small screen; click it, or Tab to it and press Enter, to edit it.
    Flow {
      id: layoutList
      width: parent.width
      spacing: Style.spacing.sm
      readonly property int columns: 6
      readonly property real thumbWidth: Math.floor((width - spacing * (columns - 1)) / columns)

      Repeater {
        id: layoutRepeater
        model: root.layouts

        LayoutThumb {
          id: layoutThumb
          required property var modelData
          required property int index
          width: layoutList.thumbWidth
          height: Math.round(width * root.aspect)
          zones: modelData.zones
          starShown: true
          starred: modelData.starred === true
          onStarClicked: root.starLayout(index)
          highlighted: activeFocus || (thumbMouse.containsMouse && root.dropIndex < 0) || index === root.dropIndex
          // Its place stays faint while a copy follows the pointer.
          opacity: thumbMouse.dragging ? 0.25 : 1
          activeFocusOnTab: true
          onHighlightedChanged: {
            if (highlighted) root.layoutHint = modelData.name || root.strings.t("settings.unnamedLayout")
            else if (!activeFocus && !thumbMouse.containsMouse) root.layoutHint = ""
          }
          // Alt and an arrow move the layout one place earlier or later; S stars it.
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_S && !event.modifiers) {
              root.starLayout(index)
              event.accepted = true
              return
            }
            if (!(event.modifiers & Qt.AltModifier)) return
            if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) root.moveLayout(index, index - 1)
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) root.moveLayout(index, index + 1)
            else return
            event.accepted = true
          }
          Keys.onSpacePressed: root.editLayout(index)
          Keys.onReturnPressed: root.editLayout(index)
          Keys.onEnterPressed: root.editLayout(index)

          // A click opens the layout; dragging it onto another layout moves it there.
          MouseArea {
            id: thumbMouse
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            cursorShape: dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            property bool dragging: false
            property bool dragged: false
            property point pressAt

            onPressed: function(mouse) {
              pressAt = Qt.point(mouse.x, mouse.y)
              dragging = false
              dragged = false
            }
            onPositionChanged: function(mouse) {
              if (!pressed) return
              if (!dragging && Math.abs(mouse.x - pressAt.x) + Math.abs(mouse.y - pressAt.y) > Style.space(6)) {
                dragging = true
                root.dragFrom = layoutThumb.index
                root.dragGrab = pressAt
              }
              if (dragging) {
                root.dragPoint = mapToItem(form, mouse.x, mouse.y)
                root.dropIndex = root.layoutIndexAt(mapToItem(layoutList, mouse.x, mouse.y))
              }
            }
            // Moving rebuilds the list and this thumbnail with it, so the drag state is cleared first.
            onReleased: {
              var target = dragging ? root.dropIndex : -1
              dragged = dragging
              dragging = false
              root.dropIndex = -1
              root.dragFrom = -1
              if (target >= 0) root.moveLayout(layoutThumb.index, target)
            }
            onCanceled: {
              dragging = false
              root.dropIndex = -1
              root.dragFrom = -1
            }
            onClicked: if (!dragged) root.editLayout(layoutThumb.index)
          }
        }
      }

    }

    Row {
      spacing: Style.spacing.sm

      Button {
        id: newLayoutButton
        focusable: true
        bordered: true
        iconText: Icons.add
        text: root.strings.t("settings.newLayout")
        enabled: root.layouts.length < Presets.MAX_LAYOUTS
        onClicked: root.editLayout(-1)
      }

      Button {
        focusable: true
        bordered: true
        iconText: Icons.restore
        text: root.strings.t("settings.restoreLayouts")
        enabled: !root.layoutsAreDefault
        opacity: enabled ? 1 : 0.4
        onClicked: root.restoreLayouts()
      }
    }

    SwitchRow { key: "swap"; text: root.strings.t("settings.swap") }

    SectionTitle {
      topPadding: Style.space(10)
      text: root.strings.t("settings.gaps")
    }

    Repeater {
      model: root.gapLoads >= 0 ? [
        { key: "outerGap", text: "settings.outerGap" },
        { key: "innerGap", text: "settings.innerGap" }
      ] : []

      Item {
        required property var modelData
        width: root.width
        height: gapField.height

        Label {
          anchors.left: parent.left
          anchors.right: gapField.left
          anchors.verticalCenter: parent.verticalCenter
          text: root.strings.t(modelData.text)
          elide: Text.ElideRight
        }

        Label {
          id: pxLabel
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.strings.t("settings.px")
          opacity: 0.6
        }

        TextField {
          id: gapField
          anchors.right: pxLabel.left
          anchors.rightMargin: Style.space(6)
          width: root.fieldWidth
          text: root[modelData.key]
          horizontalAlignment: TextInput.AlignHCenter
          validator: IntValidator { bottom: 0; top: Presets.MAX_GAP }
          onTextEdited: root[modelData.key] = text
        }
      }
    }

    SectionTitle {
      topPadding: Style.space(10)
      text: root.strings.t("settings.openMenu")
    }

    Item {
      width: root.width
      height: shortcutField.height

      Label {
        anchors.left: parent.left
        anchors.right: shortcutField.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.strings.t("settings.shortcut")
        elide: Text.ElideRight
      }

      ShortcutField {
        id: shortcutField
        anchors.right: defaultShortcut.left
        anchors.rightMargin: Style.spacing.sm
        shortcut: root.shortcut
        offText: root.strings.t("settings.shortcutOff")
        listeningText: root.strings.t("settings.shortcutListening")
        onEdited: function(next) { root.shortcut = next }
      }

      Button {
        id: defaultShortcut
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        focusable: true
        bordered: true
        iconText: Icons.restore
        tooltipText: root.strings.t("settings.shortcutDefault")
        enabled: root.shortcut !== Presets.DEFAULT_SHORTCUT
        opacity: enabled ? 1 : 0.4
        onClicked: root.shortcut = Presets.DEFAULT_SHORTCUT
      }
    }

    Label {
      width: parent.width
      wrapMode: Text.WordWrap
      font.pixelSize: Style.font.bodySmall
      color: root.shortcutHolder ? Commons.Color.urgent : Commons.Color.menu.text
      opacity: root.shortcutHolder ? 1 : 0.6
      text: root.shortcutHolder ? root.strings.t("settings.shortcutTaken").arg(root.shortcutHolder)
        : root.strings.t("settings.shortcutHint")
    }

    SwitchRow { key: "titlebarClick"; text: root.strings.t("settings.titlebarClick") }
    SwitchRow { key: "borderClick"; text: root.strings.t("settings.borderClick") }

    SectionTitle {
      topPadding: Style.space(10)
      text: root.strings.t("settings.moveZones")
    }

    Item {
      width: root.width
      height: moveField.height

      Label {
        anchors.left: parent.left
        anchors.right: moveField.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.strings.t("settings.moveKeys")
        elide: Text.ElideRight
      }

      ShortcutField {
        id: moveField
        anchors.right: defaultMove.left
        anchors.rightMargin: Style.spacing.sm
        arrows: true
        shortcut: root.moveKeys
        offText: root.strings.t("settings.shortcutOff")
        listeningText: root.strings.t("settings.moveListening")
        onEdited: function(next) { root.moveKeys = next }
      }

      Button {
        id: defaultMove
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        focusable: true
        bordered: true
        iconText: Icons.restore
        tooltipText: root.strings.t("settings.moveDefault")
        enabled: root.moveKeys !== Presets.DEFAULT_MOVE_KEYS
        opacity: enabled ? 1 : 0.4
        onClicked: root.moveKeys = Presets.DEFAULT_MOVE_KEYS
      }
    }

    Label {
      width: parent.width
      wrapMode: Text.WordWrap
      font.pixelSize: Style.font.bodySmall
      color: root.moveHolder ? Commons.Color.urgent : Commons.Color.menu.text
      opacity: root.moveHolder ? 1 : 0.6
      text: root.moveHolder ? root.strings.t("settings.moveTaken").arg(root.moveHolder)
        : root.strings.t("settings.moveHint")
    }

    Row {
      anchors.right: parent.right
      spacing: Style.spacing.sm

      Label {
        height: parent.height
        visible: !root.valid
        text: root.strings.t("settings.invalid")
        color: Commons.Color.urgent
      }
      // Cancel and Save share one size, the larger of the two.
      Button {
        id: cancelButton
        focusable: true
        bordered: true
        iconText: Icons.close
        text: root.strings.t("settings.cancel")
        width: Math.max(cancelButton.implicitWidth, saveButton.implicitWidth)
        height: Math.max(cancelButton.implicitHeight, saveButton.implicitHeight)
        onClicked: root.cancelled()
      }
      Button {
        id: saveButton
        width: cancelButton.width
        height: cancelButton.height
        focusable: true
        selected: true
        iconText: Icons.done
        text: root.strings.t("settings.save")
        bordered: true
        enabled: root.valid
        onClicked: root.trySave()
      }
    }
  }

    // The layout being dragged, following the pointer above the list. The Flickable's
    // content doesn't lay out its children, so it can sit anywhere over the form.
    LayoutThumb {
      visible: root.dragFrom >= 0 && root.dragFrom < root.layouts.length
      z: 10
      width: layoutList.thumbWidth
      height: Math.round(width * root.aspect)
      x: root.dragPoint.x - root.dragGrab.x
      y: root.dragPoint.y - root.dragGrab.y
      zones: visible ? root.layouts[root.dragFrom].zones : []
      highlighted: true
      opacity: 0.9
    }
  }

  LayoutEditor {
    id: editor
    width: parent.width
    visible: root.editing
    strings: root.strings
    aspect: root.aspect
    onDone: function(layout) {
      if (!root.editing) return
      var next = root.layouts.slice()
      var index = root.editingIndex
      if (index < 0) { next.push(layout); index = next.length - 1 }
      else next[index] = { name: layout.name, zones: layout.zones, starred: next[index].starred }
      root.layouts = Presets.sanitizeLayouts(next)
      root.closeEditor(index)
    }
    onDeleted: {
      if (!root.editing) return
      var next = root.layouts.slice()
      next.splice(root.editingIndex, 1)
      // Deleting the starred layout passes the star to the first.
      root.layouts = Presets.sanitizeLayouts(next)
      root.closeEditor(Math.min(root.editingIndex, next.length - 1))
    }
    onCancelled: if (root.editing) root.closeEditor(root.editingIndex)
  }
}
