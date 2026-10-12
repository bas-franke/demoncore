class_name ObjectiveFX
extends RefCounted
## Shared helpers for objectives: the beacon column, a ground zone ring (BossTelegraph), enemy
## spawning in the same HP scaling as the regular waves, and the infernal "corruption" burst
## played when a holy thing is desecrated. Static only.

const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")
## Same default as EnemySpawner.hp_growth_per_minute (read from the live spawner when present).
const DEFAULT_HP_GROWTH := 0.35
## Above this many live enemies, objective spawns are skipped (the regular spawner caps at 300).
const ENEMY_CAP := 290

static var _enemy_cache := {}  # String id -> EnemyData (or null when missing)
static var _column_mesh: CylinderMesh


## A tall, thin additive light column standing on `parent` (its own material, so it can fade).
static func beacon(parent: Node3D, tint: Color, height: float) -> MeshInstance3D:
	if _column_mesh == null:
		_column_mesh = CylinderMesh.new()
		_column_mesh.top_radius = 0.02
		_column_mesh.bottom_radius = 0.16
		_column_mesh.height = 1.0
		_column_mesh.radial_segments = 10
		_column_mesh.rings = 1
		_column_mesh.cap_top = false
		_column_mesh.cap_bottom = false
	var mi := HolyFX.glow_part(parent, _column_mesh, tint, 0.9, Vector3(0.0, height * 0.5, 0.0),
			Vector3(1.0, height, 1.0))
	return mi


## A ground ring/disc decal (call show_disc / show_sector on it every frame you want it seen).
static func zone(parent: Node3D) -> BossTelegraph:
	var t := BossTelegraph.new()
	parent.add_child(t)
	return t


## Loads data/enemies/<id>.tres once. Null (with one warning) when missing.
static func enemy_data(enemy_id: String) -> EnemyData:
	if _enemy_cache.has(enemy_id):
		return _enemy_cache[enemy_id]
	var path := "res://data/enemies/%s.tres" % enemy_id
	var d: EnemyData = null
	if ResourceLoader.exists(path):
		d = load(path) as EnemyData
	if d == null:
		push_warning("ObjectiveFX: unknown enemy id '%s'" % enemy_id)
	_enemy_cache[enemy_id] = d
	return d


## HP multiplier the regular waves use right now.
static func wave_hp_scale() -> float:
	var growth := DEFAULT_HP_GROWTH
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.current_scene:
		var sp := tree.current_scene.get_node_or_null(^"EnemySpawner")
		if sp and &"hp_growth_per_minute" in sp:
			growth = float(sp.get(&"hp_growth_per_minute"))
	return 1.0 + growth * Game.elapsed / 60.0


## Spawns an angel by id at `at` (with a small column of light). Null if unknown or at the cap.
static func spawn_enemy(enemy_id: String, at: Vector3, hp_mult: float = 1.0) -> Enemy:
	var data := enemy_data(enemy_id)
	if data == null or Game.world == null:
		return null
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.get_node_count_in_group(&"enemies") - tree.get_node_count_in_group(&"map_features") >= ENEMY_CAP:  # [maps] statues are not angels
		return null
	return spawn_enemy_data(data, at, hp_mult)


static func spawn_enemy_data(data: EnemyData, at: Vector3, hp_mult: float = 1.0) -> Enemy:
	var e: Enemy = ENEMY_SCENE.instantiate()
	e.setup(data, wave_hp_scale() * hp_mult)
	at = walkable(at)
	Game.spawn(e, Vector3(at.x, 0.0, at.z))
	HolyFX.column(at, 0.35, 10.0, 0.5, Art.HOLY, 1.2)
	return e


## Nearest walkable spot on a bounded map (Maps autoload); unchanged on open maps.
static func walkable(at: Vector3) -> Vector3:
	var tree := Engine.get_main_loop() as SceneTree
	var maps := tree.root.get_node_or_null(^"Maps") if tree else null
	if maps and maps.has_method(&"clamp_to_bounds"):
		return maps.call(&"clamp_to_bounds", at)
	return at


## Point on a ring of `radius` around `center` at a random angle.
static func ring_point(center: Vector3, radius: float) -> Vector3:
	var a := randf() * TAU
	return Vector3(center.x + cos(a) * radius, 0.0, center.z + sin(a) * radius)


## Infernal burst: a crimson flash, a hellfire column, rising embers, a camera shake.
static func corruption_burst(at: Vector3, size: float = 1.0) -> void:
	HolyFX.flash(at + Vector3(0.0, 0.8, 0.0), 3.5 * size, 0.6, Art.HELLFIRE, 2.6)
	HolyFX.column(at, 0.9 * size, 18.0, 0.9, Art.HELLFIRE, 1.8)
	HolyFX.motes(at + Vector3(0.0, 0.3, 0.0), int(20 * size), Art.EMBER, 1.6 * size, 3.0, 1.6, 0.08)
	HolyFX.motes(at + Vector3(0.0, 0.3, 0.0), int(10 * size), Art.SOUL, 1.0 * size, 2.0, 1.2, 0.06)
	EnemyModel.shockwave(at, 3.5 * size, Art.HELLFIRE, 0.6)
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.call_group(&"camera_rig", &"shake", 0.35 * size)


## Damages every live enemy within `radius` of `at` (XZ). Returns how many were hit.
static func damage_enemies(at: Vector3, radius: float, amount: float) -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return 0
	var hit := 0
	var r2 := radius * radius
	# Perf.enemies(): the group list cached once per frame / physics step for every caller.
	for n in Perf.enemies():
		var e := n as Enemy
		if e == null or e.is_dying or e.is_in_group(&"boss"):
			continue
		var d := e.global_position - at
		d.y = 0.0
		if d.length_squared() <= r2:
			var push := d.normalized() * 6.0 if d.length_squared() > 0.01 else Vector3.ZERO
			e.take_damage(amount, push)
			hit += 1
	return hit
