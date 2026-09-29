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
run fire    --script res://godot/tests/fire_test.gd
run forest  --script res://godot/tests/forest_test.gd -- 7
run jesse   --script res://godot/tests/jesse_dump.gd -- /tmp/mewd-jesse.json 1 7
run sprawl  --script res://godot/tests/sprawl_dump.gd
# network play: the wire against the JS, a match over loopback, and a
# headless --server with two headless --join clients on a real socket
run net     --script res://godot/tests/net_test.gd
exit $fail
