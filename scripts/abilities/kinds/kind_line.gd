extends AbilityKind
## "line": params.count strips (fissure on the ground, or a raised "beam") from the demon toward
## the nearest enemy, fanned 0.45 rad apart. Params: length, width, count, style.


func cast() -> bool:
	var length := p("length", 8.0) * area()
	var near := Targeting.nearest_enemy(tree(), player.global_position, length)
	if near == null:
		return false
	var base_dir := Targeting.flat_dir(player.global_position, near.global_position)
	var width := p("width", 1.0) * area()
	var n := int(p("count", 1.0))
	var beam := style("fissure") == "beam"
	for i in n:
		var dir := base_dir.rotated(Vector3.UP, (i - (n - 1) * 0.5) * 0.45)
		var a := player.global_position
		var b := a + dir * length
		if beam:
			AbilityFx.beam(a + dir * 0.5, b, width, def.color, 0.4, 1.0)
		else:
			AbilityFx.beam(a, b, width, def.color, 0.5)
			for k in 4:
				InfernalFx.burst(a.lerp(b, (k + 1) / 5.0) + Vector3(0.0, 0.2, 0.0), def.color, 6, 3.0, 1.0)
			after(a.lerp(b, 0.6))
		hit_all(AbilityCombat.enemies_on_segment(a, b, width * 0.5), a)
	sfx(&"beam" if beam else &"impact", -5.0)
	return true
