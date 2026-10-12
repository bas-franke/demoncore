class_name SaintEnemy
extends Enemy
## A living saint fleeing for the heavens (the "Hunt the Fleeing Saint" objective). Reuses
## Enemy's setup / take_damage / die, but replaces the AI: it runs from the demon (sprinting when
## close, dawdling when far so the hunt stays winnable), weaves side to side, and every
## `blessing_interval` seconds leaves a Judgement Pillar on the spot it just left (punishing a
## demon that follows straight in its footsteps). It leaves glowing footprints. It never relocates
## and deals no contact damage. ascend() lifts it away in a column of light (the hunt failed).

## Emitted when a procession reaches the end of its route (it then waits there).
signal route_finished
## Emitted when a procession breaks into flight.
signal panicked

const SPRINT_DISTANCE := 9.0
const DAWDLE_DISTANCE := 18.0
const WEAVE_RATE := 0.9
const STEP_TIME := 0.32

var flee_speed := 4.6
## Procession mode: waypoints walked in order at `route_speed` until the demon comes within
## `panic_distance` or strikes; then it flees like any saint. Empty = flee from the start.
var route: Array[Vector3] = []
var route_speed := 2.0
var panic_distance := 7.0
var blessing_interval := 2.6
var blessing_damage := 16.0

var _bless_t := 1.5
var _weave := 0.0
var _step_t := 0.0
var _ascending := false
var _halo: Node3D
var _turn_sign := 1.0


func _ready() -> void:
	super()
	damage = 0.0  # it does not fight; its blessings do
	_halo = Art.pivot(self, Vector3(0.0, data.size * 1.75 + data.hover, 0.0))
	HolyFX.glow_part(_halo, Art.torus(0.85, 1.0), Art.HOLY_WHITE, 2.8, Vector3.ZERO, Vector3.ONE * 0.36 * data.size)
	Art.light(_halo, Art.HOLY, 1.6, 5.0)
	_weave = randf() * TAU


func _physics_process(delta: float) -> void:
	_tick_feedback(delta)
	if _ascending or is_dying:
		return
	var player := Game.player
	if player == null or not is_instance_valid(player):
		return
	var away := global_position - player.global_position
	away.y = 0.0
	var dist := away.length()
	var dir := away / dist if dist > 0.01 else Vector3.FORWARD
	var spd := flee_speed
	if not route.is_empty() and dist > panic_distance and hp >= max_hp:
		# Procession: walk the route at a stately pace until the demon comes close or strikes.
		var to := route[0] - global_position
		to.y = 0.0
		if to.length() < 0.6:
			route.remove_at(0)
			if route.is_empty():
				route_finished.emit()
				return
			to = route[0] - global_position
			to.y = 0.0
		dir = _avoid_walls(to.normalized())
		spd = route_speed
	else:
		if not route.is_empty():
			route.clear()
			panicked.emit()
		_weave += delta * WEAVE_RATE
		dir = _avoid_walls(dir.rotated(Vector3.UP, sin(_weave) * 0.6).normalized())
		if dist < SPRINT_DISTANCE:
			spd *= 1.2
		elif dist > DAWDLE_DISTANCE:
			spd *= 0.45
	velocity = dir * spd + _knockback
	_knockback = _knockback.lerp(Vector3.ZERO, 1.0 - exp(-8.0 * delta))
	move_and_slide()
	position.y = 0.0
	model.rotation.y = lerp_angle(model.rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-8.0 * delta))
	model.animate(delta, clampf(spd / maxf(speed, 0.01), 0.0, 1.0), EnemyModel.State.MOVING)
	_halo.rotate_y(delta * 1.2)

	_step_t -= delta
	if _step_t <= 0.0:
		_step_t = STEP_TIME
		HolyFX.motes(global_position + Vector3(0.0, 0.05, 0.0), 2, Art.HOLY, 0.15, 0.25, 1.6, 0.05)
	_bless_t -= delta
	if _bless_t <= 0.0 and dist < DAWDLE_DISTANCE:
		_bless_t = blessing_interval
		# Behind itself, on the line toward the demon: the pursuer runs into it.
		JudgementPillar.cast(global_position - dir * 1.2, 1.6, 1.0, blessing_damage)


## The hunt failed: rise into the sky and vanish.
func ascend() -> void:
	if _ascending or is_dying:
		return
	_ascending = true
	collision_layer = 0
	remove_from_group(&"enemies")
	HolyFX.column(global_position, 1.0, 30.0, 1.6, Art.HOLY, 2.2)
	HolyFX.feathers(global_position + Vector3(0.0, 1.2, 0.0), 12, 1.2, 2.0)
	Sfx.play(&"choir", 0.0, 2.0)
	var tw := create_tween()
	tw.tween_property(model, "position:y", 14.0, 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(model, "scale", Vector3.ONE * 0.01, 1.6)
	tw.tween_callback(queue_free)


## On bounded maps, bends the flight along walls and map edges instead of into them (the map's
## flow field only steers toward the demon, so probe a few headings instead).
func _avoid_walls(dir: Vector3) -> Vector3:
	var maps := get_tree().root.get_node_or_null(^"Maps")
	if maps == null or not maps.has_method(&"is_walkable"):
		return dir
	for turn: float in [0.0, 0.7, -0.7, 1.4, -1.4, 2.1, -2.1]:
		var d := dir.rotated(Vector3.UP, turn * _turn_sign)
		if maps.call(&"is_walkable", global_position + d * 1.8):
			if turn != 0.0:
				_turn_sign = signf(turn) * _turn_sign  # keep sliding the same way along a wall
			return d
	return -dir


func _tick_feedback(delta: float) -> void:
	if _flash_t > 0.0:
		_flash_t = maxf(_flash_t - delta, 0.0)
		model.set_flash(_flash_t / FLASH_TIME)
	if _squash > 0.0:
		_squash = maxf(_squash - delta * 7.0, 0.0)
		var k := _squash * 0.08
		model.scale = Vector3(data.size * (1.0 + k), data.size * (1.0 - k), data.size * (1.0 + k))
