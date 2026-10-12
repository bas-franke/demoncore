class_name AtmoLayers
extends RefCounted
## Builds the Atmosphere rig's weather layers: one GPUParticles3D per kind, emitting in world space
## inside a box that the rig keeps centred on the player (see AtmoRig._follow_layers).
##
##   var p := AtmoLayers.build(&"snow", amount)     # node named "Snow", not emitting yet
##   AtmoLayers.base_amount(&"snow")                 # particle count at High / density 1.0
##
## Kinds: ash, embers, feathers, snow, rain, splash, rays, wisps. All are lazily built by the rig the
## first time a preset turns them on, so maps that never rain never pay for rain.

const ASH_SHADER := preload("res://shaders/ash.gdshader")
const MOTE_SHADER := preload("res://shaders/mote.gdshader")
const RAIN_SHADER := preload("res://shaders/rain.gdshader")
const SPLASH_SHADER := preload("res://shaders/rain_splash.gdshader")
const RAY_SHADER := preload("res://shaders/atmo/holy_ray.gdshader")
const FEATHER_SHADER := preload("res://shaders/atmo/feather.gdshader")
const SNOW_SHADER := preload("res://shaders/atmo/snow.gdshader")
const WISP_SHADER := preload("res://shaders/atmo/wisp.gdshader")

const KINDS: Array[StringName] = [&"ash", &"embers", &"feathers", &"snow", &"rain", &"splash", &"rays", &"wisps"]

## Particle counts at density 1.0 (Settings.particle_density scales them).
const BASE_AMOUNT := {
	&"ash": 520, &"embers": 160, &"feathers": 110, &"snow": 1500, &"rain": 1800, &"splash": 170,
	&"rays": 9, &"wisps": 22,
}
## Emitter offset from the focus point (the player). Spawn boxes sit up-wind/above so the visible
## area around the player is covered once the particles have drifted.
const OFFSET := {
	&"ash": Vector3(-3.0, 4.5, -2.0), &"embers": Vector3(-2.0, 0.2, -1.0),
	&"feathers": Vector3(-2.0, 8.5, -3.0), &"snow": Vector3(-1.5, 12.0, -2.0),
	&"rain": Vector3.ZERO, &"splash": Vector3(0.0, 0.035, 1.5),
	&"rays": Vector3(0.0, 0.0, -2.0), &"wisps": Vector3(-4.0, 5.5, -3.0),
}


static func base_amount(kind: StringName) -> int:
	return int(BASE_AMOUNT.get(kind, 100))


static func offset(kind: StringName) -> Vector3:
	return OFFSET.get(kind, Vector3.ZERO)


## A new, non-emitting layer of `kind` with `amount` particles. Its draw-pass material is the
## mesh's surface material (AtmoLayers.material_of(p) returns it).
static func build(kind: StringName, amount: int) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = String(kind).capitalize().replace(" ", "")
	p.amount = maxi(amount, 1)
	p.local_coords = false
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	p.process_material = pm
	match kind:
		&"ash": _ash(p, pm)
		&"embers": _embers(p, pm)
		&"feathers": _feathers(p, pm)
		&"snow": _snow(p, pm)
		&"rain": _rain(p, pm)
		&"splash": _splash(p, pm)
		&"rays": _rays(p, pm)
		&"wisps": _wisps(p, pm)
		_:
			push_warning("AtmoLayers: unknown layer kind %s" % kind)
	return p


static func material_of(p: GPUParticles3D) -> ShaderMaterial:
	if p and p.draw_pass_1:
		return p.draw_pass_1.surface_get_material(0) as ShaderMaterial
	return null


# ---------------------------------------------------------------- kinds

static func _quad(p: GPUParticles3D, size: Vector2, shader: Shader) -> ShaderMaterial:
	var quad := QuadMesh.new()
	quad.size = size
	var mat := ShaderMaterial.new()
	mat.shader = shader
	quad.material = mat
	p.draw_pass_1 = quad
	return mat


## Alpha ramp: transparent at birth and death, `peak` in between.
static func _fade_ramp(a_in: float, a_out: float, peak: float = 1.0) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(a_in, Color(1, 1, 1, peak))
	g.add_point(a_out, Color(1, 1, 1, peak))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt


## Scale curve that grows in and shrinks out (for alpha-scissored particles that can't fade).
static func _grow_shrink() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.0))
	c.add_point(Vector2(0.06, 1.0))
	c.add_point(Vector2(0.9, 1.0))
	c.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = c
	return ct


static func _ash(p: GPUParticles3D, pm: ParticleProcessMaterial) -> void:
	p.lifetime = 12.0
	p.preprocess = 12.0
	p.fixed_fps = 30
	p.visibility_aabb = AABB(Vector3(-30, -12, -24), Vector3(60, 24, 48))
	pm.emission_box_extents = Vector3(24.0, 4.0, 18.0)
	pm.direction = Vector3(1.0, -0.3, 0.3)
	pm.spread = 40.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3(0.25, -0.32, 0.1)
	pm.damping_min = 0.2
	pm.damping_max = 0.4
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.2
	pm.turbulence_noise_scale = 5.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.14
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -90.0
	pm.angular_velocity_max = 90.0
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	pm.color_ramp = _fade_ramp(0.15, 0.75)
	pm.particle_flag_rotate_y = true
	_quad(p, Vector2(0.09, 0.09), ASH_SHADER)


static func _embers(p: GPUParticles3D, pm: ParticleProcessMaterial) -> void:
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.fixed_fps = 30
	p.visibility_aabb = AABB(Vector3(-30, -4, -24), Vector3(60, 16, 48))
	pm.emission_box_extents = Vector3(22.0, 0.3, 16.0)
	pm.direction = Vector3(0.3, 1.0, 0.1)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0.3, 0.35, 0.1)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 2.0
	pm.turbulence_noise_scale = 2.5
	pm.turbulence_noise_speed_random = 0.6
	pm.turbulence_influence_min = 0.1
	pm.turbulence_influence_max = 0.25
	pm.scale_min = 0.4
	pm.scale_max = 1.2
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.9, 0.6, 0.0))
	g.set_color(1, Color(0.6, 0.1, 0.02, 0.0))
	g.add_point(0.1, Color(1.0, 0.8, 0.5, 1.0))
	g.add_point(0.6, Color(1.0, 0.45, 0.15, 0.85))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	_quad(p, Vector2(0.075, 0.075), MOTE_SHADER)


static func _feathers(p: GPUParticles3D, pm: ParticleProcessMaterial) -> void:
	# ~8.5 m of fall over a 14 s life (v0 * t + g * t^2 / 2), so feathers land as they shrink out.
	p.lifetime = 14.0
	p.preprocess = 14.0
	p.fixed_fps = 30
	p.visibility_aabb = AABB(Vector3(-32, -12, -26), Vector3(64, 16, 52))
	pm.emission_box_extents = Vector3(24.0, 1.0, 18.0)
	pm.direction = Vector3(0.3, -1.0, 0.1)
	pm.spread = 30.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.55
	pm.gravity = Vector3(0.1, -0.05, 0.04)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.4
	pm.turbulence_noise_scale = 6.0
	pm.turbulence_influence_min = 0.06
	pm.turbulence_influence_max = 0.16
	pm.scale_min = 0.7
	pm.scale_max = 1.25
	pm.scale_curve = _grow_shrink()
	_quad(p, Vector2(0.2, 0.4), FEATHER_SHADER)


static func _snow(p: GPUParticles3D, pm: ParticleProcessMaterial) -> void:
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.fixed_fps = 30
	p.visibility_aabb = AABB(Vector3(-32, -16, -26), Vector3(64, 20, 52))
	pm.emission_box_extents = Vector3(26.0, 1.0, 20.0)
	pm.direction = Vector3(0.1, -1.0, 0.05)
	pm.spread = 15.0
	# Steady ~1.35 m/s fall: from the 12 m emitter to the ground in about one lifetime.
	pm.initial_velocity_min = 1.1
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0.15, 0.0, 0.05)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.0
	pm.turbulence_noise_scale = 4.0
	pm.turbulence_influence_min = 0.04
	pm.turbulence_influence_max = 0.12
	pm.scale_min = 0.55
	pm.scale_max = 1.5
	pm.color_ramp = _fade_ramp(0.06, 0.85)
	_quad(p, Vector2(0.1, 0.1), SNOW_SHADER)


static func _rain(p: GPUParticles3D, pm: ParticleProcessMaterial) -> void:
	p.lifetime = 0.62
	p.preprocess = 0.62
	p.visibility_aabb = AABB(Vector3(-30, -16, -26), Vector3(60, 22, 52))
	pm.emission_box_extents = Vector3(23.0, 0.6, 18.0)
	pm.direction = Vector3(0.08, -1.0, 0.04)
	pm.spread = 1.5
	pm.initial_velocity_min = 22.0
	pm.initial_velocity_max = 26.0
	pm.gravity = Vector3.ZERO
	pm.color_ramp = _fade_ramp(0.08, 0.9)
	_quad(p, Vector2.ONE, RAIN_SHADER)


static func _splash(p: GPUParticles3D, pm: ParticleProcessMaterial) -> void:
	p.lifetime = 0.42
	p.visibility_aabb = AABB(Vector3(-24, -1, -20), Vector3(48, 2, 40))
	pm.emission_box_extents = Vector3(19.0, 0.0, 14.0)
	pm.direction = Vector3.UP
	pm.spread = 0.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.5
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.34, 0.34)
	var mat := ShaderMaterial.new()
	mat.shader = SPLASH_SHADER
	plane.material = mat
	p.draw_pass_1 = plane


static func _rays(p: GPUParticles3D, pm: ParticleProcessMaterial) -> void:
	p.lifetime = 14.0
	p.preprocess = 14.0
	p.fixed_fps = 15
	# The shader rebuilds each quad as a ~25 m shaft leaning toward the sun: generous AABB.
	p.visibility_aabb = AABB(Vector3(-45, -4, -45), Vector3(90, 40, 90))
	pm.emission_box_extents = Vector3(19.0, 0.0, 13.0)
	pm.direction = Vector3(1, 0, 0)
	pm.spread = 180.0
	pm.flatness = 1.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.25
	pm.gravity = Vector3.ZERO
	pm.color_ramp = _fade_ramp(0.3, 0.7)
	_quad(p, Vector2.ONE, RAY_SHADER)


static func _wisps(p: GPUParticles3D, pm: ParticleProcessMaterial) -> void:
	p.lifetime = 36.0
	p.preprocess = 36.0
	p.fixed_fps = 15
	p.visibility_aabb = AABB(Vector3(-50, -8, -40), Vector3(100, 20, 80))
	pm.emission_box_extents = Vector3(30.0, 1.5, 22.0)
	pm.direction = Vector3(1.0, 0.0, 0.4)
	pm.spread = 10.0
	pm.flatness = 1.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.1
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.7
	pm.scale_max = 1.6
	pm.color_ramp = _fade_ramp(0.2, 0.75)
	_quad(p, Vector2(6.0, 6.0), WISP_SHADER)
