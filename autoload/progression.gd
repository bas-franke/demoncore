extends Node
## Progression (autoload "Progression"): the second layer of meta progression and in-run loot quality.
## See docs/team/progression.md for the full API and how it splits work with Meta and RunState.
##
## Persistent (user://progression.json, versioned, written atomically):
##   - currencies Sin Shards and Hellstone (Souls live in Meta; get_currency(&"souls") proxies to it)
##   - upgrade ranks from data/progression/upgrades.json
##   - unlocks (demons / weapons / abilities) from data/progression/unlocks.json
##   - chosen pact ranks (heat) from data/progression/pacts.json
##   - lifetime stats and free-form flags for other systems
## Per run (reset when a Player becomes ready, banked on RunState.run_ended):
##   - run stats (luck, rerolls, banishes, dash charges, ...), relics, collected shards / hellstone
##
## Hooks used (no edits to other systems needed): SceneTree.node_added (Player ready -> apply
## upgrades; Enemy entering the tree -> pact scaling), RunState.enemy_killed / run_ended /
## currency_changed, Game.boss_died, Meta.run_finished (when Meta exists).
##
## Dev args (after "--"): --unlock-all (session only), --rich (+999 shards, +99 hellstone, saved),
## --reset-progress (wipes this save at boot), --heat=N (session-only extra heat for testing),
## --relics=N (start each run with N random relics), --loot-test (drop one relic of every rarity
## plus a Sin Shard and a Hellstone around the spawn).

signal currency_changed(id: StringName, total: int)
signal upgrade_bought(id: StringName, level: int)
signal unlocked(id: StringName)
signal pacts_changed(heat: int)
## In-run: a relic was picked up (relic is the relics.json entry plus "tier": int).
signal relic_gained(relic: Dictionary)
## In-run: a Sin Shard / Hellstone pickup was collected (banked at run end).
signal run_loot_changed(id: StringName, amount: int)
## A run's rewards were banked. See _bank_run() for keys.
signal rewards_banked(rewards: Dictionary)
## A demon gained mastery XP (level = new level).
signal mastery_changed(demon_id: StringName, level: int, xp: int)
## A relic was recorded in the codex (first find or another copy).
signal codex_updated(relic_id: StringName, times_found: int)
## A codex completion milestone was reached and paid (info = codex_milestones() entry).
signal codex_milestone_reached(percent: int, info: Dictionary)
## Hellstone respec done; refund is {currency id: amount}.
signal respecced(refund: Dictionary)

## Default save file; the real location comes from save_path() (SaveProfile: tests use user://test/<profile>/).
const SAVE_PATH := "user://progression.json"
const SAVES := preload("res://scripts/save_profile.gd")
const SAVE_VERSION := 2
const DATA_DIR := "res://data/progression/"

## Run stats that are not Player properties. Upgrades/relics touching them add here instead.
const RUN_STAT_DEFAULTS := {
	&"luck": 0.0, &"rerolls": 0.0, &"banishes": 0.0, &"dash_charges": 0.0, &"starting_boons": 0.0,
	&"starting_relics": 0.0, &"ichor_gain": 0.0, &"shard_gain": 0.0,
}

# ---- drop / reward tuning
## Chance an elite drops a Sin Shard (x (1 + luck)).
const SHARD_CHANCE_ELITE := 0.3
## Chance an ordinary angel drops a Sin Shard (x (1 + luck)).
const SHARD_CHANCE_REGULAR := 0.0025
## Chance an elite drops a relic (x (1 + luck)).
const RELIC_CHANCE_ELITE := 0.12
const BOSS_SHARDS := 3
const BOSS_HELLSTONE := 1
## End of run: Sin Shards per minute survived (floored).
const SHARDS_PER_MINUTE := 0.25
const VICTORY_SHARDS := 3
## Every banked run sheds at least this many Sin Shards (catch-up for short, early-death runs).
const RUN_SHARDS := 1
## Pact rewards: per point of heat.
const HEAT_SOUL_BONUS := 0.1
const HEAT_SHARD_BONUS := 0.1
## +1 Hellstone per this much heat, if the run was won or lasted HEAT_HELLSTONE_MIN_TIME.
const HEAT_HELLSTONE_STEP := 5
const HEAT_HELLSTONE_MIN_TIME := 300.0
## RunState.heat (its generic per-minute enemy scaling) gets this fraction of our heat; the pacts'
## own effects do the rest. RunState counts 1 heat as one extra minute, which is steep.
const HEAT_TO_RUNSTATE := 0.5

const SHARD_PICKUP := preload("res://scenes/progression/shard_pickup.gd")
const RELIC_PICKUP := preload("res://scenes/progression/relic_pickup.gd")
const RUN_HUD := preload("res://scenes/progression/relic_hud.gd")
## Hellstone respec: price of the first respec, +RESPEC_COST_STEP per earlier respec, capped.
const RESPEC_ID := &"respec"
const RESPEC_BASE_COST := 1
const RESPEC_COST_STEP := 1
const RESPEC_MAX_COST := 3
## Late-game sinks (Soul Broker): repeatable conversions so surplus Souls keep paying off once the
## Souls catalogs are done. id -> [from currency, price, to currency, amount, name, icon].
const TRANSMUTES := {
	&"transmute_shards": [&"souls", 450, &"sin_shards", 1, "Distil a Sin Shard", "◆"],
	&"transmute_hellstone": [&"sin_shards", 12, &"hellstone", 1, "Smelt Hellstone", "⬢"],
}
## Relic drops: weight multiplier for relics sharing a synergy tag with the current build.
const RELIC_TAG_WEIGHT := 3.0

# ---------------------------------------------------------------- persistent state
## currency id (String) -> int. Souls are not stored here (Meta owns them).
var currencies := {}
## upgrade id (String) -> rank
var levels := {}
var unlocks: Array[String] = []
## pact id (String) -> rank
var pacts := {}
## Free-form persisted values for other systems (get_flag / set_flag).
var flags := {}
var stats := {}
## demon model id (String) -> lifetime mastery XP (int)
var mastery := {}
## relic id (String) -> times found (int). Missing = undiscovered.
var codex := {}

# ---------------------------------------------------------------- definitions
var currency_defs: Array[Dictionary] = []
var upgrade_defs: Array[Dictionary] = []
var unlock_defs: Array[Dictionary] = []
var pact_defs: Array[Dictionary] = []
var relic_defs: Array[Dictionary] = []
var _by_id := {}  # id -> def (upgrades, unlocks, pacts, relics, currencies share one namespace per kind)
var _currency_by_id := {}
var _relic_by_id := {}
var _pact_by_id := {}
## data/progression/mastery.json
var mastery_def := {}
## relics.json "codex_milestones"
var _codex_milestone_defs: Array = []

# ---------------------------------------------------------------- run state
var run_active := false
## StringName -> float (see RUN_STAT_DEFAULTS)
var run_stats := {}
## Relic ids owned this run, in pickup order.
var run_relics: Array[String] = []
var run_shards := 0
var run_hellstone := 0
var rerolls_left := 0
var banishes_left := 0
## Level-up option titles banished this run (Upgrades.roll skips them).
var banished: Array[String] = []
## Heat of the current (or last) run, frozen at run start.
var run_heat := 0
## Rewards of the last banked run (empty until one ends). Keys in _bank_run().
var last_rewards := {}

var _player: Player
## Heat bonus souls paid via Meta.run_finished (which may fire before or after our own run_ended).
var _souls_bonus := 0
var _ichor_frac := 0.0
var _adjusting_ichor := false
var _unlock_all := false
var _dev_heat := 0
var _dev_relics := 0
var _dev_drops := false
## Ability-system parts (mods, on_hit/on_kill, grants) waiting for the Abilities run to begin.
var _ability_queue: Array = []
## Demon of the current run (model id).
var run_demon: StringName = &""
var _run_bosses := 0
## Relic / signature trigger effects, replayed for weapon hits / kills (see _on_weapon_struck).
var _weapon_on_hit: Array = []
var _weapon_on_kill: Array = []


func _ready() -> void:
	_load_definitions()
	var args := OS.get_cmdline_user_args()
	if "--reset-progress" in args:
		reset_progress()
	else:
		load_game()
	_unlock_all = "--unlock-all" in args
	for a in args:
		if a.begins_with("--heat="):
			_dev_heat = a.substr(7).to_int()
		elif a.begins_with("--relics="):
			_dev_relics = a.substr(9).to_int()
	_dev_drops = "--loot-test" in args
	if "--rich" in args:
		add_currency(&"sin_shards", 999)
		add_currency(&"hellstone", 99)
	_reset_run_state()

	get_tree().node_added.connect(_on_node_added)
	# A scene launched directly (e.g. main.tscn from the editor) entered the tree together with the
	# autoloads, before node_added was connected: catch its Player here (it isn't ready yet).
	for n in get_tree().root.find_children("*", "Player", true, false):
		if not n.is_node_ready():
			_on_node_added(n)
	RunState.enemy_killed.connect(_on_enemy_killed)
	RunState.run_ended.connect(_on_run_ended)
	RunState.currency_changed.connect(_on_ichor_changed)
	Game.boss_died.connect(_on_boss_died)
	if Game.has_signal(&"enemy_struck"):
		Game.enemy_struck.connect(_on_weapon_struck)
	Game.enemy_died.connect(_on_weapon_kill)
	# Meta (basecamp) may be registered after us or not at all: connect once the tree is up.
	_connect_meta.call_deferred()


func _connect_meta() -> void:
	var meta := _meta()
	if meta and meta.has_signal(&"run_finished") and not meta.is_connected(&"run_finished", _on_meta_run_finished):
		meta.connect(&"run_finished", _on_meta_run_finished)


func _meta() -> Node:
	return get_node_or_null(^"/root/Meta")


# ================================================================ currencies

func get_currency(id: StringName) -> int:
	if id == &"souls":
		var meta := _meta()
		return int(meta.get(&"souls")) if meta else 0
	return int(currencies.get(String(id), 0))


func add_currency(id: StringName, amount: int) -> void:
	if amount == 0:
		return
	if id == &"souls":
		var meta := _meta()
		if meta:
			meta.call(&"add_souls", amount)
			currency_changed.emit(id, get_currency(id))
		return
	currencies[String(id)] = maxi(get_currency(id) + amount, 0)
	currency_changed.emit(id, get_currency(id))
	save_game()


func can_afford(id: StringName, amount: int) -> bool:
	return get_currency(id) >= amount


## Deducts `amount` of currency `id` if affordable. Returns false (and changes nothing) otherwise.
func spend(id: StringName, amount: int) -> bool:
	if amount < 0 or not can_afford(id, amount):
		return false
	if id == &"souls":
		var meta := _meta()
		var ok: bool = meta != null and bool(meta.call(&"spend", amount))
		if ok:
			currency_changed.emit(id, get_currency(id))
		return ok
	add_currency(id, -amount)
	return true


## {id, name, icon, color: Color, description}. Souls has an entry too.
func get_currency_def(id: StringName) -> Dictionary:
	return _currency_by_id.get(String(id), {"id": String(id), "name": String(id).capitalize(), "icon": "?",
		"color": Color.WHITE, "description": ""})


# ================================================================ upgrades & unlocks

func get_def(id: StringName) -> Dictionary:
	return _by_id.get(String(id), {})


## Rank of an upgrade; 1/0 for an unlock (so unlocks can be used in "requires").
func get_level(id: StringName) -> int:
	var def := get_def(id)
	if def.get("_kind", "") == "unlock":
		return 1 if is_unlocked(id) else 0
	return int(levels.get(String(id), 0))


func get_max_level(id: StringName) -> int:
	var def := get_def(id)
	if def.get("_kind", "") == "unlock":
		return 1
	return int(def.get("max_level", 1))


func is_maxed(id: StringName) -> bool:
	return get_level(id) >= get_max_level(id)


## Price of the next rank, or -1 when maxed / unknown. `cost` may be an array (one price per rank,
## the last repeats) or a number with optional `cost_growth` per rank.
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


func cost_currency(id: StringName) -> StringName:
	return StringName(String(get_def(id).get("currency", "sin_shards")))


## Why `id` can't be bought (empty string = it can).
func block_reason(id: StringName) -> String:
	var def := get_def(id)
	if def.is_empty():
		return "Unknown"
	if is_maxed(id):
		return "Unlocked" if def.get("_kind", "") == "unlock" else "Mastered"
	var req: Variant = def.get("requires", {})
	if req is Dictionary:
		for other: String in req:
			if _requirement_level(StringName(other)) < int(req[other]):
				var od := _requirement_def(StringName(other))
				var rank := "" if od.get("_kind", "") == "unlock" else " " + Upgrades.roman(int(req[other]))
				return "Requires %s%s" % [od.get("name", other), rank]
	var cost := next_cost(id)
	if not can_afford(cost_currency(id), cost):
		return "Not enough %s" % get_currency_def(cost_currency(id)).name
	return ""


func can_buy(id: StringName) -> bool:
	return block_reason(id) == ""


## Buys the next rank of an upgrade or an unlock. Returns true on success.
func buy(id: StringName) -> bool:
	if id == RESPEC_ID:
		return respec()
	if TRANSMUTES.has(id):
		return transmute(id)
	if not can_buy(id):
		return false
	var def := get_def(id)
	if not spend(cost_currency(id), next_cost(id)):
		return false
	if def.get("_kind", "") == "unlock":
		if not unlocks.has(String(id)):
			unlocks.append(String(id))
		unlocked.emit(id)
	else:
		levels[String(id)] = get_level(id) + 1
		upgrade_bought.emit(id, get_level(id))
	save_game()
	return true


func is_unlocked(id: StringName) -> bool:
	if String(id).begins_with("mastery:"):
		# "mastery:<demon model id>:<level>" or "mastery:any:<level>" (skins, see skins.json).
		var parts := String(id).split(":")
		if parts.size() < 3:
			return false
		var need := parts[2].to_int()
		if _unlock_all:
			return true
		if parts[1] == "any":
			for d: String in mastery:
				if mastery_level(StringName(d)) >= need:
					return true
			return false
		return mastery_level(StringName(parts[1])) >= need
	var def := get_def(id)
	if def.get("_kind", "") != "unlock":
		return true  # not gated
	return _unlock_all or unlocks.has(String(id))


## Unlocks `id` for free (story rewards, achievements...).
func grant_unlock(id: StringName) -> void:
	if unlocks.has(String(id)):
		return
	unlocks.append(String(id))
	unlocked.emit(id)
	save_game()


## True unless a "demon" unlock lists this DemonData's resource path and it is still locked.
func is_demon_unlocked(demon: Resource) -> bool:
	return demon == null or _resource_unlocked("demon", demon.resource_path)


func is_weapon_unlocked(scene: PackedScene) -> bool:
	return scene == null or _resource_unlocked("weapon", scene.resource_path)


## Ability owners: Progression.is_ability_unlocked(&"my_ability_id") (unlisted ids are free).
func is_ability_unlocked(ability_id: StringName) -> bool:
	for d in unlock_defs:
		if d.kind == "ability" and String(d.get("ability", d.id)) == String(ability_id):
			return is_unlocked(StringName(d.id))
	return true


## The unlock entry gating a demon (empty if it is free).
func get_demon_unlock(demon: Resource) -> Dictionary:
	if demon == null:
		return {}
	for d in unlock_defs:
		if d.kind == "demon" and d.get("resource", "") == demon.resource_path:
			return d
	return {}


## Ids of upgrades and unlocks sold by `shop`, in data order (upgrades first).
func get_shop_items(shop: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for d in upgrade_defs:
		if d.get("shop", "") == shop:
			out.append(StringName(d.id))
	for d in unlock_defs:
		if d.get("shop", "") == shop:
			out.append(StringName(d.id))
	if shop == "hellforge":
		out.append(RESPEC_ID)
	if shop == "bindings":
		out.append_array(TRANSMUTES.keys())
	return out


## Display info for a shop row: {id, kind, name, icon, description, level, max_level, maxed, cost,
## currency, currency_name, currency_icon, currency_color, effect (current), next_effect, reason}.
func item_info(id: StringName) -> Dictionary:
	if id == RESPEC_ID:
		return _respec_info()
	if TRANSMUTES.has(id):
		return _transmute_info(id)
	var def := get_def(id)
	var cur := get_currency_def(cost_currency(id))
	var lv := get_level(id)
	return {
		"id": id, "kind": def.get("_kind", ""), "name": def.get("name", String(id)),
		"icon": def.get("icon", "?"), "description": def.get("description", ""),
		"level": lv, "max_level": get_max_level(id), "maxed": is_maxed(id), "cost": next_cost(id),
		"currency": cost_currency(id), "currency_name": cur.name, "currency_icon": cur.icon,
		"currency_color": cur.color, "effect": effect_text(id, lv), "next_effect": effect_text(id, lv + 1),
		"reason": block_reason(id), "category": def.get("category", ""),
	}


## "+10% Luck, +1 Reroll" for `rank` ranks of an upgrade (empty for unlocks / rank 0).
func effect_text(id: StringName, rank: int) -> String:
	var def := get_def(id)
	if rank <= 0 or def.get("_kind", "") != "upgrade":
		return ""
	var parts: PackedStringArray = []
	for e: Dictionary in def.get("effects", []):
		parts.append(effect_line(e, rank))
	return ", ".join(parts)


## One effect entry as text at `rank` ranks (stat, ability_mod, grant_ability, on_hit / on_kill).
func effect_line(e: Dictionary, rank: int) -> String:
	if e.has("grant_ability"):
		return "Start with %s" % ability_name(StringName(String(e.grant_ability)))
	if e.has("on_hit") or e.has("on_kill"):
		return String(e.get("label", "Triggered effect"))
	var key := StringName(String(e.get("stat", e.get("ability_mod", ""))))
	var line := format_stat(key, float(e.get("per_level", 0.0)) * rank, String(e.get("format", "")),
		String(e.get("suffix", "")))
	if e.has("label"):
		line = "%s %s" % [line.get_slice(" ", 0), e.label]
	return line


## Display name of an ability id (from the Abilities registry when present).
func ability_name(id: StringName) -> String:
	var ab := _abilities()
	if ab:
		var defs: Dictionary = ab.get(&"defs")
		var d: Variant = defs.get(id)
		if d is Object and "name" in d:
			return String(d.get(&"name"))
	return String(id).capitalize()


## Sum over bought upgrades of every effect on `stat` (e.g. &"luck"). Does not include relics.
func meta_bonus(stat: StringName) -> float:
	var total := 0.0
	for d in upgrade_defs:
		var lv := get_level(StringName(d.id))
		if lv <= 0:
			continue
		for e: Dictionary in d.get("effects", []):
			if StringName(e.get("stat", "")) == stat:
				total += float(e.get("per_level", 0.0)) * lv
	return total


# ================================================================ pacts (heat)

func get_pact_rank(id: StringName) -> int:
	return int(pacts.get(String(id), 0))


## Sets a pact's rank (clamped to 0..max_rank). Takes effect from the next run.
func set_pact_rank(id: StringName, rank: int) -> void:
	var def: Dictionary = _pact_by_id.get(String(id), {})
	if def.is_empty():
		return
	rank = clampi(rank, 0, int(def.get("max_rank", 1)))
	if rank == 0:
		pacts.erase(String(id))
	else:
		pacts[String(id)] = rank
	pacts_changed.emit(get_heat())
	save_game()


## Total heat of the chosen pacts (plus the --heat= dev arg).
func get_heat() -> int:
	var h := _dev_heat
	for d in pact_defs:
		h += get_pact_rank(StringName(d.id)) * int(d.get("heat_per_rank", 1))
	return h


## Sum of a pact effect over the chosen ranks, e.g. pact_total(&"enemy_hp") = 0.3 for +30%.
func pact_total(effect: StringName) -> float:
	var t := 0.0
	for d in pact_defs:
		var r := get_pact_rank(StringName(d.id))
		if r > 0:
			t += float((d.get("effects", {}) as Dictionary).get(String(effect), 0.0)) * r
	return t


## What the current heat adds to a run's rewards: {soul_bonus, shard_bonus (fractions), hellstone}.
func heat_rewards(heat: int = -1) -> Dictionary:
	if heat < 0:
		heat = get_heat()
	return {"soul_bonus": heat * HEAT_SOUL_BONUS, "shard_bonus": heat * HEAT_SHARD_BONUS,
		"hellstone": _hellstone_for_heat(heat)}


## Bonus Hellstone for a heat level: one per full HEAT_HELLSTONE_STEP points (partial steps give none).
static func _hellstone_for_heat(heat: int) -> int:
	@warning_ignore("integer_division")
	return heat / HEAT_HELLSTONE_STEP


# ================================================================ run: start

## Called when a Player has finished _ready (hp is already filled; we refill after our bonuses).
## Applies the upgrade tree, pacts and unlock filters, then grants starting boons / relics.
func apply_to_player(player: Player) -> void:
	_reset_run_state()
	run_active = true
	_player = player
	run_heat = get_heat()
	RunState.heat = int(round(run_heat * HEAT_TO_RUNSTATE))

	_ability_queue.clear()
	_run_bosses = 0
	for d in upgrade_defs:
		var lv := get_level(StringName(d.id))
		if lv <= 0:
			continue
		for e: Dictionary in d.get("effects", []):
			apply_effect(e, lv)
	_apply_codex_bonuses()
	# Mastery: the demon's signature boon (rank 1 at mastery III, rank 2 at VII).
	run_demon = demon_id_of(player.character)
	var sig := signature_rank(run_demon)
	if sig > 0:
		for e: Dictionary in signature_info(run_demon).get("effects", []):
			apply_effect(e, sig)
	var frail := pact_total(&"player_max_hp")
	if frail > 0.0:
		player.apply_stat(&"max_hp", -player.max_hp * minf(frail, 0.8))
	player.hp = player.max_hp
	# Bought dash charges (Shadowstep) start full: the dash filled itself before our bonus landed.
	var dash: Variant = player.get(&"dash")
	if dash is Node and (dash as Node).has_method(&"max_charges"):
		var mc := int(dash.call(&"max_charges"))
		dash.set(&"charges", mc)
		if (dash as Node).has_signal(&"charges_changed"):
			dash.emit_signal(&"charges_changed", mc, mc)

	# Locked weapons never show up as level-up offers (the demon's own starting weapon is kept).
	var pool: Array[PackedScene] = []
	for scene in player.weapon_pool:
		if is_weapon_unlocked(scene) or scene == player.starting_weapon:
			pool.append(scene)
	player.weapon_pool = pool

	rerolls_left = int(get_run_stat(&"rerolls"))
	banishes_left = int(get_run_stat(&"banishes"))
	for i in int(get_run_stat(&"starting_boons")):
		_grant_random_boon(player)
	for i in int(get_run_stat(&"starting_relics")) + _dev_relics:
		grant_relic(roll_relic(Rarity.COMMON, Rarity.RARE if _dev_relics == 0 else Rarity.LEGENDARY), false)
	if _dev_drops:
		# Dev: a relic of every tier and some loot in a ring around the spawn, for eyeballing.
		for t in Rarity.LEGENDARY + 1:
			var a := TAU * t / 5.0
			drop_relic(player.global_position + Vector3(cos(a), 0.0, sin(a)) * 4.0, t)
		drop_loot(player.global_position + Vector3(0.0, 0.0, 2.0), &"sin_shards")
		drop_loot(player.global_position + Vector3(1.5, 0.0, 2.0), &"hellstone")
	_scale_spawner.call_deferred()
	_add_run_hud.call_deferred()
	# Abilities binds its run in a deferred call queued when the Player entered the tree (before
	# this ready hook), so this deferred flush runs after it.
	_flush_ability_queue.call_deferred()


## Applies one upgrade / signature effect at `rank`: {stat}, {ability_mod}, {grant_ability},
## {on_hit} / {on_kill} (Abilities effect dictionaries, added once per rank).
func apply_effect(e: Dictionary, rank: int) -> void:
	if e.has("stat"):
		apply_stat(StringName(String(e.stat)), float(e.get("per_level", 0.0)) * rank)
	elif e.has("ability_mod"):
		_ability_part(["mod", String(e.ability_mod), float(e.get("per_level", 0.0)) * rank])
	elif e.has("grant_ability"):
		_ability_part(["grant", StringName(String(e.grant_ability))])
	if e.has("on_hit"):
		for i in rank:
			_ability_part(["on_hit", e.on_hit])
	if e.has("on_kill"):
		for i in rank:
			_ability_part(["on_kill", e.on_kill])


## Ability-system part: applied now if the Abilities run is bound to our player, else queued
## until _flush_ability_queue (run start).
func _ability_part(part: Array) -> void:
	var ab := _abilities()
	if ab and is_instance_valid(_player) and ab.get(&"player") == _player and _ability_queue.is_empty():
		_apply_ability_part(ab, part)
		_recompute_casters(ab)
	else:
		_ability_queue.append(part)


func _flush_ability_queue() -> void:
	var ab := _abilities()
	if ab == null or not is_instance_valid(_player):
		_ability_queue.clear()
		return
	var queue := _ability_queue.duplicate()
	_ability_queue.clear()
	for part: Array in queue:
		_apply_ability_part(ab, part)
	_recompute_casters(ab)


func _apply_ability_part(ab: Node, part: Array) -> void:
	match String(part[0]):
		"mod":
			var mods: Dictionary = ab.get(&"mods")
			mods[String(part[1])] = float(mods.get(String(part[1]), 0.0)) + float(part[2])
		"grant":
			if not bool(ab.call(&"has_ability", part[1])):
				ab.call(&"grant", part[1])
		"on_hit":
			(ab.get(&"global_on_hit") as Array).append(part[1])
			_weapon_on_hit.append(part[1])
		"on_kill":
			(ab.get(&"global_on_kill") as Array).append(part[1])
			_weapon_on_kill.append(part[1])


# ---- weapon hits (relic / signature effects)
# Abilities runs global_on_hit / global_on_kill only for ability hits (AbilityCombat.hit). Our own
# effects (relics, signature boons) should fire for weapon hits too, so we replay just those on
# Game.enemy_struck / enemy_died when no ability hit is in progress (AbilityCombat.in_hit == 0).
# The weapon's damage isn't known per effect, so damage-scaled effects use the struck amount.

## Damage used for weapon kills' on_kill effects (explode fractions etc.), x player might.
const WEAPON_KILL_BASE_DAMAGE := 12.0
## Weapon-triggered effects run at depth 1 (their own damage can't re-trigger anything).
const WEAPON_FX_TAGS := ["weapon"]


func _on_weapon_struck(enemy: Node3D, amount: float) -> void:
	if _weapon_on_hit.is_empty() or not run_active or AbilityCombat.in_hit > 0:
		return
	var e := enemy as Enemy
	if e == null or e.is_dying or not is_instance_valid(e):
		return
	var src := {"tags": PackedStringArray(WEAPON_FX_TAGS), "depth": 1, "color": Art.EMBER}
	var ctx := {"pos": e.global_position, "enemy": e, "damage": amount, "src": src, "had": {}, "killed": false}
	for fx: Dictionary in _weapon_on_hit:
		AbilityCombat.run_effect(fx, ctx)


func _on_weapon_kill(pos: Vector3, _data: Resource) -> void:
	if _weapon_on_kill.is_empty() or not run_active or AbilityCombat.in_hit > 0:
		return
	var src := {"tags": PackedStringArray(WEAPON_FX_TAGS), "depth": 1, "color": Art.EMBER}
	var dmg := WEAPON_KILL_BASE_DAMAGE * (_player.might if is_instance_valid(_player) else 1.0)
	var ctx := {"pos": pos, "enemy": null, "damage": dmg, "src": src, "had": {}, "killed": true}
	for fx: Dictionary in _weapon_on_kill:
		AbilityCombat.run_effect(fx, ctx)


## Area / count modifiers change persistent caster visuals (auras, orbits): let them rebuild.
func _recompute_casters(ab: Node) -> void:
	var casters: Dictionary = ab.get(&"casters")
	for c: Variant in casters.values():
		if c is Node and is_instance_valid(c) and (c as Node).has_method(&"_recompute"):
			(c as Node).call(&"_recompute")


func _abilities() -> Node:
	return get_node_or_null(^"/root/Abilities")


## Adds `amount` to a Player stat, or to a Progression run stat when the Player has no such property.
func apply_stat(stat: StringName, amount: float) -> void:
	if stat == &"" or amount == 0.0:
		return
	if is_instance_valid(_player) and stat in _player:
		_player.apply_stat(stat, amount)
	else:
		run_stats[stat] = float(run_stats.get(stat, 0.0)) + amount


## A run stat (luck, rerolls, ichor_gain, ...): the Player's property if it has one, else ours.
func get_run_stat(stat: StringName) -> float:
	if is_instance_valid(_player) and stat in _player:
		return float(_player.get(stat))
	return float(run_stats.get(stat, 0.0))


func get_luck() -> float:
	return maxf(get_run_stat(&"luck"), 0.0)


func _reset_run_state() -> void:
	run_active = false
	run_stats = RUN_STAT_DEFAULTS.duplicate()
	run_relics.clear()
	run_shards = 0
	run_hellstone = 0
	rerolls_left = 0
	banishes_left = 0
	banished.clear()
	_ichor_frac = 0.0
	_souls_bonus = 0
	_player = null
	_weapon_on_hit.clear()
	_weapon_on_kill.clear()


func _grant_random_boon(player: Player) -> void:
	var options: Array[PassiveData] = []
	for pd in player.passive_pool:
		if player.passive_levels.get(pd, 0) < pd.max_level:
			options.append(pd)
	if not options.is_empty():
		player.add_passive(options.pick_random())


func _scale_spawner() -> void:
	var rate := 1.0 + pact_total(&"spawn_rate")
	if rate == 1.0 or not is_instance_valid(_player):
		return
	for s in get_tree().current_scene.find_children("*", "EnemySpawner", true, false):
		s.set(&"base_rate", float(s.get(&"base_rate")) * rate)
		s.set(&"rate_growth", float(s.get(&"rate_growth")) * rate)


func _add_run_hud() -> void:
	var scene := get_tree().current_scene
	if scene and is_instance_valid(_player) and scene.get_node_or_null(^"ProgressionHud") == null:
		var hud: CanvasLayer = RUN_HUD.new()
		hud.name = &"ProgressionHud"
		scene.add_child(hud)


# ================================================================ run: during

## Relic entry for `id` (plus "tier"), or {}.
func get_relic(id: StringName) -> Dictionary:
	return _relic_by_id.get(String(id), {})


## Random relic id not owned this run, of a rarity rolled with the current luck. "" if none left.
func roll_relic(min_tier: int = Rarity.COMMON, max_tier: int = Rarity.LEGENDARY) -> StringName:
	var tier := Rarity.roll(get_luck(), min_tier, max_tier)
	# Prefer the rolled tier, then step down, then up, so a drop is never wasted.
	var order: Array[int] = [tier]
	for t in range(tier - 1, -1, -1):
		order.append(t)
	for t in range(tier + 1, Rarity.LEGENDARY + 1):
		order.append(t)
	var owned := _owned_tags()
	for t in order:
		var pool: Array[StringName] = []
		var weights: Array[float] = []
		var total := 0.0
		for r in relic_defs:
			if int(r.tier) == t and not run_relics.has(String(r.id)):
				# Relics that feed the current build's synergy tags drop more often.
				var w := 1.0
				for tag: Variant in r.get("tags", []):
					if owned.has(String(tag)):
						w = RELIC_TAG_WEIGHT
						break
				pool.append(StringName(r.id))
				weights.append(w)
				total += w
		if not pool.is_empty():
			var x := randf() * total
			for i in pool.size():
				x -= weights[i]
				if x <= 0.0:
					return pool[i]
			return pool[-1]
	return &""


## Synergy tags of the current build (Abilities.owned_tags), as String -> count.
func _owned_tags() -> Dictionary:
	var ab := _abilities()
	if ab == null or not is_instance_valid(_player) or not ab.has_method(&"owned_tags"):
		return {}
	var out := {}
	var tags: Dictionary = ab.call(&"owned_tags")
	for k: Variant in tags:
		out[String(k)] = tags[k]
	return out


## Gives the relic to the player now (stats, heal, HUD banner). Returns false if unknown / owned.
func grant_relic(id: StringName, announce: bool = true) -> bool:
	var r := get_relic(id)
	if r.is_empty() or run_relics.has(String(id)) or not is_instance_valid(_player):
		return false
	run_relics.append(String(id))
	var st: Variant = r.get("stats", {})
	if st is Dictionary:
		for k: String in st:
			apply_stat(StringName(k), float(st[k]))
	if r.has("heal"):
		_player.heal(float(r.heal))
	var am: Variant = r.get("ability_mods", {})
	if am is Dictionary:
		for k: String in am:
			_ability_part(["mod", k, float(am[k])])
	for fx: Variant in r.get("on_hit", []):
		_ability_part(["on_hit", fx])
	for fx: Variant in r.get("on_kill", []):
		_ability_part(["on_kill", fx])
	stats.relics_found = int(stats.get("relics_found", 0)) + 1
	_record_codex(id)
	if announce:
		var hud := get_tree().get_first_node_in_group(&"hud")
		if hud and hud.has_method(&"toast"):
			hud.call(&"toast", "%s  ·  %s" % [r.name, Rarity.display_name(int(r.tier))], Rarity.color(int(r.tier)))
	relic_gained.emit(r)
	return true


## In-run loot (banked when the run ends). id: &"sin_shards" or &"hellstone".
func collect_run_loot(id: StringName, amount: int) -> void:
	if id == &"hellstone":
		run_hellstone += amount
	else:
		run_shards += amount
	run_loot_changed.emit(id, run_shards if id == &"sin_shards" else run_hellstone)


## Level-up menu: spends a reroll charge. Returns false when none are left.
func use_reroll() -> bool:
	if rerolls_left <= 0:
		return false
	rerolls_left -= 1
	return true


## Level-up menu: banishes an option (by title) for the rest of the run.
func use_banish(title: String) -> bool:
	if banishes_left <= 0:
		return false
	banishes_left -= 1
	if not banished.has(title):
		banished.append(title)
	return true


func is_banished(title: String) -> bool:
	return banished.has(title)


## Spawns a Sin Shard / Hellstone pickup (deferred; safe from physics callbacks).
func drop_loot(at: Vector3, id: StringName, amount: int = 1) -> void:
	var p: Area3D = SHARD_PICKUP.new()
	p.set(&"currency", id)
	p.set(&"value", amount)
	var off := Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))
	Game.spawn.call_deferred(p, Vector3(at.x, 0.0, at.z) + off)


## Spawns a relic pickup holding a rolled relic. Returns false if every relic is already owned.
func drop_relic(at: Vector3, min_tier: int = Rarity.COMMON) -> bool:
	var id := roll_relic(min_tier)
	if id == &"":
		return false
	var p: Area3D = RELIC_PICKUP.new()
	p.set(&"relic_id", id)
	Game.spawn.call_deferred(p, Vector3(at.x, 0.0, at.z))
	return true


func _on_node_added(node: Node) -> void:
	if node is Player:
		node.ready.connect(apply_to_player.bind(node), CONNECT_ONE_SHOT)
	elif node is Enemy and run_active:
		_scale_enemy(node as Enemy)


## Pact scaling on top of the spawner's own (setup() already ran; _ready has not).
func _scale_enemy(e: Enemy) -> void:
	var hp_m := 1.0 + pact_total(&"enemy_hp")
	var dmg_m := 1.0 + pact_total(&"enemy_damage")
	var spd_m := 1.0 + pact_total(&"enemy_speed")
	if hp_m != 1.0:
		e.max_hp *= hp_m
		e.hp = e.max_hp
	e.damage *= dmg_m
	e.speed *= spd_m


func _on_enemy_killed(pos: Vector3, data: Resource, elite: bool) -> void:
	if not run_active or data == null or RunState.is_boss_data(data):
		return  # bosses are handled in _on_boss_died (enemy_killed now carries their data)
	var luck := 1.0 + get_luck()
	if randf() < (SHARD_CHANCE_ELITE if elite else SHARD_CHANCE_REGULAR) * luck:
		drop_loot(pos, &"sin_shards")
	if elite and randf() < RELIC_CHANCE_ELITE * luck:
		drop_relic(pos)


func _on_boss_died(pos: Vector3) -> void:
	if not run_active:
		return
	drop_relic(pos, Rarity.RARE)
	for i in BOSS_SHARDS:
		drop_loot(pos, &"sin_shards")
	drop_loot(pos, &"hellstone", BOSS_HELLSTONE)
	stats.bosses_slain = int(stats.get("bosses_slain", 0)) + 1
	_run_bosses += 1


## Ichor bonus/penalty: RunState banks the base amount, we add (or take) the difference.
## Fractions accumulate so +10% on single drops still pays out.
func _on_ichor_changed(_total: int, delta: int) -> void:
	if _adjusting_ichor or delta <= 0 or not run_active:
		return
	var mult := get_run_stat(&"ichor_gain") - pact_total(&"ichor_gain")
	if mult == 0.0:
		return
	_ichor_frac += delta * mult
	var whole := int(_ichor_frac)  # truncates toward zero for negatives too
	if whole == 0:
		return
	_ichor_frac -= whole
	_adjusting_ichor = true
	if whole > 0:
		RunState.add_currency(whole)
	else:
		RunState.spend_currency(mini(-whole, RunState.currency))
	_adjusting_ichor = false


# ================================================================ run: end

func _on_run_ended(result: Dictionary) -> void:
	if run_active:
		_bank_run(result)


## Banks the run's Sin Shards / Hellstone and updates stats. Returns the rewards dictionary:
## {victory, heat, time, shards, hellstone, shards_base, shard_mult, relics: Array[String], souls_bonus}.
func _bank_run(result: Dictionary) -> Dictionary:
	run_active = false
	var victory := bool(result.get("victory", false))
	var time := float(result.get("time", Game.elapsed))
	var r := compute_run_rewards(time, victory, run_shards, run_hellstone, run_heat, get_run_stat(&"shard_gain"))
	var base := int(r.shards_base)
	var mult := float(r.shard_mult)
	var shards := int(r.shards)
	var hellstone := int(r.hellstone)
	_record_map_run(result, victory, time)
	var mastery_result := _award_mastery(run_demon, result, victory, time)
	stats.runs = int(stats.get("runs", 0)) + 1
	stats.highest_heat = maxi(int(stats.get("highest_heat", 0)), run_heat)
	if victory:
		stats.victories = int(stats.get("victories", 0)) + 1
		stats.highest_heat_won = maxi(int(stats.get("highest_heat_won", 0)), run_heat)
	stats.shards_earned = int(stats.get("shards_earned", 0)) + shards
	stats.hellstone_earned = int(stats.get("hellstone_earned", 0)) + hellstone
	currencies["sin_shards"] = get_currency(&"sin_shards") + shards
	currencies["hellstone"] = get_currency(&"hellstone") + hellstone
	last_rewards = {
		"victory": victory, "heat": run_heat, "time": time, "shards": shards, "hellstone": hellstone,
		"shards_base": base, "shard_mult": mult, "relics": run_relics.duplicate(), "souls_bonus": _souls_bonus,
		"mastery": mastery_result,
	}
	save_game()
	currency_changed.emit(&"sin_shards", get_currency(&"sin_shards"))
	currency_changed.emit(&"hellstone", get_currency(&"hellstone"))
	rewards_banked.emit(last_rewards)
	return last_rewards


## Meta paid its soul reward: add the heat bonus on top.
func _on_meta_run_finished(summary: Dictionary) -> void:
	var souls := int(summary.get("souls", 0))
	var bonus := int(round(souls * float(heat_rewards(run_heat).soul_bonus)))
	if bonus > 0:
		add_currency(&"souls", bonus)
	_souls_bonus = bonus
	if not run_active:
		last_rewards["souls_bonus"] = bonus  # we banked first


## One line for end-of-run screens, e.g. "+4 Sin Shards  ·  +1 Hellstone  ·  Heat 3 (+30% Souls)".
func rewards_text(rewards: Dictionary = last_rewards) -> String:
	if rewards.is_empty():
		return ""
	var parts: PackedStringArray = []
	var sd := get_currency_def(&"sin_shards")
	parts.append("+%d %s" % [int(rewards.shards), sd.name])
	if int(rewards.hellstone) > 0:
		parts.append("+%d %s" % [int(rewards.hellstone), get_currency_def(&"hellstone").name])
	if int(rewards.heat) > 0:
		parts.append("Heat %d (+%d bonus Souls)" % [int(rewards.heat), int(rewards.get("souls_bonus", 0))])
	if not (rewards.relics as Array).is_empty():
		parts.append("%d relics" % (rewards.relics as Array).size())
	var m: Dictionary = rewards.get("mastery", {})
	if not m.is_empty() and int(m.get("xp", 0)) > 0:
		var up := int(m.level_after) > int(m.level_before)
		parts.append("%s mastery +%d XP%s" % [m.get("name", ""), int(m.xp),
			("  (rank %s!)" % Upgrades.roman(int(m.level_after))) if up else ""])
	return "  ·  ".join(parts)


## Pure reward formula (also used by tools/progression_economy_sim.gd):
## {shards, hellstone, shards_base, shard_mult}.
static func compute_run_rewards(time: float, victory: bool, shards_found: int, hellstone_found: int,
		heat: int, shard_gain: float) -> Dictionary:
	var base := RUN_SHARDS + shards_found + int(time / 60.0 * SHARDS_PER_MINUTE) + (VICTORY_SHARDS if victory else 0)
	var mult := 1.0 + shard_gain + heat * HEAT_SHARD_BONUS
	var hellstone := hellstone_found
	if victory or time >= HEAT_HELLSTONE_MIN_TIME:
		hellstone += _hellstone_for_heat(heat)
	return {"shards": int(round(base * mult)), "hellstone": hellstone, "shards_base": base, "shard_mult": mult}


# ================================================================ mastery (per demon)

## Model id used as the mastery / skin key for a DemonData ("vharok"). Same rule as DemonSkins.
static func demon_id_of(demon: Resource) -> StringName:
	if demon == null or not demon.has_method(&"get_model_path"):
		return &""
	return StringName(String(demon.call(&"get_model_path")).get_file().get_basename())


func get_mastery_xp(demon_id: StringName) -> int:
	return int(mastery.get(String(demon_id), 0))


## XP needed to go from `level` to level + 1.
func mastery_step(level: int) -> int:
	return int(mastery_def.get("level_base", 80)) + int(mastery_def.get("level_step", 40)) * (level - 1)


func mastery_max_level() -> int:
	return int(mastery_def.get("max_level", 10))


func mastery_level_for_xp(xp: int) -> int:
	var lv := 1
	while lv < mastery_max_level() and xp >= mastery_step(lv):
		xp -= mastery_step(lv)
		lv += 1
	return lv


func mastery_level(demon_id: StringName) -> int:
	return mastery_level_for_xp(get_mastery_xp(demon_id))


## {level, xp (total), into (xp into this level), need (xp for the next), maxed, signature_rank,
##  next_reward (text)} for UI bars.
func mastery_progress(demon_id: StringName) -> Dictionary:
	var xp := get_mastery_xp(demon_id)
	var lv := 1
	var rest := xp
	while lv < mastery_max_level() and rest >= mastery_step(lv):
		rest -= mastery_step(lv)
		lv += 1
	var maxed := lv >= mastery_max_level()
	return {"level": lv, "xp": xp, "into": rest, "need": 0 if maxed else mastery_step(lv), "maxed": maxed,
		"signature_rank": signature_rank(demon_id), "next_reward": "" if maxed else mastery_reward_text(demon_id, lv + 1)}


## Rewards granted on reaching `level` (generic + demon-specific), as data entries.
func mastery_rewards(demon_id: StringName, level: int) -> Array:
	var out: Array = []
	out.append_array((mastery_def.get("rewards", {}) as Dictionary).get(str(level), []))
	var d: Dictionary = (mastery_def.get("demons", {}) as Dictionary).get(String(demon_id), {})
	out.append_array((d.get("rewards", {}) as Dictionary).get(str(level), []))
	return out


func mastery_reward_text(demon_id: StringName, level: int) -> String:
	var parts: PackedStringArray = []
	for rw: Dictionary in mastery_rewards(demon_id, level):
		if rw.has("signature"):
			parts.append("%s %s" % [signature_info(demon_id).get("name", "Signature boon"), Upgrades.roman(int(rw.signature))])
		elif rw.has("skin"):
			parts.append("Skin: %s" % _skin_name(_mastery_skin_id(demon_id, String(rw.skin))))
		elif rw.has("currency"):
			parts.append("+%d %s" % [int(rw.get("amount", 0)), get_currency_def(StringName(String(rw.currency))).name])
	return ", ".join(parts)


## Signature boon rank (0 = not yet) from the reward table and the demon's mastery level.
func signature_rank(demon_id: StringName) -> int:
	if demon_id == &"":
		return 0
	var lv := mastery_level(demon_id)
	var rank := 0
	for l in range(2, lv + 1):
		for rw: Dictionary in mastery_rewards(demon_id, l):
			if rw.has("signature"):
				rank = maxi(rank, int(rw.signature))
	return rank


## {name, icon, description, effects} of the demon's signature boon ({} if it has none).
func signature_info(demon_id: StringName) -> Dictionary:
	var d: Dictionary = (mastery_def.get("demons", {}) as Dictionary).get(String(demon_id), {})
	return d.get("signature", {})


## "Ravager's Fury II: +30% Brimstone damage, ..." for the select screen ("" if none).
func signature_text(demon_id: StringName) -> String:
	var info := signature_info(demon_id)
	if info.is_empty():
		return ""
	var rank := maxi(signature_rank(demon_id), 1)
	var parts: PackedStringArray = []
	for e: Dictionary in info.get("effects", []):
		parts.append(effect_line(e, rank))
	return "%s %s: %s" % [info.get("name", ""), Upgrades.roman(rank), ", ".join(parts)]


## Mastery XP a run is worth (pure, used by the economy sim too).
func mastery_xp_for(time: float, kills: int, level: int, bosses: int, victory: bool, heat: int) -> int:
	var x: Dictionary = mastery_def.get("xp", {})
	var v := float(x.get("base", 10)) + float(x.get("per_minute", 8)) * time / 60.0 \
		+ float(x.get("per_kill", 0.02)) * kills + float(x.get("per_level", 2)) * level \
		+ float(x.get("per_boss", 25)) * bosses + (float(x.get("victory", 60)) if victory else 0.0)
	return int(round(v * (1.0 + float(x.get("heat_bonus", 0.05)) * heat)))


## Adds XP (pays currency rewards for every level crossed) and returns
## {demon, name, xp, level_before, level_after, rewards: Array[String]}.
func add_mastery_xp(demon_id: StringName, xp: int, display_name: String = "") -> Dictionary:
	if demon_id == &"" or xp <= 0:
		return {}
	var before := mastery_level(demon_id)
	mastery[String(demon_id)] = get_mastery_xp(demon_id) + xp
	var after := mastery_level(demon_id)
	var texts: Array[String] = []
	for lv in range(before + 1, after + 1):
		for rw: Dictionary in mastery_rewards(demon_id, lv):
			if rw.has("currency"):
				var cid := StringName(String(rw.currency))
				if cid == &"souls":
					add_currency(cid, int(rw.get("amount", 0)))
				else:
					currencies[String(cid)] = get_currency(cid) + int(rw.get("amount", 0))
		texts.append(mastery_reward_text(demon_id, lv))
	mastery_changed.emit(demon_id, after, get_mastery_xp(demon_id))
	return {"demon": String(demon_id), "name": display_name if display_name != "" else String(demon_id).capitalize(),
		"xp": xp, "level_before": before, "level_after": after, "rewards": texts}


func _award_mastery(demon_id: StringName, result: Dictionary, victory: bool, time: float) -> Dictionary:
	var xp := mastery_xp_for(time, int(result.get("kills", Game.kills)), int(result.get("level", 1)),
		_run_bosses, victory, run_heat)
	var dname := ""
	var ch: Variant = result.get("character")
	if ch is Resource and "display_name" in ch:
		dname = String(ch.get(&"display_name"))
	return add_mastery_xp(demon_id, xp, dname)


func _mastery_skin_id(demon_id: StringName, key: String) -> String:
	if key == "mastery":
		var d: Dictionary = (mastery_def.get("demons", {}) as Dictionary).get(String(demon_id), {})
		return String(d.get("skin", ""))
	return key


func _skin_name(skin_id: String) -> String:
	if ResourceLoader.exists("res://scripts/characters/demon_skins.gd"):
		var ds: Script = load("res://scripts/characters/demon_skins.gd")
		var sk: Dictionary = ds.call(&"get_skin", StringName(skin_id))
		if not sk.is_empty():
			return String(sk.get("name", skin_id))
	return skin_id.capitalize()


# ================================================================ relic codex

func _record_codex(id: StringName) -> void:
	var n := int(codex.get(String(id), 0)) + 1
	codex[String(id)] = n
	if n == 1:
		var hud := get_tree().get_first_node_in_group(&"hud")
		if hud and hud.has_method(&"toast") and run_active:
			hud.call(&"toast", "New relic recorded in the Codex", UIPalette.BRIMSTONE)
	codex_updated.emit(id, n)
	if n == 1:
		_check_codex_milestones()


## Codex completion rewards (relics.json "codex_milestones"): paid once each, when the share of
## discovered relics reaches `percent`. Currency rewards are banked at once; {stat} rewards are
## permanent run bonuses applied in apply_to_player.
func codex_milestones() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var prog := codex_progress()
	var pct := 100.0 * float(prog.found) / maxf(float(prog.total), 1.0)
	var claimed: Array = stats.get("codex_milestones", [])
	for m: Dictionary in _codex_milestone_defs:
		var parts: PackedStringArray = []
		for rw: Dictionary in m.get("rewards", []):
			if rw.has("currency"):
				parts.append("+%d %s" % [int(rw.amount), get_currency_def(StringName(String(rw.currency))).name])
			elif rw.has("stat"):
				parts.append(format_stat(StringName(String(rw.stat)), float(rw.amount), String(rw.get("format", ""))) + " (permanent)")
		out.append({"percent": int(m.percent), "name": m.get("name", ""), "reached": pct >= float(m.percent),
			"claimed": claimed.has(int(m.percent)), "reward_text": ", ".join(parts),
			"relics_needed": int(ceil(float(m.percent) / 100.0 * float(prog.total)))})
	return out


func _check_codex_milestones() -> void:
	var claimed: Array = stats.get("codex_milestones", [])
	for m in codex_milestones():
		if not m.reached or m.claimed:
			continue
		claimed.append(int(m.percent))
		for d: Dictionary in _codex_milestone_defs:
			if int(d.percent) != int(m.percent):
				continue
			for rw: Dictionary in d.get("rewards", []):
				if rw.has("currency"):
					var cid := StringName(String(rw.currency))
					if cid == &"souls":
						add_currency(cid, int(rw.amount))
					else:
						currencies[String(cid)] = get_currency(cid) + int(rw.amount)
						currency_changed.emit(cid, get_currency(cid))
		stats["codex_milestones"] = claimed
		var hud := get_tree().get_first_node_in_group(&"hud")
		if hud and hud.has_method(&"toast"):
			hud.call(&"toast", "Codex %d%%: %s  ·  %s" % [int(m.percent), m.name, m.reward_text], UIPalette.BRIMSTONE)
		codex_milestone_reached.emit(int(m.percent), m)
	save_game()


## Permanent stat bonuses from claimed codex milestones (applied at run start).
func _apply_codex_bonuses() -> void:
	var claimed: Array = stats.get("codex_milestones", [])
	for d: Dictionary in _codex_milestone_defs:
		if claimed.has(int(d.percent)):
			for rw: Dictionary in d.get("rewards", []):
				if rw.has("stat"):
					apply_stat(StringName(String(rw.stat)), float(rw.amount))


## Every relic for a codex screen, in data order: {id, name, icon, rarity (id), tier, color,
## description, tags, discovered, times_found}. Undiscovered entries keep their name/icon so the UI
## can choose to show them as silhouettes ("???").
func codex_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in relic_defs:
		var n := int(codex.get(String(r.id), 0))
		out.append({"id": StringName(r.id), "name": r.get("name", r.id), "icon": r.get("icon", "?"),
			"rarity": Rarity.id_of(int(r.tier)), "tier": int(r.tier), "color": Rarity.color(int(r.tier)),
			"description": r.get("description", ""), "tags": r.get("tags", []), "discovered": n > 0,
			"times_found": n})
	return out


## {found, total, by_tier: {rarity id: [found, total]}}.
func codex_progress() -> Dictionary:
	var by := {}
	var found := 0
	for r in relic_defs:
		var key := String(Rarity.id_of(int(r.tier)))
		var pair: Array = by.get(key, [0, 0])
		pair[1] += 1
		if int(codex.get(String(r.id), 0)) > 0:
			pair[0] += 1
			found += 1
		by[key] = pair
	return {"found": found, "total": relic_defs.size(), "by_tier": by}


# ================================================================ Hellstone respec

## Hellstone price of the next respec.
func respec_cost() -> int:
	return mini(RESPEC_BASE_COST + RESPEC_COST_STEP * int(stats.get("respecs", 0)), RESPEC_MAX_COST)


## What a respec would give back: {currency id: amount} (every rank of every upgrade, at the price
## it was bought for; unlocks are permanent and not refunded).
func respec_refund() -> Dictionary:
	var out := {}
	for d in upgrade_defs:
		var id := StringName(d.id)
		var lv := get_level(id)
		if lv <= 0:
			continue
		var cur := String(cost_currency(id))
		var total := 0
		for rank in lv:
			total += _cost_at(d, rank)
		out[cur] = int(out.get(cur, 0)) + total
	return out


## Refunds every upgrade rank for respec_cost() Hellstone. False if nothing to refund / can't pay.
func respec() -> bool:
	var refund := respec_refund()
	if refund.is_empty() or not can_afford(&"hellstone", respec_cost()):
		return false
	currencies["hellstone"] = get_currency(&"hellstone") - respec_cost()
	levels = {}
	for cur: String in refund:
		if cur == "souls":
			add_currency(&"souls", int(refund[cur]))
		else:
			currencies[cur] = get_currency(StringName(cur)) + int(refund[cur])
	stats.respecs = int(stats.get("respecs", 0)) + 1
	save_game()
	for cur: String in ["sin_shards", "hellstone"]:
		currency_changed.emit(StringName(cur), get_currency(StringName(cur)))
	respecced.emit(refund)
	return true


func _respec_info() -> Dictionary:
	var hs := get_currency_def(&"hellstone")
	var refund := respec_refund()
	var parts: PackedStringArray = []
	for cur: String in refund:
		parts.append("%d %s" % [int(refund[cur]), get_currency_def(StringName(cur)).name])
	var reason := ""
	if refund.is_empty():
		reason = "Nothing to unbind"
	elif not can_afford(&"hellstone", respec_cost()):
		reason = "Not enough %s" % hs.name
	return {
		"id": RESPEC_ID, "kind": "action", "name": "Unbinding Rite", "icon": "⟲",
		"description": "Melt every Progression upgrade back into the currency you paid for it, and choose again. Unlocks are kept.",
		"level": 0, "max_level": 0, "maxed": false, "cost": respec_cost(), "currency": &"hellstone",
		"currency_name": hs.name, "currency_icon": hs.icon, "currency_color": hs.color,
		"effect": "", "next_effect": ("Refund: " + ", ".join(parts)) if not parts.is_empty() else "",
		"reason": reason, "category": "Rites",
	}


## Price of rank `rank` (0-based) of an upgrade definition.
func _cost_at(def: Dictionary, rank: int) -> int:
	var c: Variant = def.get("cost", 0)
	if c is Array:
		var arr := c as Array
		return 0 if arr.is_empty() else int(arr[mini(rank, arr.size() - 1)])
	return int(round(float(c) * pow(float(def.get("cost_growth", 1.0)), rank)))


# ================================================================ transmutes

## Converts currency per TRANSMUTES[id]. Returns false if unaffordable.
func transmute(id: StringName) -> bool:
	var t: Array = TRANSMUTES.get(id, [])
	if t.is_empty() or not spend(t[0], int(t[1])):
		return false
	add_currency(t[2], int(t[3]))
	return true


func _transmute_info(id: StringName) -> Dictionary:
	var t: Array = TRANSMUTES[id]
	var from := get_currency_def(t[0])
	var to := get_currency_def(t[2])
	return {
		"id": id, "kind": "action", "name": String(t[4]), "icon": String(t[5]),
		"description": "Trade %d %s for %d %s. Repeatable." % [int(t[1]), from.name, int(t[3]), to.name],
		"level": 0, "max_level": 0, "maxed": false, "cost": int(t[1]), "currency": t[0],
		"currency_name": from.name, "currency_icon": from.icon, "currency_color": from.color,
		"effect": "", "next_effect": "+%d %s" % [int(t[3]), to.name],
		"reason": "" if can_afford(t[0], int(t[1])) else "Not enough %s" % from.name, "category": "Rites",
	}


# ================================================================ map gating

## Why `map_id` can't be opened yet ("" = progression is satisfied). Reads the map JSON's
## "unlock" block (data/maps/<id>.json, Maps autoload):
##   "progress": {"stat": "<Progression stat>", "min": N}     lifetime stat, e.g. bosses_slain
##   "cleared": "<map id>"                                      a boss slain or a run won on that map
##   "story": "<Dialogue flag>", "story_hint": "text"           a story beat (Dialogue.has_flag)
##   "mastery": N                                               any demon at mastery N
## Meta.map_requirement() asks this, so the cartographer shows it and won't sell the map early.
func map_gate(map_id: StringName) -> String:
	var def := _map_def(map_id)
	var u: Variant = def.get("unlock", {})
	if not u is Dictionary or _unlock_all:
		return ""
	var ud := u as Dictionary
	if ud.has("progress"):
		var pr: Dictionary = ud.progress
		var have := float(stats.get(String(pr.get("stat", "runs")), 0))
		if have < float(pr.get("min", 1)):
			return String(pr.get("hint", "Requires %s %d" % [String(pr.get("stat", "runs")).capitalize(), int(pr.get("min", 1))]))
	if ud.has("cleared") and String(ud.cleared) != "":
		var m: Dictionary = (stats.get("maps", {}) as Dictionary).get(String(ud.cleared), {})
		if int(m.get("bosses", 0)) <= 0 and int(m.get("victories", 0)) <= 0:
			return "Conquer %s first (slay its herald or win there)" % _map_def(StringName(String(ud.cleared))).get("name", ud.cleared)
	if ud.has("mastery"):
		if not is_unlocked(StringName("mastery:any:%d" % int(ud.mastery))):
			return "Requires mastery %s with any demon" % Upgrades.roman(int(ud.mastery))
	if ud.has("story") and String(ud.story) != "":
		var dlg := get_node_or_null(^"/root/Dialogue")
		if dlg and dlg.has_method(&"has_flag") and not bool(dlg.call(&"has_flag", String(ud.story))):
			return String(ud.get("story_hint", "The story has not led you there yet"))
	return ""


func is_map_open(map_id: StringName) -> bool:
	return map_gate(map_id) == ""


## Per-map lifetime stats: {runs, victories, bosses, best_time}.
func map_stats(map_id: StringName) -> Dictionary:
	return (stats.get("maps", {}) as Dictionary).get(String(map_id), {})


func _record_map_run(_result: Dictionary, victory: bool, time: float) -> void:
	var id := _current_map_id()
	if id == "":
		return
	if not stats.get("maps") is Dictionary:
		stats["maps"] = {}
	var m: Dictionary = (stats.maps as Dictionary).get(id, {})
	m["runs"] = int(m.get("runs", 0)) + 1
	m["victories"] = int(m.get("victories", 0)) + (1 if victory else 0)
	m["bosses"] = int(m.get("bosses", 0)) + _run_bosses
	m["best_time"] = maxf(float(m.get("best_time", 0.0)), time)
	stats.maps[id] = m


func _current_map_id() -> String:
	var maps := get_node_or_null(^"/root/Maps")
	if maps == null:
		return ""
	var cur: Variant = maps.get(&"current_def")
	if cur is Dictionary and (cur as Dictionary).has("id"):
		return String(cur.id)
	return String(maps.get(&"selected_id"))


func _map_def(map_id: StringName) -> Dictionary:
	var maps := get_node_or_null(^"/root/Maps")
	if maps and maps.has_method(&"get_def"):
		var d: Variant = maps.call(&"get_def", map_id)
		if d is Dictionary:
			return d
	return {}


# ================================================================ formatting

## "+10% Luck", "+1 Reroll", "-3% Cooldown", "+12 Max HP".
static func format_stat(stat: StringName, amount: float, fmt: String = "", suffix: String = "") -> String:
	const NAMES := {
		&"max_hp": "Max HP", &"move_speed": "Speed", &"might": "Damage", &"area": "Area",
		&"cooldown": "Cooldown", &"projectile_speed": "Projectile Speed", &"bonus_projectiles": "Projectiles",
		&"xp_gain": "XP", &"pickup_radius": "Pickup Radius", &"armor": "Armor", &"regen": "Regen",
		&"luck": "Luck", &"rerolls": "Rerolls", &"banishes": "Banishes", &"dash_charges": "Dash Charges",
		&"starting_boons": "Starting Boons", &"starting_relics": "Starting Relics", &"ichor_gain": "Ichor",
		&"shard_gain": "Sin Shards",
	}
	var label: String = NAMES.get(stat, String(stat).capitalize())
	var sgn := "+" if amount >= 0.0 else "-"
	if fmt == "percent":
		return "%s%d%% %s" % [sgn, int(round(absf(amount) * 100.0)), label]
	if suffix != "":
		return "%s%s%s" % [sgn, _num(absf(amount)), suffix]
	return "%s%s %s" % [sgn, _num(absf(amount)), label]


static func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, round(v)) else ("%.2f" % v).rstrip("0").rstrip(".")


# ================================================================ persistence

func get_flag(key: String, default: Variant = null) -> Variant:
	return flags.get(key, default)


func set_flag(key: String, value: Variant) -> void:
	flags[key] = value
	save_game()


## Writes the save atomically (temp file, then rename) so a crash never leaves half a file.
## Where the save lives right now (honours --save-profile= / DEMONCORE_SAVE_PROFILE, see SaveProfile).
func save_path() -> String:
	return SAVES.path(SAVE_PATH.get_file())


func save_game() -> void:
	var data := {
		"version": SAVE_VERSION, "currencies": currencies, "levels": levels, "unlocks": unlocks,
		"pacts": pacts, "flags": flags, "stats": stats, "mastery": mastery, "codex": codex,
	}
	var tmp := save_path() + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Progression: cannot write %s (%s)" % [tmp, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	DirAccess.rename_absolute(tmp, save_path())


func load_game() -> void:
	if not FileAccess.file_exists(save_path()):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path()))
	if not parsed is Dictionary:
		# Keep the broken file for inspection instead of silently overwriting it.
		push_warning("Progression: %s is corrupt; backed up and starting fresh" % save_path())
		DirAccess.copy_absolute(save_path(), save_path() + ".corrupt")
		return
	var d := _migrate(parsed as Dictionary)
	currencies = _int_dict(d.get("currencies", {}))
	levels = _int_dict(d.get("levels", {}))
	pacts = _int_dict(d.get("pacts", {}))
	unlocks.clear()
	for u: Variant in d.get("unlocks", []):
		unlocks.append(String(u))
	var fl: Variant = d.get("flags", {})
	flags = (fl as Dictionary).duplicate() if fl is Dictionary else {}
	var st: Variant = d.get("stats", {})
	stats = (st as Dictionary).duplicate(true) if st is Dictionary else {}
	mastery = _int_dict(d.get("mastery", {}))
	codex = _int_dict(d.get("codex", {}))


## Upgrades an older save dictionary to SAVE_VERSION. Add a step per version bump.
func _migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("version", 0))
	if v > SAVE_VERSION:
		push_warning("Progression: save version %d is newer than %d; loading what we understand" % [v, SAVE_VERSION])
	# v0 -> v1: no structural change (v0 = pre-release files without a version key).
	# v1 -> v2: adds "mastery" and "codex" (both default to empty; codex is seeded from relics_found = 0).
	d.version = SAVE_VERSION
	return d


## Wipes all Progression data (not Meta's souls) and saves.
func reset_progress() -> void:
	currencies = {}
	levels = {}
	unlocks.clear()
	pacts = {}
	flags = {}
	stats = {}
	mastery = {}
	codex = {}
	save_game()
	pacts_changed.emit(get_heat())


static func _int_dict(v: Variant) -> Dictionary:
	var out := {}
	if v is Dictionary:
		for k: Variant in v:
			out[String(k)] = int(v[k])  # JSON numbers load as floats
	return out


# ================================================================ definitions

func _load_definitions() -> void:
	currency_defs.clear()
	# Souls are Meta's, but list them so shop UIs can show one consistent set of currencies.
	currency_defs.append({"id": "souls", "name": "Souls", "icon": "☽", "color": Color("d0383c"),
		"description": "Banked by Meta at the end of each run."})
	for c in _read_list("currencies.json", "currencies"):
		c.color = Color(String(c.get("color", "ffffff")))
		if c.id == "souls":
			currency_defs[0] = c
		else:
			currency_defs.append(c)
	for c in currency_defs:
		_currency_by_id[String(c.id)] = c

	upgrade_defs = _read_list("upgrades.json", "upgrades")
	for d in upgrade_defs:
		d["_kind"] = "upgrade"
		_by_id[String(d.id)] = d
	unlock_defs = _read_list("unlocks.json", "unlocks")
	for d in unlock_defs:
		d["_kind"] = "unlock"
		d["kind"] = String(d.get("kind", "ability"))
		_by_id[String(d.id)] = d
	pact_defs = _read_list("pacts.json", "pacts")
	for d in pact_defs:
		_pact_by_id[String(d.id)] = d
	var mp := DATA_DIR + "mastery.json"
	var md: Variant = JSON.parse_string(FileAccess.get_file_as_string(mp)) if FileAccess.file_exists(mp) else null
	mastery_def = md if md is Dictionary else {}
	relic_defs = _read_list("relics.json", "relics")
	var rp := DATA_DIR + "relics.json"
	var rj: Variant = JSON.parse_string(FileAccess.get_file_as_string(rp)) if FileAccess.file_exists(rp) else null
	_codex_milestone_defs = (rj as Dictionary).get("codex_milestones", []) if rj is Dictionary else []
	for d in relic_defs:
		d["tier"] = Rarity.from_id(d.get("rarity", "common"))
		_relic_by_id[String(d.id)] = d


func _read_list(file: String, key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var path := DATA_DIR + file
	if not FileAccess.file_exists(path):
		push_warning("Progression: missing %s" % path)
		return out
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_warning("Progression: %s is not valid JSON" % path)
		return out
	for e: Variant in (parsed as Dictionary).get(key, []):
		if e is Dictionary and (e as Dictionary).has("id"):
			out.append(e)
	return out


## "requires" may name our upgrades/unlocks or Meta's souls upgrades.
func _requirement_level(id: StringName) -> int:
	if _by_id.has(String(id)):
		return get_level(id)
	var meta := _meta()
	return int(meta.call(&"get_level", id)) if meta else 0


func _requirement_def(id: StringName) -> Dictionary:
	if _by_id.has(String(id)):
		return get_def(id)
	var meta := _meta()
	return meta.call(&"get_def", id) if meta else {}


func _resource_unlocked(kind: String, path: String) -> bool:
	for d in unlock_defs:
		if d.kind == kind and d.get("resource", "") == path:
			return is_unlocked(StringName(d.id))
	return true
