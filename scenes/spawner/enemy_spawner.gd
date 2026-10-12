class_name EnemySpawner
extends Node
## Spawns enemies on an ellipse just outside the camera view. The base spawn rate grows over
## time; enemy HP / damage / speed scale with RunState's difficulty (minutes survived + heat).
## A boss arrives every `boss_time` seconds (normal spawns run at half rate while it lives).
##
## Wave pacing: the run is cut into `wave_length`-second waves, each with three phases that
## multiply the spawn rate and are reported through RunState.set_wave() (-> wave_started):
##   build  ramps from build_rate_start to build_rate_end   (pressure grows)
##   surge  surge_rate; opens with a horde ring closing in from every side + an elite
##   lull   lull_rate; a breather to collect souls before the next wave
## Debug builds: F3 = spawn the boss right now.

const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")
const DEFAULT_BOSS_PATH := "res://data/bosses/sariel.tres"
const DEFAULT_BOSS_SCENE_PATH := "res://scenes/bosses/boss.tscn"

@export var rules: Array[SpawnRule] = []
@export var max_enemies := 300
@export_group("Rate")
## Enemies per second at the start of the run.
@export var base_rate := 0.9
## Added enemies-per-second for every second survived.
@export var rate_growth := 0.028
@export_group("Waves")
@export var wave_length := 60.0
## Seconds into each wave at which the surge starts and ends (the rest is the lull).
@export var surge_start := 36.0
@export var surge_end := 50.0
@export var build_rate_start := 0.75
@export var build_rate_end := 1.15
@export var surge_rate := 2.2
@export var lull_rate := 0.35
## Horde ring at the start of a surge: base size + per wave, capped.
@export var ring_base := 8
@export var ring_per_wave := 3
@export var ring_max := 30
@export_group("Elite")
@export var elite: EnemyData
## Kept for compatibility: elites now arrive at the start of each surge.
@export var elite_interval := 60.0
@export_group("Placement")
## Half-extents of the spawn ellipse (X = screen horizontal, Z = screen vertical).
@export var spawn_radius := Vector2(38, 28)  # just off-screen at CameraRig.distance 36
@export_group("Boss")
## Boss EnemyData (defaults to Sariel, Herald of the Last Dawn).
@export var boss: EnemyData
## Boss scene: a CharacterBody3D with a Boss script (defaults to res://scenes/bosses/boss.tscn).
@export var boss_scene: PackedScene
## First boss at this time, then another every `boss_time` seconds.
@export var boss_time := 300.0
## Distance from the player at which the boss descends (kept on screen so the intro is seen).
@export var boss_spawn_distance := 9.0
## Extra boss HP multiplier for every boss already spawned this run.
@export var boss_hp_step := 0.5
## Normal spawn-rate multiplier while a boss is alive.
@export var boss_spawn_rate_scale := 0.5

var _accum := 0.0
var _next_boss := 0.0
var _boss_count := 0
var _wave := 0
var _phase: StringName = &""


func _ready() -> void:
	_next_boss = boss_time
	if boss == null:
		boss = load(DEFAULT_BOSS_PATH) as EnemyData
	if boss_scene == null:
		boss_scene = load(DEFAULT_BOSS_SCENE_PATH) as PackedScene


func _process(delta: float) -> void:
	var player := Game.player
	if player == null or player.is_dead or not RunState.active:
		return
	var t := Game.elapsed
	var boss_alive := is_boss_alive()
	_update_wave(t, boss_alive)
	var rate := (base_rate + rate_growth * t) * phase_rate(t) * RunState.spawn_rate_mult()
	if boss_alive:
		rate *= boss_spawn_rate_scale
	_accum += rate * delta
	while _accum >= 1.0:
		_accum -= 1.0
		# [maps] breakable map statues (group map_features) are not angels: they never fill the cap
		if get_tree().get_node_count_in_group(&"enemies") - get_tree().get_node_count_in_group(&"map_features") >= max_enemies:
			_accum = 0.0
			break
		var data := _pick(t)
		if data:
			spawn(data)
	if boss and boss_scene and t >= _next_boss:
		if boss_alive:
			_next_boss = t + 30.0  # one boss at a time: try again a bit later
		else:
			_next_boss += boss_time
			spawn_boss()


## Spawns `data` at a random point of the spawn ellipse (or at `angle` radians, if given).
func spawn(data: EnemyData, angle := NAN) -> Enemy:
	var e: Enemy = ENEMY_SCENE.instantiate()
	e.setup(data, RunState.enemy_hp_mult(), RunState.enemy_damage_mult(), RunState.enemy_speed_mult())
	var a := randf() * TAU if is_nan(angle) else angle
	var offset := Vector3(cos(a) * spawn_radius.x, 0.0, sin(a) * spawn_radius.y) * randf_range(1.0, 1.15)
	# Horde rings (explicit angle) keep their formation: no redirect to the map's gate spawn points.
	Game.spawn(e, Maps.spawn_position(Game.player.global_position + offset, is_nan(angle)))
	return e


# ---------------------------------------------------------------- wave pacing

## Wave number (1-based) and phase at run time `t`.
func wave_at(t: float) -> int:
	return int(t / wave_length) + 1


func phase_at(t: float) -> StringName:
	var w := fmod(t, wave_length)
	if w < surge_start:
		return &"build"
	if w < surge_end:
		return &"surge"
	return &"lull"


## Spawn-rate multiplier of the pacing phase at time `t`.
func phase_rate(t: float) -> float:
	var w := fmod(t, wave_length)
	match phase_at(t):
		&"build":
			return lerpf(build_rate_start, build_rate_end, w / maxf(surge_start, 0.01))
		&"surge":
			# The first surge is gentler: the demon has one weapon.
			return surge_rate * (0.7 if wave_at(t) == 1 else 1.0)
	return lull_rate


func _update_wave(t: float, boss_alive: bool) -> void:
	var w := wave_at(t)
	var ph := phase_at(t)
	if w == _wave and ph == _phase:
		return
	_wave = w
	_phase = ph
	RunState.set_wave(w, ph)
	if ph == &"surge" and not boss_alive:
		if w > 1:  # wave 1's surge stays quiet: the run intro banners are still up
			_announce_surge(w)
		_spawn_ring(w)
		if elite:
			spawn(elite)


func _announce_surge(w: int) -> void:
	var hud := get_tree().get_first_node_in_group(&"hud")
	if hud and hud.has_method(&"toast"):
		hud.toast("The Host gathers  -  Wave %s" % TextFormat.roman(w), Color("e8d6a6"))
	get_tree().call_group(&"camera_rig", &"shake", 0.12)
	Sfx.play(&"choir", 0.0, -3.0)


## A ring of melee angels closing in from every side: forces the demon to dash out.
func _spawn_ring(w: int) -> void:
	var pool: Array[EnemyData] = []
	for r in rules:
		if r.is_active(Game.elapsed) and r.enemy and r.enemy.behavior == EnemyData.Behavior.CHASE:
			pool.append(r.enemy)
	if pool.is_empty():
		return
	var count := mini(ring_base + ring_per_wave * (w - 1), ring_max)
	count = mini(count, max_enemies - get_tree().get_node_count_in_group(&"enemies") + get_tree().get_node_count_in_group(&"map_features"))  # [maps]
	var start := randf() * TAU
	for i in count:
		spawn(pool.pick_random(), start + TAU * float(i) / float(maxi(count, 1)))


func is_boss_alive() -> bool:
	return get_tree().get_first_node_in_group(&"boss") != null


## Spawns the boss `boss_spawn_distance` away (toward the top of the screen). The Boss runs its
## own intro (descent in a pillar of light, name toast, Sfx boss_intro).
func spawn_boss() -> Enemy:
	if boss == null or boss_scene == null or Game.player == null:
		return null
	# Any Enemy-based boss scene (Boss = Sariel, InquisitorBoss, ...; roster in data/bosses/bosses.json).
	var inst := boss_scene.instantiate()
	var b := inst as Enemy
	if b == null:
		push_warning("EnemySpawner.boss_scene is not an Enemy-based boss")
		inst.free()
		return null
	b.setup(boss, 1.0 + boss_hp_step * float(_boss_count))
	_boss_count += 1
	var a := -PI / 2.0 + randf_range(-0.9, 0.9)  # -Z = up on screen: it descends ahead of the player
	var offset := Vector3(cos(a), 0.0, sin(a)) * boss_spawn_distance
	Game.spawn(b, Maps.clamp_to_bounds(Game.player.global_position + offset))
	return b


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_F3:
		if Game.player and not Game.player.is_dead:
			spawn_boss()
		get_viewport().set_input_as_handled()


func _pick(t: float) -> EnemyData:
	var total := 0.0
	for r in rules:
		if r.is_active(t):
			total += r.weight
	if total <= 0.0:
		return null
	var roll := randf() * total
	for r in rules:
		if r.is_active(t):
			roll -= r.weight
			if roll <= 0.0:
				return r.enemy
	return null
