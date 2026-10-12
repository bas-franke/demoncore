class_name TerrainPatch
extends Node3D
## A bounded, walkable terrain arena: heightmap mesh (splat/triplanar terrain shader), cliffs or
## sky-island drop-offs around a flat play area, beaten or paved paths, rivers and pools of lava /
## water / open sky, bridges, rock outcrops, scattered props and collision for all of it.
##
## The game is planar (player and enemies are locked to y = 0), so the walkable area is kept flat
## at y = 0 and everything that is not walkable gets box colliders on layer 1 ("world"). Heights
## are purely visual outside the play area.
##
## Use it from code (maps) or drop the node into a scene with a theme assigned:
##
##   var t := TerrainPatch.new()
##   t.theme = preload("res://data/terrain/hell.tres")
##   t.size = Vector2(120, 120)
##   t.auto_features = false                       # author everything yourself:
##   t.add_open_circle(Vector2.ZERO, 30.0)          #   walkable arena
##   t.add_path(PackedVector2Array([Vector2(0, 0), Vector2(0, -40)]), 3.0)
##   t.add_river(PackedVector2Array([Vector2(-50, 10), Vector2(0, 14), Vector2(50, 6)]), 4.0)
##   t.add_bridge(Vector2(0, 8), Vector2(0, 20), 3.0)
##   t.add_block_circle(Vector2(14, -12), 4.0)     #   rock outcrop
##   t.add_cloud_path(PackedVector2Array([Vector2(0, -30), Vector2(0, -50)]), 3.0)  # walkable cloud steps
##   add_child(t)                                   # builds in _ready (build_on_ready)
##
## Sky-island themes (DROP_DOWN) also grow `theme.satellites` small islands joined to the main one
## by walkable cloud stepping paths; themes with a `foliage` table get grass / flowers (TerrainFoliage).
##
## Queries (world space): is_walkable(pos), nearest_walkable(pos), height_at(pos), random_walkable(rng).
## The node is in group &"terrain"; TerrainPatch.find(get_tree()) returns the active one.
## Coordinates passed to add_* are local to the node (x, z) and must be added before build().

signal built

const TERRAIN_SHADER := preload("res://shaders/terrain/terrain.gdshader")
const LAVA_SHADER := preload("res://shaders/terrain/lava.gdshader")
const WATER_SHADER := preload("res://shaders/terrain/water.gdshader")
const CLOUD_SEA_SHADER := preload("res://shaders/terrain/cloud_sea.gdshader")
const NOISE_TEX := preload("res://assets/textures/ground_noise.png")
const STONE_TEX := preload("res://assets/textures/ground_stone.png")
const SOIL_TEX := preload("res://assets/textures/ground_soil.png")

@export var theme: TerrainTheme
## Size of the generated heightmap (x, z) in metres, centred on the node.
@export var size := Vector2(120, 120)
## Grid spacing of the heightmap in metres.
@export var cell := 0.75
## 0 = random.
@export var rng_seed := 0
## Generate an arena, outcrops, paths, a river and bridges procedurally (in addition to anything
## added with add_*). Arena radius = `arena_radius` (0 = 30% of the smaller side).
@export var auto_features := true
@export var arena_radius := 0.0
## Area around the node origin kept free of outcrops, rivers and props (spawn plaza).
@export var clear_radius := 8.0
@export var scatter_props := true
@export var collision := true
@export var build_on_ready := true
## Max lights (braziers, lava glows) on at once, nearest to the player first. 0 = leave lights alone
## (e.g. when a GameMap manages them).
@export var max_lights := 8

# ---- authored features (local x, z)
var _open: Array = []        # [Vector2 center, float radius, float edge_noise]
var _open_rects: Array = []  # [Rect2]
var _blocks: Array = []      # [Vector2 center, float radius, float height_scale]
var _paths: Array = []       # [PackedVector2Array, float width]
var _rivers: Array = []      # [PackedVector2Array, float width]
var _pools: Array = []       # [Vector2 center, float radius]
var _bridges: Array = []     # [Vector2 a, Vector2 b, float width]
var _cloud_paths: Array = [] # [PackedVector2Array, float width, Rect2 bbox]

# ---- generated
var _nx := 0
var _nz := 0
var _h := PackedFloat32Array()
var _walk := PackedFloat32Array()  # signed walkability (m): > 0 inside the play area
var _liq := PackedFloat32Array()   # signed distance into liquid (m): > 0 inside
var _noise := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
var _built := false
var _terrain_mesh: MeshInstance3D
var _props_root: Node3D
var _body: StaticBody3D
var _lights: Array[OmniLight3D] = []
var _light_timer := 0.0
var _time := 0.0
var _stats := {}
var _authored: Array = []

## After build(): rectangles (local x, z) covering everything that is not walkable.
var blocker_rects: Array[Rect2] = []
## After build(): blocking props as (local x, local z, footprint radius).
var prop_blockers: Array[Vector3] = []


func _ready() -> void:
	add_to_group(&"terrain")
	if build_on_ready and not _built:
		build()


## The first TerrainPatch in the tree (or null).
static func find(tree: SceneTree) -> TerrainPatch:
	return tree.get_first_node_in_group(&"terrain") as TerrainPatch if tree else null


# ================================================================ authoring

func add_open_circle(center: Vector2, radius: float, edge_noise: float = 0.15) -> void:
	_open.append([center, radius, edge_noise])


func add_open_rect(rect: Rect2) -> void:
	_open_rects.append(rect)


## Rock outcrop / mesa (not walkable). `height_scale` multiplies theme.edge_height.
func add_block_circle(center: Vector2, radius: float, height_scale: float = 0.7) -> void:
	_blocks.append([center, radius, height_scale])


## Walkable path (also opens the ground it crosses; painted with the path splat).
func add_path(points: PackedVector2Array, width: float = 3.0) -> void:
	_paths.append([points, width, _bbox(points)])


## Liquid channel (impassable unless bridged).
func add_river(points: PackedVector2Array, width: float = 4.0) -> void:
	_rivers.append([points, width, _bbox(points)])


func add_pool(center: Vector2, radius: float) -> void:
	_pools.append([center, radius])


## Walkable bridge deck from a to b over liquid; a prop is built for it.
func add_bridge(a: Vector2, b: Vector2, width: float = 3.0) -> void:
	_bridges.append([a, b, width])


## Walkable corridor of cloud stepping-stones over the void (or anything else): the ground keeps
## its height (drop-offs stay visible), cloud platforms are laid along it at y = 0.
func add_cloud_path(points: PackedVector2Array, width: float = 3.0) -> void:
	_cloud_paths.append([points, width, _bbox(points)])


# ================================================================ queries (world space)

func is_walkable(world_pos: Vector3, margin: float = 0.4) -> bool:
	return walk_distance(world_pos) > margin


## Signed distance (m, approximate) to the edge of the play area: > 0 inside.
func walk_distance(world_pos: Vector3) -> float:
	var l := _local(world_pos)
	return _walk_q(Vector2(l.x, l.z))


## Visual terrain height at a world position (bilinear on the heightmap).
func height_at(world_pos: Vector3) -> float:
	if not _built:
		return 0.0
	var l := _local(world_pos)
	var gx := (l.x + size.x * 0.5) / cell
	var gz := (l.z + size.y * 0.5) / cell
	var x0 := clampi(floori(gx), 0, _nx - 2)
	var z0 := clampi(floori(gz), 0, _nz - 2)
	var fx := clampf(gx - float(x0), 0.0, 1.0)
	var fz := clampf(gz - float(z0), 0.0, 1.0)
	var a := lerpf(_h[z0 * _nx + x0], _h[z0 * _nx + x0 + 1], fx)
	var b := lerpf(_h[(z0 + 1) * _nx + x0], _h[(z0 + 1) * _nx + x0 + 1], fx)
	return _global(Vector3(0, lerpf(a, b, fz), 0)).y


## Closest walkable point (world, y = node y) to `world_pos`; the point itself if already walkable.
func nearest_walkable(world_pos: Vector3, margin: float = 0.8) -> Vector3:
	if is_walkable(world_pos, margin) or not _built:
		return world_pos
	var l := _local(world_pos)
	var p := Vector2(l.x, l.z)
	# expanding rings of samples; the walk field is smooth, so this converges quickly
	var r := cell * 2.0
	while r < maxf(size.x, size.y):
		var best := Vector2.INF
		var steps := maxi(12, int(TAU * r / (cell * 2.0)))
		for i in steps:
			var a := TAU * float(i) / float(steps)
			var q := p + Vector2(cos(a), sin(a)) * r
			if _walk_q(q) > margin and (best == Vector2.INF or q.distance_squared_to(p) < best.distance_squared_to(p)):
				best = q
		if best != Vector2.INF:
			return _global(Vector3(best.x, 0.0, best.y))
		r += cell * 2.0
	return _global(Vector3.ZERO)


## Random walkable world point (y = node y), or the node origin if none found.
func random_walkable(rng: RandomNumberGenerator, margin: float = 1.0) -> Vector3:
	for _i in 64:
		var q := Vector2(rng.randf_range(-0.5, 0.5) * size.x, rng.randf_range(-0.5, 0.5) * size.y)
		if _walk_q(q) > margin:
			return _global(Vector3(q.x, 0.0, q.y))
	return _global(Vector3.ZERO)


func stats() -> Dictionary:
	return _stats


## Radius (m, around the node origin) that contains every open area: the arena and any satellite
## islands. Maps use it for their bounds.
func play_radius() -> float:
	var r := 0.0
	for o: Array in _open:
		r = maxf(r, (o[0] as Vector2).length() + float(o[1]) * (1.0 + float(o[2])))
	for rc: Rect2 in _open_rects:
		for c in [rc.position, rc.end, Vector2(rc.position.x, rc.end.y), Vector2(rc.end.x, rc.position.y)]:
			r = maxf(r, (c as Vector2).length())
	return r


# Transforms that also work before the node enters the tree (tools, map generators).
func _local(p: Vector3) -> Vector3:
	return to_local(p) if is_inside_tree() else transform.affine_inverse() * p


func _global(p: Vector3) -> Vector3:
	return to_global(p) if is_inside_tree() else transform * p


# ================================================================ build

## Generates mesh, liquid, bridges, props and collision. Safe to call again (rebuilds).
func build() -> void:
	if theme == null:
		theme = load("res://data/terrain/hell.tres")
	_clear()
	# Rebuilds start again from what was authored with add_*, not from the previous auto layout.
	if _authored.is_empty():
		_authored = [_open.duplicate(), _open_rects.duplicate(), _blocks.duplicate(), _paths.duplicate(),
				_rivers.duplicate(), _pools.duplicate(), _bridges.duplicate(), _cloud_paths.duplicate()]
	else:
		_open = _authored[0].duplicate(); _open_rects = _authored[1].duplicate()
		_blocks = _authored[2].duplicate(); _paths = _authored[3].duplicate()
		_rivers = _authored[4].duplicate(); _pools = _authored[5].duplicate()
		_bridges = _authored[6].duplicate(); _cloud_paths = _authored[7].duplicate()
	if rng_seed == 0:
		rng_seed = randi()
	_rng.seed = rng_seed
	_noise.seed = rng_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.05
	if auto_features:
		_auto_features()
	if _open.is_empty() and _open_rects.is_empty() and _paths.is_empty():
		add_open_circle(Vector2.ZERO, _arena_r())
	_nx = int(ceil(size.x / cell)) + 1
	_nz = int(ceil(size.y / cell)) + 1
	var t0 := Time.get_ticks_msec()
	_sample_fields()
	_stats["fields_ms"] = Time.get_ticks_msec() - t0
	_build_mesh()
	_build_liquid()
	_build_bridges()
	_build_cloud_paths()
	t0 = Time.get_ticks_msec()
	_build_collision()
	_stats["collision_ms"] = Time.get_ticks_msec() - t0
	if scatter_props:
		t0 = Time.get_ticks_msec()
		_scatter()
		_stats["scatter_ms"] = Time.get_ticks_msec() - t0
	if not theme.foliage.is_empty() and theme.foliage_density > 0.0:
		t0 = Time.get_ticks_msec()
		var f := TerrainFoliage.grow(self, theme.foliage, rng_seed, theme.foliage_density)
		_stats["foliage"] = f.instance_count
		_stats["foliage_ms"] = Time.get_ticks_msec() - t0
	if max_lights > 0:
		_register_lights(self)
	_built = true
	built.emit()


func _clear() -> void:
	for c in get_children():
		c.free()
	_lights.clear()
	_terrain_mesh = null
	_props_root = null
	_body = null
	_built = false
	_walk = PackedFloat32Array()
	_liq = PackedFloat32Array()


func _arena_r() -> float:
	return arena_radius if arena_radius > 0.0 else minf(size.x, size.y) * 0.3


## Procedural layout: noisy round arena, 2-4 spoke paths, a meandering river with bridges where
## paths cross it, a pool or two and some outcrops (never on paths or the spawn plaza).
func _auto_features() -> void:
	var R := _arena_r()
	add_open_circle(Vector2.ZERO, R, 0.18)
	# spokes
	var spokes := _rng.randi_range(2, 4)
	var a0 := _rng.randf() * TAU
	for i in spokes:
		var a := a0 + TAU * float(i) / float(spokes) + _rng.randf_range(-0.3, 0.3)
		var pts := PackedVector2Array()
		var steps := 6
		for k in steps + 1:
			var t := float(k) / float(steps)
			var d := t * R * 1.05
			var wob := sin(t * 5.0 + float(i)) * 2.0 * t
			pts.append(Vector2(cos(a), sin(a)) * d + Vector2(-sin(a), cos(a)) * wob)
		add_path(pts, _rng.randf_range(2.6, 3.6))
	# river across the arena, offset from the centre so the plaza stays dry
	if theme.liquid != TerrainTheme.Liquid.NONE:
		var ra := _rng.randf() * TAU
		var dir := Vector2(cos(ra), sin(ra))
		var nrm := Vector2(-dir.y, dir.x)
		var off := nrm * _rng.randf_range(clear_radius + 6.0, R * 0.6) * (1.0 if _rng.randf() < 0.5 else -1.0)
		var pts := PackedVector2Array()
		var n := 28
		var phase := _rng.randf() * TAU
		for k in n + 1:
			var t := float(k) / float(n) * 2.0 - 1.0
			# two-frequency meander so the channel never reads as a straight ditch
			var bend := sin(t * 4.0 + phase) * 7.0 + sin(t * 9.0 + phase * 1.7) * 2.5
			var p := off + dir * t * maxf(size.x, size.y) * 0.75 + nrm * bend
			pts.append(p)
		var width := _rng.randf_range(3.5, 5.0)
		add_river(pts, width)
		# bridges where paths cross the river
		for path: Array in _paths:
			var hit := _polyline_intersection(path[0], pts)
			if hit != Vector2.INF:
				var along := _polyline_dir(path[0], hit)
				# decks at least 4.5 m wide so enemy nav (obstacles inflated ~0.7 m) never seals them
				add_bridge(hit - along * (width * 0.5 + 1.6), hit + along * (width * 0.5 + 1.6), maxf(float(path[1]) + 0.4, 4.5))
		if _bridges.is_empty():
			# no spoke crosses the river: add one straight across it so the far bank stays reachable
			@warning_ignore("integer_division")
			var near := Geometry2D.get_closest_point_to_segment(Vector2.ZERO, pts[n / 2 - 2], pts[n / 2 + 2])
			var to := near.normalized()
			var cross := PackedVector2Array([Vector2.ZERO, near + to * (width + 10.0)])
			var hit := _polyline_intersection(cross, pts)
			if hit == Vector2.INF:
				hit = near
			add_path(cross, 3.0)
			add_bridge(hit - to * (width * 0.5 + 1.6), hit + to * (width * 0.5 + 1.6), 4.5)
		if _rng.randf() < 0.7:
			var pa := _rng.randf() * TAU
			var pc := Vector2(cos(pa), sin(pa)) * _rng.randf_range(R * 0.45, R * 0.8)
			if _dist_to_paths(pc) > 5.0 and _dist_to_rivers(pc) > 6.0:
				add_pool(pc, _rng.randf_range(2.0, 3.5))
	# outcrops
	for _i in _rng.randi_range(2, 4):
		for _try in 10:
			var a := _rng.randf() * TAU
			var c := Vector2(cos(a), sin(a)) * _rng.randf_range(R * 0.35, R * 0.8)
			var r := _rng.randf_range(2.0, 4.0)
			if c.length() - r < clear_radius + 2.0 or _dist_to_paths(c) < r + 2.5 or _dist_to_rivers(c) < r + 3.0:
				continue
			add_block_circle(c, r, _rng.randf_range(0.4, 0.8))
			break
	if theme.edge == TerrainTheme.Edge.DROP_DOWN and theme.satellites > 0:
		_add_satellites(R)


## Small sky islands around the main one, each joined by a cloud stepping path. They go to the side
## away from the rift (so it never splits them) and only where they fit inside the patch.
func _add_satellites(R: float) -> void:
	var away := Vector2.from_angle(_rng.randf() * TAU)
	if not _rivers.is_empty():
		var near := _closest_on(_rivers[0][0], Vector2.ZERO)
		if near.length() > 0.1:
			away = -near.normalized()
	var n := theme.satellites
	for k in n:
		var dir := away.rotated((float(k) - float(n - 1) * 0.5) * 1.1 + _rng.randf_range(-0.2, 0.2))
		var r_sat := _rng.randf_range(7.0, 10.0)
		var gap := _rng.randf_range(8.0, 12.0)
		var limit := minf(size.x, size.y) * 0.5 - 4.0
		var dist := R + gap + r_sat
		if dist + r_sat > limit:
			dist = limit - r_sat
			gap = dist - r_sat - R
		if gap < 5.0:
			continue
		var c := dir * dist
		if _liquid_at(c) > -r_sat - 2.0:
			continue
		add_open_circle(c, r_sat, 0.12)
		var perp := Vector2(-dir.y, dir.x) * _rng.randf_range(-2.5, 2.5)
		# 4.5 m wide: enemy nav inflates obstacles by ~0.7 m a side and must still get through
		add_cloud_path(PackedVector2Array([dir * (R - 3.0), dir * (R + gap * 0.5) + perp, c - dir * (r_sat - 2.5)]), 4.5)


# ---------------------------------------------------------------- fields

## Signed walk distance at local (x, z): union of open areas and paths, minus blocks, liquids
## (except where bridged) and the patch border.
func _walk_at(q: Vector2, liq: float = NAN, clouds: bool = true) -> float:
	var open := -1e6
	if clouds:
		for c: Array in _cloud_paths:
			open = maxf(open, float(c[1]) * 0.5 - _poly_dist(q, c[0], c[2], 10.0))
	for o: Array in _open:
		var c: Vector2 = o[0]
		var d := q - c
		var r: float = o[1]
		var dl := d.length()
		var amp := float(o[2]) * r
		# far from the rim the wobble can't change the sign: skip the noise (speed)
		if absf(r - dl) > amp + 8.0:
			open = maxf(open, r - dl)
			continue
		# wobbly rim: noise on the direction (sampled on a circle so it wraps)
		var dn := d / maxf(dl, 0.001)
		var wob := _noise.get_noise_2d(dn.x * 40.0 + c.x, dn.y * 40.0 + c.y) * amp
		open = maxf(open, r + wob - dl)
	for rc: Rect2 in _open_rects:
		var dx := maxf(rc.position.x - q.x, q.x - rc.end.x)
		var dz := maxf(rc.position.y - q.y, q.y - rc.end.y)
		open = maxf(open, -maxf(dx, dz))
	for p: Array in _paths:
		open = maxf(open, float(p[1]) * 0.5 - _poly_dist(q, p[0], p[2], 10.0))
	var bridge := -1e6
	for b: Array in _bridges:
		bridge = maxf(bridge, float(b[2]) * 0.5 - _seg_dist_ab(q, b[0], b[1]))
	var s := open
	for b: Array in _blocks:
		s = minf(s, (q - (b[0] as Vector2)).length() - float(b[1]))
	var liquid := _liquid_at(q) if is_nan(liq) else liq
	if liquid > -1e5 and bridge < 0.0:
		s = minf(s, -liquid)
	elif bridge >= 0.0:
		s = maxf(s, bridge)
	# never past the patch border
	var border := minf(size.x * 0.5 - absf(q.x), size.y * 0.5 - absf(q.y)) - 2.0
	return minf(s, border)


## Signed distance into liquid (> 0 inside a river / pool).
func _liquid_at(q: Vector2) -> float:
	var d := -1e6
	for r: Array in _rivers:
		d = maxf(d, float(r[1]) * 0.5 - _poly_dist(q, r[0], r[2], 6.0))
	for p: Array in _pools:
		var c: Vector2 = p[0]
		var dd := q - c
		var wob := _noise.get_noise_2d(c.x + dd.normalized().x * 30.0, c.y + dd.normalized().y * 30.0) * 0.6
		d = maxf(d, float(p[1]) + wob - dd.length())
	return d


func _sample_fields() -> void:
	_h.resize(_nx * _nz)
	_walk.resize(_nx * _nz)
	_liq.resize(_nx * _nz)
	for z in _nz:
		for x in _nx:
			var q := Vector2(-size.x * 0.5 + float(x) * cell, -size.y * 0.5 + float(z) * cell)
			var i := z * _nx + x
			_liq[i] = _liquid_at(q)
			_walk[i] = _walk_at(q, _liq[i])
			# cloud steps are walkable but the ground under them keeps falling away
			var wd := _walk[i] if _cloud_paths.is_empty() else _walk_at(q, _liq[i], false)
			_h[i] = _height(q, wd, _liq[i])


## Bilinear lookup in a baked grid field (fast; used after build for queries, collision, scatter).
func _grid_sample(field: PackedFloat32Array, q: Vector2) -> float:
	var gx := (q.x + size.x * 0.5) / cell
	var gz := (q.y + size.y * 0.5) / cell
	if gx < 0.0 or gz < 0.0 or gx > float(_nx - 1) or gz > float(_nz - 1):
		return -1e3
	var x0 := mini(floori(gx), _nx - 2)
	var z0 := mini(floori(gz), _nz - 2)
	var fx := gx - float(x0)
	var fz := gz - float(z0)
	var a := lerpf(field[z0 * _nx + x0], field[z0 * _nx + x0 + 1], fx)
	var b := lerpf(field[(z0 + 1) * _nx + x0], field[(z0 + 1) * _nx + x0 + 1], fx)
	return lerpf(a, b, fz)


## 0..1 how well plants grow at local q (TerrainFoliage): open ground only, off paths, liquids,
## cloud steps, props and the spawn plaza; thinner toward the arena edge.
func growth_at(q: Vector2) -> float:
	var w := _walk_q(q)
	if w < 0.7 or _liq_q(q) > -1.0 or q.length() < clear_radius * 0.5:
		return 0.0
	for p: Array in _paths:
		if _poly_dist(q, p[0], p[2], 4.0) < float(p[1]) * 0.5 + 0.2:
			return 0.0
	for c: Array in _cloud_paths:
		if _poly_dist(q, c[0], c[2], 4.0) < float(c[1]) * 0.5 + 1.5:
			return 0.0
	for b in prop_blockers:
		if Vector2(b.x, b.y).distance_to(q) < b.z * 0.8:
			return 0.0
	return smoothstep(0.7, 2.5, w)


## Visual terrain height at local q (bilinear on the heightmap; 0 before build).
func height_local(q: Vector2) -> float:
	return _grid_sample(_h, q) if not _h.is_empty() else 0.0


## Walk distance at local q: baked grid after build, analytic before.
func _walk_q(q: Vector2) -> float:
	return _grid_sample(_walk, q) if not _walk.is_empty() else _walk_at(q)


func _liq_q(q: Vector2) -> float:
	return _grid_sample(_liq, q) if not _liq.is_empty() else _liquid_at(q)


func _terrace(t: float, steps: int) -> float:
	if steps <= 0:
		return t
	var s := t * float(steps)
	var f := s - floorf(s)
	# flat treads with steep risers
	return (floorf(s) + smoothstep(0.35, 1.0, f)) / float(steps)


## Height of the cloud sea below sky islands (DROP_DOWN themes / CLOUD liquid).
func _cloud_y() -> float:
	return -theme.edge_height * 0.7


## Visual height at local q given its walk distance w and liquid distance liq. Cliff patches rise
## to a flat rim at the border (where the far skirt continues), whatever is inside.
func _height(q: Vector2, w: float, liq: float) -> float:
	var h := _height_inner(q, w, liq)
	if theme.edge != TerrainTheme.Edge.CLIFF_UP:
		return h
	var border := minf(size.x * 0.5 - absf(q.x), size.y * 0.5 - absf(q.y))
	return lerpf(theme.edge_height * 1.15, h, smoothstep(0.0, 6.0, border))


func _height_inner(q: Vector2, w: float, liq: float) -> float:
	var n := _noise.get_noise_2d(q.x, q.y)
	var n2 := _noise.get_noise_2d(q.x * 3.1 + 100.0, q.y * 3.1)
	var h := (n * 0.6 + n2 * 0.4) * theme.ground_bump
	var dry := _dry_height(q, w, h)
	if liq <= -1.2:
		return dry
	# liquid channels carve through whatever is there (arena floor, cliffs, island rim): banks slope
	# from the ground down below the liquid surface
	var depth := theme.liquid_level - 0.8
	if theme.liquid == TerrainTheme.Liquid.CLOUD or theme.edge == TerrainTheme.Edge.DROP_DOWN:
		depth = -theme.edge_height * 1.5  # sky islands: rifts open onto whatever lies far below
	var wet := lerpf(h, depth, smoothstep(-1.2, 1.0, liq))
	for b: Array in _bridges:
		if float(b[2]) * 0.5 + 0.5 - _seg_dist_ab(q, b[0], b[1]) > 0.0:
			wet = minf(wet, theme.liquid_level - 0.2)  # keep the gap under a bridge
	return minf(dry, wet)


## Height ignoring liquids: ground bump `h` inside the play area, cliffs / outcrops / island
## underside outside it.
func _dry_height(q: Vector2, w: float, h: float) -> float:
	if w >= 0.0:
		return h
	# outside the play area: which feature closes it off?
	var block_d := 1e6
	var block_hs := 0.7
	for b: Array in _blocks:
		var bd := (q - (b[0] as Vector2)).length() - float(b[1])
		if bd < block_d:
			block_d = bd
			block_hs = float(b[2])
	var t := clampf(-w / 4.5, 0.0, 1.0)
	var rough := _noise.get_noise_2d(q.x * 0.5 + 50.0, q.y * 0.5) * 0.18
	if block_d < 0.0:
		# outcrop / mesa: terraced bump
		# steep walls within ~1.2 m of the rim, then a flat-topped mesa
		var bt := clampf(-block_d / 1.2, 0.0, 1.0)
		return h + theme.edge_height * block_hs * _terrace(clampf(bt + rough, 0.0, 1.0), maxi(theme.terraces - 1, 1))
	if theme.edge == TerrainTheme.Edge.DROP_DOWN:
		# sky island: a lip, then the rock underside falls away
		# (then keeps falling well below the cloud sea, so nothing but clouds is seen beyond the rim)
		var dt := clampf(-w / 3.0, 0.0, 1.0)
		return h - theme.edge_height * ((dt * dt) * (1.0 + rough) + 2.0 * clampf((-w - 3.0) / 3.0, 0.0, 1.0))
	var hh := theme.edge_height * _terrace(clampf(t + rough, 0.0, 1.0), theme.terraces)
	# taller, lumpier further out
	hh *= 1.0 + 0.35 * clampf((-w - 4.5) / 12.0, 0.0, 1.0) * (0.5 + _noise.get_noise_2d(q.x * 0.3, q.y * 0.3 + 70.0))
	return h + hh


# ---------------------------------------------------------------- mesh

func _build_mesh() -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	verts.resize(_nx * _nz)
	norms.resize(_nx * _nz)
	cols.resize(_nx * _nz)
	uvs.resize(_nx * _nz)
	var x0 := -size.x * 0.5
	var z0 := -size.y * 0.5
	for z in _nz:
		for x in _nx:
			var i := z * _nx + x
			var q := Vector2(x0 + float(x) * cell, z0 + float(z) * cell)
			verts[i] = Vector3(q.x, _h[i], q.y)
			var hl := _h[z * _nx + maxi(x - 1, 0)]
			var hr := _h[z * _nx + mini(x + 1, _nx - 1)]
			var hd := _h[maxi(z - 1, 0) * _nx + x]
			var hu := _h[mini(z + 1, _nz - 1) * _nx + x]
			norms[i] = Vector3(hl - hr, 2.0 * cell, hd - hu).normalized()
			# convexity (height above the neighbours' mean): rims > 0, hollows < 0 (shader edge wear)
			uvs[i] = Vector2(_h[i] - (hl + hr + hd + hu) * 0.25, 0.0)
			var path := 0.0
			for p: Array in _paths:
				path = maxf(path, 1.0 - smoothstep(float(p[1]) * 0.3, float(p[1]) * 0.55, _poly_dist(q, p[0], p[2], float(p[1]))))
			var liq := _liq[i]
			var shore := 1.0 - smoothstep(-3.0, 0.3, -liq) if liq > -3.0 else 0.0
			var accent := clampf(0.5 + _noise.get_noise_2d(q.x * 0.4 + 300.0, q.y * 0.4) + shore * 0.5, 0.0, 1.0)
			var walk := smoothstep(-0.5, 0.5, _walk[i])
			cols[i] = Color(path * walk, accent, shore, walk)
	for z in _nz - 1:
		for x in _nx - 1:
			var a := z * _nx + x
			var b := a + 1
			var c := a + _nx
			var d := c + 1
			# clockwise seen from above (Godot front faces). Split each quad along the diagonal with the
			# smaller height change, so cliff rims follow the terrain instead of stair-stepping.
			if absf(_h[a] - _h[d]) <= absf(_h[b] - _h[c]):
				idx.append_array([a, b, d, a, d, c])
			else:
				idx.append_array([a, b, c, b, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_terrain_mesh = MeshInstance3D.new()
	_terrain_mesh.name = "TerrainMesh"
	_terrain_mesh.mesh = am
	_terrain_mesh.material_override = _terrain_material()
	_terrain_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_terrain_mesh)
	_stats["verts"] = verts.size()
	@warning_ignore("integer_division")
	_stats["tris"] = idx.size() / 3
	# far skirt so the camera never sees past the patch: a big ring at the border height
	if theme.edge == TerrainTheme.Edge.CLIFF_UP:
		var skirt := MeshInstance3D.new()
		skirt.name = "FarSkirt"
		skirt.mesh = _ring_mesh(size * 0.5 - Vector2(cell, cell), size * 0.5 + Vector2(120, 120))
		skirt.position.y = theme.edge_height * 1.15 - 0.02
		skirt.material_override = _terrain_mesh.material_override
		skirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(skirt)


## Flat square ring (hole `inner` half-extents, outer `outer` half-extents) facing up, white
## vertex colour alpha 0 (not walkable) so the terrain shader paints it as cliff-top ground.
func _ring_mesh(inner: Vector2, outer: Vector2) -> ArrayMesh:
	var v := PackedVector3Array([
		Vector3(-outer.x, 0, -outer.y), Vector3(outer.x, 0, -outer.y), Vector3(outer.x, 0, outer.y), Vector3(-outer.x, 0, outer.y),
		Vector3(-inner.x, 0, -inner.y), Vector3(inner.x, 0, -inner.y), Vector3(inner.x, 0, inner.y), Vector3(-inner.x, 0, inner.y)])
	var n := PackedVector3Array()
	var c := PackedColorArray()
	for i in 8:
		n.append(Vector3.UP)
		c.append(Color(0, 0.5, 0, 0))
	# four trapezoids between the outer (0..3) and inner (4..7) squares, clockwise from above
	var idx := PackedInt32Array()
	for k in 4:
		var o0 := k
		var o1 := (k + 1) % 4
		var i0 := 4 + k
		var i1 := 4 + (k + 1) % 4
		idx.append_array([o0, o1, i1, o0, i1, i0])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_COLOR] = c
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am


func _terrain_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TERRAIN_SHADER
	m.set_shader_parameter(&"noise_tex", NOISE_TEX)
	m.set_shader_parameter(&"stone_tex", STONE_TEX)
	m.set_shader_parameter(&"soil_tex", SOIL_TEX)
	m.set_shader_parameter(&"ground_a", theme.ground_a)
	m.set_shader_parameter(&"ground_b", theme.ground_b)
	m.set_shader_parameter(&"path_color", theme.path_color)
	m.set_shader_parameter(&"path_joint", theme.path_joint)
	m.set_shader_parameter(&"cliff_a", theme.cliff_a)
	m.set_shader_parameter(&"cliff_b", theme.cliff_b)
	m.set_shader_parameter(&"accent", theme.accent)
	m.set_shader_parameter(&"accent_energy", theme.accent_energy)
	m.set_shader_parameter(&"accent_amount", theme.accent_amount)
	m.set_shader_parameter(&"accent_metal", 1.0 if theme.accent_energy <= 0.0 else 0.0)
	m.set_shader_parameter(&"shore", theme.shore)
	m.set_shader_parameter(&"shore_glow", theme.shore_glow)
	m.set_shader_parameter(&"shore_glow_energy", 1.5 if theme.liquid == TerrainTheme.Liquid.LAVA else 0.0)
	m.set_shader_parameter(&"path_paved", theme.path_paved)
	m.set_shader_parameter(&"ground_grain", theme.ground_grain)
	m.set_shader_parameter(&"corruption_strength", theme.corruption_strength)
	m.set_shader_parameter(&"path_wear", theme.path_wear)
	m.set_shader_parameter(&"inlay_color", theme.inlay_color)
	# sky islands over lava: the hot glow sits on the rift lips, not at the far-away lava surface
	var glow_level := 0.1 if theme.edge == TerrainTheme.Edge.DROP_DOWN else theme.liquid_level
	m.set_shader_parameter(&"liquid_level", glow_level)
	return m


# ---------------------------------------------------------------- liquid

## One big liquid plane under everything; the terrain covers it except in channels / beyond the
## island edge. Heaven gets the cloud sea far below instead.
func _build_liquid() -> void:
	var y := theme.liquid_level
	var mat: ShaderMaterial = ShaderMaterial.new()
	match theme.liquid:
		TerrainTheme.Liquid.NONE:
			if theme.edge != TerrainTheme.Edge.DROP_DOWN:
				return
			mat.shader = CLOUD_SEA_SHADER
			y = _cloud_y()
		TerrainTheme.Liquid.LAVA:
			mat.shader = LAVA_SHADER
			if theme.edge == TerrainTheme.Edge.DROP_DOWN:
				y = _cloud_y()  # a sky island over the fires of hell (The Breach)
				mat.set_shader_parameter(&"scale", 0.12)  # far below: bigger crust plates
				mat.set_shader_parameter(&"energy", 1.6)  # a whole sea of it: dimmer than a river
				mat.set_shader_parameter(&"crust_amount", 0.7)
		TerrainTheme.Liquid.WATER:
			mat.shader = WATER_SHADER
		TerrainTheme.Liquid.CLOUD:
			mat.shader = CLOUD_SEA_SHADER
			y = _cloud_y()
	if mat.shader == CLOUD_SEA_SHADER:
		mat.set_shader_parameter(&"noise_tex", NOISE_TEX)
	var mi := MeshInstance3D.new()
	mi.name = "Liquid"
	var pm := PlaneMesh.new()
	pm.size = size + Vector2(200, 200)
	pm.subdivide_width = 0
	pm.subdivide_depth = 0
	mi.mesh = pm
	mi.material_override = mat
	mi.position.y = y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta(&"keep", true)
	add_child(mi)
	# glow lights along lava rivers (capped with the others)
	if theme.liquid == TerrainTheme.Liquid.LAVA:
		for r: Array in _rivers:
			var pts: PackedVector2Array = r[0]
			for i in range(1, pts.size() - 1, 3):
				var p := pts[i]
				if absf(p.x) < size.x * 0.5 and absf(p.y) < size.y * 0.5:
					var l := PropKit._light(self, PropKit.LAVA_LIGHT, 2.0, 9.0, Vector3(p.x, 1.2, p.y), true)
					l.name = "LavaGlow"


# ---------------------------------------------------------------- bridges

func _build_bridges() -> void:
	var holy := theme.edge == TerrainTheme.Edge.DROP_DOWN
	for br: Array in _bridges:
		var a: Vector2 = br[0]
		var c: Vector2 = br[1]
		var w: float = br[2]
		var b := PropBuilder.new()
		var deck := PropKit.marble() if holy else PropKit.basalt()
		var rail := PropKit.gold() if holy else PropKit.iron()
		var length := a.distance_to(c)
		var mid := (a + c) * 0.5
		var yaw := atan2(c.x - a.x, c.y - a.y)  # local +z along the bridge
		# slightly arched deck made of planks / slabs
		var n := maxi(4, int(length / 0.9))
		for i in n:
			var t := (float(i) + 0.5) / float(n)
			var z := (t - 0.5) * length
			var y := sin(t * PI) * 0.18 - 0.08
			b.box(deck, Vector3(w, 0.22, length / float(n) - 0.05), Transform3D(Basis(), Vector3(0, y, z)))
		# piers at both ends and posts with rails / chains
		for s: float in [-1.0, 1.0]:
			b.box(deck, Vector3(w + 0.6, 1.2, 0.8), Transform3D(Basis(), Vector3(0, -0.55, s * length * 0.5)))
			for side: float in [-1.0, 1.0]:
				var post := Vector3(side * (w * 0.5 + 0.1), 0.0, s * (length * 0.5 - 0.3))
				b.box(deck, Vector3(0.3, 1.1, 0.3), Transform3D(Basis(), post + Vector3(0, 0.45, 0)))
				if holy:
					b.blob(rail, 0.14, _rng, Transform3D(Basis(), post + Vector3(0, 1.1, 0)), 0.0, 1, false)
				else:
					b.spike(rail, 0.12, 0.35, 4, Transform3D(Basis(), post + Vector3(0, 1.0, 0)))
		for side: float in [-1.0, 1.0]:
			var pts := PackedVector3Array()
			for k in 9:
				var t := float(k) / 8.0
				var z := (t - 0.5) * (length - 0.6)
				var sag := 0.0 if holy else 0.25 * 4.0 * t * (1.0 - t)
				pts.append(Vector3(side * (w * 0.5 + 0.1), 0.9 + sin(t * PI) * 0.18 - sag, z))
			if holy:
				b.tube(rail, pts, 0.05, 6)
			else:
				PropKit._chain(b, rail, pts, 0.2)
		# rails block sideways (so the bridge can't be used to step into the liquid)
		for side: float in [-1.0, 1.0]:
			b.collide_box(Vector3(0.3, 2.0, length), Transform3D(Basis(), Vector3(side * (w * 0.5 + 0.25), 1.0, 0)))
		var node := b.finish()
		node.name = "Bridge"
		node.position = Vector3(mid.x, 0.0, mid.y)
		node.rotation.y = yaw
		add_child(node)


# ---------------------------------------------------------------- cloud paths

## Cloud stepping-stones laid along every cloud path (flat walkable tops at y = 0).
func _build_cloud_paths() -> void:
	if _cloud_paths.is_empty():
		return
	var root := Node3D.new()
	root.name = "CloudPaths"
	add_child(root)
	for c: Array in _cloud_paths:
		var pts: PackedVector2Array = c[0]
		var w: float = c[1]
		var total := 0.0
		for i in pts.size() - 1:
			total += pts[i].distance_to(pts[i + 1])
		var step := w * 0.8
		var d := 0.0
		while d <= total:
			var p := _along(pts, d)
			var pl := PropKit.cloud_platform(_rng, w * _rng.randf_range(0.6, 0.75))
			pl.position = Vector3(p.x + _rng.randf_range(-0.3, 0.3), -0.02, p.y + _rng.randf_range(-0.3, 0.3))
			root.add_child(pl)
			d += step
	Scatter.merge(root, 24.0)


## Point at arc length `d` along a polyline.
static func _along(pts: PackedVector2Array, d: float) -> Vector2:
	for i in pts.size() - 1:
		var seg := pts[i].distance_to(pts[i + 1])
		if d <= seg:
			return pts[i].lerp(pts[i + 1], d / maxf(seg, 0.001))
		d -= seg
	return pts[pts.size() - 1]


# ---------------------------------------------------------------- collision

## Rectangles covering every non-walkable cell (1 m cells merged greedily), kept in
## `blocker_rects` (local space) for nav systems (GameMap). With `collision` on they also become box
## colliders on layer 1, plus four walls around the patch.
func _build_collision() -> void:
	blocker_rects.clear()
	var cs := 1.0
	var gx := int(ceil(size.x / cs))
	var gz := int(ceil(size.y / cs))
	var blocked := PackedByteArray()
	blocked.resize(gx * gz)
	for z in gz:
		for x in gx:
			var q := Vector2(-size.x * 0.5 + (float(x) + 0.5) * cs, -size.y * 0.5 + (float(z) + 0.5) * cs)
			# a cell blocks if its centre is outside the play area (bridges are kept open by _walk_at)
			blocked[z * gx + x] = 1 if _walk_q(q) < 0.0 else 0
	for z in gz:
		for x in gx:
			if blocked[z * gx + x] == 0:
				continue
			# grow right, then down while the whole row span is blocked
			var w := 1
			while x + w < gx and blocked[z * gx + x + w] == 1:
				w += 1
			var h := 1
			var grow := true
			while grow and z + h < gz:
				for k in w:
					if blocked[(z + h) * gx + x + k] == 0:
						grow = false
						break
				if grow:
					h += 1
			for dz in h:
				for k in w:
					blocked[(z + dz) * gx + x + k] = 0
			blocker_rects.append(Rect2(-size.x * 0.5 + float(x) * cs, -size.y * 0.5 + float(z) * cs, float(w) * cs, float(h) * cs))
	_stats["blocker_rects"] = blocker_rects.size()
	if not collision:
		return
	_body = StaticBody3D.new()
	_body.name = "TerrainCollision"
	_body.collision_layer = PropBuilder.WORLD_LAYER
	_body.collision_mask = 0
	add_child(_body)
	for r in blocker_rects:
		_add_box(Vector3(r.size.x, 4.0, r.size.y), Vector3(r.get_center().x, 1.0, r.get_center().y))
	for sgn: float in [-1.0, 1.0]:
		_add_box(Vector3(4.0, 4.0, size.y + 8.0), Vector3(sgn * (size.x * 0.5 + 2.0), 1.0, 0.0))
		_add_box(Vector3(size.x + 8.0, 4.0, 4.0), Vector3(0.0, 1.0, sgn * (size.y * 0.5 + 2.0)))


func _add_box(box_size: Vector3, pos: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = box_size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = pos
	_body.add_child(col)


# ---------------------------------------------------------------- scatter

func _scatter() -> void:
	_props_root = Node3D.new()
	_props_root.name = "Props"
	add_child(_props_root)
	var rect := Rect2(-size * 0.5, size)
	var walk_area := 0.0
	for w in _walk:
		if w > 0.0:
			walk_area += cell * cell
	var field_count := int(walk_area * theme.field_density / 100.0)
	var small_count := int(walk_area * theme.small_density / 100.0)
	# big blocking props: inside the arena, off paths, away from the plaza and liquids
	var placed: Array[Vector3] = []  # x, z, radius
	if not theme.field_props.is_empty():
		var pts := Scatter.poisson(rect, 6.0, _rng, field_count, func(p: Vector2) -> bool:
			return _walk_q(p) > 3.5 and p.length() > clear_radius + 3.0 and _dist_to_paths(p) > 3.0 \
					and _liq_q(p) < -2.5)
		for n in Scatter.place(_props_root, pts, theme.field_props, _rng, collision):
			placed.append(Vector3(n.position.x, n.position.z, float(n.get_meta(&"footprint", 1.0))))
		prop_blockers = placed.duplicate()
	# small filler (visual only): may sit on path edges but not in the plaza centre
	if not theme.small_props.is_empty():
		var pts := Scatter.poisson(rect, 2.2, _rng, small_count, func(p: Vector2) -> bool:
			if _walk_q(p) < 0.8 or p.length() < clear_radius * 0.6 or _dist_to_paths(p) < 1.2:
				return false
			for f in placed:
				if Vector2(f.x, f.y).distance_to(p) < f.z + 0.6:
					return false
			return true)
		Scatter.place(_props_root, pts, theme.small_props, _rng, false)
	# edge dressing: on cliffs / just past the island rim, no collision (terrain already blocks)
	if not theme.edge_props.is_empty():
		var edge_count := int(_perimeter_estimate() * theme.edge_density / 10.0)
		var pts := Scatter.poisson(rect, 4.0, _rng, edge_count, func(p: Vector2) -> bool:
			var w := _walk_q(p)
			return w < -1.0 and w > -9.0 and _liq_q(p) < -1.0)
		Scatter.place(_props_root, pts, theme.edge_props, _rng, false, func(p: Vector2) -> float:
			if theme.edge == TerrainTheme.Edge.DROP_DOWN:
				return maxf(_h_local(p), _cloud_y() + 0.4)  # clouds lap at the island's flanks
			return _h_local(p) - 0.15)
	_stats["props"] = _props_root.get_child_count()
	_stats["merged_meshes"] = Scatter.merge(_props_root, 24.0)


func _perimeter_estimate() -> float:
	var n := 0
	for i in _walk.size():
		if _walk[i] > -6.0 and _walk[i] < -1.0:
			n += 1
	return float(n) * cell * cell / 5.0


func _h_local(q: Vector2) -> float:
	var gx := clampi(int(round((q.x + size.x * 0.5) / cell)), 0, _nx - 1)
	var gz := clampi(int(round((q.y + size.y * 0.5) / cell)), 0, _nz - 1)
	return _h[gz * _nx + gx]


# ---------------------------------------------------------------- lights

func _register_lights(root: Node) -> void:
	if root is OmniLight3D:
		var l := root as OmniLight3D
		l.visible = false
		l.set_meta(&"w", 0.0)
		l.set_meta(&"phase", randf() * TAU)
		if not l.has_meta(&"base_energy"):
			l.set_meta(&"base_energy", l.light_energy)
		_lights.append(l)
	for c in root.get_children():
		_register_lights(c)


func _process(delta: float) -> void:
	if _lights.is_empty():
		return
	_time += delta
	_light_timer -= delta
	if _light_timer <= 0.0:
		_light_timer = 0.3
		_pick_lights()
	for l in _lights:
		var w: float = l.get_meta(&"w", 0.0)
		var target: float = l.get_meta(&"target", 0.0)
		if w == 0.0 and target == 0.0:
			continue
		w = move_toward(w, target, delta * 1.5)
		l.set_meta(&"w", w)
		l.visible = w > 0.001
		var ph: float = l.get_meta(&"phase", 0.0)
		var f: float = 0.75 + 0.25 * sin(_time * 1.4 + ph) if l.has_meta(&"pulse") \
				else 0.82 + 0.1 * sin(_time * 9.0 + ph) + 0.08 * sin(_time * 23.0 + ph * 2.3)
		l.light_energy = float(l.get_meta(&"base_energy", 2.0)) * w * f


func _pick_lights() -> void:
	# player looked up by group (not the Game autoload) so the patch also works in tools / editor
	var player := get_tree().get_first_node_in_group(&"player") as Node3D if is_inside_tree() else null
	var f := player.global_position if player else global_position
	var alive: Array[OmniLight3D] = []
	for l in _lights:
		if is_instance_valid(l) and l.is_inside_tree():
			alive.append(l)
	_lights = alive
	var sorted := _lights.duplicate()
	sorted.sort_custom(func(a: OmniLight3D, b: OmniLight3D) -> bool:
		return a.global_position.distance_squared_to(f) < b.global_position.distance_squared_to(f))
	for i in sorted.size():
		var l: OmniLight3D = sorted[i]
		l.set_meta(&"target", 1.0 if i < max_lights and l.global_position.distance_to(f) < 34.0 else 0.0)


# ---------------------------------------------------------------- geometry helpers

static func _bbox(pts: PackedVector2Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO) if pts.size() > 0 else Rect2()
	for p in pts:
		r = r.expand(p)
	return r


static func _seg_dist_ab(q: Vector2, a: Vector2, b: Vector2) -> float:
	return Geometry2D.get_closest_point_to_segment(q, a, b).distance_to(q)


## Distance to a polyline, short-cut by its bounding box: beyond `far` metres of the box only the
## (smaller) distance to the box is returned, which is plenty for fields that saturate anyway.
static func _poly_dist(q: Vector2, pts: PackedVector2Array, box: Rect2, far: float) -> float:
	var dx := maxf(maxf(box.position.x - q.x, q.x - box.end.x), 0.0)
	var dz := maxf(maxf(box.position.y - q.y, q.y - box.end.y), 0.0)
	var box_d := Vector2(dx, dz).length()
	if box_d > far:
		return box_d
	return _seg_dist(q, pts)


static func _seg_dist(q: Vector2, pts: PackedVector2Array) -> float:
	var best := 1e9
	for i in pts.size() - 1:
		var p := Geometry2D.get_closest_point_to_segment(q, pts[i], pts[i + 1])
		best = minf(best, p.distance_to(q))
	if pts.size() == 1:
		best = q.distance_to(pts[0])
	return best


func _dist_to_paths(q: Vector2) -> float:
	var d := 1e9
	for p: Array in _paths:
		d = minf(d, _seg_dist(q, p[0]) - float(p[1]) * 0.5)
	return d


func _dist_to_rivers(q: Vector2) -> float:
	var d := 1e9
	for r: Array in _rivers:
		d = minf(d, _seg_dist(q, r[0]) - float(r[1]) * 0.5)
	return d


static func _closest_on(pts: PackedVector2Array, q: Vector2) -> Vector2:
	var best := Vector2.INF
	for i in pts.size() - 1:
		var p := Geometry2D.get_closest_point_to_segment(q, pts[i], pts[i + 1])
		if best == Vector2.INF or p.distance_squared_to(q) < best.distance_squared_to(q):
			best = p
	return best


static func _polyline_intersection(a: PackedVector2Array, b: PackedVector2Array) -> Vector2:
	for i in a.size() - 1:
		for j in b.size() - 1:
			var hit: Variant = Geometry2D.segment_intersects_segment(a[i], a[i + 1], b[j], b[j + 1])
			if hit != null:
				return hit
	return Vector2.INF


## Direction of polyline `pts` at the segment nearest to `q`.
static func _polyline_dir(pts: PackedVector2Array, q: Vector2) -> Vector2:
	var best := 1e9
	var dir := Vector2.UP
	for i in pts.size() - 1:
		var p := Geometry2D.get_closest_point_to_segment(q, pts[i], pts[i + 1])
		var d := p.distance_to(q)
		if d < best:
			best = d
			dir = (pts[i + 1] - pts[i]).normalized()
	return dir
