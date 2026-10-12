class_name Warmup
extends Node
## Shader / pipeline warm-up. Renders, for a few frames and invisibly (into a tiny private
## SubViewport with its own World3D), every Blender model under the given folders plus the game's
## shared materials and every .gdshader in the project, so Godot compiles the render pipelines
## before gameplay instead of hitching on the first appearance of an enemy / weapon / effect.
##
##   Warmup.run(self, func(): print("pipelines warm"))
##   Warmup.run(self, _on_warm, ["res://assets/models"], ["res://assets/models/title"])
##
## Robust to missing folders and to models / shaders that fail to load (they are skipped).
## Models load on worker threads (ResourceLoader.load_threaded_request), then are instanced a
## batch per frame so the warm-up itself never stalls the caller's scene. Per model it draws:
##   * the GlbModel-converted lit material (flashable, with the hit flash ON) and the static variant,
##   * the raw imported materials,
##   * an additive "dissolving into light" variant and an alpha-faded variant (death fades).
## Plus Art.mat for every surface preset (flashable + static), Art.emissive, Art.glow (additive,
## alpha, opaque) on every primitive mesh shape, and each project shader on a quad / particle system /
## ColorRect depending on its type. A directional light with shadows, an omni and a spot light are
## present so lit + shadow pipelines are covered.
## `on_done` is called exactly once (also on timeout); `finished` is emitted too. Paths warmed by an
## earlier run are skipped, so calling it again (e.g. returning to the title) is cheap.

signal finished

const DEFAULT_MODEL_ROOTS: Array = ["res://assets/models"]
## Folders scanned for .gdshader files ("res://" = the whole project, hidden folders skipped).
const SHADER_ROOTS: Array = ["res://"]
const SKIP_DIRS: Array = ["res://.godot", "res://addons", "res://tools/blender"]
## Frames rendered once everything is on screen.
const HOLD_FRAMES := 4
## Instances created per frame while building.
const PER_FRAME := 6
## Safety net: finish anyway after this many seconds.
const MAX_TIME := 20.0

## Resource paths already warmed in this session (shared across runs).
static var _warmed := {}

var on_done: Callable
var model_roots: Array = DEFAULT_MODEL_ROOTS
var exclude: Array = []
var is_done := false

var _requested: Array[String] = []
var _ready_res: Array = []  # [path, Resource]
var _build_queue: Array[Callable] = []
var _viewport: SubViewport
var _stage: Node3D
var _canvas: Node
var _state := 0  # 0 loading, 1 building, 2 holding
var _hold := 0
var _t := 0.0
var _n_models := 0
var _n_shaders := 0
var _n_inst := 0


## Starts a warm-up under `parent`. `on_done` (no arguments) is called when finished.
## `exclude` = path prefixes to skip (e.g. a folder the current scene already renders).
static func run(parent: Node, done: Callable = Callable(), roots: Array = DEFAULT_MODEL_ROOTS,
		skip: Array = []) -> Warmup:
	var w := Warmup.new()
	w.name = "Warmup"
	w.on_done = done
	w.model_roots = roots
	w.exclude = skip
	w.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(w)
	return w


func _ready() -> void:
	var paths: Array[String] = []
	for r in model_roots:
		_scan(String(r), [".glb", ".gltf"], paths)
	for r in SHADER_ROOTS:
		_scan(String(r), [".gdshader"], paths)
	for p in paths:
		if _warmed.has(p) or _excluded(p):
			continue
		if not ResourceLoader.exists(p):
			continue
		if ResourceLoader.load_threaded_request(p, "", true) == OK:
			_requested.append(p)
	_build_viewport()
	_queue_material_palette()
	_queue_enemy_roster()


func _process(delta: float) -> void:
	_t += delta
	if is_done:
		return
	if _t > MAX_TIME:
		push_warning("Warmup: timed out after %.0fs" % MAX_TIME)
		_finish()
		return
	match _state:
		0:
			_poll_loads()
			_build_some()
			if _requested.is_empty():
				for pr in _ready_res:
					_queue_resource(pr[0], pr[1])
				_ready_res.clear()
				_state = 1
		1:
			_build_some()
			if _build_queue.is_empty():
				_state = 2
				_hold = 0
		2:
			_hold += 1
			if _hold == 2:
				Art.flash(_stage, 1.0)
			if _hold >= HOLD_FRAMES:
				_finish()


func _finish() -> void:
	if is_done:
		return
	is_done = true
	if _viewport:
		_viewport.queue_free()
		_viewport = null
	print("Warmup: %d models, %d shaders, %d instances drawn in %.2fs" % [_n_models, _n_shaders, _n_inst, _t])
	finished.emit()
	if on_done.is_valid():
		on_done.call()
	queue_free()


# ------------------------------------------------------------------ discovery

func _excluded(p: String) -> bool:
	for e in exclude:
		if p.begins_with(String(e)):
			return true
	return false


## Recursively collects files with one of `exts` (handles exported builds, where only
## "<file>.import" / "<file>.remap" entries are listed). Missing folders are ignored.
func _scan(dir: String, exts: Array, out: Array[String]) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for s in SKIP_DIRS:
		if dir.trim_suffix("/") == String(s):
			return
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.include_hidden = false
	for f in d.get_files():
		var file_name := f.trim_suffix(".import").trim_suffix(".remap")
		for e in exts:
			if file_name.ends_with(String(e)):
				var full := dir.path_join(file_name)
				if not out.has(full):
					out.append(full)
				break
	for sub in d.get_directories():
		if sub.begins_with("."):
			continue
		_scan(dir.path_join(sub), exts, out)


func _poll_loads() -> void:
	var still: Array[String] = []
	for p in _requested:
		var st := ResourceLoader.load_threaded_get_status(p)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			still.append(p)
		elif st == ResourceLoader.THREAD_LOAD_LOADED:
			_ready_res.append([p, ResourceLoader.load_threaded_get(p)])
			_warmed[p] = true
		else:
			_warmed[p] = true  # failed / invalid: skip
	_requested = still
	# Feed finished resources into the build queue right away.
	for pr in _ready_res:
		_queue_resource(pr[0], pr[1])
	_ready_res.clear()


# ------------------------------------------------------------------ stage

func _build_viewport() -> void:
	var root_vp := get_tree().root
	_viewport = SubViewport.new()
	_viewport.name = "WarmupViewport"
	_viewport.size = Vector2i(192, 108)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = root_vp.msaa_3d
	_viewport.screen_space_aa = root_vp.screen_space_aa
	_viewport.use_taa = root_vp.use_taa
	_viewport.use_debanding = root_vp.use_debanding
	_viewport.positional_shadow_atlas_size = maxi(root_vp.positional_shadow_atlas_size, 1024)
	_viewport.audio_listener_enable_3d = false
	add_child(_viewport)

	var we := WorldEnvironment.new()
	we.environment = _environment()
	_viewport.add_child(we)

	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.position = Vector3(0, 0.4, 4.0)
	cam.current = true
	_viewport.add_child(cam)

	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-50, 30, 0)
	_viewport.add_child(sun)
	var omni := OmniLight3D.new()
	omni.position = Vector3(1.0, 1.5, 1.5)
	omni.omni_range = 8.0
	_viewport.add_child(omni)
	var omni_s := OmniLight3D.new()
	omni_s.position = Vector3(-1.0, 1.5, 1.0)
	omni_s.omni_range = 8.0
	omni_s.shadow_enabled = true
	_viewport.add_child(omni_s)
	var spot := SpotLight3D.new()
	spot.position = Vector3(0, 3, 2)
	spot.rotation_degrees = Vector3(-60, 0, 0)
	spot.spot_range = 10.0
	_viewport.add_child(spot)

	_stage = Node3D.new()
	_stage.name = "Stage"
	_viewport.add_child(_stage)
	_canvas = Node.new()  # 2D items (canvas_item shaders) live directly in the SubViewport
	_viewport.add_child(_canvas)


## The current world's environment if there is one (so fog / glow variants match), else a
## default dark-fantasy one with fog and glow.
func _environment() -> Environment:
	var w: World3D = get_viewport().world_3d if get_viewport() else null
	if w and w.environment:
		return w.environment
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.4, 0.45)
	env.fog_enabled = true
	env.fog_density = 0.01
	env.glow_enabled = true
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	return env


## Places `n` in front of the camera, scaled to ~1.6 m. Everything overlaps at the origin: nothing
## is occlusion-culled, so every pipeline still gets bound and drawn.
func _place(n: Node3D) -> void:
	_stage.add_child(n)
	_n_inst += 1
	var box := _aabb(n, Transform3D.IDENTITY)
	var size := box.get_longest_axis_size()
	if size > 0.001:
		var s := 1.6 / size
		n.scale = Vector3.ONE * s
		n.position = -box.get_center() * s


func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	if n is VisualInstance3D:
		var box := xf * (n as VisualInstance3D).get_aabb()
		out = box
		first = false
	for c in n.get_children():
		if c is Node3D:
			var b := _aabb(c, xf * (c as Node3D).transform)
			if b.size != Vector3.ZERO:
				out = b if first else out.merge(b)
				first = false
	return out


func _build_some() -> void:
	var n := 0
	while n < PER_FRAME and not _build_queue.is_empty():
		var job: Callable = _build_queue.pop_front()
		job.call()
		n += 1


# ------------------------------------------------------------------ jobs

func _queue_resource(path: String, res: Resource) -> void:
	if res is PackedScene:
		_n_models += 1
		_build_queue.append(_add_model.bind(path, res, 0))
		_build_queue.append(_add_model.bind(path, res, 1))
		_build_queue.append(_add_model.bind(path, res, 2))
		_build_queue.append(_add_model.bind(path, res, 3))
		_build_queue.append(_add_model.bind(path, res, 4))
	elif res is Shader:
		_n_shaders += 1
		_build_queue.append(_add_shader.bind(res))


## variant: 0 = GlbModel flashable, 1 = GlbModel static, 2 = raw imported materials,
## 3 = additive dissolve-into-light override, 4 = alpha fade override.
func _add_model(_path: String, ps: PackedScene, variant: int) -> void:
	var inst := ps.instantiate() as Node3D
	if inst == null:
		return
	match variant:
		0:
			GlbModel.convert_materials(inst, true)
		1:
			GlbModel.convert_materials(inst, false)
		3:
			_override(inst, Art.glow(Art.HOLY_WHITE, 2.0, true))
		4:
			_override(inst, _fade_mat())
	var holder := Node3D.new()
	holder.add_child(inst)
	_place(holder)
	var ap := _find_player(inst)
	if ap and ap.get_animation_list().size() > 0:
		ap.play(ap.get_animation_list()[0])


func _override(n: Node, m: Material) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).material_override = m
	for c in n.get_children():
		_override(c, m)


func _fade_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.8, 0.75, 0.7, 0.5)
	return m


func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var p := _find_player(c)
		if p:
			return p
	return null


func _add_shader(sh: Shader) -> void:
	var sm := ShaderMaterial.new()
	sm.shader = sh
	match sh.get_mode():
		Shader.MODE_SPATIAL:
			for mesh: Mesh in [QuadMesh.new(), Art.sphere()]:
				var mi := MeshInstance3D.new()
				mi.mesh = mesh
				mi.material_override = sm
				_place(mi)
		Shader.MODE_PARTICLES:
			var gp := GPUParticles3D.new()
			gp.amount = 4
			gp.lifetime = 1.0
			gp.process_material = sm
			gp.draw_pass_1 = QuadMesh.new()
			gp.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
			_stage.add_child(gp)
		Shader.MODE_CANVAS_ITEM:
			var cr := ColorRect.new()
			cr.size = Vector2(32, 32)
			cr.material = sm
			_canvas.add_child(cr)
		_:
			pass  # sky / fog shaders: compiled when their environment is used


## Shared Art materials on every primitive shape (the procedural characters/effects use these).
## Perf (docs/team/performance.md): one of every enemy model as the game spawns it (procedural
## builds, merged / skin-baked meshes, holy rim and the elite outline), so the first wave of a new
## type doesn't stutter on pipeline compiles. One type per build step.
const ENEMY_DIR := "res://data/enemies"

func _queue_enemy_roster() -> void:
	if _warmed.has(ENEMY_DIR) or not DirAccess.dir_exists_absolute(ENEMY_DIR):
		return
	_warmed[ENEMY_DIR] = true
	for f in DirAccess.get_files_at(ENEMY_DIR):
		var file := f.trim_suffix(".remap")
		if file.ends_with(".tres"):
			_build_queue.append(_add_enemy.bind(ENEMY_DIR.path_join(file)))


func _add_enemy(path: String) -> void:
	var data := load(path) as EnemyData
	if data == null or data.model == null:
		return
	var m := data.model.instantiate() as EnemyModel
	if m == null:
		return
	m.body_scale = data.size
	if m is ProcModel:
		(m as ProcModel).autoplay = false
		m.ensure_built()
	var holder := Node3D.new()
	holder.add_child(m)
	_place(holder)
	ArtStyle.apply_faction(m, ArtStyle.Faction.HOLY, data.xp_value >= Enemy.ELITE_XP)
	_n_models += 1


func _queue_material_palette() -> void:
	var mats: Array[Material] = []
	for flashable in [true, false]:
		mats.append(Art.mat(Art.STONE, 0.8, 0.0, 0.35, flashable))
		for s in Art.SURFACES.keys():
			mats.append(Art.mat(Art.STONE, 0.7, 0.2, 0.35, flashable, 0.25, s))
		mats.append(Art.emissive(Art.OBSIDIAN, Art.HELLFIRE, 2.5, 0.5, flashable))
	mats.append(Art.glow(Art.HOLY, 2.0, true))
	mats.append(Art.glow(Art.EMBER, 1.0, false, 0.5))
	mats.append(Art.glow(Art.HOLY_WHITE, 1.5, false, 1.0))
	mats.append(_fade_mat())
	var meshes: Array = [Art.sphere(), Art.box(), Art.cylinder(), Art.torus(), Art.prism(), Art.capsule(),
			Art.cone(), QuadMesh.new()]
	for i in mats.size():
		var m: Material = mats[i]
		# every material on two shapes, and the basic lit ones on all of them
		var shapes: Array = meshes if i < 2 else [meshes[i % meshes.size()], meshes[(i + 3) % meshes.size()]]
		for mesh: Mesh in shapes:
			_build_queue.append(_add_prim.bind(mesh, m))


func _add_prim(mesh: Mesh, m: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	_place(mi)
