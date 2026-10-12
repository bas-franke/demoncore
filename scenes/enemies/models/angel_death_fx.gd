class_name AngelDeathFX
extends RefCounted
## One-shot holy FX for angels and other hit / death moments: light flashes, rising motes, falling
## feathers, flying debris, ground shockwaves and soft dust puffs. Static only; everything is
## spawned into Game.world and frees itself, so it is safe to call from a node about to be freed.
## Split out of EnemyModel (enemy_model.gd), which keeps forwarders for the public functions.

const DEBRIS_GRAVITY := 14.0
const FEATHER_FALL := 0.75
static var _soft_meshes := {}

## A brief burst of light: a glowing sphere that swells and collapses. Elites add a pillar of
## light and a short-lived OmniLight.
static func light_flash(at: Vector3, radius: float, color: Color = Art.HOLY, strong: bool = false) -> void:
	if Game.world == null:
		return
	var root := _fx_root(at)
	var core := Art.part(root, Art.sphere(), Art.glow(Art.HOLY_WHITE, 2.2), Vector3.ZERO, Vector3.ONE * 0.05)
	var bloom := Art.part(root, Art.sphere(), Art.glow(color, 0.5), Vector3.ZERO, Vector3.ONE * 0.05)
	var tw := root.create_tween()
	tw.tween_property(core, "scale", Vector3.ONE * radius * 0.7, 0.06).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(bloom, "scale", Vector3.ONE * radius * 1.6, 0.1).set_ease(Tween.EASE_OUT)
	tw.tween_property(core, "scale", Vector3.ONE * 0.01, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(bloom, "scale", Vector3.ONE * 0.01, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var life := 0.45
	if strong:
		var pillar := Art.part(root, Art.cylinder(), Art.glow(color, 1.4), Vector3(0.0, 4.0 - at.y, 0.0),
				Vector3(radius * 0.5, 9.0, radius * 0.5))
		var ptw := pillar.create_tween()
		ptw.tween_property(pillar, "scale", Vector3(0.01, 9.0, 0.01), 0.6).set_trans(Tween.TRANS_QUAD) \
				.set_ease(Tween.EASE_IN)
		var l := Art.light(root, color, 6.0, radius * 6.0)
		var ltw := l.create_tween()
		ltw.tween_property(l, "light_energy", 0.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		life = 0.8
	_cleanup(root, life)


## Small motes of light that drift upward and outward, then wink out.
static func spawn_motes(at: Vector3, count: int, s: float = 1.0, color: Color = Art.HOLY) -> void:
	if Game.world == null or count <= 0:
		return
	var root := _fx_root(at)
	var k := sqrt(maxf(s, 0.1))
	var longest := 0.0
	for i in count:
		var col: Color = Art.HOLY_WHITE if i % 3 == 0 else color
		var r := randf_range(0.05, 0.1) * k
		var m := Art.part(root, Art.sphere(), Art.glow(col, 3.0), Vector3.ZERO, Vector3.ONE * r)
		var a := randf() * TAU
		var target := Vector3(cos(a), 0.0, sin(a)) * randf_range(0.3, 1.1) * k \
				+ Vector3(0.0, randf_range(0.6, 1.6) * k, 0.0)
		var life := randf_range(0.7, 1.3)
		longest = maxf(longest, life)
		var tw := m.create_tween()
		tw.tween_property(m, "position", target, life).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(m, "scale", Vector3.ONE * 0.005, life * 0.5).set_delay(life * 0.5) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_cleanup(root, longest + 0.05)


## White feathers that puff out, then see-saw slowly down to the ground and fade.
static func spawn_feathers(at: Vector3, count: int, s: float = 1.0, color: Color = Art.HOLY_WHITE) -> void:
	if Game.world == null or count <= 0:
		return
	var root := _fx_root(at)
	var floor_y := 0.03 - at.y
	var k := sqrt(maxf(s, 0.1))
	var fmat := Art.mat(color, 0.7, 0.0, 0.1, false, 0.4)
	var longest := 0.0
	for i in count:
		var piece := Art.pivot(root)
		var vane := Art.part(piece, Art.sphere(), fmat, Vector3.ZERO, Vector3(0.075, 0.012, 0.24) * k)
		vane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := randf() * TAU
		var out := Vector3(cos(a), 0.0, sin(a)) * randf_range(0.35, 0.9) * k
		var up := randf_range(0.2, 0.6) * k
		var sway_f := randf_range(2.6, 3.8)
		var ph := randf() * TAU
		var spin := randf_range(-1.5, 1.5)
		var life := randf_range(1.6, 2.4)
		longest = maxf(longest, life)
		var fly := func(tt: float) -> void:
			var burst := 1.0 - exp(-5.0 * tt)
			var sway := sin(tt * sway_f + ph)
			var pos := out * burst + Vector3(out.z, 0.0, -out.x).normalized() * sway * 0.18 * k
			pos.y = up * burst - FEATHER_FALL * k * tt + absf(sway) * 0.05 * k
			pos.y = maxf(pos.y, floor_y)
			piece.position = pos
			piece.rotation = Vector3(sway * 0.5, a + spin * tt, cos(tt * sway_f + ph) * 0.35)
		var tw := piece.create_tween()
		tw.tween_method(fly, 0.0, life, life)
		tw.parallel().tween_property(piece, "scale", Vector3.ONE * 0.01, 0.35).set_delay(life - 0.35)
	_cleanup(root, longest + 0.05)


## Flings `count` bits out of `at` in short arcs. Kinds: &"shard" (stone), &"gold", &"steel",
## &"feather", &"mote"; unknown kinds become shards tinted `color`.
static func spawn_debris(at: Vector3, kinds: Array[StringName], color: Color, count: int, s: float = 1.0) -> void:
	if Game.world == null or kinds.is_empty() or count <= 0:
		return
	var root := _fx_root(at)
	var floor_y := 0.05 - at.y
	var k := sqrt(maxf(s, 0.1))
	var longest := 0.0
	for i in count:
		var kind: StringName = kinds[i % kinds.size()]
		var piece := _debris_piece(root, kind, color)
		Art.no_shadows(piece)
		piece.scale = Vector3.ONE * k * randf_range(0.8, 1.2)
		var a := randf() * TAU
		var out := randf_range(1.2, 3.0) * k
		var vel := Vector3(cos(a) * out, randf_range(3.4, 5.4) * k, sin(a) * out)
		var rot_v := Vector3(randf_range(-10.0, 10.0), randf_range(-10.0, 10.0), randf_range(-10.0, 10.0))
		var life := randf_range(0.7, 1.0)
		longest = maxf(longest, life)
		var fly := func(tt: float) -> void:
			var pos := vel * tt + Vector3(0.0, -0.5 * DEBRIS_GRAVITY * tt * tt, 0.0)
			if pos.y <= floor_y:
				pos.y = floor_y
				piece.rotation = rot_v * minf(tt, 0.4)
			else:
				piece.rotation = rot_v * tt
			piece.position = pos
		var tw := piece.create_tween()
		tw.tween_method(fly, 0.0, life, life)
		tw.parallel().tween_property(piece, "scale", Vector3.ONE * 0.01, 0.2).set_delay(life - 0.2)
	_cleanup(root, longest + 0.1)


static func _debris_piece(parent: Node3D, kind: StringName, color: Color) -> Node3D:
	var p := Art.pivot(parent)
	match kind:
		&"gold":
			Art.part(p, Art.box(), Art.mat(Art.GOLD, 0.3, 0.95, 0.2, false), Vector3.ZERO, Vector3(0.12, 0.03, 0.08))
		&"steel":
			Art.part(p, Art.prism(), Art.mat(Art.IVORY, 0.4, 0.4, 0.3, false), Vector3.ZERO, Vector3(0.16, 0.14, 0.03))
		&"feather":
			Art.part(p, Art.sphere(), Art.mat(Art.HOLY_WHITE, 0.7, 0.0, 0.1, false, 0.4), Vector3.ZERO,
					Vector3(0.07, 0.012, 0.22))
		&"mote", &"sparkle":
			Art.part(p, Art.sphere(), Art.glow(Art.HOLY, 3.0), Vector3.ZERO, Vector3.ONE * 0.08)
		_:
			var c: Color = color if kind != &"shard" else Art.STONE
			Art.part(p, Art.prism(), Art.mat(c, 0.95, 0.0, 0.6, false), Vector3.ZERO, Vector3(0.18, 0.16, 0.1))
	return p


## Expanding ring of light on the ground (slam impacts, elite deaths). `at` is on the ground.
static func shockwave(at: Vector3, radius: float, color: Color = Art.HOLY, time: float = 0.45) -> void:
	if Game.world == null:
		return
	var root := _fx_root(at)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(color.r * 2.5, color.g * 2.5, color.b * 2.5, 1.0)
	var ring := Art.part(root, Art.torus(0.82, 1.0), m, Vector3.ZERO, Vector3(0.2, 0.15, 0.2))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector3(radius, 0.15, radius), time).set_trans(Tween.TRANS_CUBIC) \
			.set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_cleanup(root, time + 0.05)


## Dust / light burst: `count` soft translucent puffs that billow out, rise a little and thin
## away. Spawned into Game.world, so it is safe to call from a node that is about to be freed.
static func poof(at: Vector3, color_a: Color, color_b: Color, count: int = 6, radius: float = 0.45,
		spread: float = 0.5) -> void:
	if Game.world == null or count <= 0:
		return
	var root := _fx_root(at)
	var mat_a := Art.glow(color_a, 0.55, false, 0.3)
	var mat_b := Art.glow(color_b, 0.55, false, 0.3)
	var longest := 0.0
	for i in count:
		var a := TAU * float(i) / float(count) + randf_range(-0.3, 0.3)
		var dir := Vector3(cos(a), randf_range(-0.1, 0.45), sin(a)).normalized()
		var r := radius * randf_range(0.75, 1.2)
		var puff := Art.part(root, _soft_sphere(), (mat_a if i % 2 == 0 else mat_b) as Material, dir * spread * 0.2,
				Vector3.ONE * r * 0.3)
		var life := randf_range(0.55, 0.8)
		longest = maxf(longest, life)
		var tw := puff.create_tween()
		tw.tween_property(puff, "scale", Vector3.ONE * r * 1.3, life).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(puff, "position", dir * spread + Vector3(0.0, 0.25, 0.0), life) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(puff, "scale", Vector3.ONE * 0.02, 0.25).set_delay(life - 0.25) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_cleanup(root, longest + 0.05)


static func _fx_root(at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	Game.spawn(root, at)
	return root


static func _cleanup(root: Node3D, after: float) -> void:
	if not is_instance_valid(root) or not root.is_inside_tree():
		return
	var tw := root.create_tween()
	tw.tween_interval(after)
	tw.tween_callback(root.queue_free)


## Low-poly sphere for translucent puffs (cheap, the softness comes from the alpha).
static func _soft_sphere() -> SphereMesh:
	if not _soft_meshes.has(&"puff"):
		var m := SphereMesh.new()
		m.radius = 0.5
		m.height = 1.0
		m.radial_segments = 12
		m.rings = 6
		_soft_meshes[&"puff"] = m
	return _soft_meshes[&"puff"]
