## MEWD — the editor's LAYERS PANE (godot/scripts/editor/ed_layers.gd),
## Photoshop's way, headless, on THE ANNEXE (a map in two storeys):
##
##   godot --headless --script res://godot/tests/layers_pane_test.gd -- --edit
##
## Holds: the stack top first, the one being edited lit; a layer opened
## is its rooms, a room cut from another under it, every thing under the
## room it stands in; a click on a room selects it on its layer, and what
## the plan selects the pane shows; the eye hides a layer from the plan's
## ghosts and the 3D view's level (never the one being edited), Alt: one
## alone; rename, duplicate a storey up, move in the stack (each layer
## taking the other's height, its things with it), a drag doing the same,
## delete — each one undo step.
extends SceneTree

var fails := 0
var main: Node
var _kept := {}

func ok(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		fails += 1

func frames(n := 2) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	for f in [MewdEditor.AUTOSAVE, MewdEditor.PREFS]:
		_kept[f] = FileAccess.get_file_as_string(f) if FileAccess.file_exists(f) else null
	main = load("res://godot/scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	run()

func _restore() -> void:
	for f in _kept:
		if _kept[f] == null:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		else:
			var h := FileAccess.open(f, FileAccess.WRITE)
			h.store_string(_kept[f])

func rows(L: EdLayers) -> Array:
	var out := []
	for it in L.tree.get_root().get_children():
		out.append(it.get_metadata(0).k)
	return out

func find(it: TreeItem, kind: String, id) -> TreeItem:
	for c in it.get_children():
		var m = c.get_metadata(0)
		if m is Dictionary and m.kind == kind and m.id == id:
			return c
		var f := find(c, kind, id)
		if f != null:
			return f
	return null

func level_sectors(ed: MewdEditor) -> int:
	var lv = ed.compiled.get("level")
	return -1 if lv == null else lv.sectors.size()

func run() -> void:
	await frames(5)
	var ed: MewdEditor = main.editor
	ok(ed != null and ed.ui != null, "--edit opens the editor")
	if ed == null:
		_restore()
		quit(1)
		return
	ed.file_demo("layers")
	await frames(3)
	var P: EdPanels = ed.ui.panels
	P.show_tab("layers")
	await frames(3)
	var L: EdLayers = P.layers
	ok(L.box.visible and L.tree != null, "the Layers tab shows the pane")
	ok(rows(L) == [1, 0], "the stack, the top storey first (%s)" % [rows(L)])
	var ground: TreeItem = L._layer_items[0]
	var up: TreeItem = L._layer_items[1]
	ok(ground.get_text(0) == "Ground" and up.get_text(0) == "Storey 1", "named by default (%s, %s)" % [up.get_text(0), ground.get_text(0)])
	ok(ground.get_icon(0) != null and ground.get_icon(0).get_width() == EdLayers.THUMB.x, "each with a thumbnail of its plan")
	ok(ground.get_button_count(1) == 1, "and an eye")
	ok(ground.get_custom_bg_color(0) != Color(0, 0, 0, 0) and ed.layer() == 0, "the layer being edited is lit")

	# OPENED: the hierarchy
	ground.collapsed = false
	await frames(2)
	var g := EdDoc.layer_geom(ed.doc, 0)
	var parents := EdDoc.hole_parents(g)
	var nested := -1
	for i in parents.size():
		if parents[i] >= 0:
			nested = i
	var top_n := 0
	for c in ground.get_children():
		if c.get_metadata(0) is Dictionary and c.get_metadata(0).kind == "sector":
			top_n += 1
	var roots := 0
	for i in parents.size():
		if parents[i] < 0:
			roots += 1
	ok(top_n == roots, "opened: its rooms (%d at the top of %d)" % [top_n, g.sectors.size()])
	if nested >= 0:
		var it := find(ground, "sector", g.sectors[nested].id)
		ok(it != null and it.get_parent().get_metadata(0).get("id") == g.sectors[parents[nested]].id,
			"a room cut from another is under it")
	var th = null
	for t in ed.doc.things:
		if int(EdDoc.num(t.get("layer"), 0)) == 0:
			th = t
			break
	if th != null:
		var ti := find(ground, "thing", th.id)
		var own = EdDoc.sector_in(g, th.x, th.y)
		var pm = ti.get_parent().get_metadata(0) if ti != null else null
		ok(ti != null and ((own == null and pm.kind == "layer") or (own != null and pm.get("id") == own.id)),
			"a thing is under the room it stands in")

	# SELECTION, both ways
	var s0 = g.sectors[0]
	var si := find(ground, "sector", s0.id)
	si.select(0)
	L._clicked = si
	L._apply_sel()
	ok(ed.sel_kind == "sector" and ed.sel_ids.has(s0.id) and ed.mode == "sectors", "a click on a room selects it in the map")
	var s1 = g.sectors[g.sectors.size() - 1]
	ed.select("sector", [s1.id])
	await frames(2)
	var si1 := find(ground, "sector", s1.id)
	ok(si1 != null and si1.is_selected(0) and not find(ground, "sector", s0.id).is_selected(0), "what the plan selects the pane shows")
	# a room upstairs: its layer is opened for editing
	var ug := EdDoc.layer_geom(ed.doc, 1)
	up.collapsed = false
	await frames(2)
	var ui := find(L._layer_items[1], "sector", ug.sectors[0].id)
	ui.select(0)
	L._clicked = ui
	L._apply_sel()
	await frames(3)
	ok(ed.layer() == 1 and ed.sel_ids.has(ug.sectors[0].id), "a room on another layer: that layer is edited, the room selected")
	ok(L._layer_items[1].get_custom_bg_color(0) != Color(0, 0, 0, 0), "and it is lit")
	ed.set_layer(0)
	await frames(3)

	# THE EYE
	ed.compile_now()
	var whole := level_sectors(ed)
	var probs: int = ed.compiled.problems.size()
	ed.set_layer_hidden(0, true)
	ok(not ed.layer_hidden(0), "the layer being edited cannot be hidden")
	L._on_button(L._layer_items[1], 1, 0, MOUSE_BUTTON_LEFT)
	await frames(3)
	ed.compile_now()
	ok(ed.layer_hidden(1) and ed.other_layers().is_empty(), "the eye hides the upstairs from the plan")
	ok(level_sectors(ed) < whole and level_sectors(ed) > 0, "and from the 3D view's level (%d of %d sectors)" % [level_sectors(ed), whole])
	L.render()     # (the pane redraws on a timer; not waited for here)
	ok(L._layer_items[1].get_button(1, 0) == L._eye_shut, "the eye shut")
	ok(ed.compiled.problems.size() == probs, "the problems are still the whole map's (%d)" % probs)
	L._on_button(L._layer_items[1], 1, 0, MOUSE_BUTTON_LEFT)
	ed.compile_now()
	ok(not ed.layer_hidden(1) and level_sectors(ed) == whole, "again: shown")
	L.solo(0)
	ok(ed.layer_hidden(1), "Alt: the ground alone")
	L.solo(0)
	ok(not ed.layer_hidden(1), "again: all of them")

	# RENAME, one undo step
	ed.rename_layer(1, "Terrace")
	await frames(3)
	ok(EdDoc.layer_name(ed.doc, 1) == "Terrace" and L._layer_items[1].get_text(0) == "Terrace", "renamed: Terrace")
	var saved := EdDoc.parse(EdDoc.to_json(ed.doc))
	ok(EdDoc.layer_name(saved.doc, 1) == "Terrace", "and the name is kept in the file")
	ed.undo()
	ok(EdDoc.layer_name(ed.doc, 1) == "Storey 1", "undone")
	ed.redo()

	# MOVE IN THE STACK: the ground and the terrace change places
	var up_floor = EdDoc._base_of(EdDoc.layer_geom(ed.doc, 1))
	var gr_floor = EdDoc._base_of(EdDoc.layer_geom(ed.doc, 0))
	var n_up: int = EdDoc.layer_geom(ed.doc, 1).sectors.size()
	var n_gr: int = EdDoc.layer_geom(ed.doc, 0).sectors.size()
	var things_up: int = ed.doc.things.filter(func(t): return int(EdDoc.num(t.get("layer"), 0)) == 1).size()
	ed.move_layer(1, -1)
	await frames(3)
	var g0 := EdDoc.layer_geom(ed.doc, 0)
	var g1 := EdDoc.layer_geom(ed.doc, 1)
	ok(g0.sectors.size() == n_up and g1.sectors.size() == n_gr, "moved down: the terrace is layer 0, the ground layer 1")
	ok(EdDoc._base_of(g0) == gr_floor and EdDoc._base_of(g1) == up_floor, "each at the other's height (%s, %s)" % [EdDoc._base_of(g0), EdDoc._base_of(g1)])
	ok(EdDoc.layer_name(ed.doc, 0) == "Terrace" and ed.layer() == 1, "its name with it; the ground, edited, went up with it")
	ok(ed.doc.things.filter(func(t): return int(EdDoc.num(t.get("layer"), 0)) == 0).size() == things_up, "its things with it")
	ok(rows(L) == [1, 0] and L._layer_items[0].get_text(0) == "Terrace", "the pane shows it")
	ed.undo()
	ok(EdDoc.layer_geom(ed.doc, 1).sectors.size() == n_up and EdDoc.layer_name(ed.doc, 1) == "Terrace", "undone, in one step")
	# by dragging: the ground onto the terrace
	await frames(2)
	var data = {"mewd_layer": 0}
	ed.move_layer_to(0, 1)
	ok(EdDoc.layer_geom(ed.doc, 1).sectors.size() == n_gr, "dragged up the stack, the same")
	ed.undo()
	ok(data.mewd_layer == 0 and EdDoc.layer_geom(ed.doc, 0).sectors.size() == n_gr, "undone")

	# DUPLICATE: a storey up
	await frames(2)
	ed.set_layer(1)
	ed.duplicate_layer(1)
	await frames(3)
	var g2 := EdDoc.layer_geom(ed.doc, 2)
	ok(g2.sectors.size() == n_up and ed.layer() == 2, "duplicated onto layer 2, and edited")
	ok(EdDoc._base_of(g2) == up_floor + EdDoc.STOREY_H, "a storey up (%s)" % EdDoc._base_of(g2))
	var ids := {}
	var unique := true
	for k in [0, 1, 2]:
		for s in EdDoc.layer_geom(ed.doc, k).sectors:
			if ids.has(s.id):
				unique = false
			ids[s.id] = true
	ok(unique, "its rooms new ids")
	ok(EdDoc.layer_name(ed.doc, 2) == "Terrace copy" and rows(L) == [2, 1, 0], "named, and on top of the stack")

	# DELETE
	ed.delete_layer(2)
	await frames(3)
	ok(not EdDoc.layer_filled(ed.doc, 2) and not ed.doc.things.any(func(t): return int(EdDoc.num(t.get("layer"), 0)) == 2), "deleted, its things too")
	ed.undo()
	ok(EdDoc.layer_geom(ed.doc, 2).sectors.size() == n_up, "undone")
	# a new layer on top
	L.new_layer()
	ok(ed.layer() == 3, "+ New: a new layer on top (%d)" % ed.layer())
	ed.set_layer(0)
	await frames(3)
	ok(rows(L) == [2, 1, 0], "an empty layer left is not in the stack")
	ed.compile_now()
	ok(ed.compiled.level != null, "the map still builds")
	print("layers pane: %s" % ("OK" if fails == 0 else "%d FAILED" % fails))
	_restore()
	quit(1 if fails else 0)
