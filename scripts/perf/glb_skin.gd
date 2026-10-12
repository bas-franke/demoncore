class_name GlbSkin
## Perf round 3 (docs/team/performance.md): turns a Blender node-rig model (one MeshInstance3D and
## one animated Node3D per joint, 10-40 of them) into ONE skinned MeshInstance3D on a Skeleton3D,
## with the clips retargeted from node tracks to bone tracks, so the AnimationPlayer poses the
## skeleton natively. A seraph sentinel drops from ~60 nodes / 24 render instances to ~4 nodes /
## 1 instance: far less culling, transform propagation and physics-interpolation work per enemy.
##
## Applied by GlbModel.setup() to the model files listed in TYPES (the common horde enemies). The
## converted mesh, Skin and AnimationLibrary are built once per (file, flashable) and shared.
##
## What changes for code using the model:
##   - joints are bones now: GlbModel.joint(name) returns a BoneAttachment3D that follows the bone
##     (EnemyModel.glb_node() uses it), so `global_position` of a joint still works;
##   - scene_root has no joint children; find_child(name) on it finds nothing;
##   - CharacterMotion finds no joints (it is only attached to models of size >= 1.5 anyway).
## Opt a model out by removing it from TYPES.

## Model file stems converted (res://assets/models/enemies/<stem>.glb).
const TYPES := ["seraph_sentinel", "choir_wisp", "dawn_lancer", "ophanim", "penitent_statue",
		"thurible_priest"]
const SKELETON := &"Skeleton3D"

## Master switch (A/B: --bench-exp=noglbskin).
static var enabled := true
static var _cache := {}  # "path|flashable" -> Data
static var _warned := {}


class Data:
	var names := PackedStringArray()
	var parents := PackedInt32Array()
	var rests: Array[Transform3D] = []
	var mesh: ArrayMesh
	var mats: Array[Material] = []
	var skin: Skin
	var library: AnimationLibrary


static func wants(path: String) -> bool:
	return enabled and TYPES.has(path.get_file().get_basename())


## Converts `glb` in place (its scene_root and anim_player must be set up). Returns true on success.
static func convert(glb: GlbModel, path: String, flashable: bool) -> bool:
	var key := "%s|%d" % [path, int(flashable)]
	var data: Data = _cache.get(key)
	if data == null:
		data = _build(glb.scene_root, glb.anim_player)
		if data == null:
			return false
		_cache[key] = data
	var root := glb.scene_root
	for c in root.get_children():
		if c != glb.anim_player:
			root.remove_child(c)
			c.queue_free()
	var sk := Skeleton3D.new()
	sk.name = SKELETON
	for i in data.names.size():
		sk.add_bone(data.names[i])
	for i in data.names.size():
		sk.set_bone_parent(i, data.parents[i])
		sk.set_bone_rest(i, data.rests[i])
		sk.set_bone_pose(i, data.rests[i])
	root.add_child(sk)
	var mi := MeshInstance3D.new()
	mi.name = &"Body"
	mi.mesh = data.mesh
	mi.skin = data.skin
	mi.skeleton = NodePath("..")
	for i in data.mats.size():
		mi.set_surface_override_material(i, data.mats[i])
	sk.add_child(mi)
	var ap := glb.anim_player
	for lib in ap.get_animation_library_list():
		ap.remove_animation_library(lib)
	ap.add_animation_library(&"", data.library)
	return true


## BoneAttachment3D following bone `bone_name` of a converted model (created on first request).
static func attachment(glb: GlbModel, bone_name: String) -> Node3D:
	var sk := glb.scene_root.get_node_or_null(NodePath(String(SKELETON))) as Skeleton3D
	if sk == null:
		return null
	var existing := sk.get_node_or_null(NodePath("Joint_" + bone_name)) as Node3D
	if existing:
		return existing
	var idx := sk.find_bone(_bone_name(bone_name))
	if idx < 0:
		return null
	var ba := BoneAttachment3D.new()
	ba.name = "Joint_" + bone_name
	ba.bone_name = sk.get_bone_name(idx)
	sk.add_child(ba)
	return ba


static func clear_cache() -> void:
	_cache.clear()


static func _bone_name(n: String) -> String:
	return n.replace(":", "_").replace("/", "_")


static func _build(root: Node3D, ap: AnimationPlayer) -> Data:
	var d := Data.new()
	var index := {}  # Node -> bone index
	var to_root := {}  # Node -> Transform3D (rest, relative to root)
	var stack: Array = []
	for c in root.get_children():
		stack.append([c, -1, Transform3D.IDENTITY])
	var meshes: Array = []  # [MeshInstance3D, bone]
	while not stack.is_empty():
		var item: Array = stack.pop_front()
		var n := item[0] as Node3D
		if n == null:
			continue
		var bi := d.names.size()
		var nm := _bone_name(String(n.name))
		if d.names.has(nm):
			nm = "%s_%d" % [nm, bi]
		d.names.append(nm)
		d.parents.append(item[1])
		d.rests.append(n.transform)
		index[n] = bi
		var g: Transform3D = (item[2] as Transform3D) * n.transform
		to_root[n] = g
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			meshes.append([n, bi])
		for c in n.get_children():
			stack.append([c, bi, g])
	if meshes.is_empty():
		return null
	# Skin: bind = inverse of each bone's rest relative to the root (vertices go to root space).
	d.skin = Skin.new()
	var bone_nodes := index.keys()
	for n in bone_nodes:
		d.skin.add_bind(int(index[n]), (to_root[n] as Transform3D).affine_inverse())
	# Mesh: one surface per material.
	var groups := {}
	var order: Array[Material] = []
	for m in meshes:
		var mi := m[0] as MeshInstance3D
		var bone: int = m[1]
		var xf: Transform3D = to_root[mi]
		var nb := xf.basis.inverse().transposed()
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_surface_override_material(s)
			if mat == null:
				mat = mi.get_active_material(s)
			var a := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			if verts.is_empty():
				continue
			if not groups.has(mat):
				groups[mat] = [PackedVector3Array(), PackedVector3Array(), PackedFloat32Array(),
						PackedVector2Array(), PackedInt32Array(), PackedFloat32Array(), PackedInt32Array()]
				order.append(mat)
			var g: Array = groups[mat]
			var base: int = (g[0] as PackedVector3Array).size()
			var nrm: Variant = a[Mesh.ARRAY_NORMAL]
			var tangent: Variant = a[Mesh.ARRAY_TANGENT]
			var uv: Variant = a[Mesh.ARRAY_TEX_UV]
			for i in verts.size():
				g[0].append(xf * verts[i])
				g[1].append((nb * (nrm as PackedVector3Array)[i]).normalized() if nrm != null else Vector3.UP)
				if tangent != null and (tangent as PackedFloat32Array).size() >= verts.size() * 4:
					var tf := tangent as PackedFloat32Array
					var t3 := (xf.basis * Vector3(tf[i * 4], tf[i * 4 + 1], tf[i * 4 + 2])).normalized()
					g[2].append_array([t3.x, t3.y, t3.z, tf[i * 4 + 3]])
				else:
					g[2].append_array([1.0, 0.0, 0.0, 1.0])
				g[3].append((uv as PackedVector2Array)[i] if uv != null else Vector2.ZERO)
				g[4].append_array([bone, 0, 0, 0])
				g[5].append_array([1.0, 0.0, 0.0, 0.0])
			var idx: Variant = a[Mesh.ARRAY_INDEX]
			if idx != null and (idx as PackedInt32Array).size() > 0:
				for v in (idx as PackedInt32Array):
					g[6].append(base + v)
			else:
				for v in verts.size():
					g[6].append(base + v)
	d.mesh = ArrayMesh.new()
	for mat in order:
		var g: Array = groups[mat]
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = g[0]
		arr[Mesh.ARRAY_NORMAL] = g[1]
		arr[Mesh.ARRAY_TANGENT] = g[2]
		arr[Mesh.ARRAY_TEX_UV] = g[3]
		arr[Mesh.ARRAY_BONES] = g[4]
		arr[Mesh.ARRAY_WEIGHTS] = g[5]
		arr[Mesh.ARRAY_INDEX] = g[6]
		d.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		d.mats.append(mat)
	# Clips: node tracks -> bone tracks of "Skeleton3D:<bone>".
	d.library = AnimationLibrary.new()
	if ap:
		var anim_root := ap.get_node_or_null(ap.root_node)
		for an in ap.get_animation_list():
			var src := ap.get_animation(an)
			var dst := src.duplicate(true) as Animation
			for t in range(dst.get_track_count() - 1, -1, -1):
				var tp := dst.track_get_path(t)
				var node_path := NodePath(String(tp).get_slice(":", 0))
				var target: Node = anim_root.get_node_or_null(node_path) if anim_root else null
				var tt := dst.track_get_type(t)
				if target and index.has(target) and (tt == Animation.TYPE_POSITION_3D
						or tt == Animation.TYPE_ROTATION_3D or tt == Animation.TYPE_SCALE_3D):
					dst.track_set_path(t, NodePath("%s:%s" % [SKELETON, d.names[int(index[target])]]))
				elif target and index.has(target):
					# Value / method tracks on joints (visibility, ...) can't follow a bone: dropped.
					if not _warned.has(String(an)):
						_warned[String(an)] = true
						print_verbose("GlbSkin: dropped non-transform track %s in %s" % [tp, an])
					dst.remove_track(t)
			d.library.add_animation(an, dst)
	return d
