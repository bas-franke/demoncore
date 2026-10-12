extends AbilityKind
## "cone": a melee arc toward the nearest enemy. Params: radius, arc (degrees), knockback.


func cast() -> bool:
	var r := p("radius", 3.0) * area()
	var center := player.global_position
	var near := Targeting.nearest_enemy(tree(), center, r + 0.5)
	if near == null:
		return false
	var dir := Targeting.flat_dir(center, near.global_position)
	var half := deg_to_rad(p("arc", 100.0)) * 0.5
	AbilityFx.fan(center, dir, r, rad_to_deg(half * 2.0), def.color, 0.3)
	var foes: Array[Enemy] = []
	for e in AbilityCombat.enemies_in_radius(center, r):
		if Targeting.flat_dir(center, e.global_position).angle_to(dir) <= half:
			foes.append(e)
	hit_all(foes, center)
	after(center + dir * r * 0.6)
	sfx(&"cleave", -4.0)
	tree().call_group(&"camera_rig", &"shake", 0.1)
	return true
