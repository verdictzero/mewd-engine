## MEWD Editor — a script of edits (godot/tests/editor_ops.json's
## format): the same operations the views and the keyboard make, run in
## order. The parity test (godot/tests/editor_test.gd) runs one against
## the web build's editor; `--edit --edit-ops=FILE` runs one in the real
## editor for pictures (with a few more ops that drive the workspace:
## layout, visual, camera, tab, demo, hover...).
class_name EdScript

## the parity test measures every texture as 64 (the web build's bank is
## not there headless); the real editor measures them
static var zero_sizes := false

static func run(ed: MewdEditor, ops: Array, checkpoint := Callable()) -> void:
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
				EdDoc.align_textures(d, ed.sel_ids.keys(), a[0], zero if zero_sizes else ed.tex_size)
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
			"wait":
				if ed.is_inside_tree():
					for i in int(a[0]) if a.size() > 0 else 2:
						await ed.get_tree().process_frame
			"checkpoint":
				if checkpoint.is_valid():
					checkpoint.call(a[0])
			_:
				if not ui_op(ed, k, a):
					push_warning("EdScript: unknown op %s" % k)

## The ops that drive the workspace rather than the document.
static func ui_op(ed: MewdEditor, k: String, a: Array) -> bool:
	match k:
		"layout": ed.set_layout(a[0])
		"demo": ed.file_demo(a[0])
		"new": ed.file_new(a[0] if a.size() > 0 else false)
		"open": ed.open_from(a[0])
		"frame": ed.frame_req.emit()
		"frameSel": ed.frame_sel_req.emit()
		"planView":
			ed.plan_view = a[0]
			ed.grid_changed.emit()
		"grid": ed.set_grid(int(a[0]))
		"snap": ed.set_snap(a[0])
		"tab":
			if ed.ui != null:
				ed.ui.panels.show_tab(a[0])
		"visual":
			if ed.view3d != null:
				ed.view3d.toggle_visual(a[0])
		"fullbright":
			if ed.view3d != null:
				ed.view3d.set_fullbright(a[0])
		"cam":
			if ed.view3d != null:
				ed.view3d.cam = {"x": float(a[0]), "y": float(a[1]), "z": float(a[2]), "yaw": deg_to_rad(float(a[3])), "pitch": deg_to_rad(float(a[4]))}
				ed.camera_changed.emit()
		"hover3d":
			if ed.view3d != null:
				ed.view3d.mouse = Vector2(a[0], a[1])
				ed.view3d._hover_dirty = true
		"view2d":
			if ed.view2d != null:
				ed.view2d.cx = float(a[0])
				ed.view2d.cy = float(a[1])
				ed.view2d.scale_ = float(a[2])
				ed.view2d.queue_redraw()
		"texeditor":
			if ed.ui != null:
				ed.ui.open_texture_editor(a[0], a[1] if a.size() > 1 else "GRIDWALL")
		"pick":
			if ed.ui != null:
				ed.ui.panels.picking = {"field": a[0], "label": a[1], "allow_none": true}
				ed.ui.panels.show_tab("tex")
		"say": ed.say(a[0])
		"pathPoint": ed.add_path_point(Vector2(a[0], a[1]))
		"menu":
			# open a top-bar menu by its title, for pictures
			if ed.ui != null:
				for c in ed.ui.top.get_children():
					if c is MenuButton and c.text == a[0]:
						c.show_popup()
		"play": ed.play()
		_:
			return false
	return true
