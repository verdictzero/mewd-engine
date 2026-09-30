## MEWD Editor — THE LAYERS PANE, Photoshop's, at the user's request: the
## map's layers (its storeys) as a stack, the top one at the top, each
## with a thumbnail of its plan, its name and an eye; and under each, its
## HIERARCHY — its rooms, a room cut out of another (a pillar, a pit, a
## platform) under the one it is cut from, and every thing under the room
## it stands in (the ones in no room at the end).
##
##   click a layer        edit it (the layer being edited is lit)
##   the eye              hide it: not ghosted in the plan, and left out
##                        of the 3D view (the map keeps it; the one being
##                        edited is always shown). Alt+click: that one
##                        alone, again: all of them
##   double-click         rename it
##   drag it              up or down the stack: it swaps places with the
##                        layers it passes, each taking the other's height
##   right-click          rename, duplicate, up, down, alone, delete
##   click a room/thing   select it (Ctrl/Shift for more), on its layer;
##                        double-click frames it
##   along the bottom     a new layer on top, duplicate, up, down, delete
##
## What is selected in the plan is selected here, and the other way.
class_name EdLayers
extends RefCounted

const THUMB := Vector2i(40, 26)

var ed: MewdEditor
var ui: EdUI
var box: VBoxContainer
var tree: Tree
var menu: PopupMenu
## what is opened, by path ("3", "3/s12"): kept across rebuilds
var _open := {}
var _syncing := false
var _sel_queued := false
var _items := {}
var _layer_items := {}
var _icons := {}
var _eye: Texture2D
var _eye_shut: Texture2D
var _menu_k := 0
var _clicked: TreeItem = null

func _init(editor: MewdEditor, frame: EdUI) -> void:
	ed = editor
	ui = frame

func build(parent: Control) -> Control:
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 6
	box.offset_right = -6
	box.offset_top = 4
	box.offset_bottom = -6
	parent.add_child(box)
	box.add_child(EdStyle.note("The map's layers, top storey first. Click one to edit it, the eye to hide it, double-click to rename, drag to move it in the stack; open one for its rooms and things."))
	tree = Tree.new()
	tree.columns = 2
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_MULTI
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.focus_mode = Control.FOCUS_CLICK
	tree.set_column_expand(0, true)
	tree.set_column_expand(1, false)
	tree.set_column_custom_minimum_width(1, 26)
	tree.add_theme_stylebox_override("panel", EdStyle.box(EdStyle.FIELD, EdStyle.LINE, 3, 1, Vector4(2, 2, 2, 2)))
	tree.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	tree.add_theme_stylebox_override("selected", EdStyle.box(Color("#3a2a14"), Color(0, 0, 0, 0), 2, 0, Vector4()))
	tree.add_theme_stylebox_override("selected_focus", EdStyle.box(Color("#4a3416"), Color(0, 0, 0, 0), 2, 0, Vector4()))
	tree.add_theme_color_override("font_color", EdStyle.TEXT)
	tree.add_theme_color_override("font_selected_color", Color("#ffcf9a"))
	tree.add_theme_font_size_override("font_size", 11)
	tree.add_theme_constant_override("item_margin", 12)
	tree.add_theme_constant_override("v_separation", 2)
	tree.multi_selected.connect(_on_multi)
	tree.item_activated.connect(_on_activated)
	tree.button_clicked.connect(_on_button)
	tree.item_collapsed.connect(_on_collapsed)
	tree.item_mouse_selected.connect(func(_at, _b): _clicked = tree.get_selected())
	tree.gui_input.connect(_on_tree_input)
	tree.set_drag_forwarding(_drag, _can_drop, _drop)
	box.add_child(tree)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 2)
	foot.add_child(EdStyle.small_button("+ New", func(): new_layer(), "A new layer on top of the stack"))
	foot.add_child(EdStyle.small_button("Dup", func(): ed.duplicate_layer(ed.layer()), "Duplicate the layer being edited, onto the first empty layer over it"))
	foot.add_child(EdStyle.small_button("▲", func(): ed.move_layer(ed.layer(), 1), "Move the layer up the stack"))
	foot.add_child(EdStyle.small_button("▼", func(): ed.move_layer(ed.layer(), -1), "Move the layer down the stack"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp)
	var del := EdStyle.small_button("Delete", func(): ask_delete(ed.layer()), "Delete the layer being edited, and its things")
	del.add_theme_color_override("font_color", EdStyle.DANGER)
	foot.add_child(del)
	box.add_child(foot)
	menu = PopupMenu.new()
	menu.id_pressed.connect(_on_menu)
	box.add_child(menu)
	_eye = _eye_tex(true)
	_eye_shut = _eye_tex(false)
	return box

# ---------------------------------------------------------------------
# THE STACK
# ---------------------------------------------------------------------

## Every layer there is to show, top first: the ones with something on
## them and the one being edited.
func stack() -> Array:
	var ks := []
	for g in EdDoc.layers_of(ed.doc):
		ks.append(int(g.k))
	ks.reverse()
	return ks

func render() -> void:
	if tree == null:
		return
	_syncing = true
	var scroll := tree.get_scroll()
	tree.clear()
	_items.clear()
	_layer_items.clear()
	var root := tree.create_item()
	var d: Dictionary = ed.doc
	var cur := ed.layer()
	var bounds := _bounds(d)
	for k in stack():
		var g := EdDoc.layer_geom(d, k)
		var it := tree.create_item(root)
		_layer_items[k] = it
		var hidden := ed.layer_hidden(k)
		var n_th := 0
		for t in d.things:
			if int(EdDoc.num(t.get("layer"), 0)) == k:
				n_th += 1
		it.set_metadata(0, {"kind": "layer", "k": k})
		it.set_text(0, EdDoc.layer_name(d, k))
		it.set_icon(0, _thumb(g, bounds, k == cur, hidden))
		it.set_icon_max_width(0, THUMB.x)
		it.set_tooltip_text(0, "Layer %d%s · %d sector%s · %d thing%s\nclick: edit it · double-click: rename · drag: move it in the stack · right-click: more" % [
			k, " (the ground)" if k == 0 else "", g.sectors.size(), "" if g.sectors.size() == 1 else "s", n_th, "" if n_th == 1 else "s"])
		it.add_button(1, _eye_shut if hidden else _eye, 0, false, "Show this layer" if hidden else "Hide this layer (Alt+click: this one alone)")
		if k == cur:
			it.set_custom_bg_color(0, Color("#17301f"))
			it.set_custom_bg_color(1, Color("#17301f"))
			it.set_custom_font(0, EdStyle.bold())
			it.set_custom_color(0, Color.WHITE)
		elif hidden:
			it.set_custom_color(0, EdStyle.DIM)
		var filled: bool = not g.sectors.is_empty() or n_th > 0 or not g.linedefs.is_empty()
		it.collapsed = not _open.has(str(k))
		if filled:
			if it.collapsed:
				tree.create_item(it)   # the arrow, filled when it is opened
			else:
				_fill(it, k, g)
	_syncing = false
	_sync_sel(false)
	tree.scroll_to_item(root)
	for c in tree.get_children(true):
		if c is VScrollBar:
			(c as VScrollBar).value = scroll.y

## A layer's hierarchy under its row: rooms in rooms, things in rooms.
func _fill(it: TreeItem, k: int, g: Dictionary) -> void:
	for c in it.get_children():
		it.remove_child(c)
		c.free()
	var S: Array = g.sectors
	var parents := EdDoc.hole_parents(g) if not S.is_empty() else PackedInt32Array()
	var kids := {}
	var rings := []
	var boxes := []
	var areas := PackedFloat64Array()
	for i in S.size():
		var r := EdDoc.ring_of(g, S[i])
		rings.append(r)
		boxes.append(EdDoc.bbox(r))
		areas.append(absf(EdDoc.signed_area(r)))
		var p := parents[i]
		if not kids.has(p):
			kids[p] = []
		kids[p].append(i)
	# each thing in the smallest room round it
	var owned := {}
	for t in ed.doc.things:
		if int(EdDoc.num(t.get("layer"), 0)) != k:
			continue
		var q := Vector2(EdDoc.num(t.x), EdDoc.num(t.y))
		var best := -1
		var ba := INF
		for i in S.size():
			if areas[i] >= ba or rings[i].size() < 3 or not (boxes[i] as Rect2).grow(0.5).has_point(q):
				continue
			if EdDoc.pip(rings[i], q.x, q.y):
				best = i
				ba = areas[i]
		if not owned.has(best):
			owned[best] = []
		owned[best].append(t)
	for i in kids.get(-1, []):
		_sector_item(it, k, g, i, kids, owned, str(k))
	for t in owned.get(-1, []):
		_thing_item(it, k, t)
	var free: int = g.linedefs.size()
	if free > 0:
		var l := tree.create_item(it)
		l.set_text(0, "%d free-standing line%s" % [free, "" if free == 1 else "s"])
		l.set_custom_color(0, EdStyle.DIM)
		l.set_selectable(0, false)
		l.set_selectable(1, false)

func _sector_item(parent: TreeItem, k: int, g: Dictionary, i: int, kids: Dictionary, owned: Dictionary, path: String) -> void:
	var s: Dictionary = g.sectors[i]
	var it := tree.create_item(parent)
	var nm: String = str(s.get("name", ""))
	it.set_text(0, nm if nm != "" else "Sector %d" % int(s.id))
	it.set_icon(0, _icon("sector", Color("#7fb2ff") if not s.get("outdoor", true) else Color("#7fd88f")))
	it.set_metadata(0, {"kind": "sector", "k": k, "id": s.id})
	it.set_tooltip_text(0, "Sector %d · floor %d, ceiling %d · %s\nclick: select · double-click: frame it" % [int(s.id), int(EdDoc.num(s.get("floor"), 0)),
		int(EdDoc.num(s.get("ceil"), 0)), "inside" if not s.get("outdoor", true) else "outside"])
	_items["s%s" % s.id] = it
	var p := "%s/s%s" % [path, s.id]
	var has := kids.has(i) or owned.has(i)
	it.collapsed = has and not _open.has(p)
	for c in kids.get(i, []):
		_sector_item(it, k, g, c, kids, owned, p)
	for t in owned.get(i, []):
		_thing_item(it, k, t)

func _thing_item(parent: TreeItem, k: int, t: Dictionary) -> void:
	var it := tree.create_item(parent)
	var def: Dictionary = EdDoc.THING_TYPES.get(t.type, {"name": str(t.type), "color": "#f0f"})
	var nm: String = def.get("name", str(t.type))
	if t.type == "PLANT" and t.get("kind") != null:
		nm += " · " + str(t.kind).replace("_", " ")
	it.set_text(0, nm)
	var c: Color = EdScatter.plant_colour(t.get("kind")) if t.type == "PLANT" else EdDoc.col(def.get("color", "#f0f"))
	it.set_icon(0, _icon("thing", c))
	it.set_metadata(0, {"kind": "thing", "k": k, "id": t.id})
	it.set_tooltip_text(0, "%s %d at %d, %d\nclick: select · double-click: frame it" % [nm, int(t.id), int(EdDoc.num(t.x)), int(EdDoc.num(t.y))])
	_items["t%s" % t.id] = it

# ---------------------------------------------------------------------
# WHAT IS SELECTED, both ways
# ---------------------------------------------------------------------

## The map's selection, shown here (and the rooms it is in opened, when
## its layer is open).
func _sync_sel(reveal := true) -> void:
	if tree == null:
		return
	_syncing = true
	tree.deselect_all()
	var pre := "s" if ed.sel_kind == "sector" else ("t" if ed.sel_kind == "thing" else "")
	var last: TreeItem = null
	if pre != "":
		for id in ed.sel_ids:
			var it: TreeItem = _items.get(pre + str(id))
			if it == null:
				continue
			if reveal:
				var p := it.get_parent()
				while p != null and p != tree.get_root():
					if p.collapsed:
						p.collapsed = false
						_open[_path_of(p)] = true
					p = p.get_parent()
			it.select(0)
			last = it
	_syncing = false
	if last != null and reveal:
		tree.scroll_to_item(last)

func sel_changed() -> void:
	_sync_sel(true)

func _on_multi(_item: TreeItem, _col: int, _selected: bool) -> void:
	if _syncing or _sel_queued:
		return
	_sel_queued = true
	_apply_sel.call_deferred()

## The pane's selection, onto the map.
func _apply_sel() -> void:
	_sel_queued = false
	var clicked := _clicked if _clicked != null else tree.get_selected()
	_clicked = null
	if clicked == null:
		return
	var m = clicked.get_metadata(0)
	if not m is Dictionary:
		return
	if m.kind == "layer":
		if m.k != ed.layer():
			ed.set_layer(m.k)
		else:
			_sync_sel(false)
		return
	var ids := []
	var it := tree.get_next_selected(null)
	while it != null:
		var mm = it.get_metadata(0)
		if mm is Dictionary and mm.kind == m.kind and mm.k == m.k:
			ids.append(mm.id)
		it = tree.get_next_selected(it)
	if ids.is_empty():
		ids = [m.id]
	if m.k != ed.layer():
		ed.set_layer(m.k)
	ed.set_mode("sectors" if m.kind == "sector" else "things")
	ed.select(m.kind, ids)

func _on_tree_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
		var it := tree.get_item_at_position(e.position)
		while it != null and it.get_parent() != tree.get_root():
			it = it.get_parent()
		if it != null and it.get_metadata(0) is Dictionary:
			_popup(it.get_metadata(0).k)
			tree.accept_event()

func _on_activated() -> void:
	var it := tree.get_selected()
	if it == null:
		return
	var m = it.get_metadata(0)
	if not m is Dictionary:
		return
	if m.kind == "layer":
		ask_rename(m.k)
	else:
		ed.frame_sel_req.emit()

func _on_button(it: TreeItem, _col: int, _id: int, button: int) -> void:
	if button != MOUSE_BUTTON_LEFT:
		return
	var m = it.get_metadata(0)
	if not m is Dictionary or m.kind != "layer":
		return
	if Input.is_key_pressed(KEY_ALT):
		solo(m.k)
	else:
		ed.set_layer_hidden(m.k, not ed.layer_hidden(m.k))

func _on_collapsed(it: TreeItem) -> void:
	if _syncing:
		return
	var m = it.get_metadata(0)
	if not m is Dictionary:
		return
	var p := _path_of(it)
	if it.collapsed:
		_open.erase(p)
		return
	_open[p] = true
	if m.kind == "layer":
		var first := it.get_first_child()
		if first != null and first.get_metadata(0) == null:
			_syncing = true
			_fill(it, m.k, EdDoc.layer_geom(ed.doc, m.k))
			_syncing = false
			_sync_sel(false)

func _path_of(it: TreeItem) -> String:
	var parts := []
	while it != null and it != tree.get_root():
		var m = it.get_metadata(0)
		if m is Dictionary:
			parts.push_front(str(m.k) if m.kind == "layer" else "s%s" % m.id)
		it = it.get_parent()
	return "/".join(parts)

# ---------------------------------------------------------------------
# THE OPERATIONS
# ---------------------------------------------------------------------

func new_layer() -> void:
	var ks := stack()
	var top: int = ks[0] if not ks.is_empty() else 0
	if EdDoc.layer_filled(ed.doc, top) or top != ed.layer():
		top += 1
	if top > EdDoc.LAYER_MAX:
		ed.say("the stack is full")
		return
	ed.set_layer(top)

## This layer alone shown; again, all of them.
func solo(k: int) -> void:
	var others := []
	for j in stack():
		if j != k:
			others.append(j)
	var alone := others.all(func(j): return ed.layer_hidden(j))
	if k != ed.layer():
		ed.set_layer(k)
	for j in others:
		ed.set_layer_hidden(j, not alone)

func ask_rename(k: int) -> void:
	ui._prompt("Name layer %d:" % k, EdDoc.layer_name(ed.doc, k), func(t): ed.rename_layer(k, t))

func ask_delete(k: int) -> void:
	if not EdDoc.layer_filled(ed.doc, k) and not ed.doc.things.any(func(t): return int(EdDoc.num(t.get("layer"), 0)) == k):
		ed.say("%s is empty" % EdDoc.layer_name(ed.doc, k))
		return
	var c := ConfirmationDialog.new()
	c.title = "MEWD Editor"
	c.dialog_text = "Delete %s (layer %d), its rooms and its things? Ctrl+Z brings it back." % [EdDoc.layer_name(ed.doc, k), k]
	c.confirmed.connect(func(): ed.delete_layer(k); c.queue_free())
	c.canceled.connect(func(): c.queue_free())
	ui.add_child(c)
	c.popup_centered()

func _popup(k: int) -> void:
	_menu_k = k
	menu.clear()
	menu.add_item("Edit this layer", 0)
	menu.add_item("Rename…", 1)
	menu.add_item("Duplicate", 2)
	menu.add_separator()
	menu.add_item("Move up", 3)
	menu.add_item("Move down", 4)
	menu.add_separator()
	menu.add_item("Show" if ed.layer_hidden(k) else "Hide", 5)
	menu.add_item("Show this one alone (Alt+click the eye)", 6)
	menu.add_separator()
	menu.add_item("Delete…", 7)
	menu.set_item_disabled(menu.get_item_index(5), k == ed.layer())
	menu.position = Vector2i(ui.get_viewport().get_mouse_position()) + ui.get_window().position
	menu.reset_size()
	menu.popup()

func _on_menu(id: int) -> void:
	var k := _menu_k
	match id:
		0: ed.set_layer(k)
		1: ask_rename(k)
		2: ed.duplicate_layer(k)
		3: ed.move_layer(k, 1)
		4: ed.move_layer(k, -1)
		5: ed.set_layer_hidden(k, not ed.layer_hidden(k))
		6: solo(k)
		7: ask_delete(k)

# --- dragging a layer up or down the stack -----------------------------

func _drag(at: Vector2) -> Variant:
	var it := tree.get_item_at_position(at)
	if it == null:
		return null
	var m = it.get_metadata(0)
	if not m is Dictionary or m.kind != "layer":
		return null
	var l := EdStyle.label(EdDoc.layer_name(ed.doc, m.k), Color.WHITE, 11, EdStyle.bold())
	tree.set_drag_preview(l)
	tree.drop_mode_flags = Tree.DROP_MODE_ON_ITEM | Tree.DROP_MODE_INBETWEEN
	return {"mewd_layer": m.k}

func _drop_target(at: Vector2, data) -> Variant:
	if not data is Dictionary or not data.has("mewd_layer"):
		return null
	var it := tree.get_item_at_position(at)
	while it != null and it.get_parent() != tree.get_root():
		it = it.get_parent()
	if it == null:
		return null
	var k: int = it.get_metadata(0).k
	var from: int = data.mewd_layer
	var sect := tree.get_drop_section_at_position(at)
	# above a row (the top first): one layer higher than it
	if sect == -1 and k < from:
		k += 1
	elif sect == 1 and k > from:
		k -= 1
	return k if k != from else null

func _can_drop(at: Vector2, data) -> bool:
	return _drop_target(at, data) != null

func _drop(at: Vector2, data) -> void:
	var k = _drop_target(at, data)
	tree.drop_mode_flags = Tree.DROP_MODE_DISABLED
	if k != null:
		ed.move_layer_to(int(data.mewd_layer), int(k))

# ---------------------------------------------------------------------
# PICTURES: the thumbnails, the eye, the little icons
# ---------------------------------------------------------------------

## Every layer's plan, in one box: the thumbnails all at one scale.
func _bounds(d: Dictionary) -> Rect2:
	var r := Rect2()
	var first := true
	for g in EdDoc.layers_of(d):
		for v in g.vertices:
			if first:
				r = Rect2(v, Vector2.ZERO)
				first = false
			else:
				r = r.expand(v)
	return r.grow(maxf(r.size.x, r.size.y) * 0.04 + 1.0)

func _thumb(g: Dictionary, b: Rect2, cur: bool, hidden: bool) -> Texture2D:
	var img := Image.create(THUMB.x, THUMB.y, false, Image.FORMAT_RGBA8)
	img.fill(Color("#0b0e11"))
	var edge := Color("#3ddc84") if cur else Color("#2a323b")
	for x in THUMB.x:
		img.set_pixel(x, 0, edge)
		img.set_pixel(x, THUMB.y - 1, edge)
	for y in THUMB.y:
		img.set_pixel(0, y, edge)
		img.set_pixel(THUMB.x - 1, y, edge)
	if b.size.x > 0 and b.size.y > 0:
		var sc := minf((THUMB.x - 4) / b.size.x, (THUMB.y - 4) / b.size.y)
		var off := Vector2(THUMB.x, THUMB.y) * 0.5 - b.get_center() * sc
		var col := Color("#cfe8d6") if cur else Color("#8a98a4")
		if hidden:
			col.a = 0.35
		for s in g.sectors:
			var n: int = s.verts.size()
			for i in n:
				var a: Vector2 = g.vertices[int(s.verts[i])] * sc + off
				var c: Vector2 = g.vertices[int(s.verts[(i + 1) % n])] * sc + off
				_line(img, a, c, col)
	return ImageTexture.create_from_image(img)

static func _line(img: Image, a: Vector2, b: Vector2, c: Color) -> void:
	var n := int(maxf(absf(b.x - a.x), absf(b.y - a.y))) + 1
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		var x := int(p.x)
		var y := int(p.y)
		if x >= 1 and y >= 1 and x < img.get_width() - 1 and y < img.get_height() - 1:
			img.set_pixel(x, y, c)

func _eye_tex(open: bool) -> Texture2D:
	var img := Image.create(16, 12, false, Image.FORMAT_RGBA8)
	var c := Color("#cfd8dc") if open else Color("#4a555e")
	for y in 12:
		for x in 16:
			var u := (x + 0.5 - 8.0) / 7.0
			var v := (y + 0.5 - 6.0) / 4.2
			var r := u * u + v * v
			if not open:
				# shut: the lid's lower edge and the lashes
				if (r > 0.55 and r < 1.05 and v > 0.0) or (v > 0.95 and absf(u) < 0.7 and x % 4 == 1):
					img.set_pixel(x, y, c)
				continue
			if r > 0.62 and r < 1.05:
				img.set_pixel(x, y, c)
			elif Vector2(x + 0.5 - 8.0, y + 0.5 - 6.0).length() < 2.2:
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func _icon(kind: String, c: Color) -> Texture2D:
	var key := "%s%s" % [kind, c.to_html()]
	if _icons.has(key):
		return _icons[key]
	var img := Image.create(10, 10, false, Image.FORMAT_RGBA8)
	for y in 10:
		for x in 10:
			if kind == "sector":
				if x == 1 or x == 8 or y == 1 or y == 8:
					if x >= 1 and x <= 8 and y >= 1 and y <= 8:
						img.set_pixel(x, y, c)
				elif x > 1 and x < 8 and y > 1 and y < 8:
					img.set_pixel(x, y, Color(c, 0.25))
			elif Vector2(x + 0.5 - 5.0, y + 0.5 - 5.0).length() < 3.6:
				img.set_pixel(x, y, c)
	var t := ImageTexture.create_from_image(img)
	_icons[key] = t
	return t
