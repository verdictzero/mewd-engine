## MEWD — the editor's document, headless: blocks on the ground.
##
##   godot --headless --script res://godot/tests/editor_test.gd
##
## Drives MewdEditor without a window through its own commands (the
## ones the views and the keyboard call): a block pulled up on the
## ground, one drawn inside it (standing on it), the wheel's height and
## base, a negative height (a pit), the Room tool (walls, a floor, a
## roof on the layer above), a door cut into a wall block (the lintel),
## stairs and rings, a block split along a path, two merged across a
## line, loop select and the textures, a layer with a slab floating on
## the walls, copy and paste, delete, undo all the way back, the file
## written and read back the same, and what the compiler builds of it
## all. Prints OK or fails.
extends SceneTree

var fails := 0
var checks := 0

func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL ", what)

func _init() -> void:
	var ed := MewdEditor.new(EdDoc.new_doc(), true)
	ed.compile_now()
	ok(ed.doc.blocks.is_empty() and ed.compiled.level != null and ed.compiled.level.sectors.size() == 1, "a new map is the ground alone, and builds to one storey")
	var g0: Level.Sector = ed.compiled.level.sector_at(123456.0, -98765.0)
	ok(g0 == null, "the ground stops at the world's edge")
	ok(ed.compiled.level.sector_at(30000.0, -30000.0) != null, "but runs on far past the start")
	# A BLOCK PULLED UP
	ed.set_pull(96)
	var b = ed.add_rect(Vector2(0, 0), Vector2(512, 512))
	ok(b != null and EdDoc.h_of(b) == 96.0 and EdDoc.base_of(b) == null and ed.is_sel("block", b.id), "a drag pulls up a block as high as the Pull, on the ground, selected")
	var lv: Level = ed.compiled.level
	var top: Level.Sector = BlockCompile.stand_in(lv, 256, 256, 0)
	ok(top != null and top.floor == 96.0 and top.floor_tex == "CONC_1" and top.ceil_tex == "SKY", "its top is a floor at 96 under the sky (%s)" % str(top.floor if top else null))
	ok(ed.top_of(b.id).top == 96.0 and ed.top_of(b.id).base == 0.0, "and the editor knows where it stands (%s)" % str(ed.top_of(b.id)))
	var edge := lv.ray_hit_wall(-100, 256, 40, 300, 256, 40)
	ok(not edge.is_empty() and absf(edge.x) < 0.01, "its side stops a round from the ground")
	# THE WHEEL: height and base
	ed.nudge_height("h", 8)
	ok(EdDoc.h_of(ed.block_by_id(b.id)) == 104.0, "PgUp raises it 8 (%s)" % EdDoc.h_of(ed.block_by_id(b.id)))
	ed.nudge_height("base", 64)
	var bb = ed.block_by_id(b.id)
	ok(EdDoc.base_of(bb) == 64.0 and ed.top_of(b.id).top == 168.0, "Shift+PgUp lifts its base off the ground: it floats at 64 (top %s)" % ed.top_of(b.id).top)
	var under: Level.Sector = ed.compiled.level.span_at(256, 256, 1)
	ok(under != null and under.floor == 0.0 and under.ceil == 64.0 and under.ceil_tex == "GRIDWALL", "and under it is a room, its underside the ceiling (%s..%s %s)" % [under.floor if under else -1, under.ceil if under else -1, under.ceil_tex if under else ""])
	ed.set_base(b.id, null)
	ok(EdDoc.base_of(ed.block_by_id(b.id)) == null and ed.top_of(b.id).base == 0.0, "back on the ground")
	# A BLOCK DRAWN INSIDE IT STANDS ON IT
	ed.set_pull(32)
	var c = ed.add_rect(Vector2(128, 128), Vector2(256, 256))
	ok(c != null and ed.doc.blocks.size() == 2 and ed.top_of(c.id).base == 104.0 and ed.top_of(c.id).top == 136.0,
		"a block drawn on a block stands on it: %s" % str(ed.top_of(c.id) if c else null))
	ok(c != null and c.side == b.side and c.top == b.top, "in its textures")
	# A PIT: a negative height
	ed.select("block", [c.id])
	ed.set_snap(false)
	ed.nudge_height("h", -64)
	ed.set_snap(true)
	ok(EdDoc.h_of(ed.block_by_id(c.id)) == -32.0 and ed.top_of(c.id).top == 72.0, "pushed below zero it is a pit in the block (top %s)" % ed.top_of(c.id).top)
	ed.undo()
	# LOOP SELECT, AND THE TEXTURES
	ed.loop_select(ed.block_index(b.id))
	ok(ed.sel_kind == "line" and ed.sel_ids.size() == 8 and ed.sel_face == b.id, "the big block's sides: its four, and the four of the block on it (%d)" % ed.sel_ids.size())
	ed.apply_texture("CITYMET1")
	ok(ed.block_by_id(b.id).side == "CITYMET1" and ed.loop_tex_of("skin") == "CITYMET1", "a texture on the loop is the block's sides")
	ed.clear_sel()
	var k0 := ""
	for l in ed.lines():
		if l.blocks.size() == 1 and ed.doc.vertices[l.a].x == 0.0 and ed.doc.vertices[l.b].x == 0.0:
			k0 = l.key
	ed.select("line", [k0])
	ed.apply_texture("CONC_2")
	ok(ed.doc.lines.get(k0, {}).get("tex") == "CONC_2", "a texture on one line is that side's skin alone")
	ed.compile_now()
	var west_face := []
	for l in ed.compiled.level.lines:
		if absf(l.x1) < 0.01 and absf(l.x2) < 0.01:
			west_face.append(l.lower)
	ok(not west_face.is_empty() and west_face.all(func(t): return t == "CONC_2"), "and the build wears it there (%s)" % str(west_face))
	ed.select("block", [b.id])
	ed.apply_texture("DIRT1", "top")
	ok(ed.block_by_id(b.id).top == "DIRT1", "the inspector's Top field")
	# THE ROOM TOOL
	ed.set_make("room")
	ed.set_pull(128)
	var roof = ed.add_rect(Vector2(1024, 0), Vector2(1536, 512))
	ed.set_make("block")
	var walls := 0
	for x in ed.doc.blocks:
		if x.get("name") == "wall":
			walls += 1
	ok(roof != null and walls == 4 and ed.doc.get("layers", {}).has("1") and ed.doc.layers["1"].blocks.size() == 1,
		"a room: four walls, a floor, and a roof on layer 1 (%d walls)" % walls)
	var room: Level.Sector = BlockCompile.stand_in(ed.compiled.level, 1280, 256, 0)
	ok(room != null and room.floor == 0.0 and room.ceil == 128.0 and room.ceil_tex == "OFCCEIL1" and room.floor_tex == "CONC_2" and absf(room.light - 0.7) < 0.01,
		"inside it: a floor of its own, the roof's underside for a ceiling at 128, the roof's light (%s)" % str([room.floor, room.ceil, room.ceil_tex] if room else null))
	var over: Level.Sector = BlockCompile.stand_in(ed.compiled.level, 1280, 256, 1)
	ok(over != null and over.floor == 144.0 and over.ceil_tex == "SKY", "and on the roof, the open sky at 144")
	# A DOOR CUT INTO A WALL
	var wk := ""
	for l in ed.lines():
		var a: Vector2 = ed.doc.vertices[l.a]
		var bq: Vector2 = ed.doc.vertices[l.b]
		if absf(a.x - 1024) < 0.5 and absf(bq.x - 1024) < 0.5 and minf(a.y, bq.y) <= 200 and maxf(a.y, bq.y) >= 300:
			wk = l.key
	var dk := ed.place_door(wk, Vector2(1024, 256))
	ok(dk != "" and ed.doc.lines.get(dk, {}).get("door") is Dictionary, "a door in the west wall: the wall cut, the door on the lintel's line (%s)" % dk)
	var lintel = null
	for x in ed.doc.blocks:
		if x.get("name") == "lintel":
			lintel = x
	ok(lintel != null and EdDoc.base_of(lintel) == 96.0 and EdDoc.h_of(lintel) == 32.0, "the piece over the doorway floats at 96, up to the wall's top")
	ok(ed.compiled.level.doors.size() == 1 and ed.compiled.level.doors[0].top == 96.0 and ed.compiled.level.doors[0].wall == 16.0, "and the build has the door, 96 high, through a wall 16 thick")
	var way: Level.Sector = BlockCompile.stand_in(ed.compiled.level, 1032, 256, 0)
	ok(way != null and way.floor == 0.0 and way.ceil == 96.0, "the way through under it is open to 96")
	ed.remove_door(dk)
	ok(not (ed.doc.lines.get(dk, {}).get("door") is Dictionary), "Shift+click takes the door out, the doorway stays")
	ed.undo()
	# STAIRS: a strip between the ground and the big block
	ed.set_pull(0)
	var st = ed.add_rect(Vector2(512, 0), Vector2(768, 512))
	ed.select("block", [st.id])
	var made := ed.make_steps("stairs", {"stepH": 16})
	ok(made.size() == 6 and ed.compiled.problems.is_empty(), "a block beside the 104-high one cut into %d steps (%s)" % [made.size(), str(ed.compiled.problems)])
	var tops := []
	for id in made:
		tops.append(ed.top_of(id).top)
	tops.sort()
	ok(tops == [15.0, 30.0, 45.0, 59.0, 74.0, 89.0] or tops.size() == 6 and tops[0] > 0 and tops[5] < 104, "each a step higher, from the ground up to the block (%s)" % str(tops))
	# RINGS
	ed.set_pull(16)
	var mound = ed.add_rect(Vector2(0, 1024), Vector2(512, 1536))
	ed.select("block", [mound.id])
	var rings := ed.make_steps("rings", {"stepH": 16, "to": 64})
	ok(rings.size() == 4 and ed.top_of(rings[rings.size() - 1]).top == 64.0, "rings up to a mound 64 high (%d, top %s)" % [rings.size(), ed.top_of(rings[rings.size() - 1]).top])
	# SPLIT ALONG A PATH, AND MERGED BACK
	var n0: int = ed.doc.blocks.size()
	ed.path = [Vector2(0, 1280), Vector2(512, 1280)]
	ed.close_path(true)
	ok(ed.doc.blocks.size() == n0 + 1, "a path edge to edge splits the block it crosses")
	var mk := ""
	for l in ed.lines():
		if l.blocks.size() == 2 and ed.doc.vertices[l.a].y == 1280.0 and ed.doc.vertices[l.b].y == 1280.0:
			mk = l.key
	ed.select("line", [mk])
	ed.delete_sel()
	ok(ed.doc.blocks.size() == n0, "and deleting the line between them joins them again")
	# A LAYER: a slab over the first block, floating on it
	ed.set_layer(1)
	ok(ed.layer() == 1 and ed.doc.blocks.size() == 1, "layer 1 holds the roof")
	ed.set_pull(16)
	var slab = ed.add_rect(Vector2(0, 0), Vector2(512, 512))
	ok(slab != null and ed.top_of(slab.id).base == 136.0, "a block on layer 1 stands on the highest top under it — the small block's, 136 (%s)" % str(ed.top_of(slab.id)))
	ed.set_layer(0)
	# COPY AND PASTE
	ed.select("block", [b.id])
	ed.copy_sel()
	ed.set_cursor(Vector2(2048, 2048))
	ed.paste()
	ok(ed.doc.blocks.size() == n0 + 1 and ed.block_at(2300, 2300) != null, "Ctrl+C, Ctrl+V pastes the block at the cursor")
	# THE FILE
	var text := EdDoc.to_json(ed.doc)
	var back := EdDoc.parse(text)
	ok(back.has("doc") and EdDoc.to_json(back.doc) == text, "written and read back the same")
	ok(EdDoc.parse('{"format":"gss-map","vertices":[],"sectors":[]}').has("error"), "a map of the old editor is refused, and says why")
	# UNDO, ALL THE WAY
	var n := 0
	while not ed.history.past.is_empty() and n < 200:
		ed.undo()
		n += 1
	ok(ed.doc.blocks.is_empty() and not ed.doc.has("layers"), "undo all the way back to the empty ground (%d steps)" % n)
	print("editor: %d checks, %s" % [checks, "OK" if fails == 0 else "%d FAIL" % fails])
	quit(1 if fails else 0)
