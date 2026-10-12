class_name BossTelegraph
extends MeshInstance3D
## Ground sigil decal for the Herald's attacks (sector or full disc, see telegraph.gdshader).
## Lives in world space (top_level), so it can be a child of the boss (or of a hazard); call
## show_sector() every frame while the warning should be visible.

const SHADER := preload("res://scenes/bosses/telegraph.gdshader")
const GROUND_Y := 0.045

var _mat: ShaderMaterial


func _init() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	mesh = plane
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	visible = false


## Shows a sector of `radius` centered at `center`, opening along `dir` (XZ) with `half_angle`
## (radians, >= PI for a full disc). `fill` 0..1 is the charge progress.
func show_sector(center: Vector3, dir: Vector3, radius: float, half_angle: float, color: Color,
		fill: float, alpha: float = 1.0, energy: float = 1.6) -> void:
	visible = true
	var yaw := atan2(-dir.x, -dir.z) if dir.length_squared() > 0.0001 else 0.0
	var b := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(radius, 1.0, radius))
	global_transform = Transform3D(b, Vector3(center.x, GROUND_Y, center.z))
	_mat.set_shader_parameter(&"color", color)
	_mat.set_shader_parameter(&"half_angle", half_angle)
	_mat.set_shader_parameter(&"fill", fill)
	_mat.set_shader_parameter(&"alpha", alpha)
	_mat.set_shader_parameter(&"energy", energy)
	_mat.set_shader_parameter(&"edge", clampf(0.16 / maxf(radius, 0.1), 0.015, 0.2))


func show_disc(center: Vector3, radius: float, color: Color, fill: float, alpha: float = 1.0,
		energy: float = 1.6) -> void:
	show_sector(center, Vector3.FORWARD, radius, PI + 0.1, color, fill, alpha, energy)


func hide_now() -> void:
	visible = false
