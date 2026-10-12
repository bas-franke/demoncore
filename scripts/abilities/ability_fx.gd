class_name AbilityFx
## Procedural one-shot visuals for abilities (rings, pillars, lightning, fans, beams, telegraphs).
## Everything is spawned into Game.world, animated with a tween and frees itself. Meshes are the
## shared unit meshes from Art; fading uses GeometryInstance3D.transparency so cached materials
## are never mutated.
##
##   AbilityFx.ring(pos, 3.0, color)                # expanding ground ring
##   AbilityFx.lightning(a, b, color)               # jagged bolt between two points
##   AbilityFx.pillar(pos, 1.2, color)              # column of light / fire
##   AbilityFx.fan(pos, dir, 3.0, 110.0, color)     # melee arc on the ground
##   AbilityFx.beam(a, b, 0.8, color)               # flat strip (fissure / beam)
##   AbilityFx.telegraph(pos, r, color, time)       # warning circle that fills, then frees

static var _fan_meshes := {}


static func _spawn_mesh(mesh: Mesh, mat: Material, at: Vector3) -> MeshInstance3D:
	if Game.world == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	Game.spawn(mi, at)
	return mi


static func _fade_free(mi: MeshInstance3D, time: float, delay: float = 0.0) -> Tween:
	var tw := mi.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(mi, ^"transparency", 1.0, time).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)
	return tw


## Flat ring on the ground that expands from 30% to `radius` and fades.
static func ring(at: Vector3, radius: float, color: Color, time: float = 0.35) -> void:
	var mi := _spawn_mesh(Art.torus(0.86, 1.0), Art.glow(color, 2.4, true, 0.85), Vector3(at.x, 0.12, at.z))
	if mi == null:
		return
	mi.scale = Vector3(radius * 0.3, 0.12, radius * 0.3)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, ^"scale", Vector3(radius, 0.12, radius), time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, ^"transparency", 1.0, time).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


## Translucent disc on the ground (fades in place).
static func disc(at: Vector3, radius: float, color: Color, time: float = 0.3, alpha: float = 0.3) -> void:
	var mi := _spawn_mesh(Art.cylinder(), Art.glow(color, 1.0, true, alpha), Vector3(at.x, 0.06, at.z))
	if mi == null:
		return
	mi.scale = Vector3(radius * 2.0, 0.02, radius * 2.0)
	_fade_free(mi, time)


## A column of light/fire that shoots up and thins out.
static func pillar(at: Vector3, radius: float, color: Color, time: float = 0.4, height: float = 6.0) -> void:
	var mi := _spawn_mesh(Art.cylinder(0.7, 1.0), Art.glow(color, 2.0, true, 0.5), Vector3(at.x, height * 0.5, at.z))
	if mi == null:
		return
	mi.scale = Vector3(radius, height, radius)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, ^"scale", Vector3(radius * 0.15, height * 1.2, radius * 0.15), time).set_ease(Tween.EASE_IN)
	tw.tween_property(mi, ^"transparency", 1.0, time).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


## A jagged bolt from `a` to `b`: a few kinked segments that flicker out.
static func lightning(a: Vector3, b: Vector3, color: Color, time: float = 0.22, thickness: float = 0.07) -> void:
	if Game.world == null:
		return
	var root := Node3D.new()
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	Game.spawn(root, Vector3.ZERO)
	var mat := Art.glow(color, 3.5, true, 1.0)
	var core := Art.glow(Color(1.0, 0.92, 0.95), 2.0, true, 1.0)
	var steps := clampi(int(a.distance_to(b) / 0.8), 2, 9)
	var side := (b - a).cross(Vector3.UP).normalized()
	var prev := a
	for i in range(1, steps + 1):
		var t := float(i) / steps
		var p := a.lerp(b, t)
		if i < steps:
			p += side * randf_range(-0.35, 0.35) + Vector3(0.0, randf_range(-0.25, 0.25), 0.0)
		InfernalFx.segment(root, prev, p, thickness * 2.2, mat)
		InfernalFx.segment(root, prev, p, thickness * 0.8, core)
		prev = p
	var tw := root.create_tween()
	tw.tween_interval(time)
	tw.tween_callback(root.queue_free)


## Melee arc: a flat fan of `arc_deg` degrees facing `dir`, sweeping in and fading.
static func fan(at: Vector3, dir: Vector3, radius: float, arc_deg: float, color: Color, time: float = 0.25) -> void:
	var mi := _spawn_mesh(_fan_mesh(arc_deg), Art.glow(color, 2.2, true, 0.7), Vector3(at.x, 0.15, at.z))
	if mi == null:
		return
	mi.rotation.y = atan2(dir.x, dir.z)
	mi.scale = Vector3.ONE * radius * 0.5
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, ^"scale", Vector3.ONE * radius, time * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, ^"transparency", 1.0, time).set_delay(time * 0.3)
	tw.chain().tween_callback(mi.queue_free)


## Unit fan (radius 1) around +Z in the XZ plane, cached per arc.
static func _fan_mesh(arc_deg: float) -> ArrayMesh:
	var key := int(arc_deg)
	if _fan_meshes.has(key):
		return _fan_meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := deg_to_rad(arc_deg) * 0.5
	var segs := maxi(int(arc_deg / 10.0), 4)
	for i in segs:
		var a0 := -half + (2.0 * half) * i / segs
		var a1 := -half + (2.0 * half) * (i + 1) / segs
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(sin(a0), 0.0, cos(a0)))
		st.add_vertex(Vector3(sin(a1), 0.0, cos(a1)))
	var m := st.commit()
	_fan_meshes[key] = m
	return m


## Flat glowing strip from `a` to `b` on the ground (fissure, beam footprint).
static func beam(a: Vector3, b: Vector3, width: float, color: Color, time: float = 0.35, height: float = 0.1) -> void:
	var d := b - a
	d.y = 0.0
	var mid := (a + b) * 0.5
	var mi := _spawn_mesh(Art.box(), Art.glow(color, 2.6, true, 0.8), Vector3(mid.x, height, mid.z))
	if mi == null:
		return
	mi.rotation.y = atan2(d.x, d.z)
	mi.scale = Vector3(width, 0.08, d.length())
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, ^"scale:x", width * 0.15, time).set_ease(Tween.EASE_IN)
	tw.tween_property(mi, ^"transparency", 1.0, time).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


## Warning circle: a faint disc with a ring that closes in over `time`. Frees itself.
static func telegraph(at: Vector3, radius: float, color: Color, time: float) -> void:
	var d := _spawn_mesh(Art.cylinder(), Art.glow(color, 0.6, true, 0.15), Vector3(at.x, 0.05, at.z))
	if d == null:
		return
	d.scale = Vector3(radius * 2.0, 0.02, radius * 2.0)
	var tw := d.create_tween()
	tw.tween_interval(time)
	tw.tween_callback(d.queue_free)
	var r := _spawn_mesh(Art.torus(0.93, 1.0), Art.glow(color, 1.8, true, 0.8), Vector3(at.x, 0.08, at.z))
	r.scale = Vector3(radius * 1.6, 0.1, radius * 1.6)
	var rt := r.create_tween()
	rt.tween_property(r, ^"scale", Vector3(radius, 0.1, radius), time).set_ease(Tween.EASE_IN)
	rt.tween_callback(r.queue_free)


## A brief glyph (flat torus) hovering over an enemy, used for hexes and marks.
static func sigil(at: Vector3, color: Color, size: float = 0.6, time: float = 0.5) -> void:
	var mi := _spawn_mesh(Art.torus(0.75, 1.0), Art.glow(color, 3.0, true, 0.9), at)
	if mi == null:
		return
	mi.scale = Vector3(size * 1.6, 0.1, size * 1.6)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, ^"scale", Vector3(size, 0.1, size), time * 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, ^"position:y", at.y + 0.5, time)
	tw.tween_property(mi, ^"transparency", 1.0, time).set_delay(time * 0.4)
	tw.chain().tween_callback(mi.queue_free)


## A taut chain from `a` to `b`: dark iron links with a glowing core, gone after `time`.
static func tether(a: Vector3, b: Vector3, color: Color, time: float = 0.25) -> void:
	if Game.world == null:
		return
	var root := Node3D.new()
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	Game.spawn(root, Vector3.ZERO)
	InfernalFx.segment(root, a, b, 0.09, Art.mat(Art.STEEL, 0.4, 0.8))
	InfernalFx.segment(root, a, b, 0.05, Art.glow(color, 2.5, true, 0.9))
	var tw := root.create_tween()
	tw.tween_interval(time)
	tw.tween_callback(root.queue_free)
