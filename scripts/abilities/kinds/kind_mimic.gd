extends AbilityKind
## "mimic" (Envy): copies the attack of the nearest angel within params.range, turned against its
## own kind: shooters -> a fan of stolen holy bolts, chargers / leapers -> a lance of light along
## the ground, slammers -> a smite circle on the angel, anything else -> a column of judgement.
## Params: range, radius, length, width.


func cast() -> bool:
	var e := Targeting.nearest_enemy(tree(), player.global_position, p("range", 10.0))
	if e == null or e.data == null:
		return false
	var at := e.global_position
	var src := source()
	src["origin"] = player.global_position
	match e.data.behavior:
		EnemyData.Behavior.SHOOT, EnemyData.Behavior.KITE:
			var aim := Targeting.flat_dir(player.global_position, at)
			for i in 5:
				var b := AbilityBolt.create(src, damage() * 0.6, aim.rotated(Vector3.UP, (i - 2) * 0.16) * 15.0,
					def.color, &"holy", 0.2)
				b.lifetime = 1.0
				Game.spawn.call_deferred(b, origin())
		EnemyData.Behavior.CHARGE, EnemyData.Behavior.HOP:
			var a := player.global_position
			var b2 := a + Targeting.flat_dir(a, at) * p("length", 10.0) * area()
			AbilityFx.beam(a, b2, p("width", 1.2) * area(), def.color, 0.4, 0.6)
			hit_all(AbilityCombat.enemies_on_segment(a, b2, p("width", 1.2) * area() * 0.5), a, damage() * 1.2)
		EnemyData.Behavior.SLAM, EnemyData.Behavior.SHIELD:
			var r := p("radius", 2.4) * area()
			AbilityFx.ring(at, r, def.color, 0.4)
			AbilityFx.pillar(at, r * 0.6, def.color, 0.3, 2.5)
			hit_all(AbilityCombat.enemies_in_radius(at, r), at, damage() * 1.3)
		_:
			AbilityFx.pillar(at, 0.9, def.color, 0.4)
			AbilityFx.lightning(at + Vector3(0.0, 8.0, 0.0), at, def.color, 0.2, 0.08)
			var one: Array[Enemy] = [e]
			hit_all(one, at, damage() * 1.6)
	AbilityFx.sigil(at + Vector3(0.0, 1.8, 0.0), def.color, 0.5)
	sfx(&"choir", -10.0)
	return true
