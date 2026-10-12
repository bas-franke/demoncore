extends SceneTree
## Headless check of the Blender world props as Props uses them:
##   godot --headless --path . --script res://tools/_props_check.gd
## Prints variants / triangles / sockets per prop and the cost of building props + merging a chunk.


func _init() -> void:
	# QA: run after the autoloads exist (decor.gd uses Game); from _init it failed to compile and
	# the script never reached quit(), hanging the suite.
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var names: Array[StringName] = []
	names.append_array(Props.SMALL)
	names.append_array(Props.BIG)
	names.append_array(Props.LANDMARKS)
	var t0 := Time.get_ticks_msec()
	for n in names:
		var vs := Props.variants(n)
		var line := "PROP %s variants=%d" % [n, vs.size()]
		for v: Dictionary in vs:
			var prop_tris := 0
			for p: Dictionary in v["parts"]:
				var m: Mesh = p["mesh"]
				for s in m.get_surface_count():
					var il: int = m.surface_get_array_index_len(s)  # ArrayMesh-only method, so type it explicitly
					prop_tris += (il if il > 0 else m.surface_get_array_len(s)) / 3
			line += " | tris=%d parts=%d sockets=%s" % [prop_tris, v["parts"].size(), str(v["sockets"].keys())]
		print(line)
	print("LOAD_MS ", Time.get_ticks_msec() - t0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var t1 := Time.get_ticks_usec()
	var holder := Node3D.new()
	for n in names:
		for i in 4:
			holder.add_child(Props.build(n, rng))
	@warning_ignore("integer_division")
	print("BUILD_US_PER_PROP ", (Time.get_ticks_usec() - t1) / (names.size() * 4))
	holder.free()
	# decor chunk streaming cost (build + merge), 5x5 ring
	var decor_script := load("res://scenes/world/decor.gd") as GDScript
	if decor_script == null or not decor_script.can_instantiate():
		print("FAIL decor.gd does not compile")  # QA: never hang on a broken dependency
		quit(1)
		return
	var decor = decor_script.new()
	decor.run_seed = 12345
	decor._setup_noise()
	var worst := 0
	var total := 0
	var tris := 0
	var draws := 0
	for z in range(-2, 3):
		for x in range(-2, 3):
			var c0 := Time.get_ticks_usec()
			decor._build(Vector2i(x + 3, z - 4))
			var dt := Time.get_ticks_usec() - c0
			worst = maxi(worst, dt)
			total += dt
	for k in decor._chunks:
		for c in (decor._chunks[k] as Node).get_children():
			if c is MeshInstance3D:
				draws += 1
				var m := (c as MeshInstance3D).mesh
				for s in m.get_surface_count():
					var il: int = m.surface_get_array_index_len(s)  # ArrayMesh-only method, so type it explicitly
					tris += (il if il > 0 else m.surface_get_array_len(s)) / 3
	print("CHUNKS 25 avg_ms=%.1f worst_ms=%.1f mesh_instances=%d tris=%d" % [total / 25000.0, worst / 1000.0, draws, tris])
	decor.free()
	quit()
