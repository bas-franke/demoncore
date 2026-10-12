class_name HubWanderer
extends Node3D
## Walks a procedural character (ProcModel: imps, hellhounds, damned souls, ...) around Basecamp
## Hell along a loop of waypoints, pausing at each one and optionally playing a gesture there
## (a soul swings its pick, a porter drops its sack). Purely cosmetic: no collision, no physics.
##
##   var w := HubWanderer.create(model, [Vector3(-9, 0, -11), Vector3(-6, 0, -8)], 1.2)
##   hub.add_child(w)

## Waypoints in the parent's space (ground positions), visited in order and looped.
var points: PackedVector3Array = PackedVector3Array()
## Walking speed (m/s).
var speed := 1.4
## Seconds spent at each stop (random in this range).
var pause_range := Vector2(1.5, 4.0)
## Gesture played on arrival (-1 = none).
var stop_gesture := -1
## Gestures repeated while stopped (e.g. a soul digs several times).
var gestures_per_stop := 1

## Clearance kept from obstacles, and from other walkers / the avatar.
const AVOID_MARGIN := 0.45
const PERSONAL_SPACE := 0.7

var model: ProcModel
var _target := 0
var _wait := 0.0
var _gestures_left := 0
var _gesture_cd := 0.0
var _yaw := 0.0
var _stuck_t := 0.0
var _side := 1.0


## Wraps `m` (not yet in the tree) in a wanderer that starts at points[0].
static func create(m: ProcModel, path: Array, walk_speed: float = 1.4) -> HubWanderer:
	var w := HubWanderer.new()
	w.model = m
	w.speed = walk_speed
	for p: Vector3 in path:
		w.points.append(p)
	return w


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_to_group(&"hub_wanderers")
	_side = 1.0 if randf() < 0.5 else -1.0
	if model == null or points.is_empty():
		return
	model.autoplay = false
	add_child(model)
	# Start somewhere along the loop so a crowd isn't in step.
	_target = randi() % points.size()
	position = points[_target]
	_wait = randf_range(0.0, pause_range.y)


func _process(delta: float) -> void:
	if model == null or points.is_empty():
		return
	var moving := false
	if _wait > 0.0:
		_wait -= delta
		if _gestures_left > 0:
			_gesture_cd -= delta
			if _gesture_cd <= 0.0:
				_gestures_left -= 1
				_gesture_cd = 1.3
				model.gesture(stop_gesture, 1.1)
		if _wait <= 0.0:
			_target = (_target + 1) % points.size()
	else:
		var to := points[_target] - position
		to.y = 0.0
		var d := to.length()
		if d < 0.08:
			_wait = randf_range(pause_range.x, pause_range.y)
			if stop_gesture >= 0:
				_gestures_left = gestures_per_stop
				_gesture_cd = 0.3
				_wait = maxf(_wait, gestures_per_stop * 1.3 + 0.4)
		else:
			# Close to the stop: walk straight in (stops may sit right next to a prop).
			var dir := _steer(to / d) if d > 1.2 else to / d
			position += dir * minf(d, speed * delta)
			_yaw = lerp_angle(_yaw, atan2(-dir.x, -dir.z), 1.0 - exp(-6.0 * delta))
			moving = true
			# Wedged against something for too long: give up on this stop.
			_stuck_t = _stuck_t + delta if dir.dot(to / d) < 0.2 else 0.0
			if _stuck_t > 4.0:
				_stuck_t = 0.0
				_target = (_target + 1) % points.size()
	model.rotation.y = _yaw
	model.ground_speed = speed if moving else 0.0
	model.animate(delta, 1.0 if moving else 0.0, EnemyModel.State.MOVING)


## Simple local avoidance: the wanted direction plus a push away from every nearby obstacle
## (HubScenery.obstacles), other wanderers and the hub avatar. Obstacles straight ahead also add a
## sideways nudge so walkers slide around posts instead of stopping dead in front of them.
func _steer(want: Vector3) -> Vector3:
	var push := Vector3.ZERO
	var here := global_position
	here.y = 0.0
	var hub := get_tree().get_first_node_in_group(&"basecamp")
	var scenery: Node = hub.get(&"scenery") if hub else null
	if scenery:
		for o: Array in scenery.get(&"obstacles"):
			push += _repel(here, o[0], float(o[1]) + AVOID_MARGIN, want)
	for n in get_tree().get_nodes_in_group(&"hub_wanderers"):
		if n != self:
			push += _repel(here, (n as Node3D).global_position, PERSONAL_SPACE, want) * 0.6
	var avatar := get_tree().get_first_node_in_group(&"hub_avatar") as Node3D
	if avatar and avatar.visible:
		push += _repel(here, avatar.global_position, PERSONAL_SPACE + 0.3, want)
	var dir := want + push
	dir.y = 0.0
	return dir.normalized() if dir.length_squared() > 0.0001 else want


func _repel(here: Vector3, centre: Vector3, reach: float, want: Vector3) -> Vector3:
	var away := here - Vector3(centre.x, 0.0, centre.z)
	var d := away.length()
	if d >= reach or d < 0.001:
		return Vector3.ZERO
	away /= d
	var k := (reach - d) / reach
	var out := away * k * 2.0
	# Ahead of us: sidestep (keep a consistent side per wanderer so it doesn't dither).
	if away.dot(want) < -0.3:
		out += Vector3(-want.z, 0.0, want.x) * k * 1.5 * _side
	return out
