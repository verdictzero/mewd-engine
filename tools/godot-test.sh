#!/bin/sh
# FENRIR — the terrain engine's headless suites (see GODOT.txt, TESTS). Exits
# non-zero if any of them fails. The places want baking first:
#   godot --headless --script res://tools/bake_island.gd -- --all --if-missing
cd "$(dirname "$0")/.." || exit 1
# (Godot 4.7: `godot47` where both are installed)
if [ -z "$GODOT" ]; then
  if command -v godot47 >/dev/null 2>&1; then GODOT=godot47; else GODOT=godot; fi
fi
fail=0
run() {
  echo "== $1"
  shift
  out=$("$GODOT" --headless "$@" 2>&1)
  code=$?
  echo "$out" | grep -E "ok|FAIL|OK|^==|SCRIPT ERROR" | grep -v "^ *at:" | tail -60
  [ $code -eq 0 ] || { echo "   exit $code"; fail=1; }
}
"$GODOT" --headless --editor --quit >/dev/null 2>&1   # register the class names
# A REAL PLACE (EarthField, tools/earth_fetch.py): the field against its own
# open data, then the place through the viewer — its water, its paint, its
# sky, the cinema, its shadows, its grade (godot/tests/earth_test.gd)
run earth   --script res://godot/tests/earth_test.gd -- --map=earth_oeschinen
# EVERY PLACE through the viewer: up, off its bake, planted, the eye over its
# ground, its picture, nothing of a game in it (godot/tests/terrain_test.gd)
run terrain --script res://godot/tests/terrain_test.gd
exit $fail
