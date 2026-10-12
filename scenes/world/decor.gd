extends Node3D
## Streams the purely visual ruined-sanctum scenery (no collisions) in square chunks around the
## player. Each chunk is deterministic for (chunk coords, run_seed), so walking away and back rebuilds
## the same ruins in the same spots.
##
## Per chunk: a theme from low-frequency noise (graveyard / ruins / dead wood / ash waste), an
## occasional landmark (ruined chapel, giant sword, stone circle with a hellish sigil, fallen
## colossus), 1-3 big features, then small filler. Afterwards every static mesh in the chunk is merged
## into one ArrayMesh per (material, shadow) pair, so a chunk costs ~10-20 draw calls.
##
## Fire / sigil OmniLights are capped: only the MAX_LIGHTS nearest to the player are on (faded in and
## out), and they flicker.

const CHUNK := 14.0
## Chunks within this Chebyshev radius of the player's chunk are kept loaded (5x5).
const LOAD_RADIUS := 2
## Chunks farther than this are freed (hysteresis so chunk borders don't thrash).
const FREE_RADIUS := 3
## Max chunks built per physics frame after the initial ring.
const BUILDS_PER_FRAME := 1
## perf: microseconds of chunk building per physics tick while streaming (0 = build at once).
const SLICE_US := 2500
## Area around world origin left empty (the starting plaza).
const CLEAR_RADIUS := 8.5
## Big features stay this far from the world origin.
const FEATURE_CLEAR_RADIUS := 11.0
## Landmarks stay this far from the world origin.
const LANDMARK_CLEAR_RADIUS := 24.0
const LANDMARK_CHANCE := 0.16
const MAX_LIGHTS := 8
const LIGHT_RANGE := 34.0

enum Biome { GRAVEYARD, RUINS, DEADWOOD, ASH }

const BIG_TABLES := {
	Biome.GRAVEYARD: {&"crypt": 3.0, &"statue_angel": 2.0, &"iron_fence": 3.0, &"dead_tree": 2.5,
			&"brazier": 1.2, &"banner": 0.6, &"gibbet": 0.6, &"golden_tree": 0.5},
	Biome.RUINS: {&"broken_column": 5.0, &"fallen_pillar": 3.0, &"arch": 3.0, &"statue_angel": 1.2,
			&"statue_knight": 1.5, &"banner": 1.8, &"brazier": 1.4, &"chains": 1.0},
	Biome.DEADWOOD: {&"dead_tree": 7.0, &"golden_tree": 1.6, &"broken_column": 1.0, &"statue_knight": 0.8,
			&"gibbet": 1.0, &"brazier": 0.6},
	Biome.ASH: {&"dead_tree": 2.0, &"fallen_pillar": 2.0, &"chains": 1.5, &"statue_knight": 1.0,
			&"brazier": 1.2, &"gibbet": 0.8, &"banner": 0.8},
}
const SMALL_TABLES := {
	Biome.GRAVEYARD: {&"gravestone": 9.0, &"grass_tuft": 4.0, &"candles": 1.2, &"skull": 1.0, &"dead_shrub": 1.5, &"rubble": 1.0},
	Biome.RUINS: {&"rubble": 5.0, &"grass_tuft": 4.0, &"gravestone": 1.0, &"candles": 1.0, &"skull": 0.8, &"dead_shrub": 1.0},
	Biome.DEADWOOD: {&"dead_shrub": 5.0, &"grass_tuft": 5.0, &"rubble": 1.5, &"skull": 1.0, &"bone_pile": 1.0, &"gravestone": 0.8},
	Biome.ASH: {&"bone_pile": 3.0, &"skull": 2.0, &"rubble": 3.0, &"dead_shrub": 2.0, &"grass_tuft": 1.0, &"candles": 0.5},
}
## Footprint radius per big feature (spacing).
const RADII := {&"broken_column": 1.8, &"fallen_pillar": 2.6, &"arch": 2.8, &"statue_angel": 1.8,
		&"statue_knight": 1.5, &"dead_tree": 2.2, &"golden_tree": 3.2, &"iron_fence": 4.0, &"brazier": 1.0,
		&"banner": 1.0, &"crypt": 1.8, &"chains": 1.8, &"gibbet": 1.8}

## 0 = pick a random seed on _ready.
@export var run_seed: int = 0
@export var big_min: int = 1
@export var big_max: int = 3
@export var small_min: int = 7
@export var small_max: int = 13

var _chunks: Dictionary = {}  # Vector2i -> Node3D
var _queue: Array[Vector2i] = []
var _building := false
var _slice_budget := 0  # usec per slice while streaming; 0 = no slicing (initial ring)
var _slice_t0 := 0
## Longest uninterrupted slice so far (usec; perf overlay / bench).
var slice_max_us := 0
var _center := Vector2i(2147483647, 2147483647)
var _initialized := false
var _theme_noise := FastNoiseLite.new()
var _lights: Array[OmniLight3D] = []
var _light_timer := 0.0
var _time := 0.0


func _ready() -> void:
	if run_seed == 0:
		run_seed = randi()
	_setup_noise()
	# perf: build every prop kind's merged variants now (part of the run's load), not the first
	# time streaming meets it mid-run (6-46 ms each). Instant if the menus already warmed them.
	Perf.prewarm_props_now()
	_prewarm_kinds()


## perf: one throwaway build of every prop kind the tables can pick (first builds also create
## their materials / load surface textures: up to ~20 ms each when it happened mid-run).
func _prewarm_kinds() -> void:
	var rng := RandomNumberGenerator.new()
	var kinds: Array[StringName] = []
	kinds.append_array(Props.LANDMARKS)
	for tables: Dictionary in [BIG_TABLES, SMALL_TABLES]:
		for theme in tables:
			for kind in (tables[theme] as Dictionary).keys():
				if not kinds.has(kind):
					kinds.append(kind)
	for kind in kinds:
		var n := Props.build(kind, rng)
		if n:
			n.free()


func _setup_noise() -> void:
	_theme_noise.seed = run_seed
	_theme_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_theme_noise.frequency = 0.012


func _physics_process(_delta: float) -> void:
	var p := _focus()
	var c := Vector2i(floori(p.x / CHUNK), floori(p.z / CHUNK))
	if c != _center:
		_center = c
		_refresh()
	if not _initialized:
		_initialized = true
		while not _queue.is_empty():
			_build(_queue.pop_front())
		return
	# perf (docs/team/performance.md): streamed chunks are built time-sliced, SLICE_US of work per
	# physics tick, one chunk at a time (a whole chunk used to cost ~13 ms in one frame).
	if _building or _queue.is_empty():
		return
	_building = true
	_slice_budget = SLICE_US
	_slice_t0 = Time.get_ticks_usec()
	await _build(_queue.pop_front())
	_slice_budget = 0
	_building = false


func _process(delta: float) -> void:
	_time += delta
	_light_timer -= delta
	if _light_timer <= 0.0:
		_light_timer = 0.25
		_pick_lights()
	for l in _lights:
		if not is_instance_valid(l):
			continue  # its chunk was freed since the last _pick_lights()
		var w: float = l.get_meta(&"w", 0.0)
		var target: float = l.get_meta(&"target", 0.0)
		if w == 0.0 and target == 0.0:
			continue
		w = move_toward(w, target, delta * 1.5)
		l.set_meta(&"w", w)
		l.visible = w > 0.001
		if not l.visible:
			continue
		var ph: float = l.get_meta(&"phase", 0.0)
		var f: float
		if l.has_meta(&"pulse"):
			f = 0.75 + 0.25 * sin(_time * 1.4 + ph)
		else:
			f = 0.82 + 0.1 * sin(_time * 9.0 + ph) + 0.08 * sin(_time * 23.0 + ph * 2.3) * sin(_time * 3.1 + ph)
		l.light_energy = float(l.get_meta(&"base_energy", 2.0)) * w * f


## Enables (fades in) the MAX_LIGHTS registered lights nearest to the player.
func _pick_lights() -> void:
	var alive: Array[OmniLight3D] = []
	for l in _lights:
		if is_instance_valid(l) and l.is_inside_tree():
			alive.append(l)
	_lights = alive
	var f := _focus()
	var sorted := _lights.duplicate()
	sorted.sort_custom(func(a: OmniLight3D, b: OmniLight3D) -> bool:
		return a.global_position.distance_squared_to(f) < b.global_position.distance_squared_to(f))
	for i in sorted.size():
		var l: OmniLight3D = sorted[i]
		var on := i < MAX_LIGHTS and l.global_position.distance_to(f) < LIGHT_RANGE
		l.set_meta(&"target", 1.0 if on else 0.0)


## Rebuilds everything with a new seed (e.g. on a new run).
func reset(new_seed: int = 0) -> void:
	for k: Vector2i in _chunks:
		(_chunks[k] as Node3D).queue_free()
	_chunks.clear()
	_queue.clear()
	_lights.clear()
	run_seed = new_seed if new_seed != 0 else randi()
	_setup_noise()
	_center = Vector2i(2147483647, 2147483647)
	_initialized = false


func _focus() -> Vector3:
	if is_instance_valid(Game.player):
		return Game.player.global_position
	return Vector3.ZERO


func _refresh() -> void:
	for k: Vector2i in _chunks.keys():
		if _dist(k) > FREE_RADIUS:
			(_chunks[k] as Node3D).queue_free()
			_chunks.erase(k)
	var wanted: Array[Vector2i] = []
	for k in _queue:
		if _dist(k) <= LOAD_RADIUS:
			wanted.append(k)
	for dz in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
		for dx in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
			var k := _center + Vector2i(dx, dz)
			if not _chunks.has(k) and not wanted.has(k):
				wanted.append(k)
	wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _dist2(a) < _dist2(b))
	_queue = wanted


func _dist(k: Vector2i) -> int:
	return maxi(absi(k.x - _center.x), absi(k.y - _center.y))


func _dist2(k: Vector2i) -> int:
	var d := k - _center
	return d.x * d.x + d.y * d.y


func _theme(k: Vector2i) -> Biome:
	var n := _theme_noise.get_noise_2d((float(k.x) + 0.5) * CHUNK, (float(k.y) + 0.5) * CHUNK)
	if n < -0.22:
		return Biome.GRAVEYARD
	if n < 0.08:
		return Biome.RUINS
	if n < 0.32:
		return Biome.DEADWOOD
	return Biome.ASH


## Deterministic: does chunk `k` hold a landmark? Never two in neighbouring chunks.
func _is_landmark(k: Vector2i) -> bool:
	var center := (Vector2(k) + Vector2(0.5, 0.5)) * CHUNK
	if center.length() < LANDMARK_CLEAR_RADIUS:
		return false
	if _landmark_roll(k) >= LANDMARK_CHANCE:
		return false
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dz == 0:
				continue
			var o := k + Vector2i(dx, dz)
			# a neighbour with a lower roll that is itself eligible wins
			if _landmark_roll(o) < LANDMARK_CHANCE and _landmark_roll(o) < _landmark_roll(k) \
					and ((Vector2(o) + Vector2(0.5, 0.5)) * CHUNK).length() >= LANDMARK_CLEAR_RADIUS:
				return false
	return true


func _landmark_roll(k: Vector2i) -> float:
	var h := hash([k.x, k.y, run_seed, 77])
	return float(h & 0xFFFFFF) / float(0xFFFFFF)


# ---------------------------------------------------------------- chunk building

## Yields to the next physics tick when the current slice's time budget is used up (perf).
func _slice() -> void:
	if _slice_budget > 0 and Time.get_ticks_usec() - _slice_t0 > _slice_budget:
		slice_max_us = maxi(slice_max_us, Time.get_ticks_usec() - _slice_t0)
		await get_tree().physics_frame
		_slice_t0 = Time.get_ticks_usec()


func _build(k: Vector2i) -> void:
	if _chunks.has(k):
		return
	var chunk := Node3D.new()
	chunk.name = "Chunk_%d_%d" % [k.x, k.y]
	chunk.position = Vector3(float(k.x) * CHUNK, 0.0, float(k.y) * CHUNK)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([k.x, k.y, run_seed])
	var origin := Vector2(chunk.position.x, chunk.position.z)
	var taken: Array[Vector3] = []  # local x, z, radius
	var theme := _theme(k)

	_origin_braziers(chunk, rng, origin, taken)

	await _slice()
	if _is_landmark(k):
		var kind: StringName = Props.LANDMARKS[rng.randi() % Props.LANDMARKS.size()]
		var at := Vector2(CHUNK * 0.5 + rng.randf_range(-1.5, 1.5), CHUNK * 0.5 + rng.randf_range(-1.5, 1.5))
		var lm := Props.build(kind, rng)
		lm.position = Vector3(at.x, 0.0, at.y)
		chunk.add_child(lm)
		taken.append(Vector3(at.x, at.y, 6.5))

	var big_table: Dictionary = BIG_TABLES[theme]
	for _i in rng.randi_range(big_min, big_max):
		var kind := Props.pick(big_table, rng)
		var r: float = RADII.get(kind, 2.0)
		var spot := _find_spot(rng, origin, taken, r, minf(r, 2.5), FEATURE_CLEAR_RADIUS)
		if spot.z < 0.0:
			continue
		await _slice()
		var f := Props.build(kind, rng)
		f.position = Vector3(spot.x, 0.0, spot.y)
		chunk.add_child(f)
		taken.append(Vector3(spot.x, spot.y, r))
		if kind == &"brazier" and rng.randf() < 0.5:
			# braziers come in pairs, flanking a path
			var off := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized() * 3.2
			var p2 := Vector2(spot.x, spot.y) + off
			if p2.x > 0.5 and p2.x < CHUNK - 0.5 and p2.y > 0.5 and p2.y < CHUNK - 0.5 and (origin + p2).length() > CLEAR_RADIUS:
				var f2 := Props.brazier(rng)
				f2.position = Vector3(p2.x, 0.0, p2.y)
				chunk.add_child(f2)
				taken.append(Vector3(p2.x, p2.y, 1.0))

	await _slice()
	var small_table: Dictionary = SMALL_TABLES[theme]
	for _i in rng.randi_range(small_min, small_max):
		var spot := _find_spot(rng, origin, taken, 0.9, 0.4)
		if spot.z < 0.0:
			continue
		var kind := Props.pick(small_table, rng)
		await _slice()
		var item := Props.build(kind, rng)
		item.position = Vector3(spot.x, 0.0, spot.y)
		chunk.add_child(item)
		taken.append(Vector3(spot.x, spot.y, 0.7))
		# graveyard rows: a neighbour stone in line
		if kind == &"gravestone" and rng.randf() < 0.5:
			var p2 := Vector2(spot.x + 1.6, spot.y + rng.randf_range(-0.2, 0.2))
			if p2.x < CHUNK - 0.4 and (origin + p2).length() > CLEAR_RADIUS:
				var g2 := Props.gravestone(rng)
				g2.position = Vector3(p2.x, 0.0, p2.y)
				g2.rotation.y = item.rotation.y + rng.randf_range(-0.2, 0.2)
				chunk.add_child(g2)

	await _merge(chunk)
	if _chunks.has(k) or not is_inside_tree():
		chunk.free()  # built twice meanwhile / decor left the tree while slicing
		return
	add_child(chunk)
	_chunks[k] = chunk
	_register_lights(chunk)


## Four braziers around the starting plaza (each built by whichever chunk contains it).
func _origin_braziers(chunk: Node3D, rng: RandomNumberGenerator, origin: Vector2, taken: Array[Vector3]) -> void:
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var w := Vector2(sx, sz) * 5.6
			var local := w - origin
			if local.x < 0.0 or local.y < 0.0 or local.x >= CHUNK or local.y >= CHUNK:
				continue
			var b := Props.brazier(rng)
			b.position = Vector3(local.x, 0.0, local.y)
			chunk.add_child(b)
			taken.append(Vector3(local.x, local.y, 1.2))


func _register_lights(root: Node) -> void:
	if root is OmniLight3D:
		var l := root as OmniLight3D
		l.visible = false
		l.set_meta(&"w", 0.0)
		l.set_meta(&"phase", randf() * TAU)
		_lights.append(l)
	for c in root.get_children():
		_register_lights(c)
	_light_timer = 0.0


## Returns (x, z, 1) of a free local spot, or z < 0 if none found.
func _find_spot(rng: RandomNumberGenerator, origin: Vector2, taken: Array[Vector3], radius: float, margin: float,
		clear: float = CLEAR_RADIUS) -> Vector3:
	for _attempt in 10:
		var p := Vector2(rng.randf_range(margin, CHUNK - margin), rng.randf_range(margin, CHUNK - margin))
		if (origin + p).length() < clear:
			continue
		var ok := true
		for t in taken:
			if Vector2(t.x, t.y).distance_to(p) < radius + t.z * 0.8:
				ok = false
				break
		if ok:
			return Vector3(p.x, p.y, 1.0)
	return Vector3(0.0, 0.0, -1.0)


# ---------------------------------------------------------------- mesh merging

## Merges every static MeshInstance3D under `chunk` into one MeshInstance3D per (material, shadow).
## Skips nodes with meta `keep` and materials with custom vertex shaders (flames, sigils).
func _merge(chunk: Node3D) -> void:
	var groups := {}  # key -> {st, mat, shadow}
	var merged: Array[MeshInstance3D] = []
	await _collect(chunk, chunk, Transform3D.IDENTITY, groups, merged)
	var freed := 0
	for mi in merged:
		mi.get_parent().remove_child(mi)
		mi.free()
		freed += 1
		if freed % 24 == 0:
			await _slice()
	for key: String in groups:
		await _slice()
		var g: Dictionary = groups[key]
		var st: SurfaceTool = g["st"]
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = g["mat"]
		mi.cast_shadow = g["shadow"]
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		chunk.add_child(mi)


func _collect(node: Node, chunk: Node3D, xf: Transform3D, groups: Dictionary, merged: Array[MeshInstance3D]) -> void:
	for c in node.get_children():
		if not c is Node3D:
			continue
		var n3 := c as Node3D
		var cxf := xf * n3.transform
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			if _mergeable(mi):
				var key := "%d|%d" % [mi.material_override.get_instance_id(), mi.cast_shadow]
				if not groups.has(key):
					var st := SurfaceTool.new()
					groups[key] = {"st": st, "mat": mi.material_override, "shadow": mi.cast_shadow}
				(groups[key]["st"] as SurfaceTool).append_from(mi.mesh, 0, cxf)
				merged.append(mi)
				await _slice()
		await _collect(c, chunk, cxf, groups, merged)


func _mergeable(mi: MeshInstance3D) -> bool:
	if mi.has_meta(&"keep") or mi.mesh == null:
		return false
	var m := mi.material_override
	if m is StandardMaterial3D:
		return true
	if m is ShaderMaterial:
		return (m as ShaderMaterial).shader == Art.LIT_STATIC
	return false
