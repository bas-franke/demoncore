extends Node
## Headless functional test of map interactables (maps role):
##   godot --headless --path . res://tools/maps/feature_check.tscn
## Runs the real run scene on outer_gardens and checks: breaking a MapStatue does not count as a
## kill or fill the enemy cap; the "profane_fonts" objective completes after the demon corrupts two
## holy fonts by standing in them; striking a summoning bell calls angels. Prints FEATURECHECK lines.

var _fails := 0


func _ready() -> void:
	Game.godmode = true
	Game.autopilot = true  # level-up menus (objective rewards) pick by themselves
	process_mode = Node.PROCESS_MODE_ALWAYS
	Maps.select(&"outer_gardens")
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _wait(4.0)
	var p := Game.player
	# 1. statues
	var statues := get_tree().get_nodes_in_group(&"map_features")
	_check(statues.size() > 0, "statues spawned (%d)" % statues.size())
	if statues.size() > 0:
		# QA: sealed arena (was flaky: a spawned angel died to the demon's weapons during the wait).
		# Spawner and weapons off, every non-statue enemy gone, then count kill events for the statue.
		var spawner := main.get_node(^"EnemySpawner")
		spawner.set_process(false)
		p.weapon_root.process_mode = Node.PROCESS_MODE_DISABLED
		for e in get_tree().get_nodes_in_group(&"enemies"):
			if not e.is_in_group(&"map_features"):
				e.queue_free()
		await get_tree().process_frame
		var kills := Game.kills
		var st := statues[0] as Enemy
		var statue_kills := [0]
		var on_kill := func(_pos: Vector3, data: Resource, _elite: bool) -> void:
			if data == st.data:
				statue_kills[0] += 1
		RunState.enemy_killed.connect(on_kill)
		st.take_damage(999999.0)
		await _wait(0.5)
		RunState.enemy_killed.disconnect(on_kill)
		_check(statue_kills[0] == 0 and Game.kills == kills,
			"breaking a statue is not a kill (statue kill events %d, kills %d -> %d)" % [statue_kills[0], kills, Game.kills])
		_check(not is_instance_valid(st) or st.is_queued_for_deletion() or st.is_dying, "statue destroyed")
		p.weapon_root.process_mode = Node.PROCESS_MODE_INHERIT
		spawner.set_process(true)
	# 2. profane_fonts objective
	var dir := get_tree().get_first_node_in_group(&"objective_director")
	var obj: Node = dir.call(&"spawn_objective", "profane_fonts") if dir else null
	_check(obj != null, "profane_fonts objective spawned")
	var fonts: Array[Node] = []
	for n in get_tree().get_nodes_in_group(&"map_interactables"):
		if n is HolyFont:
			fonts.append(n)
	_check(fonts.size() >= 2, "map has 2+ fonts (%d)" % fonts.size())
	for i in mini(2, fonts.size()):
		var f := fonts[i] as HolyFont
		for k in 150:
			p.global_position = f.global_position + Vector3(1.6, 0, 0)
			await get_tree().physics_frame
		_check(f.corrupted, "font %d corrupted by standing in it" % i)
	await _wait(0.3)
	print("FEATURECHECK obj valid=%s" % is_instance_valid(obj))
	if obj and is_instance_valid(obj):
		_check(int(obj.get(&"state")) == Objective.State.COMPLETED, "profane_fonts completed (state %d)" % int(obj.get(&"state")))
	# 3. bell
	var bell: SummoningBell = null
	for n in get_tree().get_nodes_in_group(&"map_interactables"):
		if n is SummoningBell:
			bell = n
	_check(bell != null, "map has a bell")
	if bell:
		var before := get_tree().get_node_count_in_group(&"enemies")
		for k in 80:
			p.global_position = bell.global_position + Vector3(0, 0, 1.0)
			await get_tree().physics_frame
		await _wait(0.2)
		var after := get_tree().get_node_count_in_group(&"enemies")
		_check(after >= before + 5, "bell called angels (%d -> %d)" % [before, after])
	print("FEATURECHECK DONE fails=%d" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _wait(s: float) -> void:
	await get_tree().create_timer(s, false).timeout


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	print("FEATURECHECK %s  %s" % ["PASS" if ok else "FAIL", what])
