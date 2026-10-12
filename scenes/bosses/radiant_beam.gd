class_name RadiantBeam
extends Node3D
## The Herald's "Radiant Sweep" beam: a shaft of light from the halo down to a point on the ground,
## a burning strip along the ground beneath it and a glare where it lands. World space
## (top_level); the boss calls aim() every frame while it is visible.

var _core: MeshInstance3D
var _core_mat: StandardMaterial3D
var _shell: MeshInstance3D
var _shell_mat: StandardMaterial3D
var _strip: MeshInstance3D
var _strip_mat: StandardMaterial3D
var _glare: MeshInstance3D
var _glare_mat: StandardMaterial3D
var _light: OmniLight3D
var _t := 0.0


func _init() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	visible = false


func _ready() -> void:
	_core = HolyFX.glow_part(self, Art.cylinder(), Art.HOLY_WHITE, 2.5)
	_core_mat = _core.material_override as StandardMaterial3D
	_shell = HolyFX.glow_part(self, Art.cylinder(), Art.HOLY, 0.9)
	_shell_mat = _shell.material_override as StandardMaterial3D
	_strip = HolyFX.glow_part(self, Art.box(), Art.HOLY, 1.4)
	_strip_mat = _strip.material_override as StandardMaterial3D
	_glare = HolyFX.glow_part(self, Art.sphere(), Art.HOLY_WHITE, 1.8)
	_glare_mat = _glare.material_override as StandardMaterial3D
	_light = Art.light(self, Art.HOLY, 0.0, 7.0)


func _process(delta: float) -> void:
	_t += delta


## Beam from `origin` (halo) to `ground_end` (y ignored, placed on the ground), drawn with
## `width` (ground half-width) and `intensity` 0..1 (0.15 = faint warning line, 1 = full beam).
## `strip_from` is where the burning ground strip starts (usually the boss's feet).
func aim(origin: Vector3, strip_from: Vector3, ground_end: Vector3, width: float, intensity: float) -> void:
	visible = intensity > 0.001
	if not visible:
		return
	var end := Vector3(ground_end.x, 0.05, ground_end.z)
	var flicker := 1.0 + 0.06 * sin(_t * 41.0) + 0.04 * sin(_t * 23.0)
	var w := width * (0.35 + 0.65 * intensity) * flicker
	_place_cylinder(_core, origin, end, w * 0.45)
	_place_cylinder(_shell, origin, end, w * 1.1)
	_core_mat.albedo_color = HolyFX.scaled(Art.HOLY_WHITE, 2.5 * intensity)
	_shell_mat.albedo_color = HolyFX.scaled(Art.HOLY, 0.9 * intensity * intensity)
	# Ground strip from the boss to the end point.
	var a := Vector3(strip_from.x, 0.06, strip_from.z)
	var along := end - a
	along.y = 0.0
	var l := along.length()
	if l > 0.01:
		var dir := along / l
		var side := Vector3(-dir.z, 0.0, dir.x)
		_strip.global_transform = Transform3D(Basis(side * w, Vector3.UP * 0.02, dir * l), a + along * 0.5)
		_strip.visible = true
	else:
		_strip.visible = false
	_strip_mat.albedo_color = HolyFX.scaled(Art.HOLY, 1.4 * intensity)
	_glare.global_transform = Transform3D(Basis.from_scale(Vector3(w * 2.4, w * 1.0, w * 2.4) * flicker), end)
	_glare_mat.albedo_color = HolyFX.scaled(Art.HOLY_WHITE, 1.8 * intensity)
	_light.global_position = end + Vector3(0.0, 0.8, 0.0)
	_light.light_energy = 4.0 * intensity


func hide_now() -> void:
	visible = false
	if _light:
		_light.light_energy = 0.0


## Orients a unit (height 1, along +Y) cylinder between `a` and `b` with radius scale `r`.
static func _place_cylinder(mi: MeshInstance3D, a: Vector3, b: Vector3, r: float) -> void:
	var up := b - a
	var span := up.length()
	if span < 0.001:
		mi.visible = false
		return
	mi.visible = true
	var y := up / span
	var ref := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := y.cross(ref).normalized()
	var z := x.cross(y).normalized()
	mi.global_transform = Transform3D(Basis(x * r, y * span, z * r), (a + b) * 0.5)
