extends AbilityKind
## "strike": telegraphed impacts from the sky at get_count() spots after params.delay.
## style "meteor" aims at the densest pack and drops a burning rock; "lightning" picks at random;
## "gold" is a falling ingot (Greed). Params: range, radius, delay, knockback.


func cast() -> bool:
	var spots := pick_spots(count(), p("range", 12.0), style("meteor") != "lightning")
	if spots.is_empty():
		return false
	var r := p("radius", 2.0) * area()
	var delay := p("delay", 0.6)
	for at in spots:
		AbilityFx.telegraph(at, r, def.color, delay)
		if style("meteor") != "lightning":
			_drop_rock(at, delay)
		tree().create_timer(delay, false).timeout.connect(_impact.bind(at, r, damage()))
	return true


## Up to `n` ground points on enemies within `rng`; `dense` prefers the most crowded spots.
func pick_spots(n: int, rng: float, dense: bool) -> Array[Vector3]:
	var foes := AbilityCombat.enemies_in_radius(player.global_position, rng)
	var out: Array[Vector3] = []
	if foes.is_empty():
		return out
	foes.shuffle()
	for i in n:
		var best := foes[i % foes.size()]
		if dense:
			var best_n := -1
			for k in mini(6, foes.size()):
				var cand := foes[(i * 3 + k) % foes.size()]
				var crowd := AbilityCombat.enemies_in_radius(cand.global_position, 2.5).size()
				if crowd > best_n:
					best_n = crowd
					best = cand
		var at := best.global_position
		if i >= foes.size():
			at += Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5))
		out.append(at)
	return out


func _drop_rock(at: Vector3, delay: float) -> void:
	if Game.world == null:
		return
	var rock := Node3D.new()
	rock.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	Game.spawn(rock, at + Vector3(3.0, 12.0, 2.0))
	if style("meteor") == "gold":
		Art.part(rock, Art.box(), Art.mat(Art.GOLD, 0.25, 1.0), Vector3.ZERO, Vector3(1.2, 0.5, 0.6))
	else:
		Art.part(rock, Art.sphere(), Art.emissive(Art.OBSIDIAN, def.color, 3.0), Vector3.ZERO, Vector3.ONE * 0.9)
	Art.part(rock, Art.sphere(), Art.glow(def.color, 2.0, true, 0.6), Vector3.ZERO, Vector3.ONE * 1.4)
	InfernalFx.embers(rock, def.color, 16, 0.4, 0.4)
	var tw := rock.create_tween()
	tw.tween_property(rock, ^"position", at + Vector3(0.0, 0.3, 0.0), delay).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(rock.queue_free)


func _impact(at: Vector3, r: float, dmg: float) -> void:
	if not is_instance_valid(caster) or not is_instance_valid(player) or player.is_dead:
		return
	if style("meteor") == "lightning":
		AbilityFx.lightning(at + Vector3(randf_range(-1.0, 1.0), 9.0, randf_range(-1.0, 1.0)), at, def.color, 0.25, 0.1)
		AbilityFx.pillar(at, r * 0.5, def.color, 0.25)
		sfx(&"beam", -7.0)
	else:
		AbilityFx.pillar(at, r * 0.7, def.color, 0.35, 3.0)
		InfernalFx.burst(at + Vector3(0.0, 0.4, 0.0), def.color, 20, r * 3.0, 1.5)
		tree().call_group(&"camera_rig", &"shake", 0.12)
		sfx(&"impact", -3.0)
	AbilityFx.ring(at, r, def.color, 0.35)
	var src := source()
	src["origin"] = at
	src["knockback"] = maxf(p("knockback"), 3.0)
	for e in AbilityCombat.enemies_in_radius(at, r):
		AbilityCombat.hit(e, dmg, src)
	after(at)
