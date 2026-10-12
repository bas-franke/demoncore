class_name AtmoHubDressing
extends Node3D
## Basecamp Hell's extra atmosphere, added by the AtmoRig when the scene has a node in group
## &"basecamp". Layout comes from HubScenery's constants (read by name, no class dependency), so it
## follows whatever the Basecamp role moves around:
##   - lava bounce: a low, smouldering uplight under each merchant from the nearest lava edge
##   - warm pools: a soft firelight pool in front of each merchant's stall (and the gate)
##   - heat haze: refraction strips shimmering over the lava sea on all four sides, and a puff
##     above the bonfire
## Ash fall / embers come from the basecamp_hell preset's weather. Quality: Low keeps only the
## warm pools; haze needs Medium (AtmoHeat's rule).

const HAZE_SHADER := preload("res://shaders/atmo/heat_haze.gdshader")
const MERCHANTS: Array[String] = ["SMITH", "OCCULT", "BROKER", "CARTO"]
## Lava surface height (HubScenery puts the sea at y = -1.6); strips hover just above it.
const HAZE_Y := -1.35

var _bounce: Array[Light3D] = []
var _pools: Array[Light3D] = []
var _haze: Array[MeshInstance3D] = []


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_build()
	var atmo := get_node_or_null(^"/root/Atmosphere")
	set_quality(int(atmo.call(&"quality")) if atmo else 2)


func set_quality(tier: int) -> void:
	for l in _bounce:
		l.visible = tier >= 1
	for h in _haze:
		h.visible = tier >= 1


func _build() -> void:
	var c := _layout()
	var x0: float = c.get("X0", -15.0)
	var x1: float = c.get("X1", 15.0)
	var z0: float = c.get("Z0", -13.0)
	var z1: float = c.get("Z1", 11.0)
	var fire: Vector3 = c.get("FIRE", Vector3(0, 0, 1))
	for key in MERCHANTS:
		if not c.has(key):
			continue
		var at: Vector3 = c[key]
		# Nearest plateau edge: the lava glow climbs from there.
		var to_edge := Vector3(-1, 0, 0)
		var best := at.x - x0
		for cand: Array in [[x1 - at.x, Vector3(1, 0, 0)], [at.z - z0, Vector3(0, 0, -1)], [z1 - at.z, Vector3(0, 0, 1)]]:
			if float(cand[0]) < best:
				best = cand[0]
				to_edge = cand[1]
		# Out at the lava's edge and below the floor: a raking uplight, not a lamp at their feet.
		_bounce.append(_light(at + to_edge * 3.2 + Vector3(0, -0.5, 0), Color(1.0, 0.3, 0.07), 0.9, 6.0,
				HellfireLight.Style.EMBER))
		var to_fire := (fire - at).normalized() if fire.distance_to(at) > 0.1 else Vector3.BACK
		_pools.append(_light(at + to_fire * 2.4 + Vector3(0, 2.6, 0), Color(1.0, 0.62, 0.32), 0.55, 4.5,
				HellfireLight.Style.FIRE))
	if c.has("GATE"):
		_pools.append(_light((c["GATE"] as Vector3) + Vector3(0, 2.6, 2.2), Color(1.0, 0.45, 0.2), 0.7, 5.5,
				HellfireLight.Style.PULSE))
	# Heat haze over the lava on every side of the plateau, and above the bonfire.
	var strip := ShaderMaterial.new()
	strip.shader = HAZE_SHADER
	strip.set_shader_parameter(&"billboard", false)
	strip.set_shader_parameter(&"strength", 1.4)
	var w := x1 - x0 + 14.0
	var d := z1 - z0 + 14.0
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	_haze_plane(strip, Vector3(cx, HAZE_Y, z1 + 3.5), Vector2(w, 6.0))
	_haze_plane(strip, Vector3(cx, HAZE_Y, z0 - 3.5), Vector2(w, 6.0))
	_haze_plane(strip, Vector3(x0 - 3.5, HAZE_Y, cz), Vector2(6.0, d))
	_haze_plane(strip, Vector3(x1 + 3.5, HAZE_Y, cz), Vector2(6.0, d))
	var puff := ShaderMaterial.new()
	puff.shader = HAZE_SHADER
	puff.set_shader_parameter(&"strength", 1.2)
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var mi := _haze_mesh(q, puff)
	mi.position = fire + Vector3(0, 1.8, 0)
	mi.scale = Vector3.ONE * 3.0


## HubScenery's layout constants (X0, X1, Z0, Z1, FIRE, GATE, SMITH, ...), {} if not found.
func _layout() -> Dictionary:
	var camp := get_tree().get_first_node_in_group(&"basecamp")
	var sc: Variant = camp.get(&"scenery") if camp else null
	var script: Script = (sc as Object).get_script() if sc is Object else null
	if script == null and camp:
		script = camp.get_script()  # older layout: constants on Basecamp itself
	return script.get_script_constant_map() if script else {}


func _light(at: Vector3, color: Color, energy: float, rng: float, style: int) -> Light3D:
	var l := HellfireLight.new()
	l.style = style as HellfireLight.Style
	l.base_energy = energy
	l.light_color = color
	l.omni_range = rng
	l.omni_attenuation = 1.2
	l.light_specular = 0.2
	l.flicker_amount = 0.8
	l.position = at
	add_child(l)
	return l


func _haze_plane(mat: ShaderMaterial, at: Vector3, size: Vector2) -> void:
	var p := PlaneMesh.new()
	p.size = size
	var mi := _haze_mesh(p, mat)
	mi.position = at


func _haze_mesh(mesh: Mesh, mat: ShaderMaterial) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)
	_haze.append(mi)
	return mi
