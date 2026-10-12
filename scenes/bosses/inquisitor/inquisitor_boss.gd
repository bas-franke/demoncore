class_name InquisitorBoss
extends Enemy
## "Ozias, the Grand Inquisitor": a three-phase angelic judge. Reuses Enemy's setup / damage /
## flash; replaces the AI with a slow stalk and clearly telegraphed attacks, every one drawn on
## the ground before it lands (lanes, sigils, rings):
##   Phase I   Interrogation (100-66%)  Chains of Penance (fanned lanes), Brand (pillars that chase
##                                      the demon), Censure (a cross of lanes on the demon)
##   Phase II  Trial by Fire  (66-33%)  + Sanctified Pyre (a disc of fire around itself: get out),
##                                      Censer Sweep (a wide arc in front), Censer Clerics join
##   Phase III Auto-da-fe     (< 33%)   + Bell of Judgement (expanding rings: be outside or dash
##                                      through), Rain of Judgement, double crosses, faster tells
## Each phase change: it rises, untouchable for a moment, flings its arms wide (a short pyre
## around itself) and calls minions. Damage can never skip a phase (it is clamped at the line).
## UI hooks: `phase_index` (0..2), `phase_count` (3), `phase_name()`, `is_enraged` (last phase),
## Game.boss_phase_changed(boss, phase). In groups "enemies" and "boss".

enum Phase { INTRO, STALK, TELL, RECOVER, TRANSITION, DYING, FELLED }
enum Attack { CHAINS, BRAND, CENSURE, PYRE, SWEEP, BELLS, RAIN }

const PHASE_LINES: Array[float] = [0.66, 0.33]
const PHASE_NAMES: Array[String] = ["Interrogation", "Trial by Fire", "Auto-da-fe"]
const PATTERNS := [
	[Attack.CHAINS, Attack.BRAND, Attack.CENSURE, Attack.CHAINS, Attack.BRAND],
	[Attack.PYRE, Attack.CHAINS, Attack.SWEEP, Attack.CENSURE, Attack.BRAND, Attack.SWEEP],
	[Attack.BELLS, Attack.CHAINS, Attack.SWEEP, Attack.RAIN, Attack.CENSURE, Attack.PYRE, Attack.BELLS, Attack.BRAND],
]
## Minions called at the start of phase II / III (enemy ids, data/enemies/).
const PHASE_MINIONS := [[], ["thurible_priest", "thurible_priest", "thurible_priest"],
	["penitent_statue", "penitent_statue", "choir_wisp", "choir_wisp", "choir_wisp"]]

const INTRO_TIME := 2.6
const TRANSITION_TIME := 2.4
const FIRST_ATTACK_DELAY := 1.6
const ATTACK_COOLDOWN := [3.0, 2.6, 2.0]
const TELL_MULT := [1.0, 0.92, 0.8]
const SPEED_MULT := [1.0, 1.1, 1.25]
const KEEP_DISTANCE := 4.5
const ATTACK_RANGE := 16.0
const CATCH_UP_DISTANCE := 13.0
const BOSS_RELOCATE_DISTANCE := 30.0
const TURN_RATE := 3.0

const CHAIN_LENGTH := 14.0
const CHAIN_WIDTH := 1.1
const CHAIN_DAMAGE := 22.0
const BRAND_DAMAGE := 20.0
const CROSS_LENGTH := 17.0
const CROSS_DAMAGE := 24.0
const PYRE_RADIUS := 6.2
const PYRE_DAMAGE := 26.0
const SWEEP_RADIUS := 6.0
const SWEEP_HALF := 1.75  # ~100 degrees each side
const SWEEP_DAMAGE := 22.0
const BELL_RADIUS := 15.0
const BELL_SPEED := 6.5
const BELL_DAMAGE := 18.0
const RAIN_DAMAGE := 18.0

const DEATH_KNEEL := 0.6
const DEATH_BURN := 1.8
const DEATH_FLASH_AT := 2.6
const FELLED_TIME := 0.9

const TOAST_NAME := Color("e8d6a0")
const TOAST_PHASE := Color("f2c66b")
const TOAST_FELLED := Color("e6c26e")

var phase_index := 0
var phase_count := 3
## True in the last phase (the boss bar pulses).
var is_enraged := false
var phase := Phase.INTRO

var _phase_t := 0.0
var _tell_len := 0.0
var _attack := Attack.CHAINS
var _cd := FIRST_ATTACK_DELAY
var _pattern_i := 0
var _home_layer := 4
var _landed := false
var _death_t := 0.0
# QA: renamed from _aim, which now clashes with Enemy._aim (enemy.gd, gameplay role).
var _sweep_aim := Vector3.FORWARD
var _scheduled: Array = []  # [time_left: float, Callable]
var _im: InquisitorModel


func _ready() -> void:
	super()
	add_to_group(&"boss")
	_im = model as InquisitorModel
	_begin_intro()


## HP ratios where the phase changes (the boss bar draws a notch at each).
func phase_thresholds() -> Array[float]:
	return PHASE_LINES


func phase_name() -> String:
	return PHASE_NAMES[clampi(phase_index, 0, PHASE_NAMES.size() - 1)]


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
				_end_transition()
		Phase.STALK:
			if dist > BOSS_RELOCATE_DISTANCE:
				_relocate(player, dir)
				return
			var spd := speed * float(SPEED_MULT[phase_index])
			if dist > CATCH_UP_DISTANCE:
				spd *= 2.0
			if dist > KEEP_DISTANCE:
				move = dir * spd
			elif dist < KEEP_DISTANCE * 0.6:
				move = -dir * spd * 0.4
			_turn_toward(dir, TURN_RATE, delta)
			_cd -= delta
			if _cd <= 0.0 and not player.is_dead and dist < ATTACK_RANGE:
				_start_attack(dir)
		Phase.TELL:
			# The sweep keeps the aim it locked at the start; the rest track the demon.
			_turn_toward(_sweep_aim if _attack == Attack.SWEEP else dir, 4.0, delta)
			if _phase_t <= 0.0:
				_release_attack(player)
		Phase.RECOVER:
			move = dir * speed * 0.3
			_turn_toward(dir, 2.0, delta)
			if _phase_t <= 0.0:
				_im_set(&"raise", 0.0)
				_im_set(&"book", 0.0)
				_im_set(&"wide", 0.0)
				phase = Phase.STALK
				_cd = float(ATTACK_COOLDOWN[phase_index]) * randf_range(0.85, 1.15)
	velocity = move
	move_and_slide()
	position.y = 0.0
	_animate(delta, clampf(move.length() / maxf(speed, 0.01), 0.0, 1.0))


# ---------------------------------------------------------------- damage / phases

func take_damage(amount: float, knockback := Vector3.ZERO) -> void:
	if is_dying or phase == Phase.INTRO or phase == Phase.TRANSITION:
		return
	# Never skip a phase: a big hit stops at the line, and the next phase begins.
	var crossing := false
	if phase_index < PHASE_LINES.size():
		var line_hp := max_hp * PHASE_LINES[phase_index]
		# hp - amount <= line also catches hp already under the line (max_hp rescaled mid-fight).
		if hp - amount <= line_hp:
			amount = maxf(hp - line_hp, 0.0)
			crossing = true
	super(amount, knockback)
	# On-hit effects (Game.enemy_struck listeners) may re-enter take_damage during super() and
	# start the transition themselves: never begin it twice.
	if crossing and not is_dying and phase != Phase.TRANSITION:
		_begin_transition()


func die() -> void:
	if is_dying:
		return
	if phase == Phase.INTRO:
		hp = max_hp
		return
	# Whatever killed it (an external hp change, a max_hp rescale), a phase is never skipped:
	# refuse death before the last phase and change phase instead.
	if phase_index < PHASE_LINES.size():
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
	_im_set(&"kneel", 1.0)
	_im_set(&"raise", 0.0)
	_im_set(&"book", 0.0)
	_im_set(&"wide", 0.0)
	Sfx.play(&"boss_death", 0.0)
	_shake(0.4)


func _line(index: int) -> float:
	if index < 0 or index >= PHASE_LINES.size():
		return 0.0
	return PHASE_LINES[index]


func _begin_transition() -> void:
	phase_index = mini(phase_index + 1, phase_count - 1)
	is_enraged = phase_index >= phase_count - 1
	phase = Phase.TRANSITION
	_phase_t = TRANSITION_TIME
	_scheduled.clear()
	get_tree().call_group(&"boss_hazards", &"dissipate")
	_im_set(&"wide", 1.0)
	_im_set(&"raise", 0.0)
	_im_set(&"book", 0.0)
	_im_set(&"burn", float(phase_index))
	_toast("%s  -  %s" % [PHASE_NAMES[phase_index].to_upper(), "Phase %s" % UIPalette.roman(phase_index + 1)], TOAST_PHASE)
	Sfx.play(&"toll", 0.0, 3.0)
	Sfx.play(&"choir", 0.0, 2.0)
	_shake(0.45)
	HolyFX.flash(global_position + Vector3(0.0, 2.0, 0.0), 4.0, 0.7, Art.HOLY_WHITE, 3.0)
	HolyFX.column(global_position, 1.6, 30.0, TRANSITION_TIME, Art.HOLY, 1.6)
	# A ring of fire around it at the end of the rise pushes the demon out of melee.
	PyreBurst.cast(global_position, 3.6, TRANSITION_TIME * 0.7, 14.0)
	Game.boss_phase_changed.emit(self, phase_index)


func _end_transition() -> void:
	_im_set(&"wide", 0.0)
	for id: String in PHASE_MINIONS[phase_index]:
		ObjectiveFX.spawn_enemy(id, ObjectiveFX.ring_point(global_position, randf_range(3.0, 5.0)), 0.8)
	phase = Phase.STALK
	_cd = 0.8


# ---------------------------------------------------------------- intro

func _begin_intro() -> void:
	phase = Phase.INTRO
	_phase_t = INTRO_TIME
	Game.boss_spawned.emit(self)
	_home_layer = collision_layer
	collision_layer = 0
	model.position.y = -4.0
	_intro_fx.call_deferred()


func _intro_fx() -> void:
	if not is_inside_tree():
		return
	HolyFX.column(global_position, 1.4, 30.0, INTRO_TIME + 0.4, Art.HOLY, 1.4)
	_toast(data.display_name.to_upper() if data else "THE GRAND INQUISITOR", TOAST_NAME)
	Sfx.play(&"boss_intro", 0.0)
	Sfx.play(&"toll", 0.0, 0.0)
	_shake(0.25)


## It rises out of a sigil of light, censer swinging.
func _intro_process(delta: float, dir: Vector3) -> void:
	hp = max_hp
	var k := clampf(1.0 - _phase_t / INTRO_TIME, 0.0, 1.0)
	var e := 1.0 - (1.0 - k) * (1.0 - k)
	model.position.y = lerpf(-4.0, data.hover, e)
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
		_cd = FIRST_ATTACK_DELAY
	_animate(delta, 0.0)


# ---------------------------------------------------------------- attacks

func _start_attack(dir: Vector3) -> void:
	var pattern: Array = PATTERNS[phase_index]
	_attack = pattern[_pattern_i % pattern.size()]
	_pattern_i += 1
	_sweep_aim = dir
	var tm := float(TELL_MULT[phase_index])
	var tell := 0.6
	match _attack:
		Attack.CHAINS:
			tell = 0.55
			_im_set(&"book", 1.0)
			Sfx.play(&"cast", 0.05, -4.0)
		Attack.BRAND:
			tell = 0.35
			_im_set(&"book", 1.0)
		Attack.CENSURE:
			tell = 0.6
			_im_set(&"raise", 1.0)
			Sfx.play(&"boss_charge", 0.05, -6.0)
		Attack.PYRE:
			tell = 0.3
			_im_set(&"wide", 1.0)
		Attack.SWEEP:
			tell = 0.3
			_im_set(&"raise", 0.6)
		Attack.BELLS:
			tell = 0.6
			_im_set(&"raise", 1.0)
			Sfx.play(&"toll", 0.0, -2.0)
		Attack.RAIN:
			tell = 0.5
			_im_set(&"wide", 1.0)
			Sfx.play(&"choir", 0.05, -3.0)
	_tell_len = tell * tm
	phase = Phase.TELL
	_phase_t = _tell_len


func _release_attack(player: Player) -> void:
	var tm := float(TELL_MULT[phase_index])
	var p := player.global_position
	p.y = 0.0
	var recover := 1.0
	match _attack:
		Attack.CHAINS:
			var count := 3 if phase_index == 0 else 5
			var spread := 0.38 if phase_index == 0 else 0.3
			for i in count:
				var off := (float(i) - float(count - 1) * 0.5) * spread
				InquisitorLane.cast(global_position, _sweep_aim.rotated(Vector3.UP, off), CHAIN_LENGTH, CHAIN_WIDTH, 1.0 * tm, CHAIN_DAMAGE)
			Sfx.play(&"chain", 0.05, 0.0)
			recover = 1.2
		Attack.BRAND:
			# Brands follow the demon: each lands where it is when that brand is cast.
			var n := 4 if phase_index < 2 else 6
			for i in n:
				_schedule(0.42 * i, _brand.bind(0.85 * tm))
			recover = 0.42 * n + 0.4
		Attack.CENSURE:
			_cross(p, 0.0, tm)
			if phase_index >= 2:
				_schedule(0.7, _cross_on_player.bind(PI * 0.25, tm))
			recover = 1.4
		Attack.PYRE:
			PyreBurst.cast(global_position, PYRE_RADIUS, 1.5 * tm, PYRE_DAMAGE)
			if phase_index >= 2:
				_schedule(0.9, _pyre_on_player.bind(1.0 * tm))
			Sfx.play(&"brimstone", 0.05, -6.0)
			recover = 1.8
		Attack.SWEEP:
			PyreBurst.cast(global_position, SWEEP_RADIUS, 0.95 * tm, SWEEP_DAMAGE, _sweep_aim, SWEEP_HALF)
			recover = 1.2
		Attack.BELLS:
			for i in 3:
				BellRing.cast(global_position, BELL_RADIUS, BELL_SPEED, 0.9, BELL_DAMAGE, 0.7 + 1.0 * i)
			recover = 2.4
		Attack.RAIN:
			JudgementPillar.cast(p, 1.5, 1.1 * tm, RAIN_DAMAGE)
			for i in 9:
				var a := randf() * TAU
				var at := p + Vector3(cos(a), 0.0, sin(a)) * randf_range(2.0, 8.0)
				JudgementPillar.cast(at, 1.5, 1.1 * tm + 0.12 * i, RAIN_DAMAGE)
			recover = 1.6
	phase = Phase.RECOVER
	_phase_t = recover
	if _im:
		HolyFX.flash(_im.book_global() if _attack in [Attack.CHAINS, Attack.BRAND] else _im.censer_global(),
				1.2, 0.35, Art.HOLY_WHITE, 2.5)


func _brand(tell: float) -> void:
	var p := Game.player
	if p == null or not is_instance_valid(p) or p.is_dead or is_dying:
		return
	JudgementPillar.cast(p.global_position, 1.35, tell, BRAND_DAMAGE)


func _cross_on_player(angle: float, tm: float) -> void:
	if Game.player and not is_dying:
		_cross(Game.player.global_position, angle, tm)


func _pyre_on_player(tell: float) -> void:
	if Game.player and not is_dying:
		PyreBurst.cast(Game.player.global_position, 2.6, tell, PYRE_DAMAGE * 0.8)


## Two crossing lanes centred on `at`, the first along `angle` from the boss's aim.
func _cross(at: Vector3, angle: float, tm: float) -> void:
	if is_dying:
		return
	for k in 2:
		var d := _sweep_aim.rotated(Vector3.UP, angle + PI * 0.5 * k)
		InquisitorLane.cast(at - d * CROSS_LENGTH * 0.5, d, CROSS_LENGTH, 1.3, 1.15 * tm, CROSS_DAMAGE)


# ---------------------------------------------------------------- death

func _dying_process(delta: float) -> void:
	_death_t += delta
	match phase:
		Phase.DYING:
			_im_set(&"dissolve", clampf((_death_t - DEATH_KNEEL) / DEATH_BURN, 0.0, 1.0))
			if randf() < delta * 12.0:
				HolyFX.motes(global_position + Vector3(randf_range(-0.6, 0.6), randf_range(0.5, 3.0), randf_range(-0.6, 0.6)),
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
	HolyFX.ash(global_position, 10.0, 6.0, 140)
	ObjectiveFX.corruption_burst(global_position, 1.4)
	_shake(0.8)
	Sfx.play(&"impact", 0.0, 2.0)
	Sfx.play(&"toll", 0.0, 4.0)
	_toast("INQUISITOR SILENCED", TOAST_FELLED)
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


func _im_set(field: StringName, value: float) -> void:
	if _im:
		_im.set(field, value)


func _animate(delta: float, move_ratio: float) -> void:
	var st := EnemyModel.State.MOVING
	if phase == Phase.TELL or phase == Phase.TRANSITION:
		st = EnemyModel.State.WINDUP
	model.animate(delta, move_ratio, st)


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
