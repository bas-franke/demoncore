class_name PhasedBoss
extends Enemy
## Shared skeleton for multi-phase bosses (Azrafel, the Gate Archon; new bosses should extend it).
## Handles what every phased fight needs so a boss script only writes its attacks:
##   - INTRO (rises out of a pillar of light, untouchable), STALK (glide toward the demon, keep
##     `keep_distance`), TELL (wind-up, length from `_start_attack`), ACTION (an attack in motion,
##     e.g. a dash), RECOVER, TRANSITION (phase change: untouchable, `transition_time`), DYING.
##   - Phase lines (`phase_lines`, HP ratios): damage is clamped at the line so a phase can never
##     be skipped; Game.boss_phase_changed fires; `phase_index`, `phase_count`, `is_enraged`
##     (last phase) and `phase_thresholds()` feed the boss bar.
##   - A small scheduler (`_schedule(delay, callable)`) for cascades, cancelled on phase change
##     and death; hazards in group "boss_hazards" are dissipated at both.
##   - Death: kneel, burn to light, Game.boss_died, XP + chalice + a Reliquary worth 3 levels.
## Subclasses override: _start_attack(dir) -> float (tell seconds), _release_attack(player),
## _action_process(delta, dir) -> Vector3 (velocity while in ACTION; call _end_action()),
## _on_phase_begin(index), and optionally _intro_fx() / _felled_fx().

enum Phase { INTRO, STALK, TELL, ACTION, RECOVER, TRANSITION, DYING, FELLED }

const DEATH_KNEEL := 0.6
const DEATH_BURN := 1.8
const DEATH_FLASH_AT := 2.6
const FELLED_TIME := 0.9
const BOSS_RELOCATE_DISTANCE := 30.0
const TOAST_NAME := Color("e8d6a0")
const TOAST_PHASE := Color("f2c66b")
const TOAST_FELLED := Color("e6c26e")

## HP ratios where the phase changes (descending).
var phase_lines: Array[float] = [0.66, 0.33]
var phase_names: Array[String] = ["I", "II", "III"]
var phase_index := 0
var phase_count := 3
var is_enraged := false
var phase := Phase.INTRO
var intro_time := 2.6
var transition_time := 2.4
var keep_distance := 4.5
var attack_range := 16.0
## Seconds between attacks, per phase.
var cooldowns: Array[float] = [3.0, 2.6, 2.0]
var speed_mults: Array[float] = [1.0, 1.1, 1.25]
var felled_text := "BOSS FELLED"
var rage_text := ""

var _phase_t := 0.0
var _tell_len := 0.0
var _cd := 1.6
var _boss_aim := Vector3.FORWARD
var _home_layer := 4
var _landed := false
var _death_t := 0.0
var _scheduled: Array = []  # [time_left: float, Callable]


func _ready() -> void:
	super()
	add_to_group(&"boss")
	phase_count = phase_lines.size() + 1
	_begin_intro()


## HP ratios where the phase changes (the boss bar draws a notch at each).
func phase_thresholds() -> Array[float]:
	return phase_lines


func phase_name() -> String:
	return phase_names[clampi(phase_index, 0, phase_names.size() - 1)]


func _physics_process(delta: float) -> void:
	_update_hit_feedback(delta)
	_run_scheduled(delta)
	if is_dying:
		_dying_process(delta)
		return
	var player := Game.player
	if player == null or not is_instance_valid(player):
		_animate(delta, 0.0)
		return
	var to := player.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var dir := to / dist if dist > 0.001 else _forward()
	_phase_t -= delta
	var move := Vector3.ZERO
	match phase:
		Phase.INTRO:
			_intro_process(delta, dir)
		Phase.TRANSITION:
			hp = maxf(hp, max_hp * _line(phase_index - 1))
			_turn_toward(dir, 2.0, delta)
			if _phase_t <= 0.0:
				phase = Phase.STALK
				_cd = 0.8
				_on_phase_begin(phase_index)
		Phase.STALK:
			if dist > BOSS_RELOCATE_DISTANCE:
				_relocate(player, dir)
				return
			var spd := speed * speed_mults[mini(phase_index, speed_mults.size() - 1)]
			if dist > 13.0:
				spd *= 2.0
			if dist > keep_distance:
				move = dir * spd
			elif dist < keep_distance * 0.6:
				move = -dir * spd * 0.4
			_turn_toward(dir, 3.0, delta)
			_cd -= delta
			if _cd <= 0.0 and not player.is_dead and dist < attack_range:
				_boss_aim = dir
				_tell_len = _start_attack(dir)
				phase = Phase.TELL
				_phase_t = _tell_len
		Phase.TELL:
			_turn_toward(_boss_aim, 4.0, delta)
			if _phase_t <= 0.0:
				_release_attack(player)
		Phase.ACTION:
			move = _action_process(delta, dir)
		Phase.RECOVER:
			move = dir * speed * 0.3
			_turn_toward(dir, 2.0, delta)
			if _phase_t <= 0.0:
				phase = Phase.STALK
				_cd = cooldowns[mini(phase_index, cooldowns.size() - 1)] * randf_range(0.85, 1.15)
				_on_recovered()
	velocity = move
	move_and_slide()
	position.y = 0.0
	_animate(delta, clampf(move.length() / maxf(speed, 0.01), 0.0, 1.0))


# ---------------------------------------------------------------- overridables

## Starts the wind-up of the next attack; returns the tell length (s).
func _start_attack(_dir: Vector3) -> float:
	return 0.5


## The tell ended: cast the attack, then call _recover(seconds) or _begin_action().
func _release_attack(_player: Player) -> void:
	_recover(1.0)


## Velocity while in ACTION. Call _end_action(recover_seconds) when done.
func _action_process(_delta: float, _dir: Vector3) -> Vector3:
	_end_action(0.5)
	return Vector3.ZERO


func _on_phase_begin(_index: int) -> void:
	pass


## Pose reset when RECOVER ends.
func _on_recovered() -> void:
	pass


func _intro_fx() -> void:
	HolyFX.column(global_position, 1.4, 30.0, intro_time + 0.4, Art.HOLY, 1.4)
	_toast(data.display_name.to_upper() if data else "BOSS", TOAST_NAME)
	Sfx.play(&"boss_intro", 0.0)
	_shake(0.25)


func _felled_fx() -> void:
	pass


# ---------------------------------------------------------------- state helpers

func _recover(seconds: float) -> void:
	phase = Phase.RECOVER
	_phase_t = seconds


func _begin_action(seconds: float) -> void:
	phase = Phase.ACTION
	_phase_t = seconds


func _end_action(recover_seconds: float) -> void:
	_recover(recover_seconds)


func _model_state() -> int:
	match phase:
		Phase.TELL, Phase.TRANSITION:
			return EnemyModel.State.WINDUP
		Phase.ACTION:
			return EnemyModel.State.ATTACKING
		Phase.RECOVER:
			return EnemyModel.State.RECOVER
	return EnemyModel.State.MOVING


func _animate(delta: float, move_ratio: float) -> void:
	# Blender models stretch their windup / attack clips over the state: tell them how far in.
	match phase:
		Phase.TELL:
			model.state_duration = _tell_len
			model.state_progress = clampf(1.0 - _phase_t / maxf(_tell_len, 0.01), 0.0, 1.0)
		_:
			model.state_duration = 0.0
	model.body_scale = data.size
	model.animate(delta, move_ratio, _model_state())


# ---------------------------------------------------------------- damage / phases

func take_damage(amount: float, knockback := Vector3.ZERO) -> void:
	if is_dying or phase == Phase.INTRO or phase == Phase.TRANSITION:
		return
	var crossing := false
	if phase_index < phase_lines.size():
		var line_hp := max_hp * phase_lines[phase_index]
		# hp - amount <= line also catches hp already under the line (max_hp rescaled mid-fight).
		if hp - amount <= line_hp:
			amount = maxf(hp - line_hp, 0.0)
			crossing = true
	super(amount, knockback)
	# On-hit effects (Game.enemy_struck listeners) may re-enter take_damage during super() and
	# start the transition themselves: never begin it twice.
	if crossing and not is_dying and phase != Phase.TRANSITION:
		_begin_transition()


func _line(index: int) -> float:
	if index < 0 or index >= phase_lines.size():
		return 0.0
	return phase_lines[index]


func _begin_transition() -> void:
	phase_index = mini(phase_index + 1, phase_count - 1)
	is_enraged = phase_index >= phase_count - 1
	phase = Phase.TRANSITION
	_phase_t = transition_time
	_scheduled.clear()
	get_tree().call_group(&"boss_hazards", &"dissipate")
	_toast("%s  -  Phase %s" % [phase_name().to_upper(), UIPalette.roman(phase_index + 1)], TOAST_PHASE)
	if is_enraged and rage_text != "":
		_toast(rage_text, TOAST_PHASE)
	Sfx.play(&"toll", 0.0, 3.0)
	Sfx.play(&"choir", 0.0, 2.0)
	_shake(0.45)
	HolyFX.flash(global_position + Vector3(0.0, 2.0, 0.0), 4.0, 0.7, Art.HOLY_WHITE, 3.0)
	HolyFX.column(global_position, 1.6, 30.0, transition_time, Art.HOLY, 1.6)
	PyreBurst.cast(global_position, 3.6, transition_time * 0.7, 14.0)
	Game.boss_phase_changed.emit(self, phase_index)


func _begin_intro() -> void:
	phase = Phase.INTRO
	_phase_t = intro_time
	Game.boss_spawned.emit(self)
	_home_layer = collision_layer
	collision_layer = 0
	model.position.y = -4.0
	_intro_fx.call_deferred()


func _intro_process(delta: float, dir: Vector3) -> void:
	hp = max_hp
	var k := clampf(1.0 - _phase_t / intro_time, 0.0, 1.0)
	model.position.y = lerpf(-4.0, data.hover, 1.0 - (1.0 - k) * (1.0 - k))
	_turn_toward(dir, 3.0, delta)
	if k >= 0.7 and not _landed:
		_landed = true
		Sfx.play(&"impact", 0.0)
		HolyFX.motes(global_position + Vector3(0.0, 0.3, 0.0), 20, Art.HOLY, 2.5, 1.5, 1.4)
		_shake(0.4)
	if _phase_t <= 0.0:
		model.position.y = data.hover
		collision_layer = _home_layer
		phase = Phase.STALK
		_cd = 1.6
		_on_phase_begin(0)
	_animate(delta, 0.0)


# ---------------------------------------------------------------- death

func die() -> void:
	if is_dying:
		return
	if phase == Phase.INTRO:
		hp = max_hp
		return
	# Whatever killed it (an external hp change, a max_hp rescale), a phase is never skipped:
	# refuse death before the last phase and change phase instead.
	if phase_index < phase_lines.size():
		hp = maxf(hp, 1.0)
		if phase != Phase.TRANSITION:
			_begin_transition()
		return
	is_dying = true
	hp = 0.0
	Game.kills += 1
	_scheduled.clear()
	get_tree().call_group(&"boss_hazards", &"dissipate")
	set_deferred(&"collision_layer", 0)
	phase = Phase.DYING
	_death_t = 0.0
	Sfx.play(&"boss_death", 0.0)
	_shake(0.4)


func _dying_process(delta: float) -> void:
	_death_t += delta
	match phase:
		Phase.DYING:
			# Sinks a little and sheds light while it burns away.
			model.position.y = data.hover - clampf((_death_t - DEATH_KNEEL) / DEATH_BURN, 0.0, 1.0) * 0.6
			if randf() < delta * 12.0:
				HolyFX.motes(global_position + Vector3(randf_range(-0.8, 0.8), randf_range(0.5, 3.5), randf_range(-0.8, 0.8)),
						2, Art.HOLY, 0.4, 1.6, 0.9)
			if _death_t >= DEATH_FLASH_AT:
				_felled()
		Phase.FELLED:
			if _death_t >= DEATH_FLASH_AT + FELLED_TIME:
				queue_free()
				return
	_animate(delta, 0.0)


func _felled() -> void:
	phase = Phase.FELLED
	Game.boss_died.emit(global_position)
	var center := global_position + Vector3(0.0, 1.8, 0.0)
	HolyFX.flash(center, 9.0, 1.0, Art.HOLY_WHITE, 4.0)
	HolyFX.column(global_position, 2.0, 34.0, 1.4, Art.HOLY, 2.0)
	HolyFX.motes(center, 40, Art.HOLY, 3.0, 3.0, 2.0)
	HolyFX.feathers(center + Vector3(0.0, 1.0, 0.0), 22, 2.4, 3.0)
	HolyFX.ash(global_position, 10.0, 6.0, 140)
	ObjectiveFX.corruption_burst(global_position, 1.4)
	_shake(0.8)
	Sfx.play(&"impact", 0.0, 2.0)
	_toast(felled_text, TOAST_FELLED)
	_felled_fx()
	var tw := model.create_tween()
	tw.tween_property(model, "scale", Vector3.ONE * 0.01, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(model.hide)
	_drop_xp()
	BloodChalice.try_drop(global_position + Vector3(1.6, 0.0, 0.8), 1.0)
	ReliquaryOfSin.drop(global_position, ObjectiveDirector.xp_for_levels(3.0), 1.0)


# ---------------------------------------------------------------- helpers

func _schedule(delay: float, fn: Callable) -> void:
	_scheduled.append([delay, fn])


func _run_scheduled(delta: float) -> void:
	if _scheduled.is_empty():
		return
	var due: Array[Callable] = []
	for i in range(_scheduled.size() - 1, -1, -1):
		var item: Array = _scheduled[i]
		item[0] = float(item[0]) - delta
		if float(item[0]) <= 0.0:
			due.append(item[1])
			_scheduled.remove_at(i)
	for fn in due:
		fn.call()


func _update_hit_feedback(delta: float) -> void:
	if _flash_t > 0.0:
		_flash_t = maxf(_flash_t - delta, 0.0)
		model.set_flash(_flash_t / FLASH_TIME)
	if _squash > 0.0 and not is_dying:
		_squash = maxf(_squash - delta * 7.0, 0.0)
		var k := _squash * 0.03
		var s := data.size
		model.scale = Vector3(s * (1.0 + k), s * (1.0 - k), s * (1.0 + k))


func _forward() -> Vector3:
	var yaw := model.rotation.y
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func _turn_toward(dir: Vector3, rate: float, delta: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	model.rotation.y = lerp_angle(model.rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-rate * delta))


func _relocate(player: Player, dir_to_player: Vector3) -> void:
	var ahead := dir_to_player.rotated(Vector3.UP, randf_range(-0.5, 0.5))
	global_position = ObjectiveFX.walkable(player.global_position + ahead * 12.0)
	reset_physics_interpolation()
	HolyFX.column(global_position, 1.0, 26.0, 0.8, Art.HOLY, 1.4)


func _toast(text: String, color: Color) -> void:
	var hud := get_tree().get_first_node_in_group(&"hud")
	if hud and hud.has_method(&"toast"):
		hud.call(&"toast", text, color)


func _shake(amount: float) -> void:
	get_tree().call_group(&"camera_rig", &"shake", amount)
