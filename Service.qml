import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "Presets.js" as Presets

// Gives Hyprland OmaSizer's keyboard shortcut and right-click hook at runtime, so
// nobody edits their config: when the shell starts, after every Hyprland config
// reload (which drops runtime binds), and when the shortcut setting changes. A
// shortcut that something else already uses is left to it, and the user is told once.
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
  property bool registerAgain: false

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")
  readonly property string shellConfigPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omarchy/shell.json"

  function conflictFor(shortcut) {
    return Presets.bindConflict(root.binds, shortcut)
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
    var holder = wanted ? root.conflictFor(wanted) : null
    root.blockedShortcut = holder ? wanted : ""
    root.blockedBy = holder || ""

    if (holder && root.notifiedShortcut !== wanted) {
      root.notifiedShortcut = wanted
      Quickshell.execDetached(["omarchy-notification-send", "-g", "\u{F030C}",
        "OmaSizer shortcut not set",
        wanted + " is already used by “" + holder + "”. Choose another in OmaSizer's settings."])
    }

    // Both values go into Lua source, so each must be exactly the safe form checked here.
    var hook = root.pluginDir + "hypr/omasizer.lua"
    var shortcut = holder ? "" : wanted
    if (!/^[A-Za-z0-9_\/.\-]+$/.test(hook) || (shortcut !== "" && Presets.normalizeShortcut(shortcut) !== shortcut)) {
      console.warn("omasizer: refusing to load the Hyprland hook from", hook)
      return
    }
    hookLoader.command = ["hyprctl", "eval", "omasizer_shortcut = \"" + shortcut + "\" dofile(\"" + hook + "\")"]
    hookLoader.running = true
  }

  FileView {
    path: root.shellConfigPath
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      var next = Presets.fromShellConfig(text())
      var changed = !root.settingsLoaded || next.shortcut !== root.settings.shortcut
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

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && String(event.name) === "configreloaded") root.register()
    }
  }
}
