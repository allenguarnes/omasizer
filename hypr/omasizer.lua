-- OmaSizer for Hyprland: a keyboard shortcut (Super + Alt + Z by default) opens
-- the menu for the focused window, a right-click on a floating window's
-- titlebar (its buttons included) or its resize border opens it at the cursor
-- for that window, and modifiers with an arrow key (Super + Ctrl + Alt by
-- default) move the focused window to the next zone of its layout.
--
-- OmaSizer's shell service loads this file with `hyprctl eval` when the shell
-- starts and after every config reload, first setting `omasizer_shortcut` to
-- the shortcut to bind, or "" for none, `omasizer_clicks` to which right-clicks
-- open the menu, and `omasizer_move` to the modifiers for the arrows, or "" for
-- none. Loaded from bindings.lua instead, the defaults apply. It also sets
-- `omasizer_owner`, a token of the service instance; with `omasizer_unload` set to
-- that token instead, the file removes everything it bound, if that instance still owns it. Loading it again only changes what differs.

local M = {}

M.DEFAULT_SHORTCUT = "SUPER + ALT + Z"
-- Marks the binding in `hyprctl binds`, so the service can tell it from others; Presets.js uses the same text.
M.DESCRIPTION = "OmaSizer: open the menu"
M.DEFAULT_MOVE = "SUPER + CTRL + ALT"
M.MOVE_DESCRIPTION = "OmaSizer: move between zones"
M.ARROWS = { LEFT = "left", RIGHT = "right", UP = "up", DOWN = "down" }

local WORKSPACE_TAG = "omarchy-floating-workspace" -- windows Omarchy's floating mode gives titlebars

local function has_tag(window, tag)
  for _, t in ipairs(window.tags or {}) do
    if t == tag or t == tag .. "*" then
      return true
    end
  end
  return false
end

-- The part of a window a point lands on: "content", "titlebar", "border", or nil.
-- The titlebar is drawn above the window's reported position; the border band
-- reaches `grab` past the titlebar and the content.
function M.zone(window, x, y, bar, grab)
  local left, top = window.at.x, window.at.y
  local right, bottom = left + window.size.x, top + window.size.y

  if x >= left and x < right and y >= top and y < bottom then
    return "content"
  elseif x >= left and x < right and y >= top - bar and y < top then
    return "titlebar"
  elseif x >= left - grab and x < right + grab and y >= top - bar - grab and y < bottom + grab then
    return "border"
  end
end

-- How high a window stacks, as Hyprland's own hit test orders them: pinned windows,
-- then the shown special workspace, then fullscreen ones, then the rest, which Hyprland
-- lists bottom to top. A fullscreen window counts above every floating one, whatever
-- the list order, so a right-click in a fullscreen app is never taken for a titlebar's.
local function stack_tier(window)
  if window.pinned then
    return 3
  elseif window.workspace and window.workspace.special then
    return 2
  elseif (window.fullscreen or 0) ~= 0 then
    return 1.5
  end
  return 1
end

-- The floating window whose titlebar or border is under the point, and which of
-- the two, if no window above it covers the point. Only windows on a shown workspace
-- (or pinned) count: windows on other workspaces still report themselves visible.
function M.target(windows, x, y, bar, grab)
  local hit, hit_zone, hit_tier = nil, nil, 0

  for _, window in ipairs(windows) do
    local shown = window.pinned or (window.workspace and window.workspace.visible)
    if shown and window.visible and window.mapped and not window.hidden then
      local floating = window.floating and window.fullscreen == 0
      local titled = floating and has_tag(window, WORKSPACE_TAG)
      -- XWayland popups and tooltips are floating windows too; only titled ones get the grab band.
      local banded = floating and (titled or not window.xwayland)
      local zone = M.zone(window, x, y, titled and bar or 0, banded and grab or 0)
      local tier = stack_tier(window)
      if zone and tier >= hit_tier then
        hit, hit_zone, hit_tier = window, zone, tier
      end
    end
  end

  if hit and hit_zone ~= "content" then
    return hit, hit_zone
  end
end

-- Whether the point is in the monitor's reserved edge, where the bar sits above any window.
-- shortcut: other layers (dock, notifications) are not checked, since Hyprland only gives their full-size boxes, not where they take clicks.
function M.reserved_at(monitor, x, y)
  local r = monitor.reserved
  if type(r) ~= "table" then
    return false
  end
  local rotated = monitor.transform % 2 == 1
  local width = (rotated and monitor.height or monitor.width) / monitor.scale
  local height = (rotated and monitor.width or monitor.height) / monitor.scale
  return x < monitor.x + (r.left or 0) or x >= monitor.x + width - (r.right or 0)
    or y < monitor.y + (r.top or 0) or y >= monitor.y + height - (r.bottom or 0)
end

-- Whether a layer that takes the keyboard (a launcher, a menu, a panel, OmaSizer's own
-- overlay) covers the point: the click is that layer's, whatever titlebar lies under it.
-- The bar and notifications take no keyboard and span the screen, so they can't be told apart.
function M.overlay_at(layers, x, y)
  for _, l in ipairs(layers) do
    if l.mapped and l.layer >= 2 and (l.interactivity or 0) ~= 0
        and x >= l.x and x < l.x + l.w and y >= l.y and y < l.y + l.h then
      return true
    end
  end
  return false
end

-- How far the pointer may travel between press and release for a right-click to count as one.
M.CLICK_SLOP = 4

function M.is_click(press, release)
  return math.abs(release.x - press.x) <= M.CLICK_SLOP and math.abs(release.y - press.y) <= M.CLICK_SLOP
end

local function config_number(name, fallback)
  local ok, value = pcall(hl.get_config, name)
  value = ok and tonumber(value) or nil
  return value or fallback
end

-- A right-press OmaSizer claims is kept from the app under it (which would open
-- its own context menu) and from Hyprland's border resize; any other right-press
-- passes through. The menu opens on the release, so the release is swallowed too.
local pressed

local function claim_press()
  -- Unregistered, the hook stays bound but claims nothing (see M.unregister).
  if not _G.omasizer_state then
    return nil
  end
  local cursor = hl.get_cursor_pos()
  if not cursor or M.overlay_at(hl.get_layers(), cursor.x, cursor.y) then
    return nil
  end
  local bar = config_number("plugin.hyprbars.bar_height", 30)
  local grab = config_number("general.border_size", 0)

  local ok, resize_on_border = pcall(hl.get_config, "general.resize_on_border")
  if ok and resize_on_border then
    grab = grab + config_number("general.extend_border_grab_area", 0)
  end

  local monitor = hl.get_monitor_at(cursor.x, cursor.y)
  local window, zone
  if not (monitor and M.reserved_at(monitor, cursor.x, cursor.y)) then
    window, zone = M.target(hl.get_windows(), cursor.x, cursor.y, bar, grab)
  end
  local clicks = (_G.omasizer_state or {}).clicks or {}
  if window and clicks[zone] ~= false then
    return { window = window, zone = zone, x = cursor.x, y = cursor.y }
  end
end

-- This bind consumes the press unless told to pass it, and a callback that fails tells
-- Hyprland nothing, which would swallow every right-click. So any error passes it on.
local function on_right_press()
  local ok, press = pcall(claim_press)
  pressed = ok and press or nil
  return { pass_event = pressed == nil }
end

local function open_menu(press)
  local cursor = hl.get_cursor_pos()
  if not cursor or not M.is_click(press, cursor) then
    return
  end

  -- Every value is a number, a fixed word, or Hyprland's hex address, so the JSON needs no escaping.
  local window = press.window
  local payload = string.format('{"address":"%s","zone":"%s","x":%d,"y":%d,"width":%d,"height":%d}',
    window.address, press.zone, math.floor(press.x), math.floor(press.y), math.floor(window.size.x), math.floor(window.size.y))
  hl.exec_cmd("omarchy-shell shell summon omasizer '" .. payload .. "'")
end

-- The window may have closed since the press; whatever fails, the menu just doesn't open.
local function on_right_release()
  local press = pressed
  pressed = nil
  if press then
    pcall(open_menu, press)
  end
end

-- Hyprland keeps this table until its config reloads, which also drops these binds.
-- `clicks` maps "titlebar" and "border" to false to leave those right-clicks alone.
function M.register(shortcut, clicks, move, owner)
  local state = _G.omasizer_state or {}
  _G.omasizer_state = state
  state.clicks = clicks
  state.owner = owner

  -- Bound once per Hyprland config (a reload drops it); unregistering leaves it bound but inert.
  -- state.mouse marks a hook bound by OmaSizer 1.2.0 or earlier, still loaded after an update.
  if not _G.omasizer_mouse and not state.mouse then
    -- The press handler decides per click whether the app gets it.
    hl.bind("mouse:273", on_right_press)
    hl.bind("mouse:273", on_right_release, { non_consuming = true, release = true, transparent = true, ignore_mods = true })
    _G.omasizer_mouse = true
  end
  -- The service unloads through this, so unloading works even once the plugin's files are gone.
  _G.omasizer_unregister = M.unregister

  -- Every old key is unbound before any new one is bound, so a new shortcut that was an old arrow key survives.
  -- Only keys this file bound are ever unbound; the service never passes one that is in use.
  move = move or ""
  local new_shortcut, new_move = state.shortcut ~= shortcut, state.move ~= move
  if new_shortcut and state.shortcut and state.shortcut ~= "" then
    hl.unbind(state.shortcut)
  end
  if new_move and state.move and state.move ~= "" then
    for key in pairs(M.ARROWS) do
      hl.unbind(state.move .. " + " .. key)
    end
  end
  if new_shortcut then
    if shortcut ~= "" then
      hl.bind(shortcut, hl.dsp.exec_cmd("omarchy-shell shell toggle omasizer"), { description = M.DESCRIPTION })
    end
    state.shortcut = shortcut
  end
  if new_move then
    -- The overlay runs the move: it holds the layouts, and opens nothing for it.
    if move ~= "" then
      for key, direction in pairs(M.ARROWS) do
        hl.bind(move .. " + " .. key, hl.dsp.exec_cmd("omarchy-shell shell summon omasizer '{\"move\":\"" .. direction .. "\"}'"),
          { description = M.MOVE_DESCRIPTION })
      end
    end
    state.move = move
  end
end

-- Remove every bind this file made. A service that is going away calls it with its own
-- token; if a newer service has registered since, the binds are that one's and stay.
function M.unregister(owner)
  local state = _G.omasizer_state
  if not state or state.owner ~= owner then
    return
  end
  -- Never Keybind:remove(): it removes every bind on the same keys, and calling it on the
  -- second, already removed one crashes Hyprland 0.56 (a null dereference in keybindRemove).
  -- The right-click hook is not unbound: that would also remove a plain right-click bind of
  -- the user's own. With no state it claims nothing, and the next config reload drops it.
  -- An earlier version's hook can't go inert, so that one is unbound as it always was.
  if state.mouse then
    hl.unbind("mouse:273")
  end
  if state.shortcut and state.shortcut ~= "" then
    hl.unbind(state.shortcut)
  end
  if state.move and state.move ~= "" then
    for key in pairs(M.ARROWS) do
      hl.unbind(state.move .. " + " .. key)
    end
  end
  _G.omasizer_state = nil
end

if hl and hl.bind and _G.omasizer_unload then
  M.unregister(_G.omasizer_unload)
  -- Cleared, so a later load of this file without the service registers again.
  _G.omasizer_unload = nil
elseif hl and hl.bind then
  local shortcut = _G.omasizer_shortcut
  if shortcut == nil then
    shortcut = M.DEFAULT_SHORTCUT
  end
  local move = _G.omasizer_move
  if move == nil then
    move = M.DEFAULT_MOVE
  end
  M.register(shortcut, _G.omasizer_clicks, move, _G.omasizer_owner)
end

return M
