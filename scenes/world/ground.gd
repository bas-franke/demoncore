extends MeshInstance3D
## Keeps the ground plane under the player. The shader works in world space, so the pattern doesn't slide.
## Also feeds the shader its baked detail textures (tools/build_ground_textures.gd) and the sun
## direction (for the contact shadows), and exposes `wetness` for a weather system:
##   get_tree().get_first_node_in_group(&"ground").wetness = 0.8

const NOISE_TEX := preload("res://assets/textures/ground_noise.png")
const STONE_TEX := preload("res://assets/textures/ground_stone.png")
const SOIL_TEX := preload("res://assets/textures/ground_soil.png")

## 0 = dry, 1 = soaked (bigger puddles, darker glossy stone and soil).
var wetness: float = -1.0:
	set(v):
		wetness = clampf(v, 0.0, 1.0)
		if _mat:
			_mat.set_shader_parameter(&"wetness", wetness)

var _mat: ShaderMaterial
var _sun: DirectionalLight3D


func _ready() -> void:
	add_to_group(&"ground")
	_mat = get_active_material(0) as ShaderMaterial
	if _mat:
		if _mat.get_shader_parameter(&"noise_tex") == null:
			_mat.set_shader_parameter(&"noise_tex", NOISE_TEX)
		if _mat.get_shader_parameter(&"stone_tex") == null:
			_mat.set_shader_parameter(&"stone_tex", STONE_TEX)
		if _mat.get_shader_parameter(&"soil_tex") == null:
			_mat.set_shader_parameter(&"soil_tex", SOIL_TEX)
		if wetness >= 0.0:
			_mat.set_shader_parameter(&"wetness", wetness)
	_sun = _find_sun(get_tree().current_scene if get_tree().current_scene else get_parent())


func _find_sun(n: Node) -> DirectionalLight3D:
	if n is DirectionalLight3D and (n as DirectionalLight3D).visible:
		return n
	for c in n.get_children():
		var s := _find_sun(c)
		if s:
			return s
	return null


func _physics_process(_delta: float) -> void:
	if Game.player:
		var p := Game.player.global_position
		global_position = Vector3(p.x, 0.0, p.z)
	if _mat and is_instance_valid(_sun):
		# light travels along -Z of the light's basis; the shader wants the direction toward the sun
		_mat.set_shader_parameter(&"sun_dir", _sun.global_basis.z.normalized())
