// OmaSizer's settings live in its entry in ~/.config/omarchy/shell.json:
// { "id": "omasizer", "presets": [{ label, width, height }], "center": true, "clamp": true,
//   "titlebarClick": true, "borderClick": true, "swap": true,
//   "layouts": [{ name, zones: [[x, y, width, height], ...], starred }],
//   "outerGap": 10, "innerGap": 10, "shortcut": "SUPER + ALT + Z", "moveKeys": "SUPER + CTRL + ALT" }
// The gaps are logical pixels: from the screen edges, and between two zones.
// Until they are saved, zones use Hyprland's own gaps_out and twice gaps_in.
// Zones are fractions (0 to 1) of the monitor's usable area.

var DEFAULTS = [
  { label: "4:3", width: 800, height: 600 },
  { label: "4:3", width: 1024, height: 768 },
  { label: "16:9", width: 1280, height: 720 },
  { label: "16:9", width: 1600, height: 900 },
  { label: "16:9", width: 1920, height: 1080 },
  { label: "21:9", width: 2560, height: 1080 }
]

// Side by side is "columns", stacked is "rows".
var DEFAULT_LAYOUTS = [
  { name: "50:50 columns", zones: [[0, 0, 0.5, 1], [0.5, 0, 0.5, 1]] },
  { name: "50:50 rows", zones: [[0, 0, 1, 0.5], [0, 0.5, 1, 0.5]] },
  { name: "33:33:33 columns", zones: [[0, 0, 1 / 3, 1], [1 / 3, 0, 1 / 3, 1], [2 / 3, 0, 1 / 3, 1]] },
  { name: "33:33:33 rows", zones: [[0, 0, 1, 1 / 3], [0, 1 / 3, 1, 1 / 3], [0, 2 / 3, 1, 1 / 3]] },
  { name: "75:25 main + side", zones: [[0, 0, 0.75, 1], [0.75, 0, 0.25, 1]] },
  { name: "25:75 side + main", zones: [[0, 0, 0.25, 1], [0.25, 0, 0.75, 1]] },
  { name: "25:50:25 main + sides", zones: [[0, 0, 0.25, 1], [0.25, 0, 0.5, 1], [0.75, 0, 0.25, 1]] },
  { name: "Quadrants", zones: [[0, 0, 0.5, 0.5], [0.5, 0, 0.5, 0.5], [0, 0.5, 0.5, 0.5], [0.5, 0.5, 0.5, 0.5]] },
  { name: "Fullscreen", zones: [[0, 0, 1, 1]] }
]

// How many layouts the menu shows in a row: four, or five when that leaves fewer
// gaps in the last row (nine layouts fill 5 + 4 rather than 4 + 4 + 1).
function menuColumns(count) {
  var empty = function(columns) { return (columns - count % columns) % columns }
  return empty(5) < empty(4) ? 5 : 4
}

var MAX_LAYOUTS = 20
var MAX_ZONES = 16
var MAX_PRESETS = 50
var MAX_GAP = 200

// The keyboard shortcut that opens the menu: modifiers and one key, in Hyprland's
// "SUPER + ALT + Z" form, or "" for none. The service registers it at runtime.
var DEFAULT_SHORTCUT = "SUPER + ALT + Z"
// Marks OmaSizer's own bindings in `hyprctl binds`; hypr/omasizer.lua uses the same text.
var BIND_DESCRIPTION = "OmaSizer: open the menu"
var MOVE_DESCRIPTION = "OmaSizer: move between zones"
// The modifiers that, with an arrow key, move the focused window to the next zone
// of its layout: "" for none. The service binds all four arrows with them.
var DEFAULT_MOVE_KEYS = "SUPER + CTRL + ALT"
var ARROWS = ["LEFT", "RIGHT", "UP", "DOWN"]
var MODIFIERS = ["SUPER", "CTRL", "ALT", "SHIFT"]
var MODIFIER_MASKS = { SUPER: 64, CTRL: 4, ALT: 8, SHIFT: 1 }
var SHORTCUT_KEY = /^(?:[A-Z0-9]|F(?:[1-9]|1[0-2])|LEFT|RIGHT|UP|DOWN|SPACE|RETURN|HOME|END|PAGEUP|PAGEDOWN|INSERT|DELETE|SLASH|BACKSLASH|COMMA|PERIOD|MINUS|EQUAL|GRAVE|SEMICOLON|APOSTROPHE|BRACKETLEFT|BRACKETRIGHT)$/

// A shortcut in canonical form ("super+alt+z" becomes "SUPER + ALT + Z"), or null
// unless it is one or more distinct modifiers and one supported key. The result is
// also what gets written into the Lua the service hands Hyprland, so nothing else passes.
function normalizeShortcut(value) {
  if (typeof value !== "string") return null
  var parts = value.toUpperCase().split("+").map(function(p) { return p.trim() })
  var key = parts.pop()
  if (!key || !SHORTCUT_KEY.test(key) || parts.length === 0) return null
  for (var i = 0; i < parts.length; i++)
    if (MODIFIERS.indexOf(parts[i]) < 0 || parts.indexOf(parts[i]) !== i) return null
  return MODIFIERS.filter(function(m) { return parts.indexOf(m) >= 0 }).concat([key]).join(" + ")
}

// Modifiers alone in canonical form ("ctrl+super" becomes "SUPER + CTRL"), or null.
function normalizeModifiers(value) {
  var combo = typeof value === "string" ? normalizeShortcut(value + " + LEFT") : null
  return combo ? combo.slice(0, -" + LEFT".length) : null
}

// What already uses one of the four arrows with `modifiers`, or null when all are free.
function moveConflict(binds, modifiers) {
  for (var i = 0; modifiers && i < ARROWS.length; i++) {
    var holder = bindConflict(binds, modifiers + " + " + ARROWS[i])
    if (holder) return holder
  }
  return null
}

// Whether `shortcut` is one of the arrows OmaSizer binds with `moveKeys`: both would be bound,
// and changing either later would unbind the other.
function ownConflict(shortcut, moveKeys) {
  var combo = normalizeShortcut(shortcut)
  return !!combo && !!moveKeys && ARROWS.some(function(a) { return combo === moveKeys + " + " + a })
}

// What already uses `shortcut` among `hyprctl -j binds`, as a short description, or
// null when it is free. OmaSizer's own bindings and mouse bindings don't count.
function bindConflict(binds, shortcut) {
  var combo = normalizeShortcut(shortcut)
  if (!combo || !Array.isArray(binds)) return null
  var parts = combo.split(" + ")
  var key = parts.pop()
  var mask = parts.reduce(function(sum, m) { return sum + MODIFIER_MASKS[m] }, 0)
  for (var i = 0; i < binds.length; i++) {
    var b = binds[i] || {}
    if (b.mouse || b.submap || b.description === BIND_DESCRIPTION || b.description === MOVE_DESCRIPTION) continue
    if (Number(b.modmask) === mask && String(b.key).toUpperCase() === key)
      return String(b.description || [b.dispatcher, b.arg].filter(Boolean).join(" ") || "another shortcut").slice(0, 80)
  }
  return null
}

// A whole number of pixels from 0 to 200, or null when unset.
function gap(value) {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 && value <= MAX_GAP ? value : null
}
var MAX_SIZE = 16384

function validSize(value) {
  var n = Number(value)
  return Number.isInteger(n) && n >= 1 && n <= MAX_SIZE
}

// Keep the presets with whole positive sizes, with labels cut to 40 characters.
function sanitize(list) {
  if (!Array.isArray(list)) return []
  var presets = []
  for (var i = 0; i < list.length && presets.length < MAX_PRESETS; i++) {
    var p = list[i] || {}
    if (!validSize(p.width) || !validSize(p.height)) continue
    presets.push({ label: String(p.label || "").slice(0, 40), width: Number(p.width), height: Number(p.height) })
  }
  return presets
}

// A zone is [x, y, width, height] with every edge inside the screen and a real size.
function validZone(zone) {
  if (!Array.isArray(zone) || zone.length !== 4) return false
  for (var i = 0; i < 4; i++)
    if (typeof zone[i] !== "number" || !isFinite(zone[i]) || zone[i] < 0 || zone[i] > 1) return false
  return zone[2] > 0 && zone[3] > 0 && zone[0] + zone[2] <= 1.0001 && zone[1] + zone[3] <= 1.0001
}

// Keep the layouts with 1 to 16 valid zones, with names cut to 40 characters.
// Exactly one is starred: the first marked, or else the first.
function sanitizeLayouts(list) {
  if (!Array.isArray(list)) return []
  var layouts = []
  for (var i = 0; i < list.length && layouts.length < MAX_LAYOUTS; i++) {
    var layout = list[i] || {}
    var zones = Array.isArray(layout.zones) ? layout.zones : []
    if (zones.length < 1 || zones.length > MAX_ZONES || !zones.every(validZone)) continue
    layouts.push({ name: String(layout.name || "").slice(0, 40), zones: zones.map(function(z) { return z.slice() }), starred: layout.starred === true })
  }
  var star = Math.max(0, starredIndex(layouts))
  return layouts.map(function(l, i) {
    var kept = { name: l.name, zones: l.zones }
    if (i === star) kept.starred = true
    return kept
  })
}

// The starred layout's index, or -1 when none is.
function starredIndex(layouts) {
  for (var i = 0; i < layouts.length; i++)
    if (layouts[i] && layouts[i].starred === true) return i
  return -1
}

// A copy of `layouts` with only the one at `index` starred.
function starLayout(layouts, index) {
  return layouts.map(function(l, i) {
    var next = { name: l.name, zones: l.zones }
    if (i === index) next.starred = true
    return next
  })
}

// A copy of `list` with the item at `from` moved to `to`; the same list when either is out of range.
function moveItem(list, from, to) {
  if (from === to || from < 0 || to < 0 || from >= list.length || to >= list.length) return list
  var next = list.slice()
  next.splice(to, 0, next.splice(from, 1)[0])
  return next
}

function defaultLayouts() {
  return sanitizeLayouts(DEFAULT_LAYOUTS)
}

// Zone editing. Edges snap to a grid of 24ths, which holds halves, thirds, quarters,
// sixths and eighths exactly; a zone is never narrower or shorter than one step.
var GRID = 24
var MIN_ZONE = 1 / GRID

function snap(value) {
  return Math.round(value * GRID) / GRID
}

function clamp(value, low, high) {
  return Math.max(low, Math.min(high, value))
}

// Six decimals keep saved zones short while still meeting exactly at thirds.
function tidy(zone) {
  return zone.map(function(v) { return Math.round(v * 1e6) / 1e6 })
}

// Drag a zone by (dx, dy), fractions of the screen. `edges` names the edges
// being dragged ({ left, right, top, bottom }); with none, the whole zone moves.
function dragZone(zone, edges, dx, dy) {
  var left = zone[0], top = zone[1], right = zone[0] + zone[2], bottom = zone[1] + zone[3]
  if (!edges.left && !edges.right && !edges.top && !edges.bottom) {
    var x = clamp(snap(left + dx), 0, 1 - zone[2])
    var y = clamp(snap(top + dy), 0, 1 - zone[3])
    return tidy([x, y, zone[2], zone[3]])
  }
  if (edges.left) left = clamp(snap(left + dx), 0, right - MIN_ZONE)
  if (edges.right) right = clamp(snap(right + dx), left + MIN_ZONE, 1)
  if (edges.top) top = clamp(snap(top + dy), 0, bottom - MIN_ZONE)
  if (edges.bottom) bottom = clamp(snap(bottom + dy), top + MIN_ZONE, 1)
  return tidy([left, top, right - left, bottom - top])
}

// Split zone `index` into two halves, side by side ("columns") or stacked
// ("rows"); null when the halves would be smaller than a grid step.
function splitZone(zones, index, direction) {
  var z = zones[index]
  if (!z || zones.length >= MAX_ZONES) return null
  var halves = direction === "columns"
    ? [[z[0], z[1], z[2] / 2, z[3]], [z[0] + z[2] / 2, z[1], z[2] / 2, z[3]]]
    : [[z[0], z[1], z[2], z[3] / 2], [z[0], z[1] + z[3] / 2, z[2], z[3] / 2]]
  if (halves[0][2] < MIN_ZONE - 1e-9 || halves[0][3] < MIN_ZONE - 1e-9) return null
  return zones.slice(0, index).concat(halves.map(tidy), zones.slice(index + 1))
}

// A zone typed as percentages, or null unless it fits the screen and is at least a grid step.
function zoneFromPercent(x, y, width, height) {
  var zone = [x, y, width, height].map(function(v) { return Number(v) / 100 })
  if (!validZone(zone) || zone[2] < MIN_ZONE - 1e-9 || zone[3] < MIN_ZONE - 1e-9) return null
  return tidy(zone)
}

function percent(value) {
  return String(Math.round(value * 10000) / 100)
}

function fromShellConfig(text) {
  var entry = {}
  try {
    var plugins = JSON.parse(text).plugins
    for (var i = 0; Array.isArray(plugins) && i < plugins.length; i++)
      if (plugins[i] && plugins[i].id === "omasizer") entry = plugins[i]
  } catch (e) {}

  return {
    presets: Array.isArray(entry.presets) ? sanitize(entry.presets) : DEFAULTS.slice(),
    center: entry.center !== false,
    clamp: entry.clamp !== false,
    titlebarClick: entry.titlebarClick !== false,
    borderClick: entry.borderClick !== false,
    swap: entry.swap !== false,
    layouts: Array.isArray(entry.layouts) ? sanitizeLayouts(entry.layouts) : defaultLayouts(),
    shortcut: entry.shortcut === "" ? "" : normalizeShortcut(entry.shortcut) || DEFAULT_SHORTCUT,
    moveKeys: entry.moveKeys === "" ? "" : normalizeModifiers(entry.moveKeys) || DEFAULT_MOVE_KEYS,
    outerGap: gap(entry.outerGap),
    innerGap: gap(entry.innerGap)
  }
}
