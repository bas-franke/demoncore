extends Node
## Art-style audit (res://tools/style_audit.tscn): loads main.tscn (any map via --map=<id>), lets it
## run for --audit-time seconds, then lists every visible mesh whose material is off the Art
## pipeline: opaque lit StandardMaterial3D, legacy Toon shaders, or no material at all. Glows
## (unshaded / additive / transparent StandardMaterial3D) and custom shaders are only counted.
##   godot --path . res://tools/style_audit.tscn -- --map=sunlit_citadel --audit-time=8 [--audit-all]
##   godot --path . res://tools/style_audit.tscn -- --scene=res://scenes/basecamp/basecamp.tscn
## Windowed or headless both work (it only inspects resources).

## --scene=res://... audits another scene instead (e.g. scenes/basecamp/basecamp.tscn).
const MAIN_SCENE := "res://scenes/main.tscn"

var _t := 0.0
var _audit_time := 8.0
var _done := false
## --audit-all: list every category by owner, not just the off-pipeline ones.
var _verbose := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-time="):
			_audit_time = arg.substr(13).to_float()
		elif arg == "--audit-all":
			_verbose = true
	var scene_path := MAIN_SCENE
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			scene_path = arg.substr(8)
	add_child(load(scene_path).instantiate())


func _process(delta: float) -> void:
	if get_tree().paused and Dialogue.is_active():
		get_tree().paused = false
	_t += delta
	if _t >= _audit_time and not _done:
		_done = true
		_audit()
		get_tree().quit()


func _audit() -> void:
	var counts := {}  # category -> int
	var offenders := {}  # "category | where" -> int
	_scan(get_tree().root, counts, offenders)
	print("style_audit: categories")
	for k in counts:
		print("  %-28s %d" % [k, counts[k]])
	print("style_audit: off-pipeline meshes (category | owner script / path)")
	var keys := offenders.keys()
	keys.sort()
	for k in keys:
		print("  %4d  %s" % [offenders[k], k])


func _scan(n: Node, counts: Dictionary, offenders: Dictionary) -> void:
	if n is GeometryInstance3D and not n is GPUParticles3D and not n is CPUParticles3D \
			and (n as Node3D).is_visible_in_tree():
		for m in _materials(n as GeometryInstance3D):
			var cat := _category(m)
			counts[cat] = int(counts.get(cat, 0)) + 1
			if cat in ["std_lit_opaque", "toon", "none"] or _verbose:
				var key := "%s | %s" % [cat, _where(n)]
				offenders[key] = int(offenders.get(key, 0)) + 1
	for c in n.get_children():
		_scan(c, counts, offenders)


func _materials(g: GeometryInstance3D) -> Array:
	if g.material_override:
		return [g.material_override]
	var out := []
	var mesh: Mesh = null
	if g is MeshInstance3D:
		mesh = (g as MeshInstance3D).mesh
	elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh:
		mesh = (g as MultiMeshInstance3D).multimesh.mesh
	if mesh == null:
		return out
	for i in mesh.get_surface_count():
		var m: Material = null
		if g is MeshInstance3D:
			m = (g as MeshInstance3D).get_surface_override_material(i)
		if m == null:
			m = mesh.surface_get_material(i)
		out.append(m)
	return out


func _category(m: Material) -> String:
	if m == null:
		return "none"
	if m is ShaderMaterial:
		var s := (m as ShaderMaterial).shader
		if s == null:
			return "none"
		if s == Art.LIT:
			return "art_lit"
		if s == Art.LIT_STATIC:
			return "art_static"
		if s.resource_path.contains("toon"):
			return "toon"
		return "shader:" + s.resource_path.get_file()
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		if b.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED or b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
				or b.blend_mode != BaseMaterial3D.BLEND_MODE_MIX:
			return "std_glow"
		return "std_lit_opaque"
	return "other"


## The two nearest ancestors with a script (who built it) plus the node name.
func _where(n: Node) -> String:
	var names: Array[String] = []
	var p := n.get_parent()
	while p and names.size() < 2:
		if p.get_script():
			names.append((p.get_script() as Script).resource_path.get_file())
		p = p.get_parent()
	# Strip auto-generated numbering so duplicates group together.
	var nm := String(n.name).rstrip("0123456789@").trim_suffix("_")
	return "%s :: %s" % [" < ".join(names), nm]
