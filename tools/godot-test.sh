#!/bin/sh
# MEWD — the Godot port's headless suites (see GODOT.txt). Exits non-zero
# if any of them fails.
cd "$(dirname "$0")/.." || exit 1
GODOT=${GODOT:-godot}
fail=0
run() {
  echo "== $1"
  shift
  out=$("$GODOT" --headless "$@" 2>&1)
  code=$?
  echo "$out" | grep -E "ok|FAIL|OK|weapons:|fire:|island" | grep -v "^ *at:" | tail -40
  [ $code -eq 0 ] || { echo "   exit $code"; fail=1; }
}
"$GODOT" --headless --editor --quit >/dev/null 2>&1   # register the class names
run weapons --script res://godot/tests/weapons_test.gd -- --seed=7
# THE ISLAND (at the user's request; godot/scripts/level/island_level.gd):
# the ground off the bake, you and the crowd on it, the coast, the hills,
# rounds and blasts into the ground — needs the island baked first:
#   godot --headless --script res://tools/bake_island.gd
run island  --script res://godot/tests/island_test.gd
# network play: the wire against the JS, a match over loopback, and a
# headless --server with two headless --join clients on a real socket
run net     --script res://godot/tests/net_test.gd
# the dead are gone: removed, and their sprites with them (godot/tests/death_test.gd)
run death   --script res://godot/tests/death_test.gd
# the pad: any device, the standard layout, the menus (godot/tests/pad_test.gd)
run pad     --script res://godot/tests/pad_test.gd
exit $fail
