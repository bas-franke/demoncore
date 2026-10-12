extends AbilityKind
## "retaliate" (Wrath): once the demon's Wrath reaches params.threshold stacks, vents it as a nova:
## base damage + Wrath x params.retaliate_mult (x might), spending half the Wrath.
## Params: radius, threshold, retaliate_mult, knockback.


func cast() -> bool:
	if Abilities.wrath < p("threshold", 6.0):
		return false
	var r := p("radius", 3.5) * area()
	var center := player.global_position
	var foes := AbilityCombat.enemies_in_radius(center, r)
	if foes.is_empty():
		return false
	var dmg := damage() + Abilities.wrath * p("retaliate_mult", 2.0) * player.might
	Abilities.wrath *= 0.5
	AbilityFx.ring(center, r, def.color, 0.45)
	AbilityFx.ring(center, r * 0.6, Color.WHITE, 0.3)
	AbilityFx.pillar(center, 1.0, def.color, 0.3, 3.0)
	InfernalFx.burst(center + Vector3(0.0, 0.8, 0.0), def.color, 24, r * 2.5, 1.4)
	hit_all(foes, center, dmg)
	after(center)
	sfx(&"smite", -2.0)
	tree().call_group(&"camera_rig", &"shake", 0.18)
	return true
