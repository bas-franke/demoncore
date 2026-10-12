class_name Enemy
extends CharacterBody3D
## Generic enemy driven by an EnemyData resource: instances its EnemyModel, runs one of the
## behaviors (CHASE / SHOOT / CHARGE / HOP / SLAM) and deals contact damage (the player's Hurtbox
## does the damage check). CHARGE, HOP and SLAM draw their warning on the ground in light
## (HolyTelegraph): a lane for charges, the landing circle for leaps, the struck circle for slams.

const GEM_SCENE := preload("res://scenes/pickups/xp_gem.tscn")
const HOLY_ORB_SCENE := preload("res://scenes/enemies/holy_orb.tscn")
## Enemies further than this from the player are moved back in front of them.
## Both sized for CameraRig.distance 36: relocation lands just off-screen, beyond EnemySpawner.spawn_radius.
const RELOCATE_DISTANCE := 52.0
const RELOCATE_RADIUS := 36.0
## Perf LOD: off-screen enemies closer than this always run at full rate.
const LOD_NEAR := 9.0
## Perf LOD: on-screen walkers further than this think / slide / animate every other tick and just
## coast on their last velocity in between (the demon is the centre of the action; the far ring of a
## wide view doesn't need 30 Hz AI).
const LOD_FAR := 13.0
## Perf LOD: on-screen test box padding (m) for shadows cast into view from just off screen.
const SHADOW_PAD := 3.0
## Above this many gems on the floor, new XP is merged into an existing gem.
const MAX_GEMS := 250
const FLASH_TIME := 0.1
const CHARGE_RECOVER_TIME := 0.5
## HOP: time spent squashed on the ground after landing.
const HOP_LAND_TIME := 0.25
## HOP: landing within this radius (x size) of the player stomps them.
const STOMP_RADIUS := 0.9
## HOP: stomp damage as a fraction of contact damage.
const STOMP_DAMAGE_SCALE := 0.6
## CHARGE: the lane stops tracking the player after this much of the wind-up (fair dodge window).
const CHARGE_AIM_LOCK := 0.7
## SLAM: time standing in the aftermath of a strike.
const SLAM_RECOVER_TIME := 0.9
## Enemies worth at least this much XP count as elites (food drop, camera shake, big burst).
const ELITE_XP := 20
## Hit stagger: an effective knockback (knockback * knockback_scale) of at least STAGGER_MIN
## stops the enemy's own movement for STAGGER_PER_KNOCK s per unit (capped at STAGGER_MAX), while
## it is walking or winding up. At INTERRUPT_KNOCK or more a non-elite's wind-up is cancelled.
const STAGGER_MIN := 2.0
const STAGGER_PER_KNOCK := 0.03
const STAGGER_MAX := 0.25
const INTERRUPT_KNOCK := 5.0
const INTERRUPT_RECOVER := 0.35
## Hit freeze (2D-fighter "hitstop", per enemy): a struck walker locks in place and shakes for a few
## frames scaled by how hard the hit was relative to its max HP (light ~3 frames, heavy ~11 at 60 fps),
## and its knockback is held until the freeze ends, then released all at once. Never during a
## wind-up / attack (attacks keep their timing), and a re-freeze needs HITFREEZE_GAP after the last
## one so a stream of auto-weapon hits can't pin a crowd in place.
const HITFREEZE_MIN := 0.05
const HITFREEZE_MAX := 0.18
## Damage as a fraction of max HP that earns the full HITFREEZE_MAX.
const HITFREEZE_HEAVY_FRAC := 0.35
const HITFREEZE_GAP := 0.3
## Peak shake of the model (m, x size) at the start of a freeze.
const HITFREEZE_SHAKE := 0.09
## Support behaviours (HEAL / SHIELD / KITE / EXPLODE / SUMMON).
const HEAL_COLOR := Color(0.75, 1.0, 0.55)
const FUSE_COLOR := Color(1.0, 0.55, 0.25)
const WARD_COLOR := Color(0.6, 0.85, 1.0)
const SUPPORT_TICK := 0.25
## aim_line shooters stop tracking at this fraction of the wind-up (then the lane is fixed).
const AIM_LOCK := 0.7
const ENEMY_SCENE_PATH := "res://scenes/enemies/enemy.tscn"
const DEFAULT_SUMMON := "res://data/enemies/cherub.tres"

enum State { MOVE, WINDUP, ATTACK, RECOVER }

var data: EnemyData
var max_hp := 10.0
var hp := 10.0
var damage := 10.0
var speed := 3.0
var is_dying := false
var model: EnemyModel
## Product of every set_move_factor() source (slows / binds). Scales all self-propelled movement,
## dashes and leaps included, but not knockback. Composes with changes to `speed`.
var move_factor := 1.0
var _move_factors := {}  # StringName source -> float
var _damage_scale := 1.0

var _knockback := Vector3.ZERO
var _stagger_t := 0.0
## Hit freeze (see HITFREEZE_*). Only plain enemies use it: subclasses (bosses, objective actors)
## run their own _physics_process, which would never release the held knockback.
var _hitfreeze_ok := false
var _freeze_t := 0.0
var _freeze_len := 0.0
var _freeze_cd := 0.0
var _freeze_kb := Vector3.ZERO
var _freeze_dir := Vector3.RIGHT
## CHASE: fixed approach-angle offset (radians) so a crowd fans out and surrounds the demon
## instead of trailing behind it in a conga line. Fades out close in.
var _flank := 0.0
var _hp_scale := 1.0
var _speed_scale := 1.0
## Ward from a nearby SHIELD bearer: damage taken is multiplied by _ward_mult while _ward_t > 0.
var _ward_t := 0.0
var _ward_mult := 1.0
var _ward_fx: MeshInstance3D
## SHIELD: the faint ward ring on the ground. SUMMON: live minions.
var _aura_fx: MeshInstance3D
var _support_t := 0.0
var _summons: Array[Enemy] = []
## aim_line: the locked shot direction.
var _shot_dir := Vector3.FORWARD
var _enraged := false
## Who dealt the hit being processed (a Weapon, an ability caster, ...). Set by Enemy.hit() for
## the duration of take_damage(), so Game.enemy_struck listeners can read it; null otherwise.
var last_hit_source: Object
## Taunt: while valid and _taunt_t > 0 the enemy moves / aims at this node instead of the demon.
var _taunt: Node3D
var _taunt_t := 0.0
var _flash_t := 0.0
var _squash := 0.0
var _state := State.MOVE
var _state_t := 0.0
## Full length of the current state (for model clip stretching / progress).
var _state_len := 0.0
## Smoothed real horizontal speed (walk-clip playback).
var _ground_speed := 0.0
var _attack_t := 0.0
var _charge_dir := Vector3.FORWARD
## Straight-at-the-player direction (see _physics_process; Maps steering only bends `dir`).
var _aim := Vector3.FORWARD
## Maps un-stick nudge state (see _physics_process).
var _stuck_t := 0.0
var _unstick_t := 0.0
var _unstick_dir := Vector3.ZERO
var _strafe_sign := 1.0
var _speed_mult := 1.0
var _hop_speed := 0.0
## HOP: where the current leap lands. SLAM: center of the struck circle.
var _strike_at := Vector3.ZERO
## Ground warning (only for CHARGE / HOP / SLAM enemies).
var _holy_tele: HolyTelegraph
## Perf LOD (docs/team/performance.md): engine-side on-screen test. Off-screen enemies skip model
## animation (their AnimationPlayer is paused) and, while just walking, think every other tick.
var _vis: VisibleOnScreenNotifier3D
var _on_screen := true
var _lod_acc := 0.0
var _lod_phase := 0

@onready var shape_node: CollisionShape3D = $CollisionShape3D


## Call before adding to the tree. The scales come from RunState's difficulty (EnemySpawner).
## damage_scale also scales projectile, stomp and slam damage.
func setup(enemy_data: EnemyData, hp_scale: float = 1.0, damage_scale: float = 1.0,
		speed_scale: float = 1.0) -> void:
	data = enemy_data
	max_hp = data.max_hp * hp_scale
	hp = max_hp
	_damage_scale = damage_scale
	_hp_scale = hp_scale
	_speed_scale = speed_scale
	damage = data.damage * damage_scale
	_speed_mult = randf_range(0.9, 1.1) * speed_scale
	speed = data.speed * _speed_mult


func _ready() -> void:
	var s := data.size
	var cap := (shape_node.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	cap.radius *= s
	cap.height *= s
	shape_node.shape = cap
	shape_node.position.y = cap.height * 0.5
	if Crowd.enabled:
		collision_mask &= ~4  # no physics vs other enemies: Crowd.push() separates them (perf)

	if data.model:
		model = data.model.instantiate() as EnemyModel
	if model == null:
		model = EnemyModel.new()
	model.position.y = data.hover
	model.scale = Vector3.ONE * s
	model.body_scale = s
	if model is ProcModel:
		model.ensure_built()  # perf: build + merge out of the tree (see EnemyModel.ensure_built)
	add_child(model)
	# Heaven's look: pale-gold rim light, gold outline on elites (docs/team/art-style.md).
	ArtStyle.apply_faction(model, ArtStyle.Faction.HOLY, is_elite())
	if Game.player:
		var to := Game.player.global_position - global_position
		model.rotation.y = atan2(-to.x, -to.z)

	# Stagger the first attack so a fresh wave doesn't fire in unison.
	_attack_t = _cooldown() * randf_range(0.6, 1.2)
	_strafe_sign = 1.0 if randf() < 0.5 else -1.0
	_flank = randf_range(-0.7, 0.7)
	match data.behavior:
		EnemyData.Behavior.CHARGE, EnemyData.Behavior.HOP, EnemyData.Behavior.SLAM, \
				EnemyData.Behavior.HEAL, EnemyData.Behavior.SHIELD, EnemyData.Behavior.EXPLODE, \
				EnemyData.Behavior.SUMMON:
			_holy_tele = HolyTelegraph.new()
			add_child(_holy_tele)
	if data.aim_line and _holy_tele == null:
		_holy_tele = HolyTelegraph.new()
		add_child(_holy_tele)
	if data.behavior == EnemyData.Behavior.SHIELD:
		_aura_fx = _ring_fx(self, data.ward_radius, WARD_COLOR, 0.35)
		_aura_fx.top_level = true
	if data.id != &"":
		Settings.mark_seen(data.id)
	_vis = VisibleOnScreenNotifier3D.new()
	# Padded by SHADOW_PAD so a model whose long low-sun shadow still reaches the screen stays drawn
	# (EnemyModel.set_lod hides off-screen models entirely).
	_vis.aabb = AABB(Vector3(-1.0 * s - SHADOW_PAD, 0.0, -1.0 * s - SHADOW_PAD),
			Vector3(2.0 * s + 2.0 * SHADOW_PAD, 2.6 * s + data.hover, 2.0 * s + 2.0 * SHADOW_PAD))
	add_child(_vis)
	_lod_phase = get_instance_id() % 2
	_hitfreeze_ok = (get_script() as Script).resource_path == "res://scenes/enemies/enemy.gd"


## Sets a named movement multiplier (e.g. &"abilities" for slows; 0 = held fast). 1 removes it.
func set_move_factor(source: StringName, factor: float) -> void:
	if is_equal_approx(factor, 1.0):
		_move_factors.erase(source)
	else:
		_move_factors[source] = maxf(factor, 0.0)
	move_factor = 1.0
	for f: float in _move_factors.values():
		move_factor *= f


func is_elite() -> bool:
	return data.xp_value >= ELITE_XP


func _physics_process(delta: float) -> void:
	var player := Game.player
	if player == null:
		return
	_freeze_cd = maxf(_freeze_cd - delta, 0.0)
	if _freeze_t > 0.0:
		_hitfreeze_step(delta)
		return
	var to := player.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	if dist > RELOCATE_DISTANCE:
		_relocate(player, to / dist)
		return

	# Bent around walls on bounded maps (flow field); unchanged on open maps.
	# Perf LOD: walkers (not winding up / attacking / staggered / taunted) beyond LOD_NEAR off-screen,
	# or beyond LOD_FAR on-screen, run AI + move_and_slide + animation every other tick with the skipped
	# time folded in. On-screen ones coast on their last velocity in the skipped tick so motion stays smooth.
	var on_screen := _vis == null or _vis.is_on_screen()
	if on_screen != _on_screen:
		_on_screen = on_screen
		model.set_lod(on_screen)
	if _state == State.MOVE and _stagger_t <= 0.0 and _taunt_t <= 0.0 \
			and dist > (LOD_FAR if on_screen else LOD_NEAR):
		_lod_acc += delta
		if (Engine.get_physics_frames() + _lod_phase) % 2 != 0:
			if on_screen:
				# Coast so visible motion stays smooth (no wall test for this half tick).
				global_position += velocity * delta
				position.y = 0.0
			return
		delta = _lod_acc
	_lod_acc = 0.0

	# Taunt (set_taunt_target): chase / aim at the decoy instead. Relocation and LOD above keep
	# using the demon's distance.
	if _taunt_t > 0.0:
		_taunt_t -= delta
		if is_instance_valid(_taunt) and _taunt.is_inside_tree():
			to = _taunt.global_position - global_position
			to.y = 0.0
			dist = to.length()
		else:
			clear_taunt()

	# Maps (bounded maps): `dir` = MOVE direction, bent around walls by the flow field; `_aim` = straight
	# at the player, used for facing, shots and attack lanes so steering never skews an attack.
	_aim = to / maxf(dist, 0.001)
	var dir := Maps.steer(global_position, _aim)
	var move := Vector3.ZERO
	match data.behavior:
		EnemyData.Behavior.SHOOT:
			move = _shoot_ai(delta, dir, dist)
		EnemyData.Behavior.CHARGE:
			move = _charge_ai(delta, dir, dist)
		EnemyData.Behavior.HOP:
			move = _hop_ai(delta, dir, dist)
		EnemyData.Behavior.SLAM:
			move = _slam_ai(delta, dir, dist)
		EnemyData.Behavior.HEAL:
			move = _heal_ai(delta, dir, dist)
		EnemyData.Behavior.SHIELD:
			move = _slam_ai(delta, dir, dist)
			_ward_tick(delta)
		EnemyData.Behavior.KITE:
			move = _kite_ai(delta, dir, dist)
		EnemyData.Behavior.EXPLODE:
			move = _explode_ai(delta, dir, dist)
		EnemyData.Behavior.SUMMON:
			move = _summon_ai(delta, dir, dist)
		_:
			move = _chase_dir(dir, dist) * speed
	_update_ward(delta)
	if _stagger_t > 0.0:
		_stagger_t -= delta
		if _state == State.MOVE or _state == State.WINDUP:
			move = Vector3.ZERO
	# Maps: un-stick nudge. A walker that pushes but barely moves for 0.5 s next to a wall (pinned on
	# a corner) heads for the centre of the best open nav cell for a moment. Crowd jams don't count:
	# Maps.unstick() returns ZERO when no wall is adjacent.
	if _unstick_t > 0.0:
		_unstick_t -= delta
		if _state == State.MOVE:
			move = _unstick_dir * speed
	elif _state == State.MOVE and dist > 3.0 and move.length_squared() > 0.25 and _ground_speed < speed * 0.15:
		_stuck_t += delta
		if _stuck_t > 0.5:
			_stuck_t = 0.0
			_unstick_dir = Maps.unstick(global_position, dir)
			_unstick_t = 0.45 if _unstick_dir != Vector3.ZERO else 0.0
	else:
		_stuck_t = maxf(_stuck_t - delta, 0.0)
	# Crowd.push: enemy-vs-enemy separation (they no longer collide physically; perf role).
	velocity = move * move_factor + _knockback + Crowd.push(self)
	_knockback = _knockback.lerp(Vector3.ZERO, 1.0 - exp(-8.0 * delta))
	move_and_slide()
	position.y = 0.0

	# Face the player (or the locked charge / leap / slam direction), smoothly.
	var face := dir if _state == State.MOVE and dir.dot(_aim) < 0.7 else _aim  # walk around walls, else watch the player
	var dashing := data.behavior == EnemyData.Behavior.CHARGE or data.behavior == EnemyData.Behavior.HOP
	if _state == State.ATTACK and dashing:
		face = _charge_dir
	elif (data.behavior == EnemyData.Behavior.SLAM or data.behavior == EnemyData.Behavior.SHIELD) \
			and (_state == State.WINDUP or _state == State.ATTACK):
		face = _charge_dir
	if dist > 0.1 or _state == State.ATTACK:
		var turn_rate := 4.0 if _state == State.ATTACK else 10.0
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-face.x, -face.z), 1.0 - exp(-turn_rate * delta))

	# Animation runs off the real (slid, knocked-back) ground speed, smoothed against crowd jitter.
	var real := get_real_velocity()
	real.y = 0.0
	_ground_speed = lerpf(_ground_speed, real.length(), 1.0 - exp(-12.0 * delta))
	var move_ratio := clampf(_ground_speed / maxf(speed, 0.01), 0.0, 1.0)
	model.state_progress = _state_progress()
	model.state_duration = _state_len if _state != State.MOVE else 0.0
	model.ground_speed = _ground_speed
	model.body_scale = data.size
	if _on_screen:
		model.animate(delta, move_ratio, _model_state())

	# Hit feedback: flash + squash, both decaying quickly.
	if _flash_t > 0.0:
		_flash_t = maxf(_flash_t - delta, 0.0)
		model.set_flash(_flash_t / FLASH_TIME)
	if _squash > 0.0:
		_squash = maxf(_squash - delta * 7.0, 0.0)
		var k := _squash * 0.08
		model.scale = Vector3(data.size * (1.0 + k), data.size * (1.0 - k), data.size * (1.0 + k))


func _model_state() -> int:
	match _state:
		State.WINDUP:
			return EnemyModel.State.WINDUP
		State.ATTACK:
			return EnemyModel.State.ATTACKING
		State.RECOVER:
			return EnemyModel.State.RECOVER
	return EnemyModel.State.MOVING


## Enters `state` for `time` seconds (MOVE has no fixed length: assign _state directly).
func _set_state(state: State, time: float) -> void:
	_state = state
	_state_t = time
	_state_len = time
	if state == State.WINDUP:
		# Per-enemy cry (data/audio/enemy_audio.json); elites are louder, deeper and rarer.
		Sfx.play_enemy_voice(data, global_position, -6.0, is_elite())


## 0..1 progress through the current wind-up / attack / recovery (model telegraphs, hop arcs).
func _state_progress() -> float:
	if _state == State.MOVE:
		return 0.0
	return clampf(1.0 - _state_t / maxf(_state_len, 0.001), 0.0, 1.0)


# ---------------------------------------------------------------- behaviors

## CHASE steering: head for the player at an angle that straightens out within ~3 units.
func _chase_dir(dir: Vector3, dist: float) -> Vector3:
	var k := clampf((dist - 3.0) / 9.0, 0.0, 1.0)
	return dir.rotated(Vector3.UP, _flank * k)


## Keeps `preferred_distance`, circles the player and fires projectiles.
func _shoot_ai(delta: float, dir: Vector3, dist: float) -> Vector3:
	match _state:
		State.WINDUP:
			_state_t -= delta
			_aim_windup()
			if _state_t <= 0.0:
				_fire(_shot_dir if data.aim_line else _aim)
				_hide_telegraph()
				_set_state(State.ATTACK, data.shot_recover_time)
			return Vector3.ZERO
		State.ATTACK, State.RECOVER:
			_state_t -= delta
			if _state_t <= 0.0:
				_state = State.MOVE
			return Vector3.ZERO

	_attack_t -= delta
	if _attack_t <= 0.0 and dist < data.preferred_distance * 1.6:
		_attack_t = _cooldown() * randf_range(0.85, 1.15)
		_set_state(State.WINDUP, data.windup_time)
		return Vector3.ZERO
	if randf() < delta * 0.25:
		_strafe_sign = -_strafe_sign
	var radial := clampf((dist - data.preferred_distance) / 2.0, -1.0, 1.0)
	var tangent := Vector3(-dir.z, 0.0, dir.x) * _strafe_sign
	var m := dir * radial + tangent * (1.0 - absf(radial) * 0.6)
	if m.length_squared() < 0.0001:
		return Vector3.ZERO
	return m.normalized() * speed


func _fire(dir: Vector3) -> void:
	var scene: PackedScene = data.projectile if data.projectile else HOLY_ORB_SCENE
	var shot := scene.instantiate() as Node3D
	if shot == null:
		return
	shot.set(&"velocity", dir * data.projectile_speed)
	shot.set(&"damage", data.projectile_damage * _damage_scale)
	shot.add_to_group(&"enemy_shots")  # Danger / Autopilot read it as an incoming lane
	var muzzle := global_position + dir * 0.5 * data.size + Vector3(0.0, data.muzzle_height * data.size, 0.0)
	Game.spawn(shot, muzzle)
	model.play_attack()


## Walks in, winds up in place (a lane of light shows the path), then dashes in a locked direction.
func _charge_ai(delta: float, dir: Vector3, dist: float) -> Vector3:
	match _state:
		State.WINDUP:
			_state_t -= delta
			var p := _state_progress()
			if p < CHARGE_AIM_LOCK:
				_charge_dir = _aim
			if _holy_tele:
				var length := data.charge_speed * data.charge_time + data.size * 0.6
				_holy_tele.show_line(global_position, _charge_dir, length, 0.95 * data.size, p)
			if _state_t <= 0.0:
				_set_state(State.ATTACK, data.charge_time)
				_hide_telegraph()
				model.play_attack()
			return Vector3.ZERO
		State.ATTACK:
			_state_t -= delta
			if _state_t <= 0.0:
				_set_state(State.RECOVER, CHARGE_RECOVER_TIME)
			return _charge_dir * data.charge_speed
		State.RECOVER:
			_state_t -= delta
			if _state_t <= 0.0:
				_state = State.MOVE
				_attack_t = _cooldown() * randf_range(0.8, 1.2)
			return dir * speed * 0.2

	_attack_t -= delta
	if _attack_t <= 0.0 and dist < data.preferred_distance:
		_set_state(State.WINDUP, data.windup_time)
		_charge_dir = _aim
		return Vector3.ZERO
	return dir * speed


## Shuffles, crouches, then leaps toward where the player is at take-off and stomps on landing.
## The landing circle is lit on the ground while airborne. The arc itself is visual only (the
## model lifts its own pivots from state_progress).
func _hop_ai(delta: float, dir: Vector3, dist: float) -> Vector3:
	match _state:
		State.WINDUP:
			_state_t -= delta
			if _state_t <= 0.0:
				var air := maxf(data.charge_time, 0.05)
				var reach := data.charge_speed * _speed_mult * air
				_charge_dir = _aim
				_hop_speed = minf(dist, reach) / air
				_strike_at = global_position + _charge_dir * _hop_speed * air
				_set_state(State.ATTACK, air)
				model.play_attack()
			return Vector3.ZERO
		State.ATTACK:
			_state_t -= delta
			if _holy_tele:
				_holy_tele.show_circle(_strike_at, STOMP_RADIUS * data.size, _state_progress())
			if _state_t <= 0.0:
				_set_state(State.RECOVER, HOP_LAND_TIME)
				_hide_telegraph()
				_land()
			return _charge_dir * _hop_speed
		State.RECOVER:
			_state_t -= delta
			if _state_t <= 0.0:
				_state = State.MOVE
				_attack_t = _cooldown() * randf_range(0.8, 1.2)
			return Vector3.ZERO

	_attack_t -= delta
	if _attack_t <= 0.0:
		_set_state(State.WINDUP, data.windup_time)
		return Vector3.ZERO
	return dir * speed * 0.15


func _land() -> void:
	model.play_land()
	Sfx.play(&"impact", 0.12, -4.0)
	var s := data.size
	EnemyModel.poof(global_position + Vector3(0.0, 0.1, 0.0), Art.STONE, Art.BONE, 6, 0.3 * s, 0.7 * s)
	EnemyModel.shockwave(global_position, STOMP_RADIUS * s * 1.2, Art.HOLY, 0.35)
	var player := Game.player
	if player and not player.is_dead \
			and global_position.distance_to(player.global_position) < STOMP_RADIUS * s:
		player.take_damage(data.damage * _damage_scale * STOMP_DAMAGE_SCALE, global_position)


## Closes in, then raises its weapon over a circle of light ahead of it (fixed on the ground
## once the wind-up starts), swings down for `charge_time` and strikes everything inside.
func _slam_ai(delta: float, dir: Vector3, dist: float) -> Vector3:
	match _state:
		State.WINDUP:
			_state_t -= delta
			if _holy_tele:
				_holy_tele.show_circle(_strike_at, data.slam_radius, _state_progress())
			if _state_t <= 0.0:
				_set_state(State.ATTACK, maxf(data.charge_time, 0.05))
				model.play_attack()
			return Vector3.ZERO
		State.ATTACK:
			_state_t -= delta
			if _holy_tele:
				_holy_tele.show_circle(_strike_at, data.slam_radius, 1.0)
			if _state_t <= 0.0:
				_set_state(State.RECOVER, SLAM_RECOVER_TIME)
				_hide_telegraph()
				_strike_slam()
			return Vector3.ZERO
		State.RECOVER:
			_state_t -= delta
			if _state_t <= 0.0:
				_state = State.MOVE
				_attack_t = _cooldown() * randf_range(0.85, 1.15)
			return Vector3.ZERO

	_attack_t -= delta
	if _attack_t <= 0.0 and dist < data.preferred_distance:
		_set_state(State.WINDUP, data.windup_time)
		_charge_dir = _aim
		_strike_at = global_position + _aim * data.slam_reach
		_strike_at.y = 0.0
		Sfx.play(&"choir", 0.05, -6.0)
		return Vector3.ZERO
	return dir * speed


func _strike_slam() -> void:
	model.play_land()
	Sfx.play(&"smite", 0.08, 0.0)
	get_tree().call_group(&"camera_rig", &"shake", 0.18)
	var r := data.slam_radius
	EnemyModel.shockwave(_strike_at, r * 1.15, Art.HOLY, 0.5)
	EnemyModel.light_flash(_strike_at + Vector3(0.0, 0.3, 0.0), r * 0.6, Art.HOLY, false)
	EnemyModel.poof(_strike_at + Vector3(0.0, 0.15, 0.0), Art.STONE, Art.BONE, 10, 0.5, r * 0.8)
	var player := Game.player
	if player and not player.is_dead:
		var d := player.global_position - _strike_at
		d.y = 0.0
		if d.length() < r:
			player.take_damage(data.slam_damage * _damage_scale, _strike_at)


# ---------------------------------------------------------------- support behaviours

## Hovers around `pref` from the demon, strafing (the SHOOT movement, without the attack).
func _hang_back(dir: Vector3, dist: float, pref: float) -> Vector3:
	if randf() < get_physics_process_delta_time() * 0.25:
		_strafe_sign = -_strafe_sign
	var radial := clampf((dist - pref) / 2.0, -1.0, 1.0)
	var tangent := Vector3(-dir.z, 0.0, dir.x) * _strafe_sign
	var m := dir * radial + tangent * (1.0 - absf(radial) * 0.6)
	if m.length_squared() < 0.0001:
		return Vector3.ZERO
	return m.normalized() * speed


## Ticks the ATTACK / RECOVER timers shared by the support behaviours. Returns true while one
## of them is running (the caller then returns its own velocity).
func _tick_busy(delta: float) -> bool:
	if _state == State.ATTACK or _state == State.RECOVER:
		_state_t -= delta
		if _state_t <= 0.0:
			_state = State.MOVE
		return true
	return false


## HEAL: hangs back; when a wounded ally is near, stops and channels a circle that heals them.
func _heal_ai(delta: float, dir: Vector3, dist: float) -> Vector3:
	if _state == State.WINDUP:
		_state_t -= delta
		if _holy_tele:
			_holy_tele.show_circle(global_position, data.heal_radius, _state_progress(), HEAL_COLOR)
		if _state_t <= 0.0:
			_hide_telegraph()
			_cast_heal()
			_set_state(State.RECOVER, 0.5)
		return Vector3.ZERO
	if _tick_busy(delta):
		return Vector3.ZERO
	_attack_t -= delta
	if _attack_t <= 0.0:
		if _wounded_ally_near():
			_attack_t = _cooldown() * randf_range(0.9, 1.1)
			_set_state(State.WINDUP, data.windup_time)
			return Vector3.ZERO
		_attack_t = 0.4
	return _hang_back(dir, dist, data.preferred_distance)


func _wounded_ally_near() -> bool:
	for e in _allies_within(data.heal_radius, true):
		if e.hp < e.max_hp * 0.9:
			return true
	return false


## Living, non-boss enemies within `r` (optionally including self).
func _allies_within(r: float, include_self: bool) -> Array[Enemy]:
	var out: Array[Enemy] = []
	var r2 := r * r
	var at := global_position
	if r <= 12.0:
		# Perf: grid lookup (Crowd keeps every enemy bucketed for separation anyway).
		var near: Array[Enemy] = []
		Crowd.query(at, r, near)
		for e in near:
			if (e != self or include_self) and not e.is_in_group(&"boss"):
				out.append(e)
		return out
	# Perf: shared per-frame list, distance test first (cheap) and the group lookup last.
	for n in Perf.enemies():
		var e := n as Enemy
		if e == null or e.is_dying or (e == self and not include_self):
			continue
		if e.global_position.distance_squared_to(at) <= r2 and not e.is_in_group(&"boss"):
			out.append(e)
	return out


func _cast_heal() -> void:
	model.play_attack()
	Sfx.play_at(&"heal", global_position, 0.1, -6.0)
	EnemyModel.shockwave(global_position, data.heal_radius, HEAL_COLOR, 0.5)
	for e in _allies_within(data.heal_radius, true):
		# characters-new (round 5, marked): through Enemy.heal (clamp, "+N", healed / Game.enemy_healed).
		if e.heal(e.max_hp * data.heal_fraction, &"heal_circle") > 0.0:
			HolyFX.motes(e.global_position + Vector3(0.0, 0.6, 0.0), 4, HEAL_COLOR, 0.4, 1.0, 0.7)


## SHIELD: every SUPPORT_TICK wards the nearest allies inside ward_radius.
func _ward_tick(delta: float) -> void:
	if _aura_fx:
		_aura_fx.global_position = Vector3(global_position.x, 0.06, global_position.z)
	_support_t -= delta
	if _support_t > 0.0:
		return
	_support_t = SUPPORT_TICK
	var allies := _allies_within(data.ward_radius, false)
	var here := global_position
	allies.sort_custom(func(a: Enemy, b: Enemy) -> bool:
		return a.global_position.distance_squared_to(here) < b.global_position.distance_squared_to(here))
	for i in mini(allies.size(), data.ward_max):
		allies[i].apply_ward(SUPPORT_TICK * 2.0, data.ward_reduction)


## Called by SHIELD bearers: take (1 - reduction) damage for `seconds`.
func apply_ward(seconds: float, reduction: float) -> void:
	_ward_t = maxf(_ward_t, seconds)
	_ward_mult = 1.0 - clampf(reduction, 0.0, 0.9)


# ---- characters-new (round 4, marked): heal API for model-side and support mechanics (Virtue's
# miracle, the Paschal Lamb, Sanctified "hallowed", ...). Clamped to max_hp, refused while dying;
# shows a green "+N", emits `healed` here and Game.enemy_healed for run tallies / UI.
signal healed(amount: float, source: StringName)
## Emitted once from die(), before the death FX (characters-new round 5).
signal died(enemy: Enemy)


## Restores up to `amount` HP. Returns the HP actually restored.
func heal(amount: float, source: StringName = &"", show_number: bool = true) -> float:
	if is_dying or amount <= 0.0 or hp >= max_hp:
		return 0.0
	var applied := minf(amount, max_hp - hp)
	hp += applied
	healed.emit(applied, source)
	Game.enemy_healed.emit(self, applied)
	if show_number and data:
		DamageNumber.spawn(applied, global_position + Vector3(0.0, data.size * 1.4 + data.hover, 0.0), HEAL_COLOR, "+")
	return applied
# ---- end characters-new


func _update_ward(delta: float) -> void:
	if _ward_t > 0.0:
		_ward_t -= delta
		if _ward_fx == null:
			_ward_fx = _ring_fx(model, 0.45, WARD_COLOR, 1.2)
			_ward_fx.position.y = 1.7 + data.hover / maxf(data.size, 0.01)
		_ward_fx.visible = true
		_ward_fx.rotation.y += delta * 2.0
	elif _ward_fx and _ward_fx.visible:
		_ward_fx.visible = false


## A flat additive ring (ward aura on the ground / halo over a warded head).
func _ring_fx(parent: Node3D, radius: float, color: Color, energy: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = radius * 0.9
	t.outer_radius = radius
	t.rings = 32
	t.ring_segments = 4
	mi.mesh = t
	mi.material_override = HolyFX.additive(color, energy)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## KITE: SHOOT that backs off whenever the demon closes in, and keeps backing while it fires.
func _kite_ai(delta: float, dir: Vector3, dist: float) -> Vector3:
	var pref := data.preferred_distance
	var retreat := -dir * speed * 0.45 if dist < pref * 0.6 else Vector3.ZERO
	if _state == State.WINDUP:
		_state_t -= delta
		_aim_windup()
		if _state_t <= 0.0:
			_fire(_shot_dir if data.aim_line else _aim)
			_hide_telegraph()
			_set_state(State.ATTACK, data.shot_recover_time)
		return retreat
	if _tick_busy(delta):
		return retreat
	_attack_t -= delta
	if _attack_t <= 0.0 and dist < pref * 1.6 and dist > pref * 0.35:
		_attack_t = _cooldown() * randf_range(0.85, 1.15)
		_set_state(State.WINDUP, data.windup_time)
		return retreat
	if dist < pref * 0.75:
		# Flee at an angle (not straight back) so it doesn't get pinned against the crowd.
		var tangent := Vector3(-dir.z, 0.0, dir.x) * _strafe_sign
		return (-dir + tangent * 0.6).normalized() * speed * 1.2
	return _hang_back(dir, dist, pref)


## aim_line shooters: track the demon, lock at AIM_LOCK, and paint the lane the shot will take.
func _aim_windup() -> void:
	if not data.aim_line:
		return
	var p := _state_progress()
	if p < AIM_LOCK or _shot_dir == Vector3.ZERO:
		_shot_dir = _aim
	if _holy_tele:
		var length := minf(data.projectile_speed * 1.1, 20.0)
		_holy_tele.show_line(global_position, _shot_dir, length, 0.9, p)


## EXPLODE: sprints in, lights a fuse within preferred_distance and detonates after windup_time.
func _explode_ai(delta: float, dir: Vector3, dist: float) -> Vector3:
	if _state == State.WINDUP:
		_state_t -= delta
		var p := _state_progress()
		if _holy_tele:
			_holy_tele.show_circle(global_position, data.explode_radius, p, FUSE_COLOR)
		model.set_flash(0.5 + 0.5 * sin(p * p * 40.0))  # quickening blink
		if _state_t <= 0.0:
			_detonate()
			return Vector3.ZERO
		return dir * speed * 0.35
	if _tick_busy(delta):
		return Vector3.ZERO
	if dist < data.preferred_distance:
		_set_state(State.WINDUP, data.windup_time)
		Sfx.play_at(&"boss_charge", global_position, 0.1, -8.0)
		return Vector3.ZERO
	return _chase_dir(dir, dist) * speed * 1.25


## Self-destruct: hurts the demon inside the radius; no XP or kill credit (it was not slain).
func _detonate() -> void:
	is_dying = true
	_hide_telegraph()
	var r := data.explode_radius
	EnemyModel.shockwave(global_position, r * 1.1, FUSE_COLOR, 0.45)
	EnemyModel.light_flash(global_position + Vector3(0.0, 0.5, 0.0), r * 0.7, Art.HOLY, true)
	Sfx.play_at(&"smite", global_position, 0.08, 0.0)
	get_tree().call_group(&"camera_rig", &"shake", 0.2)
	var player := Game.player
	if player and not player.is_dead:
		var d := player.global_position - global_position
		d.y = 0.0
		if d.length() < r:
			player.take_damage(data.explode_damage * _damage_scale, global_position)
	# The holy fire does not spare the faithful: other angels in the blast are hurt too.
	var ally_dmg := data.explode_damage * data.explode_ally_mult * _hp_scale
	if ally_dmg > 0.0:
		for e in _allies_within(r, false):
			var away := e.global_position - global_position
			away.y = 0.0
			e.take_damage(ally_dmg, away.normalized() * 6.0 if away.length_squared() > 0.01 else Vector3.ZERO)
	model.death_burst(global_position + Vector3(0.0, 0.45 * data.size + data.hover, 0.0), data.size, false)
	queue_free()


## SUMMON: keeps its distance; every attack_cooldown calls minions while below summon_max.
func _summon_ai(delta: float, dir: Vector3, dist: float) -> Vector3:
	if _state == State.WINDUP:
		_state_t -= delta
		if _holy_tele:
			_holy_tele.show_circle(global_position, 2.0 * data.size, _state_progress())
		if _state_t <= 0.0:
			_hide_telegraph()
			_call_minions()
			_set_state(State.RECOVER, 0.6)
		return Vector3.ZERO
	if _tick_busy(delta):
		return Vector3.ZERO
	_attack_t -= delta
	if _attack_t <= 0.0 and dist < data.preferred_distance * 1.8:
		# Untyped param: a freed summon must reach is_instance_valid() (a typed one errors first).
		_summons.assign(_summons.filter(func(e: Variant) -> bool: return is_instance_valid(e) and not (e as Enemy).is_dying))
		_attack_t = _cooldown() * randf_range(0.9, 1.1)
		if _summons.size() < data.summon_max:
			_set_state(State.WINDUP, data.windup_time)
			return Vector3.ZERO
	return _hang_back(dir, dist, data.preferred_distance)


func _call_minions() -> void:
	var minion: EnemyData = data.summon if data.summon else load(DEFAULT_SUMMON) as EnemyData
	var scene := load(ENEMY_SCENE_PATH) as PackedScene
	if minion == null or scene == null:
		return
	model.play_attack()
	Sfx.play_at(&"choir", global_position, 0.05, -8.0)
	var n := mini(data.summon_count, data.summon_max - _summons.size())
	var a0 := randf() * TAU
	for i in n:
		var a := a0 + TAU * float(i) / float(maxi(n, 1))
		var at := global_position + Vector3(cos(a), 0.0, sin(a)) * 1.6 * data.size
		var e := scene.instantiate() as Enemy
		e.setup(minion, _hp_scale, _damage_scale, _speed_scale)
		_summons.append(e)
		Game.spawn.call_deferred(e, at)
		HolyFX.flash(at + Vector3(0.0, 0.6, 0.0), 1.2, 0.4)


func _hide_telegraph() -> void:
	if _holy_tele:
		_holy_tele.hide_now()


# ---------------------------------------------------------------- damage

## Damage with a known source (weapons pass themselves): sets last_hit_source while the hit is
## processed, so Game.enemy_struck listeners (weapon statuses) know exactly who struck.
static func hit(e: Enemy, amount: float, knockback: Vector3, source: Object) -> void:
	if e == null or not is_instance_valid(e):
		return
	e.last_hit_source = source
	e.take_damage(amount, knockback)
	if is_instance_valid(e):
		e.last_hit_source = null


## Taunt hook (decoys, banners): for `seconds` the enemy walks to and aims at `target` instead of
## the demon. Contact / area damage still only hurts the demon. Call again to refresh.
func set_taunt_target(target: Node3D, seconds: float) -> void:
	_taunt = target
	_taunt_t = seconds


func clear_taunt() -> void:
	_taunt = null
	_taunt_t = 0.0


func is_taunted() -> bool:
	return _taunt_t > 0.0 and is_instance_valid(_taunt)


func take_damage(amount: float, knockback := Vector3.ZERO) -> void:
	if is_dying:
		return
	if _ward_t > 0.0:
		amount *= _ward_mult  # shielded by a SHIELD bearer
	hp -= amount
	Game.enemy_hit.emit(global_position, amount)
	Game.enemy_struck.emit(self, amount)
	var kb := knockback * data.knockback_scale
	if hp > 0.0:
		_try_hitfreeze(amount, kb)
	if _freeze_t > 0.0:
		_freeze_kb += kb  # released when the freeze ends, like a fighter's launch after hitstop
	else:
		_knockback += kb
	_apply_stagger(knockback.length() * data.knockback_scale)
	_flash_t = FLASH_TIME
	_squash = 1.0
	model.set_flash(1.0)
	model.jiggle_eyes(1.0, -knockback)  # characters-polish: flinch away from the blow
	DamageNumber.spawn(amount, global_position + Vector3(0, data.size * 1.4 + data.hover, 0))
	if hp <= 0.0:
		die()
	elif not _enraged and data.enrage_hp > 0.0 and hp < max_hp * data.enrage_hp:
		_enrage()


## Starts a hit freeze (see HITFREEZE_*) if this enemy can take one right now.
func _try_hitfreeze(amount: float, kb: Vector3) -> void:
	if not _hitfreeze_ok or _freeze_t > 0.0 or _freeze_cd > 0.0:
		return
	if _state != State.MOVE and _state != State.RECOVER:
		return
	var heavy := clampf(amount / maxf(max_hp, 1.0) / HITFREEZE_HEAVY_FRAC, 0.0, 1.0)
	_freeze_len = lerpf(HITFREEZE_MIN, HITFREEZE_MAX, sqrt(heavy))
	_freeze_t = _freeze_len
	_freeze_cd = _freeze_len + HITFREEZE_GAP
	_freeze_dir = kb.normalized() if kb.length_squared() > 0.0001 else model.global_basis.x


## One frozen tick: no AI, movement or animation; the model shakes along the hit direction with a
## decaying amplitude. On the last tick the held knockback is released.
func _hitfreeze_step(delta: float) -> void:
	_freeze_t -= delta
	if _freeze_t <= 0.0:
		_freeze_t = 0.0
		model.position = Vector3(0.0, data.hover, 0.0)
		_knockback += _freeze_kb
		_freeze_kb = Vector3.ZERO
		return
	var k := _freeze_t / maxf(_freeze_len, 0.001)
	var side := 1.0 if Engine.get_physics_frames() % 2 == 0 else -1.0
	var off := _freeze_dir * (HITFREEZE_SHAKE * data.size * k * side)
	model.position = Vector3(off.x, data.hover, off.z)


## Attack cooldown, shortened while frenzied.
func _cooldown() -> float:
	return data.attack_cooldown * (0.6 if _enraged else 1.0)


## Frenzy (EnemyData.enrage_hp): faster, attacks sooner; a red flare marks it.
func _enrage() -> void:
	_enraged = true
	speed *= data.enrage_speed_mult
	EnemyModel.light_flash(global_position + Vector3(0.0, 0.8 * data.size, 0.0), 0.8 * data.size, Art.CRIMSON, false)
	Sfx.play_enemy_voice(data, global_position, -3.0)


func _apply_stagger(force: float) -> void:
	if force < STAGGER_MIN:
		return
	_stagger_t = maxf(_stagger_t, minf(force * STAGGER_PER_KNOCK, STAGGER_MAX))
	# A heavy blow breaks a wind-up (never an elite's): the attack is lost, cooldown restarts.
	if force >= INTERRUPT_KNOCK and _state == State.WINDUP and not is_elite():
		_hide_telegraph()
		_set_state(State.RECOVER, INTERRUPT_RECOVER)
		_attack_t = _cooldown() * randf_range(0.5, 0.8)


func die() -> void:
	if is_dying:
		return
	is_dying = true
	Game.enemy_died.emit(global_position, data)
	Game.kills += 1
	_drop_xp()
	var elite := is_elite()
	# Elites always leave a healing chalice; regular enemies rarely do.
	BloodChalice.try_drop(global_position, 1.0 if elite else 0.012)
	_hide_telegraph()
	# characters-new (round 5, marked): death mechanics that must always fire (martyr burst,
	# revenant rise, lamb sacrifice, frost shards...) run here, before any death FX can take over.
	died.emit(self)
	if model and model.has_method(&"on_host_died"):
		model.call(&"on_host_died", self)
	var s := data.size
	model.death_burst(global_position + Vector3(0.0, 0.45 * s + data.hover, 0.0), s, elite)
	Sfx.play(&"angel_death", 0.12, 0.0 if elite else -5.0)
	if elite:
		Sfx.play(&"choir", 0.0, -2.0)
		get_tree().call_group(&"camera_rig", &"shake", 0.25)
	queue_free()


func _drop_xp() -> void:
	if get_tree().get_node_count_in_group(&"gems") > MAX_GEMS:
		var best: XPGem = null
		var best_d := INF
		for n in get_tree().get_nodes_in_group(&"gems"):
			var g := n as XPGem
			if g == null or g.is_queued_for_deletion():
				continue
			var d := g.global_position.distance_squared_to(global_position)
			if d < best_d:
				best_d = d
				best = g
		if best:
			best.value += data.xp_value
			return
	var gem: XPGem = GEM_SCENE.instantiate()
	gem.value = data.xp_value
	# Deferred: die() is usually called from a physics callback, where adding areas is not allowed.
	Game.spawn.call_deferred(gem, global_position + Vector3(0, 0.4, 0))


## Moves a straggler back into play, ahead of where the player is heading.
func _relocate(player: Player, dir_to_player: Vector3) -> void:
	var ahead := dir_to_player.rotated(Vector3.UP, randf_range(-0.7, 0.7))
	global_position = Maps.spawn_position(player.global_position + ahead * RELOCATE_RADIUS)
	_state = State.MOVE
	_hide_telegraph()
	reset_physics_interpolation()
