class_name PlayerDash
extends Node
## The demon's dash: a short burst of speed with invulnerability frames, charge-based with a
## per-charge recharge. Added as a child by Player._ready(); Player asks it for the movement
## override (process_dash) and for invulnerability (is_invulnerable).
##
## Stats live on the Player (dash_speed, dash_time, dash_cooldown, dash_charges) so passives,
## abilities and meta upgrades can change them with Player.apply_stat().
##
## While dashing the player's physics layer is cleared, so holy orbs and smoke pass through the
## demon instead of popping on it; non-body hits (slams, beams, pillars) are negated by the
## i-frames and reported as dodges (RunState.player_dodged -> a brief slow-mo "perfect dodge").

signal charges_changed(charges: int, max_charges: int)
signal dash_started(direction: Vector3)
signal dash_ended

## Extra invulnerability after the burst ends (so the exit frame is forgiving).
const IFRAME_GRACE := 0.1
## Dash input is remembered this long if pressed while unable to dash (buffering).
const INPUT_BUFFER := 0.15
## Seconds between afterimage puffs along the path.
const TRAIL_STEP := 0.035
const TRAIL_COLOR := Color(1.0, 0.3, 0.08)

var player: Player
var charges := 1
var _dir := Vector3.FORWARD
var _dash_t := 0.0
var _iframe_t := 0.0  # dash i-frames (burst + grace): hits here count as dodges
var _mercy_t := 0.0  # granted i-frames (post-hit mercy, abilities): hits are just ignored
var _recharge_t := 0.0
var _buffer_t := 0.0
var _trail_t := 0.0
var _saved_layer := 0
var _dodge_slowmo_ready := true
## Last seen max_charges(): extra charges granted later (meta upgrades apply after _ready,
## boons mid-run) arrive full instead of waiting for the recharge.
var _known_max := 1


func _ready() -> void:
	player = get_parent() as Player
	charges = max_charges()
	_known_max = charges


func max_charges() -> int:
	return maxi(int(player.dash_charges), 1) if player else 1


func is_dashing() -> bool:
	return _dash_t > 0.0


func is_invulnerable() -> bool:
	return _dash_t > 0.0 or _iframe_t > 0.0 or _mercy_t > 0.0


## 0..1 progress of the recharge of the next charge (1 = all charges ready). For HUD widgets.
func recharge_ratio() -> float:
	if charges >= max_charges():
		return 1.0
	return clampf(1.0 - _recharge_t / maxf(player.dash_cooldown, 0.01), 0.0, 1.0)


## Called by the Player every physics frame with the steering direction and the walk velocity.
## Returns the velocity to use this frame.
func process_dash(delta: float, input_dir: Vector3, walk_velocity: Vector3) -> Vector3:
	_tick_recharge(delta)
	_iframe_t = maxf(_iframe_t - delta, 0.0)
	_mercy_t = maxf(_mercy_t - delta, 0.0)
	_buffer_t = maxf(_buffer_t - delta, 0.0)
	if Input.is_action_just_pressed(&"dash") or (Game.autopilot and _autopilot_wants_dash()):
		_buffer_t = INPUT_BUFFER
	if _buffer_t > 0.0 and _dash_t <= 0.0 and charges > 0 and not player.is_dead:
		_buffer_t = 0.0
		_start(input_dir)

	if _dash_t <= 0.0:
		return walk_velocity
	_dash_t -= delta
	_trail_t -= delta
	if _trail_t <= 0.0:
		_trail_t = TRAIL_STEP
		_afterimage()
	# Ease out over the last third so the stop doesn't feel like hitting a wall.
	var k := clampf(_dash_t / maxf(player.dash_time * 0.35, 0.001), 0.0, 1.0)
	var v := _dir * player.dash_speed * lerpf(0.45, 1.0, k)
	if _dash_t <= 0.0:
		_end()
	return v


func _start(input_dir: Vector3) -> void:
	_dir = input_dir.normalized() if input_dir.length_squared() > 0.01 else player.facing
	_dir.y = 0.0
	if _dir.length_squared() < 0.01:
		_dir = Vector3.FORWARD
	_dir = _dir.normalized()
	charges -= 1
	if _recharge_t <= 0.0:
		_recharge_t = player.dash_cooldown
	charges_changed.emit(charges, max_charges())
	_dash_t = player.dash_time
	_iframe_t = player.dash_time + IFRAME_GRACE
	_trail_t = 0.0
	_dodge_slowmo_ready = true
	# Phase through holy projectiles (they detect the player's body layer).
	_saved_layer = player.collision_layer
	player.collision_layer = 0
	player.model.set_flash(0.5)
	Sfx.play(&"wingbeat", 0.12, -9.0)  # under the &"dash" whoosh from SfxHooks (RunState.player_dashed)
	EnemyModel.poof(player.global_position + Vector3(0.0, 0.2, 0.0), Art.ASH, Art.EMBER, 5, 0.3, 0.5)
	dash_started.emit(_dir)
	RunState.notify_dash(_dir)


func _end() -> void:
	_dash_t = 0.0
	if player.collision_layer == 0:
		player.collision_layer = _saved_layer
	player.model.set_flash(0.0)
	dash_ended.emit()


## A hit landed during i-frames. Returns true if it was negated.
func absorb_hit(amount: float) -> bool:
	if not is_invulnerable():
		return false
	if _dash_t > 0.0 or _iframe_t > 0.0:
		RunState.notify_dodge(amount)
		# One slow-mo "perfect dodge" per dash, so a volley doesn't freeze the game.
		if _dodge_slowmo_ready:
			_dodge_slowmo_ready = false
			Game.hitstop(0.09, 0.25)
			HolyFX.motes(player.global_position + Vector3(0.0, 0.8, 0.0), 6, Art.EMBER, 0.6, 1.2, 0.6)
	return true


## Grants i-frames without dashing (post-hit mercy, abilities, revives).
func grant_iframes(seconds: float) -> void:
	_mercy_t = maxf(_mercy_t, seconds)


## True while post-hit mercy frames run (the Player blinks).
func in_mercy() -> bool:
	return _mercy_t > 0.0 and _dash_t <= 0.0


func _tick_recharge(delta: float) -> void:
	var mc := max_charges()
	if mc > _known_max:
		charges += mc - _known_max
		charges_changed.emit(charges, mc)
	_known_max = mc
	if charges > mc:
		charges = mc
		charges_changed.emit(charges, mc)
	if charges >= mc:
		_recharge_t = 0.0
		return
	if _recharge_t <= 0.0:
		_recharge_t = player.dash_cooldown
	_recharge_t -= delta
	if _recharge_t <= 0.0:
		charges += 1
		charges_changed.emit(charges, mc)
		if charges < mc:
			_recharge_t = player.dash_cooldown


func _afterimage() -> void:
	if Game.world == null:
		return
	# A fading ember smear behind the demon, stretched along the dash.
	var mi := MeshInstance3D.new()
	mi.mesh = Art.sphere()
	var mat := HolyFX.additive(TRAIL_COLOR, 1.6)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	Game.spawn(mi, player.global_position + Vector3(0.0, 0.75, 0.0))
	mi.look_at(mi.global_position + _dir, Vector3.UP)
	mi.scale = Vector3(0.55, 1.1, 1.3)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(0.1, 0.4, 1.6), 0.28).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(mat, "albedo_color", Color(0, 0, 0, 1), 0.28)
	tw.tween_callback(mi.queue_free)


## Dev bot (--autopilot): see scripts/autopilot.gd.
func _autopilot_wants_dash() -> bool:
	return Autopilot.wants_dash(player)
