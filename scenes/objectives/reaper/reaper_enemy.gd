class_name ReaperEnemy
extends Enemy
## "The Pale Reaper" (run event angel_of_death): a wandering mini-boss. It glides after the demon,
## slow but relentless, and every `reap_interval` s winds up a great Reap (a wide arc of pale light
## ahead of it, PyreBurst) and every few reaps a Harvest (pillars around the demon). Contact with it
## withers. After `life` s it departs (depart()). In group "champions" (not "boss": the boss bar,
## boss rotation and boss music stay free for real bosses).

const REAP_RADIUS := 5.0
const REAP_HALF := 1.25
const REAP_DAMAGE := 30.0
const HARVEST_DAMAGE := 20.0

var reap_interval := 4.0
var life := 90.0

var _t := 0.0
var _cd := 2.5
var _tell := 0.0
var _reaps := 0
var _departing := false
var _rm: ReaperModel


func _ready() -> void:
	super()
	add_to_group(&"champions")
	_rm = model as ReaperModel


func _physics_process(delta: float) -> void:
	if _flash_t > 0.0:
		_flash_t = maxf(_flash_t - delta, 0.0)
		model.set_flash(_flash_t / FLASH_TIME)
	if is_dying or _departing:
		return
	_t += delta
	var p := Game.player
	if p == null or not is_instance_valid(p):
		return
	var to := p.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var dir := to / dist if dist > 0.01 else Vector3.FORWARD
	if dist > 32.0:
		# It never loses the scent: it steps out of the dark nearby.
		global_position = ObjectiveFX.walkable(p.global_position - dir * 12.0)
		reset_physics_interpolation()
		HolyFX.column(global_position, 0.8, 14.0, 0.7, Color(0.8, 0.85, 1.0), 1.4)
		return
	var move := Vector3.ZERO
	if _tell > 0.0:
		_tell -= delta
		if _rm:
			_rm.raise = 1.0
		if _tell <= 0.0:
			_swing()
	else:
		move = dir * speed
		_cd -= delta
		if _cd <= 0.0 and dist < 9.0:
			_begin_reap(dir)
	velocity = move + _knockback
	_knockback = _knockback.lerp(Vector3.ZERO, 1.0 - exp(-8.0 * delta))
	move_and_slide()
	position.y = 0.0
	model.rotation.y = lerp_angle(model.rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-4.0 * delta))
	model.animate(delta, clampf(move.length() / maxf(speed, 0.01), 0.0, 1.0),
			EnemyModel.State.WINDUP if _tell > 0.0 else EnemyModel.State.MOVING)
	if _t >= life:
		depart()


func _begin_reap(dir: Vector3) -> void:
	_reaps += 1
	_tell = 0.95
	_cd = reap_interval * randf_range(0.85, 1.15)
	PyreBurst.cast(global_position, REAP_RADIUS, 0.95, REAP_DAMAGE, dir, REAP_HALF)
	Sfx.play(&"boss_charge", 0.05, -8.0)
	if _reaps % 3 == 0 and Game.player:
		var pp := Game.player.global_position
		for i in 5:
			JudgementPillar.cast(ObjectiveFX.ring_point(pp, 2.6), 1.3, 1.3 + 0.1 * i, HARVEST_DAMAGE)
		JudgementPillar.cast(pp, 1.3, 1.5, HARVEST_DAMAGE)


func _swing() -> void:
	if _rm:
		_rm.raise = 0.0
		_rm.swing = 1.0
		var tw := create_tween()
		tw.tween_interval(0.35)
		tw.tween_callback(_lower_scythe)
	Sfx.play(&"scythe", 0.05, 0.0)


func _lower_scythe() -> void:
	if _rm:
		_rm.swing = 0.0


## Leaves the field (the event ran out): fades into a column of pale light.
func depart() -> void:
	if _departing or is_dying:
		return
	_departing = true
	collision_layer = 0
	remove_from_group(&"enemies")
	HolyFX.column(global_position, 1.0, 26.0, 1.4, Color(0.8, 0.85, 1.0), 1.8)
	HolyFX.feathers(global_position + Vector3(0.0, 1.4, 0.0), 10, 1.2, 2.0)
	var tw := create_tween()
	tw.tween_property(model, "scale", Vector3.ONE * 0.01, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
