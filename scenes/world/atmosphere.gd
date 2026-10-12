extends Node3D
## Dark-fantasy atmosphere around the player (purely visual):
##   - holy light shafts from the heavens: additive quads aligned with the sun, slowly drifting and
##     breathing in and out (plus Godot's volumetric fog god-rays from the sun itself)
##   - falling ash flakes and rising embers (GPUParticles3D following the player)
##   - low ground mist: two soft, depth-faded world-space mist sheets that follow the player
##   - full-screen post pass (gold/teal grade, vignette, grain) on a CanvasLayer below the UI
##   - feeds the player position to the decor occluder fade (lit_static + legacy Toon materials)

const SUNBEAM_SHADER := preload("res://shaders/sunbeam.gdshader")
const MOTE_SHADER := preload("res://shaders/mote.gdshader")
const ASH_SHADER := preload("res://shaders/ash.gdshader")
const MIST_SHADER := preload("res://shaders/ground_mist.gdshader")
const POST_SHADER := preload("res://shaders/post_fx.gdshader")

## The sun; shafts are aligned with its direction.
@export var sun: DirectionalLight3D
@export var beam_count: int = 7
@export var ash_count: int = 420
@export var ember_count: int = 90
@export var mist_enabled := true
## Post-process CanvasLayer layer (UI uses 1..20; must stay below it).
@export var post_layer: int = -1
@export var post_enabled := true
## Area (around the focus, X/Z half-extents) in which shafts appear.
@export var beam_area := Vector2(19.0, 13.0)
@export var wind := Vector3(0.45, 0.0, 0.18)

var _beams: Array[Dictionary] = []
var _beam_material: ShaderMaterial
var _ash: GPUParticles3D
var _embers: GPUParticles3D
var _mist: Array[MeshInstance3D] = []
var _rng := RandomNumberGenerator.new()
var _fade_mats: Array[ShaderMaterial] = []
var _fade_seen := -1


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rng.randomize()
	_beam_material = ShaderMaterial.new()
	_beam_material.shader = SUNBEAM_SHADER
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	for i in beam_count:
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = _beam_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.extra_cull_margin = 4.0
		mi.set_instance_shader_parameter(&"seed", _rng.randf() * 10.0)
		add_child(mi)
		var b := {"node": mi, "age": 0.0, "life": 1.0, "pos": Vector3.ZERO, "len": 10.0, "width": 2.0, "peak": 1.0}
		_respawn_beam(b)
		b["age"] = _rng.randf() * float(b["life"])  # desync initial beams
		_beams.append(b)
	_build_ash()
	_build_embers()
	if mist_enabled:
		_build_mist()
	if post_enabled:
		_build_post()


func _fade_ramp(peak: float = 1.0) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.15, Color(1, 1, 1, peak))
	g.add_point(0.75, Color(1, 1, 1, peak))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt


func _build_ash() -> void:
	_ash = GPUParticles3D.new()
	_ash.name = "Ash"
	_ash.amount = ash_count
	_ash.lifetime = 12.0
	_ash.preprocess = 12.0
	_ash.local_coords = false
	_ash.fixed_fps = 30
	_ash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ash.visibility_aabb = AABB(Vector3(-30, -12, -24), Vector3(60, 24, 48))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
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
	pm.color_ramp = _fade_ramp()
	pm.particle_flag_rotate_y = true
	_ash.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	var mat := ShaderMaterial.new()
	mat.shader = ASH_SHADER
	quad.material = mat
	_ash.draw_pass_1 = quad
	add_child(_ash)


func _build_embers() -> void:
	_embers = GPUParticles3D.new()
	_embers.name = "Embers"
	_embers.amount = ember_count
	_embers.lifetime = 6.0
	_embers.preprocess = 6.0
	_embers.local_coords = false
	_embers.fixed_fps = 30
	_embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_embers.visibility_aabb = AABB(Vector3(-30, -4, -24), Vector3(60, 16, 48))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
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
	_embers.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.075, 0.075)
	var mat := ShaderMaterial.new()
	mat.shader = MOTE_SHADER
	quad.material = mat
	_embers.draw_pass_1 = quad
	add_child(_embers)


func _build_mist() -> void:
	# two stacked, slightly offset mist sheets give the banks some thickness
	for i in 2:
		var mi := MeshInstance3D.new()
		mi.name = "GroundMist%d" % i
		var plane := PlaneMesh.new()
		plane.size = Vector2(70.0, 56.0)
		mi.mesh = plane
		var mat := ShaderMaterial.new()
		mat.shader = MIST_SHADER
		mat.set_shader_parameter(&"seed", float(i) * 1.7)
		mat.set_shader_parameter(&"opacity", 0.18 if i == 0 else 0.1)
		mat.set_shader_parameter(&"scale", 0.05 if i == 0 else 0.075)
		mat.set_shader_parameter(&"coverage", 0.5 if i == 0 else 0.56)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(mi)
		_mist.append(mi)


func _build_post() -> void:
	var layer := CanvasLayer.new()
	layer.layer = post_layer
	layer.name = "PostFX"
	add_child(layer)
	var rect := ColorRect.new()
	rect.name = "PostRect"
	# Game feel (res://scenes/world/game_feel.gd) finds the post material through this group and
	# drives its low_hp / heartbeat / hit_flash / chroma_pulse uniforms.
	rect.add_to_group(&"post_fx")
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = POST_SHADER
	rect.material = mat
	layer.add_child(rect)


func _process(delta: float) -> void:
	var focus := _focus()
	_update_fade(focus)
	_ash.global_position = focus + Vector3(-3.0, 4.5, -2.0)
	_embers.global_position = focus + Vector3(-2.0, 0.2, -1.0)
	for i in _mist.size():
		_mist[i].global_position = Vector3(focus.x, 0.35 + float(i) * 0.45, focus.z - 4.0)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var down := Vector3(0.6, -0.75, 0.3).normalized()
	if is_instance_valid(sun):
		down = -sun.global_transform.basis.z.normalized()
	var up := -down
	var cam_pos := cam.global_position
	for b in _beams:
		var age: float = float(b["age"]) + delta
		b["age"] = age
		var life: float = b["life"]
		if age >= life:
			_respawn_beam(b)
			age = 0.0
		var pos: Vector3 = b["pos"]
		pos += wind * delta * 0.5
		b["pos"] = pos
		var env := sin(PI * clampf(age / life, 0.0, 1.0))
		var length: float = b["len"]
		var width: float = b["width"]
		var center := pos + up * length * 0.5
		var x_axis := up.cross(cam_pos - center)
		if x_axis.length_squared() < 0.0001:
			continue
		x_axis = x_axis.normalized()
		var z_axis := x_axis.cross(up).normalized()
		var mi: MeshInstance3D = b["node"]
		mi.global_transform = Transform3D(Basis(x_axis * width, up * length, z_axis), center)
		mi.set_instance_shader_parameter(&"fade", env * env * float(b["peak"]))


## Occluder fade: every lit_static material (Art cache + props' own) and legacy Toon decor.
func _update_fade(focus: Vector3) -> void:
	Toon.set_fade_focus(focus)
	var count := Art._mats.size() + Props.material_count()
	if count != _fade_seen:
		_fade_seen = count
		_fade_mats.clear()
		for m: ShaderMaterial in Art._mats.values():
			if m.shader == Art.LIT_STATIC:
				_fade_mats.append(m)
		for m in Props.static_materials():
			if not _fade_mats.has(m):
				_fade_mats.append(m)
	for m in _fade_mats:
		m.set_shader_parameter(&"fade_focus", focus)


func _respawn_beam(b: Dictionary) -> void:
	var f := _focus()
	b["pos"] = f + Vector3(_rng.randf_range(-beam_area.x, beam_area.x), 0.0,
			_rng.randf_range(-beam_area.y, beam_area.y * 0.6))
	b["life"] = _rng.randf_range(9.0, 16.0)
	b["len"] = _rng.randf_range(16.0, 26.0)
	b["width"] = _rng.randf_range(1.2, 3.6)
	b["peak"] = _rng.randf_range(0.55, 1.0)
	b["age"] = 0.0


func _focus() -> Vector3:
	if is_instance_valid(Game.player):
		return Game.player.get_global_transform_interpolated().origin
	return Vector3.ZERO
