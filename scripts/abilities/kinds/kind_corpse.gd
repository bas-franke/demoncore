extends AbilityKind
## "corpse": detonates up to get_count() fresh corpses within params.range (Abilities keeps the
## last few seconds of deaths). Params: radius.


func cast() -> bool:
	var spots := Abilities.take_corpses(player.global_position, p("range", 10.0), count())
	if spots.is_empty():
		return false
	var r := p("radius", 2.0) * area()
	var src := source()
	for at in spots:
		InfernalFx.burst(at + Vector3(0.0, 0.3, 0.0), Art.BONE, 10, 4.0, 1.0)
		AbilityCombat.explode(at, r, damage(), src, def.color)
	sfx(&"impact", -4.0)
	return true
