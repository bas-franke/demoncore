class_name AtmoScene
extends RefCounted
## The nodes of one scene that the Atmosphere autoload drives, found (or created) once and kept:
## WorldEnvironment + its Environment / ProceduralSkyMaterial, the Sun, the post pass (group
## &"post_fx"), the stock Atmosphere node of main.tscn, the ground material (wetness) and the
## AtmoRig the autoload adds under the scene. `apply()` writes a flat state onto all of them.
## A new AtmoScene is made for every new current scene, so nothing stale survives a scene change.

const RIG := preload("res://scenes/world/atmo/atmo_rig.gd")
const LEGACY_ATMO_PATH := "res://scenes/world/atmosphere.gd"
const POST_SHADER_PATH := "res://shaders/post_fx.gdshader"
## Graphics (res://scripts/graphics.gd) stores the "authored" env toggles under this meta key and
## gates them by the settings; presets write their toggles there so both agree.
const GFX_META := &"_gfx_orig"

var root: Node
var rig: AtmoRig
var we: WorldEnvironment
var env: Environment
var sky: ProceduralSkyMaterial
var sun: DirectionalLight3D
var post: ShaderMaterial
var legacy: Node3D
var ground_mat: ShaderMaterial


func _init(scene_root: Node) -> void:
	root = scene_root


func is_valid() -> bool:
	return root != null and is_instance_valid(root)


## The rig under the scene (created on first use, sized for `quality` / `density`).
func ensure_rig(quality: int, density: float) -> AtmoRig:
	if is_instance_valid(rig):
		return rig
	if not is_valid():
		return null
	rig = RIG.new()
	rig.name = "AtmosphereRig"
	root.add_child(rig)
	rig.set_quality(quality, density)
	return rig


## Finds the driven nodes. `full` also creates what is missing (environment, sun, post pass).
## Cheap to call again: only missing / freed bindings are searched for.
func bind(full: bool) -> void:
	if not is_valid():
		return
	if env == null:
		var w := find(root, func(n: Node) -> bool: return n is WorldEnvironment) as WorldEnvironment
		if w == null and full and rig:
			w = make_environment(rig)
		if w and w.environment:
			we = w
			_take_env(w.environment)
	if not is_instance_valid(sun):
		sun = find(root, func(n: Node) -> bool:
			return n is DirectionalLight3D and n.name == &"Sun") as DirectionalLight3D
		if sun == null:
			sun = find(root, func(n: Node) -> bool:
				return n is DirectionalLight3D and not (rig and rig.is_ancestor_of(n))) as DirectionalLight3D
		if sun == null and full and rig:
			sun = make_sun(rig)
	if post == null:
		for n in root.get_tree().get_nodes_in_group(&"post_fx"):
			var ci := n as CanvasItem
			if ci and root.is_ancestor_of(ci) and ci.material is ShaderMaterial:
				post = ci.material
				break
		if post == null and full and rig and ResourceLoader.exists(POST_SHADER_PATH):
			post = make_post(rig)
	if not is_instance_valid(legacy):
		legacy = find(root, func(n: Node) -> bool:
			var s: Script = n.get_script()
			return s != null and s.resource_path == LEGACY_ATMO_PATH) as Node3D
	if ground_mat == null:
		var g := root.get_node_or_null(^"Ground") as MeshInstance3D
		if g:
			var m := g.material_override if g.material_override else (g.get_active_material(0) if g.mesh else null)
			if m is ShaderMaterial and (m as ShaderMaterial).shader:
				for u in (m as ShaderMaterial).shader.get_shader_uniform_list():
					if u.get("name", "") == "wetness":
						ground_mat = m
						break


## Writes `s` onto every bound node. `allow` = what the settings permit:
## {"ssao": bool, "glow": bool, "volumetrics": bool}.
func apply(s: Dictionary, allow: Dictionary) -> void:
	if s.is_empty() or not is_valid():
		return
	# Someone swapped the Environment resource (e.g. a map duplicating it): follow the new one.
	if env and is_instance_valid(we) and we.environment != env:
		_take_env(we.environment)
	if env:
		AtmoApply.environment(env, s)
		apply_toggles(s, allow)
	if sky:
		AtmoApply.sky(sky, s)
	if is_instance_valid(sun):
		AtmoApply.sun(sun, s)
	if post:
		AtmoApply.grade(post, s)
	if is_instance_valid(legacy):
		AtmoApply.legacy_atmosphere(legacy, s)
	var maps := root.get_node_or_null(^"/root/Maps")
	var map: Variant = maps.get(&"current_map") if maps else null
	if map is Node and is_instance_valid(map):
		AtmoApply.map_particles(map, s)
	if ground_mat:
		ground_mat.set_shader_parameter(&"wetness", s["weather.wet"])
	if is_instance_valid(rig):
		rig.apply_state(s)


## Glow / SSAO / volumetric fog: the preset says what the look wants, `allow` what the machine may
## do. Written into Graphics' "authored" meta too, so a later Graphics.apply() agrees.
func apply_toggles(s: Dictionary, allow: Dictionary) -> void:
	if env == null or s.is_empty():
		return
	var o: Dictionary = env.get_meta(GFX_META, {})
	o[&"ssao_enabled"] = bool(s["env.ssao"])
	o[&"glow_enabled"] = bool(s["env.glow"])
	o[&"volumetric_fog_enabled"] = bool(s["env.volfog"])
	if not o.has(&"ssil_enabled"):
		o[&"ssil_enabled"] = env.ssil_enabled
	env.set_meta(GFX_META, o)
	env.ssao_enabled = bool(s["env.ssao"]) and bool(allow.get("ssao", true))
	env.glow_enabled = bool(s["env.glow"]) and bool(allow.get("glow", true))
	env.volumetric_fog_enabled = bool(s["env.volfog"]) and bool(allow.get("volumetrics", true))


## Depth-first search under `from` (skipping huge entity containers and the rig itself).
func find(from: Node, pred: Callable) -> Node:
	for c in from.get_children():
		if pred.call(c):
			return c
	for c in from.get_children():
		if c.get_child_count() > 0 and c.get_child_count() < 400 and c != rig:
			var r := find(c, pred)
			if r:
				return r
	return null


# ---------------------------------------------------------------- fallbacks (under the rig)

## A fallback post-process pass (only created when the scene has none in group &"post_fx").
static func make_post(parent: Node) -> ShaderMaterial:
	var layer := CanvasLayer.new()
	layer.name = "AtmoPostFX"
	layer.layer = -1
	parent.add_child(layer)
	var rect := ColorRect.new()
	rect.name = "PostRect"
	rect.add_to_group(&"post_fx")  # GameFeel drives low_hp / hit_flash through this group
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = load(POST_SHADER_PATH)
	rect.material = mat
	layer.add_child(rect)
	return mat


## A fallback WorldEnvironment (procedural sky, AgX) for scenes that have none.
static func make_environment(parent: Node) -> WorldEnvironment:
	var env_res := Environment.new()
	env_res.background_mode = Environment.BG_COLOR
	var sky_res := Sky.new()
	sky_res.sky_material = ProceduralSkyMaterial.new()
	env_res.sky = sky_res
	env_res.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env_res.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var world_env := WorldEnvironment.new()
	world_env.name = "AtmoEnvironment"
	world_env.environment = env_res
	parent.add_child(world_env)
	return world_env


## A fallback shadow-casting sun for scenes that have none.
static func make_sun(parent: Node) -> DirectionalLight3D:
	var sun_light := DirectionalLight3D.new()
	sun_light.name = "AtmoSun"
	sun_light.shadow_enabled = true
	sun_light.shadow_bias = 0.04
	sun_light.shadow_normal_bias = 1.4
	sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun_light.directional_shadow_max_distance = 55.0
	parent.add_child(sun_light)
	return sun_light


func _take_env(e: Environment) -> void:
	env = e
	sky = env.sky.sky_material as ProceduralSkyMaterial if env and env.sky else null
