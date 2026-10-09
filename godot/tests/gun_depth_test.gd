## MEWD — THE GUN'S BLACK SQUARES ON AN ADRENO (Lofi.gun_depth; at the
## user's request: "this gun rendering bug is still happening", "just
## adreno qualcomm"): the fix and its switches.
##
##   godot --headless --script res://godot/tests/gun_depth_test.gd
##
## Headless: every shader that writes depth in the gun's world writes its
## own (the line outside its MEWD_FIXED_DEPTH guard); the switches swap
## the gun's materials to copies compiled without it, and back to the
## shipped ones; the DEBUG page has them and the defaults are the fix.
##
## Under a real renderer (xvfb-run -a -s "-screen 0 1280x720x24" godot
## --audio-driver Dummy --script res://godot/tests/gun_depth_test.gd),
## the flamer drawn in the gun's own viewport, and its picture read back:
## writing its own depth draws it to the BYTE the same as the GPU's own
## depth did (and without the cut-out, the flamer having no alpha); the
## tonemap in a pass of its own within a half-float step of the subpass's;
## and, the gun world cleared to magenta, not one texel left undrawn.
## Prints OK or fails.
extends SceneTree

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1

func _init() -> void:
	# (a script error in an awaiting _init would leave the process running
	# for ever, and the suite with it)
	create_timer(300.0).timeout.connect(func(): print("gundepth: TIMED OUT"); quit(2))
	await process_frame
	# ---- the shaders -------------------------------------------------------
	var own := 0
	for path in Lofi.GUN_SHADERS:
		var code: String = (load(path) as Shader).code
		var at := code.find("void fragment() {")
		var guard := code.find("#ifndef MEWD_FIXED_DEPTH", at)
		var line := code.find("DEPTH = FRAGCOORD.z;", guard)
		var end := code.find("#endif", line)
		# (first thing in fragment(): before any discard can skip it)
		var first_stmt := code.find(";", at)
		if at >= 0 and guard > at and line > guard and end > line and first_stmt >= line:
			own += 1
	check(own == Lofi.GUN_SHADERS.size(), "every depth-writing shader of the gun's world writes its own depth (%d of %d)" % [own, Lofi.GUN_SHADERS.size()])
	var gun_code: String = (load("res://godot/shaders/gun.gdshader") as Shader).code
	check(gun_code.contains("#ifndef MEWD_NO_DISCARD\n\tif (c.a < 0.5) discard;\n#endif"), "the gun's cut-out behind its switch")

	# ---- the gun, and its switches ----------------------------------------
	var lofi := Lofi.new()
	root.add_child(lofi)
	var w3d := Weapon3D.new()
	lofi.gun.add_child(w3d)
	await process_frame
	w3d.preload_all()
	w3d.set_weapon("FLAMER")
	await process_frame
	check(lofi.gun_depth == "shader" and lofi.gun_tone == "auto" and lofi.gun_clear == "grey" and lofi.gun_hdr,
		"the fix is the default (own depth, tonemap auto, grey, HDR)")
	var d: Dictionary = (load("res://godot/scripts/ui/pause.gd") as Script).get_script_constant_map()["DEFAULTS"]
	var keys := []
	for dial in (load("res://godot/scripts/ui/pause.gd") as Script).get_script_constant_map()["DIALS"]:
		keys.append(dial[0])
	check(keys.has("gun_depth") and keys.has("gun_tone") and keys.has("gun_clear") and keys.has("gun_hdr")
		and d.gun_depth == "shader" and d.gun_tone == "auto" and d.gun_clear == "grey" and d.gun_hdr == true,
		"the DEBUG page has the four switches, the fix their defaults")
	var mats := _gun_mats(lofi)
	check(mats.size() >= 18, "the gun's world's materials found (%d)" % mats.size())
	check(_all_shipped(mats), "by default every one runs its shipped shader")
	var probe: ShaderMaterial = null
	for m in mats:
		if (m as ShaderMaterial).shader.resource_path.ends_with("/gun.gdshader") and m.get_shader_parameter("map") != null:
			probe = m
			break
	var probe_map = probe.get_shader_parameter("map") if probe != null else null
	lofi.gun_diag("fixed", "auto", "grey", true)
	check(_all_defined(mats, "MEWD_FIXED_DEPTH"), "GPU'S DEPTH: every one swapped to a copy without its own depth")
	lofi.gun_diag("nodiscard", "auto", "grey", true)
	check(_all_defined(mats, "MEWD_NO_DISCARD"), "NO CUT-OUT: and without the cut-out")
	lofi.gun_diag("shader", "auto", "grey", true)
	check(_all_shipped(mats) and probe != null and probe.get_shader_parameter("map") == probe_map,
		"and back to the shipped shaders, their settings kept")
	check(lofi.gun_state().begins_with("gun own depth") or not lofi.gun_on_room, "the PERF readout says which (%s)" % lofi.gun_state())
	lofi.gun_diag("own", "sometimes", "pink", true)
	check(lofi.gun_depth == "shader" and lofi.gun_tone == "auto" and lofi.gun_clear == "grey" and _all_shipped(mats),
		"a value it does not know (a settings file edited by hand) is the fix")

	# ---- the picture (a real renderer only) ---------------------------------
	if DisplayServer.get_name() != "headless" and RenderingServer.get_rendering_device() != null:
		var shipped := await _grab(lofi, "shader", "subpass", "grey")
		var fixed := await _grab(lofi, "fixed", "subpass", "grey")
		var nodis := await _grab(lofi, "nodiscard", "subpass", "grey")
		var pass_ := await _grab(lofi, "shader", "pass", "grey")
		check(shipped.get_data() == fixed.get_data(), "its own depth draws it to the byte as the GPU's did")
		check(shipped.get_data() == nodis.get_data(), "and so does it without the cut-out (no alpha in the flamer)")
		var most := 0.0
		for y in shipped.get_height():
			for x in shipped.get_width():
				var a := shipped.get_pixel(x, y)
				var b := pass_.get_pixel(x, y)
				most = maxf(most, maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))))
		check(most <= 0.002, "the tonemap in a pass of its own within a half-float step (%.5f)" % most)
		# (and the flamer is in it: hidden, a good part of the picture changes)
		w3d.visible = false
		var bare := await _grab(lofi, "shader", "subpass", "grey")
		w3d.visible = true
		var gun_px := 0
		for y in shipped.get_height():
			for x in shipped.get_width():
				if shipped.get_pixel(x, y) != bare.get_pixel(x, y):
					gun_px += 1
		check(gun_px > 5000, "the flamer is in the picture (%d texels of it)" % gun_px)
		var mag := await _grab(lofi, "shader", "pass", "magenta")
		var holes := 0
		for y in mag.get_height():
			for x in mag.get_width():
				var c := mag.get_pixel(x, y)
				if c.r > 0.9 and c.g < 0.1 and c.b > 0.9:
					holes += 1
		check(holes == 0, "cleared to magenta, not one texel left undrawn (%d)" % holes)
		mag.save_png("user://gun_depth_magenta.png")
		lofi.gun_diag("shader", "auto", "grey", true)
	else:
		print("  (headless: the pictures are checked under a real renderer)")
	print("gundepth: " + ("OK" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)

func _gun_mats(lofi: Lofi) -> Array:
	var out := []
	for n in lofi.gun.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			for m in [mi.get_surface_override_material(i), mi.mesh.surface_get_material(i), mi.material_override]:
				if m is ShaderMaterial:
					var base: Shader = m.get_meta("mewd_base") if m.has_meta("mewd_base") else m.shader
					if base != null and Lofi.GUN_SHADERS.has(base.resource_path) and not out.has(m):
						out.append(m)
	return out

func _all_shipped(mats: Array) -> bool:
	for m in mats:
		if not Lofi.GUN_SHADERS.has((m as ShaderMaterial).shader.resource_path):
			return false
	return true

func _all_defined(mats: Array, define: String) -> bool:
	for m in mats:
		var s: Shader = (m as ShaderMaterial).shader
		var base: Shader = m.get_meta("mewd_base")
		# (the room has no cut-out to switch off, but carries the define all the same)
		if s.resource_path != "" or not s.code.contains("#define " + define) or s.code.length() < base.code.length():
			return false
	return true

func _grab(lofi: Lofi, depth: String, tone: String, clear: String) -> Image:
	lofi.gun_diag(depth, tone, clear, true)
	for i in 10:
		await RenderingServer.frame_post_draw
	return lofi.gun.get_texture().get_image()
