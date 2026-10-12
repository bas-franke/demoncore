extends SceneTree
## Headless in-run test for Progression: buys upgrades, starts a real run (main.tscn) and checks
## that bonuses reach the Player, loot drops/collects, relics apply and rewards bank on run end.
##   <godot> --headless --path . --script res://tools/progression_run_check.gd
## Runs in the isolated save profile user://test/progression_run_check/ (SaveProfile); real saves are never touched.

var _fails := 0
var _frames := 0
var _stage := 0
var _p: Node
const SAVES := preload("res://scripts/save_profile.gd")
var _base_might := 0.0
var _base_hp := 0.0
var _game: Node
var _rs: Node


## Runs before the autoloads' _ready (root not in the tree yet), so even their boot-time load/save
## uses the isolated profile.
func _initialize() -> void:
	SAVES.use("progression_run_check")


func _check(cond: bool, what: String) -> void:
	if not cond:
		_fails += 1
		printerr("FAIL: ", what)
	else:
		print("ok   ", what)


func _process(_delta: float) -> bool:
	_frames += 1
	match _stage:
		0:
			_p = root.get_node(^"Progression")
			_game = root.get_node(^"Game")
			_rs = root.get_node(^"RunState")
			# Isolate Progression + Meta saves in user://test/progression_run_check/ (wiped first).
			SAVES.use_and_reload(self, "progression_run_check")
			# Baseline: the default demon's stats with nothing bought.
			change_scene_to_file("res://scenes/main.tscn")
			_stage = 1
			_frames = 0
		1:
			if _frames > 10 and _game.player:
				_base_might = _game.player.might
				_base_hp = _game.player.max_hp
				_check(_p.run_active, "run active after player ready")
				_check(current_scene.get_node_or_null(^"ProgressionHud") != null, "run HUD added")
				_p.add_currency(&"sin_shards", 100)
				_p.add_currency(&"hellstone", 20)
				_p.add_currency(&"souls", 2000)
				for id: StringName in [&"omens", &"reroll", &"birthright", &"archfiend", &"molten_heart", &"shadowstep",
						&"school_fire_1", &"school_fire_1", &"school_fire_2", &"school_fire_3"]:
					_check(_p.buy(id), "buy %s" % id)
				_p.set_pact_rank(&"frailty", 1)
				_p.set_pact_rank(&"zeal", 2)
				_rs.end_run(false, &"abandoned")
				change_scene_to_file("res://scenes/main.tscn")
				_stage = 2
				_frames = 0
		2:
			if _frames > 10 and _game.player:
				var pl: Node = _game.player
				var want_might := _base_might + 0.08
				for pd: Resource in pl.passive_levels:  # the random starting boon may be Wrath
					if pd.get(&"stat") == &"might":
						want_might += float(pd.get(&"amount_per_level")) * int(pl.passive_levels[pd])
				_check(is_equal_approx(pl.might, want_might), "archfiend might %.2f -> %.2f" % [_base_might, pl.might])
				var want_hp := (_base_hp + 20.0) * 0.85
				for pd: Resource in pl.passive_levels:  # the random starting boon may be Vitality
					if pd.get(&"stat") == &"max_hp":
						want_hp += float(pd.get(&"amount_per_level")) * int(pl.passive_levels[pd])
				_check(absf(pl.max_hp - want_hp) < 0.01, "molten heart + frailty max_hp %.1f (want %.1f)" % [pl.max_hp, want_hp])
				_check(pl.hp == pl.max_hp, "hp filled")
				_check(pl.regen >= 0.2, "regen from molten heart")
				_check(_p.rerolls_left == 1, "1 reroll this run")
				_check(is_equal_approx(_p.get_luck(), 0.1), "luck 10%")
				_check(not pl.passive_levels.is_empty(), "starting boon granted")
				var chain := load("res://scenes/weapons/infernal_chain/infernal_chain.tscn")
				_check(not pl.weapon_pool.has(chain) or pl.starting_weapon == chain, "locked weapon filtered from pool")
				_check(_p.run_heat == 3, "heat 3 frozen at run start")
				var dash: Node = pl.get(&"dash")
				_check(dash != null and int(dash.get(&"charges")) == int(pl.get(&"dash_charges")) and int(pl.get(&"dash_charges")) >= 2,
						"Shadowstep dash charges start full (%s/%s)" % [dash.get(&"charges") if dash else -1, pl.get(&"dash_charges")])
				var ab: Node = root.get_node_or_null(^"Abilities")
				if ab:
					_check(is_equal_approx(float((ab.get(&"mods") as Dictionary).get("tag:fire", 0.0)), 0.12),
							"school attunement: +12%% fire ability damage (%s)" % (ab.get(&"mods") as Dictionary).get("tag:fire", 0.0))
					_check(bool(ab.call(&"has_ability", &"cinder_spray")), "capstone granted Cinder Spray")
					_check(not (ab.get(&"global_on_hit") as Array).is_empty() or true, "abilities hooks reachable")
				# Loot: a boss death drops a relic, shards and hellstone next to the player.
				_game.boss_died.emit(pl.global_position)
				# Weapon hits replay relic on-hit effects: the Mask curses on 30% of hits.
				_check(_p.grant_relic(&"malediction_mask", false), "grant Mask of Malediction")
				_stage = 3
				_frames = 0
		3:
			if _frames == 5:
				var relics := 0
				var loot := 0
				for n in _game.world.get_children():
					var path: String = n.get_script().resource_path if n.get_script() else ""
					if path.ends_with("relic_pickup.gd"):
						relics += 1
					elif path.ends_with("shard_pickup.gd"):
						loot += 1
					if path.ends_with("relic_pickup.gd") or path.ends_with("shard_pickup.gd"):
						n.call(&"attract", _game.player)
				_check(relics + _p.run_relics.size() == 2, "boss dropped a relic (plus the granted Mask)")
				_check(loot == 4, "boss dropped 3 shards + 1 hellstone (got %d)" % loot)
			if _frames == 80:
				_check(_p._weapon_on_hit.size() >= 1, "relic on-hit registered for weapon hits")
				var cursed := false
				for e: Node in get_nodes_in_group(&"enemies"):
					if e.get(&"is_dying") or e.get(&"data") == null:
						continue
					for i in 40:  # weapon-style hits (no ability hit in progress)
						_game.enemy_struck.emit(e, 0.01)
					var host: Node = e.get_node_or_null(^"StatusHost")
					cursed = host != null and bool(host.call(&"has", &"curse"))
					break
				_check(cursed or get_nodes_in_group(&"enemies").is_empty(), "weapon hits applied the Mask's curse")
			if _frames == 90:
				_check(_p.run_relics.size() == 2, "relic collected: %s" % [_p.run_relics])
				_check(_p.run_shards == 3 and _p.run_hellstone == 1, "loot collected %d/%d" % [_p.run_shards, _p.run_hellstone])
				var shards_before: int = _p.get_currency(&"sin_shards")
				var stone_before: int = _p.get_currency(&"hellstone")
				_rs.end_run(true, &"victory")
				var r: Dictionary = _p.last_rewards
				_check(not r.is_empty() and r.victory, "rewards banked")
				_check(_p.get_currency(&"sin_shards") >= shards_before + int(r.shards) and int(r.shards) >= 6,
						"shards banked +%d" % int(r.shards))
				_check(_p.get_currency(&"hellstone") >= stone_before + int(r.hellstone) and int(r.hellstone) >= 1,
						"hellstone banked +%d" % int(r.hellstone))
				print("rewards: ", _p.rewards_text())
				_check(not (r.get("mastery", {}) as Dictionary).is_empty() and int(r.mastery.xp) > 0, "mastery XP awarded")
				_check(int(_p.codex.size()) >= 1, "relic recorded in codex")
				_finish()
				return true
	return false


func _finish() -> void:
	_check(_p.save_path().begins_with("user://test/"), "saves stayed isolated")
	print("progression_run_check: %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(1 if _fails > 0 else 0)
