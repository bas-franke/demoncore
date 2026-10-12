class_name SkinBake
## Perf round 2 (docs/team/performance.md): collapses a code-built model's many rigid parts into at
## most two skinned MeshInstance3Ds (lit parts that cast shadows + unshaded glows that don't), one
## rigid bone per animated pivot. A cherub goes from ~13 render instances to 2 (+ kept meshes).
##
## The pivots stay in the scene tree and keep being posed by the model's code exactly as before;
## Rig.update() copies their transforms into the Skeleton3D once per animate() tick. Meshes the
## model changes at runtime (ProcModel.keep()) are left alone, as is anything that is not a plain
## MeshInstance3D. The baked ArrayMeshes and Skin are cached per model type, so every instance of a
## type shares them (identical mesh + material = cheap draws).
##
##   var rig := SkinBake.bake(self, bone_pivots, _keep, "cherub|")
##   ...each animate tick:  rig.update()
##
## Limits: a part's pose follows its *bone* (nearest registered pivot); visibility toggles on a
## pivot no longer hide its parts; bones update at the physics tick rate (30 Hz) instead of being
## interpolated per frame.

static var _cache := {}  # key -> Array [lit ArrayMesh|null, glow ArrayMesh|null, Skin, PackedStringArray bone paths]


## Live link between a model's pivots and its Skeleton3D.
class Rig:
	var skeleton: Skeleton3D
	var nodes: Array[Node3D] = []  # bone i follows nodes[i]; nodes[0] is the model root (identity)

	## Copies the pivots' current transforms (relative to the skeleton's parent) into the bones.
	func update() -> void:
		var stop := skeleton.get_parent()
		for i in range(1, nodes.size()):
			var n := nodes[i]
			var xf := n.transform
			var p := n.get_parent()
			while p != stop and p != null:
				xf = (p as Node3D).transform * xf
				p = p.get_parent()
			skeleton.set_bone_pose(i, xf)


## Bakes `root`'s static meshes onto a skeleton driven by `bones` (animated pivots under root).
## `keep` = meshes (as Dictionary keys) to leave untouched. `key` must identify the model type's
## geometry (same key = identical build). Returns null when there is nothing worth baking.
static func bake(root: Node3D, bones: Array[Node3D], keep: Dictionary, key: String) -> Rig:
	var bone_nodes: Array[Node3D] = [root]
	var bone_of := {}  # Node3D -> bone index
	bone_of[root] = 0
	for b in bones:
		if is_instance_valid(b) and not bone_of.has(b) and root.is_ancestor_of(b):
			bone_of[b] = bone_nodes.size()
			bone_nodes.append(b)
	var parts: Array = []  # [MeshInstance3D, bone index, Transform3D mesh -> root]
	_collect(root, root, bone_of, keep, parts)
	if parts.size() < 3:
		return null
	var entry: Array = _cache.get(key, [])
	if entry.is_empty():
		entry = _build(root, bone_nodes, parts)
		_cache[key] = entry
	var rig := Rig.new()
	rig.nodes = bone_nodes
	var sk := Skeleton3D.new()
	sk.name = &"BakedSkeleton"
	for i in bone_nodes.size():
		sk.add_bone("b%d" % i)
	root.add_child(sk)
	rig.skeleton = sk
	for k in 2:
		var mesh: ArrayMesh = entry[k]
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = &"BakedLit" if k == 0 else &"BakedGlow"
		mi.mesh = mesh
		# Same materials as surface *overrides*: Art.flash / ArtStyle detect flashable meshes there.
		for si in mesh.get_surface_count():
			mi.set_surface_override_material(si, mesh.surface_get_material(si))
		mi.skin = entry[2]
		mi.skeleton = NodePath("..")
		if k == 1:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sk.add_child(mi)
	# Drop the originals now (detached first, so they never render even for a frame).
	for p in parts:
		var mi := p[0] as MeshInstance3D
		mi.get_parent().remove_child(mi)
		mi.queue_free()
	rig.update()
	return rig


## Drops the cached meshes (tools / quit).
static func clear_cache() -> void:
	_cache.clear()


static func _collect(n: Node, root: Node3D, bone_of: Dictionary, keep: Dictionary, out: Array) -> void:
	for c in n.get_children():
		if keep.has(c):
			continue
		var mi := c as MeshInstance3D
		if mi:
			if mi.mesh and mi.visible and mi.skin == null and mi.get_child_count() == 0 \
					and mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
				var bnode := _bone_node(mi, root, bone_of)
				out.append([mi, int(bone_of[bnode]), _rel(mi, bnode)])
			continue
		if c is Node3D and not (c is GeometryInstance3D) and not (c is Light3D):
			_collect(c, root, bone_of, keep, out)


static func _bone_node(n: Node, root: Node3D, bone_of: Dictionary) -> Node3D:
	var p := n.get_parent()
	while p != null and p != root and not bone_of.has(p):
		p = p.get_parent()
	return root if p == null else p as Node3D


## Transform of `n` relative to `ancestor`.
static func _rel(n: Node3D, ancestor: Node) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p != ancestor and p != null:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


## Builds the shared skinned meshes + skin from one instance's parts.
static func _build(root: Node3D, bone_nodes: Array[Node3D], parts: Array) -> Array:
	# Bind poses: bone rest (relative to root) at bake time; vertices go into root space.
	var skin := Skin.new()
	for i in bone_nodes.size():
		var rest := Transform3D.IDENTITY if i == 0 else _rel(bone_nodes[i], root)
		skin.add_bind(i, rest.affine_inverse())
	# material -> [verts, normals, uvs, bones, weights, indices], split lit / glow.
	var groups := [{}, {}]
	var order := [[], []]
	for p in parts:
		var mi := p[0] as MeshInstance3D
		var bone: int = p[1]
		var to_bone: Transform3D = p[2]
		var bone_rest := Transform3D.IDENTITY if bone == 0 else _rel(bone_nodes[bone], root)
		var to_root := bone_rest * to_bone
		var nbasis := to_root.basis.inverse().transposed()
		var kind := 1 if mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF else 0
		for s in mi.mesh.get_surface_count():
			var mat: Material = mi.material_override
			if mat == null:
				mat = mi.get_active_material(s)
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if verts.is_empty():
				continue
			if not groups[kind].has(mat):
				groups[kind][mat] = [PackedVector3Array(), PackedVector3Array(), PackedVector2Array(),
						PackedInt32Array(), PackedFloat32Array(), PackedInt32Array()]
				order[kind].append(mat)
			var g: Array = groups[kind][mat]
			var base: int = (g[0] as PackedVector3Array).size()
			var nrm: Variant = arrays[Mesh.ARRAY_NORMAL]
			var uv: Variant = arrays[Mesh.ARRAY_TEX_UV]
			for i in verts.size():
				g[0].append(to_root * verts[i])
				g[1].append((nbasis * (nrm as PackedVector3Array)[i]).normalized() if nrm != null else Vector3.UP)
				g[2].append((uv as PackedVector2Array)[i] if uv != null else Vector2.ZERO)
				g[3].append_array([bone, 0, 0, 0])
				g[4].append_array([1.0, 0.0, 0.0, 0.0])
			var idx: Variant = arrays[Mesh.ARRAY_INDEX]
			if idx != null and (idx as PackedInt32Array).size() > 0:
				for v in (idx as PackedInt32Array):
					g[5].append(base + v)
			else:
				for v in verts.size():
					g[5].append(base + v)
	var out := [null, null, skin]
	for kind in 2:
		if order[kind].is_empty():
			continue
		var mesh := ArrayMesh.new()
		for mat: Material in order[kind]:
			var g: Array = groups[kind][mat]
			var a := []
			a.resize(Mesh.ARRAY_MAX)
			a[Mesh.ARRAY_VERTEX] = g[0]
			a[Mesh.ARRAY_NORMAL] = g[1]
			a[Mesh.ARRAY_TEX_UV] = g[2]
			a[Mesh.ARRAY_BONES] = g[3]
			a[Mesh.ARRAY_WEIGHTS] = g[4]
			a[Mesh.ARRAY_INDEX] = g[5]
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
		out[kind] = mesh
	return out
