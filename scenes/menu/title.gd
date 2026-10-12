extends Node3D
## SINBOUND title screen. A slow cinematic drift over the ruined plain beneath the shattered
## Cathedral of Heaven: a colossal fallen angel kneels on the right, a pillar of golden light falls
## through the broken sky on the left, embers rise and ash drifts down, bells toll in the distance.
## The logo fades in, then "Press any key" pulses. Any key / click / pad button fades to black and
## opens the demon select. Meanwhile Warmup compiles every model / material pipeline offscreen
## (if the player is faster than the warm-up, the black veil simply holds until it is done).
##
## Vista models (tools/blender/models/title/*.py -> res://assets/models/title/*.glb):
##   ruined_plain.glb  - ground, ridges, ruins, sword field, ember fissures (title coordinates)
##   fallen_angel.glb  - the kneeling colossus (~34 m)
##   sky_cathedral.glb - floating cathedral fragments (nodes "frag_*" drift independently)

const NEXT_SCENE := "res://scenes/menu/demon_select.tscn"
const MODELS := "res://assets/models/title/"
const POST_SHADER := "res://shaders/post_fx.gdshader"
const MOTE_SHADER := "res://shaders/mote.gdshader"
const ASH_SHADER := "res://shaders/ash.gdshader"

const PILLAR := Vector3(-34.0, 0.0, -260.0)
const CATHEDRAL := Vector3(-44.0, 150.0, -305.0)
const STATUE := Vector3(30.0, 0.0, -52.0)
const SUN_TOWARD := Vector3(0.12, -0.36, 1.0)  # direction the sunlight travels (from behind the cathedral)

const GOLD := Color(1.0, 0.78, 0.44)
const PALE_GOLD := Color(1.0, 0.86, 0.62)

# Title-only shaders (shaders/title/*.gdshader; they used to be inline strings here).
const BEAM_SHADER := preload("res://shaders/title/beam.gdshader")
const POOL_SHADER := preload("res://shaders/title/pool.gdshader")
const MIST_SHADER := preload("res://shaders/title/mist.gdshader")
const SKY_SHADER := preload("res://shaders/title/sky.gdshader")

var _cam: Camera3D
var _t := 0.0
var _frags: Array = []  # [node, base_xform, phase, amp, axis]
var _beams: Array = []  # [MeshInstance3D, base fade, phase]
var _ui: Dictionary = {}
var _logo_font: FontVariation
var _prompt_font: FontVariation
var _leaving := false
## Descend / Settings / Quit column shown after the first key press (scenes/ui/main_menu.gd).
var _menu: MainMenu
var _warm_done := false
var _warm_started := false
var _next_bell := 3.2
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 1666
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_build_environment()
	_build_vista()
	_build_light()
	_build_particles()
	_build_ui()
	if has_node("/root/Sfx"):
		Sfx.play_music(&"menu")
	_update_camera(0.0)
	# Start compiling pipelines once the first frames are up (under the fade from black).
	get_tree().create_timer(0.3).timeout.connect(_start_warmup)


func _start_warmup() -> void:
	if _warm_started:
		return
	_warm_started = true
	Warmup.run(self, _on_warm_done, Warmup.DEFAULT_MODEL_ROOTS, [MODELS.trim_suffix("/")])


func _on_warm_done() -> void:
	_warm_done = true


# ------------------------------------------------------------------ world

func _build_environment() -> void:
	var sky_mat := ShaderMaterial.new()
	var sh: Shader = SKY_SHADER
	sky_mat.shader = sh
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.32
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_strength = 1.0
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	for i in 7:
		env.set_glow_level(i, 1.0 if i in [2, 3, 4, 5] else 0.0)
	env.fog_enabled = true
	env.fog_light_color = Color(0.2, 0.16, 0.13)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.18
	env.fog_density = 0.0028
	env.fog_aerial_perspective = 0.7
	env.fog_sky_affect = 0.15
	env.fog_height = 3.0
	env.fog_height_density = 0.03
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _model(file: String) -> Node3D:
	var path := MODELS + file
	if not ResourceLoader.exists(path):
		push_warning("Title: missing %s (build it with tools/blender/build.py -- title/...)" % path)
		return Node3D.new()
	return GlbModel.create(path, false)


func _build_vista() -> void:
	var plain := _model("ruined_plain.glb")
	add_child(plain)

	var statue := _model("fallen_angel.glb")
	statue.position = STATUE
	statue.rotation_degrees = Vector3(0, -32, 0)
	add_child(statue)

	var cath := _model("sky_cathedral.glb")
	cath.position = CATHEDRAL
	cath.rotation_degrees = Vector3(0, 8, 0)
	add_child(cath)
	Art.no_shadows(cath)  # far away & huge: keep the shadow map for the plain and the colossus
	for n in cath.find_children("frag_*", "", true, false):
		var n3 := n as Node3D
		if n3 == null:
			continue
		var axis := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.3, 0.3), _rng.randf_range(-1, 1)).normalized()
		var big := n3.name.begins_with("frag_nave")
		_frags.append([n3, n3.transform, _rng.randf() * TAU, 1.2 if big else _rng.randf_range(2.0, 4.5), axis,
				0.4 if big else _rng.randf_range(2.0, 7.0)])

	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.near = 0.3
	_cam.far = 3000.0
	_cam.current = true
	add_child(_cam)


func _build_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.8, 0.56)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 420.0
	sun.shadow_blur = 1.5
	sun.light_angular_distance = 1.0
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, SUN_TOWARD, Vector3.UP)
	# cold fill from the viewer's side so the colossus' face is not pure black
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.55, 0.62, 0.8)
	fill.light_energy = 0.22
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(fill)
	fill.look_at_from_position(Vector3.ZERO, Vector3(-0.3, -0.5, -1.0), Vector3.UP)

	# ---- the pillar of golden light, ground to heaven
	var beam_sh: Shader = BEAM_SHADER
	_beam(beam_sh, PILLAR + Vector3(0, 1400, 0), PILLAR, 70.0, GOLD, 0.16, {"edge": 1.6, "head": 0.02,
			"tail": 0.02, "foot": 1.0, "streaks": 0.25, "soft_depth": 20.0}, 0.0)
	_beam(beam_sh, PILLAR + Vector3(0, 1400, 0), PILLAR, 22.0, GOLD, 0.9, {"edge": 2.2, "head": 0.02,
			"tail": 0.01, "foot": 2.0, "streaks": 0.45, "soft_depth": 10.0}, 1.3)
	_beam(beam_sh, PILLAR + Vector3(0, 1400, 0), PILLAR, 6.0, PALE_GOLD, 3.2, {"edge": 3.0, "head": 0.02,
			"tail": 0.005, "foot": 2.0, "streaks": 0.2, "soft_depth": 6.0}, 2.1)
	# god rays raking down from the shattered cathedral across the plain
	var src := CATHEDRAL + Vector3(0, -10, 0)
	for i in 8:
		var tx := lerpf(-150.0, 120.0, (i + _rng.randf_range(0.0, 0.6)) / 8.0)
		var tz := _rng.randf_range(-210.0, -40.0)
		var w := _rng.randf_range(14.0, 34.0)
		_beam(beam_sh, src + Vector3(_rng.randf_range(-30, 30), _rng.randf_range(-10, 20), 0), Vector3(tx, -20.0, tz),
				w, PALE_GOLD, _rng.randf_range(0.08, 0.16), {"spread": _rng.randf_range(2.2, 3.5), "edge": 1.8,
				"head": 0.18, "tail": 0.4, "streaks": 0.5, "soft_depth": 25.0, "near_fade": 60.0}, float(i) * 1.7)
	# long sun shafts fanning from behind the cathedral across the sky
	for i in 5:
		var ang := deg_to_rad(lerpf(-60.0, 50.0, i / 4.0) + _rng.randf_range(-6, 6))
		var dir := Vector3(sin(ang), cos(ang) * 0.55, 0.0)
		_beam(beam_sh, CATHEDRAL + Vector3(0, 30, -60), CATHEDRAL + Vector3(0, 30, -60) + dir * 520.0,
				_rng.randf_range(30.0, 60.0), PALE_GOLD, _rng.randf_range(0.05, 0.09), {"spread": 2.6, "head": 0.05,
				"tail": 0.6, "edge": 1.5, "streaks": 0.6, "soft_depth": 1.0}, 10.0 + i)

	# ground pool and light where the pillar lands
	var pool_sh: Shader = POOL_SHADER
	var pool := MeshInstance3D.new()
	var pq := PlaneMesh.new()
	pq.size = Vector2(150, 150)
	pool.mesh = pq
	var pm := ShaderMaterial.new()
	pm.shader = pool_sh
	pm.set_shader_parameter(&"color", GOLD)
	pm.set_shader_parameter(&"intensity", 1.4)
	pool.material_override = pm
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pool.position = PILLAR + Vector3(0, 0.6, 0)
	add_child(pool)
	var omni := OmniLight3D.new()
	omni.light_color = GOLD
	omni.light_energy = 9.0
	omni.omni_range = 150.0
	omni.omni_attenuation = 1.4
	omni.position = PILLAR + Vector3(0, 10, 0)
	add_child(omni)

	# ---- banks of ground mist at several depths
	var mist_sh: Shader = MIST_SHADER
	var banks := [[-12.0, 60.0, 9.0, 0.22], [-40.0, 120.0, 14.0, 0.3], [-90.0, 220.0, 22.0, 0.34],
			[-160.0, 360.0, 34.0, 0.38], [-240.0, 520.0, 50.0, 0.42], [-330.0, 700.0, 70.0, 0.4]]
	for i in banks.size():
		var b: Array = banks[i]
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(b[1], b[2])
		mi.mesh = q
		var mm := ShaderMaterial.new()
		mm.shader = mist_sh
		mm.set_shader_parameter(&"opacity", b[3])
		mm.set_shader_parameter(&"color", Color(0.17, 0.145, 0.125) if i < 3 else Color(0.24, 0.19, 0.15))
		mm.set_shader_parameter(&"soft_depth", 6.0 + b[2] * 0.3)
		mi.material_override = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(_rng.randf_range(-15, 15), b[2] * 0.42 - 1.0, b[0])
		mi.set_instance_shader_parameter(&"seed", float(i) * 3.7)
		add_child(mi)


func _beam(sh: Shader, from: Vector3, to: Vector3, width: float, color: Color, intensity: float,
		params: Dictionary, seed_v: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = QuadMesh.new()
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter(&"color", color)
	m.set_shader_parameter(&"intensity", intensity)
	for k in params:
		m.set_shader_parameter(StringName(k), params[k])
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var y_axis := from - to  # local +Y (UV.y = 0) is the source end
	var ref := Vector3.FORWARD if absf(y_axis.normalized().dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x_axis := y_axis.cross(ref).normalized() * width
	var z_axis := x_axis.cross(y_axis).normalized()
	mi.transform = Transform3D(Basis(x_axis, y_axis, z_axis), (from + to) * 0.5)
	mi.extra_cull_margin = maxf(width * 3.0, 60.0)
	mi.set_instance_shader_parameter(&"seed", seed_v)
	add_child(mi)
	_beams.append([mi, 1.0, seed_v])
	return mi


func _build_particles() -> void:
	# embers rising from the fissures and drifting past the camera
	var embers := GPUParticles3D.new()
	embers.amount = 260
	embers.lifetime = 9.0
	embers.preprocess = 8.0
	embers.position = Vector3(0, 2.0, -18)
	embers.visibility_aabb = AABB(Vector3(-80, -10, -80), Vector3(160, 60, 160))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(45.0, 1.5, 40.0)
	pm.direction = Vector3(0.2, 1.0, 0.1)
	pm.spread = 35.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.8
	pm.gravity = Vector3(0.45, 0.5, 0.25)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 2.0
	pm.turbulence_noise_scale = 4.0
	pm.turbulence_influence_min = 0.08
	pm.turbulence_influence_max = 0.2
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	pm.color_ramp = _ramp(Color(1.0, 0.55, 0.2, 0.0), Color(1.0, 0.45, 0.12, 1.0), Color(0.9, 0.2, 0.05, 0.0))
	embers.process_material = pm
	embers.draw_pass_1 = _quad(0.16, MOTE_SHADER, {"energy": 5.0})
	add_child(embers)

	# ash falling from the broken sky
	var ash := GPUParticles3D.new()
	ash.amount = 420
	ash.lifetime = 16.0
	ash.preprocess = 14.0
	ash.position = Vector3(0, 22, -25)
	ash.visibility_aabb = AABB(Vector3(-90, -40, -90), Vector3(180, 80, 180))
	var am := ParticleProcessMaterial.new()
	am.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	am.emission_box_extents = Vector3(55.0, 6.0, 45.0)
	am.initial_velocity_min = 0.1
	am.initial_velocity_max = 0.4
	am.gravity = Vector3(0.5, -1.0, 0.3)
	am.turbulence_enabled = true
	am.turbulence_noise_strength = 1.4
	am.turbulence_noise_scale = 6.0
	am.turbulence_influence_min = 0.05
	am.turbulence_influence_max = 0.14
	am.angular_velocity_min = -80.0
	am.angular_velocity_max = 80.0
	am.scale_min = 0.6
	am.scale_max = 1.6
	am.color_ramp = _ramp(Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0))
	ash.process_material = am
	ash.draw_pass_1 = _quad(0.22, ASH_SHADER, {"opacity": 0.65})
	add_child(ash)

	# motes of light rising up inside the pillar
	var motes := GPUParticles3D.new()
	motes.amount = 160
	motes.lifetime = 14.0
	motes.preprocess = 14.0
	motes.position = PILLAR + Vector3(0, 2, 0)
	motes.visibility_aabb = AABB(Vector3(-40, -5, -40), Vector3(80, 300, 80))
	var mm := ParticleProcessMaterial.new()
	mm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mm.emission_box_extents = Vector3(12.0, 2.0, 12.0)
	mm.direction = Vector3(0, 1, 0)
	mm.spread = 8.0
	mm.initial_velocity_min = 8.0
	mm.initial_velocity_max = 18.0
	mm.gravity = Vector3(0, 0.6, 0)
	mm.scale_min = 0.6
	mm.scale_max = 1.6
	mm.color_ramp = _ramp(Color(1.0, 0.9, 0.6, 0.0), Color(1.0, 0.85, 0.55, 1.0), Color(1.0, 0.8, 0.5, 0.0))
	motes.process_material = mm
	motes.draw_pass_1 = _quad(1.6, MOTE_SHADER, {"energy": 6.0, "tint": Color(1.0, 0.75, 0.4),
			"core_tint": Color(1.0, 0.95, 0.8)})
	add_child(motes)


func _ramp(a: Color, b: Color, c: Color) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	g.colors = PackedColorArray([a, b, c])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt


func _quad(size: float, shader_path: String, params: Dictionary) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := ShaderMaterial.new()
	if ResourceLoader.exists(shader_path):
		m.shader = load(shader_path)
	for k in params:
		m.set_shader_parameter(StringName(k), params[k])
	q.material = m
	return q


# ------------------------------------------------------------------ UI

func _build_ui() -> void:
	var post := CanvasLayer.new()
	post.layer = 1
	add_child(post)
	if ResourceLoader.exists(POST_SHADER):
		var pr := ColorRect.new()
		pr.set_anchors_preset(Control.PRESET_FULL_RECT)
		pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pm := ShaderMaterial.new()
		pm.shader = load(POST_SHADER)
		pm.set_shader_parameter(&"vignette_strength", 0.7)
		pr.material = pm
		post.add_child(pr)

	var ui := CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)

	# cinematic letterbox
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_left = 0.0
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0
		bar.anchor_bottom = 0.0 if top else 1.0
		bar.offset_top = 0.0 if top else -48.0
		bar.offset_bottom = 48.0 if top else 0.0
		root.add_child(bar)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.anchor_left = 0.0
	col.anchor_right = 1.0
	col.anchor_top = 0.5
	col.anchor_bottom = 0.5
	col.offset_top = -10.0
	col.offset_bottom = 200.0
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.add_theme_constant_override(&"separation", 12)
	root.add_child(col)

	var base_font: Font = root.get_theme_font(&"font", &"TitleLabel")
	_logo_font = FontVariation.new()
	_logo_font.base_font = base_font
	_logo_font.spacing_glyph = 34
	var logo := Label.new()
	logo.theme_type_variation = &"TitleLabel"
	logo.text = "SINBOUND"
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.add_theme_font_override(&"font", _logo_font)
	logo.add_theme_font_size_override(&"font_size", 112)
	logo.add_theme_color_override(&"font_color", Color(0.93, 0.86, 0.68))
	logo.add_theme_color_override(&"font_outline_color", Color(0.08, 0.05, 0.03, 0.75))
	logo.add_theme_color_override(&"font_shadow_color", Color(0.0, 0.0, 0.0, 0.55))
	logo.add_theme_constant_override(&"shadow_outline_size", 28)
	logo.add_theme_constant_override(&"shadow_offset_y", 4)
	logo.add_theme_constant_override(&"outline_size", 3)
	logo.modulate.a = 0.0
	col.add_child(logo)
	_ui["logo"] = logo

	# thin gilded rule under the logo, fading out at both ends
	var rule_holder := CenterContainer.new()
	rule_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rule_holder)
	var rule := TextureRect.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(0.85, 0.66, 0.35, 0.0), Color(0.95, 0.8, 0.5, 0.9), Color(0.85, 0.66, 0.35, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 2
	rule.texture = gt
	rule.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rule.stretch_mode = TextureRect.STRETCH_SCALE
	rule.custom_minimum_size = Vector2(560, 2)
	rule.pivot_offset = Vector2(280, 1)
	rule.scale = Vector2(0.0, 1.0)
	rule_holder.add_child(rule)
	_ui["rule"] = rule

	var tag := Label.new()
	tag.theme_type_variation = &"LoreLabel"
	tag.text = "What Heaven cast down, Hell will not let rest."
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override(&"font_size", 23)
	tag.add_theme_color_override(&"font_color", Color(0.8, 0.74, 0.62))
	tag.add_theme_color_override(&"font_outline_color", Color(0.03, 0.02, 0.02, 0.85))
	tag.add_theme_constant_override(&"outline_size", 6)
	tag.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.6))
	tag.add_theme_constant_override(&"shadow_outline_size", 14)
	tag.modulate.a = 0.0
	col.add_child(tag)
	_ui["tag"] = tag

	_prompt_font = FontVariation.new()
	_prompt_font.base_font = base_font
	_prompt_font.spacing_glyph = 7
	var prompt := Label.new()
	prompt.theme_type_variation = &"InkLabel"
	prompt.text = "PRESS ANY KEY"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_override(&"font", _prompt_font)
	prompt.add_theme_font_size_override(&"font_size", 17)
	prompt.add_theme_color_override(&"font_color", Color(0.9, 0.82, 0.62))
	prompt.anchor_left = 0.0
	prompt.anchor_right = 1.0
	prompt.anchor_top = 1.0
	prompt.anchor_bottom = 1.0
	prompt.offset_top = -118.0
	prompt.offset_bottom = -90.0
	prompt.modulate.a = 0.0
	root.add_child(prompt)
	_ui["prompt"] = prompt

	var veil_note := Label.new()
	veil_note.theme_type_variation = &"LoreLabel"
	veil_note.text = "The bells are still tolling..."
	veil_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	veil_note.anchor_left = 0.0
	veil_note.anchor_right = 1.0
	veil_note.anchor_top = 1.0
	veil_note.anchor_bottom = 1.0
	veil_note.offset_top = -60.0
	veil_note.offset_right = -36.0
	veil_note.offset_bottom = -30.0
	veil_note.modulate.a = 0.0

	var fade := ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)
	root.add_child(veil_note)  # above the black veil
	_ui["fade"] = fade
	_ui["veil_note"] = veil_note


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	_t += delta
	_update_camera(_t)
	_update_fragments(_t)
	for b in _beams:
		var mi: MeshInstance3D = b[0]
		mi.set_instance_shader_parameter(&"fade", 0.78 + 0.22 * sin(_t * 0.35 + float(b[2]) * 1.9))
	_update_ui(_t)
	if _t >= _next_bell and not _leaving:
		_next_bell = _t + _rng.randf_range(11.0, 17.0)
		if has_node("/root/Sfx"):
			Sfx.play(&"toll", 0.04, -9.0)


func _update_camera(t: float) -> void:
	# Slow crane-up at the start, then an endless gentle drift (period ~90 s).
	var intro := 1.0 - pow(1.0 - clampf(t / 14.0, 0.0, 1.0), 3.0)
	var s := 0.5 - 0.5 * cos(t * TAU / 90.0)
	var pos := Vector3(lerpf(-7.0, 7.0, s), lerpf(4.2, 7.5, intro) + 0.8 * sin(t * 0.11), lerpf(36.0, 24.0, s))
	pos += Vector3(sin(t * 0.37) * 0.12, sin(t * 0.53 + 1.0) * 0.08, 0.0)  # breath of a handheld lens
	var target := Vector3(lerpf(-2.0, -10.0, s), lerpf(36.0, 44.0, intro), -200.0)
	_cam.position = pos
	_cam.look_at(target, Vector3.UP)
	_cam.rotate_object_local(Vector3.FORWARD, deg_to_rad(sin(t * 0.07) * 0.6))


func _update_fragments(t: float) -> void:
	for f in _frags:
		var n: Node3D = f[0]
		var base: Transform3D = f[1]
		var ph: float = f[2]
		var amp: float = f[3]
		var axis: Vector3 = f[4]
		var deg: float = f[5]
		var off := Vector3(0, sin(t * 0.21 + ph) * amp, cos(t * 0.13 + ph) * amp * 0.4)
		var rot := Basis(axis, deg_to_rad(sin(t * 0.09 + ph) * deg))
		n.transform = Transform3D(rot * base.basis, base.origin + off)


func _update_ui(t: float) -> void:
	var fade: ColorRect = _ui["fade"]
	if not _leaving:
		fade.color.a = 1.0 - _ease(t, 0.2, 3.2)
	var logo: Label = _ui["logo"]
	logo.modulate.a = _ease(t, 2.0, 6.0)
	_logo_font.spacing_glyph = int(round(lerpf(34.0, 18.0, _ease(t, 1.5, 10.0))))
	(_ui["rule"] as Control).scale.x = _ease(t, 4.0, 7.0)
	(_ui["tag"] as Control).modulate.a = _ease(t, 5.0, 7.5) * 0.95
	var prompt: Label = _ui["prompt"]
	if not _leaving and _menu == null:
		var on := _ease(t, 7.0, 8.5)
		prompt.modulate.a = on * (0.55 + 0.4 * sin((t - 7.0) * 2.2))


func _ease(t: float, a: float, b: float) -> float:
	var x := clampf((t - a) / (b - a), 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


# ------------------------------------------------------------------ input / leaving

func _input(event: InputEvent) -> void:
	if _leaving or _t < 0.8 or _menu != null:
		return
	var go := false
	if event is InputEventKey:
		go = event.pressed and not event.echo
	elif event is InputEventMouseButton or event is InputEventJoypadButton or event is InputEventScreenTouch:
		go = event.pressed
	if go:
		get_viewport().set_input_as_handled()
		_open_menu()


## First key press: the prompt gives way to the main menu (Descend starts _leave()).
func _open_menu() -> void:
	if not _warm_started:
		_start_warmup()
	var prompt: Label = _ui["prompt"]
	create_tween().tween_property(prompt, "modulate:a", 0.0, 0.3)
	_menu = MainMenu.new()
	add_child(_menu)
	_menu.descend_chosen.connect(_leave)


func _leave() -> void:
	_leaving = true
	if not _warm_started:
		_start_warmup()
	if has_node("/root/Sfx"):
		Sfx.play(&"toll", 0.0, -4.0)
	var prompt: Label = _ui["prompt"]
	var fade: ColorRect = _ui["fade"]
	var tw := create_tween()
	tw.tween_property(prompt, "modulate:a", 1.0, 0.12)
	tw.tween_property(prompt, "modulate:a", 0.0, 0.5)
	tw.parallel().tween_property(fade, "color:a", 1.0, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	if not _warm_done:
		var note: Label = _ui["veil_note"]
		create_tween().tween_property(note, "modulate:a", 0.8, 0.8)
		while not _warm_done:
			await get_tree().process_frame
	get_tree().change_scene_to_file(NEXT_SCENE)
