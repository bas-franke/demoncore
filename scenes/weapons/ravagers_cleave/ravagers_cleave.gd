extends Weapon
## Cleaves a 120 degree arc in front of the demon with a heavy, burning blade.
## Later levels also cleave behind. A ghostly greatsword (Blender model,
## tools/blender/models/weapons/ravager_sword.py) sweeps the arc, leading the burning slash smear.

const CLEAVE_SHADER := preload("res://scenes/weapons/ravagers_cleave/cleave.gdshader")
## Half of the 120 degree arc, in radians.
const HALF_ARC := PI / 3.0
## Crescents: [radius (fraction of reach), arc span (fraction of HALF_ARC), max thickness].
## One broad blade smear plus a thin afterimage inside it.
const MARKS := [[0.8, 1.0, 0.36], [0.52, 0.78, 0.07]]
const MARK_SEGMENTS := 28
const SLASH_TIME := 0.3
## Sword length as a fraction of the reach, and how see-through the phantom blade is.
const SWORD_REACH := 0.92
const SWORD_GHOST := 0.2

@export var base_reach := 2.6
@export var knockback := 7.0
## Delay before the backwards cleave (level 4+).
@export var back_swipe_delay := 0.12

var damage_mult := 1.0
var reach_mult := 1.0
var double_swipe := false

static var _mesh: ArrayMesh
static var _material: ShaderMaterial


func _on_level_changed() -> void:
	damage_mult = 1.0 + 0.3 * int(level >= 2) + 0.4 * int(level >= 5)
	reach_mult = 1.0 + 0.2 * int(level >= 3) + 0.2 * int(level >= 6)
	double_swipe = level >= 4
	cooldown_mult = 0.75 if level >= 7 else 1.0


func get_reach() -> float:
	return base_reach * reach_mult * get_area()


func attack() -> bool:
	var dir := player.facing
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	_swipe(dir)
	if double_swipe:
		get_tree().create_timer(back_swipe_delay, false, true).timeout.connect(_swipe.bind(-dir))
	return true


func _swipe(dir: Vector3) -> void:
	if player == null or player.is_dead:
		return
	var origin := player.global_position
	var reach := get_reach()
	var dmg := get_damage() * damage_mult
	var hit_any := false
	var bursts := 0
	for node in Perf.enemies():
		var e := node as Enemy
		if e == null or e.is_dying:
			continue
		var to := e.global_position - origin
		to.y = 0.0
		var dist := to.length()
		var er := 0.45 * (e.data.size if e.data != null else 1.0)
		if dist > reach + er:
			continue
		# Enemies pressed against the demon are always hit; others must be inside the arc
		# (widened by the enemy's radius).
		if dist > er + 0.3:
			var ang := acos(clampf((to / dist).dot(dir), -1.0, 1.0))
			if ang > HALF_ARC + atan(er / dist):
				continue
		Enemy.hit(e, dmg, Targeting.flat_dir(origin, e.global_position) * knockback, self)
		if bursts < 6:
			bursts += 1
			InfernalFx.burst(e.global_position + Vector3(0.0, 0.7, 0.0), Art.HELLFIRE, 8, 3.0, 0.9)
		hit_any = true
	Sfx.play(&"cleave", 0.1)
	if hit_any:
		Sfx.play(&"impact", 0.1, -2.0)
		get_tree().call_group(&"camera_rig", &"shake", 0.1)
	_spawn_slash(origin, dir, reach)
	_spawn_sparks(origin, dir, reach)


func _spawn_slash(origin: Vector3, dir: Vector3, reach: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _get_mesh()
	mi.material_override = _get_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mi.rotation.y = atan2(-dir.x, -dir.z)
	mi.scale = Vector3.ONE * reach * 0.8
	mi.set_instance_shader_parameter(&"fade", 1.0)
	mi.set_instance_shader_parameter(&"sweep", 0.0)
	Game.spawn(mi, origin + Vector3(0.0, 0.7, 0.0))
	if not is_instance_valid(mi) or not mi.is_inside_tree():
		return
	# Phantom greatsword riding the leading edge of the smear (same pivot and yaw).
	var sword_pivot := Node3D.new()
	sword_pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mi.add_child(sword_pivot)
	var sword := WeaponArt.build(WeaponArt.SWORD, sword_pivot)
	sword.scale = Vector3.ONE * (SWORD_REACH / 1.06)  # model is 1.06 long; mi is scaled ~reach
	sword.rotation.z = 0.35  # rolled a little so the flat catches the light mid-swing
	var sword_geo := WeaponArt.geometry(sword)
	for g in sword_geo:
		g.transparency = SWORD_GHOST
	sword_pivot.rotation.y = HALF_ARC
	var set_sweep := func(v: float) -> void:
		mi.set_instance_shader_parameter(&"sweep", v)
		sword_pivot.rotation.y = -lerpf(-HALF_ARC, HALF_ARC, clampf(v, 0.0, 1.0))
	var set_ghost := func(v: float) -> void:
		for g in sword_geo:
			g.transparency = v
	var set_fade := func(v: float) -> void:
		mi.set_instance_shader_parameter(&"fade", v)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	var grow := tw.tween_property(mi, ^"scale", Vector3.ONE * reach, SLASH_TIME)
	grow.set_trans(Tween.TRANS_EXPO)
	grow.set_ease(Tween.EASE_OUT)
	# Heavy blade: a beat of wind-up, then a fast sweep.
	tw.tween_method(set_sweep, 0.0, 1.2, 0.11).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_method(set_fade, 1.0, 0.0, SLASH_TIME - 0.1).set_delay(0.1)
	tw.tween_method(set_ghost, SWORD_GHOST, 1.0, SLASH_TIME - 0.12).set_delay(0.12).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


## Embers thrown off the burning edge along the arc.
func _spawn_sparks(origin: Vector3, dir: Vector3, reach: float) -> void:
	if Game.world == null:
		return
	var yaw := atan2(-dir.x, -dir.z)
	var pts := PackedVector3Array()
	for i in 12:
		var theta := lerpf(-HALF_ARC, HALF_ARC, float(i) / 11.0)
		pts.append(Vector3(sin(theta) * reach * 0.9, 0.0, -cos(theta) * reach * 0.9).rotated(Vector3.UP, yaw))
	var p := InfernalFx.make_particles(Art.EMBER, 26, 0.5)
	p.one_shot = true
	p.explosiveness = 0.75
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	p.emission_points = pts
	p.spread = 70.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 2.4
	p.gravity = Vector3(0.0, 0.8, 0.0)
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	p.emitting = true
	Game.spawn(p, origin + Vector3(0.0, 0.7, 0.0))
	if is_instance_valid(p) and p.is_inside_tree():
		p.finished.connect(p.queue_free)


static func _get_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = CLEAVE_SHADER
	return _material


## Crescents in the XZ plane, centred on -Z, sized for a reach of 1.
static func _get_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for m: Array in MARKS:
		var radius: float = m[0]
		var half: float = HALF_ARC * float(m[1])
		var thick: float = m[2]
		for i in MARK_SEGMENTS:
			var s0 := float(i) / MARK_SEGMENTS
			var s1 := float(i + 1) / MARK_SEGMENTS
			var in0 := _arc_point(radius, half, thick, s0, -1.0)
			var out0 := _arc_point(radius, half, thick, s0, 1.0)
			var in1 := _arc_point(radius, half, thick, s1, -1.0)
			var out1 := _arc_point(radius, half, thick, s1, 1.0)
			_vertex(st, in0, Vector2(s0, 0.0))
			_vertex(st, out0, Vector2(s0, 1.0))
			_vertex(st, in1, Vector2(s1, 0.0))
			_vertex(st, in1, Vector2(s1, 0.0))
			_vertex(st, out0, Vector2(s0, 1.0))
			_vertex(st, out1, Vector2(s1, 1.0))
	_mesh = st.commit()
	return _mesh


## Point on a crescent: `s` 0..1 along the arc, `side` -1 inner / +1 outer edge.
## Thickness swells toward the trailing end (the blade's weight) and tapers to sharp tips.
static func _arc_point(radius: float, half: float, thick: float, s: float, side: float) -> Vector3:
	var theta := lerpf(-half, half, s)
	var t := thick * pow(sin(PI * s), 0.7) * lerpf(1.15, 0.85, s)
	var r := radius + side * t * 0.5
	return Vector3(sin(theta) * r, 0.0, -cos(theta) * r)


static func _vertex(st: SurfaceTool, v: Vector3, uv: Vector2) -> void:
	st.set_normal(Vector3.UP)
	st.set_uv(uv)
	st.add_vertex(v)
