class_name HubScenery
extends Node3D
## Everything you see (and bump into) in Basecamp Hell, built in code: environment and sun, the
## flagstone plateau over a lava sea, black spires, the bonfire, the hellgate, the merchants' stalls
## (forge, ritual corner, counting desk, map table), the summoning circle, the Covenant lectern and
## the scattered trophies. Purely visual plus static colliders; the interactive parts (merchants,
## gate prompt, circle, lectern) are added by Basecamp on top of it, at the positions below.

const LAVA_SHADER := preload("res://scenes/basecamp/lava.gdshader")
const PORTAL_SHADER := preload("res://scenes/basecamp/portal.gdshader")
const SIGIL_SHADER := preload("res://scenes/weapons/brimstone_sigil/sigil.gdshader")

## Walkable plateau bounds (XZ).
const X0 := -15.0
const X1 := 15.0
const Z0 := -13.0
const Z1 := 11.0
## Layout (ground positions).
const SPAWN := Vector3(0.0, 0.0, 5.0)
const GATE := Vector3(0.0, 0.0, -10.5)
const FIRE := Vector3(0.0, 0.0, 1.0)
const SMITH := Vector3(-10.0, 0.0, -3.0)
const OCCULT := Vector3(10.0, 0.0, -3.0)
const BROKER := Vector3(-8.5, 0.0, 6.5)
const CARTO := Vector3(5.5, 0.0, -9.0)
const CIRCLE := Vector3(8.5, 0.0, 6.5)
const COVENANT := Vector3(-4.6, 0.0, 8.6)

## The swirling portal quad (instance uniform "charge" 0..1 spins it up) and its light.
var gate_surface: MeshInstance3D
var gate_light: OmniLight3D
## While true the gate light is left to the caller's tween instead of flickering.
var gate_charging := false

## Round obstacles on the ground, [Vector3 centre, float radius] (every post + merchant), for
## HubWanderer avoidance.
var obstacles: Array = []
var _flicker: Array[OmniLight3D] = []
var _flicker_base: PackedFloat32Array = PackedFloat32Array()
var _t := 0.0
var _rng := RandomNumberGenerator.new()


## Builds the whole camp (call once, after adding this node to the tree).
func build() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rng.seed = 666
	_build_environment()
	_build_ground()
	_build_lava()
	_build_cliffs()
	_build_bounds()
	_build_bonfire()
	_build_gate()
	_build_stalls()
	_build_circle()
	_build_covenant()
	_build_decor()
	_build_ambience()


func _process(delta: float) -> void:
	_t += delta
	# Uneven firelight flicker.
	for i in _flicker.size():
		var l := _flicker[i]
		if is_instance_valid(l) and not (l == gate_light and gate_charging):
			l.light_energy = _flicker_base[i] * (0.85 + 0.1 * sin(_t * 7.0 + i * 1.7) + 0.05 * sin(_t * 17.0 + i))


func _build_stalls() -> void:
	_build_forge()
	_build_ritual_corner()
	_build_broker_desk()
	_build_map_table()


# ---------------------------------------------------------------- environment

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.008, 0.005)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.42, 0.36)
	env.ambient_light_energy = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.22, 0.08, 0.05)
	env.fog_light_energy = 1.0
	env.fog_density = 0.003
	env.fog_height = 0.4
	env.fog_height_density = 0.05
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_albedo = Color(0.7, 0.55, 0.5)
	env.volumetric_fog_emission = Color(0.03, 0.006, 0.003)
	env.volumetric_fog_length = 48.0
	env.volumetric_fog_ambient_inject = 0.2
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# A dim, blood-red "sun" from the burning sky for shape and shadows.
	var sun := DirectionalLight3D.new()
	sun.basis = Basis.looking_at(Vector3(0.35, -1.0, 0.45).normalized(), Vector3.UP)
	sun.light_color = Color(1.0, 0.55, 0.35)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0
	add_child(sun)


func _build_ground() -> void:
	var stones: Array[Material] = [
		Art.mat(Color(0.22, 0.19, 0.18), 0.9, 0.0, 0.55, false, 0.0, &"stone"),
		Art.mat(Color(0.27, 0.22, 0.2), 0.85, 0.0, 0.6, false, 0.0, &"stone"),
		Art.mat(Color(0.17, 0.15, 0.15), 0.92, 0.0, 0.5, false, 0.0, &"stone"),
	]
	var grout := Art.glow(Art.HELLFIRE, 0.35, false)
	# Glowing bed under the flagstones: the gaps between them read as cracks of magma.
	var bed := Art.part(self, Art.box(), grout, Vector3((X0 + X1) * 0.5, -0.32, (Z0 + Z1) * 0.5),
			Vector3(X1 - X0 + 2.0, 0.2, Z1 - Z0 + 2.0))
	bed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tile := 2.0
	var x := X0 - 1.0
	while x < X1 + 1.0:
		var z := Z0 - 1.0
		while z < Z1 + 1.0:
			var h := _rng.randf_range(-0.04, 0.02)
			var tilt := Vector3(_rng.randf_range(-0.02, 0.02), _rng.randf_range(-0.05, 0.05), _rng.randf_range(-0.02, 0.02))
			var gap := _rng.randf_range(0.05, 0.14)
			Art.part(self, Art.box(), stones[_rng.randi() % stones.size()],
					Vector3(x + tile * 0.5, -0.12 + h, z + tile * 0.5), Vector3(tile - gap, 0.24, tile - gap), tilt)
			z += tile
		x += tile
	# A worn processional path of darker slabs from the bonfire to the gate.
	var path_m := Art.mat(Color(0.08, 0.06, 0.06), 0.8, 0.0, 0.4, false, 0.0, &"stone")
	var z2 := GATE.z + 2.5
	while z2 < FIRE.z - 1.5:
		Art.part(self, Art.box(), path_m, Vector3(_rng.randf_range(-0.1, 0.1), 0.02, z2), Vector3(2.4, 0.06, 1.1),
				Vector3(0.0, _rng.randf_range(-0.06, 0.06), 0.0))
		z2 += 1.3


func _build_lava() -> void:
	var sm := ShaderMaterial.new()
	sm.shader = LAVA_SHADER
	# One big lava sea under the whole plateau, visible past every edge.
	var plane := PlaneMesh.new()
	plane.size = Vector2(120.0, 90.0)
	var sea := MeshInstance3D.new()
	sea.mesh = plane
	sea.material_override = sm
	sea.position = Vector3(0.0, -1.6, -10.0)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)
	# Plateau cliff skirt (dark rock between the floor and the lava).
	var rock := Art.mat(Color(0.07, 0.05, 0.05), 0.95, 0.0, 0.5, false, 0.0, &"stone")
	Art.part(self, Art.box(), rock, Vector3((X0 + X1) * 0.5, -1.0, (Z0 + Z1) * 0.5),
			Vector3(X1 - X0 + 2.4, 1.4, Z1 - Z0 + 2.4))
	# Warm uplight from the lava along the near (south) edge and the sides.
	for p: Vector3 in [Vector3(-9.0, -0.6, Z1 + 2.5), Vector3(9.0, -0.6, Z1 + 2.5),
			Vector3(X0 - 2.5, -0.6, -2.0), Vector3(X1 + 2.5, -0.6, -2.0)]:
		var l := Art.light(self, Color(1.0, 0.3, 0.06), 3.0, 9.0, p)
		_flicker_light(l)


func _build_cliffs() -> void:
	# Jagged black spires behind the gate and along the far sides, rimmed by the lava glow.
	var rock := Art.mat(Color(0.09, 0.06, 0.055), 0.95, 0.0, 0.55, false, 0.0, &"stone")
	var vein := Art.glow(Art.HELLFIRE, 1.4, false)
	for i in 26:
		var t := float(i) / 25.0
		var x := lerpf(-34.0, 34.0, t) + _rng.randf_range(-1.2, 1.2)
		var z := -26.0 - _rng.randf_range(0.0, 6.0) + absf(x) * 0.15
		var h := _rng.randf_range(7.0, 18.0) * (1.0 - absf(x) / 60.0)
		var w := _rng.randf_range(2.5, 5.0)
		var spire := Art.part(self, Art.cone(0.5), rock, Vector3(x, h * 0.5 - 2.0, z), Vector3(w, h, w * 0.8),
				Vector3(_rng.randf_range(-0.1, 0.1), _rng.randf() * TAU, _rng.randf_range(-0.1, 0.1)))
		spire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if _rng.randf() < 0.5:
			Art.part(self, Art.box(), vein, Vector3(x, h * 0.25 - 1.0, z + w * 0.3), Vector3(0.12, h * 0.5, 0.12),
					Vector3(0.0, 0.0, _rng.randf_range(-0.3, 0.3)))
	for side: float in [-1.0, 1.0]:
		for i in 7:
			var z := lerpf(-22.0, 8.0, float(i) / 6.0)
			var h := _rng.randf_range(5.0, 11.0)
			var w := _rng.randf_range(2.5, 4.5)
			var side_spire := Art.part(self, Art.cone(0.5), rock, Vector3(side * (26.0 + _rng.randf_range(0.0, 4.0)), h * 0.5 - 2.0, z),
					Vector3(w, h, w), Vector3(0.0, _rng.randf() * TAU, side * 0.08))
			side_spire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # long streaks over the plaza
	# A distant burning sky band (so the top of the frame isn't flat black).
	var sky := Art.part(self, Art.box(), Art.glow(Color(0.55, 0.08, 0.03), 0.9, false), Vector3(0.0, 8.0, -40.0),
			Vector3(140.0, 30.0, 0.5))
	sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Invisible walls around the plateau edge.
func _build_bounds() -> void:
	var t := 1.0
	_wall(Vector3((X0 + X1) * 0.5, 1.0, Z0 - t * 0.5), Vector3(X1 - X0 + 2.0 * t, 2.0, t))
	_wall(Vector3((X0 + X1) * 0.5, 1.0, Z1 + t * 0.5), Vector3(X1 - X0 + 2.0 * t, 2.0, t))
	_wall(Vector3(X0 - t * 0.5, 1.0, (Z0 + Z1) * 0.5), Vector3(t, 2.0, Z1 - Z0))
	_wall(Vector3(X1 + t * 0.5, 1.0, (Z0 + Z1) * 0.5), Vector3(t, 2.0, Z1 - Z0))


func _wall(center: Vector3, size: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	sb.add_child(cs)
	sb.position = center
	add_child(sb)
	return sb


## Round solid obstacle (props, pillars).
func _post(at: Vector3, radius: float) -> void:
	obstacles.append([at, radius])
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 2.0
	cs.shape = cyl
	cs.position.y = 1.0
	sb.add_child(cs)
	sb.position = at
	add_child(sb)


# ---------------------------------------------------------------- set pieces

func _build_bonfire() -> void:
	# Ring of skull-capped stones around a pit of hellfire: the heart of the camp.
	var ring := Art.mat(Color(0.16, 0.13, 0.12), 0.9, 0.0, 0.6, false, 0.0, &"stone")
	var bone := Art.mat(Art.BONE, 0.7, 0.0, 0.5, false, 0.0, &"bone")
	for k in 10:
		var a := TAU * k / 10.0
		var p := FIRE + Vector3(cos(a), 0.0, sin(a)) * 1.25
		Art.part(self, Art.box(), ring, p + Vector3(0.0, 0.2, 0.0), Vector3(0.5, 0.45, 0.4), Vector3(0.0, -a, 0.0))
		if k % 2 == 0:
			Art.part(self, Art.sphere(), bone, p + Vector3(0.0, 0.52, 0.0), Vector3(0.24, 0.22, 0.26))
	var coals := Art.part(self, Art.cylinder(0.5, 0.5), Art.glow(Art.HELLFIRE, 1.6, false), FIRE + Vector3(0.0, 0.06, 0.0),
			Vector3(2.0, 0.1, 2.0))
	coals.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fire(FIRE + Vector3(0.0, 0.1, 0.0), 0.7, 2.0)
	var l := Art.light(self, Color(1.0, 0.45, 0.15), 4.5, 12.0, FIRE + Vector3(0.0, 2.0, 0.0), true)
	l.light_volumetric_fog_energy = 1.5
	_flicker_light(l)
	_post(FIRE, 1.5)


## Particle flames + embers rising from `at`.
func _fire(at: Vector3, radius: float, height: float) -> void:
	var tongue := CylinderMesh.new()
	tongue.top_radius = 0.0
	tongue.bottom_radius = 0.14
	tongue.height = 0.8
	tongue.radial_segments = 6
	tongue.rings = 1
	var flames := InfernalFx.make_particles(Art.HELLFIRE, 40, 0.8, 2.8)
	flames.mesh = tongue
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flames.emission_sphere_radius = radius
	flames.direction = Vector3.UP
	flames.spread = 12.0
	flames.initial_velocity_min = height * 0.5
	flames.initial_velocity_max = height
	flames.gravity = Vector3(0.0, 1.0, 0.0)
	flames.scale_amount_curve = InfernalFx.swell_curve()
	flames.scale_amount_min = 1.0
	flames.scale_amount_max = 2.0
	flames.position = at
	add_child(flames)
	InfernalFx.embers(self, Art.EMBER, 24, 3.0, radius, at + Vector3(0.0, 0.5, 0.0), 3.0)


func _build_gate() -> void:
	var stone := Art.mat(Color(0.2, 0.15, 0.14), 0.85, 0.0, 0.55, false, 0.0, &"stone")
	var iron := Art.mat(Art.OBSIDIAN, 0.4, 0.8, 0.4, false, 0.0, &"metal")
	var bone := Art.mat(Art.BONE.darkened(0.1), 0.7, 0.0, 0.5, false, 0.0, &"bone")
	var g := Art.pivot(self, GATE)
	# Dais: three widening steps.
	for i in 3:
		var w := 9.0 - i * 1.6
		Art.part(g, Art.box(), stone, Vector3(0.0, 0.12 + i * 0.22, -0.4 - i * 0.3), Vector3(w, 0.24, 4.0 - i * 0.7))
	var base_y := 0.66
	# Twin tapered pillars, horned capitals, a spiked lintel.
	for s: float in [-1.0, 1.0]:
		var px := s * 2.2
		Art.part(g, Art.box(), stone, Vector3(px, base_y + 0.3, -0.6), Vector3(1.4, 0.6, 1.4))
		Art.part(g, Art.cylinder(0.42, 0.55), stone, Vector3(px, base_y + 3.0, -0.6), Vector3(1.0, 5.0, 1.0))
		for k in 3:
			Art.part(g, Art.torus(0.45, 0.6), iron, Vector3(px, base_y + 1.2 + k * 1.5, -0.6), Vector3(1.0, 0.6, 1.0))
		Art.part(g, Art.cone(0.5), bone, Vector3(px + s * 0.5, base_y + 6.3, -0.6), Vector3(0.45, 1.8, 0.45),
				Vector3(0.0, 0.0, -s * 0.7))
		_post(GATE + Vector3(px, 0.0, -0.6), 0.75)
		# Hellfire braziers flanking the steps.
		var br := Props.brazier(_rng)
		br.position = GATE + Vector3(s * 4.6, 0.0, 1.2)
		add_child(br)
		_post(br.position, 0.5)
	Art.part(g, Art.box(), stone, Vector3(0.0, base_y + 5.7, -0.6), Vector3(6.0, 0.9, 1.3))
	for k in 7:
		var x := lerpf(-2.7, 2.7, k / 6.0)
		var h := 0.6 + (1.0 - absf(x) / 2.7) * 0.9
		Art.part(g, Art.cone(0.5), iron, Vector3(x, base_y + 6.15 + h * 0.5, -0.6), Vector3(0.22, h, 0.22))
	# A great skull keystone with burning eyes.
	Art.part(g, Art.sphere(), bone, Vector3(0.0, base_y + 5.75, -0.05), Vector3(0.9, 0.8, 0.6))
	for s: float in [-1.0, 1.0]:
		Art.part(g, Art.sphere(), Art.glow(Art.HELLFIRE, 3.0), Vector3(s * 0.2, base_y + 5.8, 0.24), Vector3(0.18, 0.12, 0.08))
	# The swirling portal surface.
	var quad := QuadMesh.new()
	quad.size = Vector2(3.4, 5.0)
	var sm := ShaderMaterial.new()
	sm.shader = PORTAL_SHADER
	gate_surface = MeshInstance3D.new()
	gate_surface.mesh = quad
	gate_surface.material_override = sm
	gate_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gate_surface.position = Vector3(0.0, base_y + 2.6, -0.6)
	g.add_child(gate_surface)
	Sfx.play_loop(&"amb_portal", gate_surface, -6.0, Sfx.SFX_BUS, 5.0)  # portal hum (sfx.md)
	var swirl := InfernalFx.make_particles(Art.EMBER, 40, 1.6, 3.0)
	swirl.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	swirl.emission_box_extents = Vector3(1.5, 2.3, 0.1)
	swirl.direction = Vector3(0.0, 0.3, 1.0)
	swirl.spread = 40.0
	swirl.initial_velocity_min = 0.4
	swirl.initial_velocity_max = 1.4
	swirl.gravity = Vector3(0.0, 0.6, 0.0)
	swirl.position = Vector3(0.0, base_y + 2.6, -0.4)
	g.add_child(swirl)
	gate_light = Art.light(g, Color(1.0, 0.42, 0.14), 2.6, 9.0, Vector3(0.0, base_y + 3.4, 2.2))
	gate_light.light_volumetric_fog_energy = 2.0
	_flicker_light(gate_light)
	# Invisible blocker for the dais back so you can't walk behind the gate.
	_wall(GATE + Vector3(0.0, 1.0, -1.6), Vector3(9.0, 2.0, 1.5))


func _build_forge() -> void:
	var root := Art.pivot(self, SMITH + Vector3(-2.4, 0.0, -1.2))
	var brick := Art.mat(Color(0.18, 0.1, 0.08), 0.9, 0.0, 0.6, false, 0.0, &"stone")
	var iron := Art.mat(Art.OBSIDIAN, 0.35, 0.9, 0.4, false, 0.0, &"metal")
	# Forge hearth with a molten mouth and a chimney.
	Art.part(root, Art.box(), brick, Vector3(0.0, 0.7, 0.0), Vector3(2.2, 1.4, 1.8))
	Art.part(root, Art.box(), brick, Vector3(0.0, 2.6, -0.2), Vector3(1.2, 2.6, 1.0))
	Art.part(root, Art.cylinder(0.3, 0.45), iron, Vector3(0.0, 4.4, -0.2), Vector3(1.6, 1.0, 1.6))
	var mouth := Art.part(root, Art.box(), Art.glow(Art.HELLFIRE, 2.2, false), Vector3(0.0, 0.85, 0.82), Vector3(1.2, 0.6, 0.2))
	mouth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var top := Art.part(root, Art.box(), Art.glow(Art.EMBER, 1.6, false), Vector3(0.0, 1.42, 0.3), Vector3(1.7, 0.06, 0.9))
	top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	InfernalFx.embers(root, Art.EMBER, 20, 2.5, 0.5, Vector3(0.0, 1.6, 0.3), 3.0)
	var smoke := InfernalFx.embers(root, Art.EMBER, 12, 3.5, 0.3, Vector3(0.0, 4.9, -0.2), 1.5)
	smoke.gravity = Vector3(0.0, 1.5, 0.0)
	var l := Art.light(root, Color(1.0, 0.42, 0.12), 3.5, 8.0, Vector3(0.0, 1.8, 1.4), true)
	_flicker_light(l)
	_post(root.position + Vector3(0.0, 0.0, -0.1), 1.4)
	# Anvil on a stump, in front of the smith.
	var anvil := Art.pivot(self, SMITH + Vector3(1.4, 0.0, 0.2), Vector3(0.0, 0.4, 0.0))
	Art.part(anvil, Art.cylinder(0.35, 0.4), Art.mat(Color(0.2, 0.14, 0.1), 0.9, 0.0, 0.5, false, 0.0, &"wood"),
			Vector3(0.0, 0.3, 0.0), Vector3(1.0, 0.6, 1.0))
	Art.part(anvil, Art.box(), iron, Vector3(0.0, 0.72, 0.0), Vector3(0.9, 0.24, 0.36))
	Art.part(anvil, Art.cone(0.5), iron, Vector3(0.6, 0.76, 0.0), Vector3(0.18, 0.4, 0.18), Vector3(0.0, 0.0, -PI * 0.5))
	Art.part(anvil, Art.box(), Art.glow(Art.HELLFIRE, 2.0, false), Vector3(-0.1, 0.86, 0.0), Vector3(0.5, 0.04, 0.08))
	_post(anvil.position, 0.5)
	# Weapon rack of demon blades behind the smith.
	var rack := Art.pivot(self, SMITH + Vector3(-1.5, 0.0, 2.6), Vector3(0.0, 0.3, 0.0))
	var wood := Art.mat(Color(0.18, 0.12, 0.08), 0.85, 0.0, 0.5, false, 0.0, &"wood")
	Art.part(rack, Art.box(), wood, Vector3(0.0, 1.4, 0.0), Vector3(2.2, 0.12, 0.12))
	Art.part(rack, Art.box(), wood, Vector3(0.0, 0.3, 0.0), Vector3(2.2, 0.12, 0.3))
	for s: float in [-1.0, 1.0]:
		Art.part(rack, Art.box(), wood, Vector3(s * 1.05, 0.8, 0.0), Vector3(0.12, 1.6, 0.12))
	var steel := Art.mat(Art.STEEL.darkened(0.2), 0.3, 0.9, 0.3, false, 0.0, &"metal")
	for k in 4:
		var x := -0.75 + k * 0.5
		Art.part(rack, Art.box(), steel, Vector3(x, 0.95, 0.06), Vector3(0.09, 1.25, 0.02), Vector3(0.0, 0.0, 0.08))
		Art.part(rack, Art.box(), iron, Vector3(x - 0.04, 1.62, 0.06), Vector3(0.3, 0.05, 0.05))
	_post(rack.position, 1.0)


func _build_ritual_corner() -> void:
	var root := Art.pivot(self, OCCULT)
	# Small violet summoning glyph under the occultist.
	var sm := ShaderMaterial.new()
	sm.shader = SIGIL_SHADER
	sm.set_shader_parameter(&"fire", Vector3(1.4, 0.4, 2.4))
	sm.set_shader_parameter(&"hot", Vector3(2.4, 1.2, 3.6))
	sm.set_shader_parameter(&"smoulder", Vector3(0.12, 0.02, 0.2))
	sm.set_shader_parameter(&"intensity", 0.6)
	sm.set_shader_parameter(&"spin", -0.02)
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	plane.material = sm
	var glyph := MeshInstance3D.new()
	glyph.mesh = plane
	glyph.position = Vector3(0.0, 0.04, 0.0)
	glyph.scale = Vector3(1.8, 1.0, 1.8)
	glyph.set_instance_shader_parameter(&"radius", 1.8)
	glyph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glyph)
	# Bookshelves of forbidden texts and candle clusters.
	var wood := Art.mat(Color(0.12, 0.07, 0.07), 0.85, 0.0, 0.5, false, 0.0, &"wood")
	var shelf := Art.pivot(self, OCCULT + Vector3(2.4, 0.0, -1.0), Vector3(0.0, -1.2, 0.0))
	Art.part(shelf, Art.box(), wood, Vector3(0.0, 1.3, 0.0), Vector3(1.8, 2.6, 0.5))
	var colors: Array[Color] = [Color(0.3, 0.05, 0.08), Color(0.12, 0.05, 0.2), Color(0.25, 0.2, 0.1), Color(0.08, 0.12, 0.1)]
	for row in 4:
		for k in 7:
			var c := colors[_rng.randi() % colors.size()]
			var h := _rng.randf_range(0.32, 0.46)
			Art.part(shelf, Art.box(), Art.mat(c, 0.8, 0.0, 0.4, false, 0.0, &"leather"),
					Vector3(-0.72 + k * 0.24, 0.3 + row * 0.6 + h * 0.5 - 0.2, 0.22), Vector3(0.18, h, 0.12))
	_post(shelf.position, 1.0)
	for p: Vector3 in [Vector3(-1.6, 0.0, 1.2), Vector3(1.8, 0.0, 1.0), Vector3(-1.2, 0.0, -1.6)]:
		var c := Props.candles(_rng)
		c.position = OCCULT + p
		add_child(c)
	var l := Art.light(self, Color(0.65, 0.3, 1.0), 2.4, 7.0, OCCULT + Vector3(0.0, 2.2, 1.0))
	_flicker_light(l)


func _build_broker_desk() -> void:
	var root := Art.pivot(self, BROKER + Vector3(0.9, 0.0, -0.9), Vector3(0.0, -PI * 0.25, 0.0))
	var wood := Art.mat(Color(0.16, 0.06, 0.05), 0.6, 0.0, 0.4, false, 0.15, &"wood")
	var gold := Art.mat(Art.GOLD, 0.3, 1.0, 0.3, false, 0.0, &"gold")
	# Counting desk with a gilded edge, an open ledger and a balance scale.
	Art.part(root, Art.box(), wood, Vector3(0.0, 0.5, 0.0), Vector3(2.4, 1.0, 0.9))
	Art.part(root, Art.box(), gold, Vector3(0.0, 1.02, 0.0), Vector3(2.5, 0.05, 1.0))
	Art.part(root, Art.box(), Art.mat(Art.IVORY.darkened(0.1), 0.9, 0.0, 0.3, false, 0.0, &"parchment"),
			Vector3(-0.5, 1.07, 0.05), Vector3(0.7, 0.04, 0.5), Vector3(0.0, 0.2, 0.0))
	Art.part(root, Art.cylinder(0.03, 0.05), gold, Vector3(0.6, 1.45, 0.0), Vector3(1.0, 0.8, 1.0))
	Art.part(root, Art.box(), gold, Vector3(0.6, 1.85, 0.0), Vector3(0.9, 0.04, 0.04))
	for s: float in [-1.0, 1.0]:
		Art.part(root, Art.cylinder(0.5, 0.3), gold, Vector3(0.6 + s * 0.42, 1.6, 0.0), Vector3(0.3, 0.06, 0.3))
		Art.part(root, Art.sphere(), Art.glow(UIPalette.SOUL, 2.0), Vector3(0.6 + s * 0.42, 1.68, 0.0), Vector3.ONE * 0.12)
	# Jars of bottled souls on and around the desk.
	var glass := Art.glow(UIPalette.SOUL, 1.2, true, 0.5)
	for p: Vector3 in [Vector3(-1.6, 0.0, 0.3), Vector3(-1.9, 0.0, -0.3), Vector3(1.6, 0.0, 0.4), Vector3(-1.0, 1.05, -0.25)]:
		var h := 0.5 if p.y > 0.0 else _rng.randf_range(0.7, 1.1)
		Art.part(root, Art.cylinder(0.5, 0.5), glass, p + Vector3(0.0, h * 0.5, 0.0), Vector3(0.36, h, 0.36))
		Art.part(root, Art.sphere(), Art.glow(UIPalette.SOUL, 3.0), p + Vector3(0.0, h * 0.5, 0.0), Vector3.ONE * 0.16)
		Art.part(root, Art.cylinder(0.5, 0.5), gold, p + Vector3(0.0, h + 0.03, 0.0), Vector3(0.38, 0.06, 0.38))
	var l := Art.light(root, UIPalette.SOUL, 1.8, 6.0, Vector3(0.0, 2.0, 0.6))
	_flicker_light(l)
	_post(root.position, 1.3)
	var w := Art.pivot(self, BROKER + Vector3(-1.5, 0.0, -1.2))
	var wisps := InfernalFx.embers(w, UIPalette.SOUL, 10, 3.0, 0.6, Vector3(0.0, 0.8, 0.0), 2.5)
	wisps.gravity = Vector3(0.0, 0.4, 0.0)


func _build_map_table() -> void:
	var root := Art.pivot(self, CARTO + Vector3(1.6, 0.0, 0.6), Vector3(0.0, 0.5, 0.0))
	var wood := Art.mat(Color(0.2, 0.13, 0.08), 0.8, 0.0, 0.5, false, 0.0, &"wood")
	Art.part(root, Art.box(), wood, Vector3(0.0, 0.9, 0.0), Vector3(1.8, 0.1, 1.2))
	for sx: float in [-0.75, 0.75]:
		for sz: float in [-0.5, 0.5]:
			Art.part(root, Art.box(), wood, Vector3(sx, 0.45, sz), Vector3(0.1, 0.9, 0.1))
	# The map itself glows faintly with the roads into Heaven.
	Art.part(root, Art.box(), Art.mat(Color(0.55, 0.45, 0.32), 0.9, 0.0, 0.4, false, 0.0, &"parchment"),
			Vector3(0.0, 0.96, 0.0), Vector3(1.5, 0.02, 1.0), Vector3(0.0, 0.08, 0.0))
	for k in 5:
		var a := Vector3(_rng.randf_range(-0.6, 0.6), 0.98, _rng.randf_range(-0.4, 0.4))
		var b := Vector3(_rng.randf_range(-0.6, 0.6), 0.98, _rng.randf_range(-0.4, 0.4))
		InfernalFx.segment(root, a, b, 0.02, Art.glow(Color(0.35, 0.95, 0.9), 1.6))
	Art.part(root, Art.sphere(), Art.glow(Art.HELLFIRE, 3.0), Vector3(0.3, 1.0, -0.2), Vector3.ONE * 0.08)
	_post(root.position, 1.0)


func _build_circle() -> void:
	var sm := ShaderMaterial.new()
	sm.shader = SIGIL_SHADER
	sm.set_shader_parameter(&"intensity", 0.7)
	sm.set_shader_parameter(&"spin", 0.015)
	sm.set_shader_parameter(&"rune_count", 14.0)
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	plane.material = sm
	var circle := MeshInstance3D.new()
	circle.mesh = plane
	circle.position = CIRCLE + Vector3(0.0, 0.05, 0.0)
	circle.scale = Vector3(1.9, 1.0, 1.9)
	circle.set_instance_shader_parameter(&"radius", 1.9)
	circle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(circle)
	for k in 8:
		var a := TAU * k / 8.0
		var c := Props.candles(_rng, 3)
		c.position = CIRCLE + Vector3(cos(a), 0.0, sin(a)) * 2.25
		add_child(c)
	var l := Art.light(self, Art.HELLFIRE, 1.5, 5.0, CIRCLE + Vector3(0.0, 0.6, 0.0))
	_flicker_light(l)


## The Covenant: a lectern with a burning contract beside the soul broker, for Progression's heat
## pacts (harder runs, richer rewards).
func _build_covenant() -> void:
	var root := Art.pivot(self, COVENANT, Vector3(0.0, 0.3, 0.0))
	var stone := Art.mat(Color(0.14, 0.09, 0.08), 0.85, 0.0, 0.5, false, 0.0, &"stone")
	var gold := Art.mat(Art.GOLD, 0.3, 1.0, 0.3, false, 0.0, &"gold")
	Art.part(root, Art.cylinder(0.25, 0.4), stone, Vector3(0.0, 0.55, 0.0), Vector3(1.0, 1.1, 1.0))
	Art.part(root, Art.box(), stone, Vector3(0.0, 1.15, 0.0), Vector3(0.9, 0.12, 0.6), Vector3(0.45, 0.0, 0.0))
	Art.part(root, Art.box(), Art.mat(Color(0.62, 0.5, 0.36), 0.9, 0.0, 0.4, false, 0.0, &"parchment"),
			Vector3(0.0, 1.23, 0.0), Vector3(0.7, 0.02, 0.5), Vector3(0.45, 0.0, 0.0))
	# Bloody seal and a quill of bone.
	Art.part(root, Art.sphere(), Art.glow(Art.CRIMSON, 2.2), Vector3(0.18, 1.22, 0.12), Vector3(0.12, 0.04, 0.12))
	Art.part(root, Art.cylinder(0.01, 0.02), gold, Vector3(-0.2, 1.4, 0.0), Vector3(1.0, 0.5, 1.0), Vector3(0.0, 0.0, 0.5))
	var flames := InfernalFx.embers(root, Art.HELLFIRE, 10, 1.2, 0.25, Vector3(0.0, 1.3, 0.0), 2.5)
	flames.gravity = Vector3(0.0, 1.2, 0.0)
	_flicker_light(Art.light(root, Color(1.0, 0.25, 0.1), 1.2, 4.0, Vector3(0.0, 1.8, 0.4)))
	_post(COVENANT, 0.5)


func _build_decor() -> void:
	# Fallen holy things as trophies, banners, bones and gibbets around the edge of the camp.
	var spots := [
		[&"statue_angel", Vector3(-13.0, 0.0, -10.0)], [&"statue_angel", Vector3(13.0, 0.0, -10.0)],
		[&"banner", Vector3(-4.2, 0.0, -7.6)], [&"banner", Vector3(4.2, 0.0, -7.2)],
		[&"gibbet", Vector3(-14.2, 0.0, 7.6)], [&"gibbet", Vector3(13.5, 0.0, 9.5)],
		[&"bone_pile", Vector3(-7.0, 0.0, 10.2)], [&"bone_pile", Vector3(14.0, 0.0, 6.0)],
		[&"bone_pile", Vector3(-13.0, 0.0, 9.0)], [&"skull", Vector3(3.0, 0.0, 8.5)],
		[&"skull", Vector3(-3.4, 0.0, -3.0)], [&"broken_column", Vector3(-12.5, 0.0, -6.0)],
		[&"broken_column", Vector3(12.5, 0.0, -6.5)], [&"chains", Vector3(0.0, 0.0, 10.4)],
		[&"brazier", Vector3(-4.0, 0.0, 3.5)], [&"brazier", Vector3(4.0, 0.0, 3.5)],
		[&"candles", Vector3(-2.0, 0.0, -5.0)], [&"candles", Vector3(2.4, 0.0, -5.6)],
	]
	for s: Array in spots:
		var p: Node3D = Props.build(s[0], _rng)
		p.position = s[1]
		add_child(p)
		if s[0] in [&"statue_angel", &"gibbet", &"broken_column", &"brazier", &"banner"]:
			_post(s[1], 0.7)
	# Scattered rubble on the edges.
	for k in 24:
		var p := Vector3(_rng.randf_range(X0, X1), 0.0, _rng.randf_range(Z0, Z1))
		if absf(p.x) < 12.0 and absf(p.z) < 9.0:
			continue  # keep the plaza clear
		var r := Props.build(&"rubble", _rng)
		r.position = p
		add_child(r)


func _build_ambience() -> void:
	# Near-brazier crackle as a 2D bed (plain Node parent). play_loop waits for the stream if the
	# hub loads before synthesis finishes (docs/team/sfx.md).
	var holder := Node.new()
	holder.name = &"FireBed"
	add_child(holder)
	Sfx.play_loop(&"amb_fire", holder, -8.0, Sfx.AMB_BUS)


func _flicker_light(l: OmniLight3D) -> void:
	_flicker.append(l)
	_flicker_base.append(l.light_energy)



# ---------------------------------------------------------------- for other hub builders

## Round static collider (props other hub scripts place).
func add_post(at: Vector3, radius: float) -> void:
	_post(at, radius)


## Registers a light for the shared firelight flicker.
func add_flicker(l: OmniLight3D) -> void:
	_flicker_light(l)
