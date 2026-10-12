class_name HymnBlessing
extends Node3D
## A Mortal Choir's blessing on one angel: +SPEED_BONUS speed and +DAMAGE_BONUS contact damage for
## a few seconds, shown as a slowly turning ring of gold notes over it. Re-blessing refreshes the
## time instead of stacking. The bonus is multiplied in and divided out again, so other systems'
## changes to the enemy's speed in between are kept.

const SPEED_BONUS := 0.35
const DAMAGE_BONUS := 0.25
const NOTE := Color(1.0, 0.86, 0.45)

var time_left := 5.0

var _enemy: Enemy
var _ring: Node3D


## Blesses `enemy` for `seconds` (refreshes an existing blessing).
static func bless(enemy: Enemy, seconds: float) -> void:
	if enemy == null or not is_instance_valid(enemy) or enemy.is_dying:
		return
	var existing := enemy.get_node_or_null(^"HymnBlessing") as HymnBlessing
	if existing:
		existing.time_left = maxf(existing.time_left, seconds)
		return
	var b := HymnBlessing.new()
	b.name = "HymnBlessing"
	b.time_left = seconds
	enemy.add_child(b)


func _ready() -> void:
	_enemy = get_parent() as Enemy
	if _enemy == null:
		queue_free()
		return
	_enemy.set_move_factor(&"hymn_blessing", 1.0 + SPEED_BONUS)
	_enemy.damage *= 1.0 + DAMAGE_BONUS
	var h := (_enemy.data.size * 1.4 + _enemy.data.hover) if _enemy.data else 1.4
	_ring = Art.pivot(self, Vector3(0.0, h, 0.0))
	for k in 5:
		var a := TAU * float(k) / 5.0
		var p := Vector3(cos(a), 0.0, sin(a)) * 0.35
		Art.part(_ring, Art.sphere(), Art.glow(NOTE, 2.0), p, Vector3(0.07, 0.06, 0.05))
		Art.part(_ring, Art.box(), Art.glow(NOTE, 1.6), p + Vector3(0.03, 0.08, 0.0), Vector3(0.012, 0.15, 0.012))


func _process(delta: float) -> void:
	time_left -= delta
	if _ring:
		_ring.rotate_y(delta * 1.8)
		_ring.position.y += sin(time_left * 4.0) * 0.002
	if time_left <= 0.0:
		_end()


func _end() -> void:
	if _enemy and is_instance_valid(_enemy):
		_enemy.set_move_factor(&"hymn_blessing", 1.0)
		_enemy.damage /= 1.0 + DAMAGE_BONUS
	queue_free()
