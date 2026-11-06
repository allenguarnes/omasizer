# OmaSizer

Resize windows to preset sizes, or move them into screen zones like PowerToys FancyZones. It's an Omarchy shell plugin modelled on [Sizer](https://www.brianapps.net/sizer4/) and [KSizer](https://github.com/allenguarnes/KSizer), made for Omarchy 4.5's floating workspace layout.

## Opening the menu

- **Right-click** a floating window's titlebar or one of its titlebar buttons, including maximize. The menu opens at the cursor and acts on that window.
- **Right-click** a window's resize border or corner. This also opens the menu at the cursor for that window.
- **Super + Alt + Z** opens the menu in the middle of the screen for the focused window.

Right-clicks inside a window still go to the app as usual. The menu opens when you release the button. A right-drag on the border resizes the window as usual and doesn't open it.

The menu shows the zone layouts drawn as small screens, then the size presets. Click a zone, or arrow to it and press `Enter`, to move the window into it. The window fills the zone, titlebar included, with a gap at the screen edges and between zones.

Default layouts:

- 50:50 columns and rows
- 33:33:33 columns and rows
- 75:25 main + side, and 25:75
- 25:50:25 main with two sides
- Quadrants

Picking a preset does the following:

- Leaves fullscreen or maximized first.
- Floats a tiled window.
- Resizes the window and centers it.
- Shrinks a preset that is larger than the screen to fit.

Centering and shrinking can each be turned off in settings.

The menu takes these keys:

- `1`–`9` apply a preset.
- `↑`/`↓`/`←`/`→`, `h`/`j`/`k`/`l` or `Tab` move the selection zone by zone and then through the presets, and `Enter` picks it.
- `S` opens settings.
- `Esc` closes the menu.

## Settings

Choose **Settings…** at the bottom of the menu. There you can do the following:

- Add, edit, reorder and remove presets. A new preset starts at the size of the window you right-clicked.
- Under **Size presets**, turn **Center the window after resizing** and **Shrink presets that don't fit the screen** on or off.
- Edit zone layouts. Click a layout under **Zone layouts**, or Tab to it and press `Enter`, to open the editor; **New layout** starts one with a single full-screen zone. In the editor:
  - drag a zone to move it, or drag its edges and corners to resize it; edges snap to 24ths of the screen, so halves, thirds and quarters line up exactly;
  - **Split side by side**, **Split stacked**, **Add zone** and **Remove zone** work on the selected zone;
  - type the selected zone's X, Y, width and height in percent;
  - name the layout, or **Delete layout**;
  - from the keyboard, `Tab` moves through the zones and controls, arrows move the focused zone one grid step, `Shift`+arrows move its right or bottom edge, `Delete` removes it, `Enter` finishes and `Esc` discards the changes.

  To reorder layouts, drag a thumbnail onto another, or focus one and press `Alt`+`←`/`→`. **Restore defaults** puts back the eight default layouts.

  Layout edits, reordering and restoring are kept when you press **Save** in settings; **Cancel** discards them.
- Set the zone gaps at the screen edges and between windows. They start from Omarchy's spacing (Hyprland's `gaps_out`, and twice `gaps_in`) and keep their own values once saved.
- Under **Right-click to open**, choose whether a right-click on a window's titlebar, or on its resize border, opens the menu.

Settings work fully from the keyboard:

- `Tab` and `Shift+Tab` move through every field, button and switch.
- `Space` or `Enter` presses the focused button or flips the focused switch.
- `Enter` in a text field saves.
- `Esc` goes back to the menu without saving.

**Save** stores the settings in OmaSizer's entry in `~/.config/omarchy/shell.json`:

```json
{ "id": "omasizer", "center": true, "clamp": true, "titlebarClick": true, "borderClick": true,
  "presets": [{ "label": "16:9", "width": 1280, "height": 720 }],
  "layouts": [{ "name": "50:50 columns", "zones": [[0, 0, 0.5, 1], [0.5, 0, 0.5, 1]] }],
  "outerGap": 10, "innerGap": 10 }
```

A zone is `[x, y, width, height]` as fractions of the screen's usable area. Without `layouts`, the defaults above are used.

Sizes are logical pixels, from 1 to 16384. If the entry has no `presets`, KSizer's six defaults are used.

## Install

```bash
omarchy plugin add https://github.com/allenguarnes/omasizer.git --enable
```

Then load the keybind and the right-click hook from `~/.config/hypr/bindings.lua`:

```lua
dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/omasizer/hypr/omasizer.lua")
```

## Per-preset hotkeys

The resize script works without the menu:

```lua
o.bind("SUPER + ALT + 1", "Window 1280×720", "~/.config/omarchy/plugins/omasizer/bin/omasizer 1280 720")
```

`bin/omasizer <width> <height> [window-address]` targets the focused window unless an address is given. `bin/omasizer --zone <x> <y> <width> <height> [window-address]` moves it into a zone, for example `--zone 0 0 0.5 1` for the left half.

## Test

```bash
node test/presets.test.js
lua test/hypr.test.lua
bash test/omasizer.test.sh
```
