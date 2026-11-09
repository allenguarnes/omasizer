-- lua test/hypr.test.lua
local M = dofile((arg[0]:match("^(.*)/test/[^/]+$") or ".") .. "/hypr/omasizer.lua")

local function window(x, y, w, h, extra)
  local win = { at = { x = x, y = y }, size = { x = w, y = h }, visible = true, mapped = true, hidden = false,
    floating = true, fullscreen = 0, tags = { "omarchy-floating-workspace" }, address = "0x" .. x,
    workspace = { id = 1, visible = true, special = false } }
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
assert(M.target({ full, a }, 200, 85, 30, 10) == nil)  -- a fullscreen window is above floating ones, whatever the order

-- Floating windows off the floating workspace have a border band but no titlebar.
local plain = window(100, 100, 400, 300, { tags = {} })
assert(M.target({ plain }, 200, 85, 30, 10) == nil)
assert(M.target({ plain }, 200, 95, 30, 10) == plain)

-- Windows on a workspace that isn't shown are skipped, though they report themselves visible.
local away = window(100, 100, 400, 300, { workspace = { id = 2, visible = false, special = false } })
assert(M.target({ away }, 200, 85, 30, 10) == nil)
assert(M.target({ window(100, 100, 400, 300, { pinned = true, workspace = { id = 2, visible = false } }) }, 200, 85, 30, 10) ~= nil)

-- Pinned windows and the shown special workspace stack above the rest, wherever they are listed.
local scratch = window(150, 50, 400, 300, { workspace = { id = -98, visible = true, special = true } })
assert(M.target({ scratch, a }, 200, 85, 30, 10) == nil)
local pip = window(150, 50, 400, 300, { pinned = true })
assert(M.target({ pip, scratch, a }, 200, 85, 30, 10) == nil)

-- An XWayland popup has no titlebar and no grab band; a titled XWayland window keeps both.
local popup = window(100, 100, 400, 300, { xwayland = true, tags = {} })
assert(M.target({ popup }, 200, 95, 30, 10) == nil)
assert(M.target({ window(100, 100, 400, 300, { xwayland = true }) }, 200, 85, 30, 10) ~= nil)

-- Hidden windows are skipped.
assert(M.target({ window(100, 100, 400, 300, { visible = false }) }, 200, 85, 30, 10) == nil)

-- The bar's reserved strip, on a 3200 x 2000 monitor at 5/3 scale (1920 x 1200 logical).
local mon = { x = 0, y = 0, width = 3200, height = 2000, scale = 5 / 3, transform = 0, reserved = { top = 26, left = 0, right = 0, bottom = 0 } }
assert(M.reserved_at(mon, 500, 10))
assert(not M.reserved_at(mon, 500, 26))
assert(not M.reserved_at(mon, 1919, 1199))
assert(M.reserved_at({ x = 1920, y = 0, width = 2000, height = 3200, scale = 5 / 3, transform = 1, reserved = { top = 0, left = 0, right = 30, bottom = 0 } }, 1920 + 1900, 500))

-- A press that turns into a drag (a border resize) is not a click.
assert(M.is_click({ x = 10, y = 10 }, { x = 14, y = 6 }))
assert(not M.is_click({ x = 10, y = 10 }, { x = 15, y = 10 }))
assert(not M.is_click({ x = 10, y = 10 }, { x = 10, y = 40 }))

-- Registering again changes only what differs, and unbinds only OmaSizer's own shortcut.
local calls = {}
hl = {
  bind = function(keys)
    calls[#calls + 1] = "bind " .. keys
    return { remove = function() calls[#calls + 1] = "remove " .. keys end }
  end,
  unbind = function(keys) calls[#calls + 1] = "unbind " .. keys end,
  dsp = { exec_cmd = function(command) return command end },
}
local function register(shortcut, move)
  calls = {}
  M.register(shortcut, nil, move)
  table.sort(calls)
  return table.concat(calls, ", ")
end
_G.omasizer_state, _G.omasizer_mouse = nil, nil
assert(register("SUPER + ALT + Z") == "bind SUPER + ALT + Z, bind mouse:273, bind mouse:273")
assert(register("SUPER + ALT + Z") == "")
assert(register("SUPER + CTRL + F5") == "bind SUPER + CTRL + F5, unbind SUPER + ALT + Z")
assert(register("") == "unbind SUPER + CTRL + F5")
assert(register("") == "")
assert(register("SUPER + O") == "bind SUPER + O")
-- The arrows: all four with the modifiers, swapped together.
assert(register("SUPER + O", "SUPER + CTRL + ALT") == "bind SUPER + CTRL + ALT + DOWN, bind SUPER + CTRL + ALT + LEFT, bind SUPER + CTRL + ALT + RIGHT, bind SUPER + CTRL + ALT + UP")
assert(register("SUPER + O", "SUPER + CTRL + ALT") == "")
assert(register("SUPER + O", "SUPER + SHIFT") == "bind SUPER + SHIFT + DOWN, bind SUPER + SHIFT + LEFT, bind SUPER + SHIFT + RIGHT, bind SUPER + SHIFT + UP, unbind SUPER + CTRL + ALT + DOWN, unbind SUPER + CTRL + ALT + LEFT, unbind SUPER + CTRL + ALT + RIGHT, unbind SUPER + CTRL + ALT + UP")
assert(register("SUPER + O", "") == "unbind SUPER + SHIFT + DOWN, unbind SUPER + SHIFT + LEFT, unbind SUPER + SHIFT + RIGHT, unbind SUPER + SHIFT + UP")
-- Old keys go before new ones are bound, so a shortcut that was an old arrow key survives the change.
register("SUPER + O", "SUPER + SHIFT")
calls = {}
M.register("SUPER + SHIFT + LEFT", nil, "")
assert(calls[#calls] == "bind SUPER + SHIFT + LEFT")

-- Unregistering removes its keys, but only for the service instance that owns the binds.
-- The right-click hook stays bound (unbinding it would take the user's own right-click binds too) but goes inert.
_G.omasizer_state = nil
calls = {}
M.register("SUPER + O", nil, "SUPER + SHIFT", "old")
M.register("SUPER + O", nil, "SUPER + SHIFT", "new")
calls = {}
M.unregister("old")
assert(#calls == 0 and _G.omasizer_state ~= nil)
M.unregister("new")
table.sort(calls)
assert(table.concat(calls, ", ") == "unbind SUPER + O, unbind SUPER + SHIFT + DOWN, unbind SUPER + SHIFT + LEFT, unbind SUPER + SHIFT + RIGHT, unbind SUPER + SHIFT + UP")
assert(_G.omasizer_state == nil)
M.unregister("new")                                  -- twice is harmless
calls = {}
M.register("", nil, "", "again")
assert(#calls == 0)                                  -- registering again doesn't bind the right-click twice
assert(_G.omasizer_unregister == M.unregister)       -- the service unloads through it, with no file needed

-- After an update, a hook an earlier version bound is neither bound twice nor left behind.
_G.omasizer_state, _G.omasizer_mouse = { mouse = true, owner = "v120", shortcut = "", move = "" }, nil
calls = {}
M.register("", nil, "", "v120")
assert(#calls == 0)
M.unregister("v120")
assert(table.concat(calls, ", ") == "unbind mouse:273")
calls = {}
M.register("", nil, "", "v121")
assert(table.concat(calls, ", ") == "bind mouse:273, bind mouse:273")

-- A right-press OmaSizer claims is kept from the app; any other passes through.
local press
local cursor = { x = 200, y = 85 }
hl = {
  bind = function(keys, fn, opts) if keys == "mouse:273" and not (opts and opts.release) then press = fn end end,
  get_cursor_pos = function() return cursor end,
  get_config = function(name) return name == "plugin.hyprbars.bar_height" and 30 or 0 end,
  get_windows = function() return { a } end,
  get_monitor_at = function() return mon end,
  get_layers = function() return {} end,
}
_G.omasizer_state, _G.omasizer_mouse = nil, nil
M.register("", nil)
assert(press().pass_event == false)                  -- titlebar
cursor = { x = 200, y = 200 }
assert(press().pass_event == true)                   -- inside the window: the app's
cursor = { x = 200, y = 85 }
M.register("", { titlebar = false, border = true })
assert(press().pass_event == true)                   -- titlebar right-clicks turned off
M.register("", nil)
local high = window(100, 40, 400, 300)              -- its titlebar runs under the bar (10..40)
hl.get_windows = function() return { high } end
cursor = { x = 200, y = 20 }
assert(press().pass_event == true)                   -- on the bar: the bar's
cursor = { x = 200, y = 30 }
assert(press().pass_event == false)                  -- below the bar: still OmaSizer's

-- An overlay that takes the keyboard over the titlebar gets the click.
hl.get_layers = function() return { { mapped = true, layer = 3, interactivity = 1, x = 0, y = 0, w = 1920, h = 1200 } } end
assert(press().pass_event == true)
hl.get_layers = function() return { { mapped = true, layer = 2, interactivity = 0, x = 0, y = 0, w = 1920, h = 1200 } } end
assert(press().pass_event == false)                  -- the bar's full-screen layer takes no keyboard
-- Whatever fails inside, the click is passed on, never swallowed.
hl.get_cursor_pos = function() return nil end
assert(press().pass_event == true)
hl.get_cursor_pos = function() error("boom") end
assert(press().pass_event == true)
hl.get_cursor_pos = function() return cursor end
hl.get_windows = function() error("boom") end
assert(press().pass_event == true)
hl.get_windows = function() return { high } end
assert(press().pass_event == false)
M.unregister(nil)
assert(press().pass_event == true)                   -- unregistered: the hook claims nothing

-- The release opens the menu, and a window that closed in between makes it do nothing, without an error.
local release, summoned
hl.bind = function(keys, fn, opts) if keys == "mouse:273" and opts and opts.release then release = fn end end
hl.exec_cmd = function(cmd) summoned = cmd end
hl.get_windows = function() return { a } end
cursor = { x = 200, y = 85 }
_G.omasizer_state, _G.omasizer_mouse = nil, nil
M.register("", nil)
assert(press().pass_event == false)
release()
assert(summoned and summoned:find('"zone":"titlebar"'))
-- A window between sizes (an animation, fractional scaling) still opens the menu.
summoned = nil
a.size = { x = 400.5, y = 300.25 }
assert(press().pass_event == false)
release()
assert(summoned and summoned:find('"width":400,"height":300'))
summoned = nil
assert(press().pass_event == false)
a.size = nil
release()
assert(summoned == nil)
hl = nil

print("ok")
