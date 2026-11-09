import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "Presets.js" as Presets

// Gives Hyprland OmaSizer's keyboard shortcut, arrow keys and right-click hook at
// runtime, so nobody edits their config: when the shell starts, after every
// Hyprland config reload (which drops runtime binds), and when those settings
// change. Keys that something else already uses are left to it, and the user is told once.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property var settings: Presets.fromShellConfig("")
  property bool settingsLoaded: false
  // `hyprctl -j binds` as last read, for the conflict check here and in settings.
  property var binds: []
  // The shortcut the user chose but OmaSizer left unbound, and what holds it.
  property string blockedShortcut: ""
  property string blockedBy: ""
  property string notifiedShortcut: ""
  // The same for the arrow keys' modifiers.
  property string blockedMove: ""
  property string blockedMoveBy: ""
  property string notifiedMove: ""
  property bool registerAgain: false
  // Marks the binds this instance makes, so its teardown never removes a newer instance's.
  readonly property string owner: String(Date.now()) + String(Math.floor(Math.random() * 1e6))
  readonly property string hookPath: root.pluginDir + "hypr/omasizer.lua"

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")
  readonly property string shellConfigPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omarchy/shell.json"

  function conflictFor(shortcut) {
    return Presets.bindConflict(root.binds, shortcut)
  }

  function moveConflictFor(modifiers) {
    return Presets.moveConflict(root.binds, modifiers)
  }

  function refreshBinds() {
    if (!bindsReader.running) bindsReader.running = true
  }

  // Read the binds, then hand Hyprland the hook with the shortcut to use. Calls that
  // arrive while one is running are folded into one more run afterwards.
  function register() {
    if (!root.settingsLoaded) return
    if (bindsReader.running || hookLoader.running) {
      root.registerAgain = true
      return
    }
    root.registerAgain = false
    bindsReader.registering = true
    bindsReader.running = true
  }

  function loadHook() {
    var wanted = root.settings.shortcut
    var holder = wanted ? root.conflictFor(wanted)
      || (Presets.ownConflict(wanted, root.settings.moveKeys) ? Presets.MOVE_DESCRIPTION : null) : null
    root.blockedShortcut = holder ? wanted : ""
    root.blockedBy = holder || ""

    if (holder && root.notifiedShortcut !== wanted) {
      root.notifiedShortcut = wanted
      Quickshell.execDetached(["omarchy-notification-send", "-g", "\u{F030C}",
        "OmaSizer shortcut not set",
        wanted + " is already used by “" + holder + "”. Choose another in OmaSizer's settings."])
    }

    var wantedMove = root.settings.moveKeys
    var moveHolder = wantedMove ? root.moveConflictFor(wantedMove) : null
    root.blockedMove = moveHolder ? wantedMove : ""
    root.blockedMoveBy = moveHolder || ""

    if (moveHolder && root.notifiedMove !== wantedMove) {
      root.notifiedMove = wantedMove
      Quickshell.execDetached(["omarchy-notification-send", "-g", "\u{F030C}",
        "OmaSizer arrow keys not set",
        wantedMove + " + arrows are already used by “" + moveHolder + "”. Choose other keys in OmaSizer's settings."])
    }

    // These values go into Lua source, so each must be exactly the safe form checked here.
    var hook = root.hookPath
    var shortcut = holder ? "" : wanted
    var move = moveHolder ? "" : wantedMove
    if (!/^[A-Za-z0-9_\/.\-]+$/.test(hook) || (shortcut !== "" && Presets.normalizeShortcut(shortcut) !== shortcut)
        || (move !== "" && Presets.normalizeModifiers(move) !== move)) {
      console.warn("omasizer: refusing to load the Hyprland hook from", hook)
      return
    }
    var clicks = "{ titlebar = " + (root.settings.titlebarClick !== false) + ", border = " + (root.settings.borderClick !== false) + " }"
    hookLoader.command = ["hyprctl", "eval", "omasizer_unload = nil omasizer_owner = \"" + root.owner + "\" omasizer_shortcut = \"" + shortcut
      + "\" omasizer_clicks = " + clicks + " omasizer_move = \"" + move + "\" dofile(\"" + hook + "\")"]
    hookLoader.running = true
  }

  FileView {
    path: root.shellConfigPath
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      var next = Presets.fromShellConfig(text())
      var changed = !root.settingsLoaded || next.shortcut !== root.settings.shortcut || next.moveKeys !== root.settings.moveKeys
        || next.titlebarClick !== root.settings.titlebarClick || next.borderClick !== root.settings.borderClick
      root.settings = next
      root.settingsLoaded = true
      if (changed) root.register()
    }
    onLoadFailed: {
      root.settingsLoaded = true
      root.register()
    }
  }

  Process {
    id: bindsReader
    property bool registering: false
    command: ["hyprctl", "-j", "binds"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var list = JSON.parse(text)
          if (Array.isArray(list)) root.binds = list
        } catch (e) {}
      }
    }
    onExited: {
      if (registering) {
        registering = false
        root.loadHook()
      } else if (root.registerAgain) {
        // A register that arrived during a plain read (Settings refreshing the list).
        root.register()
      }
    }
  }

  Process {
    id: hookLoader
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "ok") console.warn("omasizer: hyprctl eval said:", text.trim())
    }
    onExited: if (root.registerAgain) root.register()
  }

  // Turning OmaSizer off, or the shell going away, takes its keys and right-click hook
  // with it; Hyprland would otherwise keep them until its config reloads.
  Component.onDestruction: {
    if (/^[A-Za-z0-9_\/.\-]+$/.test(root.hookPath))
      Quickshell.execDetached(["hyprctl", "eval", "omasizer_unload = \"" + root.owner + "\" dofile(\"" + root.hookPath + "\")"])
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && String(event.name) === "configreloaded") root.register()
    }
  }
}
