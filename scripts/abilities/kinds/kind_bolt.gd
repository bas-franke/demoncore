extends AbilityKind
## "bolt": fires get_count() AbilityBolts at the nearest enemies, or fanned toward the nearest when
## params.spread > 0. Params: range, speed, spread, pierce, size, homing, explode, style.


func cast() -> bool:
	var rng := p("range", 12.0)
	var n := count()
	var from := origin()
	var targets := Targeting.nearest_enemies(tree(), from, n, rng)
	if targets.is_empty():
		return false
	var spread := p("spread")
	var speed := p("speed", 12.0) * player.projectile_speed
	var aim := Targeting.flat_dir(from, targets[0].global_position)
	var src := source()
	for i in n:
		var dir: Vector3
		if spread > 0.0 and n > 1:
			dir = aim.rotated(Vector3.UP, lerpf(-spread, spread, float(i) / (n - 1)) * 0.5 * (1.0 + 0.05 * n))
		else:
			dir = Targeting.flat_dir(from, targets[i % targets.size()].global_position)
			if i >= targets.size():
				dir = dir.rotated(Vector3.UP, randf_range(-0.3, 0.3))
		fire(from, dir * speed, src, rng)
	sfx(&"fire_bolt" if def.has_tag("fire") else &"cast", -8.0)
	return true


## Spawns one bolt configured from this ability's params (also used by turrets and reflects).
func fire(from: Vector3, velocity: Vector3, src: Dictionary, rng: float, dmg: float = -1.0) -> AbilityBolt:
	var b := AbilityBolt.create(src, damage() if dmg < 0.0 else dmg, velocity, def.color,
		StringName(style("orb")), p("size", 0.2))
	b.pierce = int(p("pierce"))
	b.lifetime = rng / maxf(velocity.length(), 1.0) + 0.25
	b.homing = p("homing")
	b.explode_radius = p("explode") * area()
	# Deferred: casts can come from physics callbacks, where areas can't be added.
	Game.spawn.call_deferred(b, from)
	return b
