class_name HolyFX
extends RefCounted
## One-shot radiant effects for the Herald fight (and its rewards): light columns, flashes,
## drifting feathers, falling ash and rising motes. Everything is spawned into Game.world and
## cleans itself up, so it is safe to call from a node that is about to be freed.
##
## Fading glow uses per-effect additive materials (never Art.glow's shared cache): an additive
## surface fades out by darkening its albedo to black.

const GRAVITY := 9.0

static var _feather_mesh: BoxMesh
static var _flake_mesh: BoxMesh


# ---- characters-new: per-boss hazard tint (marked edit). The shared hazards (InquisitorLane,
# PyreBurst, BellRing, JudgementPillar, SarielOrb) copy `hazard_tint` into their `tint` when
# created; ProcBoss sets it around its casts and restores Art.HOLY. Default = the original look.
static var hazard_tint := Art.HOLY


## The hot core colour for a tint: HOLY_WHITE for the default holy tint, else the tint washed
## toward white.
static func white_of(c: Color) -> Color:
	return Art.HOLY_WHITE if c == Art.HOLY else c.lerp(Art.HOLY_WHITE, 0.55)
# ---- end characters-new


## A fresh (uncached) unshaded additive material. `energy` > 1 blooms.
static func additive(color: Color, energy: float = 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = scaled(color, energy)
	return m


static func scaled(color: Color, energy: float) -> Color:
	return Color(color.r * energy, color.g * energy, color.b * energy, 1.0)


## Adds an additive glowing mesh with its own material (returned via the mesh's material_override).
static func glow_part(parent: Node3D, mesh: Mesh, color: Color, energy: float, pos := Vector3.ZERO,
		scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = additive(color, energy)
	mi.position = pos
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(mi)
	return mi


static func _root(at: Vector3) -> Node3D:
	if Game.world == null:
		return null
	var root := Node3D.new()
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	Game.spawn(root, at)
	if not is_instance_valid(root) or not root.is_inside_tree():
		return null
	return root


static func _free_after(root: Node3D, seconds: float) -> void:
	var tw := root.create_tween()
	tw.tween_interval(seconds)
	tw.tween_callback(root.queue_free)


## Expanding sphere of light + a short, strong point light.
static func flash(at: Vector3, radius: float = 3.0, life: float = 0.5, color := Art.HOLY_WHITE,
		energy: float = 3.0) -> void:
	var root := _root(at)
	if root == null:
		return
	var orb := glow_part(root, Art.sphere(), color, energy, Vector3.ZERO, Vector3.ONE * radius * 0.4)
	var mat := orb.material_override as StandardMaterial3D
	var tw := orb.create_tween()
	tw.tween_property(orb, "scale", Vector3.ONE * radius * 2.0, life).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "albedo_color", Color(0.0, 0.0, 0.0, 1.0), life) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var l := Art.light(root, color, energy * 2.5, radius * 3.0)
	var lt := l.create_tween()
	lt.tween_property(l, "light_energy", 0.0, life * 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_free_after(root, life * 1.4 + 0.05)


## A column of light standing on the ground at `at` (XZ). It thins and fades over `life`.
static func column(at: Vector3, radius: float = 1.0, height: float = 16.0, life: float = 0.6,
		color := Art.HOLY, energy: float = 2.2) -> void:
	var root := _root(Vector3(at.x, 0.0, at.z))
	if root == null:
		return
	var core := glow_part(root, Art.cylinder(), Art.HOLY_WHITE, energy, Vector3(0.0, height * 0.5, 0.0),
			Vector3(radius * 1.8, height, radius * 1.8))
	var shell := glow_part(root, Art.cylinder(), color, energy * 0.45, Vector3(0.0, height * 0.5, 0.0),
			Vector3(radius * 2.8, height, radius * 2.8))
	for mi: MeshInstance3D in [core, shell]:
		var m := mi.material_override as StandardMaterial3D
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale:x", mi.scale.x * 0.15, life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(mi, "scale:z", mi.scale.z * 0.15, life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(m, "albedo_color", Color(0.0, 0.0, 0.0, 1.0), life)
	_free_after(root, life + 0.05)


## Feathers that drift and flutter down, then dissolve into light.
static func feathers(at: Vector3, count: int = 10, spread: float = 1.0, life: float = 2.2) -> void:
	var root := _root(at)
	if root == null:
		return
	if _feather_mesh == null:
		_feather_mesh = BoxMesh.new()
		_feather_mesh.size = Vector3(0.09, 0.012, 0.32)
	var ivory := Art.mat(Art.IVORY, 0.7, 0.0, 0.15, false, 0.6)
	var floor_y := 0.05 - at.y
	var longest := 0.0
	for i in count:
		var f := MeshInstance3D.new()
		f.mesh = _feather_mesh
		f.material_override = ivory
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		root.add_child(f)
		var a := randf() * TAU
		var drift := Vector3(cos(a), 0.0, sin(a)) * randf_range(0.4, 1.4) * spread
		var start := Vector3(randf_range(-0.4, 0.4), randf_range(-0.3, 0.3), randf_range(-0.4, 0.4)) * spread
		var fall := randf_range(0.7, 1.3)
		var phase := randf() * TAU
		var spin := randf_range(-3.0, 3.0)
		var s := randf_range(0.8, 1.5) * sqrt(maxf(spread, 0.2))
		var lf := life * randf_range(0.7, 1.15)
		longest = maxf(longest, lf)
		var fly := func(tt: float) -> void:
			var p := start + drift * tt + Vector3(sin(tt * 3.0 + phase) * 0.35, -fall * tt, cos(tt * 2.3 + phase) * 0.2)
			p.y = maxf(p.y, floor_y)
			f.position = p
			f.rotation = Vector3(sin(tt * 4.0 + phase) * 0.7, spin * tt + phase, cos(tt * 3.3 + phase) * 0.5)
		var tw := f.create_tween()
		f.scale = Vector3.ONE * s
		tw.tween_method(fly, 0.0, lf, lf)
		tw.parallel().tween_property(f, "scale", Vector3.ONE * 0.01, lf * 0.35).set_delay(lf * 0.65) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	motes(at, maxi(int(float(count) * 0.5), 2), Art.HOLY, spread, 1.5, life)
	_free_after(root, longest + 0.1)


## Small glowing specks that rise (or fall, with a negative `rise`) and fade.
static func motes(at: Vector3, count: int = 8, color := Art.HOLY, spread: float = 1.0, rise: float = 1.5,
		life: float = 1.2, size: float = 0.07) -> void:
	var root := _root(at)
	if root == null:
		return
	var mat := additive(color, 3.0)
	for i in count:
		var m := MeshInstance3D.new()
		m.mesh = Art.sphere()
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		var a := randf() * TAU
		m.position = Vector3(cos(a), randf_range(-0.3, 0.6), sin(a)) * randf_range(0.1, 1.0) * spread
		var sz := size * randf_range(0.6, 1.4)
		m.scale = Vector3.ONE * sz
		root.add_child(m)
		var lf := life * randf_range(0.6, 1.1)
		var tw := m.create_tween()
		tw.tween_property(m, "position", m.position + Vector3(randf_range(-0.3, 0.3), rise * randf_range(0.6, 1.3),
				randf_range(-0.3, 0.3)), lf).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(m, "scale", Vector3.ONE * 0.005, lf).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var fade := root.create_tween()
	fade.tween_property(mat, "albedo_color", Color(0.0, 0.0, 0.0, 1.0), life * 1.1)
	_free_after(root, life * 1.15 + 0.05)


## Slow fall of grey ash and a few dying embers of light over a disc of `radius`, for `duration`.
static func ash(center: Vector3, radius: float = 9.0, duration: float = 5.0, count: int = 110) -> void:
	var root := _root(Vector3(center.x, 0.0, center.z))
	if root == null:
		return
	if _flake_mesh == null:
		_flake_mesh = BoxMesh.new()
		_flake_mesh.size = Vector3(0.07, 0.01, 0.06)
	var greys: Array[Material] = [
		Art.mat(Art.ASH, 0.95, 0.0, 0.0, false),
		Art.mat(Art.STONE, 0.95, 0.0, 0.0, false),
		Art.mat(Art.BONE.darkened(0.35), 0.95, 0.0, 0.0, false),
	]
	var ember := additive(Art.HOLY, 1.6)
	var longest := 0.0
	for i in count:
		var f := MeshInstance3D.new()
		f.mesh = _flake_mesh
		var is_ember := i % 7 == 0
		f.material_override = ember if is_ember else greys[i % greys.size()]
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		f.scale = Vector3.ONE * randf_range(0.7, 1.6)
		f.visible = false
		root.add_child(f)
		var a := randf() * TAU
		var r := sqrt(randf()) * radius
		var start := Vector3(cos(a) * r, randf_range(5.0, 9.0), sin(a) * r)
		var fall_speed := randf_range(0.9, 1.6)
		var fall_time := start.y / fall_speed
		var phase := randf() * TAU
		var wind := Vector3(randf_range(-0.25, 0.25), 0.0, randf_range(-0.15, 0.25))
		var delay := randf() * duration * 0.7
		longest = maxf(longest, delay + fall_time)
		var fly := func(tt: float) -> void:
			f.position = start + wind * tt + Vector3(sin(tt * 1.7 + phase) * 0.3, -fall_speed * tt, cos(tt * 1.3 + phase) * 0.2)
			f.rotation = Vector3(tt * 1.9 + phase, tt * 0.7, tt * 1.3)
		var tw := f.create_tween()
		tw.tween_interval(delay)
		tw.tween_callback(f.set.bind(&"visible", true))
		tw.tween_method(fly, 0.0, fall_time, fall_time)
		tw.tween_property(f, "scale", Vector3.ONE * 0.01, 0.6)
	_free_after(root, longest + 0.8)
