class_name Scatter
## Placement helpers for props: blue-noise point sets, weighted prop placement with footprints,
## and chunked mesh merging (few draw calls for hundreds of props). Pure functions, deterministic
## for a given RandomNumberGenerator.
##
##   var pts := Scatter.poisson(Rect2(-40, -40, 80, 80), 4.0, rng, 60, func(p): return terrain.is_walkable(Vector3(p.x, 0, p.y)))
##   var nodes := Scatter.place(parent, pts, {&"obsidian_spire": 2.0, &"brimstone_rock": 3.0}, rng)
##   Scatter.merge(parent, 24.0)      # merge static meshes per 24 m tile
##
## Names in tables may be PropKit props (procedural, optional collision) or Props props (Blender
## models, visual only; place() gives them a simple cylinder collider when `collide` is true).


## Bridson Poisson-disc sampling inside `rect` (x, z): points at least `min_dist` apart, at most
## `max_count`. `accept` (optional Callable(Vector2) -> bool) filters candidates (walkability,
## distance to paths, ...).
static func poisson(rect: Rect2, min_dist: float, rng: RandomNumberGenerator, max_count: int = 1000,
		accept := Callable(), tries: int = 20) -> PackedVector2Array:
	var out := PackedVector2Array()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0 or max_count <= 0:
		return out
	var cs := min_dist / sqrt(2.0)
	var gw := int(ceil(rect.size.x / cs))
	var gh := int(ceil(rect.size.y / cs))
	var grid := PackedInt32Array()
	grid.resize(gw * gh)
	grid.fill(-1)
	var active: Array[int] = []
	# seed with a few random accepted points (accept may reject large regions)
	for _i in 60:
		var p := rect.position + Vector2(rng.randf() * rect.size.x, rng.randf() * rect.size.y)
		if accept.is_valid() and not accept.call(p):
			continue
		if _poisson_add(p, rect, cs, gw, gh, grid, out, min_dist):
			active.append(out.size() - 1)
		if active.size() >= 3:
			break
	while not active.is_empty() and out.size() < max_count:
		var ai := rng.randi() % active.size()
		var base := out[active[ai]]
		var found := false
		for _t in tries:
			var a := rng.randf() * TAU
			var r := min_dist * (1.0 + rng.randf())
			var p := base + Vector2(cos(a), sin(a)) * r
			if not rect.has_point(p):
				continue
			if accept.is_valid() and not accept.call(p):
				continue
			if _poisson_add(p, rect, cs, gw, gh, grid, out, min_dist):
				active.append(out.size() - 1)
				found = true
				break
		if not found:
			active.remove_at(ai)
	return out


static func _poisson_add(p: Vector2, rect: Rect2, cs: float, gw: int, gh: int, grid: PackedInt32Array,
		out: PackedVector2Array, min_dist: float) -> bool:
	var gx := clampi(int((p.x - rect.position.x) / cs), 0, gw - 1)
	var gy := clampi(int((p.y - rect.position.y) / cs), 0, gh - 1)
	for y in range(maxi(gy - 2, 0), mini(gy + 3, gh)):
		for x in range(maxi(gx - 2, 0), mini(gx + 3, gw)):
			var idx := grid[y * gw + x]
			if idx >= 0 and out[idx].distance_squared_to(p) < min_dist * min_dist:
				return false
	out.append(p)
	grid[gy * gw + gx] = out.size() - 1
	return true


## Jittered grid (cheaper than Poisson, good for dense filler): one point per `cell`, jittered by
## `jitter` (0..1 of a cell).
static func jittered(rect: Rect2, cell: float, rng: RandomNumberGenerator, jitter: float = 0.8,
		accept := Callable()) -> PackedVector2Array:
	var out := PackedVector2Array()
	var y := rect.position.y + cell * 0.5
	while y < rect.end.y:
		var x := rect.position.x + cell * 0.5
		while x < rect.end.x:
			var p := Vector2(x, y) + Vector2(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5)) * cell * jitter
			if not accept.is_valid() or accept.call(p):
				out.append(p)
			x += cell
		y += cell
	return out


## Builds one prop per point from the weighted `table` ({name: weight}) under `parent`.
## `height` (optional Callable(Vector2) -> float) sets each prop's y. Returns the created nodes.
static func place(parent: Node3D, points: PackedVector2Array, table: Dictionary, rng: RandomNumberGenerator,
		collide: bool = true, height := Callable(), scale_range := Vector2(1.0, 1.0)) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if table.is_empty():
		return out
	for p in points:
		var kind := Props.pick(table, rng)
		var n := build_any(kind, rng, collide)
		var y := float(height.call(p)) if height.is_valid() else 0.0
		n.position = Vector3(p.x, y, p.y)
		if scale_range != Vector2.ONE:
			n.scale *= rng.randf_range(scale_range.x, scale_range.y)
		parent.add_child(n)
		out.append(n)
	return out


## A prop by name from either kit. Props (Blender, visual only) get a cylinder collider if asked.
static func build_any(kind: StringName, rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	if PropKit.has(kind):
		return PropKit.build(kind, rng, collide)
	var n := Props.build(kind, rng)
	if collide and not kind in [&"grass_tuft", &"dead_shrub", &"skull", &"candles", &"rubble"]:
		var body := StaticBody3D.new()
		body.name = "Collision"
		body.collision_layer = PropBuilder.WORLD_LAYER
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.7
		cyl.height = 2.0
		cs.shape = cyl
		cs.position.y = 1.0
		body.add_child(cs)
		n.add_child(body)
	return n


## Footprint radius of a prop by name (PropKit table, or a 1 m default).
static func footprint(kind: StringName) -> float:
	return PropKit.footprint(kind) if PropKit.has(kind) else 1.0


## Instances of the same mesh at least this many times per tile become one MultiMesh.
const MULTIMESH_MIN := 3


## Batches every mergeable static MeshInstance3D under `root` (recursively), per `tile`-metre
## square in root space:
##   - meshes shared by >= MULTIMESH_MIN instances (cached PropKit variants, Props models) become
##     one MultiMeshInstance3D per (tile, mesh, material, shadow): no vertex copying at all
##   - the rest are merged into one MeshInstance3D per (tile, material, shadow), like decor.gd
## Meta `keep` and custom-shader materials stay untouched; collision bodies, lights and flames are
## kept where they are. Returns the number of draw nodes created.
static func merge(root: Node3D, tile: float = 24.0) -> int:
	var items: Array = []  # [MeshInstance3D, Transform3D (root space), Vector2i tile]
	_collect(root, Transform3D.IDENTITY, items, tile)
	var by_mesh := {}  # "tile|mesh|mat|shadow" -> Array of item indices
	for i in items.size():
		var mi: MeshInstance3D = items[i][0]
		var t: Vector2i = items[i][2]
		var key := "%d|%d|%d|%d|%d" % [t.x, t.y, mi.mesh.get_instance_id(), mi.material_override.get_instance_id(), mi.cast_shadow]
		if not by_mesh.has(key):
			by_mesh[key] = []
		(by_mesh[key] as Array).append(i)
	var created := 0
	var merged := {}  # "tile|mat|shadow" -> {st, mat, shadow}
	for key: String in by_mesh:
		var idx: Array = by_mesh[key]
		var first: MeshInstance3D = items[idx[0]][0]
		if idx.size() >= MULTIMESH_MIN:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = first.mesh
			mm.instance_count = idx.size()
			for k in idx.size():
				mm.set_instance_transform(k, items[idx[k]][1])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = first.material_override
			mmi.cast_shadow = first.cast_shadow
			mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			_vis(mmi)
			root.add_child(mmi)
			created += 1
		else:
			for i: int in idx:
				var mi: MeshInstance3D = items[i][0]
				var t: Vector2i = items[i][2]
				var mkey := "%d|%d|%d|%d" % [t.x, t.y, mi.material_override.get_instance_id(), mi.cast_shadow]
				if not merged.has(mkey):
					merged[mkey] = {"st": SurfaceTool.new(), "mat": mi.material_override, "shadow": mi.cast_shadow}
				(merged[mkey]["st"] as SurfaceTool).append_from(mi.mesh, 0, items[i][1])
	for item: Array in items:
		var mi: MeshInstance3D = item[0]
		mi.get_parent().remove_child(mi)
		mi.free()
	for mkey: String in merged:
		var g: Dictionary = merged[mkey]
		var out := MeshInstance3D.new()
		out.mesh = (g["st"] as SurfaceTool).commit()
		out.material_override = g["mat"]
		out.cast_shadow = g["shadow"]
		out.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		_vis(out)
		root.add_child(out)
		created += 1
	return created


static func _vis(g: GeometryInstance3D) -> void:
	# merged tiles are up to `tile` wide, so allow for half a tile beyond the prop range
	g.visibility_range_end = PropKit.VIS_RANGE + 16.0
	g.visibility_range_end_margin = PropKit.VIS_FADE


static func _collect(node: Node, xf: Transform3D, items: Array, tile: float) -> void:
	for c in node.get_children():
		if not c is Node3D:
			continue
		var cxf := xf * (c as Node3D).transform
		if c is MeshInstance3D and _mergeable(c as MeshInstance3D):
			items.append([c, cxf, Vector2i(floori(cxf.origin.x / tile), floori(cxf.origin.z / tile))])
		_collect(c, cxf, items, tile)


static func _mergeable(mi: MeshInstance3D) -> bool:
	if mi.has_meta(&"keep") or mi.mesh == null or mi.mesh.get_surface_count() != 1:
		return false
	var m := mi.material_override
	if m is StandardMaterial3D:
		return true
	if m is ShaderMaterial:
		return (m as ShaderMaterial).shader == Art.LIT_STATIC
	return false
