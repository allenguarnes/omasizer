// node test/presets.test.js
const fs = require("fs"), vm = require("vm"), assert = require("assert")
const ctx = {}
vm.runInNewContext(fs.readFileSync(__dirname + "/../Presets.js", "utf8"), ctx)
const plain = value => JSON.parse(JSON.stringify(value))
const read = config => plain(ctx.fromShellConfig(typeof config === "string" ? config : JSON.stringify(config)))

// No entry, a broken file, or an entry without presets: the defaults.
for (const config of ["not json", {}, { plugins: [{ id: "other", presets: [] }] }, { plugins: [{ id: "omasizer" }] }]) {
  const settings = read(config)
  assert.strictEqual(settings.presets.length, 6)
  assert.strictEqual(settings.center, true)
  assert.strictEqual(settings.clamp, true)
  assert.strictEqual(settings.titlebarClick, true)
  assert.strictEqual(settings.borderClick, true)
  assert.strictEqual(settings.layouts.length, 8)
  assert.strictEqual(settings.outerGap, null)
  assert.strictEqual(settings.innerGap, null)
}

// Gaps are whole pixels from 0 to 200; anything else is unset.
assert.strictEqual(read({ plugins: [{ id: "omasizer", outerGap: 0, innerGap: 24 }] }).outerGap, 0)
assert.strictEqual(read({ plugins: [{ id: "omasizer", outerGap: 0, innerGap: 24 }] }).innerGap, 24)
for (const bad of [-1, 201, 2.5, "x", null, "", true])
  assert.strictEqual(read({ plugins: [{ id: "omasizer", outerGap: bad }] }).outerGap, null, String(bad))

// The default layouts each tile the whole screen with no overlap.
for (const layout of read({}).layouts) {
  const area = layout.zones.reduce((sum, z) => sum + z[2] * z[3], 0)
  assert(Math.abs(area - 1) < 1e-9, layout.name)
  for (const a of layout.zones) for (const b of layout.zones) if (a !== b)
    assert(a[0] + a[2] <= b[0] + 1e-9 || b[0] + b[2] <= a[0] + 1e-9 || a[1] + a[3] <= b[1] + 1e-9 || b[1] + b[3] <= a[1] + 1e-9, layout.name)
}

// Saved layouts win; ones with a zone off the screen, no zones, or a non-number are dropped.
assert.deepStrictEqual(read({ plugins: [{ id: "omasizer", layouts: [
  { name: "Ok", zones: [[0, 0, 1, 1]] }, { name: "Off", zones: [[0.5, 0, 0.6, 1]] }, { name: "Empty", zones: [] },
  { name: "Text", zones: [[0, 0, "1", 1]] }, { zones: [[0, 0, 0, 1]] }
] }] }).layouts, [{ name: "Ok", zones: [[0, 0, 1, 1]] }])
assert.deepStrictEqual(read({ plugins: [{ id: "omasizer", layouts: [] }] }).layouts, [])

// A saved entry wins, with invalid presets dropped and an empty list kept empty.
assert.deepStrictEqual(read({ plugins: [{ id: "omasizer", center: false, clamp: false, titlebarClick: false, borderClick: false, presets: [
  { width: 800, height: 600 }, { width: "x", height: 1 }, { width: -5, height: 5 }, { width: 1.5, height: 2 },
  { width: 20000, height: 5 }, { label: "Big", width: "1920", height: 1080 }
] }] }), { presets: [{ label: "", width: 800, height: 600 }, { label: "Big", width: 1920, height: 1080 }], center: false, clamp: false, titlebarClick: false, borderClick: false, layouts: read({}).layouts, outerGap: null, innerGap: null, shortcut: "SUPER + ALT + Z" })
assert.deepStrictEqual(read({ plugins: [{ id: "omasizer", presets: [] }] }).presets, [])
assert.strictEqual(plain(ctx.sanitize(Array(80).fill({ width: 1, height: 1 }))).length, 50)

// Editing: moves and edges snap to 24ths and stay on screen; zones keep a minimum size.
const near = (got, want) => assert(got.every((v, i) => Math.abs(v - want[i]) < 1e-6), JSON.stringify(got) + " != " + JSON.stringify(want))
const none = {}
near(plain(ctx.dragZone([0, 0, 0.5, 1], none, 0.26, 0)), [0.25, 0, 0.5, 1])
near(plain(ctx.dragZone([0, 0, 0.5, 1], none, 0.9, 0.3)), [0.5, 0, 0.5, 1])
near(plain(ctx.dragZone([0, 0, 0.5, 1], none, -0.3, -0.3)), [0, 0, 0.5, 1])
near(plain(ctx.dragZone([0, 0, 0.5, 1], { right: true }, -0.17, 0)), [0, 0, 1 / 3, 1])
near(plain(ctx.dragZone([0, 0, 0.5, 1], { right: true }, -0.9, 0)), [0, 0, 1 / 24, 1])
near(plain(ctx.dragZone([0.5, 0.5, 0.5, 0.5], { left: true, top: true }, -0.5, -0.5)), [0, 0, 1, 1])
near(plain(ctx.dragZone([0.5, 0, 0.5, 1], { left: true }, 0.9, 0)), [23 / 24, 0, 1 / 24, 1])

const split = plain(ctx.splitZone([[0, 0, 1, 1], [0, 0, 0.5, 0.5]], 0, "columns"))
assert.strictEqual(split.length, 3)
near(split[0], [0, 0, 0.5, 1]); near(split[1], [0.5, 0, 0.5, 1]); near(split[2], [0, 0, 0.5, 0.5])
near(plain(ctx.splitZone([[0, 0, 1, 1]], 0, "rows"))[1], [0, 0.5, 1, 0.5])
assert.strictEqual(ctx.splitZone([[0, 0, 1 / 24, 1]], 0, "columns"), null)
assert.strictEqual(ctx.splitZone(Array(16).fill([0, 0, 1, 1]), 0, "rows"), null)

near(plain(ctx.zoneFromPercent("25", "0", "50", "100")), [0.25, 0, 0.5, 1])
assert.strictEqual(ctx.zoneFromPercent(60, 0, 50, 100), null)
assert.strictEqual(ctx.zoneFromPercent(0, 0, 1, 100), null)
assert.strictEqual(ctx.zoneFromPercent("x", 0, 50, 100), null)
assert.strictEqual(ctx.percent(1 / 3), "33.33")

// Reordering moves one item and keeps the rest in order; out-of-range moves change nothing.
assert.deepStrictEqual(plain(ctx.moveItem(["a", "b", "c", "d"], 0, 2)), ["b", "c", "a", "d"])
assert.deepStrictEqual(plain(ctx.moveItem(["a", "b", "c", "d"], 3, 0)), ["d", "a", "b", "c"])
assert.deepStrictEqual(plain(ctx.moveItem(["a", "b"], 1, 2)), ["a", "b"])
assert.deepStrictEqual(plain(ctx.moveItem(["a", "b"], -1, 0)), ["a", "b"])
assert.deepStrictEqual(plain(ctx.defaultLayouts()), read({}).layouts)

// Shortcuts: canonical form, a strict whitelist, and conflicts read from `hyprctl -j binds`.
assert.strictEqual(read({}).shortcut, "SUPER + ALT + Z")
assert.strictEqual(read({ plugins: [{ id: "omasizer", shortcut: "" }] }).shortcut, "")
assert.strictEqual(read({ plugins: [{ id: "omasizer", shortcut: "ctrl+super+F5" }] }).shortcut, "SUPER + CTRL + F5")
assert.strictEqual(read({ plugins: [{ id: "omasizer", shortcut: "Z" }] }).shortcut, "SUPER + ALT + Z")
for (const bad of ["Z", "SUPER", "SUPER + SUPER + Z", "HYPER + Z", "SUPER + ALT + Z + X", 'SUPER + "); os.exit() --', "SUPER + mouse:272", 42, null])
  assert.strictEqual(ctx.normalizeShortcut(bad), null, String(bad))
const binds = [
  { modmask: 72, key: "Z", description: "OmaSizer: open the menu" },
  { modmask: 64, key: "Return", description: "Terminal" },
  { modmask: 0, key: "mouse:273", mouse: true },
  { modmask: 76, key: "Z", description: "", dispatcher: "exec", arg: "zoom" },
  { modmask: 64, key: "T", submap: "resize", description: "In a submap" }
]
assert.strictEqual(ctx.bindConflict(binds, "SUPER + ALT + Z"), null)
assert.strictEqual(ctx.bindConflict(binds, "SUPER + RETURN"), "Terminal")
assert.strictEqual(ctx.bindConflict(binds, "SUPER + CTRL + ALT + Z"), "exec zoom")
assert.strictEqual(ctx.bindConflict(binds, "SUPER + T"), null)
assert.strictEqual(ctx.bindConflict(binds, ""), null)

console.log("ok")
