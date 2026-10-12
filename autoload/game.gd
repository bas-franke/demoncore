extends Node
## Global run state shared by every system. main.gd resets it at the start of each run.

## Gameplay events for decoupled systems (decals, VFX, audio, game feel). Emitters:
##   enemy_died      — Enemy.die()           (position, EnemyData)
##   enemy_hit       — Enemy.take_damage()   (position, amount)
##   player_hit      — Player.take_damage()  (amount)
##   boss_spawned / boss_died — Boss
# They are emitted from other scripts, so silence the "unused signal" warning for this block.
@warning_ignore_start("unused_signal")
signal enemy_died(position: Vector3, data: Resource)
signal enemy_hit(position: Vector3, amount: float)
signal player_hit(amount: float)
signal boss_spawned(boss: Node3D)
signal boss_died(position: Vector3)
## Objectives (ObjectiveDirector, docs/team/objectives.md): id from data/objectives/objectives.json.
signal objective_started(id: StringName)
signal objective_completed(id: StringName, rewards: Dictionary)
signal objective_failed(id: StringName)
## Multi-phase bosses (InquisitorBoss, Boss): phase index 0.. when it changes (0 = first phase).
signal boss_phase_changed(boss: Node3D, phase: int)
## Enemy.take_damage(), right after enemy_hit: same hit, with the enemy itself (audio picks the
## surface sound from enemy.data; docs/team/sfx.md).
signal enemy_struck(enemy: Node3D, amount: float)
## characters-new (round 4): an enemy regained health through Enemy.heal() (support angels, miracles).
signal enemy_healed(enemy: Node3D, amount: float)
@warning_ignore_restore("unused_signal")

var player: Player
## Parent node for everything spawned at runtime (enemies, projectiles, pickups, popups).
var world: Node3D
var elapsed := 0.0
var kills := 0
var show_damage_numbers := true
## Character chosen on the select screen (DemonData). Null = Player.default_character.
var selected_character: Resource

# Dev/testing flags, set from command-line user args (see main.gd).
var autopilot := false
## Test flag (--godmode): the player takes no damage, so late-game screenshots are possible.
var godmode := false


func _ready() -> void:
	var shot_path := ""
	var shot_time := 5.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--demon="):
			selected_character = load("res://data/demons/%s.tres" % arg.substr(8))
		elif arg == "--autopilot":
			autopilot = true
		elif arg == "--godmode":
			godmode = true
		elif arg.begins_with("--shot="):
			shot_path = arg.substr(7)
		elif arg.begins_with("--shot-time="):
			shot_time = arg.substr(12).to_float()
	if shot_path != "":
		# process_always timer, so it fires even while a menu has the game paused.
		await get_tree().create_timer(shot_time, true).timeout
		get_viewport().get_texture().get_image().save_png(shot_path)
		get_tree().quit()


func reset() -> void:
	player = null
	world = null
	elapsed = 0.0
	kills = 0
	_end_hitstop()


# ---------------------------------------------------------------- hitstop
# A brief freeze-frame (Engine.time_scale dip) restored by a real-time timer. Overlapping calls
# extend the current stop instead of stacking; the deepest requested scale wins. Skipped while the
# tree is paused (menus) and ended at once if a menu pauses the game mid-stop.

## Hard cap so a burst of calls can never freeze the game for long.
const HITSTOP_MAX := 0.12

var _hitstop_until := 0  # Time.get_ticks_usec() when the current stop ends; 0 = none
var _hitstop_serial := 0


## Freezes time to `scale` for `duration` real seconds (keep it to ~0.03..0.08).
func hitstop(duration: float, scale: float = 0.05) -> void:
	if duration <= 0.0 or not is_inside_tree() or get_tree().paused:
		return
	duration = minf(duration, HITSTOP_MAX)
	scale = clampf(scale, 0.0, 1.0)
	var now := Time.get_ticks_usec()
	var until := now + int(duration * 1_000_000.0)
	if _hitstop_until > now:
		# Already stopped: extend (never shorten) and keep the deeper freeze.
		_hitstop_until = maxi(_hitstop_until, until)
		Engine.time_scale = minf(Engine.time_scale, scale)
		return
	_hitstop_until = until
	Engine.time_scale = scale
	_hitstop_serial += 1
	var serial := _hitstop_serial
	# SceneTree.process_frame fires every frame even while paused or slowed: wall-clock driven.
	var tree := get_tree()
	while serial == _hitstop_serial:
		await tree.process_frame
		if serial != _hitstop_serial:
			return  # ended elsewhere (reset)
		if tree.paused or Time.get_ticks_usec() >= _hitstop_until:
			_end_hitstop()  # a menu paused mid-stop: release at once so menus run at full speed


func is_hitstopped() -> bool:
	return _hitstop_until > 0


func _end_hitstop() -> void:
	_hitstop_until = 0
	_hitstop_serial += 1
	Engine.time_scale = 1.0


## Adds `node` to the world at `at`. Position is set before entering the tree so
## physics interpolation starts from the right place.
func spawn(node: Node3D, at: Vector3) -> void:
	if world == null:
		node.free()
		return
	node.position = at
	world.add_child(node)
