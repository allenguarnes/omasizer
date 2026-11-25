#!/bin/bash
# bash test/omasizer.test.sh: runs bin/omasizer against a fake hyprctl and checks what it dispatches.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# A 1920x1200 logical monitor (3200x2000 at 5/3 scale) with a 26 px bar on top.
cat >"$tmp/hyprctl" <<'STUB'
#!/bin/bash
case "$1 $2" in
"activewindow -j") echo '{"address":"0xabc","floating":true,"fullscreen":'"${FS:-0}"',"monitor":0,"workspace":{"id":1},"at":['"${AT:-300,200}"'],"size":['"${SIZE:-800,600}"'],"tags":["omarchy-floating-workspace","terminal*"]}' ;;
"clients -j") [[ -n ${CLIENTS:-} ]] && echo "$CLIENTS" || echo '[{"address":"0xdef","floating":false,"fullscreen":0,"monitor":0,"workspace":{"id":1},"at":[5,5],"size":[800,600],"tags":[]}]' ;;
"monitors -j") echo '[{"id":0,"x":0,"y":0,"width":3200,"height":2000,"scale":1.6666666,"transform":0,"reserved":[0,26,0,0]}]' ;;
"getoption general:gaps_out") echo '{"css":"10 10 10 10"}' ;;
"getoption general:gaps_in") echo '{"css":"5 5 5 5"}' ;;
"getoption general:border_size") echo '{"int":2}' ;;
"getoption plugin:hyprbars:bar_height") echo '{"int":30}' ;;
dispatch*) [[ $2 == hl.* ]] && echo "$2" >>"$LOG" ;;
esac
STUB
chmod +x "$tmp/hyprctl"
export PATH="$tmp:$PATH" XDG_CONFIG_HOME="$tmp" XDG_RUNTIME_DIR="$tmp" LOG="$tmp/log"

run() {
  : >"$LOG"
  "$root/bin/omasizer" "$@"
  { grep -E 'resize|move|center|float|fullscreen' "$LOG" || true; } | sed -E 's/window = "address:0x[a-f]+"(, )?//'
}

expect() {
  local got
  got=$(run "${@:2}")
  [[ $got == "$1" ]] || { printf 'omasizer %s\nexpected:\n%s\ngot:\n%s\n' "${*:2}" "$1" "$got" >&2; exit 1; }
}

# Halves meet with gaps_in on each side, keep gaps_out at the edges, and leave room for border and titlebar.
expect $'hl.dsp.window.resize({ x = 941, y = 1120 })\nhl.dsp.window.move({ x = 12, y = 68 })' --zone 0 0 0.5 1
expect $'hl.dsp.window.resize({ x = 941, y = 1120 })\nhl.dsp.window.move({ x = 967, y = 68 })' --zone 0.5 0 0.5 1
# Bottom-right quadrant.
expect $'hl.dsp.window.resize({ x = 941, y = 538 })\nhl.dsp.window.move({ x = 967, y = 650 })' --zone .5 .5 .5 .5
# A tiled window has no titlebar and is floated first.
expect $'hl.dsp.window.float({ action = "enable" })\nhl.dsp.window.resize({ x = 1896, y = 1150 })\nhl.dsp.window.move({ x = 12, y = 38 })' --zone 0 0 1 1 0xdef

# Saved gaps replace Hyprland's: none at the edges, 20 between halves (10 on each side).
mkdir -p "$tmp/omarchy"; echo '{"plugins":[{"id":"omasizer","outerGap":0,"innerGap":20}]}' >"$tmp/omarchy/shell.json"
expect $'hl.dsp.window.resize({ x = 946, y = 1140 })\nhl.dsp.window.move({ x = 2, y = 58 })' --zone 0 0 0.5 1
expect $'hl.dsp.window.resize({ x = 946, y = 1140 })\nhl.dsp.window.move({ x = 972, y = 58 })' --zone 0.5 0 0.5 1
rm "$tmp/omarchy/shell.json"

# A maximized or fullscreen window leaves that state first, named, so no other window is toggled.
FS=1 expect $'hl.dsp.window.fullscreen({ mode = "maximized", action = "unset",  })\nhl.dsp.window.resize({ x = 800, y = 600 })\nhl.dsp.window.center({  })' 800 600
FS=2 expect $'hl.dsp.window.fullscreen({ mode = "fullscreen", action = "unset",  })\nhl.dsp.window.resize({ x = 800, y = 600 })\nhl.dsp.window.center({  })' 800 600

# Sizes clamp to the usable area and center, or keep their place when centering is off.
expect $'hl.dsp.window.resize({ x = 800, y = 600 })\nhl.dsp.window.center({  })' 800 600
expect $'hl.dsp.window.resize({ x = 1920, y = 1174 })\nhl.dsp.window.center({  })' 5000 5000
mkdir -p "$tmp/omarchy"; echo '{"plugins":[{"id":"omasizer","center":false,"clamp":false}]}' >"$tmp/omarchy/shell.json"
expect $'hl.dsp.window.resize({ x = 5000, y = 5000 })\nhl.dsp.window.move({ x = 300, y = 200 })' 5000 5000

rm "$tmp/omarchy/shell.json"

# Moves: the starred layout (halves) until the window is placed from another one.
halves='[[0,0,0.5,1],[0.5,0,0.5,1]]' quads='[[0,0,0.5,0.5],[0.5,0,0.5,0.5],[0,0.5,0.5,0.5],[0.5,0.5,0.5,0.5]]'
spec='{"layouts":['"$halves,$quads"'],"starred":0}'
left=$'hl.dsp.window.resize({ x = 941, y = 1120 })\nhl.dsp.window.move({ x = 12, y = 68 })'
right=$'hl.dsp.window.resize({ x = 941, y = 1120 })\nhl.dsp.window.move({ x = 967, y = 68 })'
# A free window goes to the nearest zone that way; up and down have none in columns.
expect "$right" --move right "$spec"
expect "$left" --move left "$spec"
expect "" --move up "$spec"
# In a zone it steps to the next one, and stays put past the last.
AT=12,68 SIZE=941,1120 expect "$right" --move right "$spec"
AT=12,68 SIZE=941,1120 expect "" --move left "$spec"
# Placed from the quadrants, it moves around the quadrants.
expect $'hl.dsp.window.resize({ x = 941, y = 538 })\nhl.dsp.window.move({ x = 12, y = 68 })' --layout "$quads" --zone 0 0 0.5 0.5
AT=12,68 SIZE=941,538 expect $'hl.dsp.window.resize({ x = 941, y = 538 })\nhl.dsp.window.move({ x = 12, y = 650 })' --move down "$spec"
AT=12,650 SIZE=941,538 expect $'hl.dsp.window.resize({ x = 941, y = 538 })\nhl.dsp.window.move({ x = 967, y = 650 })' --move right "$spec"
AT=967,650 SIZE=941,538 expect "" --move down "$spec"
# A preset size forgets the layout, so the next move starts from the starred one.
expect $'hl.dsp.window.resize({ x = 800, y = 600 })\nhl.dsp.window.center({  })' 800 600
AT=12,68 SIZE=941,538 expect "$right" --move right "$spec"
expect $'hl.dsp.window.resize({ x = 941, y = 538 })\nhl.dsp.window.move({ x = 12, y = 68 })' --layout "$quads" --zone 0 0 0.5 0.5
# A layout that no longer exists falls back to the starred one.
AT=12,68 SIZE=941,538 expect "$right" --move right '{"layouts":['"$halves"'],"starred":0}'
# The memory keeps only windows that are still open.
[[ $(jq -c 'keys' "$tmp/omasizer-layouts.json") == '["0xabc"]' ]] || { echo "memory: $(cat "$tmp/omasizer-layouts.json")" >&2; exit 1; }

# A window on the same layout in the zone moved to takes the zone left behind; it moves first.
export CLIENTS='[{"address":"0xabc","floating":true,"fullscreen":0,"monitor":0,"workspace":{"id":1},"at":[0,0],"size":[1,1],"tags":[]},{"address":"0xdef","floating":true,"fullscreen":0,"mapped":true,"hidden":false,"monitor":0,"workspace":{"id":1},"at":[967,68],"size":[941,538],"tags":["omarchy-floating-workspace"]}]'
quarter=$'hl.dsp.window.resize({ x = 941, y = 538 })\nhl.dsp.window.move({ x = '
run --layout "$quads" --zone 0.5 0 0.5 0.5 0xdef >/dev/null
run --layout "$quads" --zone 0 0 0.5 0.5 >/dev/null
AT=12,68 SIZE=941,538 expect "${quarter}12, y = 68 })"$'\n'"${quarter}967, y = 68 })" --move right "$spec"
# Not when it is on another layout, or when the moving window isn't in a zone.
run --layout "$halves" --zone 0.5 0 0.5 1 0xdef >/dev/null
AT=12,68 SIZE=941,538 expect "${quarter}967, y = 68 })" --move right "$spec"
run --layout "$quads" --zone 0.5 0 0.5 0.5 0xdef >/dev/null
AT=1000,100 SIZE=200,300 expect "${quarter}967, y = 68 })" --move right '{"layouts":['"$quads"'],"starred":0}'
# The same from the menu: placing it in the occupied zone swaps.
run --layout "$quads" --zone 0.5 0 0.5 0.5 0xdef >/dev/null
AT=12,68 SIZE=941,538 expect "${quarter}12, y = 68 })"$'\n'"${quarter}967, y = 68 })" --layout "$quads" --zone 0.5 0 0.5 0.5
# Not when swapping is turned off in settings.
run --layout "$quads" --zone 0.5 0 0.5 0.5 0xdef >/dev/null
echo '{"plugins":[{"id":"omasizer","swap":false}]}' >"$tmp/omarchy/shell.json"
AT=12,68 SIZE=941,538 expect "${quarter}967, y = 68 })" --layout "$quads" --zone 0.5 0 0.5 0.5
AT=12,68 SIZE=941,538 expect "${quarter}967, y = 68 })" --move right "$spec"
rm "$tmp/omarchy/shell.json"
# Not when this window isn't in a zone of that layout, or picks the zone it is already in.
AT=100,100 SIZE=500,300 expect "${quarter}967, y = 68 })" --layout "$quads" --zone 0.5 0 0.5 0.5
AT=967,68 SIZE=941,538 expect "${quarter}967, y = 68 })" --layout "$quads" --zone 0.5 0 0.5 0.5
# Both windows in their zones, as on a real desktop: the other window's move must not swap back.
export CLIENTS='[{"address":"0xabc","floating":true,"fullscreen":0,"monitor":0,"workspace":{"id":1},"at":[12,68],"size":[941,538],"tags":["omarchy-floating-workspace"]},{"address":"0xdef","floating":true,"fullscreen":0,"monitor":0,"workspace":{"id":1},"at":[967,68],"size":[941,538],"tags":["omarchy-floating-workspace"]}]'
run --layout "$quads" --zone 0.5 0 0.5 0.5 0xdef >/dev/null
run --layout "$quads" --zone 0 0 0.5 0.5 0xabc >/dev/null
: >"$LOG"
AT=12,68 SIZE=941,538 timeout 10 "$root/bin/omasizer" --layout "$quads" --zone 0.5 0 0.5 0.5 || { echo "the swap loops" >&2; exit 1; }
[[ $(grep -c 'window.move' "$LOG") == 2 ]] || { echo "swap moved $(grep -c 'window.move' "$LOG") windows" >&2; exit 1; }
[[ $(grep 'hl.dsp.focus' "$LOG") == 'hl.dsp.focus({ window = "address:0xabc" })' ]] || { echo "swap focused: $(grep 'hl.dsp.focus' "$LOG")" >&2; exit 1; }
unset CLIENTS

# Spans: the smallest box holding the first and last zone, in either order.
thirds='[[0,0,0.333333,1],[0.333333,0,0.333333,1],[0.666667,0,0.333333,1]]'
tspec='{"layouts":['"$thirds"'],"starred":0}'
third=$'hl.dsp.window.resize({ x = 624, y = 1120 })\nhl.dsp.window.move({ x = '
two_thirds=$'hl.dsp.window.resize({ x = 1258, y = 1120 })\nhl.dsp.window.move({ x = 12, y = 68 })'
middle=$'hl.dsp.window.resize({ x = 619, y = 1120 })\nhl.dsp.window.move({ x = 650, y = 68 })'
all_thirds=$'hl.dsp.window.resize({ x = 1896, y = 1120 })\nhl.dsp.window.move({ x = 12, y = 68 })'
rm -f "$tmp/omasizer-layouts.json"
expect "$two_thirds" --layout "$thirds" --span 0 1
expect "$all_thirds" --layout "$thirds" --span 2 0
[[ $(jq -c '."0xabc".span' "$tmp/omasizer-layouts.json") == '[2,0]' ]] || { echo "span memory: $(cat "$tmp/omasizer-layouts.json")" >&2; exit 1; }
# A grow keeps the first zone and moves the last one, growing and shrinking the span.
expect "${third}12, y = 68 })" --layout "$thirds" --span 0 0
AT=12,68 SIZE=624,1120 expect "$two_thirds" --grow right "$tspec"
AT=12,68 SIZE=1258,1120 expect "$all_thirds" --grow right "$tspec"
AT=12,68 SIZE=1896,1120 expect "" --grow right "$tspec"
AT=12,68 SIZE=1896,1120 expect "$two_thirds" --grow left "$tspec"
AT=12,68 SIZE=1258,1120 expect "${third}12, y = 68 })" --grow left "$tspec"
AT=12,68 SIZE=624,1120 expect "" --grow left "$tspec"
# A move takes a span to the next zone outside it; a free window grows into the nearest zone.
expect "$two_thirds" --layout "$thirds" --span 0 1
AT=12,68 SIZE=1258,1120 expect "${third}1284, y = 68 })" --move right "$tspec"
expect "$two_thirds" --layout "$thirds" --span 0 1
AT=12,68 SIZE=1258,1120 expect "" --move left "$tspec"
rm -f "$tmp/omasizer-layouts.json"
expect "${third}12, y = 68 })" --grow left "$tspec"
# A span resized by hand is no span any more: the arrows treat the window as free.
expect "$two_thirds" --layout "$thirds" --span 0 1
AT=12,68 SIZE=1000,1120 expect "$middle" --move right "$tspec"
# A layout remembered by OmaSizer 1.3, as bare zones, still counts.
echo '{"0xabc":'"$thirds"'}' >"$tmp/omasizer-layouts.json"
AT=12,68 SIZE=624,1120 expect "$middle" --move right '{"layouts":['"$halves,$thirds"'],"starred":0}'
# A span never swaps; the window in the zone keeps it.
export CLIENTS='[{"address":"0xabc","floating":true,"fullscreen":0,"monitor":0,"workspace":{"id":1},"at":[12,68],"size":[624,1120],"tags":["omarchy-floating-workspace"]},{"address":"0xdef","floating":true,"fullscreen":0,"monitor":0,"workspace":{"id":1},"at":[650,68],"size":[619,1120],"tags":["omarchy-floating-workspace"]}]'
run --layout "$thirds" --span 1 1 0xdef >/dev/null
AT=12,68 SIZE=624,1120 expect "$two_thirds" --grow right "$tspec"
unset CLIENTS

# Restore: back to where the window was before OmaSizer first moved it, however many moves since.
rm -f "$tmp/omasizer-restore.json"
export CLIENTS='[{"address":"0xabc","floating":true,"fullscreen":0,"monitor":0,"workspace":{"id":1},"at":[12,68],"size":[941,1120],"tags":["omarchy-floating-workspace"]}]'
before=$'hl.dsp.window.resize({ x = 800, y = 600 })\nhl.dsp.window.move({ x = 300, y = 200 })'
expect "$left" --zone 0 0 0.5 1
AT=12,68 SIZE=941,1120 expect "$right" --zone 0.5 0 0.5 1
AT=12,68 SIZE=941,1120 expect "$before" --restore
# Then there is nothing left to restore, and the window has left its layout.
AT=300,200 SIZE=800,600 expect "" --restore
[[ $(jq -c 'has("0xabc")' "$tmp/omasizer-layouts.json") == false ]] || { echo "restore kept the layout" >&2; exit 1; }
# Moved by hand since OmaSizer placed it, it restores to where it was moved.
expect "$left" --zone 0 0 0.5 1
AT=500,400 SIZE=941,1120 expect "$left" --zone 0 0 0.5 1
AT=12,68 SIZE=941,1120 expect $'hl.dsp.window.resize({ x = 941, y = 1120 })\nhl.dsp.window.move({ x = 500, y = 400 })' --restore
# A maximized window is maximized again.
FS=1 expect $'hl.dsp.window.fullscreen({ mode = "maximized", action = "unset",  })\n'"$left" --zone 0 0 0.5 1
AT=12,68 SIZE=941,1120 expect "$before"$'\nhl.dsp.window.fullscreen({ mode = "maximized", action = "set",  })' --restore
unset CLIENTS
# A tiled window goes back into the tiling.
expect $'hl.dsp.window.float({ action = "enable" })\nhl.dsp.window.resize({ x = 941, y = 1150 })\nhl.dsp.window.move({ x = 12, y = 38 })' --zone 0 0 0.5 1 0xdef
expect $'hl.dsp.window.float({ action = "disable" })' --restore 0xdef
rm -f "$tmp/omasizer-restore.json"

# Bad arguments are refused before anything is dispatched.
for args in "0 600" "--zone 0 0 1.5 1" "--zone 0 0 x 1" "--zone 0 0 1" "--move left" "--move sideways $spec" \
  '--move left {"layouts":[],"starred":0}' "--move left {\"layouts\":[$halves],\"starred\":1}" "--layout [[0,0,2,1]] --zone 0 0 1 1" "--layout $halves 800 600" \
  "--layout $halves --span 0 2" "--layout $halves --span x 1" "--layout $halves --span 0" "--span 0 1" "--grow left" \
  "--grow sideways $spec" "--restore 0xabc extra" "--restore window" "800 600 window"; do
  if "$root/bin/omasizer" $args 2>/dev/null; then echo "accepted: $args" >&2; exit 1; fi
done

# A stalled compositor can't pile helpers up: one runs at a time and is killed with everything
# it started after 5 s, and the rest wait at most a second, then drop their request.
mkdir -p "$tmp/stall"
printf '#!/bin/bash\nsleep 30\n' >"$tmp/stall/hyprctl"; chmod +x "$tmp/stall/hyprctl"
start=$SECONDS
for _ in 1 2 3 4 5; do PATH="$tmp/stall:$PATH" "$root/bin/omasizer" 800 600 >/dev/null 2>&1 & done
wait
(( SECONDS - start <= 7 )) || { echo "stalled helpers piled up for $((SECONDS - start)) s" >&2; exit 1; }
! pgrep -f "$tmp/stall/hyprctl" >/dev/null || { echo "a stalled hyprctl outlived its helper" >&2; exit 1; }

# A compositor that answers but stalls on the dispatch: the run, swap child included, is
# killed at its deadline, and leaves the lock free and no process behind.
sed 's/^dispatch\*).*/dispatch*) sleep 30 ;;/' "$tmp/hyprctl" >"$tmp/stall/hyprctl"
start=$SECONDS
memory_before=$(cat "$tmp/omasizer-layouts.json" 2>/dev/null || true)
PATH="$tmp/stall:$PATH" AT=12,68 SIZE=941,538 "$root/bin/omasizer" --layout "$quads" --zone 0.5 0 0.5 0.5 >/dev/null 2>&1 && { echo "a stalled dispatch reported success" >&2; exit 1; }
(( SECONDS - start <= 7 )) || { echo "a stalled dispatch held a run for $((SECONDS - start)) s" >&2; exit 1; }
flock -n "$tmp/omasizer.lock" true || { echo "the lock outlived a killed run" >&2; exit 1; }
! pgrep -f "$tmp/stall/hyprctl" >/dev/null || { echo "a stalled hyprctl outlived its helper" >&2; exit 1; }
[[ $(cat "$tmp/omasizer-layouts.json" 2>/dev/null || true) == "$memory_before" ]] || { echo "a killed run changed the layout memory" >&2; exit 1; }

# Nothing outside a sane size or the screen gets through.
for args in "99999999999999999999 1" "16385 600" "--zone 0.6 0 0.5 1"; do
  ! "$root/bin/omasizer" $args 2>/dev/null || { echo "accepted: $args" >&2; exit 1; }
done

echo ok
