class_name ProcModel
extends EnemyModel
## Base for the code-built (procedural) characters of the roster: holy enemies, demonic allies
## and Basecamp NPCs (see docs/team/characters-new.md). Geometry comes from Art primitives,
## animation is procedural: a walk / gallop phase driven by the real ground speed, smoothed
## state weights (windup_w, strike_w, recover_w) and per-model pose() code.
##
## Subclass recipe:
##   func build() -> void:
##       body = Art.pivot(self, Vector3(0, 0.6, 0))            # bobbing torso root
##       var leg := limb_pivot(self, Vector3(0.1, 0.6, 0))      # hip pivot, mesh hangs down -Y
##       add_leg(leg, 0.0)                                       # swung by the walk phase
##       ...
##       finish()                                                # merge meshes (see bake below)
##   func pose(delta) -> void: rotate your pivots from walk, move_w, windup_w, strike_w, t...
##
## Rendering: finish() merges every mesh under each animated pivot into one ArrayMesh per
## pivot (one surface per material) and caches it per script + pivot path, so crowds of
## procedural enemies share their mesh resources and cost a handful of draw calls each.
## Pivots that move must be registered (add_leg / add_arm / animated(), plus the base class
## wings, eyes and halos) or they get merged into their parent's mesh. build() must therefore
## be deterministic (no randf() in geometry); randomise in pose() instead.
##
## Standalone use (Basecamp NPCs, allies outside an Enemy, menus): set `autoplay = true`
## before adding to the tree, or leave it unset - a model whose parent is not an Enemy and not a
## bestiary preview drives itself (idle loop + talk() gestures).

## Walk cycle: phase in radians (advances one TAU per stride).
var walk := 0.0
## Ground distance (m at model scale 1) covered by one full stride cycle.
var stride := 1.3
## Smoothed 0..1 weights: moving, winding up, striking, recovering.
var move_w := 0.0
var windup_w := 0.0
var strike_w := 0.0
var recover_w := 0.0
## 0..1 envelope of a talk() / gesture() (NPCs, idle flourishes), decays.
var gesture_w := 0.0
## Which gesture is playing (subclass-defined, 0 = default).
var gesture_id := 0
## Bob / lean root, usually the hips or torso (optional).
var body: Node3D
## Self-drive animate() from _process (NPCs). null = decide automatically in _ready.
var autoplay: Variant = null
## Seconds between automatic idle gestures when autoplaying (0 = never).
var idle_gesture_every := 0.0

var _legs: Array[Node3D] = []
var _leg_phase: Array[float] = []
var _leg_amp: Array[float] = []
## Hip-to-sole length per leg (0 = don't plant: the leg may hang through the floor).
var _leg_len: Array[float] = []
## Keep feet out of the floor: a leg whose hip has sunk below its reach (crouches, bobs, wind-ups)
## is shortened along its own axis so the sole stays at ground level instead of dipping into it.
var plant_feet := true
var _arms: Array[Node3D] = []
var _arm_phase: Array[float] = []
var _arm_amp: Array[float] = []
## Extra pivots that animate (their meshes are merged separately).
var _animated: Array[Node3D] = []
## Meshes that are changed at runtime (glow, scale, visibility): never merged.
var _keep := {}
var _gesture_t := 0.0
var _gesture_len := 1.0
var _idle_gesture_cd := 0.0

## perf round 2: model scripts (file stems) whose parts are baked into 1-2 skinned meshes after
## finish() (SkinBake). These are the common horde types; the rest keep merged per-pivot meshes.
## A model can force it either way by setting `skin_bake` in build() before finish().
const SKIN_BAKE_TYPES := ["cherub", "ophan", "holy_knight", "zealot", "martyr", "light_elemental",
		"monk", "censer_nun", "villager", "flagellant", "holy_water_friar"]
var skin_bake: Variant = null
## Global switch for the type list above (A/B: --bench-exp=noskinbake).
static var skin_bake_enabled := true
var _skin_rig: SkinBake.Rig

## Cache: "script|pivot path|kind" -> [ArrayMesh, Array[Material]].
static var _baked := {}


func _ready() -> void:
	wrap_pose_pivot = true  # characters-polish: flinch / squash / telegraph pivot (EnemyModel)
	super._ready()
	if autoplay == null:
		var p := get_parent()
		# Enemy drives its model; the bestiary drives previews (they sit under a SubViewport).
		autoplay = not (p is Enemy) and not _under_subviewport()
	set_process(bool(autoplay))
	_idle_gesture_cd = randf_range(1.0, maxf(idle_gesture_every, 1.0))


func _under_subviewport() -> bool:
	var n := get_parent()
	while n:
		if n is SubViewport:
			return true
		n = n.get_parent()
	return false


func _process(delta: float) -> void:
	if idle_gesture_every > 0.0:
		_idle_gesture_cd -= delta
		if _idle_gesture_cd <= 0.0:
			_idle_gesture_cd = idle_gesture_every * randf_range(0.7, 1.3)
			gesture(randi() % 2)
	animate(delta, 0.0, State.MOVING)


## The Enemy this model belongs to (null in previews, hubs and cutscenes). For model-side
## mechanics (martyr burst, flagellant rage, hymn buffs).
func host() -> Enemy:
	return get_parent() as Enemy


## Enemies (group "enemies", alive, not this model's own host) within `radius` of `at`.
func enemies_near(at: Vector3, radius: float) -> Array[Enemy]:
	var out: Array[Enemy] = []
	if not is_inside_tree():
		return out
	var me := host()
	# perf: grid lookup instead of scanning every enemy (docs/team/performance.md).
	var near: Array[Enemy] = []
	Crowd.query(at, radius, near)
	for e in near:
		if e != me:
			out.append(e)
	return out


## Spawns `count` more enemies of the host's own type around it (flocks, pairs), each tagged with
## meta `tag` so they don't spawn companions of their own. Call once (e.g. from pose() behind a
## flag); does nothing for enemies that are already tagged or have no host.
func spawn_companions(count: int, tag: StringName, radius: float = 1.6) -> void:
	var e := host()
	if e == null or e.data == null or e.has_meta(tag) or Game.world == null:
		return
	e.set_meta(tag, true)
	for i in count:
		var a := TAU * float(i) / float(maxi(count, 1)) + randf() * 0.5
		var c := (load("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate() as Enemy
		c.setup(e.data, e.max_hp / maxf(e.data.max_hp, 0.01))
		c.set_meta(tag, true)
		Game.spawn.call_deferred(c, e.global_position + Vector3(cos(a), 0.0, sin(a)) * radius)


## Override for death mechanics that must always happen (bursts, rises, sacrifices): Enemy.die()
## calls it once, before the death FX (model.death_burst / characters-polish faction deaths), so
## nothing can skip it. `enemy` is still valid and is_dying is already true.
func on_host_died(_enemy: Enemy) -> void:
	pass


## Helper for `ragdoll_limbs()` overrides (characters-polish DeathFx flops what a model returns
## there): the walk legs and arms plus `extra` pivots, nulls and duplicates skipped. Models that
## don't override ragdoll_limbs() keep DeathFx's default (legs / arms / every animated pivot).
func limbs_with(extra: Array = []) -> Array:
	var out: Array = []
	for l in _legs:
		out.append(l)
	for l in _arms:
		out.append(l)
	for l in extra:
		if l is Node3D and not (l in out):
			out.append(l)
	return out


## Plays an NPC gesture (`id` is model-specific: 0 = talk / beckon, 1 = flourish).
func gesture(id: int = 0, length: float = 1.4) -> void:
	gesture_id = id
	_gesture_len = maxf(length, 0.1)
	_gesture_t = _gesture_len


## Shopkeepers: call when the player opens / talks at the shop.
func talk() -> void:
	gesture(0)


func animate(delta: float, move_ratio: float, state: int) -> void:
	super.animate(delta, move_ratio, state)
	var spd := ground_speed if ground_speed >= 0.0 else move_ratio * 3.0
	walk += spd / maxf(stride * maxf(body_scale, 0.01), 0.05) * TAU * delta
	move_w = damp(move_w, clampf(move_ratio * 1.4, 0.0, 1.0), 8.0, delta)
	windup_w = damp(windup_w, 1.0 if state == State.WINDUP else 0.0, 12.0, delta)
	strike_w = damp(strike_w, 1.0 if state == State.ATTACKING else 0.0, 22.0, delta)
	recover_w = damp(recover_w, 1.0 if state == State.RECOVER else 0.0, 10.0, delta)
	if _gesture_t > 0.0:
		_gesture_t -= delta
		# Ease in over the first 20 %, out over the last 30 %.
		var k := 1.0 - _gesture_t / _gesture_len
		gesture_w = clampf(minf(k / 0.2, (1.0 - k) / 0.3), 0.0, 1.0)
	else:
		gesture_w = 0.0
	for i in _legs.size():
		_legs[i].rotation.x = sin(walk + _leg_phase[i]) * _leg_amp[i] * move_w
	for i in _arms.size():
		_arms[i].rotation.x = sin(walk + _arm_phase[i]) * _arm_amp[i] * move_w
	pose(delta)
	if plant_feet:
		_plant_feet()
	if _skin_rig:
		_skin_rig.update()  # perf round 2: copy the posed pivots into the baked skeleton


## Override: pose the model every frame (after the walk swing has been applied).
func pose(_delta: float) -> void:
	pass


## Shortens legs whose sole would end up below the floor (see plant_feet). Model space is used, so
## the Enemy's scale, hover and the model's yaw don't matter.
func _plant_feet() -> void:
	if not is_inside_tree():
		return
	var inv := global_transform.affine_inverse()
	for i in _legs.size():
		var length := _leg_len[i]
		if length <= 0.0:
			continue
		var l := _legs[i]
		l.scale = Vector3.ONE
		var xf := inv * l.global_transform
		# Vertical reach of the leg in its current swing (its -Y axis, in model space).
		var reach := -(xf.basis * Vector3(0.0, -length, 0.0)).y
		if reach < length * 0.3:
			continue  # folded / lying down: leave it
		var hip_y := xf.origin.y
		if hip_y < reach:
			l.scale = Vector3(1.0, clampf(hip_y / reach, 0.55, 1.0), 1.0)


# ---------------------------------------------------------------- rig helpers

## Registers a pivot that moves on its own (merged into its own mesh by finish()).
func animated(n: Node3D) -> Node3D:
	_animated.append(n)
	return n


## Registers `hip` as a leg swung by the walk cycle (phase offset in radians, amplitude in rad).
func add_leg(hip: Node3D, phase: float, amp: float = 0.55, length: float = 0.0) -> Node3D:
	_legs.append(hip)
	_leg_len.append(length)
	_leg_phase.append(phase)
	_leg_amp.append(amp)
	return animated(hip)


## Registers `shoulder` as an arm counter-swung by the walk cycle. pose() may override it.
func add_arm(shoulder: Node3D, phase: float, amp: float = 0.4) -> Node3D:
	_arms.append(shoulder)
	_arm_phase.append(phase)
	_arm_amp.append(amp)
	return animated(shoulder)


## Excludes a mesh from merging (call for meshes pose() scales, glows or hides). Returns it.
func keep(mi: MeshInstance3D) -> MeshInstance3D:
	_keep[mi] = true
	return mi


## A pivot at `pos` registered as animated.
func limb_pivot(parent: Node3D, pos: Vector3, rot := Vector3.ZERO) -> Node3D:
	return animated(Art.pivot(parent, pos, rot))


## A humanoid leg hanging from a new hip pivot: thigh + shin (`mat`), and a boot (`foot`).
## `length` is hip-to-sole. Returns the (registered) hip pivot.
func leg(parent: Node3D, hip: Vector3, length: float, thick: float, mat: Material,
		foot: Material = null, phase: float = 0.0, amp: float = 0.55) -> Node3D:
	var p := Art.pivot(parent, hip)
	limb(p, Vector3.ZERO, Vector3(0.0, -length * 0.5, 0.02), thick, mat)
	limb(p, Vector3(0.0, -length * 0.5, 0.02), Vector3(0.0, -length * 0.92, 0.0), thick * 0.85, mat)
	Art.part(p, Art.sphere(), mat, Vector3(0.0, -length * 0.5, 0.0), Vector3.ONE * thick * 2.0)
	Art.part(p, Art.box(), foot if foot else mat, Vector3(0.0, -length + thick * 0.45, -thick * 0.6),
			Vector3(thick * 2.0, thick * 0.9, thick * 3.4))
	return add_leg(p, phase, amp, length)


## A humanoid arm hanging from a new shoulder pivot (upper arm, forearm, hand). The returned
## array is [shoulder pivot, hand pivot]; attach weapons to the hand pivot (its -Y is "down the
## arm", -Z forward). `swing` = walk counter-swing amplitude (0 = not swung).
func arm(parent: Node3D, shoulder: Vector3, length: float, thick: float, mat: Material,
		hand_mat: Material = null, phase: float = PI, swing: float = 0.35) -> Array[Node3D]:
	var p := Art.pivot(parent, shoulder)
	Art.part(p, Art.sphere(), mat, Vector3.ZERO, Vector3.ONE * thick * 2.4)
	limb(p, Vector3.ZERO, Vector3(0.0, -length * 0.5, 0.0), thick, mat)
	limb(p, Vector3(0.0, -length * 0.5, 0.0), Vector3(0.0, -length * 0.9, -thick * 0.6), thick * 0.85, mat)
	var hand := Art.pivot(p, Vector3(0.0, -length, -thick * 0.7))
	Art.part(hand, Art.sphere(), hand_mat if hand_mat else mat, Vector3.ZERO, Vector3.ONE * thick * 2.1)
	if swing > 0.0:
		add_arm(p, phase, swing)
	else:
		animated(p)
	return [p, hand]


## Common biped frame: `body` (the hips, bobbed by biped_bob) at `hip_h`, two walking legs and
## a torso pivot on the hips (returned, registered as animated).
func biped(hip_h: float, thick: float, leg_mat: Material, foot_mat: Material = null,
		hip_w: float = 0.1, amp: float = 0.5) -> Node3D:
	body = animated(Art.pivot(self, Vector3(0.0, hip_h, 0.0)))
	for s: float in [-1.0, 1.0]:
		# Legs hang from the hips so they follow bobs and leaps.
		leg(body, Vector3(s * hip_w, 0.0, 0.0), hip_h, thick, leg_mat, foot_mat, 0.0 if s < 0.0 else PI, amp)
	return animated(Art.pivot(body, Vector3(0.0, 0.02, 0.0)))


## Walk bob for biped(): two dips per stride, plus a sink while recovering.
func biped_bob(hip_h: float, amount: float = 0.035) -> void:
	body.position.y = hip_h + (absf(cos(walk)) - 0.6) * amount * move_w - recover_w * hip_h * 0.08


## A four-legged beast leg (upper + lower + hoof / paw) hanging from a new pivot.
func beast_leg(parent: Node3D, hip: Vector3, length: float, thick: float, mat: Material,
		hoof: Material, phase: float, amp: float = 0.6, back: bool = false) -> Node3D:
	var p := Art.pivot(parent, hip)
	# Hind legs kink backwards (hock), forelegs stay straight-ish.
	var knee := Vector3(0.0, -length * 0.5, -thick * 0.8 if back else thick * 0.3)
	limb(p, Vector3.ZERO, knee, thick * 1.25, mat)
	limb(p, knee, Vector3(0.0, -length * 0.93, thick * 0.4 if back else 0.0), thick * 0.75, mat)
	Art.part(p, Art.cylinder(0.45, 0.55), hoof, Vector3(0.0, -length + thick * 0.4, 0.0),
			Vector3(thick * 2.0, thick * 0.8, thick * 2.2))
	return add_leg(p, phase, amp, length)


## Cheap, solid wing pair for big fliers (instead of the base wing_pair's fan of separate
## feathers, which reads as noise from the game camera): each wing is a few overlapping flattened
## shapes - a bony leading edge, a broad covert panel, a long primary blade and a scalloped
## trailing edge - so the silhouette is one clean shape. Same flapping as wing_pair (registered
## in the base wing list: wing_speed / wing_amp / wing_lift / wing_sweep drive it).
## `edge` tints the leading edge and coverts (e.g. gold), `tip` the trailing scallops.
func solid_wing_pair(parent: Node3D, pos: Vector3, span: float, main: Material = null,
		edge: Material = null, tip: Material = null, half_gap: float = 0.08) -> Array[Node3D]:
	if main == null:
		main = Art.mat(Art.HOLY_WHITE.darkened(0.06), 0.7, 0.0, 0.15, true, 0.35, &"feather")
	if edge == null:
		edge = main
	if tip == null:
		tip = main
	var out: Array[Node3D] = []
	for s: float in [-1.0, 1.0]:
		var root := Art.pivot(parent, pos + Vector3(s * half_gap, 0.0, 0.0))
		# Leading edge: a slim bone from shoulder to wrist to tip, raked slightly forward.
		limb(root, Vector3.ZERO, Vector3(s * span * 0.45, span * 0.06, -span * 0.04), span * 0.035, edge)
		limb(root, Vector3(s * span * 0.45, span * 0.06, -span * 0.04), Vector3(s * span * 0.98, span * 0.02, span * 0.08), span * 0.025, edge)
		# Covert panel (inner half) and the long primary blade (outer half), overlapping.
		Art.part(root, Art.sphere(), edge, Vector3(s * span * 0.3, span * 0.01, span * 0.14), Vector3(span * 0.62, span * 0.05, span * 0.36))
		Art.part(root, Art.sphere(), main, Vector3(s * span * 0.38, 0.0, span * 0.26), Vector3(span * 0.78, span * 0.035, span * 0.52))
		Art.part(root, Art.sphere(), main, Vector3(s * span * 0.78, -span * 0.01, span * 0.24), Vector3(span * 0.5, span * 0.03, span * 0.4),
				Vector3(0.0, -s * 0.5, 0.0))
		# Scalloped trailing edge: a few rounded feather tips along the back.
		for k in 4:
			var f := (float(k) + 0.5) / 4.0
			Art.part(root, Art.sphere(), tip, Vector3(s * span * lerpf(0.15, 0.85, f), -span * 0.012, span * lerpf(0.5, 0.42, f)),
					Vector3(span * 0.2, span * 0.025, span * 0.2))
		_wings.append(root)
		_wing_side.append(s)
		out.append(root)
	return out


## Linear blend helper: rotation from `a` to `b` by `w`.
static func mixv(a: Vector3, b: Vector3, w: float) -> Vector3:
	return a.lerp(b, clampf(w, 0.0, 1.0))


## Euler rotation from degrees (pose tables read better in degrees).
static func deg(x: float, y: float = 0.0, z: float = 0.0) -> Vector3:
	return Vector3(deg_to_rad(x), deg_to_rad(y), deg_to_rad(z))


# ---------------------------------------------------------------- death

## Procedural corpse (replaces the base Blender "death" copy): the model itself is lifted out
## of the dying Enemy into Game.world, then topples (or sinks / shrinks, see death_style) while
## burning white. death_style: &"topple" falls backwards, &"sink" drops into the floor (statues,
## golems), &"shrink" collapses in place (small fliers), &"none" vanishes at once.
var death_style := &"topple"
var death_time := 0.7


func spawn_corpse() -> void:
	if death_style == &"none" or Game.world == null or not is_inside_tree():
		return
	var xf := global_transform
	set_process(false)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	get_parent().remove_child(self)
	Game.world.add_child(self)
	global_transform = xf
	Art.no_shadows(self)
	var tw := create_tween()
	tw.tween_method(set_flash, 0.2, 0.9, death_time)
	match death_style:
		&"topple":
			# Fall backwards (tilt about the feet), sink a little at the end.
			tw.parallel().tween_method(_topple, 0.0, 1.0, death_time * 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(self, "position:y", position.y - 0.4 * body_scale, 0.3).set_delay(death_time * 0.7)
		&"sink":
			tw.parallel().tween_property(self, "position:y", position.y - 1.6 * body_scale, death_time) \
					.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_:
			tw.parallel().tween_property(self, "scale", scale * 0.05, death_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)


var _topple_base := Basis()
var _topple_started := false


func _topple(k: float) -> void:
	if not _topple_started:
		_topple_started = true
		_topple_base = basis
	# Rotate about the model's local X axis (feet stay roughly planted).
	basis = _topple_base * Basis(Vector3.RIGHT, k * 1.35)


# ---------------------------------------------------------------- mesh merging

## Call at the end of build(): merges the static meshes under every animated pivot (and the
## model root) into shared, cached ArrayMeshes. Safe to skip (the model just costs more).
func finish() -> void:
	var anim := {}
	for n in _animated:
		anim[n] = true
	for n in _wings:
		anim[n] = true
	for n in _eyes:
		anim[n] = true
	for n in _halos:
		anim[n] = true
	var roots: Array[Node3D] = [self]
	for n in anim.keys():
		roots.append(n)
	var script_path: String = (get_script() as Script).resource_path
	for r in roots:
		_bake_root(r, anim, script_path)
	# perf round 2 (docs/team/performance.md): horde types collapse into 1-2 skinned meshes.
	if skin_bake == null:
		skin_bake = skin_bake_enabled and SKIN_BAKE_TYPES.has(script_path.get_file().get_basename())
	if skin_bake:
		var bones: Array[Node3D] = []
		for n in anim.keys():
			bones.append(n)
		_skin_rig = SkinBake.bake(self, bones, _keep, "%s|%s" % [script_path, bake_variant()])


## Override when one script builds different geometry (exported variants): return a string
## that tells the variants apart, so they don't share a cached merged mesh.
func bake_variant() -> String:
	return ""


func _bake_root(root: Node3D, anim: Dictionary, script_path: String) -> void:
	var found: Array = []  # [MeshInstance3D, Transform3D relative to root]
	_collect(root, anim, Transform3D.IDENTITY, found)
	if found.size() < 2:
		return
	# Key by child *indices*, not names: unnamed pivots get unique auto names ("@Node3D@1234") per
	# instance, so a name path never hit the cache and every spawn re-merged (perf fix).
	var key_base := "%s|%s|%s" % [script_path, bake_variant(), _index_path(root)]
	for kind in ["lit", "glow"]:
		var group: Array = []
		for f in found:
			var mi: MeshInstance3D = f[0]
			var is_glow := mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if is_glow == (kind == "glow"):
				group.append(f)
		if group.size() < 2:
			continue
		var key := "%s|%s|%d" % [key_base, kind, group.size()]
		var entry: Array = _baked.get(key, [])
		if entry.is_empty():
			entry = _merge(group)
			_baked[key] = entry
		var out := MeshInstance3D.new()
		out.mesh = entry[0]
		var mats: Array = entry[1]
		for i in mats.size():
			out.set_surface_override_material(i, mats[i])
		if kind == "glow":
			out.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(out)
		for f in group:
			# Detach now (perf): when the model is built before entering the tree (see
			# EnemyModel.ensure_built) the merged-away parts then never enter it at all.
			var part := f[0] as Node
			part.get_parent().remove_child(part)
			part.queue_free()


## "i/j/k" child-index path from this model down to `n` (stable across instances).
func _index_path(n: Node) -> String:
	var parts := PackedStringArray()
	while n and n != self:
		parts.append(str(n.get_index()))
		n = n.get_parent()
	parts.reverse()
	return "/".join(parts)


func _collect(n: Node, anim: Dictionary, xf: Transform3D, out: Array) -> void:
	for c in n.get_children():
		if anim.has(c) or _keep.has(c):
			continue  # its own bake root / changed at runtime
		var c3 := c as Node3D
		if c3 == null:
			continue
		var cx := xf * c3.transform
		var mi := c3 as MeshInstance3D
		if mi and mi.mesh and mi.material_override and mi.get_child_count() == 0 and mi.visible:
			out.append([mi, cx])
		elif not (c3 is MeshInstance3D):
			_collect(c3, anim, cx, out)


static func _merge(group: Array) -> Array:
	var by_mat := {}
	var order: Array = []
	for f in group:
		var m: Material = (f[0] as MeshInstance3D).material_override
		if not by_mat.has(m):
			by_mat[m] = []
			order.append(m)
		by_mat[m].append(f)
	var mesh := ArrayMesh.new()
	for m in order:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for f in by_mat[m]:
			var src: Mesh = (f[0] as MeshInstance3D).mesh
			for s in src.get_surface_count():
				st.append_from(src, s, f[1])
		st.commit(mesh)
	return [mesh, order]


# ---------------------------------------------------------------- shared looks

## Small shared material shortcuts (all cached by Art).
static func m_skin(c: Color) -> ShaderMaterial:
	return Art.mat(c, 0.7, 0.0, 0.2, true, 0.1, &"skin")

static func m_cloth(c: Color) -> ShaderMaterial:
	return Art.mat(c, 0.9, 0.0, 0.4, true, 0.15, &"cloth")

static func m_metal(c: Color, rough: float = 0.35) -> ShaderMaterial:
	return Art.mat(c, rough, 0.9, 0.3, true, 0.0, &"metal")

static func m_gold() -> ShaderMaterial:
	return Art.mat(Art.GOLD, 0.3, 1.0, 0.2, true, 0.0, &"gold")

static func m_stone(c: Color = Art.STONE) -> ShaderMaterial:
	return Art.mat(c, 0.9, 0.0, 0.5, true, 0.0, &"marble")

static func m_wood() -> ShaderMaterial:
	return Art.mat(Color(0.32, 0.22, 0.13), 0.85, 0.0, 0.4, true, 0.0, &"wood")

static func m_leather(c: Color = Art.LEATHER) -> ShaderMaterial:
	return Art.mat(c, 0.75, 0.0, 0.4, true, 0.1, &"leather")

static func m_fur(c: Color) -> ShaderMaterial:
	return Art.mat(c, 0.95, 0.0, 0.3, true, 0.25, &"feather")
