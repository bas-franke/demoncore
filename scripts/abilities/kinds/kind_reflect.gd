extends AbilityKind
## "reflect" (Envy): steals enemy projectiles (holy orbs, crossbow bolts, any non-player Area3D
## with `velocity` and `damage`) within params.radius and hurls them back at the nearest angels
## for ability damage + params.power x their own. With nothing to steal it fires one stolen ray.
## Params: radius, count (max projectiles), power, speed.


func cast() -> bool:
	var r := p("radius", 5.0) * area()
	var stolen := 0
	if Game.world:
		for n in Game.world.get_children():
			if stolen >= count() + 2:
				break
			var a := n as Area3D
			if a == null or a is AbilityBolt or a is Projectile or a.is_queued_for_deletion():
				continue
			if not ("velocity" in a and "damage" in a):
				continue
			if a.global_position.distance_to(player.global_position) > r:
				continue
			_throw_back(a.global_position, float(a.get(&"damage")))
			InfernalFx.flash_sphere(a.global_position, def.color, 0.5, 0.15)
			a.queue_free()
			stolen += 1
	if stolen == 0:
		var near := Targeting.nearest_enemy(tree(), player.global_position, 10.0)
		if near == null:
			return false
		_throw_back(origin(), 0.0)
	sfx(&"reflect", -4.0)
	return true


func _throw_back(from: Vector3, their_damage: float) -> void:
	var target := Targeting.nearest_enemy(tree(), from, 14.0)
	var dir := Targeting.flat_dir(from, target.global_position) if target else Vector3.FORWARD
	var b := AbilityBolt.create(source(), damage() + their_damage * p("power", 2.0) * player.might,
		dir * p("speed", 16.0) * player.projectile_speed, def.color, &"holy", 0.24)
	b.homing = 5.0
	b.pierce = 1
	b.lifetime = 1.2
	Game.spawn.call_deferred(b, Vector3(from.x, 0.8, from.z))
