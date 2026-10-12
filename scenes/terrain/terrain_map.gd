class_name TerrainMap
extends GameMap
## Generator map (data/maps/*.json "generator": "res://scenes/terrain/terrain_map.gd") built on a
## TerrainPatch: a procedural arena of the chosen TerrainTheme (sky island with cloud rifts, lava
## basin, drowned sanctum...) with paths, bridges, outcrops and scattered PropKit / Props scenery.
##
## Registry keys (besides the usual GameMap ones, see docs/team/maps.md):
##   "terrain": {
##     "theme": "heaven" | "hell" | "sanctum" | "breach"   (res://data/terrain/<theme>.tres),
##     "size": 132,             heightmap side in metres
##     "arena_radius": 44,      walkable arena radius (bounds also take in satellite islands)
##     "landmarks": true,       place named PropKit landmarks (LANDMARKS[theme], braziers by the spawn)
##     "corruption": 0.0        Corruption.ambient for the run: blight already spread (The Breach)
##   }
##
## The patch keeps its own colliders (terrain rectangles + prop bodies); this class mirrors them into
## the GameMap nav grid so enemy steering, spawning and relocation respect cliffs, rifts and rivers.

## Named landmarks per theme id: [prop, display name, clearance radius, tag]; then the spawn braziers.
const LANDMARKS := {
	"heaven": [[&"chapel", "Forsaken Chapel", 7.5, &"shrine"], [&"golden_gate", "Gate of Pearl", 4.0, &"gate"],
			[&"stained_window", "Shattered Lancet", 3.0, &"ruin"], [&"sun_mirror", "Mirror of Dawn", 2.5, &"shrine"]],
	"hell": [[&"lava_pool", "Weeping Forge", 4.0, &"forge"], [&"basalt_columns", "Basalt Organ", 3.5, &"ruin"],
			[&"chain_posts", "Chain Yard", 3.5, &"yard"]],
	"sanctum": [[&"bell_tower_ruin", "Drowned Belfry", 4.0, &"ruin"], [&"stained_window", "Shattered Lancet", 3.0, &"ruin"],
			[&"crucifix_pyre", "Penitents' Pyre", 2.5, &"shrine"]],
	"breach": [[&"hell_rift", "The Wound", 4.0, &"rift"], [&"fallen_wing", "Severed Wing", 3.5, &"ruin"],
			[&"golden_gate", "Toppled Gate", 4.0, &"gate"], [&"corrupted_column", "Pillar of Ash", 2.5, &"ruin"]],
}
const BRAZIERS := {"heaven": &"holy_brazier", "hell": &"hell_brazier", "sanctum": &"holy_brazier", "breach": &"hell_brazier"}

var patch: TerrainPatch
var _taken: Array[Vector3] = []  # x, z, radius of placed markers / landmark props


func _init() -> void:
	bounds_kind = Bounds.CIRCLE
	nav_cell = 1.5


func _build_layout() -> void:
	var t: Dictionary = def.get("terrain", {})
	var theme_id := String(t.get("theme", "heaven"))
	var theme := load("res://data/terrain/%s.tres" % theme_id) as TerrainTheme
	if theme == null:
		push_warning("TerrainMap: unknown terrain theme %s" % theme_id)
		theme = load("res://data/terrain/heaven.tres")
	var size := float(t.get("size", 132.0))
	var radius := float(t.get("arena_radius", 44.0))
	bounds_center = Vector2.ZERO
	bounds_radius = radius + 3.0

	patch = TerrainPatch.new()
	patch.name = "Terrain"
	patch.theme = theme
	patch.size = Vector2(size, size)
	patch.arena_radius = radius
	patch.rng_seed = map_seed
	patch.max_lights = 0  # GameMap caps and flickers every light under `scenery`
	patch.build_on_ready = false
	scenery.add_child(patch)
	patch.build()
	# satellite islands (sky themes) may reach beyond the arena: bounds take in every open area
	bounds_radius = maxf(radius + 3.0, minf(patch.play_radius() + 2.0, size * 0.5 - 2.0))

	# nav: everything the terrain blocks, plus the solid props it scattered
	var br := bounds_rect().grow(4.0)
	for r in patch.blocker_rects:
		if br.intersects(r):
			_blockers.append({"kind": "box", "c": r.get_center(), "half": r.size * 0.5, "rot": 0.0})
	for pb in patch.prop_blockers:
		_taken.append(pb)
	_mirror_collision(patch)

	# the stock endless ground plane would z-fight / cover the terrain: hide it for this run
	for g in get_tree().get_nodes_in_group(&"ground"):
		(g as Node3D).visible = false

	# burning hoofprints behind the demon (terrain surface dressing)
	add_child(ScorchTrail.new())
	set_player_spawn(Vector3.ZERO)
	_taken.append(Vector3(0, 0, patch.clear_radius))
	if bool(t.get("landmarks", true)):
		_place_landmarks(theme_id)
	# pre-spread blight (Corruption autoload, docs/team/art-style.md); it resets on scene change
	var blight := float(t.get("corruption", 0.0))
	var corruption := get_node_or_null(^"/root/Corruption")
	if blight > 0.0 and corruption:
		corruption.set(&"ambient", blight)
	_place_objectives()
	_place_enemy_spawns()


## After the nav grid exists (and unreachable pockets are sealed): any marker that ended up in a
## blocked cell (a pocket behind a rift or an outcrop) moves to the nearest open, reachable cell.
func _finalize() -> void:
	super()
	if not _has_nav:
		return
	for m in markers.get_children():
		if m is Marker3D and _blocked_at((m as Marker3D).position):
			(m as Marker3D).position = _nearest_open((m as Marker3D).position)


func _nearest_open(p: Vector3) -> Vector3:
	var c0 := _cell_of(p)
	for r in range(1, 40):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue  # ring only
				var c := c0 + Vector2i(dx, dy)
				if _in_grid(c) and _blocked[c.y * _gw + c.x] == 0:
					var d := float(dx * dx + dy * dy)
					if d < best_d:
						best_d = d
						best = c
		if best.x >= 0:
			var q := _cell_center(best)
			return Vector3(q.x, 0.0, q.y)
	return get_player_spawn()


# ---------------------------------------------------------------- placement

## Free walkable spot with `clearance` metres of open ground, away from paths' centre plaza and
## other markers; tries `tries` random candidates within [r_min, r_max] of the centre.
func _spot(clearance: float, r_min: float, r_max: float, tries: int = 80) -> Vector3:
	for _i in tries:
		var a := rng.randf() * TAU
		var d := rng.randf_range(r_min, r_max)
		var p := Vector3(cos(a) * d, 0.0, sin(a) * d)
		if patch.walk_distance(p) < clearance:
			continue
		var ok := true
		for q in _taken:
			if Vector2(q.x, q.y).distance_to(Vector2(p.x, p.z)) < q.z + clearance:
				ok = false
				break
		if ok:
			return p
	return Vector3.INF


func _place_landmarks(theme_id: String) -> void:
	var r := minf(bounds_radius, float(def.get("terrain", {}).get("arena_radius", 44.0)))
	var table: Array = LANDMARKS.get(theme_id, LANDMARKS["heaven"])
	for row: Array in table:
		var p := _spot(float(row[2]), r * 0.35, r * 0.8)
		if p == Vector3.INF:
			continue
		var n := PropKit.build(row[0], rng, true)
		n.position = p
		scenery.add_child(n)
		_mirror_collision(n)
		_taken.append(Vector3(p.x, p.z, float(row[2])))
		landmark(StringName(String(row[0])), String(row[1]), p, float(row[2]) + 4.0, row[3])
	# braziers flanking the spawn plaza
	for s: float in [-1.0, 1.0]:
		var b := PropKit.build(BRAZIERS.get(theme_id, &"holy_brazier"), rng, true)
		b.position = Vector3(s * 4.5, 0, -3.0)
		scenery.add_child(b)
		b.add_to_group(&"braziers")
		_mirror_collision(b)


## Mirrors every prop collider under `root` (StaticBody3D "Collision", not the terrain's own box
## body, which is covered by blocker_rects) into the nav grid with its real shape: boxes stay boxes
## (rotated), cylinders / spheres become circles. So walls of a chapel or a gate block exactly where
## they stand, and doorways stay open for enemies.
func _mirror_collision(root: Node) -> void:
	for c in root.get_children():
		if c is StaticBody3D and c.name == &"Collision":
			for cs in c.get_children():
				if not cs is CollisionShape3D:
					continue
				var shape := (cs as CollisionShape3D).shape
				var xf := (cs as Node3D).global_transform if (cs as Node3D).is_inside_tree() else _xf_to(cs as Node3D)
				var center := Vector2(xf.origin.x, xf.origin.z)
				var sc := xf.basis.get_scale()
				if shape is BoxShape3D:
					var size := (shape as BoxShape3D).size
					var yaw := atan2(xf.basis.x.z, xf.basis.x.x)
					_blockers.append({"kind": "box", "c": center, "half": Vector2(size.x * sc.x, size.z * sc.z) * 0.5,
							"rot": -yaw})
				elif shape is CylinderShape3D:
					_blockers.append({"kind": "circle", "c": center, "r": (shape as CylinderShape3D).radius * sc.x})
				elif shape is SphereShape3D:
					_blockers.append({"kind": "circle", "c": center, "r": (shape as SphereShape3D).radius * sc.x})
		elif c.name != &"TerrainCollision":
			_mirror_collision(c)


static func _xf_to(n: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p is Node3D:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


## Every bounded map provides altar (3+), ritual (2+), relic (1+), boss_arena (1) and some shrines.
func _place_objectives() -> void:
	var r := bounds_radius
	var plan := [[&"boss_arena", 1, 9.0], [&"altar", 3, 3.0], [&"ritual", 2, 4.0], [&"relic", 1, 2.5],
			[&"shrine", 2, 2.5]]
	for row: Array in plan:
		for i in int(row[1]):
			var clear := float(row[2])
			var p := _spot(clear, r * 0.25, r * 0.85)
			if p == Vector3.INF:
				p = _spot(clear * 0.5, 4.0, r * 0.9, 200)
			if p == Vector3.INF:
				p = patch.random_walkable(rng, 2.0)
			objective(row[0], p, StringName("%s_%d" % [row[0], i]))
			_taken.append(Vector3(p.x, p.z, clear))


## Enemy spawn points along the inner rim (enemies pour in from the edges of the arena).
func _place_enemy_spawns() -> void:
	var r := bounds_radius
	var placed := 0
	for i in 60:
		if placed >= 8:
			break
		var a := TAU * float(i) / 60.0 * 7.0 + rng.randf() * 0.3
		var p := Vector3(cos(a), 0, sin(a)) * rng.randf_range(r * 0.75, r * 0.92)
		var w := patch.walk_distance(p)
		if w > 1.0 and w < 8.0:
			enemy_spawn(p)
			placed += 1
