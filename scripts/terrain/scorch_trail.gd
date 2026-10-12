class_name ScorchTrail
extends Node3D
## Burning cloven hoofprints behind the demon: every STRIDE metres the player walks, a print is
## stamped (alternating left / right of the path, turned to the walking direction). Fresh prints
## glow ember-hot, cool to a red rim and fade to charred marks (shaders/terrain/scorch.gdshader).
## One MultiMesh draw call, a fixed ring-buffer pool, nothing allocated per step.
##
##   add_child(ScorchTrail.new())   # anywhere in a run scene; follows the node in group "player"
##
## Added by TerrainMap on terrain maps; any map / the hub can add one too.

const SHADER := preload("res://shaders/terrain/scorch.gdshader")
const POOL := 96
## Metres walked between prints.
const STRIDE := 0.75
## Sideways offset of each hoof from the walking line.
const GAIT := 0.2
const PRINT_SIZE := Vector2(0.34, 0.42)
const HEIGHT := 0.045

@export var enabled := true
## Ground height under the prints (planar maps stay at 0).
@export var ground_y := 0.0

var _mm: MultiMesh
var _mat: ShaderMaterial
var _next := 0
var _clock := 0.0
var _last := Vector3.INF
var _walked := 0.0
var _side := 1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rng.randomize()
	var quad := QuadMesh.new()
	quad.size = PRINT_SIZE
	quad.orientation = PlaneMesh.FACE_Y
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	quad.material = _mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = quad
	_mm.instance_count = POOL
	for i in POOL:
		_mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -100, 0)))
		_mm.set_instance_custom_data(i, Color(-1000.0, 1.0, 0.0, 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# the pool spans the whole trail: never cull it by its (tiny) quad bounds
	mmi.custom_aabb = AABB(Vector3(-1e4, -10.0, -1e4), Vector3(2e4, 20.0, 2e4))
	add_child(mmi)


func _process(delta: float) -> void:
	_clock += delta
	_mat.set_shader_parameter(&"now", _clock)
	if not enabled:
		return
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if player == null or not player.visible:
		_last = Vector3.INF
		return
	var p := player.global_position
	p.y = 0.0
	if _last == Vector3.INF:
		_last = p
		return
	var step := p - _last
	var d := step.length()
	if d > 4.0:  # teleport / dash: restart the trail, no streak of prints
		_last = p
		_walked = 0.0
		return
	_walked += d
	_last = p
	if _walked < STRIDE or d < 0.0001:
		return
	_walked = 0.0
	var fwd := step / d
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	_side = -_side
	var at := p + right * GAIT * _side - fwd * 0.1
	at.y = ground_y + HEIGHT
	# quad faces +Y; its V axis (toe) must point along the walking direction
	var rot := Basis(right, Vector3.UP, -fwd).rotated(Vector3.UP, _rng.randf_range(-0.12, 0.12))
	_mm.set_instance_transform(_next, Transform3D(rot, at))
	_mm.set_instance_custom_data(_next, Color(_clock, _side, _rng.randf(), _rng.randf_range(0.8, 1.0)))
	_next = (_next + 1) % POOL
