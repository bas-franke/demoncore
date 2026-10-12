class_name InfernalFx
## Shared hellfire effects for weapons and demons: ember particles, one-shot bursts, glow flashes.
##
##   var trail := InfernalFx.embers(self, Art.EMBER, 12, 0.5)   # continuous, world-space
##   InfernalFx.burst(hit_pos, Art.HELLFIRE, 14, 3.5)           # one-shot, spawned into the world
##   InfernalFx.flash_sphere(hit_pos, Art.EMBER, 0.9, 0.18)     # expanding glow that fades

static var _ember_mats := {}
static var _ramps := {}
static var _ember_mesh: SphereMesh
static var _shrink: Curve
static var _swell: Curve


## Additive unshaded material that takes its color from the particle color ramp.
static func ember_material(energy: float = 3.0) -> StandardMaterial3D:
	var key := snappedf(energy, 0.01)
	if _ember_mats.has(key):
		return _ember_mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(energy, energy, energy, 1.0)
	_ember_mats[key] = m
	return m


## Low-poly 0.1-diameter sphere used for every ember (size comes from the particle scale).
static func ember_mesh() -> SphereMesh:
	if _ember_mesh == null:
		_ember_mesh = SphereMesh.new()
		_ember_mesh.radius = 0.05
		_ember_mesh.height = 0.1
		_ember_mesh.radial_segments = 6
		_ember_mesh.rings = 3
	return _ember_mesh


## White-hot -> `color` -> dark, fading out.
static func ramp(color: Color) -> Gradient:
	var key := color.to_html()
	if _ramps.has(key):
		return _ramps[key]
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.18, 0.65, 1.0])
	g.colors = PackedColorArray([
		Color(1.0, 0.9, 0.7, 1.0),
		Color(color, 1.0),
		Color(color.r * 0.55, color.g * 0.25, color.b * 0.25, 0.7),
		Color(0.1, 0.02, 0.02, 0.0),
	])
	_ramps[key] = g
	return g


static func shrink_curve() -> Curve:
	if _shrink == null:
		_shrink = Curve.new()
		_shrink.add_point(Vector2(0.0, 1.0))
		_shrink.add_point(Vector2(1.0, 0.0))
	return _shrink


static func swell_curve() -> Curve:
	if _swell == null:
		_swell = Curve.new()
		_swell.add_point(Vector2(0.0, 0.0))
		_swell.add_point(Vector2(0.15, 1.0))
		_swell.add_point(Vector2(0.7, 0.8))
		_swell.add_point(Vector2(1.0, 0.0))
	return _swell


## Bare ember emitter with sane defaults (not added to the tree).
static func make_particles(color: Color, amount: int, lifetime: float, energy: float = 3.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = ember_mesh()
	p.material_override = ember_material(energy)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.amount = maxi(amount, 1)
	p.lifetime = maxf(lifetime, 0.05)
	p.color_ramp = ramp(color)
	p.scale_amount_curve = shrink_curve()
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	p.direction = Vector3.UP
	p.spread = 35.0
	p.gravity = Vector3(0.0, 1.2, 0.0)
	p.damping_min = 0.5
	p.damping_max = 1.5
	return p


## Continuous rising embers, emitted in world space (they trail behind a moving parent).
static func embers(parent: Node3D, color: Color, amount: int, lifetime: float, radius: float = 0.15,
		pos := Vector3.ZERO, energy: float = 3.0) -> CPUParticles3D:
	var p := make_particles(color, amount, lifetime, energy)
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.8
	p.position = pos
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(p)
	return p


## One-shot burst of embers flying outward at `at` (world space). Pooled (perf): finished
## emitters are hidden and reused, at most MAX_BURSTS live at once and BURSTS_PER_FRAME start per
## frame (extra calls are dropped: a weapon hitting 40 angels at once still reads as a fire storm).
static func burst(at: Vector3, color: Color, amount: int = 14, speed: float = 3.0, size: float = 1.0,
		lifetime: float = 0.55) -> void:
	if Game.world == null:
		return
	if _bursts_alive >= MAX_BURSTS or not Perf.budget(&"infernal_burst", BURSTS_PER_FRAME):
		return
	var p := _obtain_burst(at)
	if p == null:
		return
	p.amount = maxi(amount, 1)
	p.lifetime = maxf(lifetime, 0.05)
	p.color_ramp = ramp(color)
	p.emission_sphere_radius = 0.12 * size
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.damping_min = speed * 0.8
	p.damping_max = speed * 1.6
	p.scale_amount_min = 0.6 * size
	p.scale_amount_max = 1.4 * size
	p.restart()


const MAX_BURSTS := 48
const BURSTS_PER_FRAME := 8
static var _burst_pool: Array[CPUParticles3D] = []
static var _bursts_alive := 0


static func _obtain_burst(at: Vector3) -> CPUParticles3D:
	_bursts_alive += 1
	while not _burst_pool.is_empty():
		# QA: pooled bursts are freed with Game.world when a run ends; check before the typed assign.
		var v: Variant = _burst_pool.pop_back()
		if not is_instance_valid(v):
			continue
		var q: CPUParticles3D = v
		if q.is_inside_tree() and q.get_parent() == Game.world:
			q.global_position = at
			q.visible = true
			return q
	var p := make_particles(Art.HELLFIRE, 14, 0.55)
	p.one_shot = true
	p.explosiveness = 0.92
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.spread = 180.0
	p.gravity = Vector3(0.0, 1.5, 0.0)
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	p.emitting = false
	Game.spawn(p, at)
	if not is_instance_valid(p) or not p.is_inside_tree():
		_bursts_alive -= 1
		return null
	p.finished.connect(_release_burst.bind(p))
	# Freed while playing (the world went away with the run): give its slot back.
	p.tree_exiting.connect(func() -> void:
		if p.visible:
			_bursts_alive = maxi(_bursts_alive - 1, 0))
	return p


static func _release_burst(p: CPUParticles3D) -> void:
	_bursts_alive = maxi(_bursts_alive - 1, 0)
	if is_instance_valid(p):
		p.visible = false
		_burst_pool.append(p)


## Brief additive glow sphere that swells and fades (impact flare). Frees itself.
static func flash_sphere(at: Vector3, color: Color, radius: float = 0.6, time: float = 0.18,
		energy: float = 2.5) -> void:
	if Game.world == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = Art.sphere()
	mi.material_override = Art.glow(color, energy, true, 0.6)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mi.scale = Vector3.ONE * radius * 0.6
	Game.spawn(mi, at)
	if not is_instance_valid(mi) or not mi.is_inside_tree():
		return
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, ^"scale", Vector3.ONE * radius * 2.0, time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, ^"transparency", 1.0, time).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


## Polyline helper: a thin glowing cylinder from `a` to `b`, parented to `parent` (local coords).
static func segment(parent: Node3D, a: Vector3, b: Vector3, thickness: float, material: Material) -> MeshInstance3D:
	var d := b - a
	var length := d.length()
	var mi := MeshInstance3D.new()
	mi.mesh = Art.cylinder()
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mi.position = (a + b) * 0.5
	if length > 0.0001:
		var dir := d / length
		var q := Quaternion(Vector3.UP, dir) if dir.dot(Vector3.UP) > -0.999 else Quaternion(Vector3.RIGHT, PI)
		mi.basis = Basis(q) * Basis.from_scale(Vector3(thickness, length, thickness))
	else:
		mi.scale = Vector3(thickness, 0.001, thickness)
	parent.add_child(mi)
	return mi
