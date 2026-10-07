#!/bin/sh
# MEWD — the Godot port's headless suites (see GODOT.txt). Exits non-zero
# if any of them fails.
cd "$(dirname "$0")/.." || exit 1
# (Godot 4.7: `godot47` where both are installed, as here, where a plain
# `godot` is an older one whose islands hash to other bakes)
if [ -z "$GODOT" ]; then
  if command -v godot47 >/dev/null 2>&1; then GODOT=godot47; else GODOT=godot; fi
fi
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
run candyland --script res://godot/tests/island_test.gd -- --map=candyland
# CANDY LAND: roads, lamps, the candy girls greeting you and running (godot/tests/candy_test.gd)
run candy   --script res://godot/tests/candy_test.gd -- --map=candyland
# WHAT ROUNDS AND BLASTS DO TO SPRITES: bites out of people, lamps shot to
# pieces, plants blown up, set alight and shot through (godot/tests/damage_test.gd)
run damage  --script res://godot/tests/damage_test.gd -- --map=candyland
# network play: the wire against the JS, a match over loopback, and a
# headless --server with two headless --join clients on a real socket
run net     --script res://godot/tests/net_test.gd
# TEAMS: two sides, no friendly fire, a side's score and its win, a
# teammate dropped beside its own (godot/tests/teams_test.gd)
run teams   --script res://godot/tests/teams_test.gd
# THE VERSION, THE DISTANCE PAGE, THE SETTINGS FILE AND THE SERVER'S
# CONSOLE (godot/tests/options_test.gd)
run options --script res://godot/tests/options_test.gd -- --map=candyland
# the dead are gone: removed, and their sprites with them (godot/tests/death_test.gd)
run death   --script res://godot/tests/death_test.gd
# THE DROP: the pod read off its file, the ride down on the autopilot, the
# landing, the door, the hands on the stick (godot/tests/drop_test.gd)
run drop    --script res://godot/tests/drop_test.gd -- --map=candyland
# THE UNICORNS FIGHT BACK: the fury, the beam through you, the charge and
# the ram (godot/tests/unicorn_test.gd)
run unicorn --script res://godot/tests/unicorn_test.gd -- --map=candyland
# YOU DIED: the burst, the stone, the death camera, the fountain for ever,
# and a press for the level again (godot/tests/you_died_test.gd)
run youdied --script res://godot/tests/you_died_test.gd -- --map=candyland
# CANDY LAND's music: its two tracks crossfading round and round, and the
# dirge taking over (godot/tests/music_test.gd)
run music   --audio-driver Dummy --script res://godot/tests/music_test.gd
# the pad: any device, the standard layout, the menus (godot/tests/pad_test.gd)
run pad     --script res://godot/tests/pad_test.gd
# THE PICKUPS, finite ammo, armour on top of health, and IDDQD — on the
# roaded island and the roadless one (godot/tests/pickup_test.gd)
run pickups --script res://godot/tests/pickup_test.gd -- --map=candyland --seed=7
run pickups0 --script res://godot/tests/pickup_test.gd -- --map=island0 --seed=7
run pickupsd --script res://godot/tests/pickup_test.gd -- --map=debugland --seed=7
# MAZE LAND: the maze in the plus of five sections, its walls stopping
# bodies, rounds and eyes, grass only beside them (godot/tests/maze_test.gd)
run maze    --script res://godot/tests/maze_test.gd -- --map=mazeland
# THE HOUSE STYLE (golf's): no hue, cut corners, the title's logo the same
# size on every page of the menu (godot/tests/ui_test.gd)
run ui      --script res://godot/tests/ui_test.gd
exit $fail
