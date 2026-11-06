-- OmaSizer for Hyprland: Super + Alt + Z opens the preset menu for the focused
-- window, and a right-click on a floating window's titlebar (its buttons
-- included) or its resize border opens it at the cursor for that window.
--
-- Load it from ~/.config/hypr/bindings.lua:
--   dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/omasizer/hypr/omasizer.lua")

local M = {}

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

-- The floating window whose titlebar or border is under the point, and which of
-- the two, if no window above it covers the point. Hyprland lists windows bottom to top.
-- shortcut: layer surfaces such as the bar are not checked, so a click on a layer over a titlebar also opens the menu; check hl.get_layers() if that bites.
function M.target(windows, x, y, bar, grab)
  local hit, hit_zone

  for _, window in ipairs(windows) do
    if window.visible and window.mapped and not window.hidden then
      local floating = window.floating and window.fullscreen == 0
      local zone = M.zone(window, x, y, (floating and has_tag(window, WORKSPACE_TAG)) and bar or 0, floating and grab or 0)
      if zone then
        hit, hit_zone = window, zone
      end
    end
  end

  if hit and hit_zone ~= "content" then
    return hit, hit_zone
  end
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

-- A right-press on the border also starts Hyprland's own border resize, which only
-- ends when Hyprland sees the release. So the press only records what was hit and
-- the menu opens on the release, once the pointer is back with Hyprland.
local pressed

local function on_right_press()
  local cursor = hl.get_cursor_pos()
  local bar = config_number("plugin.hyprbars.bar_height", 30)
  local grab = config_number("general.border_size", 0)

  local ok, resize_on_border = pcall(hl.get_config, "general.resize_on_border")
  if ok and resize_on_border then
    grab = grab + config_number("general.extend_border_grab_area", 0)
  end

  local window, zone = M.target(hl.get_windows(), cursor.x, cursor.y, bar, grab)
  pressed = window and { window = window, zone = zone, x = cursor.x, y = cursor.y } or nil
end

local function on_right_release()
  local press = pressed
  pressed = nil
  if not press or not M.is_click(press, hl.get_cursor_pos()) then
    return
  end

  -- Every value is a number, a fixed word, or Hyprland's hex address, so the JSON needs no escaping.
  -- The overlay drops the request when right-clicks on this zone are turned off in settings.
  local window = press.window
  local payload = string.format('{"address":"%s","zone":"%s","x":%d,"y":%d,"width":%d,"height":%d}',
    window.address, press.zone, math.floor(press.x), math.floor(press.y), window.size.x, window.size.y)
  hl.exec_cmd("omarchy-shell shell summon omasizer '" .. payload .. "'")
end

if hl and hl.bind then
  hl.bind("SUPER + ALT + Z", hl.dsp.exec_cmd("omarchy-shell shell toggle omasizer"), { description = "Resize window to preset" })
  -- Non-consuming, so every right-click still reaches the app under it.
  hl.bind("mouse:273", on_right_press, { non_consuming = true })
  hl.bind("mouse:273", on_right_release, { non_consuming = true, release = true, transparent = true, ignore_mods = true })
end

return M
