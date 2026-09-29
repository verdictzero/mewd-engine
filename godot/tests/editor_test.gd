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
	# the build — a map in layers too: every layer laid over the others
	# and built as columns of rooms, as the web build builds it
	# (with the web build's thin walls: the Godot build's own are thick)
	DocCompile.thick = false
	ed.compile_now()
	DocCompile.thick = true
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
	EdScript.zero_sizes = true
	var ed := MewdEditor.new(EdDoc.new_doc("EDITOR TEST", 4096), true)
	ed.grid = 64
	ed.snap = true
	var t0 := Time.get_ticks_msec()
	EdScript.run(ed, ops, func(name): check_point(ed, name, ref.checkpoints[name]))
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

	# THE MAP'S OWN TEXTURES (texcompose): an imported picture, tiled; a
	# game texture tinted; the bank has them by name
	var red := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	red.fill(Color(1, 0, 0, 1))
	var url := EdTex.image_to_url(red)
	ok(url.begins_with("data:image/png;base64,"), "an imported picture is kept as a PNG data URL, as the web build keeps it")
	var L1 := EdTex.new_layer(null)
	L1.image = url
	var def := {"name": "REDTILE", "w": 8, "h": 8, "worldW": 64, "worldH": 32, "layers": [L1]}
	var img := EdTex.compose(def)
	ok(img.get_width() == 8 and img.get_pixel(5, 6).is_equal_approx(Color(1, 0, 0, 1)), "the picture tiles across the texture")
	var L2 := EdTex.new_layer("GRIDWALL")
	L2.tint = "#ff0000"
	var tinted := EdTex.compose({"name": "T2", "w": 16, "h": 16, "layers": [L2]})
	var any_green := false
	for y in 16:
		for x in 16:
			if tinted.get_pixel(x, y).g > 0.01:
				any_green = true
	ok(not any_green, "a red tint leaves no green")
	var L3 := EdTex.new_layer(null)
	L3.image = url
	L3.blend = "multiply"
	var L4 := EdTex.new_layer("GRIDWALL")
	var mult := EdTex.compose({"name": "T3", "w": 4, "h": 4, "layers": [L4, L3]})
	ok(mult.get_pixel(1, 1).g < 0.01, "multiply by red keeps only red")
	ok(EdTex.check({"name": "GRIDWALL", "w": 8, "h": 8, "layers": []}, EdTex.built_in()) != "", "a texture may not take a game texture's name")
	ed.replace(EdDoc.new_doc("TEX TEST", 2048), "tex test")
	ed.edit("texture", func(d): d.textures.append(def), false)
	ok(TexBank.map_own.has("REDTILE") and TexBank.new().size_of("REDTILE") == Vector2(64, 32), "the map's texture is in the bank, at its world size")
	ok(ed.map_texture_names.has("REDTILE") and ed.texture_names.has("REDTILE"), "and in the browser")
	ed.select("sector", [1])
	ed.apply_texture("REDTILE", "floorTex")
	var back = EdDoc.parse(EdDoc.to_json(ed.doc))
	ok(back.doc.textures[0].layers[0].image == url and back.doc.sectors[0].floorTex == "REDTILE", "it saves in the map, and a floor wears it")

	# BAKE: a scatter's things as ordinary things, the rule gone
	var d2 := ed.edit_begin("scatter")
	var sc := EdScatter.scatter_from("crowd", {"kind": "circle", "x": 1024, "y": 1024, "r": 600}, EdDoc.take_id(d2), 4242)
	d2.scatters.append(sc)
	ed.edit_end(false)
	ed.compile_now()
	var grown: int = ed.compiled.grown[sc.id].grown
	var nt: int = ed.doc.things.size()
	ed.select("scatter", [sc.id])
	ed.bake()
	ok(grown > 0 and ed.doc.things.size() == nt + grown and ed.doc.scatters.is_empty(), "bake turns %d grown into things and drops the rule" % grown)

	# LAYERS: a room on the layer above stands on the room under it
	ed.replace(EdDoc.new_doc("LAYERS", 2048), "layers")
	ed.add_rect(Vector2(256, 256), Vector2(768, 768))
	ed.select("sector", [2])
	ed.set_inside(true)
	var under = ed.sector_by_id(2)
	ed.set_layer(1)
	ok(ed.layer() == 1 and ed.doc.sectors.is_empty(), "layer 1 is a plan of its own")
	ed.add_rect(Vector2(256, 256), Vector2(768, 768))
	var up = ed.doc.sectors[0] if not ed.doc.sectors.is_empty() else {}
	ok(EdDoc.num(up.get("floor"), -1) == EdDoc.num(under.ceil), "a room drawn on it stands on the room under (floor %s = ceiling %s)" % [up.get("floor"), under.ceil])
	ed.set_layer(0)
	ok(ed.doc.sectors.size() == 2 and EdDoc.is_layered(ed.doc), "and the ground comes back, the storey kept")
	ed.compile_now()
	ok(ed.compiled.level != null and ed.compiled.level.sectors.size() >= 2, "a layered map builds (its ground)")

	print("editor: %d checks, %s" % [checks, "OK" if fails == 0 else "%d FAIL" % fails])
	ed.free()
	quit(1 if fails else 0)
