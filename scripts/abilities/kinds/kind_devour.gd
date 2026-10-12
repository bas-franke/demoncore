extends AbilityKind
## "devour" (Gluttony): bites the weakest angels within params.range. Any whose HP is below
## params.threshold x might (x Girth bonus) is swallowed whole: it dies, the demon heals
## params.heal and gains a Girth stack (bigger, more max HP). Others are just bitten.
## Bosses are never swallowed. Params: range, threshold, heal.


func cast() -> bool:
	var foes := AbilityCombat.enemies_in_radius(player.global_position, p("range", 2.6) * area())
	if foes.is_empty():
		return false
	foes.sort_custom(func(a: Enemy, b: Enemy) -> bool: return a.hp < b.hp)
	var limit := p("threshold", 20.0) * player.might * (1.0 + 0.05 * Abilities.girth)
	var src := source()
	src["origin"] = player.global_position
	var eaten := 0
	for e in foes:
		if eaten >= count():
			break
		var at := e.global_position
		_maw(at)
		if e.hp <= limit and not e.is_in_group(&"boss"):
			src["devour"] = true
			AbilityCombat.hit(e, e.hp + 1.0, src)
			Abilities.heal_player(p("heal", 3.0))
			Abilities.add_girth(1)
			InfernalFx.burst(at + Vector3(0.0, 0.6, 0.0), Art.BLOOD, 14, 3.0, 1.2)
		else:
			src.erase("devour")
			AbilityCombat.hit(e, damage(), src)
		eaten += 1
	sfx(&"devour", -3.0)
	return true


## Two jaws of teeth snapping shut over `at`.
func _maw(at: Vector3) -> void:
	if Game.world == null:
		return
	var root := Node3D.new()
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	Game.spawn(root, at + Vector3(0.0, 0.7, 0.0))
	var jaw_mat := Art.glow(def.color, 2.0, true, 0.8)
	for side: float in [-1.0, 1.0]:
		var jaw := Node3D.new()
		root.add_child(jaw)
		jaw.position.y = side * 0.9
		for k in 5:
			Art.part(jaw, Art.cone(0.5), jaw_mat, Vector3((k - 2) * 0.22, 0.0, 0.0), Vector3(0.14, 0.4, 0.14),
				Vector3(0.0 if side < 0.0 else PI, 0.0, 0.0))
		var tw := jaw.create_tween()
		tw.tween_property(jaw, ^"position:y", side * 0.1, 0.12).set_ease(Tween.EASE_IN)
	var t := root.create_tween()
	t.tween_interval(0.3)
	t.tween_callback(root.queue_free)
