extends Node3D
## Diablo-style perspective follow camera. The rig sits on the ground at the focus point; the
## Camera3D child looks down at it from `distance` units away at `pitch_deg`.
##
## Smooth follow with a little look-ahead toward where the player is moving, plus game-feel
## motion (all scaled by Settings.screen_shake; 0 disables every camera motion below):
##   get_tree().call_group(&"camera_rig", &"shake", 0.3)          # trauma shake (0..1, stacks)
##   get_tree().call_group(&"camera_rig", &"kick", dir, 0.4)      # directional spring kick (world XZ)
##   get_tree().call_group(&"camera_rig", &"zoom_punch", -0.08)   # FOV impulse (<0 = punch in)
##   get_tree().call_group(&"camera_rig", &"set_zoom", 0.86, 2.5) # held FOV multiplier (1 = normal)
##   get_tree().call_group(&"camera_rig", &"set_focus_bias", pos, 0.35)  # lean toward a point (0 = off)
##
## Runs in _process on the player's interpolated transform (physics interpolation is on), so
## the camera itself is not physics-interpolated.

## SINBOUND: Diablo-like high angle, pulled back for a wide view of the horde
## (36 shows ~1.9x the ground area of the old 26). Keep EnemySpawner.spawn_radius off-screen if this grows.
@export var pitch_deg := 55.0
@export var distance := 36.0
@export var fov := 35.0
## Height above the ground the camera aims at (roughly a character's middle).
@export var aim_height := 0.6
@export var follow_sharpness := 7.0
## Seconds of player velocity to look ahead by.
@export var look_ahead := 0.3
@export var max_look_ahead := 2.6
@export var look_ahead_sharpness := 2.2
@export_group("Shake")
## Max positional shake (world units) at full trauma.
@export var shake_offset := 0.55
## Max roll (degrees) at full trauma.
@export var shake_roll_deg := 1.4
## Trauma lost per second.
@export var trauma_decay := 1.8
@export var shake_frequency := 22.0
@export_group("Kick")
## World units of displacement per unit of kick strength.
@export var kick_distance := 0.55
@export var kick_stiffness := 210.0
@export var kick_damping := 19.0
@export var kick_max := 0.9
@export_group("Zoom")
@export var zoom_stiffness := 160.0
@export var zoom_damping := 15.0

var _trauma := 0.0
var _ahead := Vector3.ZERO
var _time := 0.0
var _noise := FastNoiseLite.new()
var _base := Transform3D.IDENTITY
# kick spring (world-space XZ offset of the camera)
var _kick := Vector3.ZERO
var _kick_vel := Vector3.ZERO
# zoom: held multiplier + springy FOV impulse
var _zoom := 1.0
var _zoom_target := 1.0
var _zoom_sharp := 3.0
var _punch := 0.0
var _punch_vel := 0.0
# focus bias
var _bias_pos := Vector3.ZERO
var _bias_w := 0.0
var _bias_target_w := 0.0

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	add_to_group(&"camera_rig")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.seed = randi()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = fov
	var pitch := deg_to_rad(pitch_deg)
	_base = Transform3D(Basis.from_euler(Vector3(-pitch, 0.0, 0.0)),
			Vector3(0.0, aim_height + sin(pitch) * distance, cos(pitch) * distance))
	camera.transform = _base
	if is_instance_valid(Game.player):
		global_position = Game.player.global_position


## Adds screen-shake trauma (0..1; 0.2 = bump, 0.5 = big hit, 1 = explosion). Stacks, capped at 1.
func shake(strength: float) -> void:
	_trauma = clampf(_trauma + strength, 0.0, 1.0)


## Directional kick: the view lurches along `dir` (world XZ) and springs back. ~0.2 light, 1 heavy.
func kick(dir: Vector3, strength: float) -> void:
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	_kick_vel += dir.normalized() * strength * kick_distance * 14.0


## Instant FOV impulse as a fraction of the FOV (-0.08 = sharp punch in), springs back to rest.
func zoom_punch(amount: float) -> void:
	_punch_vel += amount * 14.0


## Holds the FOV at `mult` x normal, eased with `sharpness` (1/s). set_zoom(1.0) releases.
func set_zoom(mult: float, sharpness: float = 3.0) -> void:
	_zoom_target = clampf(mult, 0.5, 1.5)
	_zoom_sharp = maxf(sharpness, 0.1)


## Leans the follow point `weight` (0..1) of the way toward `pos`. Weight 0 releases.
func set_focus_bias(pos: Vector3, weight: float) -> void:
	_bias_pos = Vector3(pos.x, 0.0, pos.z)
	_bias_target_w = clampf(weight, 0.0, 0.8)


func _process(delta: float) -> void:
	_time += delta
	var motion := clampf(Settings.screen_shake, 0.0, 1.0)
	_bias_w = lerpf(_bias_w, _bias_target_w * motion, 1.0 - exp(-2.2 * delta))
	var player := Game.player
	if is_instance_valid(player):
		var p := player.get_global_transform_interpolated().origin
		var v := player.velocity
		v.y = 0.0
		var want := (v * look_ahead).limit_length(max_look_ahead)
		_ahead = _ahead.lerp(want, 1.0 - exp(-look_ahead_sharpness * delta))
		var target := Vector3(p.x, 0.0, p.z) + _ahead
		if _bias_w > 0.001:
			target = target.lerp(_bias_pos, _bias_w)
		global_position = global_position.lerp(target, 1.0 - exp(-follow_sharpness * delta))
	_step_springs(delta)
	# FOV: held zoom (eased) x springy punch; both fade with the motion setting.
	_zoom = lerpf(_zoom, _zoom_target, 1.0 - exp(-_zoom_sharp * delta))
	var zoom_mult := lerpf(1.0, _zoom, motion) * (1.0 + _punch * motion)
	camera.fov = fov * clampf(zoom_mult, 0.5, 1.5)
	var kick_local := global_basis.inverse() * (_kick * motion)
	_trauma = maxf(_trauma - trauma_decay * delta, 0.0)
	var amount := _trauma * _trauma * motion
	var xf := _base
	xf.origin += kick_local
	if amount <= 0.0001:
		camera.transform = xf
		return
	var t := _time * shake_frequency
	var off := Vector3(_noise.get_noise_2d(t, 0.0), _noise.get_noise_2d(t, 37.0), 0.0) * shake_offset * amount
	var roll := deg_to_rad(shake_roll_deg) * amount * _noise.get_noise_2d(t, 91.0)
	camera.transform = xf * Transform3D(Basis(Vector3.BACK, roll), off)


func _step_springs(delta: float) -> void:
	# Semi-implicit spring integration, sub-stepped so a long frame cannot explode it.
	var steps := clampi(ceili(delta / 0.008), 1, 8)
	var h := delta / float(steps)
	for i in steps:
		_kick_vel += (-_kick * kick_stiffness - _kick_vel * kick_damping) * h
		_kick += _kick_vel * h
		_punch_vel += (-_punch * zoom_stiffness - _punch_vel * zoom_damping) * h
		_punch += _punch_vel * h
	_kick = _kick.limit_length(kick_max)
	_punch = clampf(_punch, -0.3, 0.3)
