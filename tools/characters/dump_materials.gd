extends SceneTree
## Dumps the converted materials and node tree of a Blender model (characters-polish tooling):
##   godot --headless --path . --script res://tools/characters/dump_materials.gd -- res://assets/models/demons/vharok.glb [--tree]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var tree := args.has("--tree")
	for p in args:
		if p.begins_with("res://"):
			_dump(p, tree)
	quit()


func _dump(path: String, tree: bool) -> void:
	var m := GlbModel.create(path)
	print("== ", path)
	var stack: Array[Node] = [m.scene_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if tree and n is Node3D:
			print("  NODE ", m.scene_root.get_path_to(n), " ", n.get_class())
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				var mat := mi.get_surface_override_material(s) as ShaderMaterial
				var src := mi.mesh.surface_get_material(s)
				if mat:
					print("  MAT %s/%d src=%s tex=%s albedo=%s emit=%s e=%s" % [mi.name, s,
						src.resource_name if src else "-", mat.get_shader_parameter(&"use_textures"),
						mat.get_shader_parameter(&"albedo"), mat.get_shader_parameter(&"emission"),
						mat.get_shader_parameter(&"emission_energy")])
		if n is Skeleton3D:
			var sk := n as Skeleton3D
			for b in sk.get_bone_count():
				print("  BONE ", sk.get_bone_name(b))
		for c in n.get_children():
			stack.append(c)
	m.free()
