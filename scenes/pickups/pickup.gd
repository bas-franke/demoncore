class_name Pickup
extends Area3D
## Base for pickups that sit still until the player's PickupArea touches them, then fly into
## the demon and are collected (XP soul shards, blood chalices, ...).
##
## How it plugs in: Player._on_pickup_area_entered() calls attract(player) on any area that has
## that method. A subclass calls _home(delta) from its _physics_process(); when the pickup
## reaches the player, _home() calls _collect(player), frees the pickup and returns true.
## Override _collect() to grant the reward (XP, healing, currency) and play its sound.
## Owned by code-quality (docs/team/code-quality.md); feature code lives in the subclasses.

## Acceleration toward the player once attracted (units / s^2).
var homing_accel := 45.0
## Speed right after attract(). Negative = a small hop away from the player first, then in.
var homing_start_speed := -4.0
## Height above the player's origin the pickup flies to (roughly chest height).
var homing_height := 0.6

## The player this pickup is flying to; null while it sits on the ground.
var _target: Player
var _speed := 0.0


## Starts flying to `target`. Later calls are ignored (the first attractor wins).
func attract(target: Player) -> void:
	if _target == null:
		_target = target
		_speed = homing_start_speed


func is_attracted() -> bool:
	return _target != null


## Override: grant the reward to `player`. Called once, right before the pickup is freed.
func _collect(_player: Player) -> void:
	pass


## Moves toward the attracting player. Returns true once collected (the node is then queued
## for deletion, so the caller should stop processing this frame).
func _home(delta: float) -> bool:
	if _target == null:
		return false
	if not is_instance_valid(_target):
		_target = null
		return false
	var to := _target.global_position + Vector3(0.0, homing_height, 0.0) - global_position
	var dist := to.length()
	_speed += homing_accel * delta
	# Collect when close, or when this frame's step would overshoot the target.
	if dist < 0.5 or (_speed > 0.0 and dist < _speed * delta):
		_collect(_target)
		queue_free()
		return true
	global_position += to / dist * _speed * delta
	return false


## Overshooting ease (0..1 -> 0..1, peaks ~1.1) for the spawn "pop" of pickup models.
static func _ease_out_back(x: float) -> float:
	const C1 := 1.70158
	const C3 := C1 + 1.0
	return 1.0 + C3 * pow(x - 1.0, 3.0) + C1 * pow(x - 1.0, 2.0)
