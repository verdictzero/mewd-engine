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
  echo "$out" | grep -E "ok|FAIL|OK|weapons:|fire:|forest:|jesse|SPRAWL|GRID" | grep -v "^ *at:" | tail -40
  [ $code -eq 0 ] || { echo "   exit $code"; fail=1; }
}
"$GODOT" --headless --editor --quit >/dev/null 2>&1   # register the class names
run weapons --script res://godot/tests/weapons_test.gd -- --seed=7
run forest  --script res://godot/tests/forest_test.gd -- 7
run jesse   --script res://godot/tests/jesse_dump.gd -- /tmp/mewd-jesse.json 1 7
run sprawl  --script res://godot/tests/sprawl_dump.gd
# network play: the wire against the JS, a match over loopback, and a
# headless --server with two headless --join clients on a real socket
run net     --script res://godot/tests/net_test.gd
# MEWD Editor: its edits and its files against the web build's editor
# (godot/tests/editor_ref.json, from godot/tests/editor_js.mjs), and the
# editor driven by input events, to the game and back
run editor  --script res://godot/tests/editor_test.gd
run editorui --script res://godot/tests/editor_ui_test.gd -- --edit
# ROOM OVER ROOM: a map in the editor's layers, compiled whole and played
# (godot/tests/layers_test.gd on THE ANNEXE, godot/scripts/maps/layers.gd)
run layers  --script res://godot/tests/layers_test.gd -- --map=layers
exit $fail
