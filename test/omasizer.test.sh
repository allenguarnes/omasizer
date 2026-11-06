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
"activewindow -j") echo '{"address":"0xabc","floating":true,"fullscreen":0,"monitor":0,"at":[300,200],"tags":["omarchy-floating-workspace","terminal*"]}' ;;
"clients -j") echo '[{"address":"0xdef","floating":false,"fullscreen":0,"monitor":0,"at":[5,5],"tags":[]}]' ;;
"monitors -j") echo '[{"id":0,"x":0,"y":0,"width":3200,"height":2000,"scale":1.6666666,"transform":0,"reserved":[0,26,0,0]}]' ;;
"getoption general:gaps_out") echo '{"css":"10 10 10 10"}' ;;
"getoption general:gaps_in") echo '{"css":"5 5 5 5"}' ;;
"getoption general:border_size") echo '{"int":2}' ;;
"getoption plugin:hyprbars:bar_height") echo '{"int":30}' ;;
dispatch*) [[ $2 == hl.* ]] && echo "$2" >>"$LOG" ;;
esac
STUB
chmod +x "$tmp/hyprctl"
export PATH="$tmp:$PATH" XDG_CONFIG_HOME="$tmp" LOG="$tmp/log"

run() {
  : >"$LOG"
  "$root/bin/omasizer" "$@"
  grep -E 'resize|move|center|float' "$LOG" | sed -E 's/window = "address:0x[a-f]+"(, )?//'
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

# Sizes clamp to the usable area and center, or keep their place when centering is off.
expect $'hl.dsp.window.resize({ x = 800, y = 600 })\nhl.dsp.window.center({  })' 800 600
expect $'hl.dsp.window.resize({ x = 1920, y = 1174 })\nhl.dsp.window.center({  })' 5000 5000
mkdir -p "$tmp/omarchy"; echo '{"plugins":[{"id":"omasizer","center":false,"clamp":false}]}' >"$tmp/omarchy/shell.json"
expect $'hl.dsp.window.resize({ x = 5000, y = 5000 })\nhl.dsp.window.move({ x = 300, y = 200 })' 5000 5000

# Bad arguments are refused before anything is dispatched.
for args in "0 600" "--zone 0 0 1.5 1" "--zone 0 0 x 1" "--zone 0 0 1"; do
  if "$root/bin/omasizer" $args 2>/dev/null; then echo "accepted: $args" >&2; exit 1; fi
done

echo ok
