class_name Projectile
extends Area3D
## Straight-flying projectile that damages enemies it touches. Configure before spawning.
##
## Optional: a Node3D child named "Visual" rolls along the flight direction and does a
## little squash when the projectile hits something.

var velocity := Vector3.ZERO
var damage := 10.0
## How many extra enemies it can pass through.
var pierce := 0
var lifetime := 2.0
var knockback := 4.0
## The Weapon that fired it (Enemy.last_hit_source during the hit; set by the weapon).
var source: Node
## Radians per second the "Visual" child rolls (0 = no roll).
var spin_speed := 14.0

const _POP_TIME := 0.1

var _hit := {}
var _visual: Node3D
var _visual_scale := Vector3.ONE
var _spin := Quaternion.IDENTITY
var _squash := 0.0
var _spent := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_visual = get_node_or_null(^"Visual") as Node3D
	if _visual:
		_visual_scale = _visual.scale
		_spin = Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, randf() * TAU)).get_rotation_quaternion()


func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	lifetime -= delta
	if _visual:
		_update_visual(delta)
	if lifetime <= 0.0:
		queue_free()


func _update_visual(delta: float) -> void:
	var axis := Vector3.UP.cross(velocity)
	if spin_speed != 0.0 and axis.length_squared() > 0.0001:
		_spin = (Quaternion(axis.normalized(), spin_speed * delta) * _spin).normalized()
	_squash = move_toward(_squash, 0.0, delta * 7.0)
	var sq := Vector3(1.0 + 0.45 * _squash, 1.0 - 0.4 * _squash, 1.0 + 0.45 * _squash)
	if _spent:
		sq *= maxf(lifetime / _POP_TIME, 0.05)
	_visual.basis = Basis(_spin).scaled(_visual_scale * sq)


func _on_body_entered(body: Node3D) -> void:
	if _spent:
		return
	var e := body as Enemy
	if e == null or e.is_dying or _hit.has(e):
		return
	_hit[e] = true
	Enemy.hit(e, damage, velocity.normalized() * knockback, source)
	_squash = 1.0
	pierce -= 1
	if pierce < 0:
		if _visual:
			# Squash-and-vanish instead of popping out of existence.
			_spent = true
			set_deferred(&"monitoring", false)
			velocity *= 0.15
			lifetime = minf(lifetime, _POP_TIME)
		else:
			queue_free()
