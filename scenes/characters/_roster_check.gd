extends SceneTree
## Smoke test for the procedural character roster (characters-new). Run:
##   godot --headless --path . -s res://scenes/characters/_roster_check.gd [-- --map=<id>]
## Windowed with a screenshot of the brawl (Game handles --shot):
##   godot --path . -s res://scenes/characters/_roster_check.gd -- --godmode --shot=<abs png> --shot-time=5
## Loads the run scene, spawns every roster enemy in a ring around the player (godmode), lets
## them fight for a few seconds (wind-ups, charges, leaps, slams, shots), kills them all (corpse
## animations), then spawns every ally and NPC model through CharacterRoster. Prints PASS/FAIL
## and exits 1 on failure. Duck-typed (a -s script compiles before the autoloads exist).

const ROSTER := "res://scenes/characters/character_roster.gd"

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1


func _frames(n: int) -> void:
	for i in n:
		# Kills give XP: a level-up menu would pause the tree (and every corpse tween) - skip it.
		paused = false
		await physics_frame


func _run() -> void:
	var roster: GDScript = load(ROSTER)
	var game: Node = root.get_node(^"Game")
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(10)
	var p = game.player
	_check(p != null, "player exists")
	game.set(&"godmode", true)
	var spawner: Node = current_scene.get_node_or_null(^"EnemySpawner")
	_check(spawner != null, "spawner exists")
	# Keep the normal spawner quiet so only roster enemies are on the field.
	spawner.set_process(false)

	var ids: Array = roster.enemy_ids()
	_check(ids.size() >= 20, "roster lists %d enemies" % ids.size())
	var enemies: Array = []
	var n := ids.size()
	for i in n:
		var d = roster.enemy_data(ids[i])
		_check(d != null and d.model != null, "data + model: %s" % ids[i])
		if d == null:
			continue
		var e = spawner.spawn(d, TAU * float(i) / float(n)) if spawner.has_method("spawn") else null
		if e:
			# Bring them close so every behaviour engages.
			var a := TAU * float(i) / float(n)
			e.global_position = p.global_position + Vector3(cos(a), 0.0, sin(a)) * (4.0 + float(i % 3) * 2.0)
			enemies.append(e)
	await _frames(3)
	var proc_ok := true
	for e in enemies:
		if not (is_instance_valid(e) and e.model and e.model.has_method("finish")):
			proc_ok = false
	_check(proc_ok, "every roster enemy uses a ProcModel")

	# Fight for a while: states cycle through wind-ups / attacks / recoveries.
	await _frames(150)
	# (The player's weapons fire on their own, so some may already be dead: that exercises deaths.)
	var broken := 0
	for e in enemies:
		if is_instance_valid(e) and not is_instance_valid(e.model):
			broken += 1
	_check(broken == 0, "live roster enemies keep their models after 5 s of fighting")

	# Allies join the fight (AllyMinion controller): each must land at least one hit.
	var ally_script: GDScript = load("res://scenes/characters/allies/ally_minion.gd")
	var hits := {}
	for id in roster.allies().keys():
		var al = ally_script.spawn(StringName(id), p.global_position + Vector3(1.0, 0.0, 1.0), {"lifetime": 6.0, "damage": 1.0})
		_check(al != null, "ally minion spawns: %s" % id)
		if al:
			hits[id] = 0
			al.struck.connect(func(_e, _a): hits[id] = int(hits[id]) + 1)
	await _frames(120)
	for id in hits.keys():
		_check(int(hits[id]) > 0, "ally %s struck angels (%d hits)" % [id, hits[id]])

	# Kill them all (procedural corpses topple / sink / shrink in Game.world).
	for e in enemies:
		if is_instance_valid(e):
			e.take_damage(1.0e6)
	await _frames(6)
	# Track the corpses that exist now (summoners / allies may keep producing new ones later).
	var tracked: Array = []
	for c in game.world.get_children():
		if c.has_method("finish"):
			tracked.append(c)
	_check(tracked.size() > 0, "procedural corpses spawned (%d)" % tracked.size())
	await _frames(90)
	var corpses := 0
	var left := []
	for c in tracked:
		if is_instance_valid(c):
			corpses += 1
			left.append("%s(%s)" % [c.name, c.get(&"death_style")])
	_check(corpses == 0, "corpses cleaned up after 3 s %s (time_scale %.2f)" % [str(left), Engine.time_scale])

	# Bosses (ProcBoss): summon, push through every phase, kill.
	for bid in ["frost_abbot", "verdant_matriarch", "dawn_wyrm", "war_chariot", "storm_archon", "gilded_seraph", "cantor"]:
		await _boss_test(spawner, bid)

	# Sanctified elites: overlay any enemy, multiply its health, and clean up on death.
	var sanct: GDScript = load("res://scenes/characters/elites/sanctified.gd")
	var probe = spawner.spawn(roster.enemy_data(&"holy_knight"))
	await _frames(2)
	var base_hp: float = probe.max_hp
	var ov = sanct.apply(probe, "martyr")
	await _frames(2)
	_check(ov != null and probe.is_in_group(&"sanctified") and probe.max_hp > base_hp * 2.5, "sanctified overlay applies (hp %.0f -> %.0f)" % [base_hp, probe.max_hp])
	_check(sanct.apply(probe) == null, "sanctified refuses a second overlay")
	probe.take_damage(1.0e7)
	await _frames(10)
	_check(not is_instance_valid(probe), "sanctified enemy dies cleanly")

	# Death mechanics run from Enemy.die() (on_host_died), whatever death FX plays.
	var lamb = spawner.spawn(roster.enemy_data(&"paschal_lamb"))
	var hurt = spawner.spawn(roster.enemy_data(&"holy_knight"))
	# Far from the demon so its weapons don't interfere.
	lamb.global_position = p.global_position + Vector3(22.0, 0.0, 0.0)
	hurt.global_position = lamb.global_position + Vector3(1.0, 0.0, 0.0)
	await _frames(2)
	_check(is_instance_valid(lamb) and is_instance_valid(hurt), "lamb test setup alive")
	hurt.hp = hurt.max_hp * 0.3
	var hp_before: float = hurt.hp
	lamb.take_damage(1.0e7)
	await _frames(2)
	_check(is_instance_valid(hurt) and hurt.hp > hp_before, "paschal lamb's death heals nearby angels")
	if is_instance_valid(hurt):
		hurt.take_damage(1.0e7)
	var rev = spawner.spawn(roster.enemy_data(&"crusader_revenant"))
	await _frames(2)
	rev.take_damage(1.0e7)
	await _frames(70)
	var risen := 0
	for en in root.get_tree().get_nodes_in_group(&"enemies"):
		if en.has_meta(&"revenant_risen"):
			risen += 1
			en.take_damage(1.0e7)
	_check(risen == 1, "crusader revenant rises exactly once (%d)" % risen)
	await _frames(70)
	risen = 0
	for en in root.get_tree().get_nodes_in_group(&"enemies"):
		if en.has_meta(&"revenant_risen") and not en.is_dying:
			risen += 1
	_check(risen == 0, "the risen revenant stays down")

	# The Celestial Leviathan: a pass starts, drops stars and leaves.
	var whale_script: GDScript = load("res://scenes/characters/events/celestial_whale.gd")
	var whale = whale_script.spawn_pass()
	_check(whale != null, "celestial whale pass spawns")
	await _frames(150)
	_check(is_instance_valid(whale), "celestial whale still drifting after 5 s")
	if is_instance_valid(whale):
		whale.queue_free()

	# Allies + NPCs.
	var holder := Node3D.new()
	current_scene.add_child(holder)
	var made := 0
	for id in roster.allies().keys():
		var m = roster.make_ally(StringName(id))
		_check(m != null, "ally model: %s" % id)
		if m:
			holder.add_child(m)
			made += 1
	for id in roster.npcs().keys():
		var m = roster.spawn_npc(holder, StringName(id), Vector3(float(made), 0.0, 3.0), 0.0)
		_check(m != null, "npc model: %s" % id)
		if m:
			made += 1
			m.talk()
	await _frames(30)
	var alive := 0
	for c in holder.get_children():
		if c.has_method("finish") and is_instance_valid(c):
			alive += 1
	_check(alive == made, "allies / NPCs alive and animating (%d / %d)" % [alive, made])
	holder.queue_free()
	await _frames(2)
	print("roster check: %s" % ("OK" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails > 0 else 0)


func _boss_test(spawner: Node, bid: String) -> void:
	spawner.set(&"boss", load("res://data/bosses/%s.tres" % bid))
	spawner.set(&"boss_scene", load("res://scenes/characters/bosses/%s.tscn" % bid))
	var b = spawner.spawn_boss()
	_check(b != null and b.has_method(&"phase_name"), "boss spawns: %s" % bid)
	if b == null:
		return
	await _frames(100)  # intro
	for k in 2:
		b.take_damage(b.max_hp * 0.4)
		await _frames(90)  # transition + an attack or two
	_check(is_instance_valid(b) and int(b.phase_index) == 2, "%s reached phase III (%s)" % [bid, b.phase_name() if is_instance_valid(b) else "?"])
	await _frames(90)
	b.take_damage(b.max_hp * 2.0)
	await _frames(130)
	_check(not is_instance_valid(b), "%s died and was freed" % bid)
	get_root().get_tree().call_group(&"boss_hazards", &"dissipate")
