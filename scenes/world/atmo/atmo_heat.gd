class_name AtmoHeat
extends Node3D
## Heat haze for the Atmosphere rig: a small pool of camera-facing refraction puffs
## (shaders/atmo/heat_haze.gdshader).
##   burst(pos, radius, duration, strength)   one-shot shimmer (hellfire casts, explosions)
##   Node3Ds in group &"heat_haze_source" get a persistent puff that follows them (nearest few to
##   the player); optional metas `heat_radius` (float, default 1.5) and `heat_strength` (default 1).
## Quality: off on Low, 4 bursts / 3 sources on Medium, 10 / 6 from High up.

const SHADER := preload("res://shaders/atmo/heat_haze.gdshader")
const MAX_BURSTS := [0, 4, 10, 10]
const MAX_SOURCES := [0, 3, 6, 6]
const SOURCE_RANGE := 30.0

var quality := 2:
	set(v):
		quality = clampi(v, 0, 3)
		_resize()

var _mat: ShaderMaterial
var _bursts: Array[Dictionary] = []  # {node, age, life, peak}
var _sources: Array[MeshInstance3D] = []
var _scan_left := 0.0
var _source_nodes: Array[Node3D] = []


func _ready() -> void:
	top_level = true
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_resize()


func _process(delta: float) -> void:
	for b in _bursts:
		var mi: MeshInstance3D = b["node"]
		if not mi.visible:
			continue
		b["age"] = float(b["age"]) + delta
		var t := float(b["age"]) / float(b["life"])
		if t >= 1.0:
			mi.visible = false
			continue
		mi.set_instance_shader_parameter(&"fade", sin(PI * t) * float(b["peak"]))
	_update_sources(delta)


func burst(pos: Vector3, radius: float, duration: float, strength: float = 1.0) -> void:
	if _bursts.is_empty():
		return
	var pick: Dictionary = _bursts[0]
	for b in _bursts:
		if not (b["node"] as MeshInstance3D).visible:
			pick = b
			break
		if float(b["age"]) / float(b["life"]) > float(pick["age"]) / float(pick["life"]):
			pick = b  # all busy: reuse the one closest to done
	var mi: MeshInstance3D = pick["node"]
	mi.global_position = pos + Vector3(0.0, radius * 0.45, 0.0)
	mi.scale = Vector3.ONE * radius * 2.0
	mi.visible = true
	pick["age"] = 0.0
	pick["life"] = maxf(duration, 0.1)
	pick["peak"] = clampf(strength, 0.0, 2.0)


func _puff() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mi.mesh = q
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.extra_cull_margin = 2.0
	mi.visible = false
	add_child(mi)
	return mi


func _resize() -> void:
	if not is_inside_tree():
		return
	var nb: int = MAX_BURSTS[quality]
	while _bursts.size() > nb:
		(_bursts.pop_back()["node"] as Node).queue_free()
	while _bursts.size() < nb:
		_bursts.append({"node": _puff(), "age": 1.0, "life": 1.0, "peak": 1.0})
	var ns: int = MAX_SOURCES[quality]
	while _sources.size() > ns:
		_sources.pop_back().queue_free()
	while _sources.size() < ns:
		_sources.append(_puff())


## Persistent puffs on the nearest group &"heat_haze_source" nodes (list refreshed twice a second).
func _update_sources(delta: float) -> void:
	if _sources.is_empty():
		return
	_scan_left -= delta
	if _scan_left <= 0.0:
		_scan_left = 0.5
		var focus := (get_parent() as AtmoRig).focus_point() if get_parent() is AtmoRig else Vector3.ZERO
		_source_nodes.clear()
		for n in get_tree().get_nodes_in_group(&"heat_haze_source"):
			var n3 := n as Node3D
			if n3 and n3.is_visible_in_tree() and n3.global_position.distance_to(focus) < SOURCE_RANGE:
				_source_nodes.append(n3)
		_source_nodes.sort_custom(func(a: Node3D, b: Node3D) -> bool:
			return a.global_position.distance_squared_to(focus) < b.global_position.distance_squared_to(focus))
	for i in _sources.size():
		var mi := _sources[i]
		var src: Node3D = _source_nodes[i] if i < _source_nodes.size() else null
		mi.visible = src != null and is_instance_valid(src)
		if mi.visible:
			var r := float(src.get_meta(&"heat_radius", 1.5))
			mi.global_position = src.global_position + Vector3(0.0, r * 0.5, 0.0)
			mi.scale = Vector3.ONE * r * 2.0
			mi.set_instance_shader_parameter(&"fade", float(src.get_meta(&"heat_strength", 1.0)))
