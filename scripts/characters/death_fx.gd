class_name DeathFx
## Death animation variety per faction for the code-built (procedural) enemy models
## (characters-polish). EnemyModel.death_burst() calls DeathFx.try_play(model, ...) first; when it
## returns false the model's own spawn_corpse() runs as before.
##
##   &"shatter" (angels, elementals): a crack of light, then the body bursts into its parts, which
##              fly apart spinning, burn white and wink out in motes.
##   &"ragdoll" (mortals, the orders, beasts): topples AWAY from the killing blow, bounces once on
##              the ground, limbs flop loose, lies still, then sinks and burns away.
##   &"crumble" (constructs): parts drop under gravity, clatter and bounce on the ground, dust
##              bursts, the rubble settles and sinks.
##
## The model itself becomes the corpse: it is lifted out of the dying Enemy into Game.world (like
## ProcModel's own corpse) and freed when done. Blender angels keep their "death" clip corpses.

const SHATTER_TIME := 0.8
const RAGDOLL_FALL := 0.42
const RAGDOLL_LIE := 0.75
const CRUMBLE_TIME := 1.25
const GRAVITY := 11.0
## Perf: variant corpses started per frame / alive at once (AoE kills can drop dozens at once);
## past the caps the model falls back to its cheap default corpse.
const PER_FRAME := 6
const MAX_ALIVE := 24

static var _alive := 0


## Death style for a faction (CharacterRoster factions). &"" = none (keep the default corpse).
static func style_for_faction(faction: StringName) -> StringName:
	match faction:
		&"angel", &"elemental":
			return &"shatter"
		&"order", &"mortal", &"beast":
			return &"ragdoll"
		&"construct":
			return &"crumble"
	return &""


## Plays `style` on `model` (a code-built EnemyModel about to lose its Enemy). `from_dir`: world
## direction the killing blow came from (ragdolls fall away from it). Returns false when it
## didn't (no world, Blender model, perf caps), so the caller can use the default corpse.
static func try_play(model: EnemyModel, style: StringName, from_dir: Vector3, elite: bool) -> bool:
	if style == &"" or model.glb != null or Game.world == null or not model.is_inside_tree():
		return false
	if _alive >= MAX_ALIVE or not Perf.budget(&"death_variant", PER_FRAME):
		return false
	var meshes := _meshes(model)
	if meshes.is_empty():
		return false
	_lift(model)
	_alive += 1
	model.tree_exiting.connect(func() -> void: _alive = maxi(_alive - 1, 0))
	if style != &"shatter":
		# The killing hit left the body white-hot; cool it back so stone / flesh reads as it falls.
		model.create_tween().tween_method(model.set_flash, 0.8, 0.0, 0.18)
	match style:
		&"shatter":
			_shatter(model, meshes, 0.9 * model.body_scale * (1.5 if elite else 1.0), model.light_color,
				8 if elite else 4, model.body_scale)
		&"ragdoll":
			_ragdoll(model, from_dir)
		_:
			_crumble(model, meshes)
	return true


# ---------------------------------------------------------------- styles

## Blender angels: when the "death" clip corpse ends, a snapshot of its meshes (sharing their
## mesh / material resources) shatters into light while the corpse goes back to its pool.
## Returns false past the perf caps (the caller then shrinks / sinks the corpse as before).
static func shatter_snapshot(source: Node3D, color: Color, scale: float, elite: bool) -> bool:
	if Game.world == null or not source.is_inside_tree():
		return false
	if _alive >= MAX_ALIVE or not Perf.budget(&"death_variant", PER_FRAME):
		return false
	var src := _meshes(source)
	if src.is_empty():
		return false
	var root := Node3D.new()
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	Game.world.add_child(root)
	var meshes: Array[MeshInstance3D] = []
	for mi in src:
		var copy := MeshInstance3D.new()
		copy.mesh = mi.mesh
		copy.material_override = mi.material_override
		for i in mi.mesh.get_surface_count():
			copy.set_surface_override_material(i, mi.get_surface_override_material(i))
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(copy)
		copy.global_transform = mi.global_transform
		meshes.append(copy)
	_alive += 1
	root.tree_exiting.connect(func() -> void: _alive = maxi(_alive - 1, 0))
	_shatter(root, meshes, 0.9 * scale * (1.5 if elite else 1.0), color, 8 if elite else 4, scale)
	return true


static func _shatter(root: Node3D, meshes: Array[MeshInstance3D], reach: float, color: Color,
		motes: int, scale: float) -> void:
	var center := _center(meshes)
	var parts: Array = []  # [mesh, base global xf, fly dir, spin axis, spin speed]
	for mi in meshes:
		var c := mi.global_transform * mi.get_aabb().get_center()
		var out := c - center
		out.y = maxf(out.y, 0.0)
		if out.length_squared() < 0.0001:
			out = Vector3(randf_range(-1.0, 1.0), 0.5, randf_range(-1.0, 1.0))
		var dir := (out.normalized() + Vector3(0.0, 0.7, 0.0)).normalized()
		var axis := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		parts.append([mi, mi.global_transform, dir, axis, randf_range(4.0, 9.0)])
	var fly := func(k: float) -> void:
		# k 0..0.12: the crack (a held, white-hot pose), then the burst (fast start, easing out).
		var b := clampf((k - 0.12) / 0.88, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - b, 3.0)
		var shrink := 1.0 - clampf((b - 0.35) / 0.65, 0.0, 1.0)
		for p: Array in parts:
			var mi := p[0] as MeshInstance3D
			if not is_instance_valid(mi):
				continue
			var base: Transform3D = p[1]
			var rot := Basis(p[3] as Vector3, float(p[4]) * b)
			mi.global_transform = Transform3D(rot * base.basis.scaled(Vector3.ONE * maxf(shrink, 0.01)),
				base.origin + (p[2] as Vector3) * reach * e)
	var flash := func(v: float) -> void: Art.flash(root, v)
	var ft := root.create_tween()
	ft.tween_method(flash, 1.0, 0.6, SHATTER_TIME * 0.12)
	ft.tween_method(flash, 0.6, 1.0, SHATTER_TIME * 0.88)
	var tw := root.create_tween()
	tw.tween_method(fly, 0.0, 1.0, SHATTER_TIME)
	tw.tween_callback(root.queue_free)
	# The burst itself: motes from where the parts fly.
	var mt := root.create_tween()
	mt.tween_interval(SHATTER_TIME * 0.12)
	mt.tween_callback(func() -> void: EnemyModel.spawn_motes(center, motes, scale, color))


static func _ragdoll(model: EnemyModel, from_dir: Vector3) -> void:
	var away := -from_dir
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = model.global_basis.z  # no idea where it came from: fall backwards
	away = away.normalized()
	# Rotate "up" toward `away` about the feet; a little sideways twist so falls vary.
	var axis := Vector3.UP.cross(away).normalized()
	var base := model.global_transform
	var max_angle := deg_to_rad(randf_range(78.0, 88.0))
	var twist := randf_range(-0.5, 0.5)
	var height := 0.9 * model.body_scale
	# Limbs (ProcModel walk pivots) flop loose with a decaying wobble.
	var limbs: Array = []
	# Which pivots go limp: the model's own list if it offers one (ragdoll_limbs() -> Array of
	# Node3D, see docs/team/characters-new.md), else the walk-cycle legs / arms at full flop plus
	# every other registered animated pivot (tails, wings, weapons, heads) at a gentler one.
	var seen := {}
	var sources: Array = []
	if model.has_method(&"ragdoll_limbs"):
		sources.append([model.call(&"ragdoll_limbs"), 1.0])
	else:
		sources.append([model.get(&"_legs"), 1.0])
		sources.append([model.get(&"_arms"), 1.0])
		sources.append([model.get(&"_animated"), 0.45])
	for src: Array in sources:
		if not src[0] is Array:
			continue
		var amp: float = src[1]
		for l: Variant in src[0]:
			if l is Node3D and is_instance_valid(l) and not seen.has(l):
				seen[l] = true
				limbs.append([l, (l as Node3D).rotation,
					Vector3(randf_range(-0.9, 0.9), randf_range(-0.3, 0.3), randf_range(-0.6, 0.6)) * amp])
	var fall := func(k: float) -> void:
		# 0..1 over fall + bounce: gravity-like fall (quad in) to the ground, then one bounce.
		var a: float
		if k < 0.7:
			var u := k / 0.7
			a = max_angle * u * u
		else:
			var u := (k - 0.7) / 0.3
			a = max_angle - deg_to_rad(9.0) * sin(u * PI) * (1.0 - u * 0.3)
		var xf := Transform3D(Basis(axis, a) * Basis(Vector3.UP, twist * k) * base.basis, base.origin)
		# Slide a little along the fall, and drop the pivot slightly so the body lies ON the ground.
		xf.origin += away * height * 0.25 * minf(k / 0.7, 1.0) - Vector3(0.0, 0.06 * model.body_scale * k, 0.0)
		model.global_transform = xf
		for l: Array in limbs:
			var n := l[0] as Node3D
			if is_instance_valid(n):
				var wob := sin(k * 18.0) * (1.0 - k) * 0.35
				n.rotation = (l[1] as Vector3) + (l[2] as Vector3) * minf(k * 1.6, 1.0) + Vector3(wob, 0.0, 0.0)
	var tw := model.create_tween()
	tw.tween_method(fall, 0.0, 1.0, RAGDOLL_FALL + 0.2)
	tw.tween_callback(func() -> void:
		EnemyModel.poof(model.global_position + away * height * 0.6, Art.STONE, Art.BONE, 5, 0.25 * model.body_scale,
			0.6 * model.body_scale))
	tw.tween_interval(RAGDOLL_LIE)
	tw.tween_method(model.set_flash, 0.0, 0.9, 0.45)
	tw.parallel().tween_property(model, "position:y", model.position.y - 0.5 * model.body_scale, 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(model.queue_free)


static func _crumble(model: EnemyModel, meshes: Array[MeshInstance3D]) -> void:
	var center := _center(meshes)
	var parts: Array = []  # [mesh, base xf, velocity, spin axis, spin speed, half height]
	for mi in meshes:
		var base := mi.global_transform
		var c := base * mi.get_aabb().get_center()
		var out := c - center
		out.y = 0.0
		var vel := out.normalized() * randf_range(0.4, 1.4) + Vector3(0.0, randf_range(0.5, 2.0), 0.0) \
				if out.length_squared() > 0.0001 else Vector3(0.0, 1.0, 0.0)
		var half := (base.basis * mi.get_aabb().size).length() * 0.25
		parts.append([mi, base, vel, Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized(),
			randf_range(2.0, 6.0), half, c])
	var fall := func(tt: float) -> void:
		for p: Array in parts:
			var mi := p[0] as MeshInstance3D
			if not is_instance_valid(mi):
				continue
			var base: Transform3D = p[1]
			var v: Vector3 = p[2]
			var c0: Vector3 = p[6]
			var pos := c0 + v * tt + Vector3(0.0, -0.5 * GRAVITY * tt * tt, 0.0)
			var floor_y := float(p[5])
			var spin := float(p[4]) * tt
			if pos.y < floor_y:
				# Landed: one damped bounce, then rest.
				var t_hit := (v.y + sqrt(maxf(v.y * v.y + 2.0 * GRAVITY * (c0.y - floor_y), 0.0))) / GRAVITY
				var after := tt - t_hit
				pos = c0 + v * t_hit + Vector3(0.0, -0.5 * GRAVITY * t_hit * t_hit, 0.0)
				pos.y = floor_y + maxf(0.0, 1.2 * after - 0.5 * GRAVITY * after * after) * 0.5
				pos += Vector3(v.x, 0.0, v.z) * minf(after, 0.15)
				spin = float(p[4]) * (t_hit + minf(after, 0.2))
			var rot := Basis(p[3] as Vector3, spin)
			# Keep the part's own offset from its centre so pieces don't snap to their pivots.
			var off := base.origin - c0
			mi.global_transform = Transform3D(rot * base.basis, pos + rot * off)
	var tw := model.create_tween()
	tw.tween_callback(func() -> void:
		EnemyModel.poof(center, Art.STONE, Art.ASH, 8, 0.4 * model.body_scale, 0.9 * model.body_scale))
	tw.tween_method(fall, 0.0, CRUMBLE_TIME * 0.65, CRUMBLE_TIME * 0.65)
	tw.tween_callback(func() -> void:
		EnemyModel.poof(Vector3(center.x, 0.1, center.z), Art.STONE, Art.ASH, 6, 0.3 * model.body_scale,
			0.7 * model.body_scale))
	tw.tween_method(model.set_flash, 0.0, 0.5, CRUMBLE_TIME * 0.35)
	tw.parallel().tween_property(model, "global_position", model.global_position - Vector3(0.0, 0.6, 0.0),
		CRUMBLE_TIME * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(model.queue_free)


# ---------------------------------------------------------------- helpers

## Moves the model out of its Enemy into Game.world, keeping its pose (Enemy frees itself next).
static func _lift(model: EnemyModel) -> void:
	var xf := model.global_transform
	model.set_process(false)
	model.set_physics_process(false)
	model.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	model.get_parent().remove_child(model)
	Game.world.add_child(model)
	model.global_transform = xf
	Art.no_shadows(model)


static func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).visible and (n as MeshInstance3D).mesh:
			out.append(n as MeshInstance3D)
		stack.append_array(n.get_children())
	return out


static func _center(meshes: Array[MeshInstance3D]) -> Vector3:
	var c := Vector3.ZERO
	for mi in meshes:
		c += mi.global_transform * mi.get_aabb().get_center()
	return c / float(maxi(meshes.size(), 1))
