class_name AtmoApply
extends RefCounted
## Writes one flat Atmosphere state ("section.key" -> value, see AtmoPresets) onto scene objects.
## Stateless helpers used by the Atmosphere autoload; safe to call every frame of a blend.
## (Quality-gated toggles live in the autoload, which knows the Settings.)

const TONEMAPS := {"linear": 0, "reinhard": 1, "filmic": 2, "aces": 3, "agx": 4}


## Everything continuous on the Environment (toggles excluded: see Atmosphere._apply_env_toggles).
static func environment(env: Environment, s: Dictionary) -> void:
	env.tonemap_mode = TONEMAPS.get(String(s["env.tonemap"]).to_lower(), Environment.TONE_MAPPER_AGX)
	env.tonemap_exposure = s["env.exposure"]
	env.tonemap_white = s["env.white"]
	env.background_color = s["env.background"]
	env.ambient_light_color = s["env.ambient"]
	env.ambient_light_energy = s["env.ambient_energy"]
	env.ambient_light_sky_contribution = s["env.ambient_sky"]
	env.glow_intensity = s["env.glow_intensity"]
	env.glow_strength = s["env.glow_strength"]
	env.glow_bloom = s["env.glow_bloom"]
	env.glow_hdr_threshold = s["env.glow_threshold"]
	env.ssao_intensity = s["env.ssao_intensity"]
	env.ssao_radius = s["env.ssao_radius"]
	env.fog_enabled = s["env.fog"]
	env.fog_light_color = s["env.fog_color"]
	env.fog_light_energy = s["env.fog_energy"]
	env.fog_density = s["env.fog_density"]
	env.fog_sun_scatter = s["env.fog_scatter"]
	env.fog_height = s["env.fog_height"]
	env.fog_height_density = s["env.fog_height_density"]
	env.volumetric_fog_density = s["env.volfog_density"]
	env.volumetric_fog_albedo = s["env.volfog_albedo"]
	env.volumetric_fog_emission = s["env.volfog_emission"]
	env.volumetric_fog_emission_energy = s["env.volfog_emission_energy"]
	env.volumetric_fog_anisotropy = s["env.volfog_anisotropy"]
	env.adjustment_enabled = s["env.adjust"]
	env.adjustment_brightness = s["env.brightness"]
	env.adjustment_contrast = s["env.contrast"]
	env.adjustment_saturation = s["env.saturation"]


static func sky(mat: ProceduralSkyMaterial, s: Dictionary) -> void:
	mat.sky_top_color = s["sky.top"]
	mat.sky_horizon_color = s["sky.horizon"]
	mat.ground_bottom_color = s["sky.ground_bottom"]
	mat.ground_horizon_color = s["sky.ground_horizon"]
	mat.sky_energy_multiplier = s["sky.energy"]


static func sun(light: DirectionalLight3D, s: Dictionary) -> void:
	var e: float = s["sun.energy"]
	light.visible = e > 0.001
	light.light_energy = e
	light.light_color = s["sun.color"]
	light.light_volumetric_fog_energy = s["sun.fog_energy"]
	light.rotation = Vector3(deg_to_rad(s["sun.pitch"]), deg_to_rad(s["sun.yaw"]), 0.0)


## The post pass (res://shaders/post_fx.gdshader). (The corruption vignette is the rig's own
## screen layer, AtmoScreenFX, so the grade's vignette stays the preset's.)
static func grade(post: ShaderMaterial, s: Dictionary) -> void:
	var sh: Color = s["grade.shadow_tint"]
	var hi: Color = s["grade.highlight_tint"]
	var vc: Color = s["grade.vignette_color"]
	post.set_shader_parameter(&"shadow_tint", Vector3(sh.r, sh.g, sh.b))
	post.set_shader_parameter(&"highlight_tint", Vector3(hi.r, hi.g, hi.b))
	post.set_shader_parameter(&"saturation", s["grade.saturation"])
	post.set_shader_parameter(&"contrast", s["grade.contrast"])
	post.set_shader_parameter(&"lift", s["grade.lift"])
	post.set_shader_parameter(&"vignette_color", Vector3(vc.r, vc.g, vc.b))
	post.set_shader_parameter(&"vignette_strength", s["grade.vignette"])
	post.set_shader_parameter(&"grain", s["grade.grain"])


## The stock Atmosphere node of main.tscn (scenes/world/atmosphere.gd): its ash / embers are hidden
## when the preset says so (the rig has its own, tinted layers), shafts recoloured, mist scaled.
static func legacy_atmosphere(legacy: Node3D, s: Dictionary) -> void:
	for pair: Array in [[^"Ash", "scene.ash"], [^"Embers", "scene.embers"]]:
		_set_particles_on(legacy.get_node_or_null(pair[0]) as GPUParticles3D, float(s[pair[1]]) > 0.01)
	var bm: Variant = legacy.get(&"_beam_material")
	if bm is ShaderMaterial:
		(bm as ShaderMaterial).set_shader_parameter(&"color", s["scene.beam_color"])
		(bm as ShaderMaterial).set_shader_parameter(&"intensity", 0.32 * float(s["scene.beams"]))
	var w: Vector2 = s["weather.wind"]
	legacy.set(&"wind", Vector3(w.x, 0.0, w.y))
	var mist: Variant = legacy.get(&"_mist")
	if mist is Array:
		for m: Variant in mist:
			var mi := m as MeshInstance3D
			if mi == null or not (mi.material_override is ShaderMaterial):
				continue
			var mat: ShaderMaterial = mi.material_override
			if not mat.has_meta(&"atmo_opacity"):
				mat.set_meta(&"atmo_opacity", mat.get_shader_parameter(&"opacity"))
			mat.set_shader_parameter(&"opacity", float(mat.get_meta(&"atmo_opacity")) * float(s["scene.mist"]))


## A GameMap's own ambient particles (GameMap.ambient_particles -> "Ambient_<kind>") are hidden when
## the preset brings its own weather for that map (scene.map_particles = 0).
static func map_particles(map: Node, s: Dictionary) -> void:
	var on: bool = float(s["scene.map_particles"]) > 0.5
	for c in map.get_children():
		if c is GPUParticles3D and String(c.name).begins_with("Ambient_"):
			_set_particles_on(c, on)


static func _set_particles_on(p: GPUParticles3D, on: bool) -> void:
	if p == null:
		return
	p.visible = on
	if p.emitting != on:
		p.emitting = on
