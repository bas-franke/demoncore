extends AbilityKind
## "nova": a burst around the demon hitting everything within params.radius.


func cast() -> bool:
	var r := p("radius", 3.0) * area()
	var center := player.global_position
	var foes := AbilityCombat.enemies_in_radius(center, r)
	if foes.is_empty():
		return false
	AbilityFx.ring(center, r, def.color, 0.4)
	AbilityFx.disc(center, r, def.color, 0.35, 0.2)
	InfernalFx.burst(center + Vector3(0.0, 0.5, 0.0), def.color, 18, r * 2.0, 1.2)
	hit_all(foes, center)
	after(center)
	sfx(&"brimstone" if def.has_tag("fire") else &"smite", -5.0)
	tree().call_group(&"camera_rig", &"shake", 0.08)
	return true
