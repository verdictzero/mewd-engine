## MEWD — THE HOUSE STYLE (golf's, at the user's request; UiStyle) and the
## title's logo, headless:
##
##   godot --headless --script res://godot/tests/ui_test.gd
##
## NO HUE: every colour of the palette a grey (golf's own test: no channel
## more than 0.031 from the others), the frames cut and never rounded. THE
## LOGO KEEPS ITS SIZE (at the user's request): the same on the main menu,
## the islands, the hosted match's modes, whatever their lengths, and the
## menu inside the screen on every one; the same on a phone on its side.
## THE ROWS: the one you are on white and bold, the rest not. THE PAUSE
## MENU: its frames cut, no red in it. Prints OK or fails.
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
	for sz in [Vector2(1280, 720), Vector2(900, 400), Vector2(720, 1280)]:
		var t := Title.new()
		root.add_child(t)
		t.size = sz
		await process_frame
		var sizes := []
		var inside := true
		for list in [Title.ITEMS, Title.LEVELS, Title.MODES, Title.MULTI, Title.HOSTS]:
			t.show_items(list)
			t._layout()
			sizes.append(t.logo.size)
			inside = inside and t.panel.position.y >= 0.0 and t.panel.position.y + t.panel.size.y <= sz.y + 0.5
		var same := true
		for s in sizes:
			same = same and s.is_equal_approx(sizes[0])
		check(same, "%dx%d: the logo the same size on every page of the menu (%s)" % [sz.x, sz.y, str(sizes[0])])
		check(inside, "%dx%d: and the menu on the screen on every page" % [sz.x, sz.y])
		t.show_items(Title.ITEMS)
		t.mark(0)
		var b0: Button = t.buttons[0]
		var b1: Button = t.buttons[1]
		check(b0.get_theme_color("font_color") == UiStyle.CURSOR and b1.get_theme_color("font_color") != UiStyle.CURSOR,
			"%dx%d: the row you are on is white, the rest not" % [sz.x, sz.y])
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
	print("ui: " + ("OK" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
