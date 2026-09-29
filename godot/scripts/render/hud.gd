## MEWD — the readout (js/hud.js, the readout half).
##
## PRINTED ON THE GLASS, at the user's request: its own layer over the
## filtered picture, at the screen's own resolution, never dithered or
## snapped — a label on the glass is not more honest for being out of
## focus, only harder to read. Almost nothing in it: how much of the map
## has gone, the tank of whatever is in your hands (with the pip where a
## latched tank starts working again), what is left of you once
## something starts taking it, and the weapon's name in the far corner.
class_name Hud
extends Control

## the page's own colours, not the palette's: a bar is a bar, not a material
const UI := {
	"ink": Color8(236, 232, 220, 240), "rule": Color8(232, 195, 74, 140),
	"track": Color8(6, 7, 12, 158), "trackEdge": Color8(236, 232, 220, 77),
	"mark": Color8(255, 255, 255, 235), "burn": Color("#e8621a"),
	"full": Color("#5fd0e8"), "low": Color("#e8c34a"), "empty": Color("#e8503c"),
	"armour2": Color("#5a8fe8"), "armour1": Color("#a07ae8"), "health": Color("#ece6d2"),
	"death": Color("#c8102e"),
}

var game
var font: Font

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["monospace", "DejaVu Sans Mono", "Liberation Mono"])
	font = f

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
	var y := M
	# how much of the place has gone
	_bar(M, y, bw, BAR, game.burn_percent() / 100.0, UI.burn)
	y += BAR + GAP
	# the tank in your hands
	var d := p.def()
	if d.has("ammo"):
		var cap: float = Weapons.TANKS[d.ammo][0]
		var t: float = p.ammo[d.ammo] / cap
		var col: Color = UI.empty if p.latched(p.weapon) else (UI.full if t > 0.35 else (UI.low if t > 0.12 else UI.empty))
		var mark: float = Weapons.TANKS[d.ammo][2] if p.latched(p.weapon) else 0.0
		_bar(M, y, bw, BAR, t, col, mark)
		y += BAR + GAP
	# and you, once something has started on you: the outer plate, the inner, then you
	if p.armour2 < Weapons.ARMOUR2 or p.armour1 < Weapons.ARMOUR1 or p.health < Weapons.HEALTH or p.dead:
		_bar(M, y, bw, BAR, p.armour2 / float(Weapons.ARMOUR2), UI.armour2)
		y += BAR + GAP
		_bar(M, y, bw, BAR, p.armour1 / float(Weapons.ARMOUR1), UI.armour1)
		y += BAR + GAP
		_bar(M, y, bw, BAR, p.health / float(Weapons.HEALTH), UI.health)
	# the weapon's name, far corner, an amber hairline under it
	if not p.dead:
		var name: String = d.name
		var fs := int(roundf(13.0 * s))
		var spaced := " ".join(name.split(""))
		var w := font.get_string_size(spaced, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x := size.x - M - w
		var ny := M + fs
		draw_string(font, Vector2(x + 1, ny + 1), spaced, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.6))
		draw_string(font, Vector2(x, ny), spaced, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UI.ink)
		draw_rect(Rect2(x, ny + roundf(5.0 * s), w, maxf(1.0, roundf(s))), UI.rule)
	else:
		# the card: 死, and YOU DIED
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
	# the red wash when something hits you
	if p.damage_flash > 0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.8, 0.05, 0.02, minf(0.35, p.damage_flash * 0.025)))
