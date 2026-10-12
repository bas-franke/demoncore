extends Node
## Run state + gameplay event hub (autoload "RunState"). Owned by the core-gameplay role
## (docs/team/gameplay.md). Game keeps the low-level per-frame signals (enemy_hit, player_hit, ...);
## RunState is the stable, higher-level API the abilities / objectives / audio / UI / meta systems
## should hook into.
##
## Lifecycle: main.gd calls RunState.start_run() after Game.reset(). The run ends exactly once,
## through end_run(): on death (Player.died, wired here), on victory (an objective calls
## RunState.end_run(true, &"victory")) or when the player abandons it from the pause menu.
## After run_ended the game-over screen offers return_to_basecamp() / restart_run().
##
## Signals (all safe to connect from any autoload or scene):
##   run_started()                                — a fresh run began (player exists)
##   run_ended(result: Dictionary)                — see _build_result() for keys
##   enemy_killed(position, data, elite: bool)    — every enemy/boss death (data: EnemyData,
##                                                  the boss's own EnemyData for bosses)
##   player_damaged(amount, hp, max_hp)           — after HP was reduced (contact ticks included)
##   player_dodged(amount)                        — a hit was negated by dash i-frames
##   player_dashed(direction: Vector3)            — the demon started a dash
##   player_died()                                — HP hit 0 (run_ended follows)
##   currency_changed(total: int, delta: int)     — run currency picked up (or spent)
##   wave_started(index: int, kind: StringName)   — spawn pacing phase: &"build" / &"surge" / &"lull"
##   difficulty_changed(tier: int)                — once per minute survived (tier = minutes + heat)

signal run_started
signal run_ended(result: Dictionary)
signal enemy_killed(position: Vector3, data: Resource, elite: bool)
signal player_damaged(amount: float, hp: float, max_hp: float)
signal player_dodged(amount: float)
signal player_dashed(direction: Vector3)
signal player_died
signal currency_changed(total: int, delta: int)
signal wave_started(index: int, kind: StringName)
signal difficulty_changed(tier: int)
## The demon survived a lethal blow at 1 HP (Player.last_stands, scenes/player/last_stand.gd).
signal last_stand
## Ascension (endless) mode after a won run: started by ascend(), ended by death (or abandon).
## ascension_ended replaces run_ended for that stretch: the run was already banked at victory.
signal ascension_started
signal ascension_ended(result: Dictionary)
signal score_changed(score: int)

## Display name of the run currency (dropped by angels, spent at Basecamp Hell shopkeepers).
const CURRENCY_NAME := "Ichor"
## Scene the run returns to when it ends. Falls back to FALLBACK_HUB_SCENE until the hub exists.
const BASECAMP_SCENE := "res://scenes/basecamp/basecamp.tscn"
const FALLBACK_HUB_SCENE := "res://scenes/menu/demon_select.tscn"
const RUN_SCENE := "res://scenes/main.tscn"
const ICHOR_SCENE := preload("res://scenes/pickups/ichor_drop.tscn")

@export_group("Currency drops")
## Chance that a regular angel drops one Ichor.
@export var drop_chance := 0.12
## Ichor dropped by an elite (always).
@export var elite_drop := 6
## Ichor dropped by a boss (always), split into several drops.
@export var boss_drop := 40

@export_group("Boss scaling")
## Boss HP multiplier added per minute survived (+ heat), applied when a boss spawns
## (Game.boss_spawned). Softer than regular enemies: bosses already step up per arrival.
@export var boss_hp_growth_per_minute := 0.12

@export_group("Difficulty")
## Enemy HP multiplier: 1 + hp_growth_per_minute * m + hp_growth_quadratic * m^2 (m = minutes
## + heat). Gentle while the demon has 1-2 weapons, steeper once abilities and synergies snowball.
## Balance pass (autopilot, ruined_sanctum): see docs/team/gameplay.md "Balance".
@export var hp_growth_per_minute := 0.28
@export var hp_growth_quadratic := 0.025
## Enemy damage multiplier added per minute survived.
@export var damage_growth_per_minute := 0.09
## Enemy move-speed multiplier added per minute survived (capped by max_speed_mult).
@export var speed_growth_per_minute := 0.02
@export var max_speed_mult := 1.3
## Minutes of scaling each point of `heat` adds (pacts carry their own effects on top).
@export var heat_minutes := 0.5

## True between start_run() and end_run().
var active := false
## Run currency carried this run (banked by the meta/basecamp system on run_ended).
var currency := 0
## Currency picked up this run (never decreases when spent).
var currency_earned := 0
## Extra difficulty set before a run (meta "heat" / curses). Each point counts as
## heat_minutes extra minutes in the scaling below (Progression sets it from its pacts).
var heat := 0
## Current spawn-pacing wave (1-based) and phase, set by EnemySpawner.
var wave := 0
var wave_kind: StringName = &""
var elites_killed := 0
var bosses_killed := 0
## Bosses alive this run (tracked from Game.boss_spawned so kills can report their EnemyData).
var _bosses: Array[Node3D] = []
var damage_taken := 0.0
var dodges := 0
var last_stands_used := 0
var dashes := 0
## Result of the last ended run (empty while a run is active).
var last_result := {}
## Basecamp scene override (the hub owner may set this at startup instead of using BASECAMP_SCENE).
var basecamp_scene := BASECAMP_SCENE

var _tier := 0

@export_group("Ascension")
## Per minute of ascension, enemy HP / damage / spawn rate multiply by these (exponential).
@export var ascension_hp_base := 1.45
@export var ascension_damage_base := 1.15
@export var ascension_rate_base := 1.12
## Score: points per kill (x ascension_kill_growth per minute) and per second survived.
@export var ascension_kill_points := 10.0
@export var ascension_kill_growth := 1.3
@export var ascension_time_points := 20.0

## True while playing on after a victory (Ascension mode).
var ascending := false
var ascension_score := 0
var ascension_start := 0.0
var _asc_score_f := 0.0
var _asc_tier := -1
const ASCENSION_SAVE := "ascension.json"
const SAVES := preload("res://scripts/save_profile.gd")


func _ready() -> void:
	# Game's raw signals are re-published here with run bookkeeping.
	Game.enemy_died.connect(_on_enemy_died)
	Game.boss_died.connect(_on_boss_died)
	Game.boss_spawned.connect(_on_boss_spawned)
	Game.player_hit.connect(_on_player_hit)


func _process(delta: float) -> void:
	if not active:
		return
	if ascending:
		_asc_score_f += ascension_time_points * delta
		_update_score()
		var at := int(ascension_minutes())
		if at != _asc_tier:
			_asc_tier = at
			if at > 0:
				_toast("Ascension %d  -  the Host grows desperate" % (at + 1), Color("ff7a3a"))
	var t := difficulty_tier()
	if t != _tier:
		_tier = t
		difficulty_changed.emit(t)


# ---------------------------------------------------------------- lifecycle

## Called by main.gd once the player exists. Resets all per-run state.
func start_run() -> void:
	active = true
	currency = 0
	currency_earned = 0
	wave = 0
	wave_kind = &""
	elites_killed = 0
	bosses_killed = 0
	_bosses.clear()
	damage_taken = 0.0
	dodges = 0
	last_stands_used = 0
	ascending = false
	ascension_score = 0
	_asc_score_f = 0.0
	dashes = 0
	last_result = {}
	_tier = difficulty_tier()
	var p := Game.player
	if p and not p.died.is_connected(_on_player_died):
		p.died.connect(_on_player_died)
	run_started.emit()


## Ends the run once (later calls are ignored). `cause`: &"slain", &"victory", &"abandoned", ...
## Returns the result dictionary.
func end_run(victory: bool, cause: StringName = &"") -> Dictionary:
	if not active:
		return last_result
	if ascending:
		return _end_ascension(cause)
	active = false
	if cause == &"":
		cause = &"victory" if victory else &"slain"
	last_result = _build_result(victory, cause)
	if OS.is_debug_build():
		print("[RunState] run ended: %s at %.0fs, wave %d, %d kills, level %d, %d %s" % [cause,
			Game.elapsed, wave, Game.kills, int(last_result.level), currency, CURRENCY_NAME])
	run_ended.emit(last_result)
	return last_result


func _build_result(victory: bool, cause: StringName) -> Dictionary:
	var p := Game.player
	return {
		"victory": victory,
		"cause": cause,
		"time": Game.elapsed,
		"kills": Game.kills,
		"elites": elites_killed,
		"bosses": bosses_killed,
		"level": p.level if is_instance_valid(p) else 1,
		"wave": wave,
		"currency": currency,
		"currency_earned": currency_earned,
		"damage_taken": damage_taken,
		"dodges": dodges,
		"character": Game.selected_character,
	}


## True after the run ended in victory (the player can no longer be hurt).
func run_won() -> bool:
	return not active and bool(last_result.get("victory", false))


## Leaves the run for the Basecamp Hell hub (or the demon select until the hub exists).
func return_to_basecamp() -> void:
	if active:
		end_run(false, &"abandoned")
	var tree := get_tree()
	tree.paused = false
	Game._end_hitstop()
	var path := basecamp_scene if ResourceLoader.exists(basecamp_scene) else FALLBACK_HUB_SCENE
	tree.change_scene_to_file(path)


## Starts a fresh run with the same demon (on the map selected in Meta, when it exists).
func restart_run() -> void:
	if active:
		end_run(false, &"abandoned")
	var tree := get_tree()
	tree.paused = false
	Game._end_hitstop()
	var meta := get_node_or_null(^"/root/Meta")
	if meta and meta.has_method(&"start_run"):
		meta.call(&"start_run")
	else:
		tree.change_scene_to_file(RUN_SCENE)


# ---------------------------------------------------------------- currency

func add_currency(amount: int) -> void:
	if amount == 0 or (not active and amount > 0 and Game.player != null):
		return  # pickups landing after the run ended don't change the banked result
	currency = maxi(currency + amount, 0)
	if amount > 0:
		currency_earned += amount
	currency_changed.emit(currency, amount)


## Spends run currency (e.g. an in-run shrine). Returns false if there is not enough.
func spend_currency(amount: int) -> bool:
	if amount > currency:
		return false
	add_currency(-amount)
	return true


## Drops `amount` Ichor as up to `pieces` pickups scattered around `at`.
func drop_currency(at: Vector3, amount: int, pieces: int = 1) -> void:
	if amount <= 0 or Game.world == null:
		return
	pieces = clampi(pieces, 1, amount)
	@warning_ignore("integer_division")  # whole units per piece; the remainder goes below
	var each := amount / pieces
	var rest := amount - each * pieces
	for i in pieces:
		var d := ICHOR_SCENE.instantiate()
		d.value = each + (1 if i < rest else 0)
		var off := Vector3.ZERO
		if pieces > 1:
			var a := TAU * float(i) / float(pieces) + randf() * 0.5
			off = Vector3(cos(a), 0.0, sin(a)) * randf_range(0.5, 1.6)
		# Deferred: deaths usually happen inside physics callbacks, where areas can't be added.
		Game.spawn.call_deferred(d, at + off + Vector3(0.0, 0.35, 0.0))


# ---------------------------------------------------------------- difficulty

## Minutes survived + heat. Drives the multipliers below; emitted as difficulty_changed.
func difficulty_tier() -> int:
	return int(_minutes())


func _minutes() -> float:
	return Game.elapsed / 60.0 + float(heat) * heat_minutes + map_difficulty_minutes()  # [maps] offset


# [maps] Per-map difficulty offset (maps role, docs/team/maps.md): the live map's
# "difficulty_minutes" (data/maps/*.json) - a harder map plays as if that many minutes had already
# been survived (HP / damage / speed scaling and the difficulty tier). 0 outside a run.
func map_difficulty_minutes() -> float:
	var maps := get_node_or_null(^"/root/Maps")
	if maps == null:
		return 0.0
	var def: Variant = maps.get(&"current_def")
	return float((def as Dictionary).get("difficulty_minutes", 0.0)) if def is Dictionary else 0.0


func enemy_hp_mult() -> float:
	var m := _minutes()
	var asc := pow(ascension_hp_base, ascension_minutes()) if ascending else 1.0
	return (1.0 + hp_growth_per_minute * m + hp_growth_quadratic * m * m) * asc


func enemy_damage_mult() -> float:
	var asc := pow(ascension_damage_base, ascension_minutes()) if ascending else 1.0
	return (1.0 + damage_growth_per_minute * _minutes()) * asc


func enemy_speed_mult() -> float:
	return minf(1.0 + speed_growth_per_minute * _minutes(), max_speed_mult)


# ---------------------------------------------------------------- feel helpers
# Thin wrappers so any system can add impact without knowing the camera rig. All camera motion
# respects Settings.screen_shake (the rig scales it); hitstop is Game.hitstop (capped, merged).

## Trauma shake, 0..1 (stacks; ~0.1 light, 0.3 heavy, 0.6+ huge).
func shake(trauma: float) -> void:
	get_tree().call_group(&"camera_rig", &"shake", trauma)


## Spring kick of the camera toward `world_pos` from the player (strength ~0.3..1).
func kick_toward(world_pos: Vector3, strength: float) -> void:
	var p := Game.player
	if not is_instance_valid(p):
		return
	var d := world_pos - p.global_position
	d.y = 0.0
	if d.length_squared() > 0.01:
		get_tree().call_group(&"camera_rig", &"kick", d.normalized(), strength)


## Hitstop + shake in one call for "big impact" moments (ability finishers, executes).
func impact(strength: float = 0.5) -> void:
	strength = clampf(strength, 0.0, 1.0)
	Game.hitstop(lerpf(0.03, 0.08, strength), 0.05)
	shake(lerpf(0.08, 0.35, strength))


# ---------------------------------------------------------------- hooks from gameplay

## EnemySpawner reports its pacing phase here.
func set_wave(index: int, kind: StringName) -> void:
	wave = index
	wave_kind = kind
	wave_started.emit(index, kind)


## Player.gd reports dashes / dodges here.
func notify_dash(direction: Vector3) -> void:
	dashes += 1
	player_dashed.emit(direction)


func notify_last_stand() -> void:
	last_stands_used += 1
	last_stand.emit()


func notify_dodge(amount: float) -> void:
	dodges += 1
	player_dodged.emit(amount)


func _on_enemy_died(pos: Vector3, data: Resource) -> void:
	var ed := data as EnemyData
	var elite := ed != null and ed.xp_value >= Enemy.ELITE_XP
	if elite:
		elites_killed += 1
		drop_currency(pos, elite_drop, 3)
	elif randf() < drop_chance:
		drop_currency(pos, 1)
	enemy_killed.emit(pos, data, elite)
	_on_ascension_kill(data)


## True if `data` belongs to a boss spawned this run (enemy_killed passes boss data too).
func is_boss_data(data: Resource) -> bool:
	if data == null:
		return false
	for b in _bosses:
		if is_instance_valid(b) and b.get(&"data") == data:
			return true
	return data.resource_path.begins_with("res://data/bosses/")


func boss_hp_mult() -> float:
	return 1.0 + boss_hp_growth_per_minute * _minutes()


## Scales every boss's HP once, whoever spawned it (EnemySpawner timer, ObjectiveDirector, F3).
func _on_boss_spawned(boss: Node3D) -> void:
	# filter() returns an untyped Array (assign() keeps _bosses typed); freed entries are Variants.
	_bosses.assign(_bosses.filter(func(b: Variant) -> bool: return is_instance_valid(b)))
	_bosses.append(boss)
	if boss.has_meta(&"run_scaled") or not (&"max_hp" in boss):
		return
	boss.set_meta(&"run_scaled", true)
	var m := boss_hp_mult()
	boss.set(&"max_hp", float(boss.get(&"max_hp")) * m)
	boss.set(&"hp", float(boss.get(&"hp")) * m)


func _on_boss_died(pos: Vector3) -> void:
	bosses_killed += 1
	drop_currency(pos, boss_drop, 8)
	# Game.boss_died only carries a position: match it to the tracked boss (dying one, else nearest).
	var data: Resource = null
	var best := INF
	for b in _bosses:
		if not is_instance_valid(b):
			continue
		var d := b.global_position.distance_squared_to(pos)
		if bool(b.get(&"is_dying")):
			d -= 1e6
		if d < best:
			best = d
			data = b.get(&"data") as Resource
	enemy_killed.emit(pos, data, true)


func _on_player_hit(amount: float) -> void:
	damage_taken += amount
	var p := Game.player
	if is_instance_valid(p):
		player_damaged.emit(amount, p.hp, p.max_hp)


# ---------------------------------------------------------------- ascension (endless)

## A won run can go on for score ("Ascend" on the victory screen). Enemies scale exponentially
## with ascension minutes; the end comes only by death (or abandoning). Rewards were banked at the
## victory; the ascension adds a best score per map (SaveProfile ascension.json).
func can_ascend() -> bool:
	return run_won() and is_instance_valid(Game.player) and not Game.player.is_dead


func ascend() -> bool:
	if not can_ascend():
		return false
	active = true
	ascending = true
	ascension_start = Game.elapsed
	ascension_score = 0
	_asc_score_f = 0.0
	_asc_tier = -1
	get_tree().paused = false
	if get_tree().get_first_node_in_group(&"ascension_hud") == null and get_tree().current_scene:
		get_tree().current_scene.add_child(load("res://scenes/ui/ascension_score.gd").new())
	ascension_started.emit()
	_toast("ASCENSION  -  play on for glory", Color("ff7a3a"))
	return true


## Minutes since ascend() (0 outside Ascension).
func ascension_minutes() -> float:
	return (Game.elapsed - ascension_start) / 60.0 if ascending else 0.0


## Extra spawn-rate multiplier for EnemySpawner (1 outside Ascension).
func spawn_rate_mult() -> float:
	return pow(ascension_rate_base, ascension_minutes()) if ascending else 1.0


func _on_ascension_kill(data: Resource) -> void:
	if not ascending or not active:
		return
	var pts := ascension_kill_points * pow(ascension_kill_growth, ascension_minutes())
	if data != null and data is EnemyData and (data as EnemyData).xp_value >= Enemy.ELITE_XP:
		pts *= 5.0
	_asc_score_f += pts
	_update_score()


func _update_score() -> void:
	var sc := int(_asc_score_f)
	if sc != ascension_score:
		ascension_score = sc
		score_changed.emit(sc)


func _end_ascension(cause: StringName) -> Dictionary:
	active = false
	ascending = false
	var map_id := _map_id()
	var best := _load_best()
	var prev := int(best.get(map_id, 0))
	var is_best := ascension_score > prev
	if is_best:
		best[map_id] = ascension_score
		_save_best(best)
	var r := last_result.duplicate()
	r.merge({
		"victory": true,
		"cause": &"ascension" if cause == &"slain" else cause,
		"ascension": true,
		"ascension_time": Game.elapsed - ascension_start,
		"ascension_score": ascension_score,
		"ascension_best": maxi(prev, ascension_score),
		"ascension_new_best": is_best,
		"time": Game.elapsed,
		"kills": Game.kills,
	}, true)
	last_result = r
	ascension_ended.emit(r)
	return r


## Best Ascension score on the current map (0 if none).
func best_ascension_score() -> int:
	return int(_load_best().get(_map_id(), 0))


func _map_id() -> String:
	var maps := get_node_or_null(^"/root/Maps")
	return str(maps.get(&"selected_id")) if maps else "default"


func _load_best() -> Dictionary:
	var text := FileAccess.get_file_as_string(SAVES.path(ASCENSION_SAVE))
	var parsed: Variant = JSON.parse_string(text) if text != "" else null
	return parsed if parsed is Dictionary else {}


func _save_best(best: Dictionary) -> void:
	var path: String = SAVES.path(ASCENSION_SAVE)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(best, "  "))


func _toast(text: String, color: Color) -> void:
	var hud := get_tree().get_first_node_in_group(&"hud")
	if hud and hud.has_method(&"toast"):
		hud.call(&"toast", text, color)


func _on_player_died() -> void:
	player_died.emit()
	end_run(false, &"slain")
