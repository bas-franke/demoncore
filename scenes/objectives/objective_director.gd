class_name ObjectiveDirector
extends Node
## Gives each map things to do. Reads data/objectives/objectives.json, places mostly optional
## objectives around the demon over the run (shrines, relics, champions, sieges, caged souls,
## fleeing saints), grants their rewards and summons bosses: after a number of completed
## objectives (settings.boss_after_completions) and, through the regular EnemySpawner timer, in
## the order of settings.boss_rotation (bosses roster: data/bosses/bosses.json).
##
## Add scenes/objectives/objective_director.tscn to any run scene (it is in scenes/main.tscn).
## It owns the tracker UI and the off-screen markers (ObjectiveTracker).
##
## Find it: get_tree().get_first_node_in_group(&"objective_director") as ObjectiveDirector
## Dev args (after "--"): --objective=<id> (spawns that objective next to the demon at 2 s),
##   --summon=<boss_id> (summons that boss at 4 s), --event=<id> (RunEvents, 3 s), --no-objectives,
##   --no-events, --objectives-selftest[=bosses|=new|=events].
## Debug builds: F8 = spawn the next objective right next to the demon.

signal objective_added(objective: Objective)
signal objective_activated(objective: Objective)
signal objective_completed(objective: Objective)
signal objective_failed(objective: Objective)
## The objective node is about to leave the tree (finished and faded, or expired).
signal objective_removed(objective: Objective)
signal boss_summoned(boss: Node3D)
## Run-total meta souls earned from objectives changed.
signal souls_earned_changed(total: int)

const DATA_PATH := "res://data/objectives/objectives.json"
const BOSS_ROSTER_PATH := "res://data/bosses/bosses.json"
const TYPE_SCRIPT := "res://scenes/objectives/types/%s_objective.gd"
const GEM_SCENE := preload("res://scenes/pickups/xp_gem.tscn")
const TRACKER_SCRIPT := preload("res://scenes/objectives/objective_tracker.gd")
## Above this XP reward the reward comes as a Reliquary of Sin instead of a ring of shards.
const RELIQUARY_XP := 60.0
const BOSS_DISTANCE := 7.0
## Seconds between the herald banner and the boss's arrival.
const BOSS_HERALD_LEAD := 3.0
## Seconds between the last boss falling and the run's victory screen.
const VICTORY_DELAY := 4.5

## Map id (set it on the instance in a map scene). Definitions with a "maps" list only appear on
## those maps; "map_settings": {"<map id>": {...}} overrides settings for one map.
@export var map_id := ""
## false = no objectives (bosses still rotate on the regular timer).
@export var enabled := true

## Live objectives (dormant, active, and finished ones still fading).
var objectives: Array[Objective] = []
var completed_count := 0
## Bosses slain this run (any source).
var bosses_slain := 0
var failed_count := 0
## Meta souls granted by objectives this run.
var souls_earned := 0
var settings: Dictionary = {}
## Names of Temptation deals accepted this run (RunScore reports them).
var curses: Array[String] = []
## Mid-run events (RunEvents) and run-end scoring (RunScore), children created in _ready.
var events: RunEvents
var score: RunScore
var definitions: Array[Dictionary] = []

var _roster: Dictionary = {}  # boss id (String) -> {data, scene, herald}
var _rotation: Array[String] = []
var _rotation_i := 0
var _boss_thresholds: Array[int] = []
var _bosses_summoned := 0
var _pending_bosses: Array[String] = []
var _next_spawn := 0.0
var _scripts := {}  # type (String) -> GDScript
var _finale_cached := -1  # -1 unknown, 0 no, 1 yes
var _finale_spawned := false
var _map_gate: Node  # a map-authored SeventhGate, if the map has one
var _winning := false
var _shared_variants: Array = []
var _spawned_counts := {}  # definition id (String) -> times spawned this run
var _used_anchors := {}  # map anchor Marker3D instance id (int) -> true (each anchor hosts one objective per run)
var _anchor_ids := {}  # Vector3 -> anchor instance id (int), scratch for _pick_anchor
var _tracker: CanvasLayer


func _ready() -> void:
	add_to_group(&"objective_director")
	_load_data()
	_load_roster()
	_prewarm_scripts()  # perf: no 3-5 ms load hitch the first time each objective type appears
	_next_spawn = float(settings.get("first_delay", 6.0))
	_tracker = TRACKER_SCRIPT.new()
	_tracker.set(&"director", self)
	add_child(_tracker)
	events = RunEvents.new()
	events.name = &"RunEvents"
	events.director = self
	add_child(events)
	score = RunScore.new()
	score.name = &"RunScore"
	score.director = self
	add_child(score)
	Game.boss_spawned.connect(_on_game_boss_spawned)
	Game.boss_died.connect(_on_game_boss_died)
	_prime_spawner_boss.call_deferred()
	_find_map_gate.call_deferred()
	_dev_args.call_deferred()


func _process(delta: float) -> void:
	var p := Game.player
	if p == null or not is_instance_valid(p) or p.is_dead:
		return
	if _pending_bosses.size() > 0 and not _boss_alive():
		_summon_now(_pending_bosses.pop_front())
	if not enabled:
		return
	# Dormant objectives the demon left far behind fade, so fresh ones can appear nearby.
	var abandon := float(settings.get("abandon_distance", 85.0))
	for o in open_objectives():
		if o.state == Objective.State.DORMANT and o.age > 20.0 and not bool(o.def.get("finale", false)) \
				and o.global_position.distance_to(p.global_position) > abandon:
			o.expire()
			_next_spawn = minf(_next_spawn, 4.0)
	_try_spawn_finale()
	_next_spawn -= delta
	if _next_spawn <= 0.0:
		_next_spawn = float(settings.get("spawn_interval", 50.0))
		var want := int(settings.get("max_active", 3))
		# The opening burst: a few objectives at once so the map has choices from the start.
		var burst := int(settings.get("initial_count", 2)) if completed_count + failed_count == 0 \
				and Game.elapsed < 30.0 else 1
		for i in burst:
			if _open_count() < want:
				spawn_objective()


# ---------------------------------------------------------------- public API

## Spawns an objective (a random eligible one, or the one with `def_id`). With `near` set, it is
## placed `near` (debug / scripted); otherwise at settings.min..max_distance from the demon.
func spawn_objective(def_id: String = "", near: Vector3 = Vector3.INF) -> Objective:
	var def := _find_def(def_id) if def_id != "" else _pick_def()
	if def.is_empty():
		return null
	def = _apply_variant(def)
	return spawn_from_def(def, near if near != Vector3.INF else _pick_position(def))


## Spawns an objective from a ready definition dictionary at `at` (run events use this with
## their own definitions from data/objectives/events.json).
func spawn_from_def(def: Dictionary, at: Vector3) -> Objective:
	var script := _script_for(str(def.get("type", "")))
	if script == null:
		return null
	var obj := script.new() as Objective
	if obj == null:
		push_warning("ObjectiveDirector: %s does not extend Objective" % def.get("type"))
		return null
	obj.setup(def)
	obj.dormant_life = float(def.get("dormant_life", settings.get("dormant_life", 170.0)))
	obj.state_changed.connect(_on_objective_state_changed)
	obj.tree_exiting.connect(_on_objective_exiting.bind(obj))
	objectives.append(obj)
	_spawned_counts[String(obj.id)] = int(_spawned_counts.get(String(obj.id), 0)) + 1
	Game.spawn(obj, Vector3(at.x, 0.0, at.z))
	objective_added.emit(obj)
	return obj


## Rolls a variant for a definition (its own "variants" plus the shared `variants` list in
## objectives.json, which applies to every definition unless it sets "no_variants"). Chance:
## settings.variant_chance (+ variant_chance_per_minute, capped at 0.8). A variant:
##   {id, name, weight, color?, min_time?, types? (only these types), params: {k: v} (override),
##    param_mult: {k: x} (scales existing numeric params), reward_mult, rewards: {extra},
##    guardian: enemy id (an elite answers when the demon engages)}
## Returns a deep copy with params / rewards / title adjusted and def.variant set.
func _apply_variant(def: Dictionary) -> Dictionary:
	if bool(def.get("finale", false)) or bool(def.get("no_variants", false)):
		return def
	var chance := minf(float(settings.get("variant_chance", 0.3))
			+ float(settings.get("variant_chance_per_minute", 0.03)) * Game.elapsed / 60.0, 0.8)
	if randf() >= chance:
		return def
	var pool: Array = []
	var total := 0.0
	for v: Variant in (def.get("variants", []) as Array) + _shared_variants:
		var vd := v as Dictionary
		if vd == null or Game.elapsed < float(vd.get("min_time", 0.0)):
			continue
		var types: Array = vd.get("types", [])
		if not types.is_empty() and not str(def.get("type", "")) in types:
			continue
		pool.append(vd)
		total += float(vd.get("weight", 1.0))
	if pool.is_empty():
		return def
	var roll := randf() * total
	var pick: Dictionary = pool.back()
	for vd: Dictionary in pool:
		roll -= float(vd.get("weight", 1.0))
		if roll <= 0.0:
			pick = vd
			break
	var out := def.duplicate(true)
	var params: Dictionary = out.get("params", {})
	params.merge(pick.get("params", {}), true)
	var pm: Dictionary = pick.get("param_mult", {})
	for k: String in pm:
		if params.has(k) and (params[k] is float or params[k] is int):
			var scaled := float(params[k]) * float(pm[k])
			params[k] = roundi(scaled) if params[k] is int else scaled
	out["params"] = params
	out["rewards"] = scale_rewards(out.get("rewards", {}), float(pick.get("reward_mult", 1.0)))
	(out["rewards"] as Dictionary).merge(pick.get("rewards", {}), false)
	out["title"] = "%s %s" % [str(pick.get("name", "")), str(out.get("title", ""))]
	if pick.has("color"):
		out["color"] = pick["color"]
	out["variant"] = pick
	return out


## Multiplies the numeric rewards (xp_levels, souls, heal, ichor, shards, hellstone, chalice) by
## `mult`; at x1.75+ a relic reward also goes up one rarity.
static func scale_rewards(rewards: Dictionary, mult: float) -> Dictionary:
	var out := rewards.duplicate(true)
	if is_equal_approx(mult, 1.0):
		return out
	for k: String in ["xp_levels", "heal"]:
		if out.has(k):
			out[k] = float(out[k]) * mult
	for k: String in ["souls", "ichor", "sin_shards", "hellstone", "chalice"]:
		if out.has(k):
			out[k] = maxi(roundi(float(out[k]) * mult), 1)
	if out.has("relic") and mult >= 1.75:
		out["relic"] = mini(_rarity_tier(out["relic"]) + 1, 4)
	return out


## Objectives that are not finished (dormant or active).
func open_objectives() -> Array[Objective]:
	var out: Array[Objective] = []
	for o in objectives:
		if is_instance_valid(o) and not o.is_finished():
			out.append(o)
	return out


## Summons a boss by roster id (data/bosses/bosses.json), or the next in the rotation when empty.
## Queued if another boss is alive. A herald banner announces it a few seconds before it lands.
func summon_boss(boss_id: String = "") -> void:
	if boss_id == "":
		boss_id = _next_rotation_id()
	if not _roster.has(boss_id):
		push_warning("ObjectiveDirector: unknown boss '%s'" % boss_id)
		return
	if _boss_alive():
		if not _pending_bosses.has(boss_id):
			_pending_bosses.append(boss_id)
		return
	_summon_now(boss_id)


## Called by the Temptation altar when a deal binds (group call).
func note_curse(deal_name: String) -> void:
	curses.append(deal_name)


## Roster ids (data/bosses/bosses.json).
func boss_ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(_roster.keys())
	return out


## Instantiates (does not spawn) the roster boss `boss_id`, set up with `hp_scale`. Null if the
## roster entry is broken. For scripted fights (the Seventh Gate) that place the boss themselves.
func make_boss(boss_id: String, hp_scale: float = 1.0) -> Enemy:
	var entry: Dictionary = _roster.get(boss_id, {})
	var data_path := str(entry.get("data", ""))
	var scene_path := str(entry.get("scene", ""))
	if not ResourceLoader.exists(data_path) or not ResourceLoader.exists(scene_path):
		push_warning("ObjectiveDirector: boss '%s' has a missing data or scene path" % boss_id)
		return null
	var inst := (load(scene_path) as PackedScene).instantiate()
	var b := inst as Enemy
	if b == null:
		inst.free()
		return null
	b.setup(load(data_path) as EnemyData, hp_scale)
	_apply_banners(b, entry)
	return b


## Roster "rage_text" / "felled_text" override a boss's enrage and death banners.
static func _apply_banners(b: Node, entry: Dictionary) -> void:
	for key: String in ["rage_text", "felled_text"]:
		if entry.has(key) and key in b:
			b.set(key, str(entry[key]))


## Grants a reward dictionary (see objectives.md) at `at`. Used by objectives; others may call it.
func grant(rewards: Dictionary, at: Vector3) -> void:
	var p := Game.player
	if p == null or not is_instance_valid(p):
		return
	var levels := float(rewards.get("xp_levels", 0.0))
	if levels > 0.0:
		_drop_xp(at, xp_for_levels(levels))
	var souls := int(rewards.get("souls", 0))
	if souls > 0:
		add_souls(souls)
	var heal := float(rewards.get("heal", 0.0))
	if heal > 0.0 and not p.is_dead:
		p.heal(heal)
		HolyFX.motes(p.global_position + Vector3(0.0, 0.6, 0.0), 10, Art.SOUL, 0.6, 1.6, 1.0)
	for i in int(rewards.get("chalice", 0)):
		BloodChalice.try_drop(at + Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5)), 1.0)
	var boon: Dictionary = rewards.get("boon", {})
	if not boon.is_empty() and not p.is_dead:
		var stat := StringName(str(boon.get("stat", "")))
		if stat in p:
			p.apply_stat(stat, float(boon.get("amount", 0.0)))
			_toast(str(boon.get("label", "Boon: %s" % stat)), UIPalette.BRIMSTONE)
	# Run currency (RunState Ichor drops), meta loot (Progression shards / hellstone pickups) and
	# relics (Progression.drop_relic, "relic": minimum rarity id such as "rare").
	var ichor := int(rewards.get("ichor", 0))
	var run_state := _autoload("RunState", &"drop_currency")
	if ichor > 0 and run_state:
		@warning_ignore("integer_division")
		run_state.call(&"drop_currency", at, ichor, clampi(ichor / 4, 1, 6))
	var prog := _autoload("Progression", &"drop_loot")
	for loot_id: String in ["sin_shards", "hellstone"]:
		var n := int(rewards.get(loot_id, 0))
		if n > 0 and prog:
			prog.call(&"drop_loot", at + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)), StringName(loot_id), n)
	if rewards.has("relic"):
		var relic_prog := _autoload("Progression", &"drop_relic")
		if relic_prog:
			relic_prog.call(&"drop_relic", at + Vector3(0.0, 0.0, 1.2), _rarity_tier(rewards["relic"]))


## An autoload by name that has `method`, or null (keeps this system working without it).
func _autoload(autoload_name: String, method: StringName) -> Node:
	var n := get_tree().root.get_node_or_null(autoload_name)
	return n if n and n.has_method(method) else null


## Rarity id ("rare") or tier int -> tier int (scripts/progression/rarity.gd order).
static func _rarity_tier(v: Variant) -> int:
	if v is int or v is float:
		return int(v)
	var ids := ["common", "uncommon", "rare", "epic", "legendary"]
	return maxi(ids.find(str(v).to_lower()), 0)


## Adds meta souls (forwarded to the Progression / Meta autoload when one exists).
func add_souls(amount: int) -> void:
	souls_earned += amount
	souls_earned_changed.emit(souls_earned)
	var prog := _autoload("Progression", &"add_currency")
	if prog:
		prog.call(&"add_currency", &"souls", amount)
		return
	var meta := _autoload("Meta", &"add_souls")
	if meta:
		meta.call(&"add_souls", amount)


## XP (before the demon's XP multiplier) that fills `levels` levels from its current progress.
static func xp_for_levels(levels: float) -> float:
	var p := Game.player
	if p == null or not is_instance_valid(p):
		return 50.0 * levels
	var need := 0.0
	var remaining := levels
	var lv := p.level
	var cur := float(p.xp_to_next) - p.xp
	# First (partial) level from the current progress, then whole ones, then a fraction.
	while remaining > 0.0:
		var span := cur if lv == p.level else float(p.xp_for_level(lv))
		need += span * minf(remaining, 1.0)
		remaining -= 1.0
		lv += 1
	return maxf(need, 5.0) / maxf(p.xp_gain, 0.01) + 0.5


# ---------------------------------------------------------------- data

func _load_data() -> void:
	var map_def := _map_def()
	if map_id == "":
		map_id = str(map_def.get("id", ""))
	# A map definition (data/maps/*.json) may carry an "objectives" block:
	#   {"settings": {...}, "include": [ids], "exclude": [ids], "weights": {id: weight}}
	var map_obj: Dictionary = map_def.get("objectives", {}) if map_def.get("objectives", {}) is Dictionary else {}
	var include: Array = map_obj.get("include", [])
	var exclude: Array = map_obj.get("exclude", [])
	var weights: Dictionary = map_obj.get("weights", {})
	var parsed := _read_json(DATA_PATH)
	settings = parsed.get("settings", {})
	_shared_variants = parsed.get("variants", [])
	# Per-map taste (objectives.json "map_preferences": {map id: {"weights": {id: x},
	# "types": {type: x}}}): multipliers on the definition weights, so each map favours its own
	# kind of trouble (processions in the city, fonts in the gardens, ...).
	var prefs: Dictionary = (parsed.get("map_preferences", {}) as Dictionary).get(map_id, {})
	var pref_weights: Dictionary = prefs.get("weights", {})
	var pref_types: Dictionary = prefs.get("types", {})
	for d: Variant in parsed.get("objectives", []):
		if not d is Dictionary:
			continue
		var def: Dictionary = (d as Dictionary).duplicate(true)
		var def_id := str(def.get("id", ""))
		var maps: Array = def.get("maps", [])
		if not maps.is_empty() and not map_id in maps:
			continue
		if (not include.is_empty() and not def_id in include) or def_id in exclude:
			continue
		if weights.has(def_id):
			def["weight"] = float(weights[def_id])
		elif pref_weights.has(def_id):
			def["weight"] = float(def.get("weight", 1.0)) * float(pref_weights[def_id])
		elif pref_types.has(str(def.get("type", ""))):
			def["weight"] = float(def.get("weight", 1.0)) * float(pref_types[str(def.get("type", ""))])
		definitions.append(def)
	var overrides: Dictionary = parsed.get("map_settings", {})
	if map_id != "" and overrides.has(map_id):
		settings.merge(overrides[map_id], true)
	settings.merge(map_obj.get("settings", {}), true)
	for t: Variant in settings.get("boss_after_completions", []):
		_boss_thresholds.append(int(t))
	for b: Variant in settings.get("boss_rotation", []):
		_rotation.append(str(b))
	# The map's own boss ("boss" in its definition) comes first in the rotation.
	var map_boss := str(map_def.get("boss", "")).get_file().get_basename()
	if map_boss != "":
		_rotation.erase(map_boss)
		_rotation.push_front(map_boss)


## The selected map definition from the Maps autoload ({} without one).
func _map_def() -> Dictionary:
	var maps := get_tree().root.get_node_or_null(^"Maps")
	if maps and maps.has_method(&"selected_def"):
		var d: Variant = maps.call(&"selected_def")
		if d is Dictionary:
			return d
	return {}


func _load_roster() -> void:
	_roster = _read_json(BOSS_ROSTER_PATH).get("bosses", {})
	_rotation.assign(_rotation.filter(func(b: String) -> bool: return _roster.has(b)))
	if _rotation.is_empty():
		for id: String in _roster.keys():
			if not bool((_roster[id] as Dictionary).get("finale_only", false)):
				_rotation.append(id)


static func _read_json(path: String) -> Dictionary:
	return JsonIO.read_dict(path, "ObjectiveDirector", false, true)


## Perf (docs/team/performance.md): starts background loads of every objective type script at
## run start; _script_for()'s load() then finds them in the resource cache instead of compiling
## mid-fight.
func _prewarm_scripts() -> void:
	var dir := TYPE_SCRIPT.get_base_dir()
	for f in DirAccess.get_files_at(dir):
		var file := f.trim_suffix(".remap")
		if file.ends_with("_objective.gd"):
			ResourceLoader.load_threaded_request(dir.path_join(file), "GDScript")


func _script_for(type: String) -> GDScript:
	if not _scripts.has(type):
		var path := TYPE_SCRIPT % type
		_scripts[type] = load(path) as GDScript if ResourceLoader.exists(path) else null
		if _scripts[type] == null:
			push_warning("ObjectiveDirector: no objective script for type '%s'" % type)
	return _scripts[type]


func _find_def(def_id: String) -> Dictionary:
	for d in definitions:
		if str(d.get("id", "")) == def_id:
			return d
	push_warning("ObjectiveDirector: no objective '%s'" % def_id)
	return {}


## Weighted pick among definitions unlocked by time and not already on the map.
func _pick_def() -> Dictionary:
	var open_ids := {}
	for o in open_objectives():
		open_ids[String(o.id)] = true
	var pool: Array[Dictionary] = []
	var total := 0.0
	for d in definitions:
		var def_id := str(d.get("id", ""))
		if Game.elapsed < float(d.get("min_time", 0.0)) or open_ids.has(def_id):
			continue
		if bool(d.get("finale", false)):
			continue  # placed by _try_spawn_finale()
		if bool(d.get("requires_no_boss", false)) and (_boss_alive() or not _pending_bosses.is_empty()):
			continue
		if d.has("max_per_run") and int(_spawned_counts.get(def_id, 0)) >= int(d["max_per_run"]):
			continue
		pool.append(d)
		total += float(d.get("weight", 1.0))
	if pool.is_empty():
		return {}
	var roll := randf() * total
	for d in pool:
		roll -= float(d.get("weight", 1.0))
		if roll <= 0.0:
			return d
	return pool.back()


## Prefers a free map objective anchor (GameMap.objective(kind, pos), kinds listed in the
## definition's "anchors"; "*" = any kind) within reach, else a random walkable spot at
## min..max_distance from the demon, as far from other objectives as possible.
func _pick_position(def: Dictionary) -> Vector3:
	var p := Game.player.global_position
	var lo := float(settings.get("min_distance", 20.0))
	var hi := float(settings.get("max_distance", 34.0))
	var sep := float(settings.get("min_separation", 16.0))
	var anchor := _pick_anchor(def, p, lo * 0.5, hi * 2.0, sep)
	if anchor != Vector3.INF:
		return anchor
	var maps := get_tree().root.get_node_or_null(^"Maps")
	var best := p
	var best_score := -INF
	for i in 14:
		var c: Vector3
		if maps and maps.has_method(&"random_point"):
			c = maps.call(&"random_point", p, lo, hi)
		else:
			var a := randf() * TAU
			c = p + Vector3(cos(a), 0.0, sin(a)) * randf_range(lo, hi)
		# Score = distance to the nearest other objective; take the first that is far enough.
		var nearest := INF
		for o in open_objectives():
			nearest = minf(nearest, o.global_position.distance_to(c))
		if nearest >= sep:
			return c
		if nearest > best_score:
			best_score = nearest
			best = c
	return best


func _pick_anchor(def: Dictionary, p: Vector3, lo: float, hi: float, sep: float) -> Vector3:
	var kinds: Array = def.get("anchors", [])
	var maps := get_tree().root.get_node_or_null(^"Maps")
	if kinds.is_empty() or maps == null or not maps.has_method(&"objective_points"):
		return Vector3.INF
	# Kinds are tried in order: the first kind with a free anchor in reach wins.
	for kind: Variant in kinds:
		var pick := _anchor_of_kind(maps, str(kind), p, lo, hi, sep)
		if pick != Vector3.INF:
			return pick
	return Vector3.INF


func _anchor_of_kind(maps: Node, kind: String, p: Vector3, lo: float, hi: float, sep: float) -> Vector3:
	var candidates: Array[Vector3] = []
	_anchor_ids.clear()
	var pts: Array = maps.call(&"objective_points", StringName("" if kind == "*" else kind))
	for n: Variant in pts:
		var at := (n as Node3D).global_position
		var d := Vector2(at.x - p.x, at.z - p.z).length()
		if d < lo or d > hi or _used_anchors.has(n.get_instance_id()):
			continue
		var ok := true
		for o in open_objectives():
			if o.global_position.distance_to(at) < sep:
				ok = false
				break
		if ok:
			candidates.append(at)
			_anchor_ids[at] = n.get_instance_id()
	if candidates.is_empty():
		return Vector3.INF
	var pick: Vector3 = candidates.pick_random()
	_used_anchors[_anchor_ids[pick]] = true
	return pick


func _open_count() -> int:
	return open_objectives().size()


# ---------------------------------------------------------------- events

func _on_objective_state_changed(obj: Objective) -> void:
	match obj.state:
		Objective.State.ACTIVE:
			objective_activated.emit(obj)
			Game.objective_started.emit(obj.id)
			Sfx.play(&"toll", 0.0, -2.0)
		Objective.State.COMPLETED:
			var is_event := bool(obj.def.get("event", false))
			var rewards: Dictionary = obj.def.get("rewards", {})
			grant(rewards, obj.global_position)
			_toast(obj.title.to_upper() + ("  -  SURVIVED" if is_event else "  -  DONE"), UIPalette.HELLFIRE)
			Sfx.play(&"triumph", 0.0, -3.0)
			objective_completed.emit(obj)
			Game.objective_completed.emit(obj.id, rewards)
			if not is_event:
				# Run events (data/objectives/events.json) don't count toward bosses.
				completed_count += 1
				_check_boss_threshold()
				# A fresh objective soon after one is done, so the map never runs dry.
				_next_spawn = minf(_next_spawn, 12.0)
		Objective.State.FAILED:
			if bool(obj.def.get("event", false)):
				objective_failed.emit(obj)
				Game.objective_failed.emit(obj.id)
				return
			failed_count += 1
			_toast(obj.title + " failed", UIPalette.ASH_TEXT)
			objective_failed.emit(obj)
			Game.objective_failed.emit(obj.id)
			_next_spawn = minf(_next_spawn, 15.0)


func _on_objective_exiting(obj: Objective) -> void:
	objectives.erase(obj)
	objective_removed.emit(obj)


func _check_boss_threshold() -> void:
	if _boss_thresholds.has(completed_count):
		summon_boss()


# ---------------------------------------------------------------- bosses

func _boss_alive() -> bool:
	return get_tree().get_first_node_in_group(&"boss") != null


func _next_rotation_id() -> String:
	if _rotation.is_empty():
		return ""
	return _rotation[_rotation_i % _rotation.size()]


func _summon_now(boss_id: String) -> void:
	var entry: Dictionary = _roster.get(boss_id, {})
	var data := load(str(entry.get("data", ""))) as EnemyData if ResourceLoader.exists(str(entry.get("data", ""))) else null
	var scene := load(str(entry.get("scene", ""))) as PackedScene if ResourceLoader.exists(str(entry.get("scene", ""))) else null
	if data == null or scene == null:
		push_warning("ObjectiveDirector: boss '%s' has a missing data or scene path" % boss_id)
		return
	_toast(str(entry.get("herald", "A champion of Heaven approaches")), UIPalette.HOLY_GOLD)
	Sfx.play(&"toll", 0.0, 2.0)
	_bosses_summoned += 1
	var hp_scale := 1.0 + 0.45 * float(_bosses_summoned - 1) + Game.elapsed / 900.0
	await get_tree().create_timer(BOSS_HERALD_LEAD, false).timeout
	var p := Game.player
	if p == null or not is_instance_valid(p) or p.is_dead or _boss_alive():
		return
	var b := scene.instantiate() as Node3D
	if b == null or not b.has_method(&"setup"):
		push_warning("ObjectiveDirector: boss scene for '%s' has no setup()" % boss_id)
		if b:
			b.free()
		return
	b.call(&"setup", data, hp_scale)
	_apply_banners(b, entry)
	var a := -PI / 2.0 + randf_range(-0.9, 0.9)  # -Z = up on screen: it arrives ahead of the demon
	Game.spawn(b, p.global_position + Vector3(cos(a), 0.0, sin(a)) * BOSS_DISTANCE)
	boss_summoned.emit(b)


# ---------------------------------------------------------------- finale (the Seventh Gate)

## True when this run offers the Seventh Gate finale: the map is a finale map (its definition has
## "finale": true, or its id is in settings.finale_maps) and, unless the map itself is the finale
## map, the story requirement (settings.finale_flag, a Dialogue flag) is met.
func finale_available() -> bool:
	if _finale_cached >= 0:
		return _finale_cached == 1
	var md := _map_def()
	var ok := false
	if _map_gate != null:
		ok = false  # the map's own SeventhGate (scenes/maps/features/seventh_gate.gd) is the finale
	elif bool(md.get("finale", false)):
		ok = true
	elif map_id in (settings.get("finale_maps", []) as Array):
		var flag := str(settings.get("finale_flag", ""))
		var dlg := _autoload("Dialogue", &"has_flag")
		ok = flag == "" or (dlg != null and bool(dlg.call(&"has_flag", flag)))
	_finale_cached = 1 if ok else 0
	return ok


## Finds a map-authored Seventh Gate (heavens_gate map). When its last seal breaks and the run
## still lacks the bosses it requires, the Gate's warden (roster "gate_archon") is summoned.
func _find_map_gate() -> void:
	for n in get_tree().get_nodes_in_group(&"map_interactables"):
		if n.has_signal(&"seals_changed") and n.has_signal(&"opened"):
			_map_gate = n
			_finale_cached = -1
			n.connect(&"seals_changed", _on_map_gate_seals_changed)
			return


## The Gate's last ward broke: its warden, Azrafel, steps through, always (settings
## "warden_always": false restores the old rule of only when the run still lacks bosses). The
## Gate's `bosses_required` is raised past the current count so it opens on the warden's death.
func _on_map_gate_seals_changed(remaining: int) -> void:
	if remaining > 0 or _map_gate == null or not _roster.has("gate_archon"):
		return
	var rs := _autoload("RunState", &"end_run")
	var killed := int(rs.get(&"bosses_killed")) if rs else bosses_slain
	var need := int(_map_gate.get(&"bosses_required")) if &"bosses_required" in _map_gate else 1
	if bool(settings.get("warden_always", true)) and &"bosses_required" in _map_gate:
		# A boss already on the field will add to the count before the warden arrives.
		var target := killed + 1 + (1 if _boss_alive() else 0)
		_map_gate.set(&"bosses_required", maxi(need, target))
		need = maxi(need, target)
	if killed < need:
		summon_boss("gate_archon")


## Places each finale objective (definition "finale": true) once, when its min_time is reached.
func _try_spawn_finale() -> void:
	if _finale_spawned or not finale_available():
		return
	for d in definitions:
		if bool(d.get("finale", false)) and Game.elapsed >= float(d.get("min_time", 0.0)):
			_finale_spawned = true
			var obj := spawn_objective(str(d.get("id", "")))
			if obj:
				_toast(str(d.get("herald", "The Seventh Gate stands open to assault")), UIPalette.HELLFIRE)
			return


## Final Judgement: after settings.victory_bosses bosses are slain (0 = endless) the run is won.
func _on_game_boss_died(_at: Vector3) -> void:
	bosses_slain += 1
	var need := int(settings.get("victory_bosses", 0))
	# On a finale run the Seventh Gate is the way to win; boss counts do not end it.
	if need <= 0 or finale_available() or _map_gate != null:
		return
	if bosses_slain >= need:
		_victory()
	elif bosses_slain == need - 1:
		_toast("One more of Heaven's champions stands between you and the throne", UIPalette.HELLFIRE)


func _victory() -> void:
	_toast("THE HOST IS BROKEN", UIPalette.HELLFIRE)
	win_run(&"victory")


## Ends the run in victory (RunState.end_run(true, cause)) after `delay` seconds, so the last
## death and its rewards can play out. Every objectives-side win goes through here
## (&"victory" = Final Judgement, &"seventh_gate" = the story finale).
func win_run(cause: StringName, delay: float = VICTORY_DELAY) -> void:
	if _winning:
		return
	_winning = true
	Sfx.play(&"triumph", 0.0, 2.0)
	enabled = false
	await get_tree().create_timer(delay, false).timeout
	var run_state := _autoload("RunState", &"end_run")
	if run_state and Game.player and not Game.player.is_dead:
		run_state.call(&"end_run", true, cause)


## Every boss arrival (ours or the spawner's timer) advances the rotation, and the spawner's next
## timed boss is set to the following entry.
func _on_game_boss_spawned(_boss: Node3D) -> void:
	_rotation_i += 1
	_prime_spawner_boss()


func _prime_spawner_boss() -> void:
	var sp := get_tree().current_scene.get_node_or_null(^"EnemySpawner") if get_tree().current_scene else null
	var entry: Dictionary = _roster.get(_next_rotation_id(), {})
	if sp == null or entry.is_empty() or not (&"boss" in sp and &"boss_scene" in sp):
		return
	var data_path := str(entry.get("data", ""))
	var scene_path := str(entry.get("scene", ""))
	if ResourceLoader.exists(data_path) and ResourceLoader.exists(scene_path):
		sp.set(&"boss", load(data_path))
		sp.set(&"boss_scene", load(scene_path))


# ---------------------------------------------------------------- rewards

## Small rewards scatter as a ring of soul shards; big ones come as a Reliquary of Sin.
func _drop_xp(at: Vector3, xp: float) -> void:
	if xp >= RELIQUARY_XP:
		ReliquaryOfSin.drop(at, xp, 0.4)
		return
	var count := clampi(int(xp / 6.0), 3, 10)
	var each := maxi(int(ceil(xp / count)), 1)
	for i in count:
		var a := TAU * float(i) / float(count)
		var gem: XPGem = GEM_SCENE.instantiate()
		gem.value = each
		Game.spawn.call_deferred(gem, at + Vector3(cos(a) * 1.4, 0.4, sin(a) * 1.4))


func _toast(text: String, tint: Color) -> void:
	var hud := get_tree().get_first_node_in_group(&"hud")
	if hud and hud.has_method(&"toast"):
		hud.call(&"toast", text, tint)


# ---------------------------------------------------------------- dev

func _dev_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--no-objectives":
			enabled = false
		elif arg == "--no-events":
			events.enabled = false
		elif arg.begins_with("--objective="):
			_dev_spawn_later(arg.substr(12))
		elif arg.begins_with("--summon="):
			_dev_summon_later(arg.substr(9))
		elif arg.begins_with("--objectives-selftest"):
			var t: Node = load("res://scenes/objectives/objective_selftest.gd").new()
			t.set(&"director", self)
			t.set(&"mode", arg.get_slice("=", 1) if arg.contains("=") else "")
			add_child(t)


func _dev_spawn_later(def_id: String) -> void:
	await get_tree().create_timer(2.0, false).timeout
	if Game.player:
		spawn_objective(def_id, Game.player.global_position + Vector3(4.0, 0.0, -3.0))


func _dev_summon_later(boss_id: String) -> void:
	await get_tree().create_timer(4.0, false).timeout
	summon_boss(boss_id)


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_F8 and Game.player:
		spawn_objective("", Game.player.global_position + Vector3(5.0, 0.0, -2.0))
		get_viewport().set_input_as_handled()
