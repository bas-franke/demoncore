extends SceneTree
## Headless sanity check for Blender models:
##   godot --headless --path . --script res://tools/check_model.gd -- res://assets/models/enemies/x.glb [...]
## Prints mesh/material/animation info for each model, or every .glb under assets/models if none given.


func _init() -> void:
	var paths: Array[String] = []
	for a in OS.get_cmdline_user_args():
		paths.append(a)
	if paths.is_empty():
		_collect("res://assets/models", paths)
	for p in paths:
		_check(p)
	quit()


func _collect(dir: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".glb"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		_collect(dir.path_join(sub), out)


func _check(path: String) -> void:
	var m := GlbModel.create(path)
	if m.scene_root == null:
		print("MODEL_FAIL ", path)
		return
	var meshes := 0
	var tris := 0
	var stack: Array[Node] = [m]
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			var mi := n as MeshInstance3D
			meshes += 1
			for s in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(s)
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				@warning_ignore("integer_division")
				tris += idx.size() / 3
			var aabb := mi.mesh.get_aabb()
			var xf := _global_xf(mi)
			for k in 8:
				var pt := xf * aabb.get_endpoint(k)
				lo = lo.min(pt)
				hi = hi.max(pt)
		for c in n.get_children():
			stack.append(c)
	var anims := m.anim_player.get_animation_list() if m.anim_player else PackedStringArray()
	print("MODEL_OK %s meshes=%d tris=%d size=%s anims=%s" % [path, meshes, tris, str(hi - lo), str(anims)])
	m.free()


func _global_xf(n: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p is Node3D:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf
