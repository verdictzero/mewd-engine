## THE ISLAND, built headless: how long, and what the ground says.
##   godot --headless --script res://godot/tests/island_probe.gd
extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var scene: Node3D = (load("res://godot/island/scenes/island_0.tscn") as PackedScene).instantiate()
	var cam := Camera3D.new()
	cam.position = Vector3(0, 120, 0)
	cam.far = 12000.0
	scene.add_child(cam)
	root.add_child(scene)
	cam.make_current()
	var world: Node = scene.get_node("IslandWorld")
	var veg: Node = scene.get_node("VegScatter")
	var done := [false]
	world.pregen_finished.connect(func(): done[0] = true)
	var last := 0
	while true:
		await process_frame
		if done[0] and bool(veg.get("_prescattered")):
			break
		if Time.get_ticks_msec() - last > 10000:
			last = Time.get_ticks_msec()
			print("  ... %.0f s" % ((last - t0) / 1000.0))
		if Time.get_ticks_msec() - t0 > 900000:
			print("FAIL: not built in 15 minutes")
			quit(1)
			return
	print("island built in %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	for p in [Vector3(0, 0, 0), Vector3(300, 0, 200), Vector3(-800, 0, 400), Vector3(1200, 0, 0), Vector3(2000, 0, 0)]:
		print("  at %s: land %s, height %.1f" % [p, world.is_land(p), world.height_at(p, -999.0)])
	quit(0)
