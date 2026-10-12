class_name TerrainFoliage
extends Node3D
## Grass and flowers on a TerrainPatch's walkable ground, using the foliage worker's plant models
## (res://assets/models/foliage/<type>.glb) and shader (res://shaders/foliage.gdshader: wind, push-
## away around the player / enemies, blight withering). Static: built once with the patch, one
## MultiMeshInstance3D per (24 m tile, plant type).
##
## Placement asks the patch where plants may grow (TerrainPatch.growth_at: off paths, props, liquids
## and cliff edges), breaks it into meadows and clearings with a cluster noise and picks the plant
## type by weight from the theme's `foliage` table ({type: weight}; weights also scale density).
##
##   var f := TerrainFoliage.grow(patch, {&"grass_green": 1.0, &"flowers_pale": 0.2}, 7)

const SHADER := preload("res://shaders/foliage.gdshader")
const TILE := 24.0
## Candidate spacing (m): at most one plant per cell.
const CELL := 0.66
const MAX_PUSHERS := 8
const PUSH_RANGE := 16.0

## Per-type look, as in scenes/world/foliage.gd (scale range and the shader's bend parameters).
const TYPES := {
	&"grass_green": {"scale": Vector2(0.85, 1.35), "sway_h": 0.45, "sway": 1.0, "up": 0.6, "sheen": 0.6},
	&"grass_dry": {"scale": Vector2(0.85, 1.4), "sway_h": 0.5, "sway": 1.0, "up": 0.6, "sheen": 0.7},
	&"grass_ash": {"scale": Vector2(0.8, 1.25), "sway_h": 0.45, "sway": 0.8, "up": 0.55, "sheen": 0.4},
	&"fern": {"scale": Vector2(0.8, 1.3), "sway_h": 0.45, "sway": 0.55, "up": 0.45, "sheen": 0.6},
	&"flowers_pale": {"scale": Vector2(0.85, 1.3), "sway_h": 0.35, "sway": 1.3, "up": 0.5, "sheen": 0.7},
	&"flowers_red": {"scale": Vector2(0.9, 1.3), "sway_h": 0.4, "sway": 1.2, "up": 0.45, "sheen": 0.7},
	&"reeds": {"scale": Vector2(0.85, 1.25), "sway_h": 1.2, "sway": 1.1, "up": 0.5, "sheen": 0.6},
	&"leaf_litter": {"scale": Vector2(0.8, 1.4), "sway_h": 1.0, "sway": 0.0, "up": 0.35, "sheen": 0.3},
	&"toadstools": {"scale": Vector2(0.8, 1.5), "sway_h": 1.0, "sway": 0.0, "up": 0.2, "sheen": 0.35},
}

static var _meshes := {}  # type -> ArrayMesh (shared across patches)
static var _materials: Array[ShaderMaterial] = []

var _push := PackedVector4Array()
var _push_timer := 0
var instance_count := 0


## Builds the foliage for `patch` (already built) and adds it as its child.
static func grow(patch: TerrainPatch, table: Dictionary, seed_value: int, density: float = 1.0) -> TerrainFoliage:
	var f := TerrainFoliage.new()
	f.name = "Foliage"
	f._build(patch, table, seed_value, density)
	patch.add_child(f)
	return f


func _build(patch: TerrainPatch, table: Dictionary, seed_value: int, density: float) -> void:
	_push.resize(MAX_PUSHERS)
	var types: Array[StringName] = []
	var total := 0.0
	for k: StringName in table:
		if TYPES.has(k) and _mesh(k) != null:
			types.append(k)
			total += float(table[k])
	if types.is_empty() or total <= 0.0:
		return
	var cluster := FastNoiseLite.new()
	cluster.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cluster.seed = seed_value
	cluster.frequency = 0.09
	var meadow := FastNoiseLite.new()
	meadow.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	meadow.seed = seed_value + 17
	meadow.frequency = 0.03
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bufs := {}  # "tx|tz|type" -> PackedFloat32Array
	var half := patch.size * 0.5
	var nx := int(patch.size.x / CELL)
	var nz := int(patch.size.y / CELL)
	var coverage := clampf(total, 0.0, 1.0) * density
	for iz in nz:
		for ix in nx:
			var q := Vector2(-half.x + (float(ix) + rng.randf()) * CELL, -half.y + (float(iz) + rng.randf()) * CELL)
			var ok := patch.growth_at(q)
			if ok <= 0.0:
				rng.randf()
				continue
			var cl := cluster.get_noise_2d(q.x, q.y)
			var md := meadow.get_noise_2d(q.x, q.y)
			var cover := clampf(0.55 + 0.55 * cl + 0.4 * md, 0.0, 1.0) * ok * coverage
			if rng.randf() > cover:
				continue
			# weighted type pick; flowers bloom in the cluster peaks
			var pick := rng.randf() * total
			var kind: StringName = types[0]
			for t in types:
				var w := float(table[t])
				if String(t).begins_with("flowers"):
					w *= 0.4 + 2.0 * maxf(cl, 0.0)
				pick -= w
				if pick <= 0.0:
					kind = t
					break
			var key := "%d|%d|%s" % [floori(q.x / TILE), floori(q.y / TILE), kind]
			if not bufs.has(key):
				bufs[key] = PackedFloat32Array()
			_emit(bufs[key], kind, q, rng, patch.height_local(q))
	for key: String in bufs:
		var parts := key.split("|")
		var kind := StringName(parts[2])
		var buf: PackedFloat32Array = bufs[key]
		@warning_ignore("integer_division")
		var count := buf.size() / 16
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _mesh(kind)
		mm.instance_count = count
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%s_%s" % [kind, parts[0], parts[1]]
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # tiny plants: not worth a shadow pass
		mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mmi.visibility_range_end = 70.0
		mmi.visibility_range_end_margin = 6.0
		add_child(mmi)
		instance_count += count


## One plant: 12 floats of transform (3x4 row-major) + 4 floats custom (rgb tint, phase).
func _emit(buf: PackedFloat32Array, kind: StringName, q: Vector2, rng: RandomNumberGenerator, y: float) -> void:
	var cfg: Dictionary = TYPES[kind]
	var sr: Vector2 = cfg["scale"]
	var r := rng.randf()
	var s := lerpf(sr.x, sr.y, r * r)
	var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, (rng.randf() - 0.5) * 0.25)
	b = b.scaled_local(Vector3(s, s * (0.85 + 0.3 * rng.randf()), s))
	buf.append_array([b.x.x, b.y.x, b.z.x, q.x, b.x.y, b.y.y, b.z.y, y - 0.02 * s, b.x.z, b.y.z, b.z.z, q.y])
	var br := 0.82 + 0.36 * rng.randf()
	buf.append_array([br, br, br * (0.95 + 0.1 * rng.randf()), rng.randf()])


static func _mesh(kind: StringName) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var path := "res://assets/models/foliage/%s.glb" % kind
	var out: ArrayMesh = null
	var ps := load(path) as PackedScene if ResourceLoader.exists(path) else null
	if ps:
		var root := ps.instantiate()
		var found := _find_mesh(root, Transform3D.IDENTITY)
		if found.size() == 2:
			var src := found[0] as MeshInstance3D
			out = ArrayMesh.new()
			for si in src.mesh.get_surface_count():
				var st := SurfaceTool.new()
				st.append_from(src.mesh, si, found[1])
				st.commit(out)
				out.surface_set_material(out.get_surface_count() - 1, _material(src.get_active_material(si) as BaseMaterial3D, TYPES[kind]))
		root.free()
	_meshes[kind] = out
	return out


static func _find_mesh(n: Node, xf: Transform3D) -> Array:
	var cxf := xf * (n as Node3D).transform if n is Node3D else xf
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		return [n, cxf]
	for c in n.get_children():
		var r := _find_mesh(c, cxf)
		if r.size() == 2:
			return r
	return []


static func _material(src: BaseMaterial3D, cfg: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter(&"albedo", src.albedo_color if src else Color(0.3, 0.33, 0.15))
	m.set_shader_parameter(&"roughness", src.roughness if src else 0.8)
	m.set_shader_parameter(&"sway_height", cfg["sway_h"])
	m.set_shader_parameter(&"sway_strength", cfg["sway"])
	m.set_shader_parameter(&"normal_up", cfg["up"])
	m.set_shader_parameter(&"sheen", cfg["sheen"])
	# static field: no streaming edge, so the fade window is effectively infinite
	m.set_shader_parameter(&"fade_half", Vector2(100000.0, 100000.0))
	if float(cfg["sway"]) <= 0.0:
		m.set_shader_parameter(&"base_dark", 0.25)
		m.set_shader_parameter(&"tip_light", 0.0)
		m.set_shader_parameter(&"ao_height", 0.12)
	_materials.append(m)
	return m


# ---------------------------------------------------------------- push-away around characters

func _process(_delta: float) -> void:
	if instance_count == 0:
		return
	_push_timer -= 1
	if _push_timer > 0:
		return
	_push_timer = 2
	for i in MAX_PUSHERS:
		_push[i] = Vector4.ZERO
	var slot := 0
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	var f := player.global_position if player else Vector3.ZERO
	if player:
		_push[0] = Vector4(f.x, f.y, f.z, 0.9)
		slot = 1
	# Perf.enemies() is the shared per-frame enemy list (docs/team/performance.md); looked up by path so
	# this script also compiles in tools that run without autoloads
	var perf := get_node_or_null(^"/root/Perf")
	if perf:
		for n in perf.call(&"enemies"):
			if slot >= MAX_PUSHERS:
				break
			var e := n as Node3D
			if e and e.global_position.distance_squared_to(f) < PUSH_RANGE * PUSH_RANGE:
				var p := e.global_position
				_push[slot] = Vector4(p.x, p.y, p.z, 0.8)
				slot += 1
	for m in _materials:
		m.set_shader_parameter(&"pushers", _push)
