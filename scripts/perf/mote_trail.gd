class_name MoteTrail
## A projectile's trail of glowing motes as ONE world-space CPUParticles3D (perf role).
## Replaces the "spawn a MeshInstance3D + tween into Game.world every few ticks" pattern, which
## created and freed hundreds of nodes per second once a few dozen projectiles were in the air.
##
##   MoteTrail.attach(self, Art.glow(Art.HOLY, 2.5), 0.1, 0.4, 0.06, 1.6)
##
## The motes keep their world position (they hang behind the projectile), shrink to nothing over
## `lifetime` and sink with `sink` m/s^2. They vanish together with the projectile.


## `size` = mote diameter (m), `every` = seconds between motes, `jitter` = spawn sphere radius.
static func attach(parent: Node3D, material: Material, size: float, lifetime: float, every: float,
		sink: float = 0.0, jitter: float = 0.08) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = &"MoteTrail"
	p.mesh = Art.sphere()
	p.material_override = material
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.local_coords = false
	p.amount = maxi(ceili(lifetime / maxf(every, 0.01)), 1)
	p.lifetime = maxf(lifetime, 0.05)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = jitter
	p.direction = Vector3.DOWN
	p.spread = 0.0
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.0
	p.gravity = Vector3(0.0, -sink, 0.0)
	p.scale_amount_min = size
	p.scale_amount_max = size
	p.scale_amount_curve = InfernalFx.shrink_curve()
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(p)
	return p
