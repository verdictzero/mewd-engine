## MEWD — THE HOUSE STYLE OF EVERY SCREEN (at the user's request: "port the
## UI design language from verdictzero/golf over to MEWD and implement fully
## in all aspects"; golf's docs/DOC_ui_style.md and SCRIPT_menu_system.gd).
##
## NO HUE. Brightness is the only thing a value can mean, so every colour
## here is a grey, and each surface reads them BY NAME, never by copying:
##   CURSOR  white   where you are; a gauge that has topped out (the alarm)
##   READY           selectable, not selected
##   NAME            the value a widget is there to show; body text
##   TAG             section labels, units, hints
##   WAIT            inactive, unfocused, edges (large text only)
##   DIM             disabled, rules, ticks — never text to be read
##   BRIGHT          a passing flash ("SAVED")
##   HP / TP / EXP   bar fills by weight, the bigger the fill the darker
## Corners square or cut at 45 degrees, never rounded (CutBox): the house
## shape cuts the top right and the bottom left; windows cut 16, rows 12,
## small plates 10, the cursor box 8.
##
## TYPE BY ROLE, never by file: WORDS in Zalando Sans Condensed (Medium the
## default, ExtraLight a resting title row, Bold the selected one — a
## selection changes weight, not size), NUMBERS in digital-7 mono,
## zero-padded, GLYPHS (pad buttons) in PromptFont. Letters spaced with
## spaces (`spaced`). Text over the moving world wears a black outline;
## text over a darkened, paused one does not.
##
## THE CURSOR: no hover state and no filled call-to-action pill — the one
## cursor moves with the mouse or the pad, and the row under it goes white,
## bold, its box brighter and its keyline white. It is highlighted, never
## moved (at the user's request: "dont indent menu items, just highlight").
class_name UiStyle
extends RefCounted

const CURSOR := Color(1.00, 1.00, 1.00)
const READY := Color(0.82, 0.82, 0.82)
const WAIT := Color(0.45, 0.45, 0.45)
const TAG := Color(0.60, 0.60, 0.60)
const NAME := Color(0.90, 0.90, 0.90)
const HP := Color(0.85, 0.85, 0.85)
const TP := Color(0.68, 0.68, 0.68)
const EXP := Color(0.52, 0.52, 0.52)
const BAR_BG := Color(0.0, 0.0, 0.0, 0.5)
const BAR_BORDER := Color(0.6, 0.6, 0.6, 0.7)
const DIM := Color(0.33, 0.33, 0.33)
const BRIGHT := Color(0.96, 0.96, 0.96)

## the glass: a translucent near-black with a breath of blue in it
const PANEL_BG := Color(0.05, 0.05, 0.06, 0.82)
const PANEL_BORDER := Color(0.72, 0.72, 0.74, 1.0)
const SEL_BG := Color(1.0, 1.0, 1.0, 0.10)
## a selected row's fill: SEL_BG over PANEL_BG
const PANEL_BG_SEL := Color(0.149, 0.149, 0.161, 0.85)
const PANEL_BORDER_REST := Color(0.72, 0.72, 0.74, 0.8)
## the shade over a paused game
const SHADE := Color(0.0, 0.0, 0.0, 0.72)

## cut sizes
const CUT_WINDOW := 16.0
const CUT_ROW := 12.0
const CUT_PLATE := 10.0
const CUT_CURSOR := 8.0

const _WORDS := "res://assets/fonts/zalando/ZalandoSans-Condensed%s.ttf"
const _NUMBERS := "res://assets/fonts/digital7/digital-7-mono.ttf"
const _GLYPHS := "res://assets/fonts/promptfont/promptfont.ttf"

static var _cache := {}

## the words, by weight: "ExtraLight", "Light", "Medium", "SemiBold",
## "Bold", "Black"
static func words(weight := "Medium") -> Font:
	var key := "w" + weight
	if not _cache.has(key):
		var f: FontFile = load(_WORDS % weight)
		var v := FontVariation.new()
		v.base_font = f
		# (the condensed face has no box drawing or arrows: DejaVu after it)
		v.fallbacks = [load("res://assets/fonts/dejavu/DejaVuSans.ttf")]
		_cache[key] = v
	return _cache[key]

## the numbers
static func numbers() -> Font:
	if not _cache.has("n"):
		var v := FontVariation.new()
		v.base_font = load(_NUMBERS)
		v.fallbacks = [words("Medium")]
		_cache["n"] = v
	return _cache["n"]

## the pad's buttons (only from ButtonGlyphs-style code points, never a
## sentence's font)
static func glyphs() -> Font:
	if not _cache.has("g"):
		_cache["g"] = load(_GLYPHS)
	return _cache["g"]

## letters a space apart, words three (golf's InteractPrompt.spaced)
static func spaced(s: String) -> String:
	var out := PackedStringArray()
	for w in s.to_upper().split(" ", false):
		var letters := PackedStringArray()
		for i in w.length():
			letters.append(w[i])
		out.append(" ".join(letters))
	return "   ".join(out)

## a number in the house's way: zero-padded to `places`
static func padded(n: int, places := 3) -> String:
	return ("%0" + str(places) + "d") % maxi(n, 0)

# ---- frames ------------------------------------------------------------------

## a window: the glass, a keyline, the house corners
static func window(margin := Vector4(16, 12, 16, 12)) -> CutBox:
	return CutBox.new(PANEL_BG, PANEL_BORDER, 2.0, CUT_WINDOW).margins(margin.x, margin.y, margin.z, margin.w)

## a row, resting or selected (or a disabled one)
static func row(selected: bool, disabled := false, cut := CUT_ROW) -> CutBox:
	var b := CutBox.new(PANEL_BG_SEL if selected and not disabled else PANEL_BG,
		CURSOR if selected and not disabled else (Color(DIM, 0.8) if disabled else PANEL_BORDER_REST), 2.0, cut)
	return b.margins(16, 6, 18, 6)

## the floating cursor box
static func cursor_box() -> CutBox:
	return CutBox.new(SEL_BG, CURSOR, 2.0, CUT_CURSOR).margins(10, 4, 10, 4)

## a bar's track
static func track() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = BAR_BG
	s.border_color = BAR_BORDER
	s.set_border_width_all(1)
	return s

# ---- controls ----------------------------------------------------------------

## a Button dressed as a row: no hover of its own (the cursor is the
## hover), white and bold when `selected` — in its place
static func dress_row(b: Button, selected: bool, disabled := false, size := 20) -> void:
	b.flat = false
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", words("Bold" if selected and not disabled else "Medium"))
	b.add_theme_font_size_override("font_size", size)
	var box := row(selected, disabled)
	for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		b.add_theme_stylebox_override(st, box)
	var ink := DIM if disabled else (CURSOR if selected else READY)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color", "font_disabled_color"]:
		b.add_theme_color_override(c, ink)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))

## a Label in a role: "name", "ready", "tag", "wait", "cursor", "bright"
static func label(text: String, role := "name", size := 18, weight := "Medium", outline := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", words(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ink(role))
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	return l

## a number Label (digital-7)
static func number(text: String, role := "name", size := 22) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", numbers())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ink(role))
	return l

## a section's heading: its name in TAG, a rule under it
static func header(text: String, size := 18) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.add_child(label(text.to_upper(), "tag", size))
	v.add_child(rule())
	return v

## a hairline rule in DIM
static func rule() -> HSeparator:
	var s := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = DIM
	line.thickness = 1
	s.add_theme_stylebox_override("separator", line)
	s.add_theme_constant_override("separation", 6)
	return s

static func ink(role: String) -> Color:
	match role:
		"cursor": return CURSOR
		"ready": return READY
		"tag": return TAG
		"wait": return WAIT
		"dim": return DIM
		"bright": return BRIGHT
	return NAME

## a LineEdit in the house's frame
static func dress_field(e: LineEdit, size := 20) -> void:
	e.add_theme_font_override("font", words("Medium"))
	e.add_theme_font_size_override("font_size", size)
	e.add_theme_color_override("font_color", NAME)
	e.add_theme_color_override("caret_color", CURSOR)
	e.add_theme_color_override("selection_color", Color(1, 1, 1, 0.25))
	e.add_theme_color_override("font_placeholder_color", WAIT)
	var b := CutBox.new(Color(0, 0, 0, 0.55), PANEL_BORDER_REST, 1.0, CUT_PLATE).margins(12, 6, 12, 6)
	e.add_theme_stylebox_override("normal", b)
	var f := CutBox.new(Color(0, 0, 0, 0.55), CURSOR, 2.0, CUT_PLATE).margins(12, 6, 12, 6)
	e.add_theme_stylebox_override("focus", f)
	e.add_theme_stylebox_override("read_only", b)

## a whole Theme for anything not dressed by hand (scrollbars, tooltips,
## stray Labels and Buttons): the house's words, greys and frames
static func theme() -> Theme:
	if _cache.has("theme"):
		return _cache["theme"]
	var t := Theme.new()
	t.default_font = words("Medium")
	t.default_font_size = 18
	t.set_color("font_color", "Label", NAME)
	t.set_color("font_color", "Button", READY)
	t.set_color("font_hover_color", "Button", CURSOR)
	t.set_color("font_pressed_color", "Button", CURSOR)
	t.set_color("font_disabled_color", "Button", DIM)
	t.set_color("font_focus_color", "Button", CURSOR)
	for st in ["normal", "focus", "disabled"]:
		t.set_stylebox(st, "Button", row(false, st == "disabled"))
	for st in ["hover", "pressed", "hover_pressed"]:
		t.set_stylebox(st, "Button", row(true))
	t.set_stylebox("panel", "PanelContainer", window())
	t.set_stylebox("panel", "Panel", window())
	var grab := StyleBoxFlat.new()
	grab.bg_color = TP
	var scroll := StyleBoxFlat.new()
	scroll.bg_color = BAR_BG
	scroll.content_margin_left = 4
	scroll.content_margin_right = 4
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab)
	t.set_stylebox("scroll", "VScrollBar", scroll)
	var tip := CutBox.new(PANEL_BG, PANEL_BORDER, 1.0, CUT_CURSOR).margins(8, 4, 8, 4)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", NAME)
	_cache["theme"] = t
	return t
