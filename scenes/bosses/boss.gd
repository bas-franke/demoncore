class_name Boss
extends Enemy
## "Sariel, Herald of the Last Dawn": a towering six-winged seraph. Reuses Enemy's setup /
## take_damage / flash and replaces the AI with a slow, majestic, clearly telegraphed cycle:
##   INTRO          descends from the sky inside a pillar of light (untouchable while descending).
##   GLIDE          glides toward the demon, wings beating.
##   PILLARS        raises its spear: 4-7 golden sigils charge ~1.2 s, then columns of light slam down.
##   SWEEP          the halo blazes; a 90-degree arc sigil charges, then a beam from the halo sweeps it.
##   HOST           opens its arms and calls 5-8 Choir Wisps out of the light.
##   DAWN RING      (enraged, < 40% HP) the halo flares and releases slow rings of holy orbs.
## Enraged: wings flung wide, brighter light, shorter cooldowns and tells.
## Death: kneels, its wings come apart into feathers and light, a blinding flash, falling ash,
## "HERALD FELLED", and a Reliquary of Sin worth ~3 levels. In groups "enemies" (scene) and "boss".

enum Phase { INTRO, GLIDE, PILLAR_TELL, SWEEP_TELL, SWEEP, HOST_TELL, NOVA_TELL, NOVA, RECOVER, DYING, FELLED }
enum Attack { PILLARS, SWEEP, HOST, NOVA }

const WISP_DATA_PATH := "res://data/enemies/choir_wisp.tres"
const MINION_SCENE: PackedScene = preload("res://scenes/enemies/enemy.tscn")

# EnemyModel.State values (moving / winding up / attacking).
const MODEL_MOVING := 0
const MODEL_WINDUP := 1
const MODEL_ATTACKING := 2

const ENRAGE_RATIO := 0.4
const RAGE_SPEED_MULT := 1.3
const RAGE_TELL_MULT := 0.82
const CATCH_UP_DISTANCE := 12.0
const CATCH_UP_MULT := 2.2
const BOSS_RELOCATE_DISTANCE := 30.0
const BOSS_RELOCATE_RADIUS := 13.0
const TURN_RATE := 2.5
const STOP_DISTANCE := 3.4
const ATTACK_RANGE := 15.0
const PLAYER_RADIUS := 0.4

const INTRO_DESCENT := 2.4
const INTRO_HOLD := 0.7
const ATTACK_COOLDOWN := 3.4
const RAGE_ATTACK_COOLDOWN := 2.4
const FIRST_ATTACK_DELAY := 2.0
const RECOVER_TIME := 1.0

const PILLAR_TELL := 1.2
const PILLAR_RAISE_TIME := 0.45
const PILLAR_STAGGER := 0.08
const PILLAR_RADIUS := 1.6
const PILLAR_DAMAGE := 24.0
const PILLAR_SPREAD := 6.5
const PILLAR_MIN_SEP := 2.4

const SWEEP_TELL := 1.35
const SWEEP_TIME := 1.7
const RAGE_SWEEP_TIME := 1.35
const BEAM_LENGTH := 13.0
const BEAM_HALF_ARC := PI / 4.0
const BEAM_HALF_WIDTH := 0.75
const BEAM_DAMAGE := 26.0

const HOST_TELL := 1.1
const HOST_MIN := 5
const HOST_MAX := 8
const MAX_MINIONS := 24

const NOVA_TELL := 0.95
const NOVA_TIME := 0.9
const NOVA_COUNT := 16
const NOVA_SPEED := 3.0
const NOVA_DAMAGE := 14.0
const NOVA_LIFE := 7.0

const DEATH_KNEEL := 0.5
const DEATH_DISSOLVE := 1.9
const DEATH_FLASH_AT := 2.6
const FELLED_TIME := 0.9

const TOAST_NAME := Color("e8d6a0")
const TOAST_RAGE := Color("f2c46a")
const TOAST_FELLED := Color("e6c26e")

const CALM_PATTERN: Array[int] = [Attack.PILLARS, Attack.SWEEP, Attack.HOST, Attack.PILLARS, Attack.SWEEP]
const RAGE_PATTERN: Array[int] = [Attack.PILLARS, Attack.NOVA, Attack.SWEEP, Attack.HOST, Attack.NOVA,
		Attack.PILLARS, Attack.SWEEP, Attack.NOVA]

var is_enraged := false
## Phase hooks shared with other bosses (boss bar notches, Game.boss_phase_changed): 0 calm, 1 enraged.
var phase_index := 0
var phase_count := 2
## Banners for the enrage and the death (other bosses reusing this AI, e.g. the Gate Archon, set them).
var rage_text := "The Herald's light burns brighter"
var felled_text := "HERALD FELLED"
var phase := Phase.INTRO

var _phase_t := 0.0
var _tell_len := 1.0
var _boss_cd := FIRST_ATTACK_DELAY
var _pattern_i := 0
var _intro_t := 0.0
var _landed := false
var _home_layer := 4
var _sweep_center := Vector3.FORWARD
var _sweep_sign := 1.0
var _sweep_hit := false
var _nova_second := false
var _death_t := 0.0
var _minion_ids: Array[int] = []
var _wisp_data: EnemyData
var _wisp_checked := false
var _telegraph: BossTelegraph
var _beam: RadiantBeam
var _sm: SarielModel


func _ready() -> void:
	super()
	add_to_group(&"boss")
	_sm = model as SarielModel
	_telegraph = BossTelegraph.new()
	add_child(_telegraph)
	_beam = RadiantBeam.new()
	add_child(_beam)
	_begin_intro()


func _physics_process(delta: float) -> void:
	_update_hit_feedback(delta)
	if is_dying:
		_dying_process(delta)
		return
	if phase == Phase.INTRO:
		_intro_process(delta)
		return
	var player := Game.player
	if player == null or not is_instance_valid(player):
		_animate_model(delta, 0.0)
		return

	var to := player.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	if dist > BOSS_RELOCATE_DISTANCE and phase == Phase.GLIDE:
		_relocate_boss(player, to / dist)
		return
	var dir := to / dist if dist > 0.001 else _forward()
	var player_alive := not player.is_dead

	if not is_enraged and hp <= max_hp * ENRAGE_RATIO:
		_enrage()

	var move := Vector3.ZERO
	_phase_t -= delta
	match phase:
		Phase.GLIDE:
			var spd := speed * (RAGE_SPEED_MULT if is_enraged else 1.0)
			if dist > CATCH_UP_DISTANCE:
				spd *= CATCH_UP_MULT
			if dist > STOP_DISTANCE:
				move = dir * spd
			_turn_toward(dir, TURN_RATE, delta)
			_boss_cd -= delta
			if _boss_cd <= 0.0 and player_alive and dist < ATTACK_RANGE:
				_start_attack(dir)
		Phase.PILLAR_TELL:
			_turn_toward(dir, 3.0, delta)
			if _phase_t <= 0.0:
				_cast_pillars(player)
		Phase.SWEEP_TELL:
			_turn_toward(_sweep_center, 5.0, delta)
			var k := clampf(1.0 - _phase_t / _tell_len, 0.0, 1.0)
			_telegraph.show_sector(global_position, _sweep_center, BEAM_LENGTH, BEAM_HALF_ARC, Art.HOLY, k,
					minf(k * 4.0, 1.0) * (0.8 + 0.2 * sin(k * 20.0)), 1.3 + k)
			# A thin warning ray already marks the edge the sweep starts from.
			var start_dir := _sweep_center.rotated(Vector3.UP, -_sweep_sign * BEAM_HALF_ARC)
			_aim_beam(start_dir, 0.1 * smoothstep(0.3, 1.0, k))
			if _phase_t <= 0.0:
				_begin_sweep()
		Phase.SWEEP:
			var length := RAGE_SWEEP_TIME if is_enraged else SWEEP_TIME
			var k := clampf(1.0 - _phase_t / length, 0.0, 1.0)
			var e := k * k * (3.0 - 2.0 * k)
			var beam_dir := _sweep_center.rotated(Vector3.UP, lerpf(-_sweep_sign, _sweep_sign, e) * BEAM_HALF_ARC)
			_turn_toward(beam_dir, 10.0, delta)
			var intensity := minf((length - _phase_t) / 0.12, 1.0) * minf(_phase_t / 0.15 + 0.2, 1.0)
			_aim_beam(beam_dir, intensity)
			_telegraph.show_sector(global_position, _sweep_center, BEAM_LENGTH, BEAM_HALF_ARC, Art.HOLY, 1.0, 0.45, 1.2)
			if not _sweep_hit and player_alive and _beam_hits(player.global_position, beam_dir):
				_sweep_hit = true
				player.take_damage(BEAM_DAMAGE)
				Sfx.play(&"holy_hit")
			if _phase_t <= 0.0:
				_beam.hide_now()
				_telegraph.hide_now()
				_sm_set(&"channel", 0.0)
				_set_phase(Phase.RECOVER, RECOVER_TIME)
		Phase.HOST_TELL:
			_turn_toward(dir, 2.0, delta)
			if randf() < delta * 18.0:
				var a := randf() * TAU
				HolyFX.motes(global_position + Vector3(cos(a) * 3.0, 0.2, sin(a) * 3.0), 2, Art.HOLY, 0.4, 2.5, 0.9)
			if _phase_t <= 0.0:
				_summon_host()
				_sm_set(&"summon", 0.0)
				_set_phase(Phase.RECOVER, RECOVER_TIME)
		Phase.NOVA_TELL:
			var k := clampf(1.0 - _phase_t / _tell_len, 0.0, 1.0)
			_telegraph.show_disc(global_position, 3.0, Art.HOLY_WHITE, k, minf(k * 4.0, 1.0), 1.6 + k)
			if _phase_t <= 0.0:
				_telegraph.hide_now()
				_release_ring(randf() * TAU)
				_nova_second = false
				_set_phase(Phase.NOVA, NOVA_TIME)
		Phase.NOVA:
			if not _nova_second and _phase_t <= NOVA_TIME * 0.35:
				_nova_second = true
				_release_ring(TAU / float(NOVA_COUNT) * 0.5 + randf_range(-0.05, 0.05))
			if _phase_t <= 0.0:
				_sm_set(&"channel", 0.0)
				_set_phase(Phase.RECOVER, RECOVER_TIME)
		Phase.RECOVER:
			move = dir * speed * 0.35
			_turn_toward(dir, 2.0, delta)
			if _phase_t <= 0.0:
				_set_phase(Phase.GLIDE, 0.0)
				var cd := RAGE_ATTACK_COOLDOWN if is_enraged else ATTACK_COOLDOWN
				_boss_cd = cd * randf_range(0.85, 1.15)

	velocity = move * move_factor  # ability slows (Enemy.set_move_factor)
	move_and_slide()
	position.y = 0.0
	_animate_model(delta, clampf(move.length() / maxf(speed, 0.01), 0.0, 1.0))


# ---------------------------------------------------------------- intro

func _begin_intro() -> void:
	phase = Phase.INTRO
	_intro_t = 0.0
	Game.boss_spawned.emit(self)
	_home_layer = collision_layer
	collision_layer = 0  # no contact damage / targeting while it descends
	_sm_set(&"descent", 1.0)
	_sm_set(&"raise", 0.0)
	# Deferred: we are inside the world's add_child() here.
	_intro_fx.call_deferred()


func _intro_fx() -> void:
	if not is_inside_tree():
		return
	HolyFX.column(global_position, 1.3, 34.0, INTRO_DESCENT + 0.5, Art.HOLY, 1.5)
	HolyFX.motes(global_position + Vector3(0.0, 0.2, 0.0), 16, Art.HOLY, 2.0, 3.0, 2.0)
	_toast(data.display_name.to_upper() if data else "SARIEL, HERALD OF THE LAST DAWN", TOAST_NAME)
	Sfx.play(&"boss_intro", 0.0)
	Sfx.play(&"choir", 0.0, -4.0)
	_shake(0.25)


func _intro_process(delta: float) -> void:
	_intro_t += delta
	hp = max_hp
	var k := clampf(_intro_t / INTRO_DESCENT, 0.0, 1.0)
	var eased := 1.0 - (1.0 - k) * (1.0 - k) * (1.0 - k)
	_sm_set(&"descent", 1.0 - eased)
	_telegraph.show_disc(global_position, 3.2, Art.HOLY, k, minf(_intro_t * 2.0, 1.0), 1.5)
	var p := Game.player
	if p and is_instance_valid(p):
		var to := p.global_position - global_position
		to.y = 0.0
		_turn_toward(to, 3.0, delta)
	if k >= 1.0 and not _landed:
		_landed = true
		Sfx.play(&"impact", 0.0)
		Sfx.play(&"wingbeat", 0.0, 0.0)
		_shake(0.5)
		HolyFX.flash(global_position + Vector3(0.0, 0.6, 0.0), 4.0, 0.6, Art.HOLY_WHITE, 2.5)
		HolyFX.motes(global_position + Vector3(0.0, 0.2, 0.0), 22, Art.HOLY, 3.0, 1.2, 1.4)
	if _intro_t >= INTRO_DESCENT + INTRO_HOLD:
		_telegraph.hide_now()
		_sm_set(&"descent", 0.0)
		collision_layer = _home_layer
		_set_phase(Phase.GLIDE, 0.0)
		_boss_cd = FIRST_ATTACK_DELAY
	_animate_model(delta, 0.0)


# ---------------------------------------------------------------- attacks

func _start_attack(dir: Vector3) -> void:
	var pattern: Array[int] = RAGE_PATTERN if is_enraged else CALM_PATTERN
	var next: int = pattern[_pattern_i % pattern.size()]
	_pattern_i += 1
	if next == Attack.HOST and (_get_wisp_data() == null or _alive_minions() >= MAX_MINIONS - 2):
		next = Attack.PILLARS
	var tell_mult := RAGE_TELL_MULT if is_enraged else 1.0
	match next:
		Attack.PILLARS:
			_set_phase(Phase.PILLAR_TELL, PILLAR_RAISE_TIME)
			_sm_set(&"raise", 1.0)
			Sfx.play(&"choir", 0.05, -6.0)
		Attack.SWEEP:
			_sweep_center = dir
			_sweep_sign = 1.0 if randf() < 0.5 else -1.0
			_tell_len = SWEEP_TELL * tell_mult
			_set_phase(Phase.SWEEP_TELL, _tell_len)
			_sm_set(&"channel", 1.0)
			Sfx.play(&"choir", 0.05, -3.0)
		Attack.HOST:
			_tell_len = HOST_TELL
			_set_phase(Phase.HOST_TELL, HOST_TELL)
			_sm_set(&"summon", 1.0)
			Sfx.play(&"choir", 0.0, 0.0)
		Attack.NOVA:
			_tell_len = NOVA_TELL * tell_mult
			_set_phase(Phase.NOVA_TELL, _tell_len)
			_sm_set(&"channel", 1.0)
			Sfx.play(&"choir", 0.1, -5.0)


## Spear raised: sigils open around (and on) the demon, then the pillars slam down in a cascade.
func _cast_pillars(player: Player) -> void:
	var tell := PILLAR_TELL * (RAGE_TELL_MULT * 1.1 if is_enraged else 1.0)
	var count := randi_range(6, 8) if is_enraged else randi_range(4, 7)
	var spots: Array[Vector3] = []
	var p := player.global_position
	p.y = 0.0
	spots.append(p)
	var lead := player.velocity
	lead.y = 0.0
	if lead.length() > 0.5:
		spots.append(p + lead.normalized() * minf(lead.length() * tell, 5.0))
	var tries := 0
	while spots.size() < count and tries < 60:
		tries += 1
		var a := randf() * TAU
		var c := p + Vector3(cos(a), 0.0, sin(a)) * sqrt(randf()) * PILLAR_SPREAD
		var ok := true
		for s in spots:
			if s.distance_to(c) < PILLAR_MIN_SEP:
				ok = false
				break
		if ok:
			spots.append(c)
	for i in spots.size():
		JudgementPillar.cast(spots[i], PILLAR_RADIUS, tell + PILLAR_STAGGER * float(i), PILLAR_DAMAGE)
	if _sm:
		HolyFX.flash(_sm.spear_tip_global(), 1.4, 0.4, Art.HOLY_WHITE, 2.5)
	# Hold the spear aloft until the first column falls, then bring it down with it.
	_set_phase(Phase.RECOVER, tell + RECOVER_TIME * 0.5)
	_lower_spear_after(tell)


func _lower_spear_after(seconds: float) -> void:
	var tw := create_tween()
	tw.tween_interval(seconds)
	tw.tween_callback(_sm_set.bind(&"raise", 0.0))


func _begin_sweep() -> void:
	var length := RAGE_SWEEP_TIME if is_enraged else SWEEP_TIME
	_set_phase(Phase.SWEEP, length)
	_sweep_hit = false
	Sfx.play(&"beam", 0.0)
	_shake(0.25)
	if _sm:
		HolyFX.flash(_sm.halo_global(), 2.0, 0.35, Art.HOLY_WHITE, 2.5)


func _aim_beam(dir: Vector3, intensity: float) -> void:
	var origin := _sm.halo_global() if _sm else global_position + Vector3(0.0, 3.6, 0.0)
	var feet := global_position + dir * 1.2
	var end := global_position + dir * BEAM_LENGTH
	_beam.aim(origin, feet, end, BEAM_HALF_WIDTH * 2.0, intensity)


func _beam_hits(p: Vector3, dir: Vector3) -> bool:
	var d := p - global_position
	d.y = 0.0
	var along := d.dot(dir)
	if along < 0.0 or along > BEAM_LENGTH + PLAYER_RADIUS:
		return false
	return (d - dir * along).length() <= BEAM_HALF_WIDTH + PLAYER_RADIUS


func _summon_host() -> void:
	var wisp := _get_wisp_data()
	if wisp == null:
		return
	var alive := _alive_minions()
	var count := mini(randi_range(HOST_MIN, HOST_MAX), MAX_MINIONS - alive)
	if get_tree().get_node_count_in_group(&"enemies") > 280:
		count = mini(count, 2)
	var hp_scale := 1.0 + 0.1 * Game.elapsed / 60.0
	var base := randf() * TAU
	for i in count:
		var a := base + TAU * float(i) / float(maxi(count, 1)) + randf_range(-0.2, 0.2)
		var at := global_position + Vector3(cos(a), 0.0, sin(a)) * randf_range(3.0, 5.0)
		var e: Enemy = MINION_SCENE.instantiate()
		e.setup(wisp, hp_scale)
		Game.spawn(e, at)
		_minion_ids.append(e.get_instance_id())
		HolyFX.column(at, 0.3, 12.0, 0.6, Art.HOLY, 1.4)
		HolyFX.motes(at + Vector3(0.0, 0.5, 0.0), 6, Art.HOLY, 0.6, 1.5, 0.9)
	Sfx.play(&"choir", 0.05, 2.0)
	if _sm:
		HolyFX.flash(_sm.halo_global(), 1.6, 0.4, Art.HOLY, 2.0)


func _alive_minions() -> int:
	var alive: Array[int] = []
	for id in _minion_ids:
		var m := instance_from_id(id) as Enemy
		if m and not m.is_dying:
			alive.append(id)
	_minion_ids = alive
	return alive.size()


func _get_wisp_data() -> EnemyData:
	if not _wisp_checked:
		_wisp_checked = true
		if ResourceLoader.exists(WISP_DATA_PATH):
			_wisp_data = load(WISP_DATA_PATH) as EnemyData
		if _wisp_data == null:
			push_warning("Boss: %s missing; Heavenly Host falls back to Judgement Pillars" % WISP_DATA_PATH)
	return _wisp_data


func _release_ring(offset: float) -> void:
	var origin := global_position
	for i in NOVA_COUNT:
		var a := offset + TAU * float(i) / float(NOVA_COUNT)
		var d := Vector3(cos(a), 0.0, sin(a))
		SarielOrb.fire(origin + d * 1.6, d * NOVA_SPEED, NOVA_DAMAGE, NOVA_LIFE)
	Sfx.play(&"smite", 0.05, -4.0)
	_shake(0.15)
	if _sm:
		HolyFX.flash(_sm.halo_global(), 2.4, 0.4, Art.HOLY_WHITE, 2.5)


## HP ratios where the phase changes (the boss bar draws a notch at each).
func phase_thresholds() -> Array[float]:
	return [ENRAGE_RATIO]


func _enrage() -> void:
	is_enraged = true
	phase_index = 1
	Game.boss_phase_changed.emit(self, phase_index)
	_sm_set(&"spread", 1.0)
	_toast(rage_text, TOAST_RAGE)
	Sfx.play(&"choir", 0.0, 3.0)
	Sfx.play(&"boss_roar", 0.0, -1.0)
	_shake(0.4)
	if _sm:
		HolyFX.flash(_sm.halo_global(), 4.0, 0.7, Art.HOLY_WHITE, 3.0)
	HolyFX.motes(global_position + Vector3(0.0, 1.5, 0.0), 24, Art.HOLY, 2.5, 2.0, 1.6)
	_boss_cd = minf(_boss_cd, 1.2)


# ---------------------------------------------------------------- death

func die() -> void:
	if is_dying:
		return
	if phase == Phase.INTRO:
		hp = max_hp  # cannot fall before it has landed
		return
	is_dying = true
	hp = 0.0
	Game.kills += 1
	_telegraph.hide_now()
	_beam.hide_now()
	get_tree().call_group(&"boss_hazards", &"dissipate")
	set_deferred(&"collision_layer", 0)
	_set_phase(Phase.DYING, 0.0)
	_death_t = 0.0
	_sm_set(&"raise", 0.0)
	_sm_set(&"channel", 0.0)
	_sm_set(&"summon", 0.0)
	_sm_set(&"kneel", 1.0)
	Sfx.play(&"boss_death", 0.0)
	_shake(0.4)


func _dying_process(delta: float) -> void:
	_death_t += delta
	match phase:
		Phase.DYING:
			var dk := clampf((_death_t - DEATH_KNEEL) / DEATH_DISSOLVE, 0.0, 1.0)
			_sm_set(&"dissolve", dk)
			if randf() < delta * 10.0 and _sm:
				for pt in _sm.wing_points(1):
					HolyFX.motes(pt, 3, Art.HOLY, 0.4, 1.4, 1.0)
			if _death_t >= DEATH_FLASH_AT:
				_felled()
		Phase.FELLED:
			if _death_t >= DEATH_FLASH_AT + FELLED_TIME:
				queue_free()
				return
	_animate_model(delta, 0.0)


func _felled() -> void:
	_set_phase(Phase.FELLED, 0.0)
	Game.boss_died.emit(global_position)
	var center := global_position + Vector3(0.0, 1.6, 0.0)
	HolyFX.flash(center, 10.0, 1.0, Art.HOLY_WHITE, 4.0)
	HolyFX.flash(center, 4.0, 0.5, Art.HOLY_WHITE, 5.0)
	HolyFX.column(global_position, 2.0, 34.0, 1.4, Art.HOLY, 2.0)
	HolyFX.feathers(center + Vector3(0.0, 1.0, 0.0), 26, 2.4, 3.0)
	HolyFX.motes(center, 40, Art.HOLY, 3.0, 3.0, 2.0)
	HolyFX.ash(global_position, 11.0, 6.5, 150)
	_shake(0.8)
	Sfx.play(&"impact", 0.0, 2.0)
	_toast(felled_text, TOAST_FELLED)
	var tw := model.create_tween()
	tw.tween_property(model, "scale", Vector3.ONE * 0.01, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(model.hide)
	_drop_xp()
	BloodChalice.try_drop(global_position + Vector3(1.6, 0.0, 0.8), 1.0)
	ReliquaryOfSin.drop(global_position, _reward_xp(), 1.0)


## XP for ~3 level-ups from the demon's current progress (before its XP multiplier).
func _reward_xp() -> float:
	var p := Game.player
	if p == null or not is_instance_valid(p):
		return 300.0
	var need := float(p.xp_to_next) - p.xp
	for k in range(1, 3):
		need += float(p.xp_for_level(p.level + k))
	return maxf(need, 30.0) / maxf(p.xp_gain, 0.01) + 1.0


# ---------------------------------------------------------------- helpers

func _set_phase(p: Phase, time: float) -> void:
	phase = p
	_phase_t = time


## Sets a pose field on the Sariel model (no-op with a different model).
func _sm_set(field: StringName, value: float) -> void:
	if _sm:
		_sm.set(field, value)


func _update_hit_feedback(delta: float) -> void:
	if _flash_t > 0.0:
		_flash_t = maxf(_flash_t - delta, 0.0)
		model.set_flash(_flash_t / FLASH_TIME)
	if _squash > 0.0 and not is_dying:
		_squash = maxf(_squash - delta * 7.0, 0.0)
		var k := _squash * 0.03
		var s := data.size
		model.scale = Vector3(s * (1.0 + k), s * (1.0 - k), s * (1.0 + k))


func _animate_model(delta: float, move_ratio: float) -> void:
	model.animate(delta, move_ratio, _model_state_for_phase())
	if _sm and _sm.beat:
		_sm.beat = false
		Sfx.play(&"wingbeat", 0.08, -6.0 if not is_enraged else -3.0)


func _model_state_for_phase() -> int:
	match phase:
		Phase.PILLAR_TELL, Phase.SWEEP_TELL, Phase.HOST_TELL, Phase.NOVA_TELL:
			return MODEL_WINDUP
		Phase.SWEEP, Phase.NOVA:
			return MODEL_ATTACKING
	return MODEL_MOVING


## Direction the Herald faces (XZ).
func _forward() -> Vector3:
	var yaw := model.rotation.y
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func _turn_toward(dir: Vector3, rate: float, delta: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	model.rotation.y = lerp_angle(model.rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-rate * delta))


func _relocate_boss(player: Player, dir_to_player: Vector3) -> void:
	var ahead := dir_to_player.rotated(Vector3.UP, randf_range(-0.5, 0.5))
	global_position = player.global_position + ahead * BOSS_RELOCATE_RADIUS
	reset_physics_interpolation()
	HolyFX.column(global_position, 1.0, 26.0, 0.8, Art.HOLY, 1.4)


func _toast(text: String, color: Color) -> void:
	var hud := get_tree().get_first_node_in_group(&"hud")
	if hud and hud.has_method(&"toast"):
		hud.call(&"toast", text, color)


func _shake(amount: float) -> void:
	get_tree().call_group(&"camera_rig", &"shake", amount)
