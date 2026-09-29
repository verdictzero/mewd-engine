## MEWD — the editor against the web build's editor.
##
##   godot --headless --script res://godot/tests/editor_test.gd
##
## Runs the script of edits in godot/tests/editor_ops.json — rooms drawn
## as shapes, a room split along a path, linedefs closing into a sector,
## things, props, heights, brightness, stairs and rings, a line deleted to
## merge two rooms, texture alignment, vertex and sector drags, a vertex
## inserted into a wall, scatters, copy and paste, undo and redo, a layer
## — through the port's MewdEditor (godot/scripts/editor/), and at each
## checkpoint holds its document to the one js/editor/editor.js made from
## the same script (godot/tests/editor_ref.json, written by
## godot/tests/editor_js.mjs): every vertex, sector, line override,
## linedef, thing, prop and scatter, the problem report, the selection,
## and what the compiler builds from it. Then the files: a document
## written by the web build opens here and is written back the same, and
## undo goes all the way back to the empty map.
extends SceneTree

var fails := 0
var checks := 0

func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL ", what)

## Every difference between two JSON values, as paths.
func diff(a, b, path := "", out := []) -> Array:
	if out.size() > 30:
		return out
	if (a is float or a is int) and (b is float or b is int):
		if absf(float(a) - float(b)) > 1e-3 * maxf(1.0, absf(float(b)) * 1e-3):
			out.append("%s: %s != %s" % [path, a, b])
		return out
	if typeof(a) != typeof(b):
		out.append("%s: %s != %s" % [path, JSON.stringify(a).left(80), JSON.stringify(b).left(80)])
		return out
	if a is Dictionary:
		for k in a:
			if not b.has(k):
				out.append("%s.%s: only here (%s)" % [path, k, JSON.stringify(a[k]).left(60)])
			else:
				diff(a[k], b[k], "%s.%s" % [path, k], out)
		for k in b:
			if not a.has(k):
				out.append("%s.%s: only in the web build's (%s)" % [path, k, JSON.stringify(b[k]).left(60)])
		return out
	if a is Array:
		if a.size() != b.size():
			out.append("%s: %d items != %d" % [path, a.size(), b.size()])
			return out
		for i in a.size():
			diff(a[i], b[i], "%s[%d]" % [path, i], out)
		return out
	if a != b:
		out.append("%s: %s != %s" % [path, a, b])
	return out

func run_ops(ed: MewdEditor, ops: Array, ref: Dictionary) -> void:
	var zero := func(_n): return Vector2.ZERO
	for op in ops:
		var k: String = op[0]
		var a: Array = op.slice(1)
		match k:
			"rect": ed.add_rect(Vector2(a[0][0], a[0][1]), Vector2(a[1][0], a[1][1]))
			"shape": ed.set_shape(a[0], a[1] if a[1] == null else int(a[1]))
			"select": ed.select(a[0], a[1].map(func(x): return int(x)))
			"selectSectorAt":
				var s = ed.sector_at(a[0], a[1])
				ed.select("sector", [s.id] if s != null else [])
			"selectLineAt":
				var best = null
				var bd := 16.0
				for l in ed.lines():
					var d := EdDoc.seg_dist(ed.doc.vertices[l.a], ed.doc.vertices[l.b], Vector2(a[0], a[1])).x
					if d < bd:
						bd = d
						best = l.key
				ed.select("line", [best] if best != null else [])
			"selectLinesIn":
				var V: Array = ed.doc.vertices
				var inb := func(p: Vector2) -> bool: return p.x >= a[0] and p.x <= a[2] and p.y >= a[1] and p.y <= a[3]
				var keys := []
				for l in ed.lines():
					if inb.call(V[l.a]) and inb.call(V[l.b]):
						keys.append(l.key)
				ed.select("line", keys)
			"selectVertexAt":
				var idx := -1
				for i in ed.doc.vertices.size():
					if ed.doc.vertices[i].distance_to(Vector2(a[0], a[1])) < 0.5:
						idx = i
						break
				ed.select("vertex", [idx] if idx >= 0 else [])
			"selectThingType":
				var ids := []
				for t in ed.doc.things:
					if t.type == a[0]:
						ids.append(t.id)
				ed.select("thing", ids)
			"inside": ed.set_inside(a[0])
			"path":
				ed.path = a[0].map(func(p): return Vector2(p[0], p[1]))
				ed.close_path(a[1])
			"linedefs": ed.add_linedefs(PackedVector2Array(a[0].map(func(p): return Vector2(p[0], p[1]))))
			"sector": ed.add_sector(PackedVector2Array(a[0].map(func(p): return Vector2(p[0], p[1]))))
			"thingType": ed.thing_type = a[0]
			"thing": ed.add_thing(a[0], a[1])
			"prop": ed.add_prop(a[0], a[1], a[2], a[3])
			"height": ed.nudge_height(a[0], a[1])
			"light": ed.nudge_light(int(a[0]))
			"stairs": ed.make_steps("stairs", a[0])
			"rings": ed.make_steps("rings", a[0])
			"mode": ed.set_mode(a[0])
			"delete": ed.delete_sel()
			"align":
				# the web build's bank is not there headless: every texture 64
				var d := ed.edit_begin("align")
				EdDoc.align_textures(d, ed.sel_ids.keys(), a[0], zero)
				ed.edit_end(false)
			"move":
				var at := Vector2(a[0][0], a[0][1])
				var dr := ed.begin_move(ed.grab_point(at), at)
				ed.drag_move(dr, Vector2(a[1][0], a[1][1]), float(a[2]))
				ed.end_move(dr)
			"cursor": ed.set_cursor(Vector2(a[0], a[1]))
			"insertVertex": ed.insert_at_cursor()
			"scatter":
				var d := ed.edit_begin("scatter")
				var area: Dictionary = a[1].duplicate(true)
				if area.get("ids") is Array:
					area.ids = area.ids.map(func(x): return int(x))
				var made := EdScatter.scatter_from(a[0], area, EdDoc.take_id(d), int(a[2]))
				d.scatters.append(made)
				ed.edit_end(false)
				ed.select("scatter", [made.id])
			"copy": ed.copy_sel()
			"paste": ed.paste(a[0])
			"nudge": ed.move_sel(a[0], a[1], "nudge")
			"texture": ed.apply_texture(a[0], a[1])
			"undo": ed.undo()
			"redo": ed.redo()
			"layer": ed.set_layer(int(a[0]))
			"checkpoint": check_point(ed, a[0], ref.checkpoints[a[0]])
			_: ok(false, "unknown op %s" % k)

func check_point(ed: MewdEditor, name: String, want: Dictionary) -> void:
	# the document, as the file the web build writes
	var mine = JSON.parse_string(EdDoc.to_json(ed.doc))
	var d := diff(mine, want.doc, name)
	ok(d.is_empty(), "%s: the document is the web build's (%d differences)" % [name, d.size()])
	for x in d.slice(0, 12):
		print("   ", x)
	# the problems
	var probs := EdDoc.problems_of(ed.doc).map(func(p): return p.msg)
	ok(probs == want.problems, "%s: problems %s == %s" % [name, probs, want.problems])
	# the selection
	var sk = ed.sel_kind if ed.sel_kind != "" else null
	ok(sk == want.sel.kind, "%s: selection kind %s == %s" % [name, sk, want.sel.kind])
	var ids := ed.sel_ids.keys()
	var wids: Array = want.sel.ids
	ok(JSON.stringify(ids) == JSON.stringify(wids), "%s: selection %s == %s" % [name, ids, wids])
	# the build: the web build compiles every layer as columns of rooms,
	# which the Godot engine does not have, so a layered map is held only
	# to the ground layer's own build (the checkpoint before it)
	if EdDoc.is_layered(ed.doc):
		print("   %s: layered — %d layers; the ground is built" % [name, EdDoc.layers_of(ed.doc).size()])
		return
	ed.compile_now()
	var lv: Level = ed.compiled.level
	var b: Dictionary = want.built
	ok(lv.sectors.size() == b.sectors, "%s: built %d sectors == %d" % [name, lv.sectors.size(), b.sectors])
	ok(lv.lines.size() == b.lines, "%s: built %d lines == %d" % [name, lv.lines.size(), b.lines])
	# (the web build's level.things leaves the plants out: they are
	# level.plants; DocCompile keeps them in both, and the game spawns none)
	var nth := 0
	for t in lv.things:
		if t.type != "PLANT" and EdDoc.THING_TYPES.has(t.type):
			nth += 1
	ok(nth == b.things, "%s: built %d things == %d" % [name, nth, b.things])
	ok(lv.plants.size() == b.plants, "%s: built %d plants == %d" % [name, lv.plants.size(), b.plants])
	for id in b.grown:
		var g = ed.compiled.grown.get(int(id))
		ok(g != null and g.grown == b.grown[id], "%s: scatter %s grew %s == %s" % [name, id, g.grown if g != null else null, b.grown[id]])
	print("   %s: %d vertices, %d sectors — built %d sectors, %d lines, %d things" % [name, ed.doc.vertices.size(), ed.doc.sectors.size(),
		lv.sectors.size(), lv.lines.size(), lv.things.size()])

func _init() -> void:
	var ops = JSON.parse_string(FileAccess.get_file_as_string("res://godot/tests/editor_ops.json"))
	var ref = JSON.parse_string(FileAccess.get_file_as_string("res://godot/tests/editor_ref.json"))
	var ed := MewdEditor.new(EdDoc.new_doc("EDITOR TEST", 4096), true)
	ed.grid = 64
	ed.snap = true
	var t0 := Time.get_ticks_msec()
	run_ops(ed, ops, ref)
	print("editor: %d edits in %d ms" % [ops.size(), Time.get_ticks_msec() - t0])

	# FILES: the web build's document opens here and is written back the same
	for name in ref.checkpoints:
		var text := JSON.stringify(ref.checkpoints[name].doc)
		var r := EdDoc.parse(text)
		ok(not r.has("error"), "%s: the web build's file opens" % name)
		if r.has("error"):
			continue
		var back = JSON.parse_string(EdDoc.to_json(r.doc))
		var d := diff(back, ref.checkpoints[name].doc, "file." + name)
		ok(d.is_empty(), "%s: opened and saved, the file is the same (%d differences)" % [name, d.size()])
		for x in d.slice(0, 6):
			print("   ", x)
	ok(EdDoc.parse("{\"format\": \"not-ours\"}").has("error"), "a file that is not a map is refused")

	# UNDO, all the way back to the empty map, and forward again
	var last := EdDoc.to_json(ed.doc)
	var n := 0
	while ed.history.undo() != null:
		n += 1
	var empty := EdDoc.new_doc("EDITOR TEST", 4096)
	var d0 := diff(JSON.parse_string(EdDoc.to_json(ed.doc)), JSON.parse_string(EdDoc.to_json(empty)), "undone")
	ok(d0.is_empty(), "%d undos go back to the empty map" % n)
	while ed.history.redo() != null:
		pass
	ok(EdDoc.to_json(ed.doc) == last, "and redo comes back to the last edit")

	# THE DEMO MAPS open, compile and save
	for which in ["maze", "sprawl", "grid", "jesse"]:
		var t := Time.get_ticks_msec()
		ed.file_demo(which)
		ed.compile_now()
		var lv: Level = ed.compiled.level
		ok(lv != null and lv.sectors.size() > 0, "%s opens and builds" % which)
		var r := EdDoc.parse(EdDoc.to_json(ed.doc))
		ok(not r.has("error") and r.doc.sectors.size() == ed.doc.sectors.size(), "%s saves and opens again" % which)
		print("   %s: %d sectors, %d problems, %d ms" % [which, ed.doc.sectors.size(), ed.compiled.problems.size(), Time.get_ticks_msec() - t])

	print("editor: %d checks, %s" % [checks, "OK" if fails == 0 else "%d FAIL" % fails])
	quit(1 if fails else 0)
