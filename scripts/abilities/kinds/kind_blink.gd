extends AbilityKind
## "blink": when an enemy presses within params.trigger_range, the demon steps params.range through
## it (stopping short of walls), cutting everything on the path. Brief i-frames on arrival.


func cast() -> bool:
	var pressed := Targeting.nearest_enemy(tree(), player.global_position, p("trigger_range", 3.0))
	if pressed == null:
		return false
	var from := player.global_position
	var dir := Targeting.flat_dir(from, pressed.global_position)
	var dest := clip_to_world(from, from + dir * p("range", 7.0))
	hit_all(AbilityCombat.enemies_on_segment(from, dest, p("width", 1.2) * 0.5 * area()), from)
	InfernalFx.burst(from + Vector3(0.0, 0.8, 0.0), def.color, 16, 3.0, 1.2)
	AbilityFx.beam(from, dest, 0.6, def.color, 0.3, 0.8)
	player.global_position = dest
	player.reset_physics_interpolation()
	# A short window of invulnerability on arrival (PlayerDash, gameplay role), if present.
	var dash: Object = player.get(&"dash")
	if dash and dash.has_method(&"grant_iframes"):
		dash.call(&"grant_iframes", 0.35)
	InfernalFx.flash_sphere(dest + Vector3(0.0, 0.8, 0.0), def.color, 1.0, 0.2)
	Abilities.on_blink(from, dest)
	sfx(&"wingbeat", -3.0)
	return true


## Stops a move short of world geometry (layer 1) so nothing lands inside a wall.
func clip_to_world(from: Vector3, to: Vector3) -> Vector3:
	var space := caster.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from + Vector3(0.0, 0.5, 0.0), to + Vector3(0.0, 0.5, 0.0), 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return to
	var at: Vector3 = hit["position"]
	return from + Targeting.flat_dir(from, at) * maxf(from.distance_to(at) - 0.8, 0.0)
