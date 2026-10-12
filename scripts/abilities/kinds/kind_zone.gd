extends AbilityKind
## "zone": lingering ground effects (AbilityZone) under up to get_count() nearby enemies.
## Params: range, radius, duration, tick, style (pillar / cloud / pool).


func cast() -> bool:
	var targets := Targeting.nearest_enemies(tree(), player.global_position, count(), p("range", 10.0))
	if targets.is_empty():
		return false
	var r := p("radius", 1.5) * area()
	var dur := p("duration", 3.0) * Abilities.duration_mult()
	for e in targets:
		AbilityZone.spawn(e.global_position, r, dur, p("tick", 0.5), damage(), source(), def.color,
			StringName(style("pool")))
	sfx(&"brimstone" if def.has_tag("fire") else &"cast", -8.0)
	return true
