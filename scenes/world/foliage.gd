extends Node3D
## Ground foliage: grass tussocks (dark green / dry gold / ash-grey), ferns, brambles, leaf litter,
## exposed roots, toadstools, pale and blood-red wildflowers and marsh reeds (Blender models in
## res://assets/models/foliage/, scripts in tools/blender/models/foliage/).
##
## Streams square chunks around the player like decor.gd: one MultiMeshInstance3D per (plant type,
## chunk), so a chunk costs at most one draw call per type and material. Placement is deterministic
## per world position (no seed), and follows the ground shader's own soil layout (FoliageField, a CPU
## port of ground.gdshader): grass stays off the flagstone roads and plazas (sparse tufts on the dirt
## verges), dry gold grass in the sun-dried drifts, ash grass and red lilies in the ash fields, ferns
## and toadstools on the moss cushions, reeds around the muddy hollows, litter where leaves fall. A
## cluster noise breaks everything into natural patches and clearings.
##
## Chunk contents are computed on WorkerThreadPool threads; the main thread only uploads the
## MultiMesh buffers. Wind sway, push-away bending around the player / enemies, grow-in and the edge
## fade all run in res://shaders/foliage.gdshader.

const CHUNK := 12.0
## Loaded rectangle around the player (metres). The camera looks north (-Z), so more is kept ahead.
const LOAD_HALF_X := 27.0
const LOAD_AHEAD := 22.0
const LOAD_BEHIND := 13.0
## Extra margin before chunks are freed (hysteresis).
const FREE_MARGIN := 8.0
## Candidate grid spacing (m): at most one plant per cell (+ an occasional ground-cover overlay).
const CELL := 0.62
const MAX_TASKS := 3
const GROW_TIME := 0.6
const MAX_PUSHERS := 8
const PUSH_RANGE := 16.0
const SHADER := preload("res://shaders/foliage.gdshader")

## Plant types. scale = (min, max) uniform scale; sway_h / sway = shader bend params;
## up = normal bend toward +Y; shadow = cast shadows; sheen = light through leaves.
const TYPES := {
	&"grass_green": {"scale": Vector2(0.85, 1.35), "sway_h": 0.45, "sway": 1.0, "up": 0.6, "shadow": true, "sheen": 0.6},
	&"grass_dry": {"scale": Vector2(0.85, 1.4), "sway_h": 0.5, "sway": 1.0, "up": 0.6, "shadow": true, "sheen": 0.7},
	&"grass_ash": {"scale": Vector2(0.8, 1.25), "sway_h": 0.45, "sway": 0.8, "up": 0.55, "shadow": true, "sheen": 0.4},
	&"fern": {"scale": Vector2(0.8, 1.3), "sway_h": 0.45, "sway": 0.55, "up": 0.45, "shadow": true, "sheen": 0.6},
	&"bramble": {"scale": Vector2(0.8, 1.25), "sway_h": 0.6, "sway": 0.3, "up": 0.3, "shadow": true, "sheen": 0.3},
	&"leaf_litter": {"scale": Vector2(0.8, 1.4), "sway_h": 1.0, "sway": 0.0, "up": 0.35, "shadow": false, "sheen": 0.3},
	&"roots": {"scale": Vector2(0.8, 1.3), "sway_h": 1.0, "sway": 0.0, "up": 0.15, "shadow": true, "sheen": 0.1},
	&"toadstools": {"scale": Vector2(0.8, 1.5), "sway_h": 1.0, "sway": 0.0, "up": 0.2, "shadow": false, "sheen": 0.35},
	&"flowers_pale": {"scale": Vector2(0.85, 1.3), "sway_h": 0.35, "sway": 1.3, "up": 0.5, "shadow": false, "sheen": 0.7},
	&"flowers_red": {"scale": Vector2(0.9, 1.3), "sway_h": 0.4, "sway": 1.2, "up": 0.45, "shadow": false, "sheen": 0.7},
	&"reeds": {"scale": Vector2(0.85, 1.25), "sway_h": 1.2, "sway": 1.1, "up": 0.5, "shadow": true, "sheen": 0.6},
}

@export var enabled := true
## Global density multiplier (performance / art knob).
@export_range(0.0, 2.0) var density := 1.0
@export var wind_strength := 1.0

var _type_names: Array[StringName] = []
var _meshes := {}  # StringName -> ArrayMesh (with foliage materials)
var _materials: Array[ShaderMaterial] = []
var _chunks := {}  # Vector2i -> Node3D
var _grow := {}  # Node3D -> float
var _pending := {}  # Vector2i -> {task, result}
var _noise_img: Image
var _wind_dir := Vector2(0.87, 0.5)
var _push_timer := 0
var _push := PackedVector4Array()


func _ready() -> void:
	for k: StringName in TYPES:
		_type_names.append(k)
		_meshes[k] = _load_mesh(k)
	_push.resize(MAX_PUSHERS)
	var ff := FoliageField.new()
	ff._load_noise()
	_noise_img = ff._noise


func _exit_tree() -> void:
	for k: Vector2i in _pending:
		WorkerThreadPool.wait_for_task_completion(_pending[k]["task"])
	_pending.clear()


# ---------------------------------------------------------------- assets

func _load_mesh(kind: StringName) -> ArrayMesh:
	var path := "res://assets/models/foliage/%s.glb" % kind
	var ps := load(path) as PackedScene
	if ps == null:
		push_warning("Foliage: missing %s" % path)
		return null
	var root := ps.instantiate() as Node3D
	var mi := _find_mesh(root, Transform3D.IDENTITY)
	var out: ArrayMesh = null
	if mi.size() == 2:
		var src := mi[0] as MeshInstance3D
		var xf: Transform3D = mi[1]
		out = ArrayMesh.new()
		var cfg: Dictionary = TYPES[kind]
		for s in src.mesh.get_surface_count():
			var st := SurfaceTool.new()
			st.append_from(src.mesh, s, xf)
			st.commit(out)
			var sm := src.get_active_material(s) as BaseMaterial3D
			out.surface_set_material(out.get_surface_count() - 1, _make_material(sm, cfg))
	root.free()
	return out


func _find_mesh(n: Node, xf: Transform3D) -> Array:
	var cxf := xf
	if n is Node3D:
		cxf = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		return [n, cxf]
	for c in n.get_children():
		var r := _find_mesh(c, cxf)
		if r.size() == 2:
			return r
	return []


func _make_material(src: BaseMaterial3D, cfg: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	var col := Color(0.3, 0.33, 0.15)
	var rough := 0.8
	if src:
		col = src.albedo_color
		rough = src.roughness
	m.set_shader_parameter(&"albedo", col)
	m.set_shader_parameter(&"roughness", rough)
	m.set_shader_parameter(&"sway_height", cfg["sway_h"])
	m.set_shader_parameter(&"sway_strength", cfg["sway"])
	m.set_shader_parameter(&"normal_up", cfg["up"])
	m.set_shader_parameter(&"sheen", cfg["sheen"])
	m.set_shader_parameter(&"fade_half", Vector2(LOAD_HALF_X - 1.0, minf(LOAD_AHEAD, LOAD_BEHIND + 6.0)))
	if cfg["sway"] <= 0.0:
		m.set_shader_parameter(&"base_dark", 0.25)
		m.set_shader_parameter(&"tip_light", 0.0)
		m.set_shader_parameter(&"ao_height", 0.12)
	_materials.append(m)
	return m


# ---------------------------------------------------------------- streaming

func _focus() -> Vector3:
	if is_instance_valid(Game.player):
		return Game.player.global_position
	return Vector3.ZERO


func _process(delta: float) -> void:
	if not enabled:
		return
	var f := _focus()
	_stream(f)
	_collect_finished()
	# grow-in of fresh chunks
	for c: Node3D in _grow.keys():
		if not is_instance_valid(c):
			_grow.erase(c)
			continue
		var g: float = minf(1.0, _grow[c] + delta / GROW_TIME)
		_grow[c] = g
		var e := 1.0 - pow(1.0 - g, 3.0)
		for mmi in c.get_children():
			(mmi as GeometryInstance3D).set_instance_shader_parameter(&"grow", e)
		if g >= 1.0:
			_grow.erase(c)
	_update_shader_globals(f)


func _wanted_rect(f: Vector3, margin: float) -> Rect2i:
	var x0 := floori((f.x - LOAD_HALF_X - margin) / CHUNK)
	var x1 := floori((f.x + LOAD_HALF_X + margin) / CHUNK)
	var z0 := floori((f.z - LOAD_AHEAD - margin) / CHUNK)
	var z1 := floori((f.z + LOAD_BEHIND + margin) / CHUNK)
	return Rect2i(x0, z0, x1 - x0 + 1, z1 - z0 + 1)


func _stream(f: Vector3) -> void:
	var keep := _wanted_rect(f, FREE_MARGIN)
	for k: Vector2i in _chunks.keys():
		if not keep.has_point(k):
			(_chunks[k] as Node3D).queue_free()
			_grow.erase(_chunks[k])
			_chunks.erase(k)
	var want := _wanted_rect(f, 0.0)
	var fc := Vector2(f.x, f.z) / CHUNK
	var missing: Array[Vector2i] = []
	for z in range(want.position.y, want.end.y):
		for x in range(want.position.x, want.end.x):
			var k := Vector2i(x, z)
			if not _chunks.has(k) and not _pending.has(k):
				missing.append(k)
	if missing.is_empty():
		return
	missing.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (Vector2(a) + Vector2(0.5, 0.5)).distance_squared_to(fc) < (Vector2(b) + Vector2(0.5, 0.5)).distance_squared_to(fc))
	for k in missing:
		if _pending.size() >= MAX_TASKS:
			break
		var job := {"result": null}
		job["task"] = WorkerThreadPool.add_task(_compute_chunk.bind(k, job), false, "foliage chunk")
		_pending[k] = job


func _collect_finished() -> void:
	var keep := _wanted_rect(_focus(), FREE_MARGIN)
	for k: Vector2i in _pending.keys():
		var job: Dictionary = _pending[k]
		if not WorkerThreadPool.is_task_completed(job["task"]):
			continue
		WorkerThreadPool.wait_for_task_completion(job["task"])
		_pending.erase(k)
		if keep.has_point(k) and not _chunks.has(k) and job["result"] != null:
			_apply_chunk(k, job["result"])


## Rebuilds everything (e.g. after changing `density`).
func rebuild() -> void:
	for k: Vector2i in _chunks:
		(_chunks[k] as Node3D).queue_free()
	_chunks.clear()
	_grow.clear()


# ---------------------------------------------------------------- placement (worker thread)

static func _hash01(a: int, b: int, c: int) -> float:
	var h := hash(Vector3i(a, b, c))
	return float(h & 0xFFFFFF) / float(0xFFFFFF)


## Runs on a worker thread: returns {type: PackedFloat32Array (16 floats per instance)}.
func _compute_chunk(k: Vector2i, job: Dictionary) -> void:
	var ff := FoliageField.new()
	ff._noise = _noise_img
	ff._nw = _noise_img.get_width()
	ff._nh = _noise_img.get_height()
	var cluster := FastNoiseLite.new()
	cluster.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cluster.seed = 1337
	cluster.frequency = 0.09
	var patch := FastNoiseLite.new()
	patch.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	patch.seed = 4242
	patch.frequency = 0.035

	var out := {}
	for t in _type_names:
		out[t] = PackedFloat32Array()
	var n := int(round(CHUNK / CELL))
	var ox := float(k.x) * CHUNK
	var oz := float(k.y) * CHUNK
	var dens := density
	for iz in n:
		for ix in n:
			var gx := k.x * n + ix
			var gz := k.y * n + iz
			var r1 := _hash01(gx, gz, 1)
			var r2 := _hash01(gx, gz, 2)
			var x := ox + (float(ix) + 0.1 + 0.8 * r1) * CELL
			var z := oz + (float(iz) + 0.1 + 0.8 * r2) * CELL
			var pick := _hash01(gx, gz, 3)
			var roll := _hash01(gx, gz, 4)
			var zn := ff.zones(x, z)
			var relief: float = zn["relief"]
			if relief < 0.2:
				continue  # standing water
			var cl := cluster.get_noise_2d(x, z)  # -1..1, small patches
			var pt := patch.get_noise_2d(x, z)  # -1..1, big meadows vs clearings
			var cover := clampf(0.55 + 0.55 * cl + 0.35 * pt, 0.0, 1.0)
			var ash: float = zn["ash"]
			var dirt: float = zn["dirt"]
			var moss: float = zn["moss"]
			var dry: float = zn["dry"]
			var lush: float = zn["lush"]
			var mud: float = zn["mud"]
			var marsh := 1.0 - FoliageField._ss(0.3, 0.42, relief)  # 1 in the wet hollows
			cover *= 1.0 - dirt * 0.65
			cover *= 1.0 - marsh * 0.35
			cover *= dens
			if roll > cover * 0.95 and roll > 0.08 * dens:
				continue
			var st := ff.stone(x, z)
			if st.x > 0.01:
				continue
			var verge := st.y
			if verge > 0.0 and _hash01(gx, gz, 5) < verge * 0.7:
				continue
			# type weights
			var w := {}
			w[&"grass_green"] = (0.25 + lush) * (1.0 - dry * 0.8) * (1.0 - ash) * (1.0 - marsh * 0.7)
			w[&"grass_dry"] = (0.15 + dry * 2.0 + verge * 0.6) * (1.0 - ash * 0.8) * (1.0 - marsh * 0.8)
			w[&"grass_ash"] = ash * 2.2 + dirt * 0.25
			w[&"fern"] = moss * 1.4 * (1.0 - ash) * (1.0 - dry * 0.7) + lush * 0.06
			w[&"bramble"] = (0.05 + 0.25 * maxf(cl - 0.45, 0.0)) * (1.0 - ash * 0.5) * (1.0 - marsh)
			w[&"leaf_litter"] = 0.06 + float(zn["leaf"]) * 0.35 + dirt * 0.3
			w[&"roots"] = 0.025 + dirt * 0.06
			w[&"toadstools"] = moss * 0.25 + lush * 0.03
			var bloom := maxf(cluster.get_noise_2d(x * 2.3 + 500.0, z * 2.3), 0.0)
			w[&"flowers_pale"] = lush * bloom * 0.9 * (1.0 - ash)
			w[&"flowers_red"] = (dry * 0.4 + ash * 0.7) * bloom * bloom * 1.2
			w[&"reeds"] = (marsh * 3.5 + mud * 1.5) * (1.0 - ash)
			var total := 0.0
			for t: StringName in w:
				total += w[t]
			if total <= 0.0001:
				continue
			var acc := pick * total
			var kind: StringName = &"grass_green"
			for t: StringName in w:
				acc -= w[t]
				if acc <= 0.0:
					kind = t
					break
			_emit(out[kind], kind, x, z, gx, gz, cl, lush, dry, ash)
	job["result"] = out


func _emit(buf: PackedFloat32Array, kind: StringName, x: float, z: float, gx: int, gz: int, cl: float,
		lush: float, dry: float, ash: float) -> void:
	var cfg: Dictionary = TYPES[kind]
	var sr: Vector2 = cfg["scale"]
	var r := _hash01(gx, gz, 6)
	var s := lerpf(sr.x, sr.y, r * r) * (0.9 + 0.2 * clampf(cl, -1.0, 1.0))
	var yaw := _hash01(gx, gz, 7) * TAU
	var tilt := (_hash01(gx, gz, 8) - 0.5) * 0.25
	var sy := s * (0.85 + 0.3 * _hash01(gx, gz, 9))
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)
	b = b.scaled_local(Vector3(s, sy, s))
	var sink := -0.02 * s
	# 3x4 row-major transform
	buf.append_array([b.x.x, b.y.x, b.z.x, x, b.x.y, b.y.y, b.z.y, sink, b.x.z, b.y.z, b.z.z, z])
	# tint: brightness jitter + drift toward the soil zone colours
	var br := 0.82 + 0.36 * _hash01(gx, gz, 10)
	var tint_r := br
	var tint_g := br
	var tint_b := br
	if kind == &"grass_green" or kind == &"fern":
		tint_r *= 1.0 + dry * 0.35 - lush * 0.05
		tint_g *= 1.0 + dry * 0.12
		tint_b *= 1.0 - dry * 0.2
	elif kind == &"grass_dry":
		tint_r *= 1.0 - lush * 0.12
		tint_b *= 1.0 + lush * 0.05
	if ash > 0.0 and kind != &"grass_ash":
		var a := ash * 0.6
		var grey := (tint_r + tint_g + tint_b) / 3.0
		tint_r = lerpf(tint_r, grey * 1.1, a)
		tint_g = lerpf(tint_g, grey * 1.1, a)
		tint_b = lerpf(tint_b, grey * 1.1, a)
	buf.append_array([tint_r, tint_g, tint_b, _hash01(gx, gz, 11)])


# ---------------------------------------------------------------- chunk nodes (main thread)

func _apply_chunk(k: Vector2i, data: Dictionary) -> void:
	var chunk := Node3D.new()
	chunk.name = "Foliage_%d_%d" % [k.x, k.y]
	var aabb := AABB(Vector3(float(k.x) * CHUNK - 1.5, -0.2, float(k.y) * CHUNK - 1.5),
			Vector3(CHUNK + 3.0, 2.2, CHUNK + 3.0))
	for t: StringName in data:
		var buf: PackedFloat32Array = data[t]
		@warning_ignore("integer_division")  # intentional truncation
		var count := buf.size() / 16
		if count == 0 or _meshes.get(t) == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _meshes[t]
		mm.instance_count = count
		mm.buffer = buf
		mm.custom_aabb = aabb
		var mmi := MultiMeshInstance3D.new()
		mmi.name = String(t)
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if TYPES[t]["shadow"] \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mmi.set_instance_shader_parameter(&"grow", 0.0)
		chunk.add_child(mmi)
	add_child(chunk)
	_chunks[k] = chunk
	_grow[chunk] = 0.0


# ---------------------------------------------------------------- per-frame shader inputs

func _update_shader_globals(f: Vector3) -> void:
	_push_timer -= 1
	if _push_timer <= 0:
		_push_timer = 2
		_gather_pushers(f)
	for m in _materials:
		m.set_shader_parameter(&"fade_center", f)
		m.set_shader_parameter(&"pushers", _push)
		m.set_shader_parameter(&"wind_strength", wind_strength)
		m.set_shader_parameter(&"wind_dir", _wind_dir)


func _gather_pushers(f: Vector3) -> void:
	for i in MAX_PUSHERS:
		_push[i] = Vector4.ZERO
	var slot := 0
	if is_instance_valid(Game.player):
		var p := Game.player.global_position
		_push[0] = Vector4(p.x, p.y, p.z, 0.9)
		slot = 1
	var best: Array = []
	var r2 := PUSH_RANGE * PUSH_RANGE
	for n in Perf.enemies():
		var e := n as Node3D
		if e == null:
			continue
		var d := e.global_position.distance_squared_to(f)
		if d < r2:
			best.append([d, e.global_position])
	if best.size() > MAX_PUSHERS - slot:
		best.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for item in best:
		if slot >= MAX_PUSHERS:
			break
		var p: Vector3 = item[1]
		_push[slot] = Vector4(p.x, p.y, p.z, 0.8)
		slot += 1
