## MEWD — THE HOUSE STYLE (golf's, at the user's request; UiStyle) and the
## title's logo, headless:
##
##   godot --headless --script res://godot/tests/ui_test.gd
##
## NO HUE: every colour of the palette a grey (golf's own test: no channel
## more than 0.031 from the others), the frames cut and never rounded. THE
## LOGO KEEPS ITS SIZE AND ITS PLACE (at the user's request): the same on
## the main menu, the islands, the hosted match's modes, whatever their
## lengths, and the menu inside the screen on every one; the logo and the
## main menu ONE GROUP, centred across and down; the logo SMALLER (under a
## third of the height). THE ROWS: the one you are on white and bold, the
## rest not, and all in one place (highlighted, never indented). THE PAUSE MENU: its frames cut, no red in it. THE TITLE'S
## PICTURE: black and white, darker than it was, film grain under the
## filter. Prints OK or fails.
extends SceneTree

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1

func _grey(c: Color) -> bool:
	return maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b)) <= 0.031

func _init() -> void:
	await process_frame
	var hued := []
	var consts: Dictionary = (load("res://godot/scripts/ui/ui_style.gd") as Script).get_script_constant_map()
	for k in ["CURSOR", "READY", "WAIT", "TAG", "NAME", "HP", "TP", "EXP", "BAR_BG", "BAR_BORDER", "DIM", "BRIGHT",
			"PANEL_BG", "PANEL_BORDER", "SEL_BG", "PANEL_BG_SEL", "PANEL_BORDER_REST", "SHADE"]:
		if not _grey(consts[k]):
			hued.append(k)
	check(hued.is_empty(), "no hue in the palette %s" % str(hued))
	check(UiStyle.window() is CutBox and UiStyle.row(true) is CutBox, "windows and rows are cut-corner frames")
	check(UiStyle.window().points(Rect2(0, 0, 200, 100)).size() == 6, "two corners cut (the house shape: top right, bottom left)")
	check(UiStyle.spaced("new game") == "N E W   G A M E", "letters spaced as golf spaces them")
	check(UiStyle.padded(7) == "007", "numbers zero-padded")

	# ---- the title's logo ---------------------------------------------------
	# (the canvas as the game has it: 720 high at least, wider on a wider
	# screen — window/stretch/aspect "expand" — a 16:9, a phone's 20:9, a
	# 21:9, a 16:10)
	for sz in [Vector2(1280, 720), Vector2(1600, 720), Vector2(1728, 720), Vector2(1280, 800)]:
		var t := Title.new()
		root.add_child(t)
		t.size = sz
		await process_frame
		var sizes := []
		var places := []
		var inside := true
		for list in [Title.ITEMS, Title.LEVELS, Title.MODES, Title.MULTI, Title.HOSTS]:
			t.show_items(list)
			t._layout()
			sizes.append(t.logo.size)
			places.append(t.logo.position)
			inside = inside and t.panel.position.y >= 0.0 and t.panel.position.y + t.panel.size.y <= sz.y + 0.5
		var same := true
		for i in sizes.size():
			same = same and sizes[i].is_equal_approx(sizes[0]) and places[i].is_equal_approx(places[0])
		check(same, "%dx%d: the logo the same size and place on every page of the menu (%s)" % [sz.x, sz.y, str(sizes[0])])
		check(inside, "%dx%d: and the menu on the screen on every page" % [sz.x, sz.y])
		t.show_items(Title.ITEMS)
		t._layout()
		var lc := t.logo.position.x + t.logo.size.x / 2.0
		var pc := t.panel.position.x + t.panel.size.x / 2.0
		var mid := (t.logo.position.y + t.panel.position.y + t.panel.size.y) / 2.0
		check(absf(lc - sz.x / 2.0) < 1.0 and absf(pc - sz.x / 2.0) < 1.0 and absf(mid - sz.y / 2.0) < 1.0,
			"%dx%d: the logo and the menu one group, centred across and down (%.0f, %.0f, %.0f)" % [sz.x, sz.y, lc, pc, mid])
		check(t.logo.size.y <= sz.y * 0.31 and t.logo.position.y + t.logo.size.y < t.panel.position.y,
			"%dx%d: the logo smaller (%.0f high), over the menu" % [sz.x, sz.y, t.logo.size.y])
		t.mark(0)
		var b0: Button = t.buttons[0]
		var b1: Button = t.buttons[1]
		check(b0.get_theme_color("font_color") == UiStyle.CURSOR and b1.get_theme_color("font_color") != UiStyle.CURSOR,
			"%dx%d: the row you are on is white, the rest not" % [sz.x, sz.y])
		# (highlighted, not moved: at the user's request, "dont indent menu items, just highlight")
		await process_frame
		var s0: StyleBox = b0.get_theme_stylebox("normal")
		var s1: StyleBox = b1.get_theme_stylebox("normal")
		check(is_equal_approx(b0.get_global_rect().position.x, b1.get_global_rect().position.x)
			and is_equal_approx(b0.size.x, b1.size.x) and is_equal_approx(s0.content_margin_left, s1.content_margin_left),
			"%dx%d: and in the same place as the rest, the same width (%.0f, %.0f)" % [sz.x, sz.y, b0.get_global_rect().position.x, b1.get_global_rect().position.x])
		t.queue_free()
		await process_frame

	# ---- the pause menu -----------------------------------------------------
	var pm := PauseMenu.new()
	root.add_child(pm)
	await process_frame
	pm._cursor_to(0)
	var tile: Button = pm.tiles[pm._stops()[0]]
	var box = tile.get_theme_stylebox("normal")
	check(box is CutBox and (box as CutBox).border == UiStyle.CURSOR, "pause: the tile under the cursor has the white keyline")
	var red := 0
	for b in pm.find_children("*", "Button", true, false):
		for st in ["normal", "hover", "pressed"]:
			var sb = b.get_theme_stylebox(st)
			if sb is CutBox and not (_grey(sb.bg) and _grey(sb.border)):
				red += 1
			if sb is StyleBoxFlat:
				red += 1
	check(red == 0, "pause: every button a grey cut-corner row (%d not)" % red)
	pm.queue_free()
	await process_frame

	# ---- the title's picture -------------------------------------------------
	var main: Node = load("res://godot/scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 5:
		await process_frame
	var lofi: Lofi = main.get("lofi")
	var tint: Vector3 = lofi.mat.get_shader_parameter("tint")
	var was := Vector3(0.17, 0.36, 0.42).dot(Vector3(0.299, 0.587, 0.114))
	check(main.get("title") != null and float(lofi.mat.get_shader_parameter("mono")) == 1.0,
		"the title's picture black and white")
	check(is_equal_approx(tint.x, tint.y) and is_equal_approx(tint.y, tint.z) and tint.x < was,
		"its grey darker than the blue was (%.2f against %.2f)" % [tint.x, was])
	check(float(lofi.mat.get_shader_parameter("grain")) >= 0.3, "and film grain under the filter, intense (%.2f)" % float(lofi.mat.get_shader_parameter("grain")))
	# THE VERSION on the logs' line, at the left, in its face (at the user's request)
	var ver: Button = main.find_child("Version", true, false)
	var logs: Button = null
	for b in main.find_children("*", "Button", true, false):
		if b != ver and b.text == Logs.where():
			logs = b
	var vr := ver.get_global_rect() if ver != null else Rect2()
	var lr := logs.get_global_rect() if logs != null else Rect2()
	check(ver != null and logs != null and ver.text == U.VERSION and absf(vr.get_center().y - lr.get_center().y) < 0.5
		and vr.position.x < 20.0 and lr.end.x > root.get_visible_rect().size.x - 20.0,
		"the version on the logs' line, at the left (%s, %s)" % [str(vr), str(lr)])
	check(ver != null and logs != null and ver.get_theme_font("font") == logs.get_theme_font("font")
		and ver.get_theme_font_size("font_size") == logs.get_theme_font_size("font_size"), "and in the same face and size")
	main.queue_free()
	await process_frame
	print("ui: " + ("OK" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
