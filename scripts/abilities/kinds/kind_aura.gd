extends AbilityKind
## "aura": a ring that follows the demon and hits everything inside every cooldown (the tick).

var _ring: Node3D


func cast() -> bool:
	var foes := AbilityCombat.enemies_in_radius(player.global_position, _radius())
	if not foes.is_empty():
		hit_all(foes, player.global_position)
	return true  # keeps ticking quietly when nothing is near


func can_unleash() -> bool:
	return false


func rebuild() -> void:
	if _ring == null:
		_ring = Node3D.new()
		caster.add_child(_ring)
		Art.part(_ring, Art.torus(0.95, 1.0), Art.glow(def.color, 1.5, true, 0.5), Vector3(0.0, 0.08, 0.0), Vector3(1.0, 0.05, 1.0))
		Art.part(_ring, Art.cylinder(), Art.glow(def.color, 0.6, true, 0.1), Vector3(0.0, 0.04, 0.0), Vector3(2.0, 0.01, 2.0))
		var fx := InfernalFx.embers(_ring, def.color, 14, 0.8, 0.9, Vector3(0.0, 0.2, 0.0), 2.0)
		fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		fx.emission_ring_axis = Vector3.UP
		fx.emission_ring_radius = 0.95
		fx.emission_ring_inner_radius = 0.8
		fx.emission_ring_height = 0.05
	var r := _radius()
	_ring.scale = Vector3(r, 1.0, r)


func _radius() -> float:
	return p("radius", 2.0) * area()
