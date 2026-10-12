class_name HolyTelegraph
extends Node3D
## Ground warning drawn in light for enemy attacks: a lane (charges) or a circle (leaps, slams).
## Lives in world space (top_level); add it as a child of the enemy and call show_line() /
## show_circle() every frame while the warning should be visible, hide_now() when done.
## While visible it sits in group "danger_zones" and describes its area with contains(point),
## so bots (Autopilot) and AI can avoid it.

const GROUND_Y := 0.05

static var _plane: PlaneMesh
static var _disc: CylinderMesh
static var _ring: TorusMesh

var _band: MeshInstance3D
var _core: MeshInstance3D
var _tip: MeshInstance3D
var _disc_outer: MeshInstance3D
var _disc_fill: MeshInstance3D
var _rim: MeshInstance3D
var _t := 0.0
# Current danger area (world XZ): a lane from _from along _dir, or a circle at _from.
var _is_line := false
var _from := Vector3.ZERO
var _dir := Vector3.FORWARD
var _len := 0.0
var _rad := 0.0


func _init() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	visible = false
	if _plane == null:
		_plane = PlaneMesh.new()
		_plane.size = Vector2.ONE
		_disc = CylinderMesh.new()
		_disc.top_radius = 1.0
		_disc.bottom_radius = 1.0
		_disc.height = 0.01
		_disc.radial_segments = 40
		_disc.rings = 1
		_disc.cap_bottom = false
		_ring = TorusMesh.new()
		_ring.inner_radius = 0.93
		_ring.outer_radius = 1.0
		_ring.rings = 48
		_ring.ring_segments = 4
	_band = _make(_plane)
	_core = _make(_plane)
	_tip = _make(_disc)
	_disc_outer = _make(_disc)
	_disc_fill = _make(_disc)
	_rim = _make(_ring)


func _process(delta: float) -> void:
	_t += delta


func _make(mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_fog = true
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mi.visible = false
	add_child(mi)
	return mi


func _tint(mi: MeshInstance3D, color: Color, energy: float, alpha: float) -> void:
	mi.visible = alpha > 0.002
	(mi.material_override as StandardMaterial3D).albedo_color = \
			Color(color.r * energy, color.g * energy, color.b * energy, clampf(alpha, 0.0, 1.0))


## A lane of light from `from` along `dir` (XZ), `length` long and `width` wide. `fill` 0..1
## (wind-up progress) grows a bright core line down the lane; at 1 the lane is fully lit.
func show_line(from: Vector3, dir: Vector3, length: float, width: float, fill: float,
		color: Color = Art.HOLY) -> void:
	_show(true)
	var d := Vector3(dir.x, 0.0, dir.z)
	d = d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD
	_is_line = true
	_from = from
	_dir = d
	_len = length
	_rad = width * 0.5
	var yaw := atan2(-d.x, -d.z)
	global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(from.x, GROUND_Y, from.z))
	var f := clampf(fill, 0.0, 1.0)
	var pulse := 0.85 + 0.15 * sin(_t * 18.0)
	# Local -Z is forward.
	_band.position = Vector3(0.0, 0.0, -length * 0.5)
	_band.scale = Vector3(width, 1.0, length)
	_tint(_band, color, 1.0, (0.1 + 0.18 * f) * pulse)
	var core_len := maxf(length * f, 0.01)
	_core.position = Vector3(0.0, 0.005, -core_len * 0.5)
	_core.scale = Vector3(width * lerpf(0.12, 0.4, f), 1.0, core_len)
	_tint(_core, Art.HOLY_WHITE, 2.0, 0.35 + 0.5 * f)
	_tip.position = Vector3(0.0, 0.01, -core_len)
	_tip.scale = Vector3.ONE * width * 0.3
	_tint(_tip, Art.HOLY_WHITE, 2.5, 0.6 * f)


## A circle of light of `radius` at `center`: a bright rim, a faint disc and an inner disc that
## grows with `fill` 0..1 until it reaches the rim (the moment of impact).
func show_circle(center: Vector3, radius: float, fill: float, color: Color = Art.HOLY) -> void:
	_show(false)
	_is_line = false
	_from = center
	_rad = radius
	global_transform = Transform3D(Basis.IDENTITY, Vector3(center.x, GROUND_Y, center.z))
	var f := clampf(fill, 0.0, 1.0)
	var pulse := 0.85 + 0.15 * sin(_t * 16.0)
	_rim.scale = Vector3(radius, 0.4, radius)
	_tint(_rim, color, 2.0, (0.55 + 0.4 * f) * pulse)
	_disc_outer.scale = Vector3(radius, 1.0, radius)
	_tint(_disc_outer, color, 1.0, 0.12 * pulse)
	var r := maxf(radius * f, 0.01)
	_disc_fill.position = Vector3(0.0, 0.005, 0.0)
	_disc_fill.scale = Vector3(r, 1.0, r)
	_tint(_disc_fill, color, 1.4, 0.18 + 0.25 * f)


func hide_now() -> void:
	visible = false
	if is_in_group(&"danger_zones"):
		remove_from_group(&"danger_zones")


## True if world point `p` (XZ) lies inside the shown warning, grown by `margin`.
func contains(p: Vector3, margin: float = 0.0) -> bool:
	if not visible:
		return false
	var rel := Vector3(p.x - _from.x, 0.0, p.z - _from.z)
	if not _is_line:
		return rel.length() < _rad + margin
	var along := rel.dot(_dir)
	if along < -margin or along > _len + margin:
		return false
	return (rel - _dir * along).length() < _rad + margin


## Center of the warned area (circle center or lane middle), for "move away from" steering.
func danger_center() -> Vector3:
	return _from + _dir * _len * 0.5 if _is_line else _from


func _show(line: bool) -> void:
	visible = true
	if not is_in_group(&"danger_zones"):
		add_to_group(&"danger_zones")
	_band.visible = line
	_core.visible = line
	_tip.visible = line
	_rim.visible = not line
	_disc_outer.visible = not line
	_disc_fill.visible = not line
