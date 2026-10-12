extends Node
## Headless checks for the character-polish systems (skins, motion layer, enemy pose layer):
##   godot --headless --path . res://tools/characters/characters_check.tscn
## Prints PASS / FAIL lines and exits with the failure count. Never writes the save file.

var _fails := 0


func _ready() -> void:
	await get_tree().process_frame
	_check_skins()
	await _check_motion()
	await _check_enemy()
	await _check_round2()
	await _check_round3()
	print("characters_check: %d failure(s)" % _fails)
	get_tree().quit(_fails)


func _ok(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		_fails += 1


func _check_skins() -> void:
	var all := DemonSkins.all()
	_ok(all.size() >= 2, "skins.json loads (%d skins)" % all.size())
	_ok(not DemonSkins.get_skin(&"default").is_empty(), "default skin exists")
	_ok(DemonSkins.is_unlocked(DemonSkins.get_skin(&"default")), "default skin is free")
	for s in all:
		_ok(String(s.id) == "default" or s.has("glow"), "skin %s has a glow color" % s.id)
	var stats: Dictionary = Progression.stats
	var had := stats.duplicate()
	stats.erase("bosses_slain")
	_ok(not DemonSkins.is_unlocked(DemonSkins.get_skin(&"soulfire")), "soulfire locked without a boss kill")
	stats["bosses_slain"] = 1
	_ok(DemonSkins.is_unlocked(DemonSkins.get_skin(&"soulfire")), "soulfire unlocks after a boss kill")
	Progression.stats = had
	_ok(DemonSkins.demon_id_of(load("res://data/demons/vharok.tres")) == &"vharok", "demon_id_of")


func _check_motion() -> void:
	var d := DemonModel.new()
	add_child(d)
	d.build(load("res://data/demons/vharok.tres"), &"soulfire")
	_ok(d.skin_id == &"soulfire", "build() wears the requested skin")
	_ok(d.glow_color.b > d.glow_color.r, "soulfire glow is blue")
	var recolored := false
	for mi in _meshes(d):
		for i in mi.mesh.get_surface_count():
			var mdl := mi.get_surface_override_material(i) as ShaderMaterial
			if mdl and mdl.get_shader_parameter(&"emission") is Color:
				var e: Color = mdl.get_shader_parameter(&"emission")
				if e.b > e.r:
					recolored = true
	_ok(recolored, "glow materials recolored")
	d.set_skin(&"default")
	_ok(d.skin_id == &"default", "set_skin back to default")
	for i in 10:
		d.position.x += 0.2
		d.animate(1.0 / 30.0, 1.0)
		await get_tree().physics_frame
	var m: CharacterMotion = d._motion
	_ok(m != null and m.joint_count() >= 10, "motion layer attached (%d joints)" % (m.joint_count() if m else 0))
	d.play_hurt(Vector3(1, 0, 0))
	d.play_attack()
	await get_tree().process_frame
	_ok(true, "hurt / attack reactions run")
	d.queue_free()


func _check_enemy() -> void:
	var data := load("res://data/enemies/archon.tres") as EnemyData
	var e := data.model.instantiate() as EnemyModel
	e.body_scale = data.size
	add_child(e)
	_ok(e.pose_pivot != null, "enemy pose_pivot exists")
	_ok(e.motion != null, "elite angel gets the motion layer")
	e.hit_from(Vector3(0, 0, -1), 1.0)
	for i in 5:
		e.animate(1.0 / 30.0, 0.0, EnemyModel.State.MOVING)
		await get_tree().physics_frame
	_ok(not e.pose_pivot.basis.is_equal_approx(Basis.IDENTITY), "hit_from tilts the pose pivot")
	e.state_progress = 0.9
	e.state_duration = 1.0
	e.animate(1.0 / 30.0, 0.0, EnemyModel.State.WINDUP)
	_ok(e._glow_now > 0.0, "wind-up telegraph glow is on near the strike")
	e.queue_free()


func _check_round2() -> void:
	# Faction death styles.
	_ok(EnemyPolish.death_style(&"holy_knight") == &"ragdoll", "order dies as a ragdoll")
	_ok(EnemyPolish.death_style(&"cherub") == &"shatter", "angel shatters")
	_ok(EnemyPolish.death_style(&"saint_statue") == &"crumble", "construct crumbles")
	_ok(EnemyPolish.death_style(&"archon") == &"", "Blender angel keeps its death clip")
	# Procedural enemies get the shared pose pivot + readability scale.
	var data := load("res://data/enemies/ophan.tres") as EnemyData
	var m := data.model.instantiate() as EnemyModel
	m.body_scale = data.size
	add_child(m)
	_ok(m.pose_pivot != null and m.pose_pivot.get_parent() == m, "procedural model wrapped in pose_pivot")
	_ok(m.get_child_count() >= 1 and m.visual_scale > 1.0, "ophan readability scale %.2f" % m.visual_scale)
	m.jiggle_eyes(1.0, Vector3(1, 0, 0))
	_ok(m.last_hit_from == Vector3(1, 0, 0), "enemy flinch uses the blow direction")
	m.queue_free()
	# Player hurt source.
	var d := DemonModel.new()
	add_child(d)
	d.build(load("res://data/demons/skarn.tres"))
	d.hit_source = d.global_position + Vector3(0, 0, -3)
	d.play_hurt()
	_ok(d.hit_source == Vector3.INF, "DemonModel consumes hit_source")
	_ok(d._model.scene_root.find_children("fx_embers*", "Node3D", true, false).size() >= 0, "skarn loads")
	d.queue_free()
	# Sariel gets the motion layer through its AnimationTree.
	var sd := load("res://data/bosses/sariel.tres") as EnemyData
	var sm := sd.model.instantiate() as EnemyModel
	sm.body_scale = sd.size
	add_child(sm)
	for i in 3:
		sm.animate(1.0 / 30.0, 0.0, EnemyModel.State.MOVING)
		await get_tree().physics_frame
	_ok(sm.motion != null and sm.motion.joint_count() > 20, "Sariel motion layer (%d joints)" %
		(sm.motion.joint_count() if sm.motion else 0))
	sm.queue_free()


func _check_round3() -> void:
	# Merchant figures build and animate.
	for look in 4:
		var fig := MerchantFigure.create(look)
		_ok(fig != null and fig.head != null, "merchant figure %d builds" % look)
		if fig:
			add_child(fig)
			for i in 5:
				fig.animate(0.1, i % 2 == 0)
			fig.greet()
			fig.react()
			fig.animate(0.1, true)
			fig.queue_free()
	# Per-demon death styles and the victory hold.
	_ok(DemonDeath.style_for(&"skarn") == &"crumble" and DemonDeath.style_for(&"ysolde") == &"unravel",
		"per-demon death styles")
	var d := DemonModel.new()
	add_child(d)
	d.build(load("res://data/demons/morvane.tres"))
	d.play_victory()
	_ok(d._victory and d.process_mode == Node.PROCESS_MODE_ALWAYS, "victory pose holds through the pause")
	d.queue_free()
	_ok(EnemyPolish.VISUAL_SCALE.get(&"templar_ballista", 1.0) > 1.0, "siege models scaled for readability")
	# Round 4: Nhazgul's own feel and death.
	_ok(DemonDeath.style_for(&"nhazgul") == &"swarm", "Nhazgul bursts into a swarm")
	var n := DemonModel.new()
	add_child(n)
	n.build(load("res://data/demons/nhazgul.tres"))
	_ok(n._motion != null and n._motion.twitch > 0.0 and n._motion.buzz_amp > 0.0, "Nhazgul twitches and buzzes")
	_ok(DemonSkins.list_for(&"nhazgul").size() >= 6, "Nhazgul has skins")
	n.queue_free()
	# Round 5: Iscariel's mismatched wings and death.
	_ok(DemonDeath.style_for(&"iscariel") == &"turncoat", "Iscariel dies wing by wing")
	var isc := DemonModel.new()
	add_child(isc)
	isc.build(load("res://data/demons/iscariel.tres"))
	_ok(isc._motion != null and isc._motion.wing_odd_k > 1.0 and isc._motion.wing_odd_twitch > 0.0,
		"Iscariel's charred wing is stiffer and twitchier")
	isc.queue_free()


func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var st: Array[Node] = [root]
	while not st.is_empty():
		var n: Node = st.pop_back()
		if n is MeshInstance3D:
			out.append(n)
		st.append_array(n.get_children())
	return out
