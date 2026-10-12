extends SceneTree
## Headless check of the terrain kit:
##   godot --headless --path . --script res://tools/terrain/terrain_check.gd
## Builds every PropKit prop a few times (prints triangles / draw calls / collision shapes / build
## time), builds a hell and a heaven TerrainPatch (prints mesh size, collision boxes, build time) and
## checks the walkability queries. Any script error shows up in the output.


func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var all: Array[StringName] = []
	all.append_array(PropKit.HOLY)
	all.append_array(PropKit.HELL)
	all.append_array(SiteProps.NAMES)
	# fresh (uncached) build cost vs cached instancing
	for name in all:
		var f0 := Time.get_ticks_usec()
		PropKit.build_fresh(name, rng).free()
		var fresh_us := Time.get_ticks_usec() - f0
		for i in 30:
			PropKit.build(name, rng).free()  # warm every variant template
		var c0 := Time.get_ticks_usec()
		for i in 20:
			PropKit.build(name, rng).free()
		@warning_ignore("integer_division")
		print("CACHE %-18s fresh_us=%6d cached_us=%5d" % [name, fresh_us, (Time.get_ticks_usec() - c0) / 20])
	for name in all:
		var t0 := Time.get_ticks_usec()
		var tris := 0
		var draws := 0
		var shapes := 0
		for i in 4:
			var n := PropKit.build(name, rng)
			for c in n.get_children():
				if c is MeshInstance3D:
					draws += 1
					tris += _tris((c as MeshInstance3D).mesh)
				if c is StaticBody3D:
					shapes += c.get_child_count()
			n.free()
		@warning_ignore("integer_division")
		print("PROPKIT %-16s tris/4=%6d draws/4=%3d shapes/4=%2d build_us=%d" % [name, tris / 4, draws / 4,
				shapes / 4, (Time.get_ticks_usec() - t0) / 4])
	# Props.build fall-through
	var via_props := Props.build(&"obsidian_spire", rng)
	print("PROPS_FALLTHROUGH ", via_props.get_meta(&"prop", &"?"))
	via_props.free()
	for theme_name in ["hell", "heaven"]:
		var t1 := Time.get_ticks_msec()
		var patch := TerrainPatch.new()
		patch.theme = load("res://data/terrain/%s.tres" % theme_name)
		patch.rng_seed = 77
		patch.build_on_ready = false
		root.add_child(patch)
		patch.build()
		var stats := patch.stats()
		print("TERRAIN %s %s build_ms=%d" % [theme_name, str(stats), Time.get_ticks_msec() - t1])
		print("  walkable(0,0)=%s walkable(far)=%s nearest(far)=%s" % [patch.is_walkable(Vector3.ZERO),
				patch.is_walkable(Vector3(patch.size.x * 0.49, 0, 0)), patch.nearest_walkable(Vector3(patch.size.x * 0.49, 0, 0))])
		patch.free()
	quit()


func _tris(m: Mesh) -> int:
	var t := 0
	if not m is ArrayMesh:
		return 0  # primitive meshes (flame quads) don't count
	for s in m.get_surface_count():
		var il: int = m.surface_get_array_index_len(s)
		t += (il if il > 0 else m.surface_get_array_len(s)) / 3
	return t
