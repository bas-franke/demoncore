extends SceneTree
## Smoke test for the Basecamp Hell loop (basecamp role). Runs headless:
##   <godot> --headless --path . --script res://tools/basecamp_smoke.gd
## hub -> hellgate -> run -> death (RunState.end_run) -> back in the hub with the soul reward,
## plus a purchase that must persist through a save/load round trip. Headless runs save to the "bot" SaveProfile, so real saves are never touched.
## Exit code 0 = pass, 1 = fail.

# QA: no project class names below (RunLoadout, DailyChallenge): a -s script compiles before the
# autoloads exist, so naming them broke Meta/Game-dependent scripts (player.gd) for the whole run
# and the test hung at "daily trial". They are load()ed at run time instead.
const HUB := "res://scenes/basecamp/basecamp.tscn"

var _fails: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var meta: Node = root.get_node(^"Meta")
	var rs: Node = root.get_node(^"RunState")

	change_scene_to_file(HUB)
	await _frames(20)
	_check(current_scene != null and current_scene.scene_file_path == HUB, "hub loads")
	_check(get_nodes_in_group(&"hub_interactables").size() >= 6, "hub has merchants, gate, circle, covenant")

	# Proving Pit: a real Player + dummies appear, take hits, and everything goes away on leave.
	var hub: Node = current_scene
	var pit: Node = hub.get(&"_pit")
	_check(pit != null, "proving pit exists")
	if pit:
		pit.call(&"enter", [])
		await _frames(90)
		var dummies: Array = pit.get(&"_dummies")
		_check(pit.get(&"active") and is_instance_valid(pit.get(&"player")), "pit spawns a player")
		_check(dummies.size() == 3, "pit spawns three dummies")
		if not dummies.is_empty():
			(dummies[0] as Node).call(&"take_damage", 999999.0)
			await _frames(2)
			_check(is_instance_valid(dummies[0]) and not dummies[0].get(&"is_dying"), "dummies are immortal")
		pit.call(&"leave")
		await _frames(5)
		_check(not pit.get(&"active") and root.get_node(^"Game").get(&"player") == null, "leaving the pit cleans up")

	# Trophies + ledger data.
	meta.reset_save()
	meta.record_boss_kill(&"sariel")
	_check(meta.has_trophy(&"sariel"), "boss kill mounts a trophy")
	var trophies: Array = meta.boss_trophies()
	_check(not trophies.is_empty(), "trophy wall lists bosses")

	# Purchase + persistence.
	meta.reset_save()
	meta.souls = 1000
	var lv0: int = meta.get_level(&"bs_vitality")
	var cost: int = meta.next_cost(&"bs_vitality")
	_check(meta.buy(&"bs_vitality"), "buy bs_vitality")
	_check(cost < 0 or meta.souls == 1000 - cost, "souls deducted")
	var souls_after: int = meta.souls
	meta.load_game()
	_check(meta.get_level(&"bs_vitality") == lv0 + 1 and meta.souls == souls_after, "save round trip")

	# Hellgate loadout -> run: the chosen weapon replaces the demon's own.
	var pick := ""
	for w: Dictionary in load("res://scripts/meta/run_loadout.gd").weapons():
		if w.unlocked:
			pick = String(w.path)
	meta.start_run_with_loadout({"weapon": pick, "ability": "", "keepsake": ""})
	await _frames(60)
	_check(current_scene != null and current_scene.scene_file_path == meta.RUN_SCENE, "gate starts the run")
	_check(meta.is_run_active(), "run registered with Meta")
	var p: Node = root.get_node(^"Game").get(&"player")
	_check(p != null, "player spawned")
	if p and pick != "":
		var ws: Array = p.get(&"weapons")
		_check(not ws.is_empty() and (ws[0] as Node).scene_file_path == pick, "loadout weapon equipped")

	# Death -> reward -> hub.
	var before: int = meta.souls
	rs.end_run(false, &"slain")
	_check(not meta.is_run_active() and meta.souls > before, "soul reward banked on run end")
	rs.return_to_basecamp()
	await _frames(20)
	_check(current_scene != null and current_scene.scene_file_path == HUB, "run end returns to the hub")

	# Daily trial: deterministic, and a finished trial records a best score.
	var daily: GDScript = load("res://scripts/meta/daily_challenge.gd")
	var t: Dictionary = daily.today()
	_check(t == daily.today() and String(t.map) != "", "daily trial is deterministic")
	meta.start_trial(t)
	await _frames(60)
	rs.end_run(false, &"slain")
	_check(meta.trial_best_score(String(t.key)) > 0, "trial score recorded")
	rs.return_to_basecamp()
	await _frames(20)

	if _fails.is_empty():
		print("basecamp_smoke: PASS")
		quit(0)
	else:
		print("basecamp_smoke: FAIL\n  " + "\n  ".join(_fails))
		quit(1)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
