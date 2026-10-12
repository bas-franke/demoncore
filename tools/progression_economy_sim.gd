extends SceneTree
## Economy simulator for the meta progression (docs/team/progression.md, "Economy").
## Plays N simulated careers per skill profile through the REAL reward code (Meta.finish_run,
## Progression._bank_run / compute_run_rewards / mastery) and the real shops (Meta.buy,
## Progression.buy, Meta.unlock_map), buying greedily (cheapest affordable first) after every run.
## Reports how many runs it takes to unlock 50 / 75 / 100 % of everything.
##
##   <godot> --headless --path . --script res://tools/progression_economy_sim.gd -- [--careers=20] [--csv=path]
##
## The run outcome model is a coarse stand-in for real play (tune SKILLS if playtests disagree):
##   minutes survived = (base + slope * power) * jitter, capped at MAX_MINUTES; power = share of the
##   whole catalog bought so far. A herald (boss) appears every 5 minutes and dies with boss_kill
##   chance; reaching WIN_MINUTES wins with win chance. Kills, levels, elites follow from minutes.
## Runs in the isolated save profile user://test/economy_sim/ (SaveProfile); real saves are never touched.

const SKILLS := {
	"novice": {"base": 4.0, "slope": 7.0, "boss_kill": 0.45, "win": 0.35, "heat_from": 2.0},
	"average": {"base": 6.0, "slope": 9.0, "boss_kill": 0.7, "win": 0.55, "heat_from": 0.6},
	"expert": {"base": 9.0, "slope": 9.0, "boss_kill": 0.9, "win": 0.75, "heat_from": 0.35},
}
const MAX_MINUTES := 20.0
const WIN_MINUTES := 15.0
const BOSS_EVERY := 5.0
const MAX_RUNS := 150
const DEMONS := [&"vharok", &"lilaeth", &"morvane", &"skarn", &"ysolde"]

var _p: Node
var _meta: Node
var _maps: Node
var _rs: Node
const SAVES := preload("res://scripts/save_profile.gd")
var _done := false


## Runs before the autoloads' _ready (root not in the tree yet), so even their boot-time load/save
## uses the isolated profile.
func _initialize() -> void:
	SAVES.use("economy_sim")


func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	_p = root.get_node(^"Progression")
	_meta = root.get_node_or_null(^"Meta")
	_maps = root.get_node_or_null(^"Maps")
	_rs = root.get_node(^"RunState")
	SAVES.use_and_reload(self, "economy_sim")
	var careers := 20
	var csv := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--careers="):
			careers = a.substr(10).to_int()
		elif a.begins_with("--csv="):
			csv = a.substr(6)
	var lines: PackedStringArray = ["skill,career,run,progress,souls,shards,hellstone"]
	print("catalog: %s" % [_catalog_summary()])
	for skill: String in SKILLS:
		var r50: Array[int] = []
		var r75: Array[int] = []
		var r100: Array[int] = []
		for c in careers:
			var res := _career(skill, c, lines)
			r50.append(res[0])
			r75.append(res[1])
			r100.append(res[2])
		print("%-8s runs to 50%%: %s   75%%: %s   100%%: %s" % [skill, _stat(r50), _stat(r75), _stat(r100)])
	if csv != "":
		var f := FileAccess.open(csv, FileAccess.WRITE)
		f.store_string("\n".join(lines))
	quit()
	return true


func _stat(a: Array[int]) -> String:
	a.sort()
	var sum := 0
	for v in a:
		sum += v
	@warning_ignore("integer_division")
	return "median %d (min %d, max %d, mean %.1f)" % [a[a.size() / 2], a[0], a[-1], float(sum) / a.size()]


## One career from a wiped save. Returns [runs to 50 %, 75 %, 100 %] (MAX_RUNS if never).
func _career(skill: String, career: int, lines: PackedStringArray) -> Array[int]:
	seed(1000 + career * 7 + skill.length())
	_p.reset_progress()
	if _meta:
		_meta.call(&"reset_save")
	var s: Dictionary = SKILLS[skill]
	var marks: Array[int] = [MAX_RUNS, MAX_RUNS, MAX_RUNS]
	for run in range(1, MAX_RUNS + 1):
		var power := _progress()
		var demon := _pick_demon(run)
		var heat := 0
		if power >= float(s.heat_from):
			heat = clampi(int((power - float(s.heat_from)) * 10.0), 0, 6)
		_set_heat(heat)
		var minutes := minf((float(s.base) + float(s.slope) * power) * randf_range(0.7, 1.3), MAX_MINUTES)
		var bosses := 0
		for k in int(minutes / BOSS_EVERY):
			if randf() < float(s.boss_kill):
				bosses += 1
		var victory := minutes >= WIN_MINUTES and randf() < float(s.win)
		var kills := int(minutes * (60.0 + 15.0 * minutes))
		var level := int(4 + 3.2 * minutes)
		var elites := int(minutes)
		var luck := float(_p.meta_bonus(&"luck"))
		var shards_found: int = bosses * int(_p.BOSS_SHARDS)
		for e in elites:
			if randf() < _p.SHARD_CHANCE_ELITE * (1.0 + luck):
				shards_found += 1
		var relics := bosses + int(_p.meta_bonus(&"starting_relics"))
		for e in elites:
			if randf() < _p.RELIC_CHANCE_ELITE * (1.0 + luck):
				relics += 1
		_p.stats.relics_found = int(_p.stats.get("relics_found", 0)) + relics
		var ichor := int(kills * float(_rs.get(&"drop_chance")) + elites * int(_rs.get(&"elite_drop")) \
			+ bosses * int(_rs.get(&"boss_drop")))
		ichor = int(ichor * (1.0 + float(_p.meta_bonus(&"ichor_gain"))))
		var result := {"victory": victory, "time": minutes * 60.0, "kills": kills, "level": level,
			"currency": ichor, "character": null}
		_bank(result, demon, heat, bosses, shards_found, bosses * _p.BOSS_HELLSTONE)
		_shop()
		var prog := _progress()
		for i in 3:
			if marks[i] == MAX_RUNS and prog >= [0.5, 0.75, 0.999][i]:
				marks[i] = run
		lines.append("%s,%d,%d,%.3f,%d,%d,%d" % [skill, career, run, prog, _p.get_currency(&"souls"),
			_p.get_currency(&"sin_shards"), _p.get_currency(&"hellstone")])
		if prog >= 0.999:
			break
	if marks[2] == MAX_RUNS and career == 0:
		print("  %s career 0 never finished; still missing: %s  maps: %s" % [skill, _missing(), _p.stats.get("maps")])
	return marks


func _missing() -> PackedStringArray:
	var out: PackedStringArray = []
	for d: Dictionary in _p.upgrade_defs + _p.unlock_defs:
		if not _p.is_maxed(StringName(d.id)):
			out.append("%s(%s)" % [d.id, _p.block_reason(StringName(d.id))])
	if _meta:
		for d: Dictionary in _meta.get(&"upgrade_defs"):
			if not _meta.call(&"is_maxed", StringName(d.id)):
				out.append("meta:" + String(d.id))
		for m: Dictionary in _meta.call(&"get_maps"):
			if not _meta.call(&"is_map_unlocked", StringName(m.id)):
				out.append("map:%s(%s)" % [m.id, _meta.call(&"map_requirement", StringName(m.id))])
	return out


func _bank(result: Dictionary, demon: StringName, heat: int, bosses: int, shards: int, hellstone: int) -> void:
	_p._reset_run_state()
	_p.run_active = true
	_p.run_heat = heat
	_p.run_demon = demon
	_p._run_bosses = bosses
	_p.run_shards = shards
	_p.run_hellstone = hellstone
	_p.run_stats[&"shard_gain"] = _p.meta_bonus(&"shard_gain")
	_p.stats.bosses_slain = int(_p.stats.get("bosses_slain", 0)) + bosses
	if _maps:
		_maps.set(&"selected_id", _best_map())
	if _meta:
		_meta.call(&"begin_run")
		_meta.call(&"finish_run", bool(result.victory), result)  # pays souls (+ Progression heat bonus)
	_p._bank_run(result)


## Spends everything greedily: cheapest affordable purchase first, until nothing is affordable.
func _shop() -> void:
	for guard in 200:
		var best := ""
		var best_cost := 1 << 30
		for id in _all_progression_ids():
			if _p.can_buy(id):
				var c: int = _norm_cost(_p.next_cost(id), _p.cost_currency(id))
				if c < best_cost:
					best_cost = c
					best = "p:" + String(id)
		if _meta:
			for d: Dictionary in _meta.get(&"upgrade_defs"):
				var mid := StringName(d.id)
				if _meta.call(&"can_buy", mid) and int(_meta.call(&"next_cost", mid)) < best_cost:
					best_cost = int(_meta.call(&"next_cost", mid))
					best = "m:" + String(mid)
			for m: Dictionary in _meta.call(&"get_maps"):
				var map_id := StringName(m.id)
				if not _meta.call(&"is_map_unlocked", map_id) and String(_meta.call(&"map_requirement", map_id)) == "" \
						and int(_meta.call(&"map_cost", map_id)) <= int(_meta.get(&"souls")) and int(_meta.call(&"map_cost", map_id)) < best_cost:
					best_cost = int(_meta.call(&"map_cost", map_id))
					best = "map:" + String(map_id)
		if best == "":
			# Nothing affordable: convert surplus into the currency the next purchase is short of.
			var short := _short_of()
			if short == &"sin_shards" and _p.transmute(&"transmute_shards"):
				continue
			if short == &"hellstone" and _p.transmute(&"transmute_hellstone"):
				continue
			return
		var kind := best.get_slice(":", 0)
		var id := StringName(best.substr(kind.length() + 1))
		match kind:
			"p": _p.buy(id)
			"m": _meta.call(&"buy", id)
			"map": _meta.call(&"unlock_map", id)


## Currency an otherwise-buyable Progression item is missing (shards before hellstone), or &"".
func _short_of() -> StringName:
	var hell := false
	for id in _all_progression_ids():
		if String(_p.block_reason(id)).begins_with("Not enough"):
			var cur: StringName = _p.cost_currency(id)
			if cur == &"sin_shards":
				return cur
			hell = hell or cur == &"hellstone"
	return &"hellstone" if hell else &""


## Souls-equivalent price so shards / hellstone purchases compete fairly in the greedy order.
func _norm_cost(cost: int, currency: StringName) -> int:
	match currency:
		&"sin_shards": return cost * 25
		&"hellstone": return cost * 120
	return cost


func _all_progression_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for d: Dictionary in _p.upgrade_defs + _p.unlock_defs:
		out.append(StringName(d.id))
	return out


## Share of the whole catalog owned: every upgrade rank, unlock, Meta rank and map (each counts 1).
func _progress() -> float:
	var have := 0
	var total := 0
	for d: Dictionary in _p.upgrade_defs + _p.unlock_defs:
		have += _p.get_level(StringName(d.id))
		total += _p.get_max_level(StringName(d.id))
	if _meta:
		for d: Dictionary in _meta.get(&"upgrade_defs"):
			have += int(_meta.call(&"get_level", StringName(d.id)))
			total += int(_meta.call(&"get_max_level", StringName(d.id)))
		for m: Dictionary in _meta.call(&"get_maps"):
			total += 1
			if _meta.call(&"is_map_unlocked", StringName(m.id)):
				have += 1
	return float(have) / maxf(total, 1)


func _catalog_summary() -> Dictionary:
	var cost := {}
	for d: Dictionary in _p.upgrade_defs + _p.unlock_defs:
		var cur := String(d.get("currency", "sin_shards"))
		var n := int(d.get("max_level", 1)) if d.get("_kind", "") == "upgrade" else 1
		for r in n:
			cost[cur] = int(cost.get(cur, 0)) + _p._cost_at(d, r)
	var meta_souls := 0
	if _meta:
		for d: Dictionary in _meta.get(&"upgrade_defs"):
			var c: Variant = d.get("cost", 0)
			for r in int(d.get("max_level", 1)):
				meta_souls += int(c[mini(r, c.size() - 1)]) if c is Array else int(round(float(c) * pow(float(d.get("cost_growth", 1.0)), r)))
		for m: Dictionary in _meta.call(&"get_maps"):
			meta_souls += int(_meta.call(&"map_cost", StringName(m.id)))
	cost["meta_souls"] = meta_souls
	cost["nodes"] = _p.upgrade_defs.size()
	return cost


## Rotates through unlocked demons so mastery spreads like a real player's would.
func _pick_demon(run: int) -> StringName:
	var open: Array[StringName] = []
	for d: StringName in DEMONS:
		var res := load("res://data/demons/%s.tres" % d)
		if _p.is_demon_unlocked(res):
			open.append(d)
	return open[run % open.size()]


## A progression-seeking player: the hardest unlocked map not yet conquered, else the hardest one.
func _best_map() -> StringName:
	var best := &""
	var best_score := -1
	if _meta:
		for m: Dictionary in _meta.call(&"get_maps"):
			if not _meta.call(&"is_map_unlocked", StringName(m.id)):
				continue
			var ms: Dictionary = _p.map_stats(StringName(m.id))
			var conquered := int(ms.get("bosses", 0)) > 0 or int(ms.get("victories", 0)) > 0
			var score := int(m.get("difficulty", 1)) + (0 if conquered else 10)
			if score > best_score:
				best_score = score
				best = StringName(m.id)
	return best


func _set_heat(heat: int) -> void:
	_p.pacts = {}
	var left := heat
	for d: Dictionary in _p.pact_defs:
		var per := int(d.get("heat_per_rank", 1))
		@warning_ignore("integer_division")
		var r := mini(int(d.get("max_rank", 1)), left / per)
		if r > 0:
			_p.pacts[String(d.id)] = r
			left -= r * per
