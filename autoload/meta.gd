extends Node
## Meta progression between runs (autoload "Meta", owned by the basecamp role): the Souls currency,
## the upgrades bought from the Basecamp Hell shopkeepers with Souls, map unlocks / the chosen map,
## and lifetime run stats. Persisted as JSON in user://meta_save.json. See docs/team/basecamp.md.
##
##   Meta.souls / Meta.add_souls(10) / Meta.spend(25)
##   Meta.get_level(&"bs_might") / Meta.buy(&"bs_might") / Meta.upgrades_for_shop("blacksmith")
##   Meta.effect_total(&"might")          # summed bonus of every bought upgrade touching `might`
##   Meta.go_to_basecamp() / Meta.start_run()
##
## Hooks (no edits elsewhere needed): RunState.run_started / run_ended pay the soul reward once per
## run; SceneTree.node_added applies bought upgrades to every Player once it is ready.
## Maps come from the Maps autoload (data/maps/*.json, maps role); Meta only stores which maps were
## unlocked with souls ("unlock": {"default": false, "cost": N}) and which one is selected.
## Upgrade catalog: res://data/meta/upgrades.json.

signal souls_changed(total: int)
signal upgrade_bought(id: StringName, level: int)
signal map_selected(id: StringName)
signal map_unlocked(id: StringName)
## Emitted once per run when the soul reward is banked. Keys: victory, cause, souls, base, ichor,
## multiplier, kills, time, level. (Progression adds its heat bonus on top of this.)
signal run_finished(summary: Dictionary)
## A boss was slain for the first time (trophy wall in Basecamp Hell).
signal trophy_unlocked(boss_id: StringName)

const SAVE_PATH := "user://meta_save.json"
const SAVES := preload("res://scripts/save_profile.gd")  # (progression) save isolation
const SAVE_VERSION := 1
const UPGRADES_PATH := "res://data/meta/upgrades.json"
const BASECAMP_SCENE := "res://scenes/basecamp/basecamp.tscn"
const RUN_SCENE := "res://scenes/main.tscn"
const BOSSES_PATH := "res://data/bosses/bosses.json"

## Soul reward per run (before the soul_gain multiplier). Carried Ichor converts 1:1.
const SOULS_PER_KILL := 0.05
const SOULS_PER_SECOND := 1.0 / 15.0
const SOULS_PER_LEVEL := 1.5
const SOULS_PER_ICHOR := 1.0
const VICTORY_BONUS := 150
## Display names for effect_text().
const STAT_LABELS := {
	"might": "damage", "armor": "armor", "max_hp": "max vigor", "projectile_speed": "projectile speed",
	"bonus_projectiles": "projectile", "cooldown": "cooldown", "area": "area", "regen": "vigor / s",
	"move_speed": "speed", "soul_gain": "souls", "xp_gain": "experience", "pickup_radius": "reach",
}

var souls := 0
## upgrade id (String) -> purchased level (int)
var upgrades := {}
## Map chosen at the cartographer (persisted; mirrored into Maps.selected_id).
var selected_map: StringName = &""
var unlocked_maps: Array[String] = []
## Lifetime stats: runs, victories, best_time, total_kills, souls_earned.
var stats := {"runs": 0, "victories": 0, "best_time": 0.0, "total_kills": 0, "souls_earned": 0}
## Souls picked up during the current run (added to the reward by finish_run).
var run_souls := 0
## Summary of the run that just ended, for the basecamp arrival banner. Cleared once shown.
var pending_summary := {}
## Boss trophies: boss id (String) -> {kills, first_kill (unix time), demon (display name)}.
var trophies := {}
## Camp development level the player has already seen announced (Basecamp growth).
var camp_level_seen := 0
## Hellgate loadout, remembered as the default for next time: {weapon: scene path, ability: id,
## keepsake: id} ("" = the demon's own weapon / none). See RunLoadout.
var loadout := {"weapon": "", "ability": "", "keepsake": ""}
## The daily trial being played ({} = a normal run). See DailyChallenge.
var trial := {}
## Best trial score per trial key: key -> {score, demon, kills, time, victory}.
var trial_best := {}

## Catalog, loaded from UPGRADES_PATH.
var shops := {}  # shop id (String) -> {name, title, greeting, color, ...}
var currency := {}  # {id, name, short}
var upgrade_defs: Array[Dictionary] = []
var _defs_by_id := {}  # String -> Dictionary
var _run_active := false
var _live_bosses: Array[Node3D] = []
## What the next Player spawn gets: "" (nothing, e.g. the Proving Pit), "loadout" or "trial".
var _armed := ""


func _ready() -> void:
	_ensure_input_actions()
	_load_catalog()
	load_game()
	get_tree().node_added.connect(_on_node_added)
	# (progression) A scene launched directly (main.tscn from the editor) entered the tree together
	# with the autoloads, before node_added was connected: catch its not-yet-ready Player here.
	for n in get_tree().root.find_children("*", "Player", true, false):
		if not n.is_node_ready():
			_on_node_added(n)
	var rs := _run_state()
	if rs:
		rs.connect(&"run_started", begin_run)
		rs.connect(&"run_ended", _on_run_ended)
	Game.boss_spawned.connect(_on_boss_spawned)
	Game.boss_died.connect(_on_boss_died)
	_sync_map.call_deferred()


# ---------------------------------------------------------------- currency

func add_souls(amount: int) -> void:
	if amount == 0:
		return
	souls = maxi(0, souls + amount)
	souls_changed.emit(souls)
	save_game()


## Deducts `amount` if affordable. Returns false (and changes nothing) otherwise.
func spend(amount: int) -> bool:
	if amount < 0 or amount > souls:
		return false
	souls -= amount
	souls_changed.emit(souls)
	save_game()
	return true


## For in-run soul pickups (elites, chests...): banked when the run ends.
func add_run_souls(amount: int) -> void:
	run_souls += amount


# ---------------------------------------------------------------- upgrades

func get_def(id: StringName) -> Dictionary:
	return _defs_by_id.get(String(id), {})


func get_level(id: StringName) -> int:
	return int(upgrades.get(String(id), 0))


func get_max_level(id: StringName) -> int:
	return int(get_def(id).get("max_level", 1))


func is_maxed(id: StringName) -> bool:
	return get_level(id) >= get_max_level(id)


## Cost of the next rank, or -1 when maxed / unknown. `cost` is either an array (one price per
## rank; the last one repeats) or a number with an optional `cost_growth` multiplier per rank.
func next_cost(id: StringName) -> int:
	var def := get_def(id)
	if def.is_empty() or is_maxed(id):
		return -1
	var lv := get_level(id)
	var c: Variant = def.get("cost", 0)
	if c is Array:
		var arr := c as Array
		return 0 if arr.is_empty() else int(arr[mini(lv, arr.size() - 1)])
	return int(round(float(c) * pow(float(def.get("cost_growth", 1.0)), lv)))


## Unmet requirement text for `id` (empty when met). "requires": {"<upgrade id>": level}; ids may
## also be Progression upgrades / unlocks.
func requirement_text(id: StringName) -> String:
	var req: Variant = get_def(id).get("requires", {})
	if not req is Dictionary:
		return ""
	for other: String in req:
		var need := int(req[other])
		var have := get_level(StringName(other))
		var od := get_def(StringName(other))
		var prog := _progression()
		if od.is_empty() and prog:
			have = int(prog.call(&"get_level", StringName(other)))
			od = prog.call(&"get_def", StringName(other))
		if have < need:
			return "Requires %s %s" % [od.get("name", other), TextFormat.roman(need)]
	return ""


## Why `id` can't be bought right now ("" = it can).
func block_reason(id: StringName) -> String:
	if get_def(id).is_empty():
		return "Unknown"
	if is_maxed(id):
		return "Mastered"
	var req := requirement_text(id)
	if req != "":
		return req
	if next_cost(id) > souls:
		return "Not enough souls"
	return ""


func can_buy(id: StringName) -> bool:
	return block_reason(id) == ""


func buy(id: StringName) -> bool:
	if not can_buy(id):
		return false
	souls -= next_cost(id)
	upgrades[String(id)] = get_level(id) + 1
	souls_changed.emit(souls)
	upgrade_bought.emit(id, get_level(id))
	save_game()
	return true


## Upgrades sold by `shop`, in catalog order.
func upgrades_for_shop(shop: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in upgrade_defs:
		if d.get("shop", "") == shop:
			out.append(d)
	return out


## Sum of `per_level * level` over every bought upgrade with an effect whose `stat` or `type`
## equals `key` (e.g. &"might", &"soul_gain"). Lets other systems read bonuses they care about
## without knowing upgrade ids.
func effect_total(key: StringName) -> float:
	var total := 0.0
	for d in upgrade_defs:
		var lv := get_level(StringName(d.id))
		if lv <= 0:
			continue
		for e: Dictionary in d.get("effects", []):
			if StringName(e.get("stat", "")) == key or StringName(e.get("type", "")) == key:
				total += float(e.get("per_level", 0.0)) * lv
	return total


## Applies every bought upgrade to a Player (done automatically once each Player is ready).
## Effect kinds:
##   {"stat": "<Player property>", "per_level": x}   -> player.apply_stat(stat, x * level)
##   {"type": "weapon", "scene": "res://..."}         -> extra starting weapon once bought
##   anything else (soul_gain, ...)                   -> read by other systems via effect_total()
func apply_to_player(player: Node) -> void:
	for d in upgrade_defs:
		var lv := get_level(StringName(d.id))
		if lv <= 0:
			continue
		for e: Dictionary in d.get("effects", []):
			if e.has("stat"):
				player.call(&"apply_stat", StringName(e.stat), float(e.get("per_level", 0.0)) * lv)
			elif e.get("type", "") == "weapon" and player.has_method(&"add_weapon"):
				var scene := load(String(e.get("scene", ""))) as PackedScene
				if scene:
					player.call(&"add_weapon", scene)


## Text for a row: "+18% damage" style summary of `rank` ranks ("" for rank 0 / no stat effects).
func effect_text(id: StringName, rank: int) -> String:
	if rank <= 0:
		return ""
	var parts: PackedStringArray = []
	for e: Dictionary in get_def(id).get("effects", []):
		if not e.has("per_level"):
			continue
		var v := float(e.per_level) * rank
		var key := String(e.get("stat", e.get("type", "")))
		var pct := key in ["might", "area", "cooldown", "projectile_speed", "xp_gain", "soul_gain"]
		var label := String(e.get("label", STAT_LABELS.get(key, key.capitalize())))
		if pct:
			parts.append("%+d%% %s" % [roundi(v * 100.0), label])
		elif is_equal_approx(v, roundf(v)):
			parts.append("%+d %s" % [roundi(v), label])
		else:
			parts.append("%+.1f %s" % [v, label])
	return ", ".join(parts)



# ---------------------------------------------------------------- maps (data lives in Maps)

## Every map (Maps.all()), or a single fallback entry when the Maps autoload is missing.
func get_maps() -> Array[Dictionary]:
	var maps := _maps()
	if maps:
		return maps.call(&"all")
	var out: Array[Dictionary] = [{"id": "default", "name": "The Heavens", "description": "", "unlock": {}}]
	return out


func get_map(id: StringName) -> Dictionary:
	for m in get_maps():
		if StringName(m.id) == id:
			return m
	return {}


## Souls needed to unseal `id` (0 = free).
func map_cost(id: StringName) -> int:
	var u: Variant = get_map(id).get("unlock", {})
	return int((u as Dictionary).get("cost", 0)) if u is Dictionary else 0


func is_map_unlocked(id: StringName) -> bool:
	var m := get_map(id)
	if m.is_empty():
		return false
	var u: Variant = m.get("unlock", {})
	var default_open := true
	if u is Dictionary:
		default_open = bool((u as Dictionary).get("default", true)) or int((u as Dictionary).get("cost", 0)) <= 0
	return default_open or unlocked_maps.has(String(id))


## Map that must be cleared / unlocked first ("unlock": {"requires": "<map id>"}), or "".
func map_requirement(id: StringName) -> String:
	var u: Variant = get_map(id).get("unlock", {})
	if not u is Dictionary:
		return ""
	var req := String((u as Dictionary).get("requires", ""))
	if req != "" and not is_map_unlocked(StringName(req)):
		return "Requires %s" % get_map(StringName(req)).get("name", req)
	# Progression gate (progress / cleared / mastery / story keys, docs/team/progression.md).
	var prog := _progression()
	if prog and prog.has_method(&"map_gate") and not is_map_unlocked(id):
		return String(prog.call(&"map_gate", id))
	return ""


## Buys a locked map with souls. Returns true if it is (now) unlocked.
func unlock_map(id: StringName) -> bool:
	if is_map_unlocked(id):
		return true
	if map_requirement(id) != "" or not spend(map_cost(id)):
		return false
	unlocked_maps.append(String(id))
	map_unlocked.emit(id)
	save_game()
	return true


func select_map(id: StringName) -> bool:
	if not is_map_unlocked(id):
		return false
	selected_map = id
	var maps := _maps()
	if maps:
		maps.call(&"select", id)
	map_selected.emit(id)
	save_game()
	return true


# ---------------------------------------------------------------- run lifecycle

## Changes to the run scene with the selected map.
func start_run() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	var map := selected_map
	if not trial.is_empty():
		map = StringName(String(trial.get("map", "")))
		# Fixed seed: the map layout (GameMap draws randi() when its def has no seed) and the
		# run's other global RNG draws start from the trial's seed.
		seed(int(trial.seed))
	var maps := _maps()
	if maps and map != &"" and bool(maps.call(&"has_map", map)):
		maps.call(&"start_run", map)
	else:
		get_tree().change_scene_to_file(RUN_SCENE)


## Starts a normal run with the hellgate loadout `choice` ({weapon, ability, keepsake}; it is
## remembered for next time). The ability is queued with Abilities; the weapon replaces the
## demon's own (Player.starting_weapon_override); the keepsake's effects apply on spawn.
func start_run_with_loadout(choice: Dictionary) -> void:
	for k: String in loadout:
		loadout[k] = String(choice.get(k, ""))
	trial = {}
	_armed = "loadout"
	save_game()
	var ab := get_node_or_null(^"/root/Abilities")
	if ab and loadout.ability != "":
		ab.call(&"grant", StringName(loadout.ability))
	start_run()


## Starts today's (or any) DailyChallenge trial: its map, seed and modifiers, the demon's own
## weapon, no keepsake. The score is recorded in trial_best when the run ends.
func start_trial(t: Dictionary) -> void:
	trial = t.duplicate(true)
	_armed = "trial"
	start_run()


## Best recorded score for a trial key (0 = never played).
func trial_best_score(key: String) -> int:
	return int((trial_best.get(key, {}) as Dictionary).get("score", 0))


## RunState.run_started (or call it yourself for a run without RunState).
func begin_run() -> void:
	_run_active = true
	run_souls = 0
	if _armed == "trial" and not trial.is_empty():
		seed(int(trial.seed))
		_add_trial_heat.call_deferred()  # after Progression has set the pacts' heat


func _add_trial_heat() -> void:
	var rs := _run_state()
	if rs:
		rs.set(&"heat", int(rs.get(&"heat")) + int(RunLoadout.total(DailyChallenge.effects(trial), "heat")))


## Ends the current run: grants the soul reward, updates lifetime stats and saves. Only the first
## call per run pays out (later calls return 0). Normally driven by RunState.run_ended.
func finish_run(victory: bool, result: Dictionary = {}) -> int:
	if not _run_active:
		return 0
	_run_active = false
	var kills := int(result.get("kills", Game.kills))
	var time := float(result.get("time", Game.elapsed))
	var lv := int(result.get("level", Game.player.level if is_instance_valid(Game.player) else 1))
	var ichor := int(result.get("currency", 0))
	var base := kills * SOULS_PER_KILL + time * SOULS_PER_SECOND + lv * SOULS_PER_LEVEL
	base += run_souls + ichor * SOULS_PER_ICHOR
	if victory:
		base += VICTORY_BONUS
	var mult := 1.0 + effect_total(&"soul_gain")
	if _armed == "loadout" and loadout.keepsake != "":
		mult += RunLoadout.total(RunLoadout.keepsake(loadout.keepsake).get("effects", []), "soul_gain")
	var earned := int(round(base * mult))
	stats.runs = int(stats.runs) + 1
	if victory:
		stats.victories = int(stats.victories) + 1
	stats.best_time = maxf(float(stats.best_time), time)
	stats.total_kills = int(stats.total_kills) + kills
	stats.souls_earned = int(stats.souls_earned) + earned
	pending_summary = {
		"victory": victory, "cause": String(result.get("cause", "victory" if victory else "slain")),
		"souls": earned, "base": int(round(base)), "ichor": ichor, "multiplier": mult,
		"kills": kills, "time": time, "level": lv,
	}
	if _armed == "trial" and not trial.is_empty():
		_record_trial(result, victory, kills, time, lv)
	_armed = ""
	trial = {}
	run_souls = 0
	add_souls(earned)  # also saves
	run_finished.emit(pending_summary)
	return earned


## True between begin_run() and finish_run().
func is_run_active() -> bool:
	return _run_active


## Leaves whatever is running for the hub (pays out an unfinished run as abandoned first).
func go_to_basecamp() -> void:
	var rs := _run_state()
	if rs:
		rs.call(&"return_to_basecamp")
		return
	if _run_active:
		finish_run(false)
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(BASECAMP_SCENE)


## Scores the trial run, keeps the best per trial key and adds it to the arrival summary.
func _record_trial(result: Dictionary, victory: bool, kills: int, time: float, lv: int) -> void:
	var r := result.duplicate()
	r.victory = victory
	r.kills = kills
	r.time = time
	r.level = lv
	var score := DailyChallenge.score(r, trial)
	var key := String(trial.key)
	var best := trial_best_score(key)
	var demon := Game.selected_character as DemonData
	if score > best:
		trial_best[key] = {"score": score, "demon": demon.display_name if demon else "", "kills": kills,
				"time": time, "victory": victory}
	pending_summary.trial_score = score
	pending_summary.trial_best = maxi(score, best)
	pending_summary.trial_new_best = score > best


func _on_run_ended(result: Dictionary) -> void:
	finish_run(bool(result.get("victory", false)), result)


# ---------------------------------------------------------------- trophies

## Every boss in res://data/bosses/bosses.json as [{id, name, title, unlocked, kills, first_kill,
## demon}], in file order (the trophy wall shows one plaque each, locked ones as shadows).
func boss_trophies() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOSSES_PATH)) \
		if FileAccess.file_exists(BOSSES_PATH) else null
	var bosses: Dictionary = (parsed as Dictionary).get("bosses", {}) if parsed is Dictionary else {}
	for id: String in bosses:
		var entry: Dictionary = bosses[id]
		var data := load(String(entry.get("data", ""))) as EnemyData \
			if ResourceLoader.exists(String(entry.get("data", ""))) else null
		var t: Dictionary = trophies.get(id, {})
		out.append({
			"id": id, "name": data.display_name if data else id.capitalize(),
			"title": String(entry.get("herald", "")), "unlocked": not t.is_empty(),
			"kills": int(t.get("kills", 0)), "first_kill": int(t.get("first_kill", 0)),
			"demon": String(t.get("demon", "")),
		})
	return out


func has_trophy(boss_id: StringName) -> bool:
	return trophies.has(String(boss_id))


## Records a boss kill (first kill unlocks its trophy). Called from Game.boss_died.
func record_boss_kill(boss_id: StringName) -> void:
	var key := String(boss_id)
	if key == "":
		return
	var first := not trophies.has(key)
	var t: Dictionary = trophies.get(key, {"kills": 0, "first_kill": int(Time.get_unix_time_from_system())})
	t.kills = int(t.get("kills", 0)) + 1
	if first:
		var demon := Game.selected_character as DemonData
		t.demon = demon.display_name if demon else ""
	trophies[key] = t
	save_game()
	if first:
		trophy_unlocked.emit(boss_id)


func _on_boss_spawned(boss: Node3D) -> void:
	_live_bosses.append(boss)


## Game.boss_died only carries a position: match it to the boss node that is dying there.
func _on_boss_died(at: Vector3) -> void:
	var best: Node3D = null
	var best_d := INF
	for b in _live_bosses:
		if not is_instance_valid(b):
			continue
		var d := b.global_position.distance_to(at)
		if bool(b.get(&"is_dying")):
			d -= 1000.0  # the one already dying wins
		if d < best_d:
			best_d = d
			best = b
	if best == null:
		return
	_live_bosses.erase(best)
	var data := best.get(&"data") as EnemyData
	if data:
		record_boss_kill(data.id if data.id != &"" else StringName(data.resource_path.get_file().get_basename()))


func _on_node_added(node: Node) -> void:
	# Upgrades go on after Player._ready (stats from the demon are in place; max_hp bonuses heal).
	if node is Player:
		# Before its _ready: the loadout weapon replaces the demon's own.
		if _armed == "loadout" and loadout.weapon != "" and ResourceLoader.exists(loadout.weapon):
			node.set(&"starting_weapon_override", load(loadout.weapon))
		node.ready.connect(apply_to_player.bind(node), CONNECT_ONE_SHOT)
		if _armed != "":
			# Deferred so Progression's own spawn setup (which resets its run stats) runs first.
			node.ready.connect(func() -> void: _apply_run_mods.call_deferred(node), CONNECT_ONE_SHOT)


## Keepsake (loadout) or trial modifiers on the run's Player.
func _apply_run_mods(player: Node) -> void:
	if not is_instance_valid(player):
		return
	if _armed == "loadout" and loadout.keepsake != "":
		RunLoadout.apply_effects(player, RunLoadout.keepsake(loadout.keepsake).get("effects", []))
	elif _armed == "trial" and not trial.is_empty():
		var fx := DailyChallenge.effects(trial)
		RunLoadout.apply_effects(player, fx)
		for e: Dictionary in fx:
			if String(e.get("type", "")) == "random_ability":
				_grant_trial_ability()
		player.set(&"hp", player.get(&"max_hp"))  # max_hp penalties must not leave HP above max


## The trial's "Borrowed Rite": an unlocked ability picked from the trial seed.
func _grant_trial_ability() -> void:
	var pool: Array = []
	for a in RunLoadout.abilities():
		if a.unlocked:
			pool.append(a.id)
	var ab := get_node_or_null(^"/root/Abilities")
	if pool.is_empty() or ab == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(trial.seed)
	ab.call(&"grant", StringName(pool[rng.randi() % pool.size()]))


# ---------------------------------------------------------------- persistence

## (progression) Save isolation: honours --save-profile= / DEMONCORE_SAVE_PROFILE (SaveProfile), so
## tests write to user://test/<profile>/ instead of the real save.
func save_path() -> String:
	return SAVES.path(SAVE_PATH.get_file())


func save_game() -> void:
	var data := {
		"version": SAVE_VERSION, "souls": souls, "upgrades": upgrades,
		"selected_map": String(selected_map), "unlocked_maps": unlocked_maps, "stats": stats,
		"trophies": trophies, "camp_level_seen": camp_level_seen, "loadout": loadout,
		"trial_best": trial_best,
	}
	# Write to a temp file, then swap, so a crash mid-write can't corrupt the save.
	var tmp := save_path() + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Meta: cannot write %s (%s)" % [tmp, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	DirAccess.rename_absolute(tmp, save_path())


func load_game() -> void:
	if not FileAccess.file_exists(save_path()):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path()))
	if not parsed is Dictionary:
		push_warning("Meta: %s is corrupt; starting fresh" % save_path())
		return
	var d := parsed as Dictionary
	souls = int(d.get("souls", 0))
	upgrades = {}
	var ups: Variant = d.get("upgrades", {})
	if ups is Dictionary:
		for k: Variant in ups:
			upgrades[String(k)] = int(ups[k])  # JSON numbers load as floats
	selected_map = StringName(String(d.get("selected_map", "")))
	unlocked_maps.clear()
	for m: Variant in d.get("unlocked_maps", []):
		unlocked_maps.append(String(m))
	var st: Variant = d.get("stats", {})
	if st is Dictionary:
		for k: Variant in st:
			stats[String(k)] = st[k]
	var saved_trophies: Variant = d.get("trophies", {})
	trophies = (saved_trophies as Dictionary).duplicate(true) if saved_trophies is Dictionary else {}
	camp_level_seen = int(d.get("camp_level_seen", 0))
	var lo: Variant = d.get("loadout", {})
	if lo is Dictionary:
		for k: String in loadout:
			loadout[k] = String((lo as Dictionary).get(k, ""))
	var tb: Variant = d.get("trial_best", {})
	trial_best = (tb as Dictionary).duplicate(true) if tb is Dictionary else {}


## Wipes all meta progress (debug / "new game").
func reset_save() -> void:
	souls = 0
	upgrades = {}
	unlocked_maps.clear()
	stats = {"runs": 0, "victories": 0, "best_time": 0.0, "total_kills": 0, "souls_earned": 0}
	trophies = {}
	camp_level_seen = 0
	trial_best = {}
	selected_map = &""
	_sync_map()
	souls_changed.emit(souls)
	save_game()


# ---------------------------------------------------------------- helpers

func _load_catalog() -> void:
	var parsed: Variant = null
	if FileAccess.file_exists(UPGRADES_PATH):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(UPGRADES_PATH))
	if not parsed is Dictionary:
		push_warning("Meta: %s missing or invalid" % UPGRADES_PATH)
		return
	shops = (parsed as Dictionary).get("shops", {})
	currency = (parsed as Dictionary).get("currency", {})
	for u: Variant in (parsed as Dictionary).get("upgrades", []):
		if u is Dictionary and (u as Dictionary).has("id"):
			upgrade_defs.append(u)
			_defs_by_id[String(u.id)] = u


## Restores the saved map choice into Maps (or adopts Maps' default when ours is invalid).
func _sync_map() -> void:
	if selected_map == &"" or not is_map_unlocked(selected_map):
		var maps_node := _maps()
		selected_map = StringName(maps_node.get(&"selected_id")) if maps_node else &""
		if selected_map != &"" and not is_map_unlocked(selected_map):
			for m in get_maps():
				if is_map_unlocked(StringName(m.id)):
					selected_map = StringName(m.id)
					break
	var maps := _maps()
	# QA: a `--map=<id>` dev arg (applied in Maps._ready) wins over the saved choice; this deferred
	# sync used to overwrite it, so `main.tscn -- --map=<id>` always ran the saved map.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map=") and maps and maps.call(&"has_map", StringName(arg.substr(6))):
			return
	if maps and selected_map != &"" and maps.call(&"has_map", selected_map):
		maps.call(&"select", selected_map)


## Registers the hub's "interact" action (E / gamepad X) if the project input map lacks it.
func _ensure_input_actions() -> void:
	if not InputMap.has_action(&"hub_menu"):
		# Basecamp quick menu (Tab / gamepad Back).
		InputMap.add_action(&"hub_menu", 0.5)
		var tab := InputEventKey.new()
		tab.physical_keycode = KEY_TAB
		InputMap.action_add_event(&"hub_menu", tab)
		var back := InputEventJoypadButton.new()
		back.button_index = JOY_BUTTON_BACK
		InputMap.action_add_event(&"hub_menu", back)
	if InputMap.has_action(&"interact"):
		return
	InputMap.add_action(&"interact", 0.5)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	InputMap.action_add_event(&"interact", key)
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_X
	InputMap.action_add_event(&"interact", pad)


func _maps() -> Node:
	return get_node_or_null(^"/root/Maps")


func _run_state() -> Node:
	return get_node_or_null(^"/root/RunState")


func _progression() -> Node:
	return get_node_or_null(^"/root/Progression")
