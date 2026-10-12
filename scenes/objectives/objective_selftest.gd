extends Node
## Dev-only scripted check of every objective type and boss (added by ObjectiveDirector when the
## run is started with `-- --objectives-selftest`). Spawns each objective next to the demon, holds
## the demon inside it, kills champions / saints, summons each boss and burns it through its phases,
## printing "OBJTEST ..." lines. Run headless with --godmode:
##   <godot> --headless --path . res://scenes/main.tscn -- --godmode --objectives-selftest
## and look for "OBJTEST DONE" plus any "OBJTEST FAIL" lines.

const NEW_TYPES := ["escort", "font", "procession", "towers", "slaughter", "chest", "temptation"]

var director: ObjectiveDirector
## "" = everything; "bosses", "new" (round-2 objective types), "events" (`--objectives-selftest=<mode>`).
var mode := ""
var _hold := Vector3.INF
var _fails := 0
var _paused_t := 0.0
var _noted_pause := false
var _summoned: Node3D


func _ready() -> void:
	# Keeps running while menus pause the tree, to un-stick them (see _process).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


## Something paused the run (a relic / level-up choice opened by a reward): note it and resume.
func _process(delta: float) -> void:
	if not get_tree().paused:
		_paused_t = 0.0
		return
	_paused_t += delta
	if _paused_t > 1.5:
		_paused_t = 0.0
		var who := []
		for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
			var cl := n as CanvasLayer
			if cl.visible and cl.process_mode == Node.PROCESS_MODE_ALWAYS or cl.process_mode == Node.PROCESS_MODE_WHEN_PAUSED:
				who.append(cl.name)
		if not _noted_pause:
			_noted_pause = true
			print("OBJTEST note: tree paused (%s), resuming (noted once)" % ", ".join(PackedStringArray(who)))
		get_tree().paused = false


func _physics_process(_delta: float) -> void:
	# Pin the demon where the current step wants it (autopilot or not).
	var p := Game.player
	if p and _hold != Vector3.INF:
		p.global_position = _hold
		p.velocity = Vector3.ZERO


func _run() -> void:
	await _wait(1.0)
	director.enabled = false
	director.set(&"_boss_thresholds", [] as Array[int])  # only the bosses this test summons
	director.settings["victory_bosses"] = 0  # no victory screen mid-test
	director.set(&"_winning", true)  # the Seventh Gate must not end the run mid-test either
	director.settings["variant_chance"] = 0.0  # deterministic params
	director.settings["variant_chance_per_minute"] = 0.0
	director.events.enabled = false
	director.boss_summoned.connect(func(boss: Node3D) -> void: _summoned = boss)
	# No timed bosses from the spawner during the test.
	var sp := get_tree().current_scene.get_node_or_null(^"EnemySpawner")
	if sp and &"boss_time" in sp:
		sp.set(&"boss_time", 1.0e9)
		if &"_next_boss" in sp:
			sp.set(&"_next_boss", 1.0e9)
	# No level-ups: their menu pauses the tree (and this test) unless the autopilot picks.
	if Game.player:
		Game.player.xp_gain = 0.0
	if mode in ["", "new"]:
		for def in director.definitions:
			if mode == "new" and not str(def.get("type", "")) in NEW_TYPES:
				continue
			await _test_objective(str(def.get("id", "")))
	if mode.begins_with("id:"):
		await _test_objective(mode.substr(3))
	if mode in ["", "events"]:
		for def in director.events.events:
			await _test_event(def)
	if mode in ["", "bosses"]:
		for boss_id: String in director.boss_ids():
			await _test_boss(boss_id)
	var rep := director.score.report()
	print("OBJTEST score=%d grade=%s" % [int(rep.score), str(rep.grade)])
	print("OBJTEST DONE fails=%d souls=%d completed=%d" % [_fails, director.souls_earned, director.completed_count])
	get_tree().quit(1 if _fails > 0 else 0)


func _test_objective(def_id: String) -> void:
	var p := Game.player
	var origin := p.global_position
	var obj := director.spawn_objective(def_id, origin + Vector3(6.0, 0.0, 0.0))
	if obj == null:
		_fail("%s did not spawn" % def_id)
		return
	await _wait(0.5)
	_hold = obj.global_position + Vector3(0.6, 0.0, 0.0)
	await _wait(2.5)
	print("OBJTEST %s state=%s progress=%.2f status='%s'" % [def_id, Objective.State.keys()[obj.state],
			obj.progress, obj.status_text])
	if obj.state == Objective.State.DORMANT:
		_fail("%s never activated with the demon on it" % def_id)
	# Drive it to the end: kill targets, or keep standing in it.
	var t := 0.0
	var levels_before := p.level
	while is_instance_valid(obj) and not obj.is_finished() and t < 70.0:
		for n in get_tree().get_nodes_in_group(&"enemies"):
			var e := n as Enemy
			if e and not e.is_dying and e.is_in_group(&"boss"):
				if str(obj.def.get("type", "")) in ["challenge", "gate"]:
					e.take_damage(e.max_hp * 0.05)
			elif e and not e.is_dying:
				if e is SaintEnemy or e.is_in_group(&"champions"):
					e.take_damage(e.max_hp * 0.2)
				elif e.global_position.distance_to(p.global_position) < 6.5:
					e.take_damage(9999.0)
		# Cages / moving targets: hop to the objective's marker.
		var m := obj.marker_position()
		_hold = Vector3(m.x + 0.4, 0.0, m.z)
		await _wait(0.5)
		t += 0.5
	if not is_instance_valid(obj):
		_fail("%s freed before finishing" % def_id)
	else:
		print("OBJTEST %s -> %s after %.1fs (level %d -> %d)" % [def_id, Objective.State.keys()[obj.state], t,
				levels_before, p.level])
		if obj.state != Objective.State.COMPLETED:
			_fail("%s ended %s" % [def_id, Objective.State.keys()[obj.state]])
	_hold = Vector3.INF
	await _wait(3.5)


func _test_event(def: Dictionary) -> void:
	var d := def.duplicate(true)
	(d["params"] as Dictionary)["duration"] = 14.0  # short, so a survival event ends in the test
	var obj := director.events.start(d)
	if obj == null:
		_fail("event %s did not start" % def.get("id"))
		return
	var t := 0.0
	while is_instance_valid(obj) and not obj.is_finished() and t < 40.0:
		for n in get_tree().get_nodes_in_group(&"enemies"):
			var e := n as Enemy
			if e and not e.is_dying and not e.is_in_group(&"boss"):
				if e.is_in_group(&"champions"):
					e.take_damage(e.max_hp * 0.15)
				elif e.global_position.distance_to(Game.player.global_position) < 6.5:
					e.take_damage(9999.0)
		await _wait(0.5)
		t += 0.5
	if not is_instance_valid(obj):
		_fail("event %s freed before finishing" % def.get("id"))
		return
	print("OBJTEST event %s -> %s after %.1fs status='%s'" % [def.get("id"), Objective.State.keys()[obj.state], t, obj.status_text])
	if obj.state != Objective.State.COMPLETED:
		_fail("event %s ended %s" % [def.get("id"), Objective.State.keys()[obj.state]])
	await _wait(3.5)


func _test_boss(boss_id: String) -> void:
	# Wait out any boss already on the field (the spawner timer may have sent one).
	var guard := 0.0
	while get_tree().get_first_node_in_group(&"boss") != null and guard < 30.0:
		await _wait(0.5)
		guard += 0.5
	_summoned = null
	director.summon_boss(boss_id)
	await _wait(ObjectiveDirector.BOSS_HERALD_LEAD + 4.0)
	# The boss this test summoned (not one the spawner timer happened to send).
	var b := _summoned as Enemy
	if b == null:
		_fail("boss %s did not arrive" % boss_id)
		return
	print("OBJTEST boss %s hp=%.0f" % [boss_id, b.max_hp])
	var phases := []
	var t := 0.0
	while is_instance_valid(b) and not b.is_dying and t < 60.0:
		# Clear the field: healers / shield bearers (Enemy support behaviours) would carry the boss.
		for n in get_tree().get_nodes_in_group(&"enemies"):
			var e := n as Enemy
			if e and e != b and not e.is_dying and not e.is_in_group(&"boss"):
				e.take_damage(9999.0)
		b.take_damage(b.max_hp * 0.04)
		var ph: Variant = b.get(&"phase_index")
		if ph != null and not phases.has(ph):
			phases.append(ph)
			print("OBJTEST   %s phase %s at hp %.0f%%" % [boss_id, str(ph), 100.0 * b.hp / b.max_hp])
		if fmod(t, 5.0) < 0.25:
			print("OBJTEST   %s t=%.0f phase=%s state=%s hp=%.0f/%.0f" % [boss_id, t, str(b.get(&"phase_index")),
					str(b.get(&"phase")), b.hp, b.max_hp])
		await _wait(0.5)
		t += 0.5
	print("OBJTEST boss %s phases=%s dead=%s after %.1fs" % [boss_id, str(phases),
			str(not is_instance_valid(b) or b.is_dying), t])
	if is_instance_valid(b) and not b.is_dying:
		_fail("boss %s survived" % boss_id)
	var count: Variant = b.get(&"phase_count") if is_instance_valid(b) else null
	if count != null and phases.size() < int(count):
		_fail("boss %s skipped phases (%s of %d)" % [boss_id, str(phases), int(count)])
	await _wait(5.0)


func _fail(msg: String) -> void:
	_fails += 1
	print("OBJTEST FAIL " + msg)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, false, true).timeout
