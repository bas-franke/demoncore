extends SceneTree
## Headless smoke test for the core loop (gameplay role). Run:
##   godot --headless --path . -s res://tools/gameplay_check.gd
## Loads the run scene, then checks: run start, dash + i-frames + dodge, discrete hits with
## mercy frames, wave pacing (build/surge/lull + horde ring), difficulty scaling, Ichor drops
## and pickup, the support behaviours (HEAL / SHIELD / SUMMON / KITE / EXPLODE), boss scaling,
## and the death -> run_ended flow. Prints PASS/FAIL lines and exits 1 on failure.
## Duck-typed on purpose: a -s script compiles before the autoloads exist, so it must not name
## project classes (Player, Enemy, ...) that reference autoloads.

var _fails := 0
var _events := {}


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1


func _count(sig: StringName) -> void:
	_events[sig] = int(_events.get(sig, 0)) + 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	var rs: Node = root.get_node(^"RunState")
	var game: Node = root.get_node(^"Game")
	for sig in [&"run_started", &"run_ended", &"enemy_killed", &"player_damaged", &"player_dodged",
			&"player_dashed", &"player_died", &"currency_changed", &"wave_started"]:
		rs.connect(sig, func(_a = null, _b = null, _c = null): _count(sig))

	change_scene_to_file("res://scenes/main.tscn")
	await _frames(10)
	var p = game.player
	_check(p != null, "player exists")
	_check(rs.active, "run active after main loads")
	_check(_events.get(&"run_started", 0) == 1, "run_started emitted once")
	_check(_events.get(&"wave_started", 0) >= 1, "wave_started emitted at run start")

	# --- dash
	var x0: Vector3 = p.global_position
	var c0: int = p.dash.charges  # meta upgrades may grant extra charges
	Input.action_press(&"dash")
	await _frames(2)
	Input.action_release(&"dash")
	_check(p.dash.is_dashing(), "dash starts on input")
	_check(p.collision_layer == 0, "body layer cleared while dashing")
	var hp0: float = p.hp
	p.take_damage(30.0)
	_check(is_equal_approx(p.hp, hp0), "hit during dash is negated")
	_check(_events.get(&"player_dodged", 0) == 1, "player_dodged emitted")
	await _frames(12)
	_check(not p.dash.is_dashing(), "dash ends")
	_check(p.collision_layer != 0, "body layer restored")
	_check(p.global_position.distance_to(x0) > 2.0, "dash moved the demon (%.2f)" % p.global_position.distance_to(x0))
	_check(p.dash.charges == c0 - 1, "dash consumed a charge (%d of %d)" % [p.dash.charges, c0])

	# --- discrete hit + mercy
	await _frames(6)
	hp0 = p.hp
	p.take_damage(10.0, p.global_position + Vector3(1, 0, 0))
	_check(is_equal_approx(p.hp, hp0 - 10.0), "discrete hit deals damage")
	p.take_damage(10.0)
	_check(is_equal_approx(p.hp, hp0 - 10.0), "mercy frames block a second hit")
	_check(_events.get(&"player_damaged", 0) >= 1, "player_damaged emitted")

	# --- recharge
	await _frames(int(p.dash_cooldown * 30.0) + 6)
	_check(p.dash.charges == p.dash.max_charges(), "dash recharged")

	# --- waves + difficulty
	var spawner = current_scene.get_node(^"EnemySpawner")
	var n0: int = get_node_count_in_group(&"enemies")
	game.elapsed = spawner.surge_start + 0.1
	await _frames(3)
	_check(rs.wave_kind == &"surge", "surge phase reached (%s)" % rs.wave_kind)
	_check(get_node_count_in_group(&"enemies") >= n0 + spawner.ring_base, "horde ring spawned")
	game.elapsed = spawner.surge_end + 0.1
	await _frames(2)
	_check(rs.wave_kind == &"lull", "lull phase reached")
	game.elapsed = 180.0
	await _frames(5)
	_check(rs.wave == 4 and rs.enemy_hp_mult() > 1.8, "wave %d (want 4) / hp mult %.2f at 3:00" % [rs.wave, rs.enemy_hp_mult()])
	_check(rs.enemy_damage_mult() > 1.2, "damage mult %.2f at 3:00" % rs.enemy_damage_mult())

	# --- kills, ichor
	var cur0: int = rs.currency
	var killed := 0
	for e in get_nodes_in_group(&"enemies"):
		if e.get(&"data") != null and killed < 40:  # duck-typed: class names need autoloads first
			e.take_damage(99999.0, Vector3(6, 0, 0))
			killed += 1
	await _frames(3)
	_check(_events.get(&"enemy_killed", 0) >= killed, "enemy_killed per kill (%d)" % _events.get(&"enemy_killed", 0))
	rs.drop_currency(p.global_position + Vector3(0.8, 0, 0), 5, 2)
	await _frames(60)
	_check(rs.currency >= cur0 + 5, "ichor dropped and picked up (%d -> %d)" % [cur0, rs.currency])

	# --- support behaviours (fresh arena: clear the field first, spawner paused)
	spawner.set_process(false)
	p.xp_gain = 0.0  # no level-up screens (they pause the tree) during the scripted checks
	p.weapon_root.process_mode = Node.PROCESS_MODE_DISABLED  # no weapon kills / knockback here
	for e in get_nodes_in_group(&"enemies"):
		e.queue_free()
	game.godmode = true
	await _frames(2)
	var at: Vector3 = p.global_position
	# HEAL: a wounded wisp beside a censer nun gets healed.
	var nun = _spawn(spawner, "censer_nun", at + Vector3(7, 0, 0))
	var hurt = _spawn(spawner, "choir_wisp", at + Vector3(8, 0, 1))
	nun.set(&"_attack_t", 0.0)
	await _frames(1)
	hurt.hp = hurt.max_hp * 0.3
	hurt.speed = 0.0  # keep it inside the nun's circle
	var hurt_hp0: float = hurt.hp
	await _frames(int(nun.data.windup_time * 30.0) + 20)
	_check(is_instance_valid(hurt) and hurt.hp > hurt_hp0, "HEAL: censer nun healed an ally")
	# SHIELD: an ally beside a paladin takes reduced damage.
	var _pal = _spawn(spawner, "paladin", at + Vector3(-9, 0, 0))  # spawned for its aura only
	var ward = _spawn(spawner, "holy_knight", at + Vector3(-9.5, 0, 1))
	await _frames(12)
	var w0: float = ward.hp
	ward.take_damage(4.0)
	_check(is_instance_valid(ward) and w0 - ward.hp < 3.0, "SHIELD: warded ally took %.1f of 4" % (w0 - ward.hp))
	# SUMMON: a throne calls minions.
	var n_before := get_node_count_in_group(&"enemies")
	var thr = _spawn(spawner, "throne", at + Vector3(0, 0, -9))
	thr.set(&"_attack_t", 0.0)
	await _frames(int(thr.data.windup_time * 30.0) + 12)
	_check(thr.get(&"_summons").size() == thr.data.summon_count and get_node_count_in_group(&"enemies") >= n_before + 1 + thr.data.summon_count, "SUMMON: throne called minions")
	# KITE: an inquisitor placed close backs away.
	var inq = _spawn(spawner, "inquisitor", at + Vector3(0, 0, 3))
	inq.set(&"_attack_t", 99.0)
	await _frames(30)
	_check(inq.global_position.distance_to(p.global_position) > 3.6, "KITE: inquisitor retreated (%.1f)" % inq.global_position.distance_to(p.global_position))
	# EXPLODE: a zealot next to the demon detonates and hurts it.
	# QA: sealed arena + count damage events (raw HP was flaky: regen / heals between the reads).
	game.godmode = false
	await _isolate(p, spawner)
	var hp_z: float = p.hp
	var blast_dmg := [0.0]
	var on_dmg := func(amount: float, _hp: float, _max: float) -> void: blast_dmg[0] += amount
	rs.player_damaged.connect(on_dmg)
	var zealot_kills := [0]
	rs.enemy_killed.connect(func(_pos, d, _e): if d and d.id == &"zealot": zealot_kills[0] += 1)
	var zea = _spawn(spawner, "zealot", at + Vector3(1.2, 0, 0))
	var victim = _spawn(spawner, "choir_wisp", at + Vector3(2.0, 0, 0.6))
	victim.speed = 0.0
	await _frames(int(zea.data.windup_time * 30.0) + 15)
	_check(not is_instance_valid(zea), "EXPLODE: zealot detonated")
	rs.player_damaged.disconnect(on_dmg)
	_check(blast_dmg[0] > 0.0, "EXPLODE: blast hurt the demon (%.0f damage, %.0f -> %.0f HP)" % [blast_dmg[0], hp_z, p.hp])
	_check(not is_instance_valid(victim) or victim.hp < victim.max_hp, "EXPLODE: blast hurt a nearby angel")
	_check(zealot_kills[0] == 0, "EXPLODE: no kill credit for the self-destruct itself")
	# aim_line: a ballista paints its lane while winding up (and joins danger_zones).
	_unpause()
	var bal = _spawn(spawner, "templar_ballista", at + Vector3(0, 0, 10))
	bal.set(&"_attack_t", 0.0)
	var seen := false
	for i in 50:
		await _frames(1)
		_unpause()
		if get_nodes_in_group(&"danger_zones").size() > 0 and Danger.is_threatened(self, p.global_position + (bal.global_position - p.global_position) * 0.5, 0.5):
			seen = true
			break
	_check(seen, "aim_line: ballista lane visible to Danger (alive=%s state=%s zones=%d)" % [is_instance_valid(bal), bal.get(&"_state") if is_instance_valid(bal) else -1, get_nodes_in_group(&"danger_zones").size()])
	p.hp = p.max_hp

	# --- contact damage (regression: perf Crowd / maps steering), taunt, weapon hit source
	_unpause()
	for e in get_nodes_in_group(&"enemies"):
		e.queue_free()
	await _frames(2)
	p.hp = p.max_hp
	for i in 60:
		_unpause()
		if not p.dash.is_invulnerable():
			break
		await _frames(1)
	var hp_c: float = p.hp
	for i in 8:
		var a := TAU * i / 8.0
		_spawn(spawner, "choir_wisp", p.global_position + Vector3(cos(a), 0, sin(a)) * 3.0)
	await _frames(90)
	_unpause()
	_check(p.hp < hp_c - 5.0, "contact damage: 8 wisps hurt a still demon (%.0f HP in 3 s)" % (hp_c - p.hp))
	p.hp = p.max_hp
	var decoy := Node3D.new()
	root.get_node(^"Game").spawn(decoy, p.global_position + Vector3(12, 0, 0))
	var taunted = _spawn(spawner, "choir_wisp", p.global_position + Vector3(6, 0, 6))
	taunted.set_taunt_target(decoy, 5.0)
	var d0: float = taunted.global_position.distance_to(decoy.global_position)
	await _frames(45)
	_unpause()
	_check(taunted.is_taunted() and taunted.global_position.distance_to(decoy.global_position) < d0 - 1.0, "taunt: enemy walks to the decoy")
	decoy.queue_free()
	var seen_src := [null]
	var probe := func(en, _amt): seen_src[0] = en.last_hit_source
	game.enemy_struck.connect(probe)
	taunted.get_script().hit(taunted, 1.0, Vector3.ZERO, p)  # no class names in a -s script
	game.enemy_struck.disconnect(probe)
	_check(seen_src[0] == p and taunted.last_hit_source == null, "Enemy.hit: source visible during enemy_struck")

	# --- boss scaling + real boss data on kill
	spawner.set_process(true)
	p.weapon_root.process_mode = Node.PROCESS_MODE_INHERIT
	var boss = spawner.spawn_boss()
	await _frames(3)
	_check(boss != null and boss.has_meta(&"run_scaled"), "boss HP scaled by difficulty (x%.2f)" % rs.boss_hp_mult())

	# --- death -> run end (close any level-up screen the kills above opened)
	_unpause()
	for i in 90:  # wait out any mercy frames from stray hits
		if not p.dash.is_invulnerable():
			break
		await _frames(1)
	# Deterministic arena for the last stand (QA: flaky when the live boss / spawner spent it
	# first or the blow landed inside mercy frames): no spawner, no enemies, no hazards, a fresh
	# charge, and no i-frames left.
	# QA: _isolate also removes shots / danger zones / pickups, zeroes regen and clears i-frames.
	_unpause()
	await _isolate(p, spawner)
	p.last_stands = 1
	p.hp = p.max_hp
	_clear_iframes(p)
	var ls := [0]
	rs.last_stand.connect(func(): ls[0] += 1)
	p.take_damage(99999.0)
	await _frames(2)
	_check(not p.is_dead and is_equal_approx(p.hp, 1.0) and ls[0] == 1, "last stand: lethal blow left 1 HP")
	_check(p.dash.is_invulnerable(), "last stand: grants i-frames")
	for i in 90:  # wait out the last stand's i-frames
		_unpause()
		if not p.dash.is_invulnerable():
			break
		await _frames(1)
	p.take_damage(99999.0)
	await _frames(2)
	_check(p.is_dead, "player died")
	_check(not rs.active, "run inactive after death")
	_check(_events.get(&"run_ended", 0) == 1, "run_ended emitted once")
	_check(rs.last_result.get("cause") == &"slain", "cause = slain")
	_check(int(rs.last_result.get("currency", -1)) == rs.currency, "result carries currency")
	await create_timer(1.8).timeout
	var go := current_scene.get_node(^"GameOver") as CanvasLayer
	_check(go.visible, "end screen opened")

	# --- Ascension (endless after a victory), in a fresh run
	paused = false
	rs.restart_run()
	await _frames(15)
	p = game.player
	p.xp_gain = 0.0
	rs.end_run(true, &"victory")
	await _frames(2)
	_check(rs.can_ascend(), "ascension: available after a victory")
	var asc_ended := [0]
	rs.ascension_ended.connect(func(_r): asc_ended[0] += 1)
	var runs_ended: int = _events.get(&"run_ended", 0)
	rs.ascend()
	_check(rs.active and rs.ascending and not paused, "ascension: run resumes")
	var hp_m0: float = rs.enemy_hp_mult()
	game.elapsed += 120.0
	await _frames(3)
	_check(rs.enemy_hp_mult() > hp_m0 * 2.0 and rs.spawn_rate_mult() > 1.2, "ascension: exponential scaling (hp x%.2f)" % (rs.enemy_hp_mult() / hp_m0))
	var w = _spawn(null, "choir_wisp", p.global_position + Vector3(4, 0, 0))
	w.take_damage(99999.0)
	await _frames(2)
	_check(rs.ascension_score > 0, "ascension: score from kills / time (%d)" % rs.ascension_score)
	p.last_stands = 0
	for i in 60:
		_unpause()
		if not p.dash.is_invulnerable():
			break
		await _frames(1)
	p.take_damage(99999.0)
	await _frames(3)
	_check(asc_ended[0] == 1 and _events.get(&"run_ended", 0) == runs_ended, "ascension: death ends it via ascension_ended only")
	_check(bool(rs.last_result.get("ascension", false)) and int(rs.last_result.get("ascension_best", 0)) >= rs.ascension_score, "ascension: result carries score + best")

	print("gameplay_check: %d failure(s)" % _fails)
	paused = false
	quit(1 if _fails > 0 else 0)


func _spawn(_spawner, id: String, pos: Vector3):
	var e = load("res://scenes/enemies/enemy.tscn").instantiate()
	e.setup(load("res://data/enemies/%s.tres" % id))
	root.get_node(^"Game").spawn(e, pos)
	return e


## QA: a sealed arena for checks that read the demon's HP: spawner off, every enemy / shot /
## hazard / pickup gone, no regen, no i-frames left. Nothing else can hurt or heal the demon.
func _isolate(p, spawner) -> void:
	spawner.set_process(false)
	for g: StringName in [&"enemies", &"enemy_shots", &"boss_hazards", &"danger_zones", &"pickups", &"gems"]:
		for n in get_nodes_in_group(g):
			n.queue_free()
	await _frames(2)
	p.regen = 0.0
	_clear_iframes(p)


## QA: drops dash / dodge / mercy i-frames right away (no waiting on timers).
func _clear_iframes(p) -> void:
	for k: StringName in [&"_dash_t", &"_iframe_t", &"_mercy_t"]:
		p.dash.set(k, 0.0)


## Closes a level-up screen opened by kills during the checks (it pauses the tree).
func _unpause() -> void:
	var lvl := current_scene.get_node_or_null(^"LevelUpMenu") as CanvasLayer
	if lvl:
		lvl.visible = false
	var p = root.get_node(^"Game").player
	if p:
		p.pending_level_ups = 0
	paused = false
