class_name HolyWaterFlask
extends Node3D
## Enemy projectile (Holy-Water Friar): a corked glass flask of blessed water lobbed in a high arc
## at where the demon stands when it is thrown. It does not hit on the way; it shatters where it
## lands and leaves a HolyPuddle that scalds the demon while it stands in it (telegraphed: the
## flask's landing spot glows on the ground during the flight). Enemy._fire sets `velocity` (only
## its direction and length are used to cap the range) and `damage` (per puddle tick).

const FLIGHT := 0.9
const ARC := 2.6
const MAX_RANGE := 11.0

var velocity := Vector3.ZERO
var damage := 4.0

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _t := 0.0
var _flask: Node3D
var _mark: MeshInstance3D


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_from = global_position
	var target := _from + velocity.normalized() * 6.0
	if Game.player:
		target = Game.player.global_position
	var flat := target - _from
	flat.y = 0.0
	if flat.length() > MAX_RANGE:
		flat = flat.normalized() * MAX_RANGE
	_to = Vector3(_from.x + flat.x, 0.0, _from.z + flat.z)
	_flask = Art.pivot(self)
	Art.part(_flask, Art.sphere(), Art.mat(Color(0.75, 0.9, 1.0), 0.05, 0.0, 0.0, true, 0.9, &"crystal"), Vector3.ZERO, Vector3(0.14, 0.16, 0.14))
	Art.part(_flask, Art.cylinder(0.5, 0.5), Art.mat(Color(0.75, 0.9, 1.0), 0.05, 0.0, 0.0, true, 0.9), Vector3(0.0, 0.11, 0.0), Vector3(0.05, 0.08, 0.05))
	Art.part(_flask, Art.cylinder(0.5, 0.5), m_cork(), Vector3(0.0, 0.16, 0.0), Vector3(0.05, 0.04, 0.05))
	Art.part(_flask, Art.sphere(), Art.glow(Color(0.7, 0.9, 1.0), 1.2), Vector3.ZERO, Vector3.ONE * 0.09)
	# Landing mark: a faint ring that brightens as the flask comes down.
	# (top_level: it stays on the ground at the target while the flask flies.)
	_mark = Art.part(self, Art.torus(0.85, 1.0), Art.glow(Color(0.6, 0.85, 1.0), 1.0, true, 0.6), Vector3.ZERO, Vector3.ONE * HolyPuddle.RADIUS)
	_mark.top_level = true
	_mark.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_mark.global_position = _to + Vector3(0.0, 0.05, 0.0)


static func m_cork() -> Material:
	return Art.mat(Color(0.55, 0.4, 0.25), 0.9)


func _physics_process(delta: float) -> void:
	_t += delta
	var k := clampf(_t / FLIGHT, 0.0, 1.0)
	var p := _from.lerp(_to, k)
	p.y = lerpf(_from.y, 0.1, k) + sin(k * PI) * ARC
	global_position = p
	_flask.rotation = Vector3(_t * 9.0, _t * 4.0, 0.0)
	if is_instance_valid(_mark):
		_mark.scale = Vector3.ONE * HolyPuddle.RADIUS * (0.6 + 0.4 * k)
	if k >= 1.0:
		_shatter()


func _shatter() -> void:
	HolyPuddle.create(_to, damage)
	EnemyModel.light_flash(_to + Vector3(0.0, 0.3, 0.0), 0.5, Color(0.7, 0.9, 1.0), false)
	EnemyModel.spawn_debris(_to + Vector3(0.0, 0.2, 0.0), [&"shard"], Color(0.7, 0.9, 1.0), 4, 0.6)
	Sfx.play(&"holy_hit", 0.15, -8.0)
	queue_free()
