extends SceneTree
## Headless self-test for the Progression autoload (docs/team/progression.md).
##   <godot> --headless --path . --script res://tools/progression_check.gd
## Runs in the isolated save profile user://test/progression_check/ (SaveProfile); never touches real saves.

const SAVES := preload("res://scripts/save_profile.gd")

var _fails := 0


## SaveProfile is switched before the autoloads' _ready (root not in the tree yet), so even their
## boot-time load/save uses the isolated profile.
func _initialize() -> void:
	SAVES.use("progression_check")
	_run.call_deferred()


func _check(cond: bool, what: String) -> void:
	if not cond:
		_fails += 1
		printerr("FAIL: ", what)
	else:
		print("ok   ", what)


func _run() -> void:
	var p: Node = root.get_node_or_null(^"Progression")
	_check(p != null, "Progression autoload present")
	if p == null:
		quit(1)
		return
	# Isolate: every save from here on goes to user://test/progression_check/ (wiped first).
	SAVES.use_and_reload(self, "progression_check")
	_check(p.save_path().begins_with("user://test/"), "save isolated: " + p.save_path())

	_check(p.upgrade_defs.size() > 0, "upgrade defs loaded (%d)" % p.upgrade_defs.size())
	_check(p.relic_defs.size() > 0, "relic defs loaded (%d)" % p.relic_defs.size())
	_check(p.pact_defs.size() > 0, "pact defs loaded (%d)" % p.pact_defs.size())
	_check(p.get_currency(&"sin_shards") == 0, "fresh save has 0 shards")
	_check(not p.can_buy(&"omens"), "cannot buy without shards")
	p.add_currency(&"sin_shards", 60)
	var omens_cost: int = p.next_cost(&"omens")
	_check(omens_cost > 0, "omens rank 1 costs %d" % omens_cost)
	_check(p.buy(&"omens"), "buy omens")
	_check(p.get_level(&"omens") == 1 and p.get_currency(&"sin_shards") == 60 - omens_cost, "rank 1, shards paid")
	_check(p.block_reason(&"banish").begins_with("Requires"), "banish gated by reroll")
	_check(not p.is_demon_unlocked(load("res://data/demons/morvane.tres")), "morvane locked")
	_check(p.is_demon_unlocked(load("res://data/demons/vharok.tres")), "vharok free")
	_check(p.buy(&"demon_morvane"), "bind morvane")
	_check(p.is_demon_unlocked(load("res://data/demons/morvane.tres")), "morvane unlocked")
	_check(not p.is_weapon_unlocked(load("res://scenes/weapons/infernal_chain/infernal_chain.tscn")), "chain locked")
	_check(not p.is_ability_unlocked(&"wraith_host"), "wraith host ability locked")
	_check(p.is_ability_unlocked(&"cinder_spray"), "unlisted ability free")
	_check(p.buy(&"ability_wraith_host") and p.is_ability_unlocked(&"wraith_host"), "wraith host unlocked")
	p.set_pact_rank(&"wrath", 2)
	p.set_pact_rank(&"legion", 9)
	_check(p.get_heat() == 4 + 3, "heat = 2*2 + 3 (clamped) = 7, got %d" % p.get_heat())
	_check(is_equal_approx(p.pact_total(&"enemy_damage"), 0.3), "wrath II = +30% enemy damage")
	_check(p.effect_text(&"omens", 2) == "+20% Luck", "effect text: " + p.effect_text(&"omens", 2))
	var counts := [0, 0, 0, 0, 0]
	for i in 5000:
		counts[Rarity.roll(0.0)] += 1
	_check(counts[0] > counts[1] and counts[1] > counts[2] and counts[2] > counts[3], "rarity weights ordered %s" % [counts])
	var lucky := [0, 0, 0, 0, 0]
	for i in 5000:
		lucky[Rarity.roll(1.0)] += 1
	_check(lucky[4] > counts[4] and lucky[0] < counts[0], "luck shifts rarity %s" % [lucky])
	_check(Rarity.roll(0.0, Rarity.RARE) >= Rarity.RARE, "min tier respected")
	_check(p.roll_relic() != &"", "can roll a relic")

	# Mastery.
	_check(p.mastery_level(&"vharok") == 1, "fresh mastery level 1")
	var m: Dictionary = p.add_mastery_xp(&"vharok", 200)
	_check(int(m.level_after) == 3 and p.signature_rank(&"vharok") == 1, "200 XP -> mastery III, signature I")
	_check(p.signature_text(&"vharok").begins_with("Ravager's Fury"), "signature text: " + p.signature_text(&"vharok"))
	_check(not p.is_unlocked(&"mastery:vharok:5") and p.is_unlocked(&"mastery:vharok:3"), "mastery unlock ids")
	_check(p.is_unlocked(&"mastery:any:3") and not p.is_unlocked(&"mastery:any:4"), "mastery:any ids")
	_check(p.get_currency(&"sin_shards") >= 2, "mastery II paid shards")
	# Respec: omens I (2 shards) + wraith host unlock are owned; respec refunds only omens.
	p.add_currency(&"hellstone", 5)
	var refund: Dictionary = p.respec_refund()
	_check(int(refund.get("sin_shards", 0)) == omens_cost, "respec would refund omens: %s" % [refund])
	var shards_before: int = p.get_currency(&"sin_shards")
	_check(p.buy(&"respec") and p.get_level(&"omens") == 0, "respec via buy(&\"respec\")")
	_check(p.get_currency(&"sin_shards") == shards_before + omens_cost and p.get_currency(&"hellstone") == 4, "refund paid, 1 hellstone spent")
	_check(p.respec_cost() == 2, "second respec costs 2")
	_check(p.is_ability_unlocked(&"wraith_host"), "unlocks survive respec")
	# Transmutes (late-game sinks).
	var hs: int = p.get_currency(&"hellstone")
	p.add_currency(&"sin_shards", 12)
	_check(p.buy(&"transmute_hellstone") and p.get_currency(&"hellstone") == hs + 1, "shards smelt into hellstone")
	# Codex.
	p._record_codex(&"cracked_halo")
	var cp: Dictionary = p.codex_progress()
	_check(int(cp.found) == 1 and int(cp.total) == p.relic_defs.size(), "codex progress %s" % [cp])
	# Codex milestones: discover a quarter of the relics -> the 25% reward pays once.
	var sh0: int = p.get_currency(&"sin_shards")
	var need: int = int(p.codex_milestones()[0].relics_needed)
	for r: Dictionary in p.relic_defs.slice(0, need):
		p._record_codex(StringName(r.id))
	var ms: Array = p.codex_milestones()
	_check(ms[0].reached and ms[0].claimed and not ms[1].claimed, "codex 25%% milestone claimed (%d relics)" % need)
	_check(p.get_currency(&"sin_shards") == sh0 + 10, "codex 25%% paid 10 shards")
	p._record_codex(StringName(p.relic_defs[0].id))
	_check(p.get_currency(&"sin_shards") == sh0 + 10, "milestone pays only once")
	_check(p.codex_entries().size() == p.relic_defs.size(), "codex lists every relic")
	_check(p.relic_defs.size() >= 29, "29+ relics (%d)" % p.relic_defs.size())
	_check(p.upgrade_defs.size() >= 25, "25+ upgrade nodes (%d)" % p.upgrade_defs.size())
	# Map gating (needs the Maps autoload and gated map JSONs).
	if root.get_node_or_null(^"Maps"):
		_check(p.map_gate(&"ruined_sanctum") == "", "starting map open")
		_check(p.map_gate(&"sunlit_citadel") != "", "citadel gated: " + p.map_gate(&"sunlit_citadel"))

	# Persistence round trip.
	p.save_game()
	p.levels = {}
	p.load_game()
	_check(p.get_level(&"omens") == 0 and p.get_heat() == 7 and p.mastery_level(&"vharok") == 3, "save/load round trip")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(p.save_path()))
	_check(raw is Dictionary and int(raw.version) == p.SAVE_VERSION, "save is versioned")

	print("progression_check: %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(1 if _fails > 0 else 0)
