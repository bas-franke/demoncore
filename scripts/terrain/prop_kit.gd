class_name PropKit
## Procedural environment prop kit for both realms, built from code with PropBuilder (no imported
## models). Every builder takes a seeded RandomNumberGenerator, is deterministic for that seed, and
## returns a new Node3D (origin on the ground, +Y up, random yaw) holding:
##   - a few MeshInstance3Ds with static lit materials (Art.mat(flashable = false), so they get the
##     occluder fade, cloud shadows and triplanar surface detail like the rest of the scenery)
##   - when `collide` is true: a StaticBody3D "Collision" on layer 1 (blocks player + enemies)
##
##   var rng := RandomNumberGenerator.new(); rng.seed = 42
##   add_child(PropKit.build(&"golden_gate", rng))
##   var spire := PropKit.obsidian_spire(rng, false)     # visual only, no collision
##
## Same conventions as Props (so decor.gd and TerrainPatch can merge / cap them):
##   - MeshInstance3Ds with meta `keep` are never merged (flames, lava, stained glass: custom shaders)
##   - OmniLight3Ds carry meta `base_energy` (+ optional `pulse`); decor.gd / TerrainPatch cap them
##   - `footprint` meta on the root = radius (m) the prop occupies, for spacing in scatter tools
##
## Holy realms:  marble_column, broken_statue, cloud_platform, cloud_bank, golden_gate,
##               stained_window, chapel, holy_grave, holy_brazier
## Basecamp Hell: obsidian_spire, lava_pool, bone_heap, chain_posts, hell_brazier, brimstone_rock,
##               basalt_columns, impaler_spikes
## Map sites (SiteProps, scripts/terrain/site_props.gd): see SiteProps.NAMES.
##
## Caching: build() keeps VARIANTS pre-built variants per prop (fixed seeds, packed into a
## PackedScene the first time each is needed) and returns an instance of one of them with a random
## yaw: ~0.05-0.2 ms instead of 1-20 ms, and every instance of a variant shares its meshes (so
## Scatter can turn them into MultiMeshes). build_fresh() always generates a new unique prop.

const FLAME_SHADER := preload("res://shaders/flame.gdshader")
const LAVA_SHADER := preload("res://shaders/terrain/lava.gdshader")
const GLASS_SHADER := preload("res://shaders/terrain/stained_glass.gdshader")

const HOLY: Array[StringName] = [&"marble_column", &"broken_statue", &"cloud_platform", &"cloud_bank",
		&"golden_gate", &"stained_window", &"chapel", &"holy_grave", &"holy_brazier"]
const HELL: Array[StringName] = [&"obsidian_spire", &"lava_pool", &"bone_heap", &"chain_posts",
		&"hell_brazier", &"brimstone_rock", &"basalt_columns", &"impaler_spikes"]

## Default footprint radius per prop (m), used for spacing when scattering.
const FOOTPRINT := {
	&"marble_column": 1.0, &"broken_statue": 1.1, &"cloud_platform": 3.2, &"cloud_bank": 2.0,
	&"golden_gate": 3.0, &"stained_window": 2.0, &"chapel": 6.5, &"holy_grave": 0.8,
	&"holy_brazier": 0.7, &"obsidian_spire": 1.6, &"lava_pool": 2.6, &"bone_heap": 1.3,
	&"chain_posts": 2.2, &"hell_brazier": 0.8, &"brimstone_rock": 1.4, &"basalt_columns": 1.8,
	&"impaler_spikes": 1.0,
}

const HOLY_LIGHT := Color(1.0, 0.86, 0.6)
const HELL_LIGHT := Color(1.0, 0.25, 0.08)
const LAVA_LIGHT := Color(1.0, 0.36, 0.1)

## Pre-built variants kept per prop by build(); set use_cache = false to always build fresh.
const VARIANTS := 6
## Props drawn this far (m) from the camera at most (fade over the last VIS_FADE metres). The game
## camera sees ~45 m; overview / editor cameras further out simply see the ground under them.
const VIS_RANGE := 110.0
## Hysteresis margin (m) of the visibility range.
const VIS_FADE := 8.0

static var use_cache := true
static var _cache := {}
static var _templates := {}  # "prop|variant" -> PackedScene


static func has(prop: StringName) -> bool:
	return HOLY.has(prop) or HELL.has(prop) or SiteProps.has(prop)


static func footprint(prop: StringName) -> float:
	if SiteProps.has(prop):
		return SiteProps.footprint(prop)
	return float(FOOTPRINT.get(prop, 1.0))


## A prop by name: an instance of one of VARIANTS cached variants (picked and yawed with `rng`).
## Deterministic for the rng state. `collide` false drops the StaticBody3D.
static func build(prop: StringName, rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	if not use_cache:
		return build_fresh(prop, rng, collide)
	var v := rng.randi() % VARIANTS
	var yaw := rng.randf() * TAU
	var key := "%s|%d" % [prop, v]
	var ps: PackedScene = _templates.get(key)
	if ps == null:
		ps = _make_template(prop, key)
		_templates[key] = ps
	var n := ps.instantiate() as Node3D
	n.rotation.y = yaw
	if not collide:
		var body := n.get_node_or_null(^"Collision")
		if body:
			n.remove_child(body)
			body.free()
	return n


static func _make_template(prop: StringName, key: String) -> PackedScene:
	var r := RandomNumberGenerator.new()
	r.seed = hash(key)
	var root := build_fresh(prop, r, true)
	root.rotation = Vector3.ZERO
	_set_vis_range(root)
	_own(root, root)
	var ps := PackedScene.new()
	ps.pack(root)
	root.free()
	return ps


## PackedScene.pack only stores nodes owned by the root.
static func _own(n: Node, root: Node) -> void:
	for c in n.get_children():
		c.owner = root
		_own(c, root)


static func _set_vis_range(n: Node) -> void:
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		g.visibility_range_end = VIS_RANGE
		g.visibility_range_end_margin = VIS_FADE
		# hysteresis only (fading would push opaque custom shaders into the transparent pipeline)
		g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	for c in n.get_children():
		_set_vis_range(c)


## Clears the visibility ranges under `root` (overview / screenshot cameras far above the map).
static func clear_visibility_ranges(root: Node) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).visibility_range_end = 0.0
	for c in root.get_children():
		clear_visibility_ranges(c)


## Generates a brand-new prop (no cache): unique geometry, 1-20 ms.
static func build_fresh(prop: StringName, rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	if SiteProps.has(prop):
		return SiteProps.build(prop, rng, collide)
	match prop:
		&"marble_column": return marble_column(rng, collide)
		&"broken_statue": return broken_statue(rng, collide)
		&"cloud_platform": return cloud_platform(rng, 3.0)
		&"cloud_bank": return cloud_bank(rng, collide)
		&"golden_gate": return golden_gate(rng, collide)
		&"stained_window": return stained_window(rng, collide)
		&"chapel": return chapel(rng, collide)
		&"holy_grave": return holy_grave(rng, collide)
		&"holy_brazier": return holy_brazier(rng, collide)
		&"obsidian_spire": return obsidian_spire(rng, collide)
		&"lava_pool": return lava_pool(rng, collide)
		&"bone_heap": return bone_heap(rng, collide)
		&"chain_posts": return chain_posts(rng, collide)
		&"hell_brazier": return hell_brazier(rng, collide)
		&"brimstone_rock": return brimstone_rock(rng, collide)
		&"basalt_columns": return basalt_columns(rng, collide)
		&"impaler_spikes": return impaler_spikes(rng, collide)
	push_warning("PropKit.build: unknown prop %s" % prop)
	return Node3D.new()


# ================================================================ materials (cached)

static func marble() -> ShaderMaterial:
	return Art.mat(Color(0.8, 0.78, 0.74), 0.42, 0.0, 0.3, false, 0.0, &"marble")


static func marble_old() -> ShaderMaterial:
	return Props.mat(Color(0.7, 0.68, 0.63), 0.55, 0.0, 0.55, 0.35, 0.0, &"marble")


static func gold() -> ShaderMaterial:
	return Art.mat(Art.GOLD, 0.32, 0.95, 0.2, false, 0.0, &"gold")


static func cloud() -> ShaderMaterial:
	if not _cache.has(&"cloud"):
		var m := Art.mat(Color(0.93, 0.92, 0.96), 1.0, 0.0, 0.0, false, 0.9).duplicate() as ShaderMaterial
		m.set_shader_parameter(&"contact_dark", 0.0)
		# faint warm self-light so cloud undersides don't go grey
		m.set_shader_parameter(&"emission", Color(1.0, 0.93, 0.82))
		m.set_shader_parameter(&"emission_energy", 0.12)
		_cache[&"cloud"] = m
	return _cache[&"cloud"]


static func slate() -> ShaderMaterial:
	return Art.mat(Color(0.2, 0.21, 0.25), 0.7, 0.0, 0.5, false, 0.0, &"stone")


static func obsidian() -> ShaderMaterial:
	return Art.mat(Color(0.03, 0.026, 0.035), 0.14, 0.0, 0.2, false, 0.0, &"crystal")


static func basalt() -> ShaderMaterial:
	return Art.mat(Color(0.2, 0.18, 0.17), 0.88, 0.0, 0.5, false, 0.0, &"stone")


static func hellstone() -> ShaderMaterial:
	return Art.mat(Color(0.3, 0.13, 0.1), 0.9, 0.0, 0.55, false, 0.0, &"stone")


## Weathered ash-grey stone for the sun-bleached tops of basalt columns.
static func basalt_top() -> ShaderMaterial:
	return Art.mat(Color(0.36, 0.33, 0.31), 0.9, 0.0, 0.4, false, 0.0, &"stone")


## Rusted wrought iron (chain posts, cages): readable against dark ground unlike black iron.
static func rust_iron() -> ShaderMaterial:
	return Art.mat(Color(0.3, 0.19, 0.13), 0.7, 0.55, 0.6, false, 0.0, &"rust")


## Dimmer magma for ground seams (the full magma() is for veins and coals).
static func magma_dim() -> ShaderMaterial:
	return Art.emissive(Color(0.1, 0.02, 0.01), Art.HELLFIRE, 1.8, 0.7, false)


static func magma() -> ShaderMaterial:
	return Art.emissive(Color(0.12, 0.02, 0.01), Art.HELLFIRE, 4.5, 0.6, false)


static func sulfur() -> ShaderMaterial:
	return Art.emissive(Color(0.78, 0.64, 0.15), Color(1.0, 0.7, 0.15), 0.3, 0.6, false)


static func iron() -> ShaderMaterial:
	return Props.iron_mat()


static func bone() -> ShaderMaterial:
	return Props.bone_mat()


static func void_mat() -> ShaderMaterial:
	return Art.mat(Color(0.015, 0.012, 0.012), 1.0, 0.0, 0.0, false)


static func flame_mat(hell: bool) -> ShaderMaterial:
	var key := &"flame_hell" if hell else &"flame_holy"
	if not _cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = FLAME_SHADER
		if hell:
			m.set_shader_parameter(&"core_color", Color(1.0, 0.62, 0.35))
			m.set_shader_parameter(&"mid_color", Color(1.0, 0.16, 0.04))
			m.set_shader_parameter(&"edge_color", Color(0.4, 0.02, 0.06))
			m.set_shader_parameter(&"energy", 3.6)
		else:
			m.set_shader_parameter(&"core_color", Color(1.0, 1.0, 0.92))
			m.set_shader_parameter(&"mid_color", Color(1.0, 0.82, 0.42))
			m.set_shader_parameter(&"edge_color", Color(0.65, 0.42, 0.12))
			m.set_shader_parameter(&"energy", 2.8)
		_cache[key] = m
	return _cache[key]


static func lava_mat() -> ShaderMaterial:
	if not _cache.has(&"lava"):
		var m := ShaderMaterial.new()
		m.shader = LAVA_SHADER
		_cache[&"lava"] = m
	return _cache[&"lava"]


static func glass_mat(broken: bool) -> ShaderMaterial:
	var key := &"glass_broken" if broken else &"glass"
	if not _cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = GLASS_SHADER
		m.set_shader_parameter(&"broken", 0.45 if broken else 0.0)
		_cache[key] = m
	return _cache[key]


# ================================================================ helpers

static func _root(rng: RandomNumberGenerator, prop: StringName, yaw: bool = true) -> Node3D:
	var r := Node3D.new()
	r.name = String(prop).to_pascal_case()
	if yaw:
		r.rotation.y = rng.randf() * TAU
	r.set_meta(&"footprint", footprint(prop))
	r.set_meta(&"prop", prop)
	return r


static func _at(pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> Transform3D:
	# local scale first, then rotation
	return Transform3D(Basis.from_euler(rot) * Basis.from_scale(scl), pos)


## Finishes the builder into `root`, dropping collision if not wanted; marks custom-shader meshes keep.
static func _done(b: PropBuilder, root: Node3D, collide: bool) -> Node3D:
	if not collide:
		b._shapes.clear()
	b.finish(root)
	for c in root.get_children():
		if c is MeshInstance3D:
			var m := (c as MeshInstance3D).material_override
			if m is ShaderMaterial and (m as ShaderMaterial).shader in [FLAME_SHADER, LAVA_SHADER, GLASS_SHADER]:
				c.set_meta(&"keep", true)
				(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


## Billboard flame quads (one MeshInstance3D each: the shader billboards around the node origin).
static func _flames(root: Node3D, hell: bool, at: Vector3, size: float) -> void:
	var offs := [Vector3.ZERO, Vector3(0.14, -0.03, 0.06), Vector3(-0.12, -0.03, -0.05)]
	var sizes := [Vector2(1.0, 1.7), Vector2(0.6, 1.0), Vector2(0.55, 0.9)]
	for i in 3:
		var q := QuadMesh.new()
		q.size = (sizes[i] as Vector2) * size
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = flame_mat(hell)
		mi.position = at + (offs[i] as Vector3) * size + Vector3(0, q.size.y * 0.5, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 1.0
		mi.set_meta(&"keep", true)
		root.add_child(mi)


static func _light(root: Node3D, color: Color, energy: float, rng_: float, pos: Vector3, pulse: bool = false) -> OmniLight3D:
	var l := Art.light(root, color, energy, rng_, pos)
	l.omni_attenuation = 1.4
	l.light_specular = 0.3
	l.light_volumetric_fog_energy = 1.6
	l.set_meta(&"base_energy", energy)
	if pulse:
		l.set_meta(&"pulse", true)
	return l


## Gothic pointed-arch outline (matches stained_glass.gdshader): points from the right spring line
## over the apex to the left spring line, in metres. Window `w` wide, arch part `h` tall
## (h = 0.38 * glass height), apex at `top`.
static func arch_curve(w: float, glass_h: float, top: float, steps: int = 10) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps + 1:
		var cx := 0.5 - float(i) / float(steps)  # +0.5 (right) .. -0.5 (left), uv units
		var side := signf(cx) if absf(cx) > 1e-4 else 1.0
		var dx := cx + side * 0.35
		var yuv := 0.38 - sqrt(maxf(0.7225 - dx * dx, 0.0)) / 2.04
		pts.append(Vector2(cx * w, top - yuv * glass_h))
	return pts


# ================================================================ holy realm

## Fluted marble column on a plinth with a gilded band. 35% are broken off, with fallen drums and
## the capital lying beside them.
static func marble_column(rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	var root := _root(rng, &"marble_column")
	var b := PropBuilder.new()
	var m := marble() if rng.randf() < 0.5 else marble_old()
	var h := 4.2 * rng.randf_range(0.9, 1.1)
	var broken := rng.randf() < 0.35
	var shaft_top := rng.randf_range(1.2, 2.8) if broken else h
	b.box(m, Vector3(1.3, 0.3, 1.3), _at(Vector3(0, 0.15, 0)))
	b.lathe(m, PackedVector2Array([Vector2(0.6, 0.3), Vector2(0.62, 0.38), Vector2(0.54, 0.47), Vector2(0.5, 0.53)]), 24)
	var flutes := func(a: float, _t: float) -> float:
		return 1.0 - 0.07 * pow(1.0 - absf(sin(a * 8.0)), 4.0)
	var prof := PackedVector2Array()
	for i in 6:
		var t := float(i) / 5.0
		prof.append(Vector2(lerpf(0.46, 0.4, t) * (1.0 + 0.03 * sin(t * PI)), lerpf(0.53, shaft_top, t)))
	b.lathe(m, prof, 48, Transform3D.IDENTITY, true, flutes)
	b.torus(gold(), 0.47, 0.035, 24, 6, _at(Vector3(0, 0.9, 0)))
	if broken:
		# jagged break: a few tilted shards on the top face
		for i in 4:
			var a := rng.randf() * TAU
			b.spike(m, rng.randf_range(0.15, 0.25), rng.randf_range(0.2, 0.45), 4,
					_at(Vector3(cos(a) * 0.22, shaft_top - 0.05, sin(a) * 0.22), Vector3(rng.randf_range(-0.3, 0.3), a, rng.randf_range(-0.3, 0.3))))
		# fallen drums and the capital on the ground
		var dir := rng.randf() * TAU
		for i in rng.randi_range(1, 2):
			var d := 1.4 + float(i) * 1.0
			var p := Vector3(cos(dir) * d, 0.4, sin(dir) * d)
			var xf := _at(p, Vector3(0, dir + rng.randf_range(-0.4, 0.4), PI * 0.5)) * Transform3D(Basis(), Vector3(0, -0.45, 0))
			b.lathe(m, PackedVector2Array([Vector2(0.42, 0), Vector2(0.41, 0.9)]), 32, xf, true, flutes)
			b.collide_box(Vector3(0.9, 0.8, 0.8), _at(p, Vector3(0, dir, 0)))
		var cp := Vector3(cos(dir + 0.9) * 1.5, 0.2, sin(dir + 0.9) * 1.5)
		b.box(m, Vector3(1.2, 0.25, 1.2), _at(cp + Vector3(0, -0.07, 0), Vector3(0.15, rng.randf() * TAU, 0.1)))
	else:
		b.lathe(m, PackedVector2Array([Vector2(0.41, h), Vector2(0.48, h + 0.15), Vector2(0.62, h + 0.32)]), 24)
		b.box(m, Vector3(1.35, 0.22, 1.35), _at(Vector3(0, h + 0.43, 0)))
		b.torus(gold(), 0.5, 0.04, 24, 6, _at(Vector3(0, h + 0.12, 0)))
	b.collide_cylinder(0.6, shaft_top + 0.5)
	return _done(b, root, collide)


## Saint / angel statue on a plinth: draped robe, hands in prayer, wings and a gold halo. Half of
## them are desecrated: head knocked off (lying at the foot), one wing snapped, halo cracked.
static func broken_statue(rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	var root := _root(rng, &"broken_statue")
	var b := PropBuilder.new()
	var m := marble_old()
	var stone := Props.stone_mat(rng)
	var broken := rng.randf() < 0.5
	# plinth with a cornice
	b.box(stone, Vector3(1.3, 0.9, 1.3), _at(Vector3(0, 0.45, 0)))
	b.box(stone, Vector3(1.45, 0.15, 1.45), _at(Vector3(0, 0.95, 0)))
	var base := 1.02
	# robe: lathe with drapery folds
	var folds := func(a: float, t: float) -> float:
		return 1.0 + 0.09 * sin(a * 7.0 + t * 2.0) * (1.0 - t * 0.7)
	b.lathe(m, PackedVector2Array([Vector2(0.48, base), Vector2(0.42, base + 0.5), Vector2(0.32, base + 1.1),
			Vector2(0.27, base + 1.5), Vector2(0.3, base + 1.62), Vector2(0.1, base + 1.75)]), 20,
			Transform3D.IDENTITY, true, folds)
	# arms down the front to praying hands
	for s: float in [-1.0, 1.0]:
		b.tube(m, PackedVector3Array([Vector3(0.3 * s, base + 1.55, 0.0), Vector3(0.33 * s, base + 1.25, 0.12),
				Vector3(0.1 * s, base + 1.15, 0.32), Vector3(0.02 * s, base + 1.3, 0.36)]), 0.075, 6)
	b.spike(m, 0.07, 0.26, 4, _at(Vector3(0, base + 1.24, 0.37), Vector3(0.2, 0, 0)))
	# head (or neck stump)
	var head_pos := Vector3(0, base + 1.95, 0.02)
	if broken:
		b.cylinder(m, 0.09, 0.08, 0.12, 8, _at(Vector3(0, base + 1.72, 0)), true, true)
		var a := rng.randf() * TAU
		var hp := Vector3(cos(a) * 1.0, 0.17, sin(a) * 1.0)
		b.blob(m, 0.17, rng, _at(hp, Vector3(rng.randf(), rng.randf(), 0)), 0.06, 1, false)
	else:
		b.cylinder(m, 0.08, 0.07, 0.15, 8, _at(Vector3(0, base + 1.72, 0)))
		b.blob(m, 0.17, rng, _at(head_pos, Vector3.ZERO, Vector3(0.9, 1.1, 0.95)), 0.04, 1, false)
	# halo: closed ring or a cracked arc
	var halo_xf := _at(head_pos + Vector3(0, 0.1, -0.2), Vector3(PI * 0.5 - 0.15, 0, 0))
	b.torus(gold(), 0.3, 0.03, 28, 5, halo_xf, true, TAU * (0.62 if broken else 1.0))
	# wings: scalloped slabs swept back
	for s: float in [-1.0, 1.0]:
		var is_snapped := broken and s > 0.0
		var poly := PackedVector2Array()
		var span := 0.75 if is_snapped else 1.45
		poly.append(Vector2(0, 0))
		poly.append(Vector2(0.25 * span, 0.55))
		poly.append(Vector2(0.75 * span, 0.75))
		poly.append(Vector2(span, 0.55))
		# scalloped trailing edge (feathers)
		var n := 5
		for i in n + 1:
			var t := float(i) / float(n)
			var x := lerpf(span, 0.1, t)
			var y := lerpf(0.55, -0.9 + 0.5 * t, t) - (0.08 if i % 2 == 1 else 0.0)
			poly.append(Vector2(x, y))
		if is_snapped:
			poly = PackedVector2Array([Vector2(0, 0), Vector2(0.2, 0.45), Vector2(0.62, 0.62), Vector2(0.72, 0.1),
					Vector2(0.5, -0.05), Vector2(0.58, -0.3), Vector2(0.2, -0.45)])
		# wing span runs along local +x: yaw it back, mirror it for the left wing
		var xf := _at(Vector3(0.12 * s, base + 1.35, -0.25), Vector3(0, 0.5 * s, 0), Vector3(s, 1, 1))
		b.slab(m, poly, 0.08, xf)
		if is_snapped:
			# the broken-off wing tip lies on the ground
			var a2 := rng.randf() * TAU
			b.slab(m, PackedVector2Array([Vector2(0, 0), Vector2(0.7, 0.2), Vector2(0.9, -0.4), Vector2(0.2, -0.6)]), 0.08,
					_at(Vector3(cos(a2) * 1.2, 0.05, sin(a2) * 1.2), Vector3(-PI * 0.5, a2, 0)))
	b.collide_box(Vector3(1.4, 3.0, 1.4), _at(Vector3(0, 1.5, 0)))
	return _done(b, root, collide)


## Floating cloud island to stand on: flat walkable top at y = 0 (radius `radius`), billowing puffs
## around the rim and underneath. No collision (walkable; edges are the map's job, see TerrainPatch).
static func cloud_platform(rng: RandomNumberGenerator, radius: float = 3.0) -> Node3D:
	var root := _root(rng, &"cloud_platform")
	root.set_meta(&"footprint", radius + 0.4)
	var b := PropBuilder.new()
	var c := cloud()
	# walkable top disc (slightly domed so the edge rolls into the puffs)
	b.lathe(c, PackedVector2Array([Vector2(radius, -0.12), Vector2(radius * 0.7, -0.02), Vector2(0.0, 0.0)]), 32,
			Transform3D.IDENTITY, false)
	var n := int(radius * 4.0)
	for i in n:
		var a := TAU * float(i) / float(n) + rng.randf_range(-0.1, 0.1)
		var r := radius * rng.randf_range(0.85, 1.05)
		var s := rng.randf_range(0.5, 0.85) * clampf(radius / 3.0, 0.6, 1.4)
		b.blob(c, s, rng, _at(Vector3(cos(a) * r, -0.25, sin(a) * r)), 0.18, 1, false, false, 0.6)
	for i in int(radius * 2.0):
		var a := rng.randf() * TAU
		var r := rng.randf() * radius * 0.7
		b.blob(c, rng.randf_range(0.8, 1.3), rng, _at(Vector3(cos(a) * r, -1.0, sin(a) * r)), 0.2, 1, false, false, 0.55)
	return _done(b, root, false)


## Low bank of solid cloud sitting on the ground (blocking scenery for the heavens).
static func cloud_bank(rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	var root := _root(rng, &"cloud_bank")
	var b := PropBuilder.new()
	var c := cloud()
	var count := rng.randi_range(4, 7)
	for i in count:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 1.2)
		var s := rng.randf_range(0.6, 1.1) * (1.3 if i == 0 else 1.0)
		b.blob(c, s, rng, _at(Vector3(cos(a) * r, s * 0.45, sin(a) * r)), 0.2, 1, false, true, 0.75)
	b.collide_cylinder(1.6, 1.6)
	return _done(b, root, collide)


## Pearly golden gates between two marble pillars: barred leaves under an arched sunburst. 40% are
## thrown open (passable between the pillars).
static func golden_gate(rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	var root := _root(rng, &"golden_gate")
	var b := PropBuilder.new()
	var m := marble()
	var g := gold()
	var half := 2.0  # half the opening width
	var open := rng.randf() < 0.4
	for s: float in [-1.0, 1.0]:
		var x := s * (half + 0.4)
		b.box(m, Vector3(0.9, 0.35, 0.9), _at(Vector3(x, 0.17, 0)))
		b.box(m, Vector3(0.7, 3.4, 0.7), _at(Vector3(x, 2.0, 0)))
		b.box(m, Vector3(0.9, 0.25, 0.9), _at(Vector3(x, 3.8, 0)))
		b.blob(g, 0.26, rng, _at(Vector3(x, 4.2, 0)), 0.0, 1, false)
		b.spike(g, 0.08, 0.5, 6, _at(Vector3(x, 4.35, 0)))
		b.collide_box(Vector3(0.9, 4.0, 0.9), _at(Vector3(x, 2.0, 0)))
		# one gate leaf, hinged at the pillar
		var hinge := Vector3(s * half, 0.0, 0.0)
		var swing := (s * 1.25) if open else 0.0
		var leaf := Transform3D(Basis(Vector3.UP, swing), hinge)
		var bars := 7
		for i in bars:
			var lx := -s * (0.14 + float(i) * (half - 0.2) / float(bars - 1))
			var top := 2.6 + 0.9 * sin(PI * 0.5 * absf(lx) / half)  # rises toward the centre
			b.cylinder(g, 0.035, 0.035, top - 0.15, 6, leaf * _at(Vector3(lx, 0.15, 0)))
			b.spike(g, 0.06, 0.22, 4, leaf * _at(Vector3(lx, top, 0)))
		for y: float in [0.35, 1.4, 2.5]:
			b.box(g, Vector3(half - 0.1, 0.07, 0.07), leaf * _at(Vector3(-s * half * 0.5, y, 0)))
		# scroll-work curls between the lower rails
		for i in 2:
			var cx := -s * (0.5 + float(i) * 0.9)
			b.torus(g, 0.22, 0.025, 16, 5, leaf * _at(Vector3(cx, 0.88, 0), Vector3(PI * 0.5, 0, 0)), true, TAU * 0.8)
	# arched crown with a sunburst
	# torus arcs start at +x and sweep toward +z; tilting by -90 deg about x makes them rise
	b.torus(g, half + 0.35, 0.06, 32, 6, _at(Vector3(0, 3.6, 0), Vector3(-PI * 0.5, 0, 0)), true, PI)
	for i in 9:
		var a := PI * (0.1 + 0.8 * float(i) / 8.0)
		var p := Vector3(cos(a) * (half + 0.35), 3.6 + sin(a) * (half + 0.35), 0)
		b.spike(g, 0.05, 0.45 if i % 2 == 0 else 0.3, 4, _at(p, Vector3(0, 0, a - PI * 0.5)))
	b.blob(g, 0.3, rng, _at(Vector3(0, 3.6 + half + 0.45, 0)), 0.0, 1, false)
	if not open:
		b.collide_box(Vector3(half * 2.0, 3.0, 0.3), _at(Vector3(0, 1.5, 0)))
	return _done(b, root, collide)


## Freestanding ruined cathedral wall with a back-lit stained-glass lancet window. A third are
## shattered (jagged wall top, missing shards).
static func stained_window(rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	var root := _root(rng, &"stained_window")
	var b := PropBuilder.new()
	var stone := Props.stone_mat(rng) if rng.randf() < 0.5 else marble_old()
	var broken := rng.randf() < 0.33
	var W := 3.4
	var depth := 0.5
	var w := 1.4  # glass width
	var gh := 2.9  # glass height
	var sill := 1.0
	var top := sill + gh
	var wall_top := top + 0.8
	var spring := top - 0.38 * gh
	# side walls
	for s: float in [-1.0, 1.0]:
		var x0 := s * w * 0.5
		var x1 := s * W * 0.5
		var poly := PackedVector2Array([Vector2(x0, 0), Vector2(x1, 0), Vector2(x1, wall_top), Vector2(x0, wall_top)])
		if broken and s > 0.0:
			poly = PackedVector2Array([Vector2(x0, 0), Vector2(x1, 0), Vector2(x1, wall_top - 1.6),
					Vector2(lerpf(x0, x1, 0.6), wall_top - 1.0), Vector2(lerpf(x0, x1, 0.3), wall_top - 0.3), Vector2(x0, spring)])
		b.slab(stone, poly, depth)
	# sill and the spandrel over the pointed arch
	b.box(stone, Vector3(w + 0.02, sill, depth), _at(Vector3(0, sill * 0.5, 0)))
	b.box(stone, Vector3(w + 0.3, 0.12, depth + 0.16), _at(Vector3(0, sill, 0)))
	var spandrel := arch_curve(w * 1.01, gh, top)
	var tip_y := wall_top if not broken else top + 0.25
	spandrel.append(Vector2(-w * 0.5 - 0.01, tip_y))
	spandrel.append(Vector2(w * 0.5 + 0.01, tip_y - (0.5 if broken else 0.0)))
	b.slab(stone, spandrel, depth)
	# moulding around the opening (thin tube following the arch)
	var mould := PackedVector3Array()
	mould.append(Vector3(w * 0.5, sill, depth * 0.5))
	for p in arch_curve(w, gh, top, 12):
		mould.append(Vector3(p.x, p.y, depth * 0.5))
	mould.append(Vector3(-w * 0.5, sill, depth * 0.5))
	b.tube(stone, mould, 0.06, 5)
	# coping stone
	if not broken:
		b.box(stone, Vector3(W + 0.15, 0.2, depth + 0.15), _at(Vector3(0, wall_top + 0.1, 0)))
	b.quad(glass_mat(broken), Vector2(w, gh), _at(Vector3(0, sill + gh * 0.5, 0)))
	b.collide_box(Vector3(W, wall_top, depth + 0.1), _at(Vector3(0, wall_top * 0.5, 0)))
	var root2 := _done(b, root, collide)
	# warm glow spilling from the window onto the ground in front
	if not broken or rng.randf() < 0.5:
		_light(root2, HOLY_LIGHT, 0.8, 5.0, Vector3(0, 2.0, 1.2), true)
	return root2


## Small gothic chapel (walkable inside through the door, which faces local +z): walls with
## stained-glass windows, slate gable roof, bell tower on a back corner with a gilded spire and an
## altar with holy candles. 40% are ruined (roof
## caved in, a wall fallen into rubble).
static func chapel(rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	var root := _root(rng, &"chapel")
	var b := PropBuilder.new()
	var stone := Props.stone_mat(rng)
	var m := marble()
	var ruined := rng.randf() < 0.4
	var hw := 3.0   # half width (x)
	var hl := 4.5   # half length (z); door faces +z
	var wall_h := 4.2
	var t := 0.4
	# long side walls (x = +-hw) with two window niches each
	for s: float in [-1.0, 1.0]:
		var fallen := ruined and s > 0.0
		var h := wall_h if not fallen else 1.4
		b.box(stone, Vector3(t, h, hl * 2.0), _at(Vector3(s * hw, h * 0.5, 0)))
		b.collide_box(Vector3(t, 4.0, hl * 2.0), _at(Vector3(s * hw, 2.0, 0)))
		if not fallen:
			for z: float in [-2.0, 1.2]:
				b.quad(glass_mat(ruined), Vector2(1.0, 2.2), _at(Vector3(s * (hw + t * 0.5 + 0.01), 2.3, z), Vector3(0, s * PI * 0.5, 0)))
				b.quad(glass_mat(ruined), Vector2(1.0, 2.2), _at(Vector3(s * (hw - t * 0.5 - 0.01), 2.3, z), Vector3(0, -s * PI * 0.5, 0)))
			# buttresses
			for z: float in [-hl + 0.3, -0.4, hl - 0.3]:
				b.prism(stone, PackedVector2Array([Vector2(0, -0.3), Vector2(0.7, -0.3), Vector2(0.7, 0.3), Vector2(0, 0.3)]), 0.0, 3.0,
						_at(Vector3(s * hw, 0, z), Vector3(0, 0.0 if s > 0.0 else PI, 0)))
				b.spike(stone, 0.32, 0.9, 4, _at(Vector3(s * (hw + 0.35), 3.0, z), Vector3(0, PI * 0.25, 0)))
		else:
			for i in 7:
				b.blob(stone, rng.randf_range(0.3, 0.6), rng, _at(Vector3(s * (hw + rng.randf_range(0.2, 1.8)), 0.15, rng.randf_range(-hl, hl))), 0.3, 0, true, true, 0.6, true)
	# back wall with a rose window
	b.box(stone, Vector3(hw * 2.0 + t, wall_h, t), _at(Vector3(0, wall_h * 0.5, -hl)))
	b.collide_box(Vector3(hw * 2.0 + t, 4.0, t), _at(Vector3(0, 2.0, -hl)))
	b.quad(glass_mat(false), Vector2(1.6, 2.6), _at(Vector3(0, 2.4, -hl + t * 0.5 + 0.01)))
	# front wall with the door gap (1.8 m)
	var dw := 0.9
	for s: float in [-1.0, 1.0]:
		var ww := hw - dw
		b.box(stone, Vector3(ww + t * 0.5, wall_h, t), _at(Vector3(s * (dw + (ww + t * 0.5) * 0.5), wall_h * 0.5, hl)))
		b.collide_box(Vector3(ww + t * 0.5, 4.0, t), _at(Vector3(s * (dw + (ww + t * 0.5) * 0.5), 2.0, hl)))
	b.box(stone, Vector3(dw * 2.0, wall_h - 2.6, t), _at(Vector3(0, 2.6 + (wall_h - 2.6) * 0.5, hl)))
	# gable ends (triangles) + roof
	var gable_h := 2.4
	var tri := PackedVector2Array([Vector2(-hw - t * 0.5, 0), Vector2(hw + t * 0.5, 0), Vector2(0, gable_h)])
	b.slab(stone, tri, t, _at(Vector3(0, wall_h, hl)))
	b.slab(stone, tri, t, _at(Vector3(0, wall_h, -hl)))
	var slope := Vector2(hw + 0.5, gable_h + 0.35).length()
	var ang := atan2(gable_h + 0.35, hw + 0.5)
	for s: float in [-1.0, 1.0]:
		var roof_len := hl * 2.0 + 0.6
		if ruined and s > 0.0:
			# caved-in half: a few rafters left
			for i in 4:
				b.box(Props.mat(Props.WOOD, 0.9, 0.0, 0.5, 0.0, 0.0, &"wood"), Vector3(slope, 0.15, 0.15),
						_at(Vector3(s * (hw + 0.5) * 0.5, wall_h + (gable_h + 0.35) * 0.5 - 0.15, -hl + 1.0 + float(i) * 2.2),
						Vector3(0, 0, -s * ang)))
			continue
		var xf := _at(Vector3(s * (hw + 0.5) * 0.5, wall_h + (gable_h + 0.35) * 0.5 - 0.15, 0), Vector3(0, 0, -s * ang))
		b.box(slate(), Vector3(slope + 0.1, 0.18, roof_len), xf)
	if not ruined:
		b.box(gold(), Vector3(0.1, 0.1, hl * 2.0 + 0.6), _at(Vector3(0, wall_h + gable_h + 0.25, 0), Vector3(0, 0, PI * 0.25)))
	# bell tower over the door
	var tower_h := 7.5
	# tower on the back corner (north side, away from the door and the camera)
	var tc := Vector3(-hw + 0.8, 0.0, -hl - 0.8)
	b.box(stone, Vector3(2.0, tower_h, 2.0), _at(tc + Vector3(0, tower_h * 0.5, 0)))
	b.collide_box(Vector3(2.0, 4.0, 2.0), _at(tc + Vector3(0, 2.0, 0)))
	# open belfry (4 corner posts) + bell
	for cx: float in [-0.85, 0.85]:
		for cz: float in [-0.85, 0.85]:
			b.box(stone, Vector3(0.3, 1.6, 0.3), _at(tc + Vector3(cx, tower_h + 0.8, cz)))
	b.lathe(bronze(), PackedVector2Array([Vector2(0.45, tower_h + 0.4), Vector2(0.35, tower_h + 0.7), Vector2(0.25, tower_h + 1.2), Vector2(0.0, tower_h + 1.3)]), 14,
			_at(tc))
	b.box(stone, Vector3(2.2, 0.25, 2.2), _at(tc + Vector3(0, tower_h + 1.7, 0)))
	if not ruined:
		b.spike(slate(), 1.2, 3.2, 4, _at(tc + Vector3(0, tower_h + 1.82, 0), Vector3(0, PI * 0.25, 0)))
		var ct := tc + Vector3(0, tower_h + 5.0, 0)
		b.box(gold(), Vector3(0.1, 0.9, 0.1), _at(ct + Vector3(0, 0.45, 0)))
		b.box(gold(), Vector3(0.5, 0.1, 0.1), _at(ct + Vector3(0, 0.6, 0)))
	# floor slab + altar with candles inside
	b.box(m, Vector3(hw * 2.0, 0.08, hl * 2.0), _at(Vector3(0, 0.04, 0)), false)
	b.box(m, Vector3(2.0, 1.0, 0.9), _at(Vector3(0, 0.5, -hl + 1.2)))
	b.box(gold(), Vector3(2.1, 0.06, 1.0), _at(Vector3(0, 1.02, -hl + 1.2)))
	b.collide_box(Vector3(2.0, 2.0, 0.9), _at(Vector3(0, 1.0, -hl + 1.2)))
	var root2 := _done(b, root, collide)
	for x: float in [-0.7, 0.7]:
		var c := Props.candles(rng, 4)
		c.position = Vector3(x, 1.05, -hl + 1.2)
		root2.add_child(c)
	_light(root2, HOLY_LIGHT, 1.6, 7.0, Vector3(0, 2.2, -hl + 1.8), true)
	return root2


static func bronze() -> ShaderMaterial:
	return Art.mat(Color(0.5, 0.36, 0.18), 0.45, 0.9, 0.5, false, 0.0, &"gold")


## Holy-realm grave: marble cross on a stepped base, rounded stele with gilded angel wings, or a
## ledger tomb with gold trim. Optional pale flowers / candles at the foot.
static func holy_grave(rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	var root := _root(rng, &"holy_grave")
	var b := PropBuilder.new()
	var m := marble_old() if rng.randf() < 0.6 else marble()
	match rng.randi_range(0, 2):
		0:  # cross
			b.box(m, Vector3(0.8, 0.18, 0.6), _at(Vector3(0, 0.09, 0)))
			b.box(m, Vector3(0.6, 0.16, 0.45), _at(Vector3(0, 0.26, 0)))
			b.box(m, Vector3(0.16, 1.5, 0.14), _at(Vector3(0, 1.08, 0)))
			b.box(m, Vector3(0.75, 0.15, 0.14), _at(Vector3(0, 1.4, 0)))
			b.torus(gold(), 0.2, 0.022, 18, 4, _at(Vector3(0, 1.4, 0), Vector3(PI * 0.5, 0, 0)))
			b.collide_box(Vector3(0.8, 1.8, 0.6), _at(Vector3(0, 0.9, 0)))
		1:  # winged stele
			var poly := PackedVector2Array()
			poly.append(Vector2(-0.35, 0))
			poly.append(Vector2(0.35, 0))
			for i in 9:
				var a := PI * float(i) / 8.0
				poly.append(Vector2(cos(a) * 0.35, 1.0 + sin(a) * 0.35))
			b.slab(m, poly, 0.16, _at(Vector3(0, 0.12, 0)))
			b.box(m, Vector3(0.95, 0.12, 0.45), _at(Vector3(0, 0.06, 0)))
			for s: float in [-1.0, 1.0]:
				var wing := PackedVector2Array([Vector2(0, 0), Vector2(0.3, 0.12), Vector2(0.42, 0.0), Vector2(0.34, -0.12),
						Vector2(0.38, -0.22), Vector2(0.12, -0.18)])
				b.slab(gold(), wing, 0.04, _at(Vector3(0.05 * s, 1.05, 0.09), Vector3.ZERO, Vector3(s, 1, 1)))
			b.collide_box(Vector3(0.95, 1.4, 0.45), _at(Vector3(0, 0.7, 0)))
		_:  # ledger tomb
			b.box(m, Vector3(1.0, 0.45, 2.0), _at(Vector3(0, 0.22, 0)))
			b.box(m, Vector3(1.12, 0.12, 2.12), _at(Vector3(0, 0.5, 0)))
			b.box(gold(), Vector3(0.1, 0.02, 1.4), _at(Vector3(0, 0.57, 0)))
			b.box(gold(), Vector3(0.6, 0.02, 0.1), _at(Vector3(0, 0.57, -0.4)))
			b.collide_box(Vector3(1.12, 0.8, 2.12), _at(Vector3(0, 0.4, 0)))
	var root2 := _done(b, root, collide)
	if rng.randf() < 0.35:
		var c := Props.candles(rng, 3)
		c.position = Vector3(rng.randf_range(-0.3, 0.3), 0.0, 0.55)
		root2.add_child(c)
	return root2


## Gilded fire bowl on a fluted marble pedestal with a white-gold holy flame.
static func holy_brazier(rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	var root := _root(rng, &"holy_brazier")
	var b := PropBuilder.new()
	var m := marble()
	b.box(m, Vector3(0.7, 0.2, 0.7), _at(Vector3(0, 0.1, 0)))
	b.lathe(m, PackedVector2Array([Vector2(0.24, 0.2), Vector2(0.18, 0.5), Vector2(0.16, 0.95), Vector2(0.22, 1.1)]), 24,
			Transform3D.IDENTITY, true, func(a: float, _t: float) -> float: return 1.0 - 0.08 * pow(1.0 - absf(sin(a * 5.0)), 4.0))
	b.lathe(gold(), PackedVector2Array([Vector2(0.12, 1.08), Vector2(0.42, 1.22), Vector2(0.55, 1.42), Vector2(0.5, 1.44),
			Vector2(0.38, 1.3), Vector2(0.0, 1.28)]), 20)
	b.blob(Art.emissive(Color(0.3, 0.25, 0.15), Art.HOLY, 3.0, 0.5, false), 0.3, rng, _at(Vector3(0, 1.32, 0)), 0.2, 1, true, false, 0.4)
	b.collide_cylinder(0.45, 1.5)
	var root2 := _done(b, root, collide)
	_flames(root2, false, Vector3(0, 1.35, 0), 0.85)
	_light(root2, HOLY_LIGHT, 2.2, 7.0, Vector3(0, 2.1, 0))
	return root2


# ================================================================ Basecamp Hell

## Cluster of glossy volcanic-glass spikes with glowing magma shards and a molten seam at the base.
static func obsidian_spire(rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	var root := _root(rng, &"obsidian_spire")
	var b := PropBuilder.new()
	var o := obsidian()
	var main_h := rng.randf_range(4.0, 6.5)
	var main_r := rng.randf_range(0.7, 0.95)
	b.spike(o, main_r, main_h, rng.randi_range(5, 6), _at(Vector3.ZERO, Vector3(rng.randf_range(-0.08, 0.08), 0, rng.randf_range(-0.08, 0.08))), true, 0.7)
	var n := rng.randi_range(4, 7)
	for i in n:
		var a := TAU * float(i) / float(n) + rng.randf_range(-0.3, 0.3)
		var d := main_r * rng.randf_range(0.7, 1.3)
		var h := main_h * rng.randf_range(0.25, 0.6)
		var lean := rng.randf_range(0.2, 0.55)
		var mat := magma() if i % 3 == 1 else o
		var axis := Vector3(sin(a), 0, -cos(a))  # tilt outward
		var xf := Transform3D(Basis(axis, lean), Vector3(cos(a) * d, -0.1, sin(a) * d))
		b.spike(mat, rng.randf_range(0.25, 0.45) * (0.6 if mat != o else 1.0), h, rng.randi_range(4, 6), xf, mat == o, 0.7)
	for i in 5:
		var a := rng.randf() * TAU
		b.blob(basalt(), rng.randf_range(0.3, 0.55), rng, _at(Vector3(cos(a) * (main_r + 0.6), 0.05, sin(a) * (main_r + 0.6))), 0.35, 0, true, true, 0.6, true)
	# molten seam (a flat glowing ring hugging the ground)
	b.lathe(magma_dim(), PackedVector2Array([Vector2(main_r + 0.45, 0.05), Vector2(main_r * 0.6, 0.09)]), 14, Transform3D.IDENTITY, false, Callable(), true, false)
	b.collide_cylinder(main_r + 0.3, 3.0)
	var root2 := _done(b, root, collide)
	if rng.randf() < 0.4:
		_light(root2, HELL_LIGHT, 1.2, 5.0, Vector3(0, 0.8, 0), true)
	return root2


## Pool of molten lava ringed by basalt boulders. Blocking (cylinder collision), hot glow light.
static func lava_pool(rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	var root := _root(rng, &"lava_pool")
	var b := PropBuilder.new()
	var r := rng.randf_range(1.6, 2.4)
	root.set_meta(&"footprint", r + 0.8)
	# lava surface: irregular disc slightly below ground
	var lump := func(a: float, _t: float) -> float: return 1.0 + 0.12 * sin(a * 3.0 + r) + 0.07 * sin(a * 7.0)
	# (sits just above y = 0 so it shows over any ground plane / terrain)
	b.lathe(lava_mat(), PackedVector2Array([Vector2(r, 0.07), Vector2(0.0, 0.07)]), 28, Transform3D.IDENTITY, false, lump, false, false)
	# charred rim (slanted ring) + boulders
	b.lathe(hellstone(), PackedVector2Array([Vector2(r * 1.35, 0.0), Vector2(r * 1.12, 0.24), Vector2(r * 0.97, 0.05)]), 28,
			Transform3D.IDENTITY, false, lump, false, false)
	var n := int(r * 5.0)
	for i in n:
		var a := TAU * float(i) / float(n) + rng.randf_range(-0.2, 0.2)
		var d := r * float(lump.call(a, 0.0)) * rng.randf_range(1.05, 1.25)
		b.blob(basalt() if i % 2 == 0 else hellstone(), rng.randf_range(0.25, 0.5), rng,
				_at(Vector3(cos(a) * d, 0.0, sin(a) * d)), 0.35, 0, true, true, 0.7, true)
	b.collide_cylinder(r * 1.1, 2.0)
	var root2 := _done(b, root, collide)
	_light(root2, LAVA_LIGHT, 2.4, r * 3.5, Vector3(0, 1.0, 0), true)
	return root2


static func _bone(b: PropBuilder, mat: Material, a: Vector3, c: Vector3, r: float) -> void:
	b.tube(mat, PackedVector3Array([a, a.lerp(c, 0.5), c]), r, 5, Transform3D.IDENTITY, false,
			PackedFloat32Array([r * 1.25, r * 0.8, r * 1.25]))
	b.blob(mat, r * 1.5, RandomNumberGenerator.new(), _at(a), 0.1, 0, true, false)
	b.blob(mat, r * 1.5, RandomNumberGenerator.new(), _at(c), 0.1, 0, true, false)


static func _skull(b: PropBuilder, mat: Material, xf: Transform3D, rng: RandomNumberGenerator, horns: bool) -> void:
	b.blob(mat, 0.22, rng, xf * _at(Vector3(0, 0.2, 0), Vector3.ZERO, Vector3(0.95, 0.9, 1.1)), 0.05, 1, false)
	b.box(mat, Vector3(0.24, 0.12, 0.2), xf * _at(Vector3(0, 0.07, 0.13)))
	for s: float in [-1.0, 1.0]:
		b.blob(void_mat(), 0.06, rng, xf * _at(Vector3(0.08 * s, 0.22, 0.19)), 0.0, 0, true, false)
		if horns:
			b.tube(mat, PackedVector3Array([Vector3(0.15 * s, 0.32, 0.0), Vector3(0.32 * s, 0.45, -0.05),
					Vector3(0.38 * s, 0.68, -0.15), Vector3(0.3 * s, 0.82, -0.3)]), 0.06, 5, xf, false,
					PackedFloat32Array([0.06, 0.05, 0.035, 0.01]))


## Mound of charred earth heaped with bones, ribcages and horned skulls.
static func bone_heap(rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	var root := _root(rng, &"bone_heap")
	var b := PropBuilder.new()
	var bm := bone()
	b.blob(Art.mat(Color(0.19, 0.14, 0.12), 1.0, 0.0, 0.5, false, 0.0, &"stone"), 1.2, rng, _at(Vector3(0, 0, 0)), 0.25, 1, true, true, 0.45, true)
	for i in rng.randi_range(10, 16):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, 1.3)
		var y := 0.5 * (1.0 - d / 1.3) + 0.05
		var p := Vector3(cos(a) * d, y, sin(a) * d)
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 0.3), rng.randf_range(-1, 1)).normalized()
		var length := rng.randf_range(0.35, 0.7)
		_bone(b, bm, p - dir * length * 0.5, p + dir * length * 0.5, 0.04)
	for i in rng.randi_range(2, 4):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.2, 1.1)
		_skull(b, bm, _at(Vector3(cos(a) * d, 0.45 * (1.0 - d / 1.3), sin(a) * d), Vector3(rng.randf_range(-0.4, 0.2), rng.randf() * TAU, 0)), rng, rng.randf() < 0.4)
	# a ribcage leaning on the pile
	var rc := _at(Vector3(rng.randf_range(-0.4, 0.4), 0.35, rng.randf_range(-0.4, 0.4)), Vector3(0.6, rng.randf() * TAU, 0))
	b.tube(bm, PackedVector3Array([Vector3(0, 0, -0.4), Vector3(0, 0.05, 0.0), Vector3(0, 0, 0.4)]), 0.035, 5, rc, false)
	for i in 5:
		var z := -0.3 + float(i) * 0.15
		var w := 0.28 - absf(z) * 0.3
		b.torus(bm, w, 0.022, 12, 4, rc * _at(Vector3(0, -w * 0.6, z), Vector3(0, 0, PI * 0.5)), false, PI * 1.3)
	b.collide_cylinder(1.0, 1.0)
	return _done(b, root, collide)


## Chain links following `points` (alternating orientation, each oriented along the path).
static func _chain(b: PropBuilder, mat: Material, points: PackedVector3Array, link: float = 0.16) -> void:
	var total := 0.0
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
	var count := int(total / link)
	var seg := 0
	var seg_start := 0.0
	for k in count:
		var dist := (float(k) + 0.5) * link
		while seg < points.size() - 2 and dist > seg_start + points[seg].distance_to(points[seg + 1]):
			seg_start += points[seg].distance_to(points[seg + 1])
			seg += 1
		var a := points[seg]
		var c := points[seg + 1]
		var seg_len := a.distance_to(c)
		var p := a.lerp(c, clampf((dist - seg_start) / maxf(seg_len, 0.001), 0.0, 1.0))
		var fwd := (c - a).normalized()
		var side := fwd.cross(Vector3.UP)
		if side.length_squared() < 0.01:
			side = Vector3.RIGHT
		side = side.normalized()
		var up := side.cross(fwd).normalized()
		# torus lies in its local XZ plane: map local X -> fwd, local Z -> side or up (alternating)
		var basis := Basis(fwd, up if k % 2 == 0 else side, side if k % 2 == 0 else -up)
		# squash the ring across the chain so links read as elongated ovals
		b.torus(mat, link * 0.42, link * 0.12, 8, 4, Transform3D(basis * Basis.from_scale(Vector3(1.0, 1.0, 0.6)), p), false)


## Two iron posts with spiked tops, a sagging chain between them and loose chain coiled at the foot.
static func chain_posts(rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	var root := _root(rng, &"chain_posts")
	var b := PropBuilder.new()
	var im := rust_iron()
	var span := rng.randf_range(2.8, 3.6)
	var tops: Array[Vector3] = []
	for s: float in [-1.0, 1.0]:
		var x := s * span * 0.5
		var h := rng.randf_range(1.9, 2.3)
		b.prism(basalt(), PackedVector2Array([Vector2(-0.3, -0.3), Vector2(0.3, -0.3), Vector2(0.3, 0.3), Vector2(-0.3, 0.3)]), 0.0, 0.3, _at(Vector3(x, 0, 0)))
		b.box(im, Vector3(0.22, h, 0.22), _at(Vector3(x, h * 0.5 + 0.3, 0), Vector3(0, 0, rng.randf_range(-0.05, 0.05))))
		b.spike(im, 0.14, 0.4, 4, _at(Vector3(x, h + 0.3, 0), Vector3(0, PI * 0.25, 0)))
		b.collide_cylinder(0.3, h + 0.3, _at(Vector3(x, 0, 0)))
		tops.append(Vector3(x, h + 0.05, 0))
	# catenary-ish sag
	var pts := PackedVector3Array()
	var sag := rng.randf_range(0.5, 0.9)
	for i in 13:
		var t := float(i) / 12.0
		var p := tops[0].lerp(tops[1], t)
		p.y -= sag * 4.0 * t * (1.0 - t)
		pts.append(p)
	_chain(b, im, pts)
	# loose chain lying on the ground
	var g := PackedVector3Array()
	var a0 := rng.randf() * TAU
	for i in 10:
		var a := a0 + float(i) * 0.6
		var r := 0.15 + float(i) * 0.05
		g.append(Vector3(tops[0].x + cos(a) * r, 0.05, sin(a) * r + 0.6))
	_chain(b, im, g)
	# a skull hung from the middle of the chain
	if rng.randf() < 0.5:
		var mid := pts[6]
		_chain(b, im, PackedVector3Array([mid, mid + Vector3(0, -0.45, 0)]))
		_skull(b, bone(), _at(mid + Vector3(0, -0.85, 0)), rng, true)
	return _done(b, root, collide)


## Iron tripod with an obsidian bowl of glowing coals and roaring hellfire.
static func hell_brazier(rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	var root := _root(rng, &"hell_brazier")
	var b := PropBuilder.new()
	var im := iron()
	for i in 3:
		var a := TAU * float(i) / 3.0
		var foot := Vector3(cos(a) * 0.6, 0.0, sin(a) * 0.6)
		var knee := Vector3(cos(a) * 0.32, 0.6, sin(a) * 0.32)
		b.tube(im, PackedVector3Array([foot + Vector3(0, 0.05, 0), knee, Vector3(cos(a) * 0.3, 1.05, sin(a) * 0.3)]), 0.045, 5)
		b.spike(im, 0.07, 0.28, 4, _at(Vector3(cos(a) * 0.5, 1.2, sin(a) * 0.5), Vector3(0, 0, 0)))
	b.torus(im, 0.33, 0.035, 16, 5, _at(Vector3(0, 0.55, 0)))
	b.lathe(obsidian(), PackedVector2Array([Vector2(0.1, 0.95), Vector2(0.42, 1.05), Vector2(0.56, 1.25), Vector2(0.52, 1.28),
			Vector2(0.4, 1.15), Vector2(0.0, 1.13)]), 8, Transform3D.IDENTITY, true, Callable(), true)
	for i in 6:
		var a := rng.randf() * TAU
		b.blob(magma(), rng.randf_range(0.1, 0.18), rng, _at(Vector3(cos(a) * 0.22, 1.18, sin(a) * 0.22)), 0.3, 0, true, false)
	b.collide_cylinder(0.5, 1.3)
	var root2 := _done(b, root, collide)
	_flames(root2, true, Vector3(0, 1.2, 0), 1.45)
	_light(root2, HELL_LIGHT, 2.8, 8.0, Vector3(0, 2.0, 0))
	return root2


## Dark sulphurous boulder crusted with yellow brimstone crystals and smouldering embers.
static func brimstone_rock(rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	var root := _root(rng, &"brimstone_rock")
	var b := PropBuilder.new()
	var r := rng.randf_range(0.8, 1.4)
	b.blob(hellstone(), r, rng, _at(Vector3(0, r * 0.35, 0)), 0.3, 1, true, true, 0.75, true)
	if rng.randf() < 0.6:
		var a := rng.randf() * TAU
		b.blob(basalt(), r * 0.55, rng, _at(Vector3(cos(a) * r * 0.9, r * 0.2, sin(a) * r * 0.9)), 0.3, 1, true, true, 0.8, true)
	for i in rng.randi_range(5, 9):
		# crystals sprout on the upper half, pointing away from the centre
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.2, 1.0), rng.randf_range(-1, 1)).normalized()
		var p := Vector3(0, r * 0.35, 0) + dir * r * 0.72
		var basis := Basis(Quaternion(Vector3.UP, dir))
		b.spike(sulfur(), rng.randf_range(0.06, 0.13), rng.randf_range(0.2, 0.45), 5, Transform3D(basis, p), false, 0.8)
	for i in 4:
		var a := rng.randf() * TAU
		b.blob(magma(), rng.randf_range(0.05, 0.1), rng, _at(Vector3(cos(a) * r * 1.05, 0.03, sin(a) * r * 1.05)), 0.3, 0, true, false)
	b.collide_cylinder(r * 0.9, r * 1.2)
	return _done(b, root, collide)


## Cluster of hexagonal basalt columns of varied height with magma glowing in the joints.
static func basalt_columns(rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	var root := _root(rng, &"basalt_columns")
	var b := PropBuilder.new()
	var hex := PackedVector2Array()
	var cr := 0.36
	for i in 6:
		var a := TAU * float(i) / 6.0
		hex.append(Vector2(cos(a), sin(a)) * cr)
	var spacing := cr * 1.75
	var rings := 2
	for q in range(-rings, rings + 1):
		for r in range(-rings, rings + 1):
			if absi(q + r) > rings:
				continue
			if rng.randf() < 0.18:
				continue
			var x := spacing * (float(q) + float(r) * 0.5)
			var z := spacing * float(r) * 0.866
			var dist := Vector2(x, z).length()
			var h := maxf(0.3, rng.randf_range(1.5, 3.6) * (1.0 - dist / (spacing * (rings + 1.0))) + rng.randf_range(0.0, 0.6))
			b.prism(basalt(), hex, 0.0, h - 0.06, _at(Vector3(x, 0, z), Vector3(0, PI / 6.0, 0)))
			# pale weathered cap so the cluster reads from the top-down camera
			b.prism(basalt_top(), hex, h - 0.06, h, _at(Vector3(x, 0, z), Vector3(0, PI / 6.0, 0)))
			# slightly tilted cap stone for a broken-off look
			if rng.randf() < 0.4:
				b.prism(basalt(), hex, 0.0, 0.25, _at(Vector3(x, h, z), Vector3(rng.randf_range(-0.15, 0.15), PI / 6.0, rng.randf_range(-0.15, 0.15))))
	b.lathe(magma_dim(), PackedVector2Array([Vector2(spacing * 2.0, 0.06), Vector2(0.0, 0.06)]), 12, Transform3D.IDENTITY, false, Callable(), true, false)
	b.collide_cylinder(spacing * 2.3, 3.0)
	return _done(b, root, collide)


## Ring of leaning wooden stakes, sharpened and crowned with skulls.
static func impaler_spikes(rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	var root := _root(rng, &"impaler_spikes")
	var b := PropBuilder.new()
	var wood := Props.mat(Color(0.32, 0.22, 0.15), 0.95, 0.0, 0.6, 0.0, 0.0, &"wood")
	var n := rng.randi_range(3, 5)
	for i in n:
		var a := TAU * float(i) / float(n) + rng.randf_range(-0.3, 0.3)
		var d := rng.randf_range(0.2, 0.6)
		var h := rng.randf_range(1.6, 2.4)
		var lean := rng.randf_range(0.1, 0.35)
		var axis := Vector3(sin(a), 0, -cos(a))
		var xf := Transform3D(Basis(axis, lean), Vector3(cos(a) * d, 0, sin(a) * d))
		b.cylinder(wood, 0.12, 0.1, h, 6, xf, true, true)
		b.spike(wood, 0.1, 0.4, 6, xf * _at(Vector3(0, h, 0)))
		if rng.randf() < 0.6:
			_skull(b, bone(), xf * _at(Vector3(0, h - 0.45, 0), Vector3(0, rng.randf() * TAU, 0)), rng, rng.randf() < 0.3)
	b.collide_cylinder(0.8, 2.0)
	return _done(b, root, collide)
