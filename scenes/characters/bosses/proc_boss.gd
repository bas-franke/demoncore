class_name ProcBoss
extends Enemy
## Data-driven multi-phase boss for the procedural boss models (characters-new). A subclass only
## fills `cfg` in _configure() (names, phase lines, attack patterns per phase, minions, numbers)
## and supplies a ProcModel through its EnemyData; this script runs the fight with the shared,
## telegraphed boss hazards (InquisitorLane, PyreBurst, BellRing, JudgementPillar, SarielOrb):
##
##   attack kinds (pattern entries):
##     &"lanes"  fan of lanes from the boss at the demon       &"cross"  two crossing lanes on the demon
##     &"chase"  pillars that land where the demon stands      &"rain"   pillars scattered around it
##     &"pyre"   a disc of fire around the boss (get out)      &"sweep"  a wide arc in front
##     &"bells"  expanding rings (be outside or dash through)  &"orbs"   a radial burst of orbs
##     &"charge" a lane, then the boss rushes along it         &"summon" phase minions join
##
## Phase changes: the boss rises (untouchable), a short ring of fire pushes the demon off, minions
## arrive; damage never skips a phase. Boss bar / story hooks: `phase_index`, `phase_count`,
## `phase_thresholds()`, `phase_name()`, `is_enraged`, Game.boss_spawned / boss_phase_changed /
## boss_died, groups "boss" + "enemies".
##
## Model contract (all optional, set with Object.set so any ProcModel works): `attack_kind`
## (StringName of the attack being told / released), `boss_phase` (int), `rise` (0..1, phase
## change), `kneel` (0..1, dying). The model's State is WINDUP while telling, ATTACKING for the
## release beat, RECOVER after.

enum Phase { INTRO, STALK, TELL, STRIKE, RECOVER, TRANSITION, CHARGING, DYING, FELLED }

const INTRO_TIME := 2.6
const TRANSITION_TIME := 2.2
const BOSS_RELOCATE_DISTANCE := 30.0
const DEATH_TIME := 2.4

var phase_index := 0
var phase_count := 3
var is_enraged := false
var phase := Phase.INTRO

## Boss definition (see _configure()).
var cfg := {
	"title": "BOSS",
	"felled": "FELLED",
	"phase_lines": [0.66, 0.33],
	"phase_names": ["I", "II", "III"],
	"patterns": [[&"lanes"], [&"lanes", &"pyre"], [&"lanes", &"pyre", &"bells"]],
	"minions": [[], [], []],
	"cooldown": [3.0, 2.6, 2.0],
	"tell_mult": [1.0, 0.9, 0.8],
	"speed_mult": [1.0, 1.1, 1.25],
	"keep_distance": 4.5,
	"attack_range": 16.0,
	"damage": 1.0,
	"intro_color": Art.HOLY,
	## Colour of this boss's hazards (lanes, pillars, rings, discs, orbs); Art.HOLY = default.
	"hazard_tint": Art.HOLY,
	"hover": 0.0,
}

var _phase_t := 0.0
var _attack := &"lanes"
var _cd := 1.6
var _pattern_i := 0
var _boss_aim := Vector3.FORWARD
var _home_layer := 4
var _landed := false
var _death_t := 0.0
var _charge_v := Vector3.ZERO
## Seconds of recovery after the current attack's strike beat.
var _recover := 1.0
var _scheduled: Array = []  # [time_left, Callable]


## Override: fill `cfg` (merge your keys over the defaults).
func _configure() -> void:
	pass


func _ready() -> void:
	_configure()
	super()
	add_to_group(&"boss")
	phase_count = (cfg["phase_lines"] as Array).size() + 1
	_begin_intro()


func phase_thresholds() -> Array[float]:
	var out: Array[float] = []
	for v in cfg["phase_lines"]:
		out.append(float(v))
	return out


func phase_name() -> String:
	var names: Array = cfg["phase_names"]
	return String(names[clampi(phase_index, 0, names.size() - 1)])


## Every hazard cast inside the boss's frame takes the boss's tint (HolyFX.hazard_tint scope).
func _physics_process(delta: float) -> void:
	HolyFX.hazard_tint = cfg["hazard_tint"]
	_boss_process(delta)
	HolyFX.hazard_tint = Art.HOLY


func _boss_process(delta: float) -> void:
	_update_feedback(delta)
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
			return
		Phase.TRANSITION:
			hp = maxf(hp, max_hp * _line(phase_index - 1))
			_model_set(&"rise", clampf(1.0 - absf(_phase_t / TRANSITION_TIME * 2.0 - 1.0), 0.0, 1.0))
			_turn_toward(dir, 2.0, delta)
			if _phase_t <= 0.0:
				_end_transition()
		Phase.STALK:
			if dist > BOSS_RELOCATE_DISTANCE:
				_relocate(player, dir)
				return
			var spd := speed * float(cfg["speed_mult"][phase_index])
			var keep := float(cfg["keep_distance"])
			if dist > keep * 2.6:
				spd *= 1.8
			if dist > keep:
				move = dir * spd
			elif dist < keep * 0.6:
				move = -dir * spd * 0.4
			_turn_toward(dir, 3.0, delta)
			_cd -= delta
			if _cd <= 0.0 and not player.is_dead and dist < float(cfg["attack_range"]):
				_start_attack(dir)
		Phase.TELL:
			var locked := _attack in [&"sweep", &"charge", &"lanes"]
			_turn_toward(_boss_aim if locked else dir, 4.0, delta)
			if not locked:
				_boss_aim = dir
			if _phase_t <= 0.0:
				_release(player)
		Phase.CHARGING:
			move = _charge_v
			if _phase_t <= 0.0:
				_charge_v = Vector3.ZERO
				phase = Phase.RECOVER
				_phase_t = 0.9
		Phase.STRIKE, Phase.RECOVER:
			move = dir * speed * 0.25
			_turn_toward(dir, 2.0, delta)
			if phase == Phase.STRIKE and _phase_t <= 0.0:
				phase = Phase.RECOVER
				_phase_t = _recover
			elif phase == Phase.RECOVER and _phase_t <= 0.0:
				phase = Phase.STALK
				_model_set(&"attack_kind", &"")
				_cd = float(cfg["cooldown"][phase_index]) * randf_range(0.85, 1.15)
	velocity = move
	move_and_slide()
	position.y = 0.0
	_animate(delta, clampf(move.length() / maxf(speed, 0.01), 0.0, 1.0))


# ---------------------------------------------------------------- damage / phases

func take_damage(amount: float, _kb := Vector3.ZERO) -> void:  # this boss ignores knockback
	if is_dying or phase == Phase.INTRO or phase == Phase.TRANSITION:
		return
	var lines: Array = cfg["phase_lines"]
	var crossing := false
	if phase_index < lines.size():
		var line_hp := max_hp * float(lines[phase_index])
		if hp - amount <= line_hp:
			amount = maxf(hp - line_hp, 0.0)
			crossing = true
	super(amount, Vector3.ZERO)
	if crossing and not is_dying:
		HolyFX.hazard_tint = cfg["hazard_tint"]
		_begin_transition()
		HolyFX.hazard_tint = Art.HOLY


func die() -> void:
	if is_dying:
		return
	if phase == Phase.INTRO:
		hp = max_hp
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


func _line(index: int) -> float:
	var lines: Array = cfg["phase_lines"]
	if index < 0 or index >= lines.size():
		return 0.0
	return float(lines[index])


func _begin_transition() -> void:
	phase_index = mini(phase_index + 1, phase_count - 1)
	is_enraged = phase_index >= phase_count - 1
	phase = Phase.TRANSITION
	_phase_t = TRANSITION_TIME
	_scheduled.clear()
	get_tree().call_group(&"boss_hazards", &"dissipate")
	_model_set(&"boss_phase", phase_index)
	_model_set(&"attack_kind", &"")
	_toast("%s  -  Phase %d" % [phase_name().to_upper(), phase_index + 1], Color("f2c66b"))
	Sfx.play(&"choir", 0.0, 2.0)
	_shake(0.45)
	var c: Color = cfg["intro_color"]
	HolyFX.flash(global_position + Vector3(0.0, 2.0, 0.0), 4.0, 0.7, Art.HOLY_WHITE, 3.0)
	HolyFX.column(global_position, 1.6, 30.0, TRANSITION_TIME, c, 1.6)
	PyreBurst.cast(global_position, 3.6, TRANSITION_TIME * 0.7, 14.0 * float(cfg["damage"]))
	Game.boss_phase_changed.emit(self, phase_index)


func _end_transition() -> void:
	_model_set(&"rise", 0.0)
	_summon()
	phase = Phase.STALK
	_cd = 0.8


func _summon() -> void:
	var minions: Array = cfg["minions"]
	if phase_index >= minions.size():
		return
	for id in minions[phase_index]:
		ObjectiveFX.spawn_enemy(String(id), ObjectiveFX.ring_point(global_position, randf_range(3.0, 5.0)), 0.8)


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
	HolyFX.column(global_position, 1.4, 30.0, INTRO_TIME + 0.4, cfg["intro_color"], 1.4)
	_toast(String(cfg["title"]), Color("e8d6a0"))
	Sfx.play(&"boss_intro", 0.0)
	_shake(0.25)


func _intro_process(delta: float, dir: Vector3) -> void:
	hp = max_hp
	var k := clampf(1.0 - _phase_t / INTRO_TIME, 0.0, 1.0)
	var e := 1.0 - (1.0 - k) * (1.0 - k)
	model.position.y = lerpf(-4.0, data.hover, e)
	_turn_toward(dir, 3.0, delta)
	if k >= 0.7 and not _landed:
		_landed = true
		Sfx.play(&"impact", 0.0)
		HolyFX.motes(global_position + Vector3(0.0, 0.3, 0.0), 20, cfg["intro_color"], 2.5, 1.5, 1.4)
		_shake(0.4)
	if _phase_t <= 0.0:
		model.position.y = data.hover
		collision_layer = _home_layer
		phase = Phase.STALK
		_cd = 1.6
	_animate(delta, 0.0)


# ---------------------------------------------------------------- attacks

func _start_attack(dir: Vector3) -> void:
	var pattern: Array = cfg["patterns"][phase_index]
	_attack = pattern[_pattern_i % pattern.size()]
	_pattern_i += 1
	_boss_aim = dir
	var tell: Variant = {&"lanes": 0.55, &"cross": 0.5, &"chase": 0.35, &"rain": 0.5, &"pyre": 0.35,
		&"sweep": 0.35, &"bells": 0.6, &"orbs": 0.55, &"charge": 0.4, &"summon": 0.8}.get(_attack, 0.5)
	_phase_t = float(tell) * float(cfg["tell_mult"][phase_index])
	phase = Phase.TELL
	_model_set(&"attack_kind", _attack)
	if _attack == &"charge":
		# The lane shows the whole rush during the tell; the boss follows it on release.
		var tm := float(cfg["tell_mult"][phase_index])
		InquisitorLane.cast(global_position, _boss_aim, 16.0, 2.0, (0.4 + 0.9) * tm, 24.0 * _dmg())
	Sfx.play(&"boss_charge", 0.05, -8.0)


func _dmg() -> float:
	return float(cfg["damage"])


func _release(player: Player) -> void:
	var tm := float(cfg["tell_mult"][phase_index])
	var p := player.global_position
	p.y = 0.0
	var recover := 1.0
	model.play_attack()
	match _attack:
		&"lanes":
			var count := 3 + phase_index * 2
			for i in count:
				var off := (float(i) - float(count - 1) * 0.5) * 0.34
				InquisitorLane.cast(global_position, _boss_aim.rotated(Vector3.UP, off), 14.0, 1.1, 1.0 * tm, 20.0 * _dmg())
			recover = 1.2
		&"cross":
			_cross(p, 0.0, tm)
			if phase_index >= 2:
				_schedule(0.7, _cross_on_player.bind(PI * 0.25, tm))
			recover = 1.3
		&"chase":
			var n := 4 + phase_index
			for i in n:
				_schedule(0.42 * i, _pillar_on_player.bind(0.85 * tm))
			recover = 0.42 * n + 0.3
		&"rain":
			JudgementPillar.cast(p, 1.5, 1.1 * tm, 18.0 * _dmg())
			for i in 7 + phase_index * 2:
				var a := randf() * TAU
				JudgementPillar.cast(p + Vector3(cos(a), 0.0, sin(a)) * randf_range(2.0, 8.0), 1.5, 1.1 * tm + 0.12 * i, 18.0 * _dmg())
			recover = 1.5
		&"pyre":
			PyreBurst.cast(global_position, 6.0, 1.4 * tm, 26.0 * _dmg())
			if phase_index >= 2:
				_schedule(0.9, _pyre_on_player.bind(1.0 * tm))
			recover = 1.7
		&"sweep":
			PyreBurst.cast(global_position, 6.5, 0.95 * tm, 22.0 * _dmg(), _boss_aim, 1.7)
			recover = 1.2
		&"bells":
			for i in 2 + mini(phase_index, 1):
				BellRing.cast(global_position, 15.0, 6.5, 0.9, 18.0 * _dmg(), 0.7 + 1.0 * i)
			recover = 2.2
		&"orbs":
			var n := 10 + phase_index * 4
			var base := randf() * TAU
			for i in n:
				var a := base + TAU * float(i) / float(n)
				SarielOrb.fire(global_position + Vector3(0.0, 1.2, 0.0), Vector3(cos(a), 0.0, sin(a)) * 6.0, 14.0 * _dmg(), 3.5)
			if phase_index >= 1:
				_schedule(0.6, _orb_ring.bind(n, base + PI / float(n)))
			recover = 1.4
		&"charge":
			# The lane was cast at the start of the tell; rush along it as it strikes.
			_charge_v = _boss_aim * 16.0 / 0.45
			phase = Phase.CHARGING
			_phase_t = 0.45
			return
		&"summon":
			_summon()
			recover = 1.2
	phase = Phase.STRIKE
	_phase_t = 0.35
	_recover = maxf(recover - 0.35, 0.3)


func _orb_ring(n: int, base: float) -> void:
	if is_dying:
		return
	for i in n:
		var a := base + TAU * float(i) / float(n)
		SarielOrb.fire(global_position + Vector3(0.0, 1.2, 0.0), Vector3(cos(a), 0.0, sin(a)) * 5.0, 14.0 * _dmg(), 3.5)


func _pillar_on_player(tell: float) -> void:
	var p := Game.player
	if p == null or not is_instance_valid(p) or p.is_dead or is_dying:
		return
	JudgementPillar.cast(p.global_position, 1.35, tell, 20.0 * _dmg())


func _cross_on_player(angle: float, tm: float) -> void:
	if Game.player and not is_dying:
		_cross(Game.player.global_position, angle, tm)


func _pyre_on_player(tell: float) -> void:
	if Game.player and not is_dying:
		PyreBurst.cast(Game.player.global_position, 2.6, tell, 20.0 * _dmg())


func _cross(at: Vector3, angle: float, tm: float) -> void:
	if is_dying:
		return
	for k in 2:
		var d := _boss_aim.rotated(Vector3.UP, angle + PI * 0.5 * k)
		InquisitorLane.cast(at - d * 8.5, d, 17.0, 1.3, 1.15 * tm, 24.0 * _dmg())


# ---------------------------------------------------------------- death

func _dying_process(delta: float) -> void:
	_death_t += delta
	_model_set(&"kneel", clampf(_death_t / 1.2, 0.0, 1.0))
	if randf() < delta * 12.0:
		HolyFX.motes(global_position + Vector3(randf_range(-0.6, 0.6), randf_range(0.5, 3.0), randf_range(-0.6, 0.6)),
				2, cfg["intro_color"], 0.4, 1.6, 0.9)
	if phase == Phase.DYING and _death_t >= DEATH_TIME:
		_felled()
	elif phase == Phase.FELLED and _death_t >= DEATH_TIME + 0.9:
		queue_free()
		return
	_animate(delta, 0.0)


func _felled() -> void:
	phase = Phase.FELLED
	Game.boss_died.emit(global_position)
	var center := global_position + Vector3(0.0, 1.8, 0.0)
	HolyFX.flash(center, 9.0, 1.0, Art.HOLY_WHITE, 4.0)
	HolyFX.column(global_position, 2.0, 34.0, 1.4, cfg["intro_color"], 2.0)
	HolyFX.motes(center, 40, cfg["intro_color"], 3.0, 3.0, 2.0)
	ObjectiveFX.corruption_burst(global_position, 1.4)
	_shake(0.8)
	Sfx.play(&"impact", 0.0, 2.0)
	_toast(String(cfg["felled"]), Color("e6c26e"))
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


func _model_set(field: StringName, value: Variant) -> void:
	if model and field in model:
		model.set(field, value)


func _animate(delta: float, move_ratio: float) -> void:
	var st := EnemyModel.State.MOVING
	match phase:
		Phase.TELL, Phase.TRANSITION:
			st = EnemyModel.State.WINDUP
		Phase.STRIKE, Phase.CHARGING:
			st = EnemyModel.State.ATTACKING
		Phase.RECOVER:
			st = EnemyModel.State.RECOVER
	model.state_progress = clampf(1.0 - _phase_t, 0.0, 1.0)
	model.ground_speed = velocity.length()
	model.body_scale = data.size
	model.animate(delta, move_ratio, st)


func _update_feedback(delta: float) -> void:
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
	HolyFX.column(global_position, 1.0, 26.0, 0.8, cfg["intro_color"], 1.4)


func _toast(text: String, color: Color) -> void:
	var hud := get_tree().get_first_node_in_group(&"hud")
	if hud and hud.has_method(&"toast"):
		hud.call(&"toast", text, color)


func _shake(amount: float) -> void:
	get_tree().call_group(&"camera_rig", &"shake", amount)
