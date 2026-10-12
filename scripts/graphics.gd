class_name Graphics
extends RefCounted
## Applies the graphics settings held by the Settings autoload to the running game.
##
##   Graphics.apply(get_tree())   # re-apply everything (viewport, window, every known scene node)
##
## Settings wires itself up automatically: it connects SceneTree.node_added to
## Graphics.on_node_added, so any WorldEnvironment / DirectionalLight3D / Camera3D /
## Atmosphere / Decor that enters the tree gets the current settings *before* its _ready
## (Atmosphere and Decor read their exported counts in _ready, so they are scaled here).
## Settings also calls apply() whenever a graphics value changes (coalesced, deferred).
##
## Scene values are treated as the "authored" look (High): the first time a node/resource is
## touched its original values are stored as metadata, and toggles restore them when on.

const ATMOSPHERE_PATH := "res://scenes/world/atmosphere.gd"
const DECOR_PATH := "res://scenes/world/decor.gd"
const META := &"_gfx_orig"

# Antialiasing modes (Settings.antialiasing).
enum AA { OFF, FXAA, MSAA_2X, MSAA_4X, TAA }

static var _atmo_script: Script
static var _decor_script: Script
static var _scripts_loaded := false
static var _nodes: Array[WeakRef] = []


## Re-applies all graphics settings: viewport/window/engine-level ones, then every registered
## scene node (and anything relevant under the current scene that isn't registered yet).
static func apply(tree: SceneTree) -> void:
	if tree == null:
		return
	_apply_global(tree)
	if tree.current_scene:
		_scan(tree.current_scene)
	var alive: Array[WeakRef] = []
	for w: WeakRef in _nodes:
		var n := w.get_ref() as Node
		if n and is_instance_valid(n) and n.is_inside_tree():
			alive.append(w)
			_apply_node(n, false)
		elif n and is_instance_valid(n):
			alive.append(w)  # temporarily out of the tree; keep
	_nodes = alive


## Hook for SceneTree.node_added (connected by Settings). Cheap type checks only.
static func on_node_added(node: Node) -> void:
	if _is_relevant(node):
		_register(node)
		_apply_node(node, true)


# ------------------------------------------------------------------ discovery

static func _load_scripts() -> void:
	if _scripts_loaded:
		return
	_scripts_loaded = true
	if ResourceLoader.exists(ATMOSPHERE_PATH):
		_atmo_script = load(ATMOSPHERE_PATH) as Script
	if ResourceLoader.exists(DECOR_PATH):
		_decor_script = load(DECOR_PATH) as Script


static func _is_relevant(node: Node) -> bool:
	if node is WorldEnvironment or node is DirectionalLight3D or node is Camera3D:
		return true
	if not node is Node3D:
		return false
	var s: Variant = node.get_script()
	if s == null:
		return false
	_load_scripts()
	return (_atmo_script != null and s == _atmo_script) or (_decor_script != null and s == _decor_script)


static func _register(node: Node) -> void:
	for w: WeakRef in _nodes:
		if w.get_ref() == node:
			return
	_nodes.append(weakref(node))


static func _scan(root: Node) -> void:
	if _is_relevant(root):
		_register(root)
	for c in root.get_children():
		# Don't descend into big dynamic containers of gameplay entities.
		if c.get_child_count() > 400:
			continue
		_scan(c)


static func _apply_node(node: Node, entering: bool) -> void:
	if node is WorldEnvironment:
		_apply_world_env(node)
	elif node is DirectionalLight3D:
		_apply_sun(node)
	elif node is Camera3D:
		var ca := (node as Camera3D).attributes
		if ca:
			_apply_cam_attr(ca)
	else:
		var s: Variant = node.get_script()
		if _atmo_script and s == _atmo_script:
			_apply_atmosphere(node, entering)
		elif _decor_script and s == _decor_script:
			_apply_decor(node)


## Stores `props` of `obj` once (first touch) and returns the stored originals.
static func _orig(obj: Object, props: Array) -> Dictionary:
	var d: Dictionary = obj.get_meta(META, {})
	var changed := false
	for p: StringName in props:
		if not d.has(p):
			d[p] = obj.get(p)
			changed = true
	if changed:
		obj.set_meta(META, d)
	return d


# ------------------------------------------------------------------ global (viewport / engine)

static func _apply_global(tree: SceneTree) -> void:
	var vp := tree.root
	if vp == null:
		return
	# Render scale (FSR 1 upscaling below 100 %).
	var scale := clampf(Settings.render_scale, 0.5, 1.0)
	vp.scaling_3d_scale = scale
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 0.999 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.fsr_sharpness = 0.3

	# Antialiasing.
	var aa: int = Settings.antialiasing
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = false
	match aa:
		AA.FXAA:
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		AA.MSAA_2X:
			vp.msaa_3d = Viewport.MSAA_2X
		AA.MSAA_4X:
			vp.msaa_3d = Viewport.MSAA_4X
		AA.TAA:
			vp.use_taa = true

	# Shadows: atlas sizes + soft filter quality (light-level bits in _apply_sun).
	var sq: int = Settings.shadow_quality
	var dir_size: int = [1024, 1024, 2048, 4096, 8192][clampi(sq, 0, 4)]
	var pos_size: int = [1024, 1024, 2048, 4096, 4096][clampi(sq, 0, 4)]
	var filt: int = [
		RenderingServer.SHADOW_QUALITY_HARD,
		RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
		RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
	][clampi(sq, 0, 4)]
	RenderingServer.directional_shadow_atlas_set_size(dir_size, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(filt)
	RenderingServer.positional_soft_shadow_filter_set_quality(filt)
	vp.positional_shadow_atlas_size = pos_size if sq > 0 else 0

	# SSAO quality (on/off is per-Environment).
	var ao: int = Settings.ssao_quality
	if ao > 0:
		var q: int = [RenderingServer.ENV_SSAO_QUALITY_VERY_LOW, RenderingServer.ENV_SSAO_QUALITY_VERY_LOW,
				RenderingServer.ENV_SSAO_QUALITY_MEDIUM, RenderingServer.ENV_SSAO_QUALITY_HIGH][clampi(ao, 0, 3)]
		RenderingServer.environment_set_ssao_quality(q, ao < 3, 0.5, 2, 50.0, 300.0)

	# Depth of field quality.
	RenderingServer.camera_attributes_set_dof_blur_quality(
			RenderingServer.DOF_BLUR_QUALITY_HIGH if sq >= 4
			else RenderingServer.DOF_BLUR_QUALITY_MEDIUM, true)

	# Frame pacing.
	Engine.max_fps = maxi(Settings.max_fps, 0)
	if DisplayServer.get_name() != "headless":
		# Adaptive: syncs while the game keeps up, but a late frame shows immediately instead of
		# waiting a whole extra refresh (plain VSYNC_ENABLED halves 60 -> 30 fps on a heavy frame).
		DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_ADAPTIVE if Settings.vsync else DisplayServer.VSYNC_DISABLED)

	# UI scale (multiplies the canvas_items stretch).
	vp.content_scale_factor = clampf(Settings.ui_scale, 0.5, 2.0)


# ------------------------------------------------------------------ per node

static func _apply_world_env(we: WorldEnvironment) -> void:
	var env := we.environment
	if env:
		var o := _orig(env, [&"ssao_enabled", &"glow_enabled", &"volumetric_fog_enabled", &"ssil_enabled"])
		env.ssao_enabled = bool(o[&"ssao_enabled"]) and Settings.ssao_quality > 0
		env.ssil_enabled = bool(o[&"ssil_enabled"]) and Settings.ssao_quality >= 3
		env.glow_enabled = bool(o[&"glow_enabled"]) and Settings.glow
		env.volumetric_fog_enabled = bool(o[&"volumetric_fog_enabled"]) and Settings.volumetrics
	if we.camera_attributes:
		_apply_cam_attr(we.camera_attributes)


static func _apply_cam_attr(ca: CameraAttributes) -> void:
	if ca is CameraAttributesPractical:
		var o := _orig(ca, [&"dof_blur_far_enabled", &"dof_blur_near_enabled"])
		ca.dof_blur_far_enabled = bool(o[&"dof_blur_far_enabled"]) and Settings.dof
		ca.dof_blur_near_enabled = bool(o[&"dof_blur_near_enabled"]) and Settings.dof


static func _apply_sun(sun: DirectionalLight3D) -> void:
	var o := _orig(sun, [&"shadow_enabled", &"directional_shadow_max_distance", &"directional_shadow_mode", &"shadow_blur"])
	var sq: int = Settings.shadow_quality
	sun.shadow_enabled = bool(o[&"shadow_enabled"]) and sq > 0
	var dist: float = o[&"directional_shadow_max_distance"]
	sun.directional_shadow_max_distance = dist * ([0.6, 0.6, 0.8, 1.0, 1.0][clampi(sq, 0, 4)])
	var mode: int = o[&"directional_shadow_mode"]
	if sq >= 4:
		mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	elif sq == 1:
		mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_mode = mode as DirectionalLight3D.ShadowMode
	sun.shadow_blur = float(o[&"shadow_blur"]) * (0.6 if sq <= 1 else 1.0)


static func _apply_atmosphere(atmo: Node, entering: bool) -> void:
	var o := _orig(atmo, [&"ash_count", &"ember_count", &"beam_count", &"mist_enabled"])
	var pd := clampf(Settings.particle_density, 0.0, 2.0)
	if entering and not atmo.is_node_ready():
		# Before _ready: change what gets built.
		atmo.set(&"ash_count", maxi(1, roundi(int(o[&"ash_count"]) * pd)))
		atmo.set(&"ember_count", maxi(1, roundi(int(o[&"ember_count"]) * pd)))
		# Keep the beams' nodes around (hidden when volumetrics are off) so they can be toggled live.
		atmo.set(&"mist_enabled", bool(o[&"mist_enabled"]) and Settings.mist)
		# Shafts are built in _ready; hide them right after if needed.
		atmo.ready.connect(func() -> void: _apply_atmosphere(atmo, false), CONNECT_ONE_SHOT)
		return
	# Live: Ash/Embers via amount_ratio relative to what was built.
	var built_ash: int = atmo.get(&"ash_count")
	var built_emb: int = atmo.get(&"ember_count")
	for pair: Array in [[&"_ash", int(o[&"ash_count"]), built_ash], [&"_embers", int(o[&"ember_count"]), built_emb]]:
		var p: Variant = atmo.get(pair[0])
		if p is GPUParticles3D and is_instance_valid(p) and int(pair[2]) > 0:
			(p as GPUParticles3D).amount_ratio = clampf(float(pair[1]) * pd / float(pair[2]), 0.0, 1.0)
	# Sun shafts.
	var beams: Variant = atmo.get(&"_beams")
	if beams is Array:
		for b: Variant in beams:
			if b is Dictionary and (b as Dictionary).get("node") is Node3D:
				var mi: Node3D = b["node"]
				if is_instance_valid(mi):
					mi.visible = Settings.volumetrics
	# Mist sheets (only exist if they were built).
	var mist: Variant = atmo.get(&"_mist")
	if mist is Array:
		for m: Variant in mist:
			if m is Node3D and is_instance_valid(m):
				(m as Node3D).visible = Settings.mist


static func _apply_decor(decor: Node) -> void:
	# Affects chunks built from now on (the streaming rebuilds as the player moves).
	var o := _orig(decor, [&"big_min", &"big_max", &"small_min", &"small_max"])
	var dd := clampf(Settings.decor_density, 0.0, 2.0)
	for p: StringName in [&"big_min", &"big_max", &"small_min", &"small_max"]:
		var v := roundi(int(o[p]) * dd)
		if p == &"big_max" or p == &"small_max":
			v = maxi(v, 1)
		decor.set(p, v)
