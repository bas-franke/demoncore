extends AbilityKind
## "turret" / "mine" / "decoy": places AbilityConstructs. Keeps at most params.max alive per
## ability (the oldest is finished first). Turrets and decoys go beside the demon; mines are
## strewn around it. Params: count (placed per cast), max, rate, reach, lifetime, flamer (1 = flame
## cone turret), scatter (mine spread radius).


func cast() -> bool:
	if Targeting.nearest_enemy(tree(), player.global_position, maxf(p("reach", 8.0) * 1.5, 8.0)) == null:
		return false
	var type := StringName(String(def.kind))
	var n := count()
	var mine := type == &"mine"
	for i in n:
		var off: Vector3
		if mine:
			var a := randf() * TAU
			off = Vector3(cos(a), 0.0, sin(a)) * randf_range(1.0, p("scatter", 3.0))
		else:
			off = Vector3(randf_range(-1.6, 1.6), 0.0, randf_range(-1.6, 1.6))
		var c := AbilityConstruct.spawn(player.global_position + off, def.id, type, damage(), p("rate", 0.8),
			p("reach", 8.0) * (area() if mine or type == &"decoy" else 1.0),
			p("lifetime", 10.0) * Abilities.duration_mult(), source(), def.color)
		if c:
			c.flamer = p("flamer") > 0.0
	_enforce_limit()
	sfx(&"mine_cast" if mine else (&"decoy_cast" if type == &"decoy" else &"turret_cast"), -7.0)
	return true


func _enforce_limit() -> void:
	var mine: Array[AbilityConstruct] = []
	for n in tree().get_nodes_in_group(AbilityConstruct.GROUP):
		var c := n as AbilityConstruct
		if c and c.get_meta(&"ability", &"") == def.id:
			mine.append(c)
	var cap := int(p("max", 4.0)) + Abilities.count_bonus(def)
	for i in maxi(mine.size() - cap, 0):
		mine[i].finish()
