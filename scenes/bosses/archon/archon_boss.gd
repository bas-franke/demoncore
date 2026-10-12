class_name ArchonBoss
extends PhasedBoss
## "Azrafel, Archon of the Seventh Gate": the finale boss (roster id gate_archon). A towering
## knight of ivory plate with a burning greatsword (the archon .glb, scaled up). Three phases, every
## attack drawn on the ground before it lands:
##   I   The Warden          (100-70%)  Cleave (wide arc ahead), Lance Dash (a lane, then it charges
##                                      down it), Sevenfold Brand (seven pillars marching at you)
##   II  The Seventh Light   (70-35%)   + Wheel of Light (lanes from its body, twice, offset),
##                                      Triple Dash, two Sentinels join
##   III Wrath of the Throne (< 35%)    + Dawn Wings (huge arcs left, right, then ahead),
##                                      Halo Rings (orb rings) and the Bell of Dawn (expanding rings:
##                                      dash through them to shatter them)
## Story pools: boss_intro/rage/death.gate_archon, boss_phase.gate_archon.<1|2>.

enum Attack { CLEAVE, DASH, BRAND, WHEEL, TRIPLE, WINGS, HALO, BELL }

const PATTERNS := [
	[Attack.CLEAVE, Attack.DASH, Attack.BRAND, Attack.CLEAVE, Attack.DASH],
	[Attack.WHEEL, Attack.DASH, Attack.CLEAVE, Attack.TRIPLE, Attack.BRAND, Attack.WHEEL],
	[Attack.WINGS, Attack.TRIPLE, Attack.HALO, Attack.BELL, Attack.WHEEL, Attack.CLEAVE, Attack.WINGS, Attack.BRAND],
]
const PHASE_MINIONS := [[], ["seraph_sentinel", "seraph_sentinel"], ["dawn_lancer", "dawn_lancer", "seraph_sentinel"]]
const TELL_MULT: Array[float] = [1.0, 0.92, 0.82]

const CLEAVE_RADIUS := 5.8
const CLEAVE_HALF := 1.05
const CLEAVE_DAMAGE := 28.0
const DASH_LENGTH := 15.0
const DASH_WIDTH := 2.2
const DASH_SPEED := 20.0
const DASH_DAMAGE := 30.0
const BRAND_DAMAGE := 20.0
const WHEEL_SPOKES := 6
const WHEEL_LENGTH := 13.0
const WHEEL_DAMAGE := 22.0
const WINGS_RADIUS := 7.5
const WINGS_HALF := 1.2
const WINGS_DAMAGE := 28.0
const HALO_COUNT := 18
const HALO_DAMAGE := 14.0

var _attack := Attack.CLEAVE
var _pattern_i := 0
var _dashes_left := 0
var _dash_dir := Vector3.FORWARD
var _dash_hit := false
var _charging := false


func _init() -> void:
	phase_lines = [0.7, 0.35]
	phase_names = ["The Warden", "The Seventh Light", "Wrath of the Throne"]
	cooldowns = [2.8, 2.3, 1.8]
	speed_mults = [1.0, 1.15, 1.3]
	keep_distance = 4.0
	felled_text = "THE WARDEN FALLS"
	rage_text = "The Warden draws the light of the Throne"


func _start_attack(dir: Vector3) -> float:
	var pattern: Array = PATTERNS[phase_index]
	_attack = pattern[_pattern_i % pattern.size()]
	_pattern_i += 1
	_boss_aim = dir
	var tm := TELL_MULT[phase_index]
	match _attack:
		Attack.CLEAVE:
			Sfx.play(&"boss_charge", 0.05, -6.0)
			return 0.7 * tm
		Attack.DASH, Attack.TRIPLE:
			_dashes_left = 3 if _attack == Attack.TRIPLE else 1
			return 0.3 * tm
		Attack.BRAND:
			Sfx.play(&"choir", 0.05, -4.0)
			return 0.45 * tm
		Attack.WHEEL:
			Sfx.play(&"choir", 0.05, -2.0)
			return 0.5 * tm
		Attack.WINGS:
			Sfx.play(&"wingbeat", 0.0, 2.0)
			return 0.5 * tm
		Attack.HALO, Attack.BELL:
			Sfx.play(&"toll", 0.0, -2.0)
			return 0.6 * tm
	return 0.5


func _release_attack(player: Player) -> void:
	var tm := TELL_MULT[phase_index]
	var p := player.global_position
	p.y = 0.0
	match _attack:
		Attack.CLEAVE:
			PyreBurst.cast(global_position, CLEAVE_RADIUS, 0.55 * tm, CLEAVE_DAMAGE, _boss_aim, CLEAVE_HALF)
			model.play_attack()
			_recover(1.1)
		Attack.DASH, Attack.TRIPLE:
			_queue_dash(tm)
		Attack.BRAND:
			# Seven pillars march from its feet toward (and past) the demon.
			var to := p - global_position
			to.y = 0.0
			var step := maxf(to.length() / 5.0, 1.6)
			var d := to.normalized() if to.length() > 0.1 else _boss_aim
			for i in 7:
				JudgementPillar.cast(global_position + d * step * float(i + 1), 1.5, 0.9 * tm + 0.16 * i, BRAND_DAMAGE)
			_recover(1.4)
		Attack.WHEEL:
			_wheel(0.0, tm)
			_schedule(0.65, _wheel.bind(PI / float(WHEEL_SPOKES), tm))
			_recover(1.8)
		Attack.WINGS:
			var left := _boss_aim.rotated(Vector3.UP, PI * 0.5)
			PyreBurst.cast(global_position, WINGS_RADIUS, 1.0 * tm, WINGS_DAMAGE, left, WINGS_HALF)
			_schedule(0.5, _wing.bind(-left, tm))
			_schedule(1.0, _wing.bind(Vector3.ZERO, tm))
			_recover(2.2)
		Attack.HALO:
			_halo_ring(randf() * TAU)
			_schedule(0.6, _halo_ring.bind(PI / float(HALO_COUNT)))
			_recover(1.4)
		Attack.BELL:
			for i in 3:
				BellRing.cast(global_position, 15.0, 7.0, 0.9, 18.0, 0.6 + 0.9 * i)
			_recover(2.4)


## Lance Dash: a lane lights up ahead (Azrafel braces, ACTION "aiming"); when it is charged it
## charges down the lane (ACTION "charging"). Triple Dash re-aims between charges.
func _queue_dash(tm: float) -> void:
	var p := Game.player
	if p:
		var to := p.global_position - global_position
		to.y = 0.0
		if to.length() > 0.1:
			_boss_aim = to.normalized()
	_dash_dir = _boss_aim
	var tell := 0.85 * tm if _dashes_left >= 3 or _attack == Attack.DASH else 0.6 * tm
	_attack = Attack.TRIPLE if _dashes_left > 1 else Attack.DASH
	InquisitorLane.cast(global_position, _dash_dir, DASH_LENGTH, DASH_WIDTH, tell, 0.0)
	_charging = false
	_begin_action(tell)


func _action_process(_delta: float, _dir: Vector3) -> Vector3:
	model.rotation.y = lerp_angle(model.rotation.y, atan2(-_dash_dir.x, -_dash_dir.z), 0.3)
	if not _charging:
		if _phase_t <= 0.0:
			_charging = true
			_dash_hit = false
			_phase_t = DASH_LENGTH / DASH_SPEED
			model.play_attack()
			Sfx.play(&"wingbeat", 0.0, 3.0)
			_shake(0.2)
		return Vector3.ZERO
	if randf() < 0.5:
		HolyFX.motes(global_position + Vector3(0.0, 1.0, 0.0), 1, Art.HOLY, 0.5, 0.6, 0.5)
	var p := Game.player
	if not _dash_hit and p and not p.is_dead and p.global_position.distance_to(global_position) < 1.2 + 0.4 * data.size:
		_dash_hit = true
		p.take_damage(DASH_DAMAGE)
		Sfx.play(&"holy_hit", 0.05)
	if _phase_t <= 0.0:
		_dashes_left -= 1
		if _dashes_left > 0:
			_queue_dash(TELL_MULT[phase_index])
		else:
			_end_action(0.9)
		return Vector3.ZERO
	return _dash_dir * DASH_SPEED


func _wheel(offset: float, tm: float) -> void:
	for i in WHEEL_SPOKES:
		var d := _boss_aim.rotated(Vector3.UP, offset + TAU * float(i) / float(WHEEL_SPOKES))
		InquisitorLane.cast(global_position + d * 1.2, d, WHEEL_LENGTH, 1.2, 0.95 * tm, WHEEL_DAMAGE)


func _wing(dir: Vector3, tm: float) -> void:
	var d := dir if dir != Vector3.ZERO else _boss_aim
	PyreBurst.cast(global_position, WINGS_RADIUS, 1.0 * tm, WINGS_DAMAGE, d, WINGS_HALF)


func _halo_ring(offset: float) -> void:
	for i in HALO_COUNT:
		var a := offset + TAU * float(i) / float(HALO_COUNT)
		var d := Vector3(cos(a), 0.0, sin(a))
		SarielOrb.fire(global_position + d * 1.8, d * 3.4, HALO_DAMAGE, 6.0)
	Sfx.play(&"smite", 0.05, -4.0)


func _on_phase_begin(index: int) -> void:
	for id: String in PHASE_MINIONS[index]:
		ObjectiveFX.spawn_enemy(id, ObjectiveFX.ring_point(global_position, randf_range(3.0, 5.0)), 0.8)


func _intro_fx() -> void:
	super()
	Sfx.play(&"toll", 0.0, 2.0)
	HolyFX.feathers(global_position + Vector3(0.0, 3.0, 0.0), 16, 2.0, 2.4)
