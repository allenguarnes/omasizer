-- lua test/hypr.test.lua
local M = dofile((arg[0]:match("^(.*)/test/[^/]+$") or ".") .. "/hypr/omasizer.lua")

local function window(x, y, w, h, extra)
  local win = { at = { x = x, y = y }, size = { x = w, y = h }, visible = true, mapped = true, hidden = false,
    floating = true, fullscreen = 0, tags = { "omarchy-floating-workspace" }, address = "0x" .. x }
  for k, v in pairs(extra or {}) do win[k] = v end
  return win
end

local a = window(100, 100, 400, 300)
assert(M.zone(a, 200, 200, 30, 10) == "content")
assert(M.zone(a, 200, 85, 30, 10) == "titlebar")
assert(M.zone(a, 495, 75, 30, 10) == "titlebar")   -- the buttons at the bar's right end
assert(M.zone(a, 95, 405, 30, 10) == "border")     -- bottom-left resize corner
assert(M.zone(a, 505, 200, 30, 10) == "border")
assert(M.zone(a, 515, 200, 30, 10) == nil)
assert(M.zone(a, 200, 65, 30, 10) == "border")     -- above the titlebar

assert(M.target({ a }, 200, 85, 30, 10) == a)
assert(select(2, M.target({ a }, 200, 85, 30, 10)) == "titlebar")
assert(select(2, M.target({ a }, 505, 405, 30, 10)) == "border")
assert(M.target({ a }, 200, 200, 30, 10) == nil)   -- right-clicks inside the window are the app's

-- A window above covering the titlebar wins; one below does not.
local b = window(150, 50, 400, 300)
assert(M.target({ a, b }, 200, 85, 30, 10) == nil)
assert(M.target({ b, a }, 200, 85, 30, 10) == a)

-- Tiled and fullscreen windows have no titlebar or grab band, but still cover what is below.
local tiled = window(100, 100, 400, 300, { floating = false, tags = {} })
assert(M.target({ tiled }, 200, 85, 30, 10) == nil)
assert(M.target({ a, tiled }, 200, 150, 30, 10) == nil)
local full = window(0, 0, 1920, 1200, { fullscreen = 2 })
assert(M.target({ a, full }, 200, 85, 30, 10) == nil)

-- Floating windows off the floating workspace have a border band but no titlebar.
local plain = window(100, 100, 400, 300, { tags = {} })
assert(M.target({ plain }, 200, 85, 30, 10) == nil)
assert(M.target({ plain }, 200, 95, 30, 10) == plain)

-- Hidden windows are skipped.
assert(M.target({ window(100, 100, 400, 300, { visible = false }) }, 200, 85, 30, 10) == nil)

-- A press that turns into a drag (a border resize) is not a click.
assert(M.is_click({ x = 10, y = 10 }, { x = 14, y = 6 }))
assert(not M.is_click({ x = 10, y = 10 }, { x = 15, y = 10 }))
assert(not M.is_click({ x = 10, y = 10 }, { x = 10, y = 40 }))

-- Registering again changes only what differs, and unbinds only OmaSizer's own shortcut.
local calls = {}
hl = {
  bind = function(keys) calls[#calls + 1] = "bind " .. keys end,
  unbind = function(keys) calls[#calls + 1] = "unbind " .. keys end,
  dsp = { exec_cmd = function(command) return command end },
}
local function register(shortcut)
  calls = {}
  M.register(shortcut)
  return table.concat(calls, ", ")
end
_G.omasizer_state = nil
assert(register("SUPER + ALT + Z") == "bind mouse:273, bind mouse:273, bind SUPER + ALT + Z")
assert(register("SUPER + ALT + Z") == "")
assert(register("SUPER + CTRL + F5") == "unbind SUPER + ALT + Z, bind SUPER + CTRL + F5")
assert(register("") == "unbind SUPER + CTRL + F5")
assert(register("") == "")
assert(register("SUPER + O") == "bind SUPER + O")
hl = nil

print("ok")
