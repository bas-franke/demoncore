class_name AtmoLightning
extends Node3D
## Lightning for the Atmosphere rig: scheduled strikes (rate per minute from the active preset) and
## on-demand ones (Atmosphere.strike_lightning). A strike is a few rapid flicker pulses that drive:
##   - a jagged, branching bolt ribbon (camera-facing quads built once per strike) for close strikes
##   - a short shadow-casting directional flash (High quality and up), a ground flash OmniLight3D
##   - an additive screen flash (CanvasLayer just above the post pass, below the UI)
##   - thunder (Sfx &"thunder" near / &"thunder_far", delayed by distance) and a camera shake for
##     close strikes. The delay timer is pausable on purpose: the flash freezes with the game, so
##     thunder heard after a menu closes stays in step with what was seen.
## Signal `struck(position, far)` is re-emitted by Atmosphere as `lightning_struck`.

signal struck(position: Vector3, far: float)

const BOLT_SHADER := preload("res://shaders/atmo/lightning_bolt.gdshader")
const BOLT_TOP := 30.0
const BOLT_SEGMENTS := 16

## Strikes per minute (set from the preset's weather.lightning every frame).
var rate := 0.0
var color := Color(0.78, 0.8, 1.0)
## Quality tier (Atmosphere.Quality): directional flash shadows from HIGH up.
var quality := 2
## Where strikes land around (the player), refreshed by the rig.
var focus := Vector3.ZERO

var _bolt_mesh: MeshInstance3D
var _bolt_mat: ShaderMaterial
var _flash_light: DirectionalLight3D
var _ground_light: OmniLight3D
var _flash_rect: ColorRect
var _rng := RandomNumberGenerator.new()
var _cd := 6.0
var _age := -1.0
var _pulses: Array[Vector3] = []  # (start, peak, decay)
var _gain := 1.0
var _bolt_active := false  # this strike drew a bolt (close strikes only)


func _ready() -> void:
	_rng.randomize()
	_bolt_mat = ShaderMaterial.new()
	_bolt_mat.shader = BOLT_SHADER
	_bolt_mesh = MeshInstance3D.new()
	_bolt_mesh.name = "Bolt"
	_bolt_mesh.top_level = true
	_bolt_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_bolt_mesh.material_override = _bolt_mat
	_bolt_mesh.visible = false
	add_child(_bolt_mesh)
	_flash_light = DirectionalLight3D.new()
	_flash_light.name = "FlashLight"
	_flash_light.visible = false
	_flash_light.light_specular = 1.2
	_flash_light.shadow_bias = 0.05
	_flash_light.shadow_normal_bias = 1.4
	_flash_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_flash_light.directional_shadow_max_distance = 45.0
	_flash_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	_flash_light.light_volumetric_fog_energy = 0.0
	add_child(_flash_light)
	_ground_light = OmniLight3D.new()
	_ground_light.name = "GroundFlash"
	_ground_light.top_level = true
	_ground_light.visible = false
	_ground_light.omni_range = 16.0
	_ground_light.omni_attenuation = 1.4
	add_child(_ground_light)
	var layer := CanvasLayer.new()
	layer.name = "LightningFlash"
	layer.layer = 0  # above the post pass (-1), below every UI layer (1+)
	add_child(layer)
	_flash_rect = ColorRect.new()
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_flash_rect.material = cm
	_flash_rect.visible = false
	layer.add_child(_flash_rect)


func _process(delta: float) -> void:
	if rate > 0.05:
		_cd -= delta
		if _cd <= 0.0:
			strike()
			_cd = _rng.randf_range(0.4, 1.6) * 60.0 / rate
	else:
		_cd = maxf(_cd, 4.0)
	if _age >= 0.0:
		_update_flash(delta)


## Fires a strike now. `at` = ground point (Vector3.INF = random around the focus); `far` 0 = right
## here (bright, loud, bolt visible) .. 1 = distant (dim flash only); < 0 = random.
## `with_sound` false = visuals only (callers with their own impact sound and shake).
func strike(at: Vector3 = Vector3.INF, far: float = -1.0, with_sound: bool = true) -> void:
	if far < 0.0:
		far = _rng.randf()
	far = clampf(far, 0.0, 1.0)
	if at == Vector3.INF:
		var ang := _rng.randf() * TAU
		var dist := lerpf(5.0, 34.0, far) + _rng.randf_range(0.0, 4.0)
		at = focus + Vector3(cos(ang), 0.0, sin(ang)) * dist
		at.y = focus.y
	_gain = lerpf(1.0, 0.35, far)
	_age = 0.0
	_pulses.clear()
	var t := 0.0
	for i in _rng.randi_range(2, 4):
		_pulses.append(Vector3(t, _rng.randf_range(0.5, 1.0), _rng.randf_range(0.03, 0.07)))
		t += _rng.randf_range(0.05, 0.13)
	_pulses.append(Vector3(t, 1.0, _rng.randf_range(0.12, 0.22)))
	_flash_light.rotation = Vector3(deg_to_rad(_rng.randf_range(-75.0, -50.0)), _rng.randf() * TAU, 0.0)
	_flash_light.shadow_enabled = quality >= 2
	_flash_light.light_color = color
	_ground_light.light_color = color
	_ground_light.global_position = at + Vector3(0.0, 2.5, 0.0)
	_flash_rect.color = Color(color.r, color.g, color.b, 0.0)
	_bolt_mat.set_shader_parameter(&"color", color)
	_bolt_active = far < 0.6
	if _bolt_active:
		_build_bolt(at)
	_bolt_mesh.visible = _bolt_active
	if with_sound:
		var delay := lerpf(0.25, 2.2, far) + _rng.randf_range(0.0, 0.3)
		get_tree().create_timer(delay, false).timeout.connect(_thunder.bind(far))
	struck.emit(at, far)


# ---------------------------------------------------------------- internals

func _update_flash(delta: float) -> void:
	_age += delta
	var v := 0.0
	var last := 0.0
	for p in _pulses:
		if _age >= p.x:
			v += p.y * exp(-(_age - p.x) / p.z)
		last = maxf(last, p.x + p.z * 6.0)
	v = minf(v, 1.3) * _gain
	if _age > last:
		v = 0.0
		_age = -1.0
		_bolt_active = false
	var on := v > 0.01
	_flash_light.visible = on
	_flash_light.light_energy = v * 3.5 * lerpf(0.5, 1.0, AtmoRig.flash_scale(self))
	_ground_light.visible = on and _gain > 0.6
	_ground_light.light_energy = v * 9.0
	_flash_rect.visible = on
	_flash_rect.color.a = v * 0.1 * AtmoRig.flash_scale(self)  # Settings.reduce_flashes: faint cue
	_bolt_mesh.visible = _bolt_active
	_bolt_mat.set_shader_parameter(&"fade", clampf(v, 0.0, 1.0))


## Builds the bolt as camera-facing ribbons: a main channel from the sky to `at` (jitter shrinking
## toward the ground) plus two or three shorter forks.
func _build_bolt(at: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	var cam_pos := cam.global_position if cam else at + Vector3(0, 20, 15)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := at + Vector3(_rng.randf_range(-6.0, 6.0), BOLT_TOP, _rng.randf_range(-8.0, 2.0))
	var pts := _jagged(top, at, BOLT_SEGMENTS, 1.6)
	_ribbon(st, pts, 0.42, 1.0, cam_pos)
	for i in _rng.randi_range(2, 3):
		var from_i := _rng.randi_range(2, BOLT_SEGMENTS - 5)
		var a: Vector3 = pts[from_i]
		var dir := (pts[mini(from_i + 3, pts.size() - 1)] - a).normalized()
		dir = (dir + Vector3(_rng.randf_range(-0.9, 0.9), 0.0, _rng.randf_range(-0.9, 0.9))).normalized()
		var b := a + dir * _rng.randf_range(4.0, 9.0)
		_ribbon(st, _jagged(a, b, 6, 0.9), 0.2, 0.55, cam_pos)
	_bolt_mesh.mesh = st.commit()
	_bolt_mesh.global_transform = Transform3D.IDENTITY


func _jagged(a: Vector3, b: Vector3, segments: int, jitter: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in segments + 1:
		var t := float(i) / float(segments)
		var p := a.lerp(b, t)
		if i > 0 and i < segments:
			var j := jitter * (1.0 - t * 0.6)
			p += Vector3(_rng.randf_range(-j, j), _rng.randf_range(-j, j) * 0.4, _rng.randf_range(-j, j))
		pts.append(p)
	return pts


func _ribbon(st: SurfaceTool, pts: PackedVector3Array, width: float, alpha: float, cam_pos: Vector3) -> void:
	for i in pts.size() - 1:
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var mid := (p0 + p1) * 0.5
		var side := (p1 - p0).cross(cam_pos - mid)
		if side.length_squared() < 0.000001:
			continue
		side = side.normalized() * width * (1.0 - 0.4 * float(i) / float(pts.size()))
		var v0 := float(i) / float(pts.size() - 1)
		var v1 := float(i + 1) / float(pts.size() - 1)
		var c := Color(1, 1, 1, alpha)
		var quad := [[p0 - side, Vector2(0, v0)], [p0 + side, Vector2(1, v0)],
				[p1 + side, Vector2(1, v1)], [p1 - side, Vector2(0, v1)]]
		for idx: int in [0, 1, 2, 0, 2, 3]:
			st.set_color(c)
			st.set_uv(quad[idx][1])
			st.add_vertex(quad[idx][0])


func _thunder(far: float) -> void:
	var vol := lerpf(-3.0, -15.0, far)
	var sfx := get_node_or_null(^"/root/Sfx")
	if sfx and sfx.has_method(&"play"):
		# Close strikes crack (thunder + impact), distant ones roll (thunder_far).
		sfx.call(&"play", &"thunder" if far < 0.55 else &"thunder_far", 0.12, vol)
		if far < 0.3:
			sfx.call(&"play", &"impact", 0.2, vol - 4.0)
	if far < 0.4 and is_inside_tree():
		get_tree().call_group(&"camera_rig", &"shake", lerpf(0.22, 0.08, far / 0.4))
