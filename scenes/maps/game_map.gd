class_name GameMap
extends Node3D
## Base class for every playable map. A map is a Node3D (usually the root of a small .tscn under
## scenes/maps/) whose script overrides `_build_layout()` and builds its scenery from code with the
## helpers below. The map loader (scenes/maps/map_loader.gd) instantiates it and calls `build(def)`.
##
## What a map provides:
##   - bounds (circle / rectangle / polygon) with invisible boundary colliders (physics layer 1)
##   - solid blockers (walls, buildings, statues) on layer 1 that both the player and enemies collide with
##   - a coarse nav grid + flow field toward the player, so enemies steer around walls (`steer()`)
##   - markers: player spawn, enemy spawn points (gates...), named landmarks, objective anchors
##   - capped, faded point lights (only the nearest MAX_LIGHTS are on) and ambient particles
##
## Static scenery is merged after building (one mesh per material per BUCKET x BUCKET metres), so a
## whole map costs a few dozen draw calls. Nodes with meta `keep` (flames, sigils) are never merged.
##
## Groups (for other systems): markers are Marker3Ds in "map_landmark", "map_objective",
## "map_enemy_spawn"; brazier-like fire props in "braziers" (Ambience fire crackle).

signal built
## A destructible statue queued with statue() entered the world (spawned after the run starts).
signal statue_spawned(statue: MapStatue)
## First time the player comes within a landmark's radius.
signal landmark_discovered(id: StringName, display_name: String, marker: Node3D)

enum Bounds { NONE, CIRCLE, RECT, POLYGON }

const BUCKET := 32.0
## See-through hole radius of map materials (shared decor uses 0.07).
const FADE_RADIUS := 0.2
const MAX_LIGHTS := 10
const LIGHT_RANGE := 36.0
## Nav-grid obstacles are inflated by a bit more than an enemy radius (gaps under ~1.4 m close).
const INFLATE := 0.7
## Flow-field BFS radius in cells (path length; ring maps need ~2x the 40 m relocation distance).
const FLOW_MAX := 140
## Cells expanded per physics tick by the time-sliced rebuild (a full map is ~4-6k open cells, so a
## rebuild spreads over 3-5 ticks at ~0.4 ms each instead of one ~2 ms spike).
const FLOW_BUDGET := 1500
## Authored spawn points are used for this share of spawns when one is in range.
const AUTHORED_SPAWN_CHANCE := 0.35
const SPAWN_MIN_DIST := 17.0
const SPAWN_MAX_DIST := 36.0
const N8: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

@export var bounds_kind: Bounds = Bounds.CIRCLE
@export var bounds_center := Vector2.ZERO
## CIRCLE radius.
@export var bounds_radius := 60.0
## RECT full size (centered on bounds_center).
@export var bounds_size := Vector2(120.0, 120.0)
## POLYGON outline (x, z), any winding.
@export var bounds_polygon := PackedVector2Array()
@export var nav_cell := 1.5
## Height of the invisible boundary colliders.
@export var boundary_height := 6.0

var def: Dictionary = {}
var map_id: StringName = &""
var map_seed := 0
## Seeded from (map seed, variant seed); use it for every random choice in _build_layout(), so a
## variant is reproducible (--map-seed=N) while runs differ.
var rng := RandomNumberGenerator.new()
## This run's layout variant (0 = the pinned layout when "variety" is false).
var variant_seed := 0
## Tests: >= 0 forces this variant seed (tools/maps/map_check.gd).
var force_variant := -1

var scenery: Node3D  # visual nodes (merged in finalize)
var body: StaticBody3D  # every collider
var markers: Node3D

var _player_spawn := Vector3.ZERO
var _blockers: Array[Dictionary] = []  # {kind: "circle"|"box", c: Vector2, r: float, half: Vector2, rot: float}
var _mesh_cache := {}
var _fade_mats := {}  # shared base material -> private copy with FADE_RADIUS
var _statue_queue: Array[Dictionary] = []
var _lights: Array[OmniLight3D] = []
var _light_timer := 0.0
var _time := 0.0
var _particles: Array[GPUParticles3D] = []
var _discovered := {}
var _discover_timer := 0.0
var _is_built := false

# nav grid
var _gw := 0
var _gh := 0
var _gorigin := Vector2.ZERO
var _blocked := PackedByteArray()
var _dist := PackedInt32Array()  # front flow field (read by steer)
var _dist_b := PackedInt32Array()  # back buffer being rebuilt
var _bhead := 0
var _btail := 0
var _building := false
var _build_cell := Vector2i(-99999, -99999)
var _queue := PackedInt32Array()
var _flow_cell := Vector2i(-99999, -99999)
var _has_nav := false


# ================================================================ lifecycle

## Builds the whole map from its registry definition. Called once by the loader.
func build(p_def: Dictionary) -> void:
	def = p_def
	map_id = StringName(def.get("id", name))
	map_seed = int(def.get("seed", 0))
	if map_seed == 0:
		map_seed = randi()
	# Per-run variety: the map keeps its identity (structure, set pieces) but every run rolls a new
	# variant seed that maps use to shuffle feature slots, gates, hazards and scatter.
	# "variety": false in the JSON pins the layout; --map-seed=N (dev) reproduces a variant.
	variant_seed = randi() if bool(def.get("variety", true)) else 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map-seed="):
			variant_seed = arg.substr(11).to_int()
	if force_variant >= 0:
		variant_seed = force_variant
	rng.seed = hash([map_seed, variant_seed])
	scenery = Node3D.new()
	scenery.name = "Scenery"
	add_child(scenery)
	body = StaticBody3D.new()
	body.name = "Colliders"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	markers = Node3D.new()
	markers.name = "Markers"
	add_child(markers)
	_build_layout()
	_build_boundary_colliders()
	_dress_boundary()
	_adopt_authored_markers(self)
	_finalize()
	_is_built = true
	built.emit()


## Override: lay out the map with the helpers below.
func _build_layout() -> void:
	pass


## Override: visuals along the boundary (walls, hedges, cliffs). Colliders are already in place.
func _dress_boundary() -> void:
	pass


func _physics_process(_delta: float) -> void:
	if not _is_built:
		return
	if _has_nav:
		# The field only depends on the player's cell (obstacles are static), so it is rebuilt only
		# when that cell changes - time-sliced, FLOW_BUDGET cells per tick, into a back buffer. The
		# first field (or a field more than FLOW_MAX / 2 cells stale) is built at once.
		var c := _cell_of(_focus())
		if _building:
			_flow_step(FLOW_BUDGET)
		elif c != _flow_cell:
			@warning_ignore("integer_division")
			var far := absi(c.x - _flow_cell.x) + absi(c.y - _flow_cell.y) > FLOW_MAX / 2
			if far:
				_update_flow(c)
			else:
				_flow_begin(c)
				_flow_step(FLOW_BUDGET)


func _process(delta: float) -> void:
	if not _is_built:
		return
	_time += delta
	_update_lights(delta)
	_update_fade(_focus())
	if not _statue_queue.is_empty():
		_spawn_statues()
	var f := _focus()
	for p in _particles:
		p.global_position = Vector3(f.x, p.get_meta(&"height", 10.0), f.z)
	_discover_timer -= delta
	if _discover_timer <= 0.0:
		_discover_timer = 0.3
		_check_discovery(f)


func _focus() -> Vector3:
	if is_instance_valid(Game.player):
		return Game.player.global_position
	return _player_spawn


# ================================================================ building helpers: materials

## Static lit material (merged, occluder-faded). `surface`: Art.SURFACES key (&"stone", &"metal"...).
## Map materials are private copies with a much wider see-through hole than the shared decor
## (FADE_RADIUS): map walls and towers are big, and the camera must always find the demon.
func mat(color: Color, rough: float = 0.85, metal: float = 0.0, grime: float = 0.5, moss: float = 0.0,
		surface: StringName = &"stone") -> Material:
	var base := Props.mat(color, rough, metal, grime, moss, 0.0, surface)
	if _fade_mats.has(base):
		return _fade_mats[base]
	var m := base.duplicate() as ShaderMaterial
	m.set_shader_parameter(&"fade_radius", FADE_RADIUS)
	_fade_mats[base] = m
	return m


## Feeds the player position to this map's private materials (Atmosphere feeds the shared ones).
func _update_fade(f: Vector3) -> void:
	for m: ShaderMaterial in _fade_mats.values():
		m.set_shader_parameter(&"fade_focus", f)


## A PropKit prop (scripts/terrain/prop_kit.gd, terrain role) without its own collision; `solid`
## adds a round blocker of its footprint so the nav grid knows about it. Falls back to Props.
func kit(kind: StringName, pos: Vector3, rot_y: float = NAN, scl: float = 1.0, solid: bool = true) -> Node3D:
	if not PropKit.has(kind):
		return prop(kind, pos, rot_y, scl, 1.0 if solid else 0.0)
	var n := PropKit.build(kind, rng, false)
	n.position = pos
	if not is_nan(rot_y):
		n.rotation.y = rot_y
	if scl != 1.0:
		n.scale *= scl
	scenery.add_child(n)
	if kind == &"holy_brazier" or kind == &"hell_brazier":
		n.add_to_group(&"braziers")
	if solid:
		block_circle(pos, PropKit.footprint(kind) * scl * 0.75, 3.0)
	return n


# ================================================================ features: interactables + hazards
# Live nodes (never merged) under the map's "Features" child. See scenes/maps/features/.

func _features() -> Node3D:
	var f := get_node_or_null(^"Features") as Node3D
	if f == null:
		f = Node3D.new()
		f.name = "Features"
		add_child(f)
	return f


## A holy font (HolyFont): heals angels nearby until the demon corrupts it.
func font(pos: Vector3) -> HolyFont:
	var n := HolyFont.new()
	n.position = pos
	_features().add_child(n)
	block_circle(pos, 0.85, 1.4)
	return n


## A summoning bell (SummoningBell): strike it for Ichor, and a ring of angels answers.
func bell(pos: Vector3, rot_y: float = 0.0) -> SummoningBell:
	var n := SummoningBell.new()
	n.position = pos
	n.rotation.y = rot_y
	_features().add_child(n)
	for s: float in [-1.0, 1.0]:  # the frame posts (SummoningBell builds their colliders) in the nav grid
		block_circle(pos + Basis(Vector3.UP, rot_y) * Vector3(s * 1.2, 0, 0), 0.3, 3.0)
	return n


## A destructible holy statue (MapStatue, an Enemy the weapons can break). Spawned into Game.world
## once the run is live; returns nothing now - use `statue_spawned` / Maps for the live node.
func statue(pos: Vector3, variant: StringName = &"saint", rot_y: float = NAN) -> void:
	_statue_queue.append({"pos": pos, "variant": variant, "rot": rot_y})


## Any hazard / feature node (LightningStorm, SweepingBeam, FissureField, custom).
func hazard(n: Node3D, pos := Vector3.ZERO) -> Node3D:
	n.position = pos
	_features().add_child(n)
	return n


## Hazard tuning from the JSON: def.hazards.<key> merged over `defaults` and copied onto `n`.
func tune(n: Object, key: String) -> void:
	var h: Dictionary = (def.get("hazards", {}) as Dictionary).get(key, {})
	for k: String in h:
		if k in n:
			n.set(k, h[k])


func _spawn_statues() -> void:
	if _statue_queue.is_empty() or Game.world == null or Game.player == null:
		return
	var scene := load(MapStatue.SCENE_PATH) as PackedScene
	for s: Dictionary in _statue_queue:
		var st := scene.instantiate() as MapStatue
		st.variant = s["variant"]
		st.setup(MapStatue.make_data(s["variant"]), 1.0)
		Game.spawn(st, clamp_to_bounds(s["pos"]))
		if not is_nan(float(s["rot"])):
			st.model.rotation.y = float(s["rot"])
		statue_spawned.emit(st)
	_statue_queue.clear()


## Random element of `arr` (from this run's variant rng).
func pick_one(arr: Array) -> Variant:
	return arr[rng.randi() % arr.size()] if not arr.is_empty() else null


## `arr` shuffled with this run's variant rng (Array.shuffle() would use the global rng).
func shuffled(arr: Array) -> Array:
	var out := arr.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t: Variant = out[i]
		out[i] = out[j]
		out[j] = t
	return out


## Unshaded glow (additive by default).
func glow(color: Color, energy: float = 2.0, additive: bool = true) -> Material:
	return Art.glow(color, energy, additive)


## Lit + emissive (holy inlays, hellfire cracks). Not merged with static scenery.
func emissive(color: Color, glow_color: Color, energy: float = 2.0) -> Material:
	return Art.emissive(color, glow_color, energy)


# ================================================================ building helpers: geometry

func _mesh(key: String, maker: Callable) -> Mesh:
	if not _mesh_cache.has(key):
		_mesh_cache[key] = maker.call()
	return _mesh_cache[key]


func _place(mesh: Mesh, m: Material, xf: Transform3D, shadow: bool, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if m is StandardMaterial3D and (m as StandardMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else scenery).add_child(mi)
	return mi


## Box standing on `pos` (pos = bottom centre). `solid` adds a collider + nav blocker.
func box(pos: Vector3, size: Vector3, m: Material, rot_y: float = 0.0, solid: bool = true,
		shadow: bool = true) -> MeshInstance3D:
	var mesh := _mesh("box%s" % size, func() -> Mesh:
		var b := BoxMesh.new()
		b.size = size
		return b)
	var xf := Transform3D(Basis(Vector3.UP, rot_y), pos + Vector3(0.0, size.y * 0.5, 0.0))
	if solid:
		block_box(pos, Vector2(size.x, size.z), rot_y, size.y)
	return _place(mesh, m, xf, shadow)


## Cylinder / cone standing on `pos`. top < 0 = same as bottom radius.
func cylinder(pos: Vector3, radius: float, height: float, m: Material, solid: bool = true,
		top: float = -1.0, sides: int = 16, shadow: bool = true) -> MeshInstance3D:
	var top_r := radius if top < 0.0 else top
	var mesh := _mesh("cyl%.2f|%.2f|%.2f|%d" % [radius, top_r, height, sides], func() -> Mesh:
		var c := CylinderMesh.new()
		c.bottom_radius = radius
		c.top_radius = top_r
		c.height = height
		c.radial_segments = sides
		c.rings = 1
		return c)
	if solid:
		block_circle(pos, maxf(radius, top_r), height)
	return _place(mesh, m, Transform3D(Basis(), pos + Vector3(0.0, height * 0.5, 0.0)), shadow)


func sphere(pos: Vector3, radius: float, m: Material, squash: float = 1.0, shadow: bool = true) -> MeshInstance3D:
	var mesh := _mesh("sph%.2f|%.2f" % [radius, squash], func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = radius
		s.height = radius * 2.0 * squash
		s.radial_segments = 16
		s.rings = 8
		return s)
	return _place(mesh, m, Transform3D(Basis(), pos), shadow)


func torus(pos: Vector3, inner: float, outer: float, m: Material, rot := Vector3.ZERO, shadow: bool = false) -> MeshInstance3D:
	var mesh := _mesh("tor%.2f|%.2f" % [inner, outer], func() -> Mesh:
		var t := TorusMesh.new()
		t.inner_radius = inner
		t.outer_radius = outer
		t.rings = 24
		t.ring_segments = 8
		return t)
	return _place(mesh, m, Transform3D(Basis.from_euler(rot), pos), shadow)


## Triangular prism (roof) on `pos`: size = (width, height, depth), ridge along local Z.
func prism(pos: Vector3, size: Vector3, m: Material, rot_y: float = 0.0, shadow: bool = true) -> MeshInstance3D:
	var mesh := _mesh("pri%s" % size, func() -> Mesh:
		var p := PrismMesh.new()
		p.size = size
		return p)
	return _place(mesh, m, Transform3D(Basis(Vector3.UP, rot_y), pos + Vector3(0.0, size.y * 0.5, 0.0)), shadow)


## Flat disc / ground decal (no collision) at height `y` (pools, sigils, plazas).
func disc(pos: Vector3, radius: float, m: Material, sides: int = 32) -> MeshInstance3D:
	var mesh := _mesh("disc%.2f|%d" % [radius, sides], func() -> Mesh:
		var c := CylinderMesh.new()
		c.top_radius = radius
		c.bottom_radius = radius
		c.height = 0.04
		c.radial_segments = sides
		c.rings = 1
		return c)
	return _place(mesh, m, Transform3D(Basis(), pos + Vector3(0.0, 0.02, 0.0)), false)


## A Props prop (see scripts/props.gd: BIG / SMALL / LANDMARKS). rot_y = NAN keeps Props' random
## rotation. `solid_radius` > 0 adds a round blocker.
func prop(kind: StringName, pos: Vector3, rot_y: float = NAN, scl: float = 1.0, solid_radius: float = 0.0) -> Node3D:
	if PropKit.has(kind):
		return kit(kind, pos, rot_y, scl, solid_radius > 0.0)
	var n := Props.build(kind, rng)
	n.position = pos
	if not is_nan(rot_y):
		n.rotation.y = rot_y
	if scl != 1.0:
		n.scale *= scl
	scenery.add_child(n)
	if kind == &"brazier":
		n.add_to_group(&"braziers")
	if solid_radius > 0.0:
		block_circle(pos, solid_radius * scl, 3.0)
	return n


## Point light, capped and faded with the others. `flicker` = fire, else steady (or `pulse`).
func light(pos: Vector3, color: Color, energy: float = 2.0, range_m: float = 8.0, flicker: bool = true,
		pulse: bool = false) -> OmniLight3D:
	var l := Art.light(scenery, color, energy, range_m, pos)
	l.omni_attenuation = 1.4
	l.light_specular = 0.3
	l.set_meta(&"base_energy", energy)
	if pulse:
		l.set_meta(&"pulse", true)
	elif not flicker:
		l.set_meta(&"steady", true)
	return l


## Animated flame quad (same material as braziers). Never merged.
func flame(pos: Vector3, size := Vector2(0.9, 1.5)) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = Props.flame_material()
	mi.position = pos + Vector3(0.0, size.y * 0.5, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta(&"keep", true)
	scenery.add_child(mi)
	return mi


# ================================================================ building helpers: blockers

## Round obstacle (collider + nav). Height only matters for the collider.
func block_circle(pos: Vector3, radius: float, height: float = 3.0) -> void:
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = radius
	sh.height = height
	cs.shape = sh
	cs.position = Vector3(pos.x, height * 0.5, pos.z)
	body.add_child(cs)
	_blockers.append({"kind": "circle", "c": Vector2(pos.x, pos.z), "r": radius})


## Box obstacle; `size` = (x, z) footprint, rotated by rot_y around its centre.
func block_box(pos: Vector3, size: Vector2, rot_y: float = 0.0, height: float = 3.0) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(size.x, height, size.y)
	cs.shape = sh
	cs.transform = Transform3D(Basis(Vector3.UP, rot_y), Vector3(pos.x, height * 0.5, pos.z))
	body.add_child(cs)
	_blockers.append({"kind": "box", "c": Vector2(pos.x, pos.z), "half": size * 0.5, "rot": rot_y})


## Straight wall from a to b (bottom), `thick` wide, `height` tall. Returns the mesh.
func wall(a: Vector3, b: Vector3, thick: float, height: float, m: Material, solid: bool = true) -> MeshInstance3D:
	var d := b - a
	d.y = 0.0
	var length := d.length()
	var rot := atan2(d.x, d.z)
	return box((a + b) * 0.5, Vector3(thick, height, length), m, rot, solid)


# ================================================================ building helpers: markers

func set_player_spawn(pos: Vector3) -> void:
	_player_spawn = pos


func get_player_spawn() -> Vector3:
	return _player_spawn


## Named landmark. `tag` groups them (e.g. &"shrine", &"gate"). radius = discovery / footprint.
func landmark(id: StringName, display_name: String, pos: Vector3, radius: float = 6.0,
		tag: StringName = &"") -> Marker3D:
	var mk := _marker(&"map_landmark", pos)
	mk.name = "Landmark_%s" % id
	mk.set_meta(&"id", id)
	mk.set_meta(&"display_name", display_name)
	mk.set_meta(&"radius", radius)
	mk.set_meta(&"tag", tag)
	# HUD minimap (ui/components/minimap.gd): a small brimstone dot, not pinned to the rim
	mk.add_to_group(&"minimap_marker")
	mk.set_meta(&"minimap_color", Color(0.85, 0.62, 0.3, 0.8))
	mk.set_meta(&"minimap_size", 3.0)
	mk.set_meta(&"minimap_pin", false)
	return mk


## Objective anchor: a clear spot the objectives system can use (altar to defile, relic, ritual
## circle...). `kind` is free-form; see docs/team/maps.md for the kinds every map provides.
func objective(kind: StringName, pos: Vector3, id: StringName = &"") -> Marker3D:
	var mk := _marker(&"map_objective", pos)
	mk.name = "Objective_%s_%d" % [kind, markers.get_child_count()]
	mk.set_meta(&"kind", kind)
	mk.set_meta(&"id", id if id != &"" else StringName(mk.name))
	return mk


func enemy_spawn(pos: Vector3) -> Marker3D:
	var mk := _marker(&"map_enemy_spawn", pos)
	mk.name = "EnemySpawn_%d" % markers.get_child_count()
	return mk


func _marker(group: StringName, pos: Vector3) -> Marker3D:
	var mk := Marker3D.new()
	mk.position = pos
	mk.add_to_group(group)
	markers.add_child(mk)
	return mk


## Hand-placed Marker3Ds in the .tscn: a node named "PlayerSpawn" sets the spawn; Marker3Ds already
## in one of the map groups are kept as they are.
func _adopt_authored_markers(n: Node) -> void:
	for c in n.get_children():
		if c == scenery or c == body or c == markers:
			continue
		if c is Marker3D and c.name == &"PlayerSpawn":
			_player_spawn = (c as Marker3D).global_position
		_adopt_authored_markers(c)


func get_landmarks(tag: StringName = &"") -> Array[Node3D]:
	return _group_under(&"map_landmark", &"tag", tag)


func get_objective_points(kind: StringName = &"") -> Array[Node3D]:
	return _group_under(&"map_objective", &"kind", kind)


func get_enemy_spawn_points() -> Array[Node3D]:
	return _group_under(&"map_enemy_spawn", &"", &"")


func _group_under(group: StringName, meta_key: StringName, value: StringName) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in get_tree().get_nodes_in_group(group):
		if not is_ancestor_of(n):
			continue
		if value != &"" and StringName(n.get_meta(meta_key, &"")) != value:
			continue
		out.append(n as Node3D)
	return out


func _check_discovery(f: Vector3) -> void:
	for mk in get_landmarks():
		var id: StringName = mk.get_meta(&"id", &"")
		if _discovered.has(id):
			continue
		var r: float = mk.get_meta(&"radius", 6.0)
		var d := Vector2(mk.global_position.x - f.x, mk.global_position.z - f.z).length()
		if d <= r + 4.0:
			_discovered[id] = true
			landmark_discovered.emit(id, String(mk.get_meta(&"display_name", id)), mk)


# ================================================================ scatter

## Scatters `count` props from a weighted `table` ({kind: weight}) in a ring around `center`,
## avoiding blockers, other scattered items, the player spawn and anything outside the bounds.
func scatter(table: Dictionary, count: int, center: Vector3, r_min: float, r_max: float,
		spacing: float = 1.4, keep_clear: Array[Vector3] = []) -> void:
	var placed: Array[Vector2] = []
	for _i in count:
		for _attempt in 8:
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf_range(r_min * r_min, r_max * r_max))
			var p := center + Vector3(cos(a) * r, 0.0, sin(a) * r)
			if not _free_spot(p, spacing, placed, keep_clear):
				continue
			prop(Props.pick(table, rng), p)
			placed.append(Vector2(p.x, p.z))
			break


## Like scatter() but inside a rotated rectangle (centre, full size, rotation).
func scatter_rect(table: Dictionary, count: int, center: Vector3, size: Vector2, rot_y: float = 0.0,
		spacing: float = 1.4, keep_clear: Array[Vector3] = []) -> void:
	var placed: Array[Vector2] = []
	var rot := Basis(Vector3.UP, rot_y)
	for _i in count:
		for _attempt in 8:
			var local := Vector3(rng.randf_range(-0.5, 0.5) * size.x, 0.0, rng.randf_range(-0.5, 0.5) * size.y)
			var p := center + rot * local
			if not _free_spot(p, spacing, placed, keep_clear):
				continue
			prop(Props.pick(table, rng), p)
			placed.append(Vector2(p.x, p.z))
			break


## keep_clear entries: (x, z, radius) packed as Vector3(x, radius, z) is confusing, so they are
## Vector3(x, 0, z) points with an implied 4 m radius.
func _free_spot(p: Vector3, spacing: float, placed: Array[Vector2], keep_clear: Array[Vector3]) -> bool:
	if not _inside_bounds(Vector2(p.x, p.z), 2.0):
		return false
	if _hits_blocker(Vector2(p.x, p.z), 0.8):
		return false
	if Vector2(p.x - _player_spawn.x, p.z - _player_spawn.z).length() < 5.0:
		return false
	for k in keep_clear:
		if Vector2(p.x - k.x, p.z - k.z).length() < 4.0:
			return false
	for q in placed:
		if q.distance_to(Vector2(p.x, p.z)) < spacing:
			return false
	return true


# ================================================================ ambient particles

## Falling / drifting particles that follow the player. kind: &"snow", &"petals", &"motes", &"embers".
func ambient_particles(kind: StringName, amount: int = 500) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Ambient_%s" % kind
	p.amount = amount
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-40, -20, -40), Vector3(80, 40, 80))
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(26.0, 1.0, 20.0)
	var quad := QuadMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	var height := 11.0
	match kind:
		&"snow":
			p.lifetime = 7.0
			pm.direction = Vector3(0.3, -1.0, 0.1)
			pm.spread = 12.0
			pm.initial_velocity_min = 1.2
			pm.initial_velocity_max = 2.4
			pm.gravity = Vector3(0.6, -0.6, 0.2)
			pm.turbulence_enabled = true
			pm.turbulence_noise_strength = 0.6
			pm.color = Color(0.92, 0.95, 1.0, 0.85)
			quad.size = Vector2(0.11, 0.11)
		&"petals":
			p.lifetime = 9.0
			pm.direction = Vector3(0.4, -1.0, 0.2)
			pm.spread = 25.0
			pm.initial_velocity_min = 0.4
			pm.initial_velocity_max = 1.0
			pm.gravity = Vector3(0.35, -0.5, 0.15)
			pm.angle_min = 0.0
			pm.angle_max = 360.0
			pm.angular_velocity_min = -90.0
			pm.angular_velocity_max = 90.0
			pm.turbulence_enabled = true
			pm.turbulence_noise_strength = 1.2
			pm.color = Color(1.0, 0.86, 0.9, 0.9)
			var g := Gradient.new()
			g.set_color(0, Color(1.0, 0.95, 0.85))
			g.set_color(1, Color(1.0, 0.72, 0.82))
			var gt := GradientTexture1D.new()
			gt.gradient = g
			pm.color_initial_ramp = gt
			quad.size = Vector2(0.16, 0.1)
		&"motes":
			p.lifetime = 6.0
			height = 0.5
			pm.direction = Vector3(0.0, 1.0, 0.0)
			pm.spread = 30.0
			pm.initial_velocity_min = 0.3
			pm.initial_velocity_max = 0.9
			pm.gravity = Vector3(0.1, 0.25, 0.0)
			pm.turbulence_enabled = true
			pm.turbulence_noise_strength = 0.8
			pm.color = Color(1.0, 0.85, 0.45, 0.8)
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			quad.size = Vector2(0.08, 0.08)
		_:  # embers
			p.lifetime = 4.0
			height = 0.3
			pm.direction = Vector3(0.2, 1.0, 0.0)
			pm.spread = 20.0
			pm.initial_velocity_min = 1.0
			pm.initial_velocity_max = 2.6
			pm.gravity = Vector3(0.5, 0.6, 0.0)
			pm.turbulence_enabled = true
			pm.turbulence_noise_strength = 1.0
			pm.color = Color(1.0, 0.45, 0.12, 1.0)
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			quad.size = Vector2(0.07, 0.07)
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.12, Color(1, 1, 1, 1))
	fade.add_point(0.8, Color(1, 1, 1, 1))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	pm.color_ramp = ft
	p.process_material = pm
	quad.material = m
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.set_meta(&"height", height)
	p.position = Vector3(_player_spawn.x, height, _player_spawn.z)
	add_child(p)
	p.preprocess = p.lifetime
	_particles.append(p)
	return p


# ================================================================ bounds

func _inside_bounds(p: Vector2, margin: float = 0.0) -> bool:
	match bounds_kind:
		Bounds.CIRCLE:
			return p.distance_to(bounds_center) <= bounds_radius - margin
		Bounds.RECT:
			var h := bounds_size * 0.5 - Vector2(margin, margin)
			var d := (p - bounds_center).abs()
			return d.x <= h.x and d.y <= h.y
		Bounds.POLYGON:
			if not Geometry2D.is_point_in_polygon(p, bounds_polygon):
				return false
			if margin <= 0.0:
				return true
			for i in bounds_polygon.size():
				var a := bounds_polygon[i]
				var b := bounds_polygon[(i + 1) % bounds_polygon.size()]
				if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < margin:
					return false
			return true
	return true


## Axis-aligned extents of the playable area (x, z, w, h).
func bounds_rect() -> Rect2:
	match bounds_kind:
		Bounds.CIRCLE:
			return Rect2(bounds_center - Vector2.ONE * bounds_radius, Vector2.ONE * bounds_radius * 2.0)
		Bounds.RECT:
			return Rect2(bounds_center - bounds_size * 0.5, bounds_size)
		Bounds.POLYGON:
			var r := Rect2(bounds_polygon[0], Vector2.ZERO)
			for q in bounds_polygon:
				r = r.expand(q)
			return r
	return Rect2(-60, -60, 120, 120)


## Boundary outline as a closed polyline (x, z), sampled every ~`step` metres.
func boundary_points(step: float = 4.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	match bounds_kind:
		Bounds.CIRCLE:
			var n := maxi(12, ceili(TAU * bounds_radius / step))
			for i in n:
				var a := TAU * float(i) / float(n)
				out.append(bounds_center + Vector2(cos(a), sin(a)) * bounds_radius)
		Bounds.RECT, Bounds.POLYGON:
			var poly := _outline()
			for i in poly.size():
				var a := poly[i]
				var b := poly[(i + 1) % poly.size()]
				var n := maxi(1, ceili(a.distance_to(b) / step))
				for k in n:
					out.append(a.lerp(b, float(k) / float(n)))
	return out


func _outline() -> PackedVector2Array:
	if bounds_kind == Bounds.RECT:
		var h := bounds_size * 0.5
		var c := bounds_center
		return PackedVector2Array([c + Vector2(-h.x, -h.y), c + Vector2(h.x, -h.y), c + Vector2(h.x, h.y), c + Vector2(-h.x, h.y)])
	return bounds_polygon


## Outward unit normal of the boundary at outline point `p` (approximate for polygons).
func outward_at(p: Vector2) -> Vector2:
	if bounds_kind == Bounds.CIRCLE:
		return (p - bounds_center).normalized()
	var probe := 0.6
	for i in 16:
		var a := TAU * float(i) / 16.0
		var d := Vector2(cos(a), sin(a))
		if not _inside_bounds(p + d * probe) and _inside_bounds(p - d * probe):
			return d
	return (p - bounds_rect().get_center()).normalized()


func _build_boundary_colliders() -> void:
	if bounds_kind == Bounds.NONE:
		return
	const THICK := 3.0
	if bounds_kind == Bounds.CIRCLE:
		var n := maxi(16, ceili(TAU * bounds_radius / 4.0))
		var seg := TAU * (bounds_radius + THICK * 0.5) / float(n) + 0.6
		for i in n:
			var a := TAU * float(i) / float(n)
			var dir := Vector2(cos(a), sin(a))
			var c := bounds_center + dir * (bounds_radius + THICK * 0.5)
			_boundary_box(c, Vector2(THICK, seg), atan2(dir.x, dir.y) + PI * 0.5)
		return
	var poly := _outline()
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var mid := (a + b) * 0.5
		var tangent := (b - a).normalized()
		var normal := Vector2(tangent.y, -tangent.x)
		if _inside_bounds(mid + normal * 0.5):
			normal = -normal
		var c := mid + normal * THICK * 0.5
		# box local Z runs along the edge
		_boundary_box(c, Vector2(THICK, a.distance_to(b) + THICK), atan2(tangent.x, tangent.y))


func _boundary_box(c: Vector2, size: Vector2, rot: float) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(size.x, boundary_height, size.y)
	cs.shape = sh
	cs.transform = Transform3D(Basis(Vector3.UP, rot), Vector3(c.x, boundary_height * 0.5, c.y))
	body.add_child(cs)


# ================================================================ finalize: nav grid + merge

func _finalize() -> void:
	_build_nav()
	_merge_scenery()
	_register_lights(scenery)


func _build_nav() -> void:
	if bounds_kind == Bounds.NONE:
		_has_nav = false
		return
	var r := bounds_rect().grow(nav_cell * 2.0)
	_gorigin = r.position
	_gw = ceili(r.size.x / nav_cell)
	_gh = ceili(r.size.y / nav_cell)
	_blocked.resize(_gw * _gh)
	_blocked.fill(0)
	_dist.resize(_gw * _gh)
	_dist_b.resize(_gw * _gh)
	_dist.fill(-1)
	_queue.resize(_gw * _gh)
	for y in _gh:
		for x in _gw:
			var p := _cell_center(Vector2i(x, y))
			if not _inside_bounds(p, INFLATE):
				_blocked[y * _gw + x] = 1
	for b in _blockers:
		_raster_blocker(b)
	_seal_unreachable()
	_has_nav = true


## Open cells that can't be reached from the player spawn (closed courtyards, gaps behind walls)
## are marked blocked, so nothing ever spawns or gets relocated into a pocket it can't leave.
func _seal_unreachable() -> void:
	var s := _cell_of(_player_spawn)
	if not _in_grid(s):
		return
	var seen := PackedByteArray()
	seen.resize(_gw * _gh)
	var q := PackedInt32Array()
	q.resize(_gw * _gh)
	var si := s.y * _gw + s.x
	_blocked[si] = 0
	seen[si] = 1
	q[0] = si
	var head := 0
	var tail := 1
	while head < tail:
		var i := q[head]
		head += 1
		var x := i % _gw
		for n: int in [i - 1 if x > 0 else -1, i + 1 if x < _gw - 1 else -1, i - _gw, i + _gw]:
			if n < 0 or n >= _gw * _gh or seen[n] != 0 or _blocked[n] != 0:
				continue
			seen[n] = 1
			q[tail] = n
			tail += 1
	for i in _gw * _gh:
		if seen[i] == 0:
			_blocked[i] = 1


func _raster_blocker(b: Dictionary) -> void:
	var c: Vector2 = b["c"]
	var ext: float
	if b["kind"] == "circle":
		ext = float(b["r"]) + INFLATE
	else:
		ext = (b["half"] as Vector2).length() + INFLATE
	var c0 := _cell_of(Vector3(c.x - ext, 0.0, c.y - ext))
	var c1 := _cell_of(Vector3(c.x + ext, 0.0, c.y + ext))
	for y in range(maxi(c0.y, 0), mini(c1.y, _gh - 1) + 1):
		for x in range(maxi(c0.x, 0), mini(c1.x, _gw - 1) + 1):
			if _point_in_blocker(_cell_center(Vector2i(x, y)), b, INFLATE):
				_blocked[y * _gw + x] = 1


func _point_in_blocker(p: Vector2, b: Dictionary, pad: float) -> bool:
	var c: Vector2 = b["c"]
	if b["kind"] == "circle":
		return p.distance_to(c) <= float(b["r"]) + pad
	# rotate into the box frame (box local X/Z; rot_y turns local +Z toward world (sin, cos))
	var d := p - c
	var rot: float = b["rot"]
	var lx := d.x * cos(rot) - d.y * sin(rot)
	var lz := d.x * sin(rot) + d.y * cos(rot)
	var h: Vector2 = b["half"]
	return absf(lx) <= h.x + pad and absf(lz) <= h.y + pad


func _hits_blocker(p: Vector2, pad: float) -> bool:
	for b in _blockers:
		if _point_in_blocker(p, b, pad):
			return true
	return false


func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori((p.x - _gorigin.x) / nav_cell), floori((p.z - _gorigin.y) / nav_cell))


func _cell_center(c: Vector2i) -> Vector2:
	return _gorigin + (Vector2(c) + Vector2(0.5, 0.5)) * nav_cell


func _in_grid(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < _gw and c.y < _gh


func _blocked_at(p: Vector3) -> bool:
	var c := _cell_of(p)
	if not _in_grid(c):
		return true
	return _blocked[c.y * _gw + c.x] != 0


## BFS (4-neighbour) distance field from the player's cell, limited to FLOW_MAX cells.
## Synchronous full rebuild (tests / first frame). The live game time-slices it: _flow_begin() +
## _flow_step() over a few physics frames into a back buffer, swapped in when complete.
func _update_flow(start: Vector2i) -> void:
	_flow_begin(start)
	while not _flow_step(1 << 30):
		pass


## Starts a BFS (4-neighbour) distance field from `start` in the back buffer (_dist_b).
func _flow_begin(start: Vector2i) -> void:
	_building = true
	_build_cell = start
	_dist_b.fill(-1)
	_bhead = 0
	_btail = 0
	if not _in_grid(start):
		return
	var w := _gw
	var s := start.y * w + start.x
	_dist_b[s] = 0
	_queue[0] = s
	_btail = 1
	if _blocked[s] != 0:
		# player hugging a wall (inside the inflated margin): also seed the open cells around them
		for o in N8:
			var n := start + o
			if _in_grid(n) and _blocked[n.y * w + n.x] == 0:
				_dist_b[n.y * w + n.x] = 1
				_queue[_btail] = n.y * w + n.x
				_btail += 1


## Expands up to `budget` cells; returns true (and swaps the buffers) when the field is complete.
func _flow_step(budget: int) -> bool:
	var w := _gw
	var total := _gw * _gh
	var head := _bhead
	var tail := _btail
	var stop := mini(head + budget, 1 << 30)
	while head < tail and head < stop:
		var i := _queue[head]
		head += 1
		var nd := _dist_b[i] + 1
		if nd > FLOW_MAX:
			continue
		var x := i % w
		# Inline neighbour visits (GDScript loops over arrays allocate; this is the hot loop).
		if x > 0:
			var n := i - 1
			if _dist_b[n] < 0 and _blocked[n] == 0:
				_dist_b[n] = nd
				_queue[tail] = n
				tail += 1
		if x < w - 1:
			var n := i + 1
			if _dist_b[n] < 0 and _blocked[n] == 0:
				_dist_b[n] = nd
				_queue[tail] = n
				tail += 1
		if i >= w:
			var n := i - w
			if _dist_b[n] < 0 and _blocked[n] == 0:
				_dist_b[n] = nd
				_queue[tail] = n
				tail += 1
		if i + w < total:
			var n := i + w
			if _dist_b[n] < 0 and _blocked[n] == 0:
				_dist_b[n] = nd
				_queue[tail] = n
				tail += 1
	_bhead = head
	_btail = tail
	if head < tail:
		return false
	# done: swap front / back (packed arrays are ref-counted, the swap is free)
	var t := _dist
	_dist = _dist_b
	_dist_b = t
	_flow_cell = _build_cell
	_building = false
	return true


## See Maps.steer(). Straight at the player while the way ahead is clear, else down the flow field.
func steer(from: Vector3, dir: Vector3) -> Vector3:
	if not _has_nav:
		return dir
	var c := _cell_of(from)
	if not _in_grid(c):
		return dir
	# Go straight only if (a) the field says nothing is in the way: the BFS distance equals the
	# Manhattan distance to the player's cell (an unobstructed staircase path exists), and (b) the next
	# few metres are clear for an enemy-sized body. (a) keeps the choice consistent from cell to cell,
	# so bodies don't oscillate at the edge of a short look-ahead behind long walls.
	var here0 := _dist[c.y * _gw + c.x]
	var manhattan := absi(c.x - _flow_cell.x) + absi(c.y - _flow_cell.y)
	if here0 < 0 or here0 <= manhattan + 1:
		var side := Vector3(-dir.z, 0.0, dir.x) * 0.45
		if not _blocked_at(from + dir * 0.9) and not _blocked_at(from + dir * 1.9) and not _blocked_at(from + dir * 3.0) \
				and not _blocked_at(from + dir * 1.2 + side) and not _blocked_at(from + dir * 1.2 - side):
			return dir
	var best := 1 << 30
	var best_off := Vector2i.ZERO
	for o in N8:
		var n := c + o
		if not _in_grid(n):
			continue
		var d := _dist[n.y * _gw + n.x]
		if d < 0:
			continue
		if o.x != 0 and o.y != 0:
			# no corner cutting
			if _blocked[c.y * _gw + n.x] != 0 or _blocked[n.y * _gw + c.x] != 0:
				continue
		if d < best:
			best = d
			best_off = o
	if best_off == Vector2i.ZERO:
		return dir
	var here := _dist[c.y * _gw + c.x]
	if here >= 0 and best >= here:
		return dir  # already at a local minimum (next to the player): go straight
	# Aim for the CENTRE of the best neighbour cell (not just its direction): cell centres keep at
	# least INFLATE clear of walls, so bodies hug corridor middles instead of catching wall ends.
	var nc := _cell_center(c + best_off)
	var out := Vector3(nc.x - from.x, 0.0, nc.y - from.z)
	out = out.normalized() if out.length_squared() > 0.01 else Vector3(best_off.x, 0.0, best_off.y).normalized()
	if here >= 0:
		# Central-difference gradient of the distance field, with walls counted as "uphill": it
		# smooths the 45-degree steps and pushes bodies off wall faces, so they slide instead of
		# pinning themselves against a hedge or house corner.
		var gx := _flow_val(c + Vector2i(-1, 0), here) - _flow_val(c + Vector2i(1, 0), here)
		var gz := _flow_val(c + Vector2i(0, -1), here) - _flow_val(c + Vector2i(0, 1), here)
		var g := Vector3(gx, 0.0, gz)
		if g.length_squared() > 0.0001:
			var blended := (out + g.normalized() * 0.8).normalized()
			# ...but never if the blend would clip a corner the pure grid direction avoids
			var sd := Vector3(-blended.z, 0.0, blended.x) * 0.45
			if not _blocked_at(from + blended * 0.8 + sd) and not _blocked_at(from + blended * 0.8 - sd):
				out = blended
	return out


func _flow_val(n: Vector2i, here: int) -> float:
	if not _in_grid(n):
		return float(here) + 2.0
	var d := _dist[n.y * _gw + n.x]
	return float(here) + 2.0 if d < 0 else float(d)


## See Maps.unstick(). Picks, among the open cells of the 3x3 block around the body, the one with
## the lowest flow distance (ties: most aligned with `dir`) and returns the direction to its centre.
func unstick(from: Vector3, dir: Vector3) -> Vector3:
	if not _has_nav:
		return Vector3.ZERO
	var c := _cell_of(from)
	if not _in_grid(c):
		return Vector3.ZERO
	var near_wall := _blocked[c.y * _gw + c.x] != 0
	for o in N8:
		var n := c + o
		if not _in_grid(n) or _blocked[n.y * _gw + n.x] != 0:
			near_wall = true
	if not near_wall:
		return Vector3.ZERO
	var best_score := INF
	var best := Vector3.ZERO
	for o: Vector2i in [Vector2i.ZERO] + N8:
		var n := c + o
		if not _in_grid(n) or _blocked[n.y * _gw + n.x] != 0:
			continue
		var cc := _cell_center(n)
		var to := Vector3(cc.x - from.x, 0.0, cc.y - from.z)
		if to.length_squared() < 0.04:
			continue  # already at that centre
		var d := _dist[n.y * _gw + n.x]
		var score := (float(d) if d >= 0 else 999.0) - to.normalized().dot(dir) * 0.5
		if score < best_score:
			best_score = score
			best = to.normalized()
	return best


func is_walkable(pos: Vector3) -> bool:
	if bounds_kind == Bounds.NONE:
		return true
	if not _has_nav:
		return _inside_bounds(Vector2(pos.x, pos.z), 0.5)
	return not _blocked_at(pos)


func clamp_to_bounds(pos: Vector3) -> Vector3:
	if bounds_kind == Bounds.NONE or is_walkable(pos):
		return pos
	var p := Vector2(pos.x, pos.z)
	if not _inside_bounds(p, 1.0):
		var center := bounds_rect().get_center() if bounds_kind != Bounds.CIRCLE else bounds_center
		# walk toward the centre until inside
		for i in 40:
			p = p.lerp(center, 0.08)
			if _inside_bounds(p, 1.5):
				break
	var c := _cell_of(Vector3(p.x, 0.0, p.y))
	# spiral search for the nearest open cell
	for r in range(0, 12):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var n := c + Vector2i(dx, dy)
				if _in_grid(n) and _blocked[n.y * _gw + n.x] == 0:
					var q := _cell_center(n)
					return Vector3(q.x, pos.y, q.y)
	return Vector3(p.x, pos.y, p.y)


func random_point(around: Vector3, min_dist: float = 0.0, max_dist: float = 30.0) -> Vector3:
	for _i in 40:
		var a := randf() * TAU
		var r := randf_range(min_dist, max_dist)
		var p := around + Vector3(cos(a) * r, 0.0, sin(a) * r)
		if is_walkable(p):
			return p
	return clamp_to_bounds(around)


func spawn_position(ideal: Vector3, allow_authored: bool = true) -> Vector3:
	if bounds_kind == Bounds.NONE:
		return ideal
	var f := _focus()
	if allow_authored and randf() < AUTHORED_SPAWN_CHANCE:
		var cands: Array[Node3D] = []
		for sp in get_enemy_spawn_points():
			var d := Vector2(sp.global_position.x - f.x, sp.global_position.z - f.z).length()
			if d >= SPAWN_MIN_DIST and d <= SPAWN_MAX_DIST:
				cands.append(sp)
		if not cands.is_empty():
			var sp := cands[randi() % cands.size()]
			var p := sp.global_position + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))
			if is_walkable(p):
				return Vector3(p.x, 0.0, p.z)
	if is_walkable(ideal):
		return ideal
	var off := ideal - f
	off.y = 0.0
	var r := maxf(off.length(), 1.0)
	# same ring, other angles (enemies come from the open side when the player hugs a wall)
	for i in 20:
		var a := randf() * TAU
		var scl := randf_range(0.95, 1.2) if i < 12 else randf_range(0.6, 0.95)
		var p := f + Vector3(cos(a), 0.0, sin(a)) * r * scl
		if is_walkable(p):
			return p
	return clamp_to_bounds(ideal)


# ================================================================ merge + lights

func _merge_scenery() -> void:
	var groups := {}  # key -> {st, mat, shadow, bucket}
	var merged: Array[MeshInstance3D] = []
	_collect(scenery, Transform3D.IDENTITY, groups, merged)
	for mi in merged:
		mi.get_parent().remove_child(mi)
		mi.free()
	for key: String in groups:
		var g: Dictionary = groups[key]
		var mi := MeshInstance3D.new()
		mi.mesh = (g["st"] as SurfaceTool).commit()
		mi.material_override = g["mat"]
		mi.cast_shadow = g["shadow"]
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		scenery.add_child(mi)
	# drop prop roots that are now empty
	for c in scenery.get_children():
		if c is Node3D and not c is MeshInstance3D and not c is Light3D and _is_empty(c):
			c.queue_free()


func _is_empty(n: Node) -> bool:
	for c in n.get_children():
		if c.get_class() != "Node3D" or not _is_empty(c):
			return false
	return true


func _collect(node: Node, xf: Transform3D, groups: Dictionary, merged: Array[MeshInstance3D]) -> void:
	for c in node.get_children():
		if not c is Node3D:
			continue
		var n3 := c as Node3D
		var cxf := xf * n3.transform
		if c is MeshInstance3D and _mergeable(c as MeshInstance3D):
			var mi := c as MeshInstance3D
			var bucket := Vector2i(floori(cxf.origin.x / BUCKET), floori(cxf.origin.z / BUCKET))
			var key := "%d|%d|%d|%d" % [mi.material_override.get_instance_id(), mi.cast_shadow, bucket.x, bucket.y]
			if not groups.has(key):
				groups[key] = {"st": SurfaceTool.new(), "mat": mi.material_override, "shadow": mi.cast_shadow}
			(groups[key]["st"] as SurfaceTool).append_from(mi.mesh, 0, cxf)
			merged.append(mi)
		_collect(c, cxf, groups, merged)


func _mergeable(mi: MeshInstance3D) -> bool:
	if mi.has_meta(&"keep") or mi.mesh == null or mi.material_override == null:
		return false
	var m := mi.material_override
	if m is StandardMaterial3D:
		return true
	if m is ShaderMaterial:
		return (m as ShaderMaterial).shader == Art.LIT_STATIC
	return false


func _register_lights(root: Node) -> void:
	if root is OmniLight3D:
		var l := root as OmniLight3D
		l.visible = false
		l.set_meta(&"w", 0.0)
		l.set_meta(&"phase", randf() * TAU)
		_lights.append(l)
	for c in root.get_children():
		_register_lights(c)


func _update_lights(delta: float) -> void:
	_light_timer -= delta
	if _light_timer <= 0.0:
		_light_timer = 0.25
		var f := _focus()
		var sorted := _lights.filter(func(l: OmniLight3D) -> bool: return is_instance_valid(l))
		sorted.sort_custom(func(a: OmniLight3D, b: OmniLight3D) -> bool:
			return a.global_position.distance_squared_to(f) < b.global_position.distance_squared_to(f))
		for i in sorted.size():
			var l: OmniLight3D = sorted[i]
			var on := i < MAX_LIGHTS and l.global_position.distance_to(f) < LIGHT_RANGE
			l.set_meta(&"target", 1.0 if on else 0.0)
	for l in _lights:
		if not is_instance_valid(l):
			continue
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
		var f := 1.0
		if l.has_meta(&"pulse"):
			f = 0.75 + 0.25 * sin(_time * 1.4 + ph)
		elif not l.has_meta(&"steady"):
			f = 0.82 + 0.1 * sin(_time * 9.0 + ph) + 0.08 * sin(_time * 23.0 + ph * 2.3) * sin(_time * 3.1 + ph)
		l.light_energy = float(l.get_meta(&"base_energy", 2.0)) * w * f


# ================================================================ debug

## Nav-grid summary for tests: {cells, blocked, size}.
func nav_stats() -> Dictionary:
	var blocked := 0
	for v in _blocked:
		blocked += v
	return {"cells": _gw * _gh, "blocked": blocked, "size": Vector2i(_gw, _gh)}
