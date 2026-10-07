## MEWD — the readout (js/hud.js, the readout half).
##
## PRINTED ON THE GLASS, at the user's request: its own layer over the
## filtered picture, at the screen's own resolution, never dithered or
## snapped — a label on the glass is not more honest for being out of
## focus, only harder to read. Almost nothing in it: what is left of you
## — HEALTH and ARMOUR, each a number and a bar, top left — and in the
## far corner the weapon's name and what is left in it, a count over
## what it holds and the tank's bar (with the pip where a latched tank
## starts working again). THE PICKUPS' OWN PICTURES (at the user's
## request: "the mechanics / ui elements to utilize them") stand by each
## number: the medkit by your health, the armour you wear by your
## armour, the box a gun's ammunition comes in by its count.
##
## IN GOLF'S HOUSE STYLE, at the user's request (UiStyle, CutBox): no hue
## in the chrome, only greys, and brightness the only thing a value can
## mean — a gauge run dry or run low goes white and its number brighter.
## The words in Zalando Sans Condensed, the numbers in digital-7,
## zero-padded; labels and units in TAG, values in NAME. Over the moving
## world the text wears a black outline, not a drop shadow.
class_name Hud
extends Control

## the readout's old names for its inks, each now one of the house's greys
## (read by name from UiStyle, never copied). The one hue left is the
## death's own red, which is the death's and not the chrome's.
const UI := {
	"ink": UiStyle.NAME, "label": UiStyle.TAG, "rule": UiStyle.DIM,
	"track": UiStyle.BAR_BG, "trackEdge": UiStyle.BAR_BORDER,
	"mark": UiStyle.CURSOR, "burn": UiStyle.CURSOR,
	"full": UiStyle.TP, "low": UiStyle.BRIGHT, "empty": UiStyle.CURSOR,
	"armour2": UiStyle.TP, "armour1": UiStyle.TP, "health": UiStyle.HP,
	"death": Color("#c8102e"), "over": UiStyle.CURSOR, "gold": UiStyle.BRIGHT,
}

var game
## the old monospaced face: kept for 死 on a match's death card, and as
## the death's fallback when its own faces will not load
var font: Font
## the house's words (Medium, and Bold for what must be heard) and numbers
var words: Font
var bold: Font
var nums: Font
## the pickups' strip as drawn (sRGB, not the world's decoded copy), for
## the icons
var icons: Texture2D

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = U.ui_font(PackedStringArray(["monospace", "DejaVu Sans Mono", "Liberation Mono"]))
	words = UiStyle.words("Medium")
	bold = UiStyle.words("Bold")
	nums = UiStyle.numbers()
	icons = load(Pickups.STRIP)
	_make_wash()

func _process(_dt: float) -> void:
	queue_redraw()

## a 720-row window is the unit, clamped so it is never a whisper or a poster
func _scale() -> float:
	return clampf(size.y / 720.0, 0.78, 1.7)

## a bar the house's way: the dark track, the fill, a one-pixel keyline
## round it, and square ends
func _bar(x: float, y: float, w: float, h: float, lit: float, colour: Color, mark := 0.0) -> void:
	draw_rect(Rect2(x, y, w, h), UI.track)
	var fill := clampf(lit, 0.0, 1.0) * w
	if fill > 0.5:
		draw_rect(Rect2(x, y, fill, h), colour)
	draw_rect(Rect2(x, y, w, h), UI.trackEdge, false, 1.0)
	if mark > 0.0:
		var s := _scale()
		draw_rect(Rect2(x + w * mark - maxf(1.0, s), y - 2.0 * s, maxf(2.0, 2.0 * s), h + 4.0 * s), UI.mark)

func _draw() -> void:
	if game == null or game.player == null:
		return
	var p: Player = game.player
	var s := _scale()
	var M := roundf(20.0 * s)
	var BAR := roundf(8.0 * s)
	var GAP := roundf(8.0 * s)
	var bw := roundf(minf(size.x * 0.34, 240.0 * s))
	# (clear of the glass's own buttons: PERF in the top left corner, and
	# II and SLO down the side they are on — TouchControls)
	var tc = game.get("touch")
	var touching: bool = tc != null and tc.visible
	var lx := M + (roundf(44.0 * s) if touching else 0.0)
	var rx := size.x - M - (roundf(44.0 * s) if touching and not tc.lefty else 0.0)
	var d := p.def()
	if not p.dead:
		_draw_vitals(p, lx, M, bw, BAR, s)
	# the weapon's name, far corner, a DIM hairline under it
	if not p.dead:
		var wname: String = d.name
		var fs := int(roundf(15.0 * s))
		var spaced := UiStyle.spaced(wname)
		var w := _wide(spaced, fs, words)
		var x := rx - w
		var ny := M + fs
		_text(x, ny, spaced, fs, UI.ink)
		draw_rect(Rect2(x, ny + roundf(5.0 * s), w, maxf(1.0, roundf(s))), UI.rule)
		# WHAT IS LEFT IN IT, under the name
		var ay := ny + roundf(5.0 * s)
		if d.has("ammo"):
			ay = _draw_ammo(p, d, rx, ay, bw, BAR, s)
		# the brains taken (Trophies), under it: the count and its name
		if p.brains > 0:
			var bs := int(roundf(12.0 * s))
			var ns := int(roundf(18.0 * s))
			var by := ay + ns + roundf(6.0 * s)
			var bn := UiStyle.padded(int(p.brains))
			var nw := _wide(bn, ns, nums)
			_text(rx - nw, by, bn, ns, UI.ink, nums)
			var bt := UiStyle.spaced("brains")
			_text(rx - nw - roundf(8.0 * s) - _wide(bt, bs, words), by, bt, bs, UI.label)
	elif game.get("death") == null or not game.death.active:
		# the card: 死, and YOU DIED (a match's death; a game alone has its
		# own words, _draw_death). Over a darkened band, so no outline.
		var band := size.y * 0.22
		var top := size.y * 0.5 - band * 0.5
		draw_rect(Rect2(0, top, size.x, band), Color(0, 0, 0, 0.72))
		var ks := int(band * 0.55)
		var kw := font.get_string_size("死", HORIZONTAL_ALIGNMENT_LEFT, -1, ks).x
		draw_string(font, Vector2(size.x * 0.5 - kw * 0.5, top + band * 0.62), "死", HORIZONTAL_ALIGNMENT_LEFT, -1, ks, UI.death)
		var ts := int(roundf(20.0 * s))
		var txt := UiStyle.spaced("you died")
		var tw := _wide(txt, ts, bold)
		draw_string(bold, Vector2(size.x * 0.5 - tw * 0.5, top + band * 0.9), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, UiStyle.BRIGHT)
	# SLOW MOTION, said at the top of the screen while it is on
	if game.get("slow_mo") == true:
		var ss := int(roundf(14.0 * s))
		var st := UiStyle.spaced("slow motion")
		var sw := _wide(st, ss, words)
		var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.004)
		_text(size.x * 0.5 - sw * 0.5, M + ss, st, ss, Color(UI.ink, pulse))
	# THE DROP'S READOUT (DropPod): the altitude, the fall, the tilt, the
	# retros, the autopilot when it has the burn, the reentry fire before.
	# Each line a TAG name, a digital-7 number and a TAG unit, centred.
	var drop = game.get("drop")
	if drop != null and drop.active and drop.phase == "drop":
		var r: Dictionary = drop.readout()
		var ls := int(roundf(12.0 * s))
		var ns := int(roundf(19.0 * s))
		var gap := roundf(7.0 * s)
		var rows := [
			["alt", "%05d" % roundi(r.alt), "m"],
			["fall", "%03d" % roundi(r.fall), "m/s"],
			["tilt", "%03d" % roundi(r.tilt), "°"],
		]
		# (no RCS line while the pod has none: DropPod.RCS_ON)
		if r.has("fuel"):
			var fuel := float(r.fuel)
			rows.append(["rcs", "%03d" % roundi(fuel * 100.0), "%"] if fuel > 0.0 else ["rcs", "", UiStyle.spaced("dry")])
		var y0 := M + ns
		for row in rows:
			var lt := UiStyle.spaced(row[0])
			var vt: String = row[1]
			var ut: String = row[2]
			var lw := _wide(lt, ls, words)
			var vw := _wide(vt, ns, nums)
			var uw := _wide(ut, ls, words)
			var x0 := roundf(size.x * 0.5 - (lw + gap + vw + gap * 0.5 + uw) * 0.5)
			_text(x0, y0, lt, ls, UI.label)
			_text(x0 + lw + gap, y0, vt, ns, UI.ink, nums)
			# (a dry tank is said brighter: it is an alarm)
			_text(x0 + lw + gap + vw + gap * 0.5, y0, ut, ls, UI.low if vt == "" else UI.label)
			y0 += ns + 4.0 * s
		var warn := ""
		if r.retro > 0.0:
			warn = UiStyle.spaced("auto burn") if r.auto else UiStyle.spaced("retros")
		elif float(r.get("heat", 0.0)) > 0.1:
			warn = UiStyle.spaced("reentry")
		if warn != "":
			var ws := int(roundf(14.0 * s))
			var rw := _wide(warn, ws, bold)
			var pulse := 0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.01)
			_text(size.x * 0.5 - rw * 0.5, y0 + ws, warn, ws, Color(UI.burn, pulse), bold)
	# the red wash when something hits you, and the gold of a pickup (the
	# world's own flashes, not the chrome's, so they keep their hue)
	if p.damage_flash > 0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.8, 0.05, 0.02, minf(0.35, p.damage_flash * 0.025)))
	if p.bonus_flash > 0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.84, 0.32, minf(0.16, p.bonus_flash * 0.027)))
	_draw_toasts(s)
	_draw_big(s)
	_draw_death(s)
	if game.get("net") != null:
		_draw_board(s)

## how wide a line is in a face (the house's words when none is named)
func _wide(t: String, fs: int, f: Font = null) -> float:
	var ff: Font = words if f == null else f
	return ff.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x

## text the house's way: in the words unless another face is named, and
## over the moving world in a black outline (two to four pixels, with
## the size); how wide it was. `outlined` false for text on a panel.
func _text(x: float, y: float, t: String, fs: int, col: Color, f: Font = null, outlined := true) -> float:
	var ff: Font = words if f == null else f
	if outlined:
		var ow := clampi(roundi(fs * 0.16), 2, 4)
		draw_string_outline(ff, Vector2(x, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ow, Color(0, 0, 0, col.a))
	draw_string(ff, Vector2(x, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	return ff.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x

## a pickup's picture (its cell of the strip), `h` high, its foot at y
func _icon(cell: int, x: float, y: float, h: float) -> void:
	if icons == null or cell < 0:
		return
	var c := float(icons.get_height())
	draw_texture_rect_region(icons, Rect2(x, y - h, h, h), Rect2(cell * c, 0, c, c))

## HEALTH AND ARMOUR, top left: the medkit and the number, the bar under
## it — the bar white and the number brighter at a quarter (the alarm),
## and a white strip along its foot for what is over the top; the armour
## you wear and its number, its bar a step down the ramp, the number
## gone to WAIT when there is none; and GOD while IDDQD is on.
func _draw_vitals(p: Player, x: float, y: float, bw: float, bh: float, s: float) -> void:
	var fs := int(roundf(30.0 * s))
	var ls := int(roundf(12.0 * s))
	var ih := roundf(34.0 * s)
	bw = roundf(bw * 0.85)
	var gap := roundf(10.0 * s)
	var nx := x + ih + gap
	# health
	var h: int = p.health
	var alarm := h <= 25
	var hc: Color = UI.low if alarm else UI.ink
	var hf: Color = UI.empty if alarm else UI.health
	var base := y + ih - roundf(3.0 * s)
	_icon(Pickups.kind_of("health"), x, y + ih, ih)
	var w := _text(nx, base, UiStyle.padded(h), fs, hc, nums)
	var lw := _text(nx + w + gap, base, UiStyle.spaced("health"), ls, UI.label)
	if p.cheat:
		_text(nx + w + gap * 3.0 + lw, base, UiStyle.spaced("god"), ls, UI.gold, bold)
	var by := y + ih + roundf(4.0 * s)
	_bar(nx, by, bw, bh, minf(h, Weapons.HEALTH) / float(Weapons.HEALTH), hf)
	if h > Weapons.HEALTH:
		draw_rect(Rect2(nx, by + bh - maxf(2.0, roundf(2.0 * s)), bw * minf(1.0, float(h - Weapons.HEALTH) / float(Weapons.HEALTH_TOP - Weapons.HEALTH)), maxf(2.0, roundf(2.0 * s))), UI.over)
	# armour
	var ay := by + bh + roundf(10.0 * s)
	var heavy: bool = p.armour_class >= 2
	var ac: Color = UI.armour2 if heavy else UI.armour1
	var an: Color = UI.ink
	if p.armour <= 0:
		an = UiStyle.WAIT
	_icon(Pickups.kind_of("armor_big" if heavy else "armor"), x, ay + ih, ih)
	var ab := ay + ih - roundf(3.0 * s)
	var aw := _text(nx, ab, UiStyle.padded(int(p.armour)), fs, an, nums)
	_text(nx + aw + gap, ab, UiStyle.spaced("heavy" if heavy else ("light" if p.armour_class == 1 else "armour")), ls, UI.label)
	_bar(nx, ay + ih + roundf(4.0 * s), bw, bh, p.armour / float(Weapons.ARMOUR_MAX), ac)

## WHAT IS LEFT IN THE GUN, under its name at the right: the box its
## ammunition comes in, the count (∞ while the pause menu or IDDQD keeps
## it full; EMPTY in bold), over what the tank holds and its name, and
## the tank's bar under that — white, the alarm, when it runs low or dry
## or latches, and the count brighter. Returns where it ended.
func _draw_ammo(p: Player, d: Dictionary, rx: float, y: float, bw: float, bh: float, s: float) -> float:
	var tank: String = d.ammo
	var cap: int = Weapons.TANKS[tank][0]
	var n: int = p.ammo.get(tank, 0)
	var fs := int(roundf(30.0 * s))
	var ls := int(roundf(12.0 * s))
	var cs := int(roundf(17.0 * s))
	var ih := roundf(32.0 * s)
	var gap := roundf(6.0 * s)
	var endless: bool = p.debug or p.cheat
	var t := n / float(cap)
	var places := maxi(3, str(cap).length())
	var dry: bool = p.latched(p.weapon) or not p.has_ammo(p.weapon)
	var alarm := dry or n <= int(Weapons.LOW.get(tank, 0))
	var nc: Color = UI.low if alarm else UI.ink
	var fc: Color = UI.empty if alarm else UI.full
	if endless:
		nc = UI.gold
		fc = UI.over
	var top := y + roundf(6.0 * s)
	var base := top + ih - roundf(3.0 * s)
	# right to left: the tank's name, what it holds, the count, the box
	var tag := UiStyle.spaced(Pickups.tank_say(tank))
	var x := rx - _wide(tag, ls, words)
	_text(x, base, tag, ls, UI.label)
	var held := "/" + UiStyle.padded(cap, places)
	x -= _wide(held, cs, nums) + gap
	_text(x, base, held, cs, UI.label, nums)
	var count := "∞" if endless else ("" if not p.has_ammo(p.weapon) else UiStyle.padded(n, places))
	if count == "":
		var et := UiStyle.spaced("empty")
		var es := int(roundf(16.0 * s))
		x -= _wide(et, es, bold) + gap * 1.5
		_text(x, base, et, es, nc, bold)
	else:
		x -= _wide(count, fs, nums) + gap
		_text(x, base, count, fs, nc, nums)
	_icon(int(Pickups.TANK_ICON.get(tank, -1)), x - gap - ih, top + ih, ih)
	var by := top + ih + roundf(4.0 * s)
	var bwr := roundf(bw * 0.75)
	var mark: float = Weapons.TANKS[tank][2] if p.latched(p.weapon) else 0.0
	_bar(rx - bwr, by, bwr, bh, 1.0 if endless else t, fc, mark)
	return by + bh

## THE BOTTOM LEFT: the gun's own notices, stacked, newest at the bottom
## in NAME and the rest in TAG, each fading in its last second and a
## quarter (js/hud.js _drawToasts, toastFade)
func _draw_toasts(s: float) -> void:
	var list: Array = game.get("toasts") if game.get("toasts") != null else []
	if list.is_empty():
		return
	var M := roundf(20.0 * s)
	var fs := int(roundf(minf(14.0 * s, size.x / 32.0)))
	var lead := roundf(fs * 1.7)
	for i in list.size():
		var up := list.size() - 1 - i
		var y := size.y - M - up * lead
		if y < lead:
			continue
		var a := clampf(float(list[i].tics) / (1.25 * 35.0), 0.0, 1.0)
		var col: Color = UI.ink if up == 0 else UI.label
		_text(M, y, UiStyle.spaced(str(list[i].text)), fs, Color(col, col.a * a))

## YOU DIED (PlayerDeath), as galvarius has it: the screen washed red,
## the words big across the middle in its Mechsuit face, and once a press
## will do it, how to go again. THE WORDS, at the user's request: YOU
## ACHIEVED THE OPPOSITE OF LIFE, and the same in Japanese under it at
## half the size (JP_FONT: the glyphs of that one line out of IPA Gothic,
## assets/fonts/IPA_Font_License.txt) — both lines LEFT-justified in a
## block that is itself centred on the screen.
const DEATH_EN := "YOU ACHIEVED THE OPPOSITE OF LIFE"
const DEATH_JP := "あなたは生命の反対を達成した。"
const JP_FONT := "res://assets/fonts/mewd_died_jp.ttf"
const JP_SCALE := 0.8
const DEATH_KEY := "PRESS ANY KEY TO DIE ALONE"
## the red multiply over the whole picture, behind the words (_draw_death)
var _wash: ColorRect
func _make_wash() -> void:
	_wash = ColorRect.new()
	_wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wash.show_behind_parent = true
	_wash.visible = false
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	_wash.material = m
	add_child(_wash)

func _red_wash(c: Color) -> void:
	if _wash == null:
		return
	_wash.color = c
	_wash.visible = true
var _dead_font: Font
var _jp_font: Font
func _draw_death(s: float) -> void:
	var D = game.get("death")
	if D == null or not D.active:
		if _wash != null:
			_wash.visible = false
		return
	if _dead_font == null:
		_dead_font = load("res://assets/fonts/Mechsuit.otf")
		if _dead_font == null:
			_dead_font = font
		_jp_font = load(JP_FONT)
		if _jp_font == null:
			_jp_font = font
	var k := clampf(D.t / 35.0, 0.0, 1.0)
	# THE WHOLE PICTURE MULTIPLIED BY RED (at the user's request: "a 100%
	# full red color multiply overlay"), coming in over the first second:
	# a rect behind this control's own drawing, so the words are not
	_red_wash(Color(1.0, 1.0 - k, 1.0 - k))
	# the big line as big as it may be and still fit nine tenths of the width
	var fs := int(roundf(56.0 * s))
	var w := _dead_font.get_string_size(DEATH_EN, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if w > size.x * 0.9:
		fs = maxi(8, int(fs * size.x * 0.9 / w))
		w = _dead_font.get_string_size(DEATH_EN, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	# the Japanese bigger (at the user's request), as big as the English
	# block is wide at most
	var js := maxi(8, int(fs * JP_SCALE))
	var jw := _jp_font.get_string_size(DEATH_JP, HORIZONTAL_ALIGNMENT_LEFT, -1, js).x
	if jw > w:
		js = maxi(8, int(js * w / jw))
		jw = _jp_font.get_string_size(DEATH_JP, HORIZONTAL_ALIGNMENT_LEFT, -1, js).x
	# THE BLOCK: as wide as its widest line, centred; the lines at its left
	var bw := maxf(w, jw)
	var x0 := roundf(size.x * 0.5 - bw * 0.5)
	var y := size.y * 0.40
	var ink := Color(1.0, 0.92, 0.88, k)
	var shade := Color(0, 0, 0, 0.7 * k)
	draw_string(_dead_font, Vector2(x0 + 3, y + 3), DEATH_EN, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, shade)
	draw_string(_dead_font, Vector2(x0, y), DEATH_EN, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
	# THE JAPANESE IN A DARK BANNER across the screen, under the English
	var pad := roundf(js * 0.45)
	var top := y + fs * 0.4
	var band := js + pad * 2.0
	draw_rect(Rect2(0.0, top, size.x, band), Color(0.04, 0.0, 0.0, 0.82 * k))
	draw_rect(Rect2(0.0, top, size.x, maxf(1.0, s)), Color(1.0, 0.92, 0.88, 0.25 * k))
	draw_rect(Rect2(0.0, top + band - maxf(1.0, s), size.x, maxf(1.0, s)), Color(1.0, 0.92, 0.88, 0.25 * k))
	var y2 := top + pad + js * 0.86
	draw_string(_jp_font, Vector2(x0, y2), DEATH_JP, HORIZONTAL_ALIGNMENT_LEFT, -1, js, ink)
	y2 = top + band
	# and once a press will do it: PRESS ANY KEY TO DIE ALONE (at the
	# user's request), in the same block, RIGHT-justified to its edge
	if D.can_restart():
		var h := DEATH_KEY
		var hs := int(roundf(18.0 * s))
		var hw := bold.get_string_size(h, HORIZONTAL_ALIGNMENT_LEFT, -1, hs).x
		var a := 0.8 + 0.2 * sin(Time.get_ticks_msec() * 0.005)
		var hp := Vector2(x0 + bw - hw, y2 + hs * 2.2)
		# a drop shadow and a solid black stroke round it (at the user's
		# request); only the letters themselves pulse. The letters are the
		# house's (golf's words, in bold, BRIGHT): the small print round
		# the card is chrome, the card itself is not
		var so := maxf(2.0, roundf(3.0 * s))
		var ow := int(maxf(4.0, roundf(6.0 * s)))
		draw_string_outline(bold, hp + Vector2(so, so), h, HORIZONTAL_ALIGNMENT_LEFT, -1, hs, ow, Color(0, 0, 0, 0.6))
		draw_string_outline(bold, hp, h, HORIZONTAL_ALIGNMENT_LEFT, -1, hs, ow, Color(0, 0, 0, 1.0))
		draw_string(bold, hp, h, HORIZONTAL_ALIGNMENT_LEFT, -1, hs, Color(UiStyle.BRIGHT, a))

## the big card across the middle (Game.set_big_message): the words in
## bold, BRIGHT, in a heavy outline over the world
func _draw_big(s: float) -> void:
	var t = game.get("big_message")
	if t == null or str(t) == "":
		return
	var fs := int(roundf(30.0 * s))
	var w := _wide(str(t), fs, bold)
	var y := size.y * 0.36
	_text(size.x * 0.5 - w * 0.5, y, str(t), fs, UiStyle.BRIGHT, bold)

## A MATCH'S SCORE (js/net/remote.js NetBoard): a line at the top of the
## screen, and the whole table under it while TAB is held or the round
## is over — in a house window, the column names in TAG, the rows in
## NAME, your own row white and bold on the cursor's glass, the numbers
## in digital-7. The lines come set out for a monospaced face (each
## column padded to its place); the faces here are not, so the columns
## are found where the headings start and each is set out again by its
## widest cell.
func _draw_board(s: float) -> void:
	var lines: Array = game.net.board_lines(Input.is_physical_key_pressed(KEY_TAB))
	var fs := int(roundf(14.0 * s))
	var ls := int(roundf(12.0 * s))
	var ns := int(roundf(17.0 * s))
	var lh := roundf(ns * 1.35)
	var y := roundf(8.0 * s) + fs
	var head := str(lines[0])
	var w := _wide(head, fs, words)
	_text(size.x * 0.5 - w * 0.5, y, head, fs, UI.ink)
	if lines.size() <= 1:
		return
	# the headings' line, if the table is up
	var hi := -1
	for i in range(1, lines.size()):
		if str(lines[i]).begins_with("NAME"):
			hi = i
			break
	# the lines above it, said plainly (the score, the host's note)
	var plain: Array[String] = []
	for i in range(1, hi if hi > 0 else lines.size()):
		plain.append(str(lines[i]))
	# the columns: where each heading starts is where its cells start
	var starts: Array[int] = []
	var heads: Array[String] = []
	var rows: Array = []
	var mine: Array[bool] = []
	if hi > 0:
		var hl := str(lines[hi])
		for i in hl.length():
			if hl[i] != " " and (i == 0 or hl[i - 1] == " "):
				starts.append(i)
		for c in starts.size():
			heads.append(_cell(hl, starts, c))
		for i in range(hi + 1, lines.size()):
			var ln := str(lines[i])
			var cells: Array[String] = []
			for c in starts.size():
				cells.append(_cell(ln, starts, c))
			rows.append(cells)
			mine.append(ln.begins_with(">"))
	# a column of nothing but whole numbers is a column of numbers
	var numeric: Array[bool] = []
	var widths: Array[float] = []
	for c in starts.size():
		var all_int := not rows.is_empty() and c > 0
		for r in rows:
			var v: String = r[c]
			if v != "" and not v.is_valid_int():
				all_int = false
		numeric.append(all_int)
		widths.append(_wide(heads[c], ls, words))
	for ri in rows.size():
		for c in starts.size():
			var v: String = rows[ri][c]
			var cw := _wide(_board_num(v), ns, nums) if numeric[c] else _wide(v, ns, bold if mine[ri] else words)
			widths[c] = maxf(widths[c], cw)
	var cgap := roundf(16.0 * s)
	var tw := 0.0
	for c in widths.size():
		tw += widths[c] + (cgap if c > 0 else 0.0)
	for t in plain:
		tw = maxf(tw, _wide(t, fs, words))
	# how tall it all is
	var th := 0.0
	for t in plain:
		th += lh * (0.5 if t == "" else 1.0)
	if hi > 0:
		th += lh + roundf(6.0 * s) + rows.size() * lh
	var pad := roundf(12.0 * s)
	var top := y + lh * 0.5
	var left := roundf(size.x * 0.5 - tw * 0.5)
	CutBox.draw_on(self, Rect2(left - pad, top, tw + pad * 2.0, th + pad * 2.0), UiStyle.PANEL_BG, UiStyle.PANEL_BORDER,
		clampf(roundf(2.0 * s), 1.0, 2.0), roundf(UiStyle.CUT_ROW * s))
	# (on the window's glass the text needs no outline)
	var yy := top + pad
	for t in plain:
		if t == "":
			yy += lh * 0.5
			continue
		yy += lh
		_text(left, yy - lh * 0.25, t, fs, UI.ink, words, false)
	if hi <= 0:
		return
	yy += lh
	var x := left
	for c in starts.size():
		var hw := _wide(heads[c], ls, words)
		_text(x + (widths[c] - hw if numeric[c] else 0.0), yy - lh * 0.25, heads[c], ls, UI.label, words, false)
		x += widths[c] + cgap
	draw_rect(Rect2(left, yy + roundf(2.0 * s), tw, 1.0), UI.rule)
	yy += roundf(6.0 * s)
	for ri in rows.size():
		var me: bool = mine[ri]
		if me:
			CutBox.draw_on(self, Rect2(left - pad * 0.5, yy + lh * 0.08, tw + pad, lh * 0.92), UiStyle.SEL_BG, Color(0, 0, 0, 0), 0.0,
				roundf(UiStyle.CUT_CURSOR * s))
		yy += lh
		var ink: Color = UiStyle.CURSOR if me else UI.ink
		x = left
		for c in starts.size():
			var v: String = rows[ri][c]
			if numeric[c]:
				var nt := _board_num(v)
				_text(x + widths[c] - _wide(nt, ns, nums), yy - lh * 0.22, nt, ns, ink, nums, false)
			else:
				_text(x, yy - lh * 0.25, v, ns, ink, bold if me else words, false)
			x += widths[c] + cgap

## one cell of a monospaced line: from its column's start to the next's,
## trimmed (and the first column without the > that marks your row)
func _cell(ln: String, starts: Array[int], c: int) -> String:
	var a := 0 if c == 0 else starts[c]
	var v := ln.substr(a, (starts[c + 1] - a) if c + 1 < starts.size() else -1).strip_edges()
	if c == 0 and v.begins_with(">"):
		v = v.substr(1).strip_edges()
	return v

## a whole number on the board, zero-padded the house's way
func _board_num(v: String) -> String:
	return "" if v == "" else "%03d" % v.to_int()
