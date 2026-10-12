extends AbilityKind
## "hook": drags up to get_count() enemies between params.min_range and params.range to the
## demon's feet, then hits them (Wrecking Ball: a shockwave where they land). Bosses are skipped.


func cast() -> bool:
	var rng := p("range", 10.0)
	var min_r := p("min_range", 3.0)
	var picked: Array[Enemy] = []
	for e in Targeting.nearest_enemies(tree(), player.global_position, 24, rng):
		if e.is_in_group(&"boss") or e.global_position.distance_to(player.global_position) < min_r:
			continue
		picked.append(e)
		if picked.size() >= count():
			break
	if picked.is_empty():
		return false
	for e in picked:
		var dest := player.global_position + Targeting.flat_dir(player.global_position, e.global_position) * 1.3
		AbilityFx.tether(origin(), e.global_position + Vector3(0.0, 0.8, 0.0), def.color, 0.25)
		var tw := e.create_tween()
		tw.tween_property(e, ^"global_position", dest, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(_landed.bind(e, damage()))
	sfx(&"chain", -4.0)
	return true


func _landed(e: Enemy, dmg: float) -> void:
	if not is_instance_valid(e) or e.is_dying or not is_instance_valid(caster):
		return
	e.reset_physics_interpolation()
	var pos := e.global_position
	AbilityCombat.hit(e, dmg, source())
	if Abilities.has_synergy(&"wrecking_ball"):
		var sp: Dictionary = Abilities.synergy_params(&"wrecking_ball")
		AbilityCombat.explode(pos, float(sp.get("radius", 2.0)) * area(),
			float(sp.get("damage", 12.0)) * player.might, AbilityCombat.child_source(source()), def.color)
