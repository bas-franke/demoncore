class_name DailyChallenge
## The Board of Trials (basecamp role): one seeded challenge run per day. The date picks a seed,
## a map (from the maps open to everyone) and `per_day` modifiers from data/meta/challenges.json,
## so every player sees the same trial on the same day. Meta keeps the active trial and the local
## best score per trial key; Meta seeds the RNG with the trial's seed at run start.
##
##   var t := DailyChallenge.today()      # {key, date, seed, map, map_name, modifiers: [...]}
##   DailyChallenge.score(result, t)      # int, from a RunState result dictionary

const DATA_PATH := "res://data/meta/challenges.json"

static var _data := {}


## The trial for today (local date).
static func today() -> Dictionary:
	return for_date(Time.get_date_dict_from_system())


## The trial for a {year, month, day} date. Deterministic: same date, same trial.
static func for_date(date: Dictionary) -> Dictionary:
	var stamp := "%04d-%02d-%02d" % [int(date.year), int(date.month), int(date.day)]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("sinbound-trial-" + stamp)
	var trial_seed := rng.randi_range(1, 0x7FFFFFFF)
	# Maps anyone can play (no souls unlock needed), in registry order so the pick is stable.
	var maps: Array[Dictionary] = []
	var meta := (Engine.get_main_loop() as SceneTree).root.get_node_or_null(^"Meta")
	var all_maps: Array = meta.call(&"get_maps") if meta else []
	for m: Dictionary in all_maps:
		var u: Variant = m.get("unlock", {})
		if not (u is Dictionary) or bool((u as Dictionary).get("default", true)):
			maps.append(m)
	var map: Dictionary = maps[rng.randi() % maps.size()] if not maps.is_empty() else {}
	var pool: Array = _load().get("modifiers", []).duplicate()
	var picked: Array = []
	for i in mini(int(_load().get("per_day", 2)), pool.size()):
		picked.append(pool.pop_at(rng.randi() % pool.size()))
	return {
		"key": stamp, "date": stamp, "seed": trial_seed,
		"map": String(map.get("id", "")), "map_name": String(map.get("name", "The Heavens")),
		"modifiers": picked,
	}


## All effects of a trial's modifiers, flattened.
static func effects(trial: Dictionary) -> Array:
	var out: Array = []
	for m: Dictionary in trial.get("modifiers", []):
		out.append_array(m.get("effects", []))
	return out


## Score: kills + 2 per second survived + 25 per level + 40 per boss + 2000 for a victory, times
## (1 + the modifiers' score_mult).
static func score(result: Dictionary, trial: Dictionary) -> int:
	var s := float(result.get("kills", 0)) + float(result.get("time", 0.0)) * 2.0
	s += float(result.get("level", 1)) * 25.0 + float(result.get("bosses", 0)) * 40.0
	if bool(result.get("victory", false)):
		s += 2000.0
	s *= 1.0 + RunLoadout.total(effects(trial), "score_mult")
	return int(round(s))


static func _load() -> Dictionary:
	if _data.is_empty():
		_data = JsonIO.read_dict(DATA_PATH, "DailyChallenge", true)
	return _data
