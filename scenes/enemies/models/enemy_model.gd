class_name EnemyModel
extends Node3D
## Base class for angel models. The seven angels are Blender models
## (tools/blender/models/enemies/*.py -> res://assets/models/enemies/*.glb) loaded with use_glb();
## the base maps the enemy state onto their animations (see _drive_glb). Code-built models (Art
## kit, e.g. bosses) still work exactly as before. Forward is -Z, feet at
## y = 0, roughly 1-1.5 units tall. The owning Enemy scales this node by EnemyData.size (and
## squashes it on hits), so subclasses animate their own child pivots, never this node.
##
## Override build() to create geometry and animate() to move it (call super.animate() first:
## it beats the wings, blinks the eyes and runs the state clock). Override _on_state_enter()
## for one-shot reactions (sounds), play_land() for leapers.
##
## Blender-model animation API (see "Blender (.glb) models" below):
##   play_oneshot(clip, blend, speed) -> seconds: plays a clip once and holds it until it ends,
##     then hands back to the state's clip / idle / walk loop.
##   proximity_range / proximity_attack(): cosmetic close-range attack of CHASE enemies.
##   State.RECOVER plays recover_anim ("recover" or "land" by default) automatically.
##   move_clip_speed: measured ground speed of the walk clip -> feet never slide.
##   attack_real_speed, blend_* times, resume_loops, corpse_* settings.
##
## Helpers: halo(), wing_pair(), eye() / eye_ring() / eye_cluster().
## Death: Enemy calls death_burst(): a flash of light, drifting light motes, falling feathers
## (feather_count) and optional `debris` (&"shard" stone, &"gold", &"steel", &"feather", &"mote").

## RECOVER: the pause after a charge / leap landing / slam strike (bosses never report it).
enum State { MOVING = 0, WINDUP = 1, ATTACKING = 2, RECOVER = 3 }


## Perf caps for death effects (see death_burst / spawn_corpse).
const DEATH_FX_PER_FRAME := 4
const CORPSES_PER_FRAME := 3
const ELITE_MOTES := 14
const ELITE_FEATHERS := 10
const MAX_CORPSES := 32
const CORPSE_POOL_PER_MODEL := 12
static var _corpses_alive := 0
var _built := false
var _lod_hidden := false
## Perf LOD switch (A/B: --bench-exp=nolodhide).
static var lod_hide := true
static var _corpse_pool := {}  # glb path -> Array[GlbModel] (hidden, in Game.world)

## Color of the death flash, motes and halo light.
var light_color := Art.HOLY
## Tint of the feathers shed on death.
var feather_color := Art.HOLY_WHITE
## Feathers shed on a regular death (x3 for elites). 0 = none.
var feather_count := 4
## Light motes released on a regular death (x3 for elites).
var mote_count := 6
## Debris kinds flung out on death (see spawn_debris). Empty = none.
var debris: Array[StringName] = []
## Tint for colored debris.
var debris_color := Art.IVORY

## Free-running animation clock (randomised so crowds don't move in sync).
var t := 0.0
## 1 right after play_attack(), decays to 0. Subclasses use it for recoil.
var attack_kick := 0.0
## 1 right after play_land(), decays to 0 (leapers use it for the landing squash).
var land_kick := 0.0
## 0..1 progress through the current wind-up / attack / recovery, set by Enemy every frame.
var state_progress := 0.0
## Total length (s) of the current wind-up / attack / recovery, set by Enemy every frame
## (0 = unknown: bosses; the length is then estimated from state_progress).
var state_duration := 0.0
## Actual horizontal speed (world m/s, knockback included), set by Enemy every frame.
## < 0 = unknown (bosses, bestiary): walk playback then follows move_ratio.
var ground_speed := -1.0
## The model's world scale (EnemyData.size, without the hit squash), set by Enemy.
var body_scale := 1.0
## Seconds spent in the current state.
var state_time := 0.0

## Wing beat, read every frame by the base animate(). Subclasses may change them any time.
## lift: rest elevation of the wing tips (rad, + = up). sweep: rest fold backwards (rad).
var wing_speed := 5.0
var wing_amp := 0.3
var wing_lift := 0.15
var wing_sweep := 0.15
## 0..1 extra eye-widening (attacks, hits); decays.
var eye_flare := 0.0

var _wings: Array[Node3D] = []
var _wing_side: Array[float] = []
var _wing_phase := 0.0
var _eyes: Array[Node3D] = []
var _eye_size: Array[float] = []
var _eye_blink: Array[float] = []
var _halos: Array[Node3D] = []
var _halo_scale: Array[float] = []
var _last_state := -1

## ---- Blender (.glb) models -------------------------------------------------------------
## Set by use_glb() in build(). When present, animate() drives its named animations:
## MOVING -> move_anim (or idle_anim when nearly still; rate from the real ground speed),
## WINDUP -> "windup", ATTACKING -> "attack" (both time-stretched to the state's length from the
## first frame, unless attack_real_speed), RECOVER -> recover_anim if the model has one,
## take_damage (jiggle_eyes) -> "hit" then back. A one-shot (play_oneshot) holds until its clip
## ends; a new wind-up / attack cuts it. On death a short-lived copy plays "death" while it
## dissolves into light (corpse_on_death).
var glb: GlbModel
## Path of the loaded .glb (for the death copy).
var glb_path := ""
## Pivot that holds `glb`: code-driven offsets (hop arcs, sway) go here, never on `glb`.
var rig: Node3D
## Loop played while moving / standing still. Missing clips fall back to the other.
var move_anim := &"walk"
var idle_anim := &"idle"
## Below this move_ratio the idle clip plays (with a little hysteresis).
var idle_below := 0.12
## Ground speed (m/s at model scale 1) at which move_anim at playback 1 keeps its feet planted
## (the Blender script's stride speed). > 0: playback = real ground speed / (this * body scale),
## so feet never slide, knockback included. 0: playback lerps move_speed_min..max by move_ratio.
var move_clip_speed := 0.0
## Playback rate of move_anim at move_ratio 0 / 1 (when move_clip_speed is 0 or speed unknown).
var move_speed_min := 0.55
var move_speed_max := 1.15
## Loops (idle / walk / fly) resume where they left off after a one-shot instead of restarting
## from the rest pose (their phase keeps advancing while away).
var resume_loops := true
## Play "attack" at real speed (as a one-shot that finishes even after the attack state ends)
## instead of stretching it over the attack state.
var attack_real_speed := false
## Clip for State.RECOVER. &"" = "recover", else "land", else none (the loop plays).
var recover_anim := &""
## Cross-fade times (s): into loops, back into a loop after a wind-up / attack / one-shot,
## into "windup", into "attack", into the recover clip, into "hit".
var blend_loop := 0.2
var blend_from_action := 0.2
var blend_windup := 0.1
var blend_attack := 0.1
var blend_recover := 0.03
var blend_hit := 0.05
## Extra pause after a "hit" before another hit reaction may play.
var hit_cooldown := 0.5
## CHASE enemies never enter WINDUP / ATTACKING: when > 0, a moving model within this distance
## (m at model scale 1, scaled by body_scale) of the player calls proximity_attack() at most
## every proximity_cooldown s (x0.85-1.25). Purely visual; contact damage is unchanged.
var proximity_range := 0.0
var proximity_cooldown := 2.0
var proximity_anim := &"attack"
## Spawn a dissolving copy that plays "death" when the enemy dies.
var corpse_on_death := true
## Seconds the death copy stays. < 0 = the "death" clip's length + corpse_linger.
var corpse_time := -1.0
var corpse_linger := 0.1
## Fraction (0..1) of the corpse's life before its white burn starts (elites: later, so the
## death pose reads first).
var corpse_flash_delay := 0.0
## true: the corpse shrinks away over its last 0.3 s. false: it sinks into the ground instead
## (keeps its size, so big deaths read to the end).
var corpse_shrink := true

## ---- procedural pose layer (characters-polish; Blender models only) ---------------------
## Pivot between `rig` and `glb`, owned by the base: hit flinch, wind-up crouch and strike
## stretch go here (subclasses keep using `rig` for their own offsets).
var pose_pivot: Node3D
## Code-built models (ProcModel sets it): after build(), every child is moved under a new
## pose_pivot so they get the flinch / squash / telegraph too (Blender models get it in use_glb).
var wrap_pose_pivot := false
## Readability scale on pose_pivot (collision unchanged; set per model by EnemyPolish).
var visual_scale := 1.0
## DeathFx style (&"shatter" / &"ragdoll" / &"crumble"; &"" = the model's own corpse). Set per
## model by EnemyPolish from the CharacterRoster faction.
var death_variant := &""
## World direction the last blow came from (ragdoll deaths fall away from it).
var last_hit_from := Vector3.ZERO
## Peak white glow (0..1) over the last part of a wind-up: a readable "strike incoming" cue.
## 0 disables it.
var telegraph_glow := 0.3
## Crouch during a wind-up (fraction of height), released as a stretch when the attack fires.
var anticipation_squash := 0.05
## Flinch strength (rad of tilt away from the blow) on hits. Heavier bodies flinch less.
var flinch_strength := 0.16
## Minimum seconds between flinches (rapid-fire weapons would otherwise pin the body tilted).
const FLINCH_INTERVAL := 0.15
var _last_flinch := -1.0
var _flinch := Vector2.ZERO  # x = tip back (away from the blow), y = roll
var _flinch_v := Vector2.ZERO
var _flinch_axis := Vector3.RIGHT  # model-local axis the flinch tips about
var _pose_active := false
var _glow_now := 0.0
var _glow_meshes: Array[GeometryInstance3D] = []
## Full procedural secondary motion (wings, capes, lean; CharacterMotion) for big angels only
## (body_scale >= MOTION_MIN_SCALE: elites are few, so the per-joint cost stays small).
const MOTION_MIN_SCALE := 1.5
var motion: CharacterMotion

var _hit_cd := 0.0
var _oneshot := &""
var _oneshot_t := 0.0
var _anim_state := -1
var _next_loop_blend := -1.0
var _proximity_cd := 0.0
## Loop clip -> [position, model time when left, playback speed].
var _loop_saved := {}


func _ready() -> void:
	ensure_built()
	if wrap_pose_pivot and pose_pivot == null:
		_wrap_in_pose_pivot()
	EnemyPolish.apply(self)
	if pose_pivot and visual_scale != 1.0:
		pose_pivot.scale = Vector3.ONE * visual_scale
	_proximity_cd = randf_range(0.2, maxf(proximity_cooldown, 0.2))


## Runs build() once (normally from _ready). Enemy calls it *before* adding a ProcModel to the
## tree: the dozens of primitive parts that ProcModel.finish() merges away then never enter the
## scene tree (no render instances, no node_added callbacks), which made procedural enemies
## spawn ~3x faster (perf role). build() must therefore not need the tree (most never do).
func ensure_built() -> void:
	if _built:
		return
	_built = true
	t = randf() * 100.0
	_wing_phase = randf() * TAU
	build()


## Loads a Blender model under `rig`. Call from build(). Returns the GlbModel.
func use_glb(path: String) -> GlbModel:
	glb_path = path
	rig = Art.pivot(self)
	pose_pivot = Art.pivot(rig)
	glb = GlbModel.create(path)
	# Blender models face Blender -Y, which glTF imports as +Z; turn them to Godot's forward (-Z).
	glb.rotation.y = PI
	pose_pivot.add_child(glb)
	if body_scale >= MOTION_MIN_SCALE:
		motion = CharacterMotion.attach(glb, self)
		if motion:
			# Heavy, slow giants: less lean, slower and wider swings.
			motion.lean_accel *= 0.6
			motion.wing_k *= 0.7
	if glb.anim_player:
		# Desync crowds.
		glb.anim_player.seek(randf() * 0.8, true)
	return glb


## Finds a node of the loaded model by name (e.g. a joint to hang a light or effect on).
func glb_node(node_name: String) -> Node3D:
	if glb == null or glb.scene_root == null:
		return null
	return glb.joint(node_name)  # perf round 3: works for skinned (GlbSkin) models too


func _anim_length(anim_name: StringName) -> float:
	if glb == null or not glb.has_anim(anim_name):
		return 0.0
	return glb.anim_player.get_animation(anim_name).length


## Plays `clip` once (from the start) and holds it until it ends, then hands back to the
## state's clip / the idle-walk loop (cross-fading with blend_from_action). A new wind-up or
## attack cuts it short; hits don't interrupt it. Returns its duration in seconds (0 if the
## model has no such clip).
func play_oneshot(clip: StringName, blend: float = 0.08, speed: float = 1.0) -> float:
	if glb == null or not glb.has_anim(clip):
		return 0.0
	var spd := maxf(speed, 0.01)
	var length := _anim_length(clip) / spd
	_start_clip(clip, blend, spd, true)
	_oneshot = clip
	# Hand back a touch early so the blend out overlaps the clip's last frames.
	_oneshot_t = maxf(length - blend_from_action * 0.5, length * 0.85)
	return length


## True while a play_oneshot() clip is held.
func is_oneshot_playing() -> bool:
	return _oneshot != &""


## Cuts the current one-shot (the next frame blends to whatever the state plays).
func stop_oneshot() -> void:
	if _oneshot != &"":
		_oneshot = &""
		_next_loop_blend = blend_from_action


## Override hook: the CHASE close-range attack (see proximity_range). Default: plays
## proximity_anim as a one-shot.
func proximity_attack() -> void:
	play_oneshot(proximity_anim, blend_attack)


func _loop_anim(move_ratio: float) -> StringName:
	# Hysteresis: once walking, keep walking down to 70 % of the threshold (crowd jostle).
	var below := idle_below * (0.7 if glb.current == move_anim else 1.0)
	var want := move_anim if move_ratio >= below else idle_anim
	if glb.has_anim(want):
		return want
	return idle_anim if want == move_anim else move_anim


## Starts a clip, remembering where the outgoing loop was (resume_loops).
func _start_clip(clip: StringName, blend: float, speed: float, restart: bool) -> void:
	var ap := glb.anim_player
	var cur := glb.current
	if cur != &"" and cur != clip and ap.current_animation == cur and ap.has_animation(cur) \
			and ap.get_animation(cur).loop_mode != Animation.LOOP_NONE:
		_loop_saved[cur] = [ap.current_animation_position, t, ap.speed_scale]
	glb.play(clip, blend, speed, restart)


## Drives the .glb animations from the enemy state (called by animate()).
func _drive_glb(delta: float, move_ratio: float, state: int) -> void:
	if glb == null or glb.anim_player == null:
		return
	_hit_cd -= delta
	_proximity_cd -= delta
	if _oneshot != &"":
		_oneshot_t -= delta
		if _oneshot_t <= 0.0 or glb.current != _oneshot:
			_oneshot = &""
			_next_loop_blend = blend_from_action
	if state != _anim_state:
		var prev := _anim_state
		_anim_state = state
		_enter_anim_state(state, prev)
	if _oneshot != &"":
		return
	match state:
		State.WINDUP, State.ATTACKING:
			var clip: StringName = &"windup" if state == State.WINDUP else &"attack"
			# (If the clip is no longer current, e.g. a real-speed attack already finished,
			# fall through to the loop.)
			if glb.current == clip:
				if not (state == State.ATTACKING and attack_real_speed):
					glb.set_speed(_stretch_speed(clip))
				return
		State.MOVING:
			if proximity_range > 0.0 and _proximity_cd <= 0.0 and _near_player(proximity_range * body_scale):
				_proximity_cd = proximity_cooldown * randf_range(0.85, 1.25)
				proximity_attack()
				if _oneshot != &"":
					return
	_play_loop(move_ratio)


func _enter_anim_state(state: int, prev: int) -> void:
	match state:
		State.WINDUP, State.ATTACKING:
			_oneshot = &""
			var clip: StringName = &"windup" if state == State.WINDUP else &"attack"
			if not glb.has_anim(clip):
				return
			if state == State.ATTACKING and attack_real_speed:
				play_oneshot(clip, blend_attack, 1.0)
				return
			# Stretch speed from the very first frame (a 0.3 s attack can't spare any).
			_start_clip(clip, blend_windup if state == State.WINDUP else blend_attack, _stretch_speed(clip), true)
		State.RECOVER:
			var clip := recover_anim
			if clip == &"":
				clip = &"recover" if glb.has_anim(&"recover") else &"land"
			if glb.has_anim(clip):
				play_oneshot(clip, blend_recover)
			elif _oneshot == &"":
				_next_loop_blend = blend_from_action
		_:
			if (prev == State.WINDUP or prev == State.ATTACKING or prev == State.RECOVER) and _oneshot == &"":
				_next_loop_blend = blend_from_action


## Playback rate that fits `clip` into the current state's length.
func _stretch_speed(clip: StringName) -> float:
	var total := state_duration
	if total <= 0.0:
		# Unknown (bosses): estimate from progress once there is enough of it.
		if state_progress <= 0.04 or state_time <= 0.0:
			return glb.anim_player.speed_scale if glb.current == clip else 1.0
		total = state_time / state_progress
	return clampf(_anim_length(clip) / maxf(total, 0.05), 0.25, 4.0)


func _play_loop(move_ratio: float) -> void:
	var clip := _loop_anim(move_ratio)
	var spd := 1.0
	if clip == move_anim:
		if move_clip_speed > 0.0 and ground_speed >= 0.0:
			spd = clampf(ground_speed / (move_clip_speed * maxf(body_scale, 0.01)), 0.3, 3.0)
		else:
			spd = lerpf(move_speed_min, move_speed_max, clampf(move_ratio, 0.0, 1.0))
	if glb.current == clip and glb.anim_player.is_playing():
		glb.set_speed(spd)
		return
	var blend := _next_loop_blend if _next_loop_blend >= 0.0 else blend_loop
	_next_loop_blend = -1.0
	var resume: Array = _loop_saved.get(clip, [])
	_start_clip(clip, blend, spd, false)
	if resume_loops and resume.size() == 3 and glb.anim_player.current_animation == clip:
		var length := _anim_length(clip)
		if length > 0.0:
			var pos: float = resume[0] + (t - float(resume[1])) * float(resume[2])
			glb.anim_player.seek(fposmod(pos, length), false)


func _near_player(dist: float) -> bool:
	var p := Game.player
	if p == null or not is_instance_valid(p) or not is_inside_tree():
		return false
	var to := p.global_position - global_position
	to.y = 0.0
	return to.length_squared() < dist * dist


## Perf LOD, called by Enemy when it goes off / on screen: off-screen models stop animating
## (Enemy also stops calling animate()). Override to pause extra per-frame work of your own
## (super.set_lod(on) first).
func set_lod(on: bool) -> void:
	# Off screen the whole model is hidden (perf round 2: render instances, shadow casters and the
	# per-node transform / interpolation work of ~300 models were the biggest remaining cost).
	# Only undo a hide we did ourselves.
	if not on and visible and lod_hide:
		visible = false
		_lod_hidden = true
	elif on and _lod_hidden:
		visible = true
		_lod_hidden = false
	if glb and glb.anim_player:
		glb.anim_player.active = on
	if motion:
		# CharacterMotion runs off mixer_applied (stops with the mixer) plus a cheap per-tick measure.
		motion.set_physics_process(on)


## Override: build the model's geometry (called once from _ready).
func build() -> void:
	pass


## Override (call super.animate first). `move_ratio` is 0..1 of the enemy's walk speed,
## `state` is EnemyModel.State (0 moving, 1 winding up, 2 attacking / charging / leaping).
func animate(delta: float, move_ratio: float, state: int) -> void:
	t += delta
	attack_kick = maxf(attack_kick - delta * 4.0, 0.0)
	land_kick = maxf(land_kick - delta * 5.0, 0.0)
	eye_flare = maxf(eye_flare - delta * 2.5, 0.0)
	if state != _last_state:
		_last_state = state
		state_time = 0.0
		_on_state_enter(state)
	else:
		state_time += delta
	_update_wings(delta)
	_update_eyes(delta)
	_update_halos()
	if glb:
		_drive_glb(delta, move_ratio, state)
	if pose_pivot:
		_update_pose(delta, state)


## Override: called from animate() whenever the state changes (EnemyModel.State).
func _on_state_enter(_state: int) -> void:
	pass


## White hit-flash 0..1 on every lit mesh of the model.
func set_flash(amount: float) -> void:
	Art.flash(self, amount)


## Called when an attack fires (projectile shot, charge start, leap take-off, sword strike).
func play_attack() -> void:
	attack_kick = 1.0
	eye_flare = 1.0
	if motion:
		motion.kick(1.0)


## Called when a leaper lands (or a slam connects).
func play_land() -> void:
	land_kick = 1.0


## Hit reaction: every eye snaps wide open; Blender models play "hit" (while moving or
## recovering, never over another one-shot, and not more often than the clip allows, so
## constant damage doesn't freeze them in it).
## `from_dir`: world direction the blow came FROM (Enemy passes -knockback); zero = from the player.
func jiggle_eyes(strength: float = 1.0, from_dir: Vector3 = Vector3.ZERO) -> void:
	eye_flare = maxf(eye_flare, clampf(0.5 * strength, 0.0, 1.0))
	for i in _eye_blink.size():
		_eye_blink[i] = maxf(_eye_blink[i], randf_range(1.0, 3.0))
	if from_dir.length_squared() < 0.0001:
		# No knockback: most blows come from the player's weapons, flinch away from the player.
		var p := Game.player
		if p and is_instance_valid(p) and is_inside_tree():
			from_dir = p.global_position - global_position
	if from_dir.length_squared() > 0.0001:
		hit_from(from_dir, strength)
	if glb == null or _hit_cd > 0.0 or _oneshot != &"" or not glb.has_anim(&"hit"):
		return
	if _last_state != State.MOVING and _last_state != State.RECOVER and _last_state != -1:
		return
	_hit_cd = play_oneshot(&"hit", blend_hit) + hit_cooldown


# ---------------------------------------------------------------- procedural pose layer

func _wrap_in_pose_pivot() -> void:
	pose_pivot = Node3D.new()
	pose_pivot.name = "PosePivot"
	var kids := get_children()
	add_child(pose_pivot)
	for c in kids:
		# Local transforms are kept (the pivot sits at the origin), node refs stay valid.
		c.reparent(pose_pivot, false)


## Flinch away from a blow coming from `from_dir` (world). Cheap: one spring on pose_pivot.
func hit_from(from_dir: Vector3, strength: float = 1.0) -> void:
	last_hit_from = from_dir
	if pose_pivot == null or t - _last_flinch < FLINCH_INTERVAL:
		return
	_last_flinch = t
	var local := global_basis.orthonormalized().inverse() * from_dir
	local.y = 0.0
	if local.length_squared() < 0.0001:
		local = Vector3(0.0, 0.0, -1.0)
	# Tip the top away from the blow: rotate "up" toward -local.
	_flinch_axis = Vector3.UP.cross(-local.normalized()).normalized()
	# Heavier (bigger) bodies flinch less.
	var k := flinch_strength * clampf(strength, 0.0, 2.0) / maxf(body_scale, 1.0)
	_flinch_v.x += k * 22.0
	_pose_active = true
	if motion:
		motion.hit(from_dir, clampf(strength, 0.0, 1.5) * 0.7)


func _update_pose(delta: float, state: int) -> void:
	if pose_pivot == null:
		return
	# Fast path for the crowd: nothing to do while just walking.
	if not _pose_active and _glow_now == 0.0 and attack_kick == 0.0 and land_kick == 0.0 \
			and state != State.WINDUP:
		return
	# Wind-up crouch, strike stretch, landing squash.
	var sq := 0.0
	if state == State.WINDUP:
		var e := clampf(state_progress, 0.0, 1.0)
		sq = -anticipation_squash * e * e * (3.0 - 2.0 * e)
	sq += anticipation_squash * 1.4 * attack_kick * attack_kick - 0.12 * land_kick * land_kick
	# Flinch spring (stiff, quick, slightly bouncy).
	_flinch_v.x += (-_flinch.x * 260.0 - _flinch_v.x * 15.0) * delta
	_flinch.x += _flinch_v.x * delta
	var busy := absf(sq) > 0.001 or absf(_flinch.x) > 0.002 or absf(_flinch_v.x) > 0.02
	if busy or _pose_active:
		_pose_active = busy
		pose_pivot.basis = Basis(_flinch_axis, clampf(_flinch.x, -0.6, 0.6)).scaled(
			Vector3(1.0 - sq * 0.5, 1.0 + sq, 1.0 - sq * 0.5) * visual_scale) if busy \
			else Basis.IDENTITY.scaled(Vector3.ONE * visual_scale)
		if not busy:
			_flinch = Vector2.ZERO
			_flinch_v = Vector2.ZERO
	# Telegraph: the body kindles white over the last ~45 % of a wind-up, flickering faster as
	# the strike nears. Only written when it changes (Enemy's hit flash wins while active).
	var g := 0.0
	if state == State.WINDUP and telegraph_glow > 0.0:
		var p := clampf((state_progress - 0.55) / 0.45, 0.0, 1.0)
		g = telegraph_glow * p * (0.7 + 0.3 * sin(t * (18.0 + 30.0 * p)))
	if absf(g - _glow_now) > 0.02 or (g == 0.0 and _glow_now != 0.0):
		_glow_now = g
		_set_glow(g)


## Sets the shader `flash` on the model's lit meshes (list cached on first use).
func _set_glow(amount: float) -> void:
	if _glow_meshes.is_empty() and pose_pivot:
		var stack: Array[Node] = [pose_pivot]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is MeshInstance3D:
				_glow_meshes.append(n as GeometryInstance3D)
			for c in n.get_children():
				stack.append(c)
	for gi in _glow_meshes:
		if is_instance_valid(gi):
			gi.set_instance_shader_parameter(&"flash", amount)


# ---------------------------------------------------------------- building helpers

## Glowing ring of light. Horizontal by default (reads best from the high camera); `upright`
## stands it behind the head, facing forward. `with_light` adds a small OmniLight: elites only.
func halo(parent: Node3D, pos: Vector3, radius: float, energy: float = 3.0, upright: bool = false,
		with_light: bool = false, color: Color = Art.HOLY) -> Node3D:
	var rot: Vector3 = Vector3(PI * 0.5, 0.0, 0.0) if upright else Vector3.ZERO
	var h := Art.pivot(parent, pos, rot)
	# art-style round 3: ArtStyle.holy_glow (white core -> `color` edge, slow shimmer bands) instead
	# of flat Art.glow; the soft outer bloom is a fresnel shell so it fades at its edges.
	Art.part(h, Art.torus(0.86, 1.0), ArtStyle.holy_glow(Art.HOLY_WHITE, color, energy * 0.9, 0.3),
			Vector3.ZERO, Vector3.ONE * radius)
	Art.part(h, Art.torus(0.6, 1.0), ArtStyle.holy_glow(color, color, energy * 0.2, 0.9),
			Vector3.ZERO, Vector3.ONE * radius * 1.15)
	if with_light:
		Art.light(h, color, 1.4, radius * 7.0)
	_halos.append(h)
	_halo_scale.append(1.0)
	return h


## A pair of feathered wings on shoulder pivots (left at index 0, right at 1). Each wing: a
## leading-edge bone and `feathers` primaries fanning backwards, plus a shorter covert layer
## when `cover` is given. Animated by the base class from wing_speed / wing_amp / wing_lift /
## wing_sweep. `span` is the wing length (model units).
func wing_pair(parent: Node3D, pos: Vector3, span: float, feathers: int = 5, main: Material = null,
		cover: Material = null, half_gap: float = 0.08, bone: Material = null) -> Array[Node3D]:
	if main == null:
		main = Art.mat(Art.HOLY_WHITE.darkened(0.06), 0.7, 0.0, 0.15, true, 0.35)
	var out: Array[Node3D] = []
	for s: float in [-1.0, 1.0]:
		var root := Art.pivot(parent, pos + Vector3(s * half_gap, 0.0, 0.0))
		_build_wing(root, s, span, maxi(feathers, 1), main, cover, bone)
		_wings.append(root)
		_wing_side.append(s)
		out.append(root)
	return out


func _build_wing(root: Node3D, s: float, span: float, n: int, main: Material, cover: Material,
		bone: Material) -> void:
	if bone:
		Art.part(root, Art.box(), bone, Vector3(s * span * 0.5, 0.0, 0.0), Vector3(span, span * 0.07, span * 0.09))
	for i in n:
		var f := (float(i) + 0.5) / float(n)
		var length := span * lerpf(0.42, 0.95, f)
		var width := span * lerpf(0.2, 0.15, f)
		var holder := Art.pivot(root, Vector3(s * span * lerpf(0.1, 0.98, f), 0.0, 0.0),
				Vector3(0.12 + 0.1 * f, s * lerpf(0.0, 0.85, f), 0.0))
		Art.part(holder, Art.sphere(), main, Vector3(0.0, -0.004 * float(i), length * 0.5),
				Vector3(width, span * 0.025, length))
		if cover and i % 2 == 0:
			Art.part(holder, Art.sphere(), cover, Vector3(0.0, span * 0.02, length * 0.22),
					Vector3(width * 1.3, span * 0.03, length * 0.45))


## A single eye at `pos` (in `parent` space) looking along `facing`: a glowing iris with a
## dark slit pupil, optionally set in a dark socket. Blinks on its own.
func eye(parent: Node3D, pos: Vector3, size: float, facing: Vector3 = Vector3.FORWARD,
		socket: bool = false, iris: Color = Art.HOLY_WHITE) -> Node3D:
	var e := Art.pivot(parent, pos)
	var f: Vector3 = facing.normalized() if facing.length_squared() > 0.0001 else Vector3.FORWARD
	var up: Vector3 = Vector3.RIGHT if absf(f.dot(Vector3.UP)) > 0.95 else Vector3.UP
	e.basis = Basis.looking_at(f, up)
	if socket:
		Art.part(e, Art.sphere(), Art.mat(Art.OBSIDIAN, 0.6), Vector3(0.0, 0.0, size * 0.12),
				Vector3(size * 1.35, size * 1.0, size * 0.6))
	Art.part(e, Art.sphere(), Art.glow(iris, 2.4), Vector3.ZERO, Vector3(size, size * 0.75, size * 0.55))
	Art.part(e, Art.sphere(), Art.mat(Art.OBSIDIAN, 0.3, 0.0, 0.0), Vector3(0.0, 0.0, -size * 0.24),
			Vector3(size * 0.16, size * 0.62, size * 0.12))
	_eyes.append(e)
	_eye_size.append(1.0)
	_eye_blink.append(randf_range(0.5, 5.0))
	return e


## `count` eyes around a ring of `radius` in the XZ plane of `parent`, looking outward.
func eye_ring(parent: Node3D, radius: float, count: int, size: float, phase: float = 0.0) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for i in count:
		var a := phase + TAU * float(i) / float(count)
		var d := Vector3(cos(a), 0.0, sin(a))
		out.append(eye(parent, d * radius, size, d))
	return out


## `count` eyes spread over the front of a sphere (`radius`, centered at `center`).
## `cover` 0..1 = how much of the sphere (from the front) they occupy.
func eye_cluster(parent: Node3D, center: Vector3, radius: float, count: int, size: float,
		cover: float = 0.6) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for i in count:
		var z := 1.0 - 2.0 * cover * (float(i) + 0.5) / float(count)
		var r := sqrt(maxf(1.0 - z * z, 0.0))
		var a := float(i) * 2.39996
		var d := Vector3(cos(a) * r, sin(a) * r, -z).normalized()
		out.append(eye(parent, center + d * radius, size, d))
	return out


## A cylinder of `radius` spanning from `a` to `b` (in `parent` space): arms, chains, shafts.
static func limb(parent: Node3D, a: Vector3, b: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var mi := Art.part(parent, Art.cylinder(), material)
	var axis := b - a
	var length := axis.length()
	var y := axis / length if length > 0.0001 else Vector3.UP
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y).normalized()
	mi.transform = Transform3D(Basis(x * radius * 2.0, y * maxf(length, 0.001), z * radius * 2.0), (a + b) * 0.5)
	return mi


# ---------------------------------------------------------------- animation helpers

func _update_wings(delta: float) -> void:
	if _wings.is_empty():
		return
	_wing_phase += delta * wing_speed
	var w := sin(_wing_phase)
	# Fast downstroke, slower upstroke.
	var lift := wing_lift + (w if w > 0.0 else w * 0.75) * wing_amp
	for i in _wings.size():
		var s := _wing_side[i]
		_wings[i].rotation = Vector3(0.0, -s * wing_sweep, s * lift)


func _update_eyes(delta: float) -> void:
	for i in _eyes.size():
		var b := _eye_blink[i] - delta
		var open := 1.0
		if b < 0.0:
			# Blinking: 0.14 s closed-ish, then reschedule.
			open = clampf(absf(b + 0.07) / 0.07, 0.08, 1.0)
			if b < -0.14:
				b = randf_range(2.0, 6.0)
		_eye_blink[i] = b
		var sz := 1.0 + eye_flare * 0.35
		_eyes[i].scale = Vector3(sz, sz * open, sz)


func _update_halos() -> void:
	for i in _halos.size():
		var k := _halo_scale[i] * (1.0 + 0.03 * sin(t * 2.2 + float(i)) + eye_flare * 0.08)
		_halos[i].scale = Vector3.ONE * k


## Scales halo `index` (e.g. to blaze during a wind-up). 1 = rest.
func set_halo_scale(index: int, k: float) -> void:
	if index >= 0 and index < _halo_scale.size():
		_halo_scale[index] = k


## Smoothly approaches `target` (frame-rate independent).
static func damp(from: float, target: float, rate: float, delta: float) -> float:
	return lerpf(from, target, 1.0 - exp(-rate * delta))


## Sets the white glow (shader "flash") on one lit mesh: telegraphs, hot blades.
static func glow(mesh: GeometryInstance3D, amount: float) -> void:
	mesh.set_instance_shader_parameter(&"flash", clampf(amount, 0.0, 1.0))


# ---------------------------------------------------------------- death effects

## Death: the angel comes apart in light. Everything is spawned into Game.world, so it is safe
## to call right before the enemy is freed.
func death_burst(at: Vector3, s: float, elite: bool) -> void:
	# Perf budget: an AoE can kill dozens in one frame, and every burst spawns nodes + tweens.
	# Past DEATH_FX_PER_FRAME full bursts in a frame (elites always get one), the rest only get the
	# flash and a couple of motes; corpses have their own per-frame / concurrent caps.
	var full := elite or Perf.budget(&"death_fx", DEATH_FX_PER_FRAME)
	if corpse_on_death and (elite or full):
		# Faction death variety for code-built models (DeathFx), else the model's own corpse.
		if not DeathFx.try_play(self, death_variant, last_hit_from, elite):
			spawn_corpse()
	light_flash(at, (1.7 if elite else 0.85) * s, light_color, elite)
	# Perf: elites used to triple every count (~70 nodes + tweens in one frame, 4-8 ms). Now x2,
	# capped, and the feathers / debris start on the next frame so the spike is split.
	spawn_motes(at, mini(mote_count * 2, ELITE_MOTES) if elite else (mote_count if full else mini(mote_count, 2)),
			s, light_color)
	if not full:
		return
	var feathers := mini(feather_count * 2, ELITE_FEATHERS) if elite else feather_count
	var bits := 10 if elite else randi_range(3, 5)
	# Static Callable: the model is usually freed before the next frame.
	var rest := EnemyModel._burst_bits.bind(at, s, feathers, feather_color, debris.duplicate(), debris_color, bits)
	if elite:
		shockwave(Vector3(at.x, 0.06, at.z), 3.2 * s, light_color)
		# QA: a fresh timer per burst; two elites dying in the same frame with identical bound args
		# made process_frame.connect() fail with "already connected" (roster_check).
		(Engine.get_main_loop() as SceneTree).create_timer(0.0, false).timeout.connect(rest)
	else:
		rest.call()


static func _burst_bits(at: Vector3, s: float, feathers: int, fcol: Color, deb: Array[StringName],
		dcol: Color, bits: int) -> void:
	if feathers > 0:
		spawn_feathers(at, feathers, s, fcol)
	if not deb.is_empty():
		spawn_debris(at, deb, dcol, bits, s)


## Blender models: a copy of the model at its current pose plays "death" in Game.world, burning
## white (hit-flash ramp) and shrinking away. Safe to call right before the enemy is freed.
func spawn_corpse() -> void:
	if glb == null or Game.world == null or not is_inside_tree() or not glb.has_anim(&"death"):
		return
	# Perf caps (see MAX_CORPSES): skipping a corpse just leaves the light burst.
	if _corpses_alive >= MAX_CORPSES or not Perf.budget(&"corpse", CORPSES_PER_FRAME):
		return
	var xf := glb.global_transform
	var c := _pooled_corpse(glb_path)
	if c == null:
		c = GlbModel.create(glb_path)
		if c.anim_player == null:
			c.free()
			return
		c.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		Game.spawn(c, xf.origin)
		Art.no_shadows(c)
		# Freed mid-animation (the run ended): give its slot back.
		c.tree_exiting.connect(func() -> void:
			if c.visible:
				_corpses_alive = maxi(_corpses_alive - 1, 0))
	c.global_transform = xf
	c.set_flash(0.0)
	c.play(&"death", 0.0, 1.0, true)
	_corpses_alive += 1
	var length := maxf(corpse_life(), 0.3)
	var base := c.scale
	var tw := c.create_tween()
	var delay := length * clampf(corpse_flash_delay, 0.0, 0.9)
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_method(c.set_flash, 0.0, 0.85, maxf((length - delay) * 0.7, 0.05))
	# characters-polish: when the clip has played out, the corpse shatters into light (DeathFx
	# snapshot) and goes back to the pool; past the perf caps it shrinks / sinks as before.
	tw.tween_interval(maxf((length - delay) * 0.3 - 0.05, 0.0))
	tw.tween_callback(_finish_corpse.bind(c, glb_path, corpse_shrink, base, light_color, body_scale,
		corpse_flash_delay > 0.0))


static func _finish_corpse(c: GlbModel, path: String, shrink: bool, base: Vector3, color: Color, s: float,
		big: bool) -> void:
	if not is_instance_valid(c):
		return
	if DeathFx.shatter_snapshot(c, color, s, big):
		_release_corpse(c, path)
		return
	var tw := c.create_tween()
	if shrink:
		tw.tween_property(c, "scale", base * 0.02, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	else:
		# Keep the full size: sink into the floor (and burn out).
		var sink := c.position - Vector3(0.0, 1.8 * base.y, 0.0)
		tw.tween_property(c, "position", sink, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_release_corpse.bind(c, path))


## Corpses alive right now (perf overlay).
static func corpses_alive() -> int:
	return _corpses_alive


## Perf: finished corpses are hidden and reused (instancing + converting a Blender model per death
## cost 0.5-1.3 ms). They live in Game.world, so the pool empties itself when the run ends.
static func _pooled_corpse(path: String) -> GlbModel:
	var pool: Array = _corpse_pool.get(path, [])
	while not pool.is_empty():
		# QA: pooled corpses are freed with Game.world when a run ends; check before the typed assign.
		var v: Variant = pool.pop_back()
		if not is_instance_valid(v):
			continue
		var c: GlbModel = v
		if c.is_inside_tree() and c.get_parent() == Game.world:
			c.visible = true
			return c
	return null


static func _release_corpse(c: GlbModel, path: String) -> void:
	_corpses_alive = maxi(_corpses_alive - 1, 0)
	if not is_instance_valid(c):
		return
	c.visible = false
	var pool: Array = _corpse_pool.get_or_add(path, [])
	if pool.size() >= CORPSE_POOL_PER_MODEL or c.get_parent() != Game.world:
		c.queue_free()
		return
	pool.append(c)


## Seconds the death copy lives: corpse_time, or (when < 0) the "death" clip + corpse_linger.
func corpse_life() -> float:
	if corpse_time >= 0.0:
		return corpse_time
	var length := _anim_length(&"death")
	return (length if length > 0.0 else 0.8) + corpse_linger


# ---------------------------------------------------------------- shared FX (forwarders)
# The static light / mote / feather / debris / shockwave / dust helpers live in AngelDeathFX
# (angel_death_fx.gd). These forwarders keep `EnemyModel.light_flash(...)` etc. working.

## See AngelDeathFX.light_flash().
static func light_flash(at: Vector3, radius: float, color: Color = Art.HOLY, strong: bool = false) -> void:
	AngelDeathFX.light_flash(at, radius, color, strong)


## See AngelDeathFX.spawn_motes().
static func spawn_motes(at: Vector3, count: int, s: float = 1.0, color: Color = Art.HOLY) -> void:
	AngelDeathFX.spawn_motes(at, count, s, color)


## See AngelDeathFX.spawn_feathers().
static func spawn_feathers(at: Vector3, count: int, s: float = 1.0, color: Color = Art.HOLY_WHITE) -> void:
	AngelDeathFX.spawn_feathers(at, count, s, color)


## See AngelDeathFX.spawn_debris().
static func spawn_debris(at: Vector3, kinds: Array[StringName], color: Color, count: int, s: float = 1.0) -> void:
	AngelDeathFX.spawn_debris(at, kinds, color, count, s)


## See AngelDeathFX.shockwave().
static func shockwave(at: Vector3, radius: float, color: Color = Art.HOLY, time: float = 0.45) -> void:
	AngelDeathFX.shockwave(at, radius, color, time)


## See AngelDeathFX.poof().
static func poof(at: Vector3, color_a: Color, color_b: Color, count: int = 6, radius: float = 0.45,
		spread: float = 0.5) -> void:
	AngelDeathFX.poof(at, color_a, color_b, count, radius, spread)
