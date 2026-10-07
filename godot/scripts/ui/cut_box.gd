## MEWD — THE FRAME OF EVERY PANEL AND ROW (golf's SCRIPT_combat_panel, as
## a StyleBox so any PanelContainer, Button or LineEdit can wear it; at the
## user's request, "port the UI design language from verdictzero/golf"):
## a fill and a keyline round a box whose corners are square or cut at 45
## degrees, never rounded. The house shape cuts the top right and the
## bottom left (UiStyle). An optional shadow is a few offset copies of the
## shape, not a blur.
class_name CutBox
extends StyleBox

var bg := Color(0.05, 0.05, 0.06, 0.82)
var border := Color(0.72, 0.72, 0.74, 1.0)
var width := 2.0
## the length of each 45-degree cut along its edges
var cut := 16.0
var tl := false
var tr := true
var br := false
var bl := true
var shadow := Color(0, 0, 0, 0)
var shadow_offset := Vector2(2, 3)

func _init(fill := Color(0.05, 0.05, 0.06, 0.82), line := Color(0.72, 0.72, 0.74, 1.0), w := 2.0, c := 16.0) -> void:
	bg = fill
	border = line
	width = w
	cut = c

## the corners cut, top left, top right, bottom right, bottom left
func corners(a: bool, b: bool, c: bool, d: bool) -> CutBox:
	tl = a
	tr = b
	br = c
	bl = d
	return self

func margins(l: float, t: float, r: float, b: float) -> CutBox:
	content_margin_left = l
	content_margin_top = t
	content_margin_right = r
	content_margin_bottom = b
	return self

func points(r: Rect2) -> PackedVector2Array:
	var c := clampf(cut, 0.0, minf(r.size.x, r.size.y) * 0.5)
	var p := r.position
	var s := r.size
	var pts := PackedVector2Array()
	if tl:
		pts.append(p + Vector2(0, c))
		pts.append(p + Vector2(c, 0))
	else:
		pts.append(p)
	if tr:
		pts.append(p + Vector2(s.x - c, 0))
		pts.append(p + Vector2(s.x, c))
	else:
		pts.append(p + Vector2(s.x, 0))
	if br:
		pts.append(p + Vector2(s.x, s.y - c))
		pts.append(p + Vector2(s.x - c, s.y))
	else:
		pts.append(p + s)
	if bl:
		pts.append(p + Vector2(c, s.y))
		pts.append(p + Vector2(0, s.y - c))
	else:
		pts.append(p + Vector2(0, s.y))
	return pts

func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if rect.size.x < 1.0 or rect.size.y < 1.0:
		return
	var pts := points(rect)
	if shadow.a > 0.0:
		var per := Color(shadow.r, shadow.g, shadow.b, shadow.a / 4.0)
		for i in range(1, 5):
			var off := shadow_offset * (i / 4.0)
			var sp := PackedVector2Array()
			for q in pts:
				sp.append(q + off)
			RenderingServer.canvas_item_add_polygon(to_canvas_item, sp, PackedColorArray([per]))
	if bg.a > 0.0:
		RenderingServer.canvas_item_add_polygon(to_canvas_item, pts, PackedColorArray([bg]))
	if width > 0.0 and border.a > 0.0:
		var line := pts.duplicate()
		line.append(pts[0])
		RenderingServer.canvas_item_add_polyline(to_canvas_item, line, PackedColorArray([border]), width, true)

## the same frame drawn straight onto a CanvasItem (the HUD, the loading
## screen: drawn, not built)
static func draw_on(ci: CanvasItem, r: Rect2, fill: Color, line: Color, w := 2.0, c := 12.0, cuts := [false, true, false, true]) -> void:
	var b := CutBox.new(fill, line, w, c).corners(cuts[0], cuts[1], cuts[2], cuts[3])
	b.draw(ci.get_canvas_item(), r)
