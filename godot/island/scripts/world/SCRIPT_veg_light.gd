class_name VegLight
extends RefCounted

## A PLANT'S BAKED LIGHT (at the user's request: "maybe even make it use an
## approximated bake so vegetation stays as lightweight as possible"): how much
## of the island's light reaches a plant where it stands, worked out
## once by the scatter that places it, off the field sample it has already
## taken, and carried in the instance's custom data (`INSTANCE_CUSTOM.x`) for
## SHADER_veg_billboard.gdshader to multiply by. Nothing is looked up while
## it is drawn.
##
##   * UNDER A CANOPY, darker: a third off in the densest wood (the field's
##     tree cover, a real place's, or golf's forest mask).
##   * ON A STEEP SLOPE a little darker, the sky half hidden by the hill.
##   * And each plant a little lighter or darker than its neighbour, by a
##     hash of where it stands, so a wood is never one flat colour.

## `s` the field's sample at the plant, `jitter` 0..1 its own.
static func of(s: Dictionary, jitter: float) -> float:
	var canopy := clampf(float(s.get("forest", 0.0)), 0.0, 1.0)
	var veg: Variant = s.get("veg")
	if veg is Dictionary:
		canopy = clampf(float((veg as Dictionary).get("tree", 0.0)), 0.0, 1.0)
	var n: Vector3 = s.get("normal", Vector3.UP)
	var light := (1.0 - 0.33 * canopy) * (0.86 + 0.14 * clampf(n.y, 0.0, 1.0))
	light *= 0.88 + 0.22 * jitter
	return clampf(light, 0.3, 1.2)
