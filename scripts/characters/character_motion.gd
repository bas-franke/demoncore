class_name CharacterMotion
extends Node
## Procedural secondary motion layered ON TOP of a Blender node-rig's baked animation
## (GlbModel). The Blender clips can't know how the character actually moves in the game, so this
## adds the parts that react to it:
##   - body lean: the spine pitches into acceleration / speed and banks into turns,
##   - wing physics: wings drag back when the body surges forward, flare on hits and attacks,
##     swing out on turns; outer links lag their parent (whip),
##   - dangles (capes, robes, chains, hair, tabards...): pendulum springs driven by inertia and
##     air drag, each link lagging the one above it,
##   - hit flinch: a directional impulse into every spring, plus a squash on `squash_pivot`.
##
##   var motion := CharacterMotion.attach(glb, frame_node, lean_pivot)
##   motion.hit(from_dir_world, 1.0)    # flinch away from from_dir
##   motion.kick(0.8)                   # attack flourish: wings flare, a small stretch
##   motion.weight = 0.0                # fade it out (deaths)
##
## How it layers: after the AnimationPlayer writes its pose (AnimationMixer.mixer_applied) every
## affected joint gets an extra rotation pre-multiplied in its parent space, so it rotates about its
## own origin and its children follow. Every Blender clip keys every joint, so the next frame
## overwrites the offset again (nothing accumulates); joints a clip leaves alone are restored from
## the pose we saw before offsetting (see _base_basis).
##
## Joints are found by name (sb.py rigs): wing chains ("wing*"), dangle chains (FAMILIES below),
## and the lean joint ("spine", else "chest" / "body" / "core" / "hips"). All axes are computed in
## world space from `frame` (the character's facing node: forward -Z, up +Y), so it works for any
## rig orientation.

## Name prefixes of dangling chains. A chain is consecutive joints of one family
## (name without its trailing link index), e.g. robe3_0 > robe3_1 > robe3_2.
const FAMILIES := [
	"robe", "coat", "cape", "cloak", "mantle", "veil", "hair", "lock_", "chain", "hookchain",
	"wristchain", "keychain", "beltchain", "tabard", "loin", "stole", "ribbon", "sleeve", "talis",
	"tal_", "charm", "pennant", "lantern", "strip",
]
const LEAN_JOINTS := ["spine", "chest", "torso", "body", "core", "hips"]
## Spring integration step (s). Large frames are substepped so stiff springs stay stable.
const STEP := 1.0 / 90.0

## 0..1 overall strength (fade to 0 for deaths / cutscenes).
var weight := 1.0
## Character facing frame (the node whose -Z is "forward"). Velocity is measured from it.
var frame: Node3D
## Optional node scaled for squash & stretch (never a joint the animation writes).
var squash_pivot: Node3D

## ---- tuning (radians per m/s or per m/s^2; scale them per character)
## Forward pitch of the spine per m/s^2 of forward acceleration, and per m/s of speed.
var lean_accel := 0.022
var lean_speed := 0.018
var lean_max := 0.32
## Spine roll per (rad/s of turning * m/s of speed).
var bank := 0.02
var bank_max := 0.22
## Wing sweep-back per m/s^2 of forward acceleration / per m/s of speed; flare on turns.
var wing_accel := 0.05
var wing_speed := 0.035
var wing_turn := 0.06
var wing_max := 0.7
## Dangle swing per m/s^2 (inertia) and per m/s (air drag), and the max swing.
var dangle_accel := 0.05
var dangle_drag := 0.045
var dangle_max := 0.6
## Spring stiffness (1/s^2) and damping (1/s) of the lean, wing and dangle springs.
var lean_k := 120.0
var lean_c := 14.0
var wing_k := 70.0
var wing_c := 6.5
var dangle_k := 55.0
var dangle_c := 5.0
## Insectile character (0 = off): sharp random twitches of the spine, wings and dangles every
## ~twitch_interval s (x0.4-1.4), stronger while moving.
var twitch := 0.0
var twitch_interval := 0.55
## Wing buzz: a fast flutter of the wings' lift (rad amplitude, Hz; 0 = off), louder while moving.
var buzz_amp := 0.0
var buzz_hz := 19.0
## Asymmetric wings (e.g. one burned): the "odd" wing chain is on the character's right (+1) or left
## (-1) side; multipliers for its stiffness and motion amplitude, and its own extra twitch strength
## (0 = none).
var wing_odd_side := -1.0
var wing_odd_k := 1.0
var wing_odd_amp := 1.0
var wing_odd_twitch := 0.0
var _twitch_t := 0.3
var _left_twitch_t := 0.2
var _buzz_t := 0.0

var _anim: AnimationMixer
var _model_root: Node3D

# Lean: one joint, 2D spring (x = pitch forward, y = roll toward the character's right).
var _lean_joint: Node3D
var _lean := Vector2.ZERO
var _lean_v := Vector2.ZERO

# Wings: per link [joint, side (+1 = character's right), depth, out_local (Vector3, root frame)].
var _wings: Array = []
# Per wing link spring: x = sweep back, y = lift up.
var _wing_s: PackedVector2Array = PackedVector2Array()
var _wing_v: PackedVector2Array = PackedVector2Array()

# Dangles: per link [joint, depth, parent link index or -1].
var _dangles: Array = []
# Per link spring: tip displacement direction * angle, in the root frame's XZ plane.
var _dangle_s: PackedVector2Array = PackedVector2Array()
var _dangle_v: PackedVector2Array = PackedVector2Array()

var _squash := 0.0
var _squash_v := 0.0
var _squash_rest := Vector3.ONE

# Motion measurement (root frame).
var _last_pos := Vector3.ZERO
var _last_yaw := 0.0
var _vel := Vector3.ZERO
var _acc := Vector3.ZERO
var _yaw_rate := 0.0
var _has_last := false
var _accum := 0.0
var _discovered := false

var _joints: Array[Node3D] = []
var _parents: Array[Node3D] = []
# Per joint index: the basis we wrote last, the clip basis it was built on, and whether either
# is valid (see _base_basis). Parallel arrays: no per-frame allocations.
var _w_out: Array[Basis] = []
var _w_base: Array[Basis] = []
var _w_has := PackedByteArray()


## Creates the layer for `model` (a GlbModel), measuring motion from `frame_node`.
## `pivot` (optional) gets the squash & stretch. `mixer`: the AnimationMixer that actually poses
## the rig when it isn't the model's AnimationPlayer (e.g. an AnimationTree, bosses). Returns null
## if the model has no animation.
static func attach(model: GlbModel, frame_node: Node3D, pivot: Node3D = null,
		mixer: AnimationMixer = null) -> CharacterMotion:
	if model == null or model.scene_root == null or (model.anim_player == null and mixer == null):
		return null
	var m := CharacterMotion.new()
	m.name = "CharacterMotion"
	m.frame = frame_node
	m.squash_pivot = pivot
	m._model_root = model.scene_root
	m._anim = mixer if mixer else model.anim_player
	model.add_child(m)
	# Joints are discovered on the first applied frame, once the model is in the tree (wing
	# directions are measured in world space).
	m._anim.mixer_applied.connect(m._on_mixer_applied)
	return m


## Number of joints driven (debug / tests).
func joint_count() -> int:
	return _wings.size() + _dangles.size() + (1 if _lean_joint else 0)


## Directional flinch. `from_dir`: world direction the blow came FROM (zero = from the front).
func hit(from_dir: Vector3, strength: float = 1.0) -> void:
	var push := _to_local_dir(-from_dir)
	if push.length_squared() < 0.0001:
		push = Vector3(0.0, 0.0, 1.0)  # knocked backwards
	push = push.normalized() * strength
	# Spine snaps away from the blow (pitch back = negative forward lean).
	_lean_v += Vector2(push.z * -6.0, push.x * 4.0)
	for i in _wing_v.size():
		# The body is shoved along `push`; the wings lag behind it and flare up.
		_wing_v[i] += Vector2(-push.z * 3.0, 5.0 + float(_wings[i][2]) * 2.0) * strength
	for i in _dangle_v.size():
		_dangle_v[i] -= Vector2(push.x, push.z) * 5.0
	_squash_v -= 2.2 * strength


## Attack flourish: wings flare, a small stretch.
func kick(strength: float = 1.0) -> void:
	for i in _wing_v.size():
		_wing_v[i] += Vector2(-2.0, 6.0) * strength
	_squash_v += 1.6 * strength


## Squash (negative) / stretch (positive) impulse on squash_pivot.
func squash(amount: float) -> void:
	_squash_v += amount


# ---------------------------------------------------------------- discovery

func _discover() -> void:
	for jn: String in LEAN_JOINTS:
		_lean_joint = _model_root.find_child(jn, true, false) as Node3D
		if _lean_joint:
			break
	_scan(_model_root)
	# Flat joint / parent lists in _apply order: lean joint, wings, dangles.
	if _lean_joint:
		_joints.append(_lean_joint)
	for wl: Array in _wings:
		_joints.append(wl[0])
	for d: Array in _dangles:
		_joints.append(d[0])
	for j in _joints:
		_parents.append(j.get_parent() as Node3D)
	_w_out.resize(_joints.size())
	_w_base.resize(_joints.size())
	_w_has.resize(_joints.size())
	_wing_s.resize(_wings.size())
	_wing_v.resize(_wings.size())
	_dangle_s.resize(_dangles.size())
	_dangle_v.resize(_dangles.size())
	if squash_pivot:
		_squash_rest = squash_pivot.scale


func _scan(node: Node) -> void:
	for c in node.get_children():
		var j := c as Node3D
		if j == null or j is MeshInstance3D or j is Light3D or j is GPUParticles3D or j is CPUParticles3D:
			continue
		var nm := String(j.name)
		if nm.begins_with("wing"):
			_add_wing(j)
		else:
			var fam := _family(nm)
			if fam != "":
				_add_dangle(j, fam)
		_scan(j)


## The chain family of a joint name ("robe3_1" -> "robe3_"), or "" if it doesn't dangle.
static func _family(nm: String) -> String:
	var lower := nm.to_lower()
	for f: String in FAMILIES:
		if lower.begins_with(f):
			var i := lower.length()
			while i > 0 and lower[i - 1] >= "0" and lower[i - 1] <= "9":
				i -= 1
			return lower.substr(0, i)
	return ""


func _add_wing(j: Node3D) -> void:
	var depth := 0
	var p := j.get_parent() as Node3D
	while p and String(p.name).begins_with("wing"):
		depth += 1
		p = p.get_parent() as Node3D
	# Outward direction: from the wing root toward the farthest node of its subtree.
	var tip := _farthest(j, j.global_position)
	var root_inv := frame.global_basis.orthonormalized().inverse() if frame else Basis()
	var out := root_inv * (tip - j.global_position)
	out.y = 0.0
	var side_x := (root_inv * (j.global_position - frame.global_position)).x if frame else 0.0
	if out.length_squared() < 0.0001:
		out = Vector3(signf(side_x) if side_x != 0.0 else 1.0, 0.0, 0.0)
	var side := 1.0 if (out.x if absf(out.x) > 0.01 else side_x) >= 0.0 else -1.0
	_wings.append([j, side, depth, out.normalized()])


func _add_dangle(j: Node3D, fam: String) -> void:
	var parent := j.get_parent() as Node3D
	var parent_idx := -1
	var depth := 0
	if parent and _family(String(parent.name)) == fam:
		for i in _dangles.size():
			if _dangles[i][0] == parent:
				parent_idx = i
				depth = int(_dangles[i][1]) + 1
				break
	_dangles.append([j, depth, parent_idx])


func _farthest(node: Node3D, from: Vector3) -> Vector3:
	var best := node.global_position
	var best_d := 0.0
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var n3 := n as Node3D
		if n3:
			var d := n3.global_position.distance_squared_to(from)
			if n3 is MeshInstance3D:
				var mi := n3 as MeshInstance3D
				var c := mi.global_transform * mi.get_aabb().get_center()
				d = c.distance_squared_to(from)
				if d > best_d:
					best_d = d
					best = c
			elif d > best_d:
				best_d = d
				best = n3.global_position
		for c in n.get_children():
			stack.append(c)
	return best


# ---------------------------------------------------------------- per frame

func _on_mixer_applied() -> void:
	if frame == null or not is_instance_valid(frame) or not frame.is_inside_tree():
		return
	if not _discovered:
		_discovered = true
		_discover()
	# Mixers advanced by hand from physics code (bosses' AnimationTrees) apply during a physics tick.
	var delta := get_physics_process_delta_time() if Engine.is_in_physics_frame() else get_process_delta_time()
	if delta <= 0.0:
		return
	_accum = minf(_accum + delta, 0.1)
	while _accum >= STEP:
		_accum -= STEP
		_integrate(STEP)
	_apply()


# Motion is measured per physics tick: with physics interpolation the frame's global transform
# only changes on ticks, so measuring per rendered frame would read 0 / huge velocities.
func _physics_process(delta: float) -> void:
	if frame and is_instance_valid(frame) and frame.is_inside_tree() and delta > 0.0:
		_measure(delta)


func _measure(delta: float) -> void:
	var pos := frame.global_position
	var yaw := frame.global_basis.get_euler().y
	if not _has_last:
		_has_last = true
		_last_pos = pos
		_last_yaw = yaw
		return
	var inv := frame.global_basis.orthonormalized().inverse()
	var v := inv * ((pos - _last_pos) / delta)
	# Teleports / respawns: ignore absurd jumps.
	if v.length() > 40.0:
		v = _vel
	var a := (v - _vel) / delta
	_vel = _vel.lerp(v, 1.0 - exp(-25.0 * delta))
	_acc = _acc.lerp(a.limit_length(60.0), 1.0 - exp(-12.0 * delta))
	_yaw_rate = lerpf(_yaw_rate, wrapf(yaw - _last_yaw, -PI, PI) / delta, 1.0 - exp(-10.0 * delta))
	_last_pos = pos
	_last_yaw = yaw


func _integrate(h: float) -> void:
	var speed := Vector2(_vel.x, _vel.z).length()
	var fwd_acc := -_acc.z
	var fwd_speed := -_vel.z
	# Lean: pitch into acceleration and speed, bank into turns (roll toward the turn's inside).
	var lt := Vector2(
		clampf(fwd_acc * lean_accel + maxf(fwd_speed, 0.0) * lean_speed, -lean_max, lean_max),
		clampf(-_yaw_rate * speed * bank, -bank_max, bank_max))
	_lean_v += ((lt - _lean) * lean_k - _lean_v * lean_c) * h
	_lean += _lean_v * h

	# Wings: sweep back with forward surge and speed, the outer wing flares on turns.
	for i in _wings.size():
		var w: Array = _wings[i]
		var side: float = w[1]
		var depth: int = w[2]
		var target := Vector2(
			fwd_acc * wing_accel + speed * wing_speed + _yaw_rate * side * wing_turn,
			-speed * wing_speed * 0.4)
		# Outer links follow (and exaggerate) the root link: the whip.
		if depth > 0 and i > 0 and _wings[i - 1][2] == depth - 1:
			target = _wing_s[i - 1] * 0.6
		target = target.limit_length(wing_max)
		var k := wing_k * (1.0 - 0.18 * float(depth))
		if side == wing_odd_side:
			target *= wing_odd_amp
			k *= wing_odd_k
		_wing_v[i] += ((target - _wing_s[i]) * k - _wing_v[i] * wing_c) * h
		_wing_s[i] += _wing_v[i] * h

	# Dangles: inertia (-acceleration) + air drag (-velocity), links lag their parent.
	var drive := Vector2(-_acc.x, -_acc.z) * dangle_accel + Vector2(-_vel.x, -_vel.z) * dangle_drag
	for i in _dangles.size():
		var d: Array = _dangles[i]
		var pi: int = d[2]
		var target := drive
		if pi >= 0:
			target = _dangle_s[pi] * 0.5
		target = target.limit_length(dangle_max)
		_dangle_v[i] += ((target - _dangle_s[i]) * dangle_k - _dangle_v[i] * dangle_c) * h
		_dangle_s[i] += _dangle_v[i] * h

	_squash_v += (-_squash * 260.0 - _squash_v * 16.0) * h
	_squash += _squash_v * h

	_buzz_t += h
	if wing_odd_twitch > 0.0:
		_left_twitch_t -= h
		if _left_twitch_t <= 0.0:
			_left_twitch_t = randf_range(0.25, 0.9)
			for i in _wing_v.size():
				if float(_wings[i][1]) == wing_odd_side:
					_wing_v[i] += Vector2(randf_range(-1.0, 1.0), randf_range(-0.6, 1.0)) * 7.0 * wing_odd_twitch
	if twitch > 0.0:
		_twitch_t -= h
		if _twitch_t <= 0.0:
			_twitch_t = twitch_interval * randf_range(0.4, 1.4)
			var k := twitch * (0.6 + 0.8 * minf(speed / 4.0, 1.0))
			_lean_v += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 7.0 * k
			for i in _wing_v.size():
				_wing_v[i] += Vector2(randf_range(-1.0, 1.0), randf_range(-0.5, 1.0)) * 6.0 * k
			for i in _dangle_v.size():
				_dangle_v[i] += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 4.0 * k


func _apply() -> void:
	var w := clampf(weight, 0.0, 1.0)
	var rb := frame.global_basis.orthonormalized()
	var up := rb.y
	var fwd := -rb.z
	var right := rb.x
	# 1) World-space rotation per joint (null = none this frame).
	var rots: Array = []
	rots.resize(_joints.size())
	var k := 0
	if _lean_joint:
		if w > 0.0 and _lean.length_squared() > 0.0000002:
			# Pitch: rotate "up" toward "forward"; roll: rotate "up" toward "right".
			rots[k] = Basis(up.cross(fwd).normalized(), _lean.x * w) * Basis(up.cross(right).normalized(), _lean.y * w)
		k += 1
	for i in _wings.size():
		var s := _wing_s[i] * w
		if buzz_amp > 0.0:
			# The flutter is added after the springs (they would filter it out).
			var speed := Vector2(_vel.x, _vel.z).length()
			s.y += sin(_buzz_t * TAU * buzz_hz + float(i) * 1.7) * buzz_amp * w \
				* (0.45 + 0.55 * minf(speed / 4.0, 1.0)) * (1.0 + 0.5 * float(_wings[i][2]))
		if s.length_squared() > 0.0000002:
			var out: Vector3 = rb * (_wings[i][3] as Vector3)
			rots[k] = Basis(out.cross(-fwd).normalized(), s.x) * Basis(out.cross(up).normalized(), s.y)
		k += 1
	for i in _dangles.size():
		var s := _dangle_s[i] * w
		var ang := s.length()
		if ang > 0.0005:
			var dir := (rb * Vector3(s.x, 0.0, s.y)).normalized()
			rots[k] = Basis((-up).cross(dir).normalized(), ang)
		k += 1
	# 2) Read every parent's global basis BEFORE writing anything: each read is then served from
	# the transform cache (writing first would re-dirty the chain and make every read walk up to
	# the root). Using the parent's pre-offset basis only tilts a child's axis by its parent's
	# (small) offset.
	var pbs: Array = []
	pbs.resize(_joints.size())
	for i in _joints.size():
		if rots[i] != null:
			pbs[i] = _parents[i].global_basis.orthonormalized()
	# 3) Write.
	for i in _joints.size():
		var j := _joints[i]
		if rots[i] == null:
			# No offset: put back the clip pose if a clip didn't rewrite our last offset.
			if _w_has[i]:
				j.basis = _base_basis(i)
				_w_has[i] = 0
			continue
		var base := _base_basis(i)
		var pb: Basis = pbs[i]
		var out := pb.inverse() * (rots[i] as Basis) * pb * base
		j.basis = out
		_w_out[i] = out
		_w_base[i] = base
		_w_has[i] = 1
	if squash_pivot:
		var q := clampf(_squash * w, -0.25, 0.25)
		squash_pivot.scale = _squash_rest * Vector3(1.0 - q * 0.5, 1.0 + q, 1.0 - q * 0.5)


## Joint `i`'s basis as the animation left it this frame. If the animation didn't write the joint
## since our last offset (the basis is still exactly ours), use the base we saw before.
func _base_basis(i: int) -> Basis:
	var cur := _joints[i].basis
	if _w_has[i] and cur.is_equal_approx(_w_out[i]):
		return _w_base[i]
	return cur


func _to_local_dir(world_dir: Vector3) -> Vector3:
	if frame == null:
		return world_dir
	var v := frame.global_basis.orthonormalized().inverse() * world_dir
	v.y = 0.0
	return v
