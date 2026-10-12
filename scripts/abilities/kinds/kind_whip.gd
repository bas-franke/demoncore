extends AbilityKind
## "whip" (Hellfire whip / chain dancer): get_count() lashes 0.12 s apart, alternating sides, each
## sweeping an arc of params.arc degrees out to params.length. Foes in the outer third take the
## crack of the tip (x params.tip_mult). style "spin" lashes all the way around the demon.
## Chain Dancer synergy: +30% reach. Params: length, arc, tip_mult, knockback.


func cast() -> bool:
	var reach := _reach()
	var near := Targeting.nearest_enemy(tree(), player.global_position, reach)
	if near == null:
		return false
	var dir := Targeting.flat_dir(player.global_position, near.global_position)
	var dmg := damage()
	for i in count():
		var side := 1.0 if i % 2 == 0 else -1.0
		if i == 0:
			_lash(dir, side, dmg)
		else:
			tree().create_timer(0.12 * i, false).timeout.connect(_lash.bind(dir, side, dmg))
	return true


func _reach() -> float:
	var r := p("length", 5.0) * area()
	if Abilities.has_synergy(&"chain_dancer"):
		r *= 1.3
	return r


func _lash(dir: Vector3, side: float, dmg: float) -> void:
	if not is_instance_valid(caster) or not is_instance_valid(player):
		return
	var center := player.global_position
	var reach := _reach()
	var spin := style("lash") == "spin"
	var arc := TAU if spin else deg_to_rad(p("arc", 120.0))
	_draw(center, dir, side, reach, arc)
	var src := source()
	src["origin"] = center
	for e in AbilityCombat.enemies_in_radius(center, reach):
		var to := e.global_position - center
		to.y = 0.0
		if not spin and Targeting.flat_dir(center, e.global_position).angle_to(dir) > arc * 0.5:
			continue
		var tip := to.length() >= reach * 0.66
		AbilityCombat.hit(e, dmg * (p("tip_mult", 1.6) if tip else 1.0), src)
		if tip:
			InfernalFx.burst(e.global_position + Vector3(0.0, 0.8, 0.0), def.color.lerp(Color.WHITE, 0.5), 4, 2.0, 0.5)
	sfx(&"chain" if def.has_tag("chain") else &"cleave", -6.0)


## The lash: a chain of glowing links swept along a curve from the hand out to the tip.
func _draw(center: Vector3, dir: Vector3, side: float, reach: float, arc: float) -> void:
	if Game.world == null:
		return
	var root := Node3D.new()
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	Game.spawn(root, Vector3.ZERO)
	var mat := Art.glow(def.color, 2.6, true, 0.85)
	var steps := 9
	var prev := center + Vector3(0.0, 1.0, 0.0)
	for k in range(1, steps + 1):
		var t := float(k) / steps
		# The lash curls: angle sweeps across the arc while the radius grows to full reach.
		var ang := (t - 0.5) * arc * side * 0.9
		var pt := center + dir.rotated(Vector3.UP, ang) * reach * t + Vector3(0.0, 1.0 - 0.75 * t, 0.0)
		InfernalFx.segment(root, prev, pt, 0.08 * (1.2 - t * 0.6), mat)
		prev = pt
	InfernalFx.flash_sphere(prev, def.color, 0.4, 0.15)
	var tw := root.create_tween()
	tw.tween_interval(0.16)
	tw.tween_callback(root.queue_free)
