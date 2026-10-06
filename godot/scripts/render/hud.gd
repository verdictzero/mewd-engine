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
class_name Hud
extends Control

## the page's own colours, not the palette's: a bar is a bar, not a material
const UI := {
	"ink": Color8(236, 232, 220, 240), "rule": Color8(232, 195, 74, 140),
	"track": Color8(6, 7, 12, 158), "trackEdge": Color8(236, 232, 220, 77),
	"mark": Color8(255, 255, 255, 235), "burn": Color("#e8621a"),
	"full": Color("#5fd0e8"), "low": Color("#e8c34a"), "empty": Color("#e8503c"),
	"armour2": Color("#5a8fe8"), "armour1": Color("#a07ae8"), "health": Color("#ece6d2"),
	"death": Color("#c8102e"), "over": Color("#7ff0c8"), "gold": Color("#ffd75a"),
}

var game
var font: Font
## the pickups' strip as drawn (sRGB, not the world's decoded copy), for
## the icons
var icons: Texture2D

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = U.ui_font(PackedStringArray(["monospace", "DejaVu Sans Mono", "Liberation Mono"]))
	icons = load(Pickups.STRIP)
	_make_wash()

func _process(_dt: float) -> void:
	queue_redraw()

## a 720-row window is the unit, clamped so it is never a whisper or a poster
func _scale() -> float:
	return clampf(size.y / 720.0, 0.78, 1.7)

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
	# the weapon's name, far corner, an amber hairline under it
	if not p.dead:
		var name: String = d.name
		var fs := int(roundf(13.0 * s))
		var spaced := " ".join(name.split(""))
		var w := font.get_string_size(spaced, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x := rx - w
		var ny := M + fs
		draw_string(font, Vector2(x + 1, ny + 1), spaced, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.6))
		draw_string(font, Vector2(x, ny), spaced, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UI.ink)
		draw_rect(Rect2(x, ny + roundf(5.0 * s), w, maxf(1.0, roundf(s))), UI.rule)
		# WHAT IS LEFT IN IT, under the name
		var ay := ny + roundf(5.0 * s)
		if d.has("ammo"):
			ay = _draw_ammo(p, d, rx, ay, bw, BAR, s)
		# the brains taken (Trophies), under it
		if p.brains > 0:
			var bs := int(roundf(11.0 * s))
			var bt := "B R A I N S  %d" % p.brains
			var bx := rx - font.get_string_size(bt, HORIZONTAL_ALIGNMENT_LEFT, -1, bs).x
			var by := ay + bs + roundf(6.0 * s)
			draw_string(font, Vector2(bx + 1, by + 1), bt, HORIZONTAL_ALIGNMENT_LEFT, -1, bs, Color(0, 0, 0, 0.6))
			draw_string(font, Vector2(bx, by), bt, HORIZONTAL_ALIGNMENT_LEFT, -1, bs, Color(1.0, 0.72, 0.78, 0.92))
	elif game.get("death") == null or not game.death.active:
		# the card: 死, and YOU DIED (a match's death; a game alone has its
		# own words, _draw_death)
		var band := size.y * 0.22
		var top := size.y * 0.5 - band * 0.5
		draw_rect(Rect2(0, top, size.x, band), Color(0, 0, 0, 0.72))
		var ks := int(band * 0.55)
		var kw := font.get_string_size("死", HORIZONTAL_ALIGNMENT_LEFT, -1, ks).x
		draw_string(font, Vector2(size.x * 0.5 - kw * 0.5, top + band * 0.62), "死", HORIZONTAL_ALIGNMENT_LEFT, -1, ks, UI.death)
		var ts := int(roundf(18.0 * s))
		var txt := "Y O U   D I E D"
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x
		draw_string(font, Vector2(size.x * 0.5 - tw * 0.5, top + band * 0.9), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, UI.death)
	# SLOW MOTION, said at the top of the screen while it is on
	if game.get("slow_mo") == true:
		var ss := int(roundf(12.0 * s))
		var st := "S L O W   M O T I O N"
		var sw := font.get_string_size(st, HORIZONTAL_ALIGNMENT_LEFT, -1, ss).x
		var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.004)
		draw_string(font, Vector2(size.x * 0.5 - sw * 0.5 + 1, M + ss + 1), st, HORIZONTAL_ALIGNMENT_LEFT, -1, ss, Color(0, 0, 0, 0.6))
		draw_string(font, Vector2(size.x * 0.5 - sw * 0.5, M + ss), st, HORIZONTAL_ALIGNMENT_LEFT, -1, ss, Color(UI.rule.r, UI.rule.g, UI.rule.b, pulse))
	# THE DROP'S READOUT (DropPod): the altitude, the fall, the tilt, the
	# retros, the autopilot when it has the burn, the reentry fire before
	var drop = game.get("drop")
	if drop != null and drop.active and drop.phase == "drop":
		var r: Dictionary = drop.readout()
		var ds := int(roundf(13.0 * s))
		var lines := ["A L T  %5.0f m" % r.alt, "F A L L  %4.0f m/s" % r.fall, "T I L T  %3.0f°" % r.tilt]
		# (no RCS line while the pod has none: DropPod.RCS_ON)
		if r.has("fuel"):
			var fuel := float(r.fuel)
			lines.append(("R C S  %3.0f%%" % (fuel * 100.0)) if fuel > 0.0 else "R C S   D R Y")
		var y0 := M + ds
		for ln in lines:
			var lw := font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, ds).x
			draw_string(font, Vector2(size.x * 0.5 - lw * 0.5 + 1, y0 + 1), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, ds, Color(0, 0, 0, 0.6))
			draw_string(font, Vector2(size.x * 0.5 - lw * 0.5, y0), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, ds, UI.ink)
			y0 += ds + 4.0 * s
		var warn := ""
		if r.retro > 0.0:
			warn = "A U T O   B U R N" if r.auto else "R E T R O S"
		elif float(r.get("heat", 0.0)) > 0.1:
			warn = "R E E N T R Y"
		if warn != "":
			var rw := font.get_string_size(warn, HORIZONTAL_ALIGNMENT_LEFT, -1, ds).x
			var pulse := 0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.01)
			draw_string(font, Vector2(size.x * 0.5 - rw * 0.5, y0 + ds), warn, HORIZONTAL_ALIGNMENT_LEFT, -1, ds, Color(UI.burn.r, UI.burn.g, UI.burn.b, pulse))
	# the red wash when something hits you, and the gold of a pickup
	if p.damage_flash > 0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.8, 0.05, 0.02, minf(0.35, p.damage_flash * 0.025)))
	if p.bonus_flash > 0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.84, 0.32, minf(0.16, p.bonus_flash * 0.027)))
	_draw_toasts(s)
	_draw_big(s)
	_draw_death(s)
	if game.get("net") != null:
		_draw_board(s)

## text with the house's drop shadow; how wide it was
func _text(x: float, y: float, t: String, fs: int, col: Color) -> float:
	draw_string(font, Vector2(x + 1, y + 1), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.6 * col.a))
	draw_string(font, Vector2(x, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	return font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x

## a pickup's picture (its cell of the strip), `h` high, its foot at y
func _icon(cell: int, x: float, y: float, h: float) -> void:
	if icons == null or cell < 0:
		return
	var c := float(icons.get_height())
	draw_texture_rect_region(icons, Rect2(x, y - h, h, h), Rect2(cell * c, 0, c, c))

## HEALTH AND ARMOUR, top left: the medkit and the number (amber at half,
## red at a quarter, mint over the top), the bar under it; the armour
## you wear and its number, its bar in its class's colour (violet
## light, blue heavy); and GOD in gold while IDDQD is on.
func _draw_vitals(p: Player, x: float, y: float, bw: float, bh: float, s: float) -> void:
	var fs := int(roundf(24.0 * s))
	var ls := int(roundf(11.0 * s))
	var ih := roundf(34.0 * s)
	bw = roundf(bw * 0.85)
	var gap := roundf(10.0 * s)
	var nx := x + ih + gap
	# health
	var h: int = p.health
	var hc: Color = UI.over if h > Weapons.HEALTH else (UI.empty if h <= 25 else (UI.low if h <= 50 else UI.health))
	var base := y + ih - roundf(3.0 * s)
	_icon(Pickups.kind_of("health"), x, y + ih, ih)
	var w := _text(nx, base, "%3d" % h, fs, hc)
	var lw := _text(nx + w + gap, base, "H E A L T H", ls, Color(UI.ink, 0.7))
	if p.cheat:
		_text(nx + w + gap * 3.0 + lw, base, "G O D", ls, UI.gold)
	var by := y + ih + roundf(4.0 * s)
	_bar(nx, by, bw, bh, minf(h, Weapons.HEALTH) / float(Weapons.HEALTH), hc)
	if h > Weapons.HEALTH:
		draw_rect(Rect2(nx, by + bh - maxf(2.0, roundf(2.0 * s)), bw * minf(1.0, float(h - Weapons.HEALTH) / float(Weapons.HEALTH_TOP - Weapons.HEALTH)), maxf(2.0, roundf(2.0 * s))), UI.gold)
	# armour
	var ay := by + bh + roundf(10.0 * s)
	var heavy: bool = p.armour_class >= 2
	var ac: Color = UI.armour2 if heavy else UI.armour1
	if p.armour <= 0:
		ac = Color(UI.ink, 0.45)
	_icon(Pickups.kind_of("armor_big" if heavy else "armor"), x, ay + ih, ih)
	var ab := ay + ih - roundf(3.0 * s)
	var aw := _text(nx, ab, "%3d" % p.armour, fs, ac)
	_text(nx + aw + gap, ab, ("H E A V Y" if heavy else ("L I G H T" if p.armour_class == 1 else "A R M O U R")), ls, Color(UI.ink, 0.7))
	_bar(nx, ay + ih + roundf(4.0 * s), bw, bh, p.armour / float(Weapons.ARMOUR_MAX), ac)

## WHAT IS LEFT IN THE GUN, under its name at the right: the box its
## ammunition comes in, the count (∞ while the pause menu or IDDQD keeps
## it full; EMPTY in red), over what the tank holds and its name, and
## the tank's bar under that. Returns where it ended.
func _draw_ammo(p: Player, d: Dictionary, rx: float, y: float, bw: float, bh: float, s: float) -> float:
	var tank: String = d.ammo
	var cap: int = Weapons.TANKS[tank][0]
	var n: int = p.ammo.get(tank, 0)
	var fs := int(roundf(24.0 * s))
	var ls := int(roundf(11.0 * s))
	var ih := roundf(32.0 * s)
	var gap := roundf(6.0 * s)
	var endless: bool = p.debug or p.cheat
	var t := n / float(cap)
	var col: Color = UI.empty if (p.latched(p.weapon) or not p.has_ammo(p.weapon)) else (UI.low if n <= int(Weapons.LOW.get(tank, 0)) else UI.full)
	var top := y + roundf(6.0 * s)
	var base := top + ih - roundf(3.0 * s)
	var label := "/%d  %s" % [cap, " ".join(Pickups.tank_say(tank).split(""))]
	var count := "∞" if endless else ("E M P T Y" if not p.has_ammo(p.weapon) else str(n))
	var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, ls).x
	var cw := font.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := rx - lw
	_text(x, base, label, ls, Color(UI.ink, 0.7))
	x -= cw + gap
	_text(x, base, count, fs, UI.gold if endless else col)
	_icon(int(Pickups.TANK_ICON.get(tank, -1)), x - gap - ih, top + ih, ih)
	var by := top + ih + roundf(4.0 * s)
	var bwr := roundf(bw * 0.75)
	var mark: float = Weapons.TANKS[tank][2] if p.latched(p.weapon) else 0.0
	_bar(rx - bwr, by, bwr, bh, 1.0 if endless else t, UI.gold if endless else col, mark)
	return by + bh

## THE BOTTOM LEFT: the gun's own notices, stacked, newest at the bottom
## in amber and the rest in the ordinary ink, each fading in its last
## second and a quarter (js/hud.js _drawToasts, toastFade)
func _draw_toasts(s: float) -> void:
	var list: Array = game.get("toasts") if game.get("toasts") != null else []
	if list.is_empty():
		return
	var M := roundf(20.0 * s)
	var fs := int(roundf(minf(13.0 * s, size.x / 34.0)))
	var lead := roundf(fs * 1.7)
	for i in list.size():
		var up := list.size() - 1 - i
		var y := size.y - M - up * lead
		if y < lead:
			continue
		var a := clampf(float(list[i].tics) / (1.25 * 35.0), 0.0, 1.0)
		var col: Color = UI.low if up == 0 else UI.ink
		var t := " ".join(str(list[i].text).split(""))
		draw_string(font, Vector2(M + 1, y + 1), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.6 * a))
		draw_string(font, Vector2(M, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, col.a * a))

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
		var hs := int(roundf(16.0 * s))
		var hw := font.get_string_size(h, HORIZONTAL_ALIGNMENT_LEFT, -1, hs).x
		var a := 0.8 + 0.2 * sin(Time.get_ticks_msec() * 0.005)
		var hp := Vector2(x0 + bw - hw, y2 + hs * 2.2)
		# a drop shadow and a solid black stroke round it (at the user's
		# request); only the letters themselves pulse
		var so := maxf(2.0, roundf(3.0 * s))
		var ow := int(maxf(4.0, roundf(6.0 * s)))
		draw_string_outline(font, hp + Vector2(so, so), h, HORIZONTAL_ALIGNMENT_LEFT, -1, hs, ow, Color(0, 0, 0, 0.6))
		draw_string_outline(font, hp, h, HORIZONTAL_ALIGNMENT_LEFT, -1, hs, ow, Color(0, 0, 0, 1.0))
		draw_string(font, hp, h, HORIZONTAL_ALIGNMENT_LEFT, -1, hs, Color(1.0, 0.95, 0.9, a))

## the big card across the middle (Game.set_big_message)
func _draw_big(s: float) -> void:
	var t = game.get("big_message")
	if t == null or str(t) == "":
		return
	var fs := int(roundf(26.0 * s))
	var w := font.get_string_size(str(t), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var y := size.y * 0.36
	draw_string(font, Vector2(size.x * 0.5 - w * 0.5 + 2, y + 2), str(t), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.7))
	draw_string(font, Vector2(size.x * 0.5 - w * 0.5, y), str(t), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UI.low)

## A MATCH'S SCORE (js/net/remote.js NetBoard): a line at the top of the
## screen, and the whole table under it while TAB is held or the round
## is over
func _draw_board(s: float) -> void:
	var lines: Array = game.net.board_lines(Input.is_physical_key_pressed(KEY_TAB))
	var fs := int(roundf(12.0 * s))
	var lh := roundf(fs * 1.35)
	var y := roundf(8.0 * s) + fs
	var head: String = lines[0]
	var w := font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(size.x * 0.5 - w * 0.5 + 1, y + 1), head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.8))
	draw_string(font, Vector2(size.x * 0.5 - w * 0.5, y), head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UI.ink)
	if lines.size() <= 1:
		return
	var tw := 0.0
	for i in range(1, lines.size()):
		tw = maxf(tw, font.get_string_size(str(lines[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var pad := roundf(10.0 * s)
	var top := y + lh * 0.5
	draw_rect(Rect2(size.x * 0.5 - tw * 0.5 - pad, top, tw + pad * 2.0, (lines.size() - 1) * lh + pad), Color(0, 0, 0, 0.72))
	for i in range(1, lines.size()):
		draw_string(font, Vector2(size.x * 0.5 - tw * 0.5, top + i * lh - lh * 0.2), str(lines[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UI.ink)
