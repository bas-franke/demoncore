class_name SiteProps
## Map-site props for the newer maps (storm spire, ashen wastes war camp, frozen monastery, sunlit
## citadel, Heaven's Gate) and The Breach. Same contract as PropKit (whose cache, helpers and
## materials they use): `SiteProps.build(name, rng, collide)` returns a Node3D, origin on the ground,
## random yaw, a "Collision" StaticBody3D on layer 1 when `collide`, meta `footprint` / `prop`.
## Normally reached through PropKit.build(name, rng) (cached variants) or Props.build(name, rng).
##
## Storm spire:      lightning_rod, bell_tower_ruin
## Ashen wastes:     war_tent, siege_ladder, burned_cart, crucifix_pyre, weapon_rack, supply_crates
## Frozen monastery: prayer_flags, ice_pine, snow_cairn
## Sunlit citadel:   citadel_banner, sun_mirror
## Heaven's Gate:    cloud_steps, colossal_door
## The Breach:       hell_rift, fallen_wing, corrupted_column

const NAMES: Array[StringName] = [&"lightning_rod", &"bell_tower_ruin", &"war_tent", &"siege_ladder",
		&"burned_cart", &"crucifix_pyre", &"weapon_rack", &"supply_crates", &"prayer_flags", &"ice_pine",
		&"snow_cairn", &"citadel_banner", &"sun_mirror", &"cloud_steps", &"colossal_door", &"hell_rift",
		&"fallen_wing", &"corrupted_column"]

const FOOTPRINT := {
	&"lightning_rod": 1.0, &"bell_tower_ruin": 2.8, &"war_tent": 2.6, &"siege_ladder": 1.6,
	&"burned_cart": 1.7, &"crucifix_pyre": 1.4, &"weapon_rack": 1.2, &"supply_crates": 1.4,
	&"prayer_flags": 2.2, &"ice_pine": 1.4, &"snow_cairn": 0.7, &"citadel_banner": 0.7,
	&"sun_mirror": 1.6, &"cloud_steps": 2.4, &"colossal_door": 6.0, &"hell_rift": 3.0,
	&"fallen_wing": 2.8, &"corrupted_column": 1.4,
}

static var _mats := {}


static func has(prop: StringName) -> bool:
	return FOOTPRINT.has(prop)


static func footprint(prop: StringName) -> float:
	return float(FOOTPRINT.get(prop, 1.0))


static func build(prop: StringName, rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	match prop:
		&"lightning_rod": return lightning_rod(rng, collide)
		&"bell_tower_ruin": return bell_tower_ruin(rng, collide)
		&"war_tent": return war_tent(rng, collide)
		&"siege_ladder": return siege_ladder(rng, collide)
		&"burned_cart": return burned_cart(rng, collide)
		&"crucifix_pyre": return crucifix_pyre(rng, collide)
		&"weapon_rack": return weapon_rack(rng, collide)
		&"supply_crates": return supply_crates(rng, collide)
		&"prayer_flags": return prayer_flags(rng, collide)
		&"ice_pine": return ice_pine(rng, collide)
		&"snow_cairn": return snow_cairn(rng, collide)
		&"citadel_banner": return citadel_banner(rng, collide)
		&"sun_mirror": return sun_mirror(rng, collide)
		&"cloud_steps": return cloud_steps(rng, collide)
		&"colossal_door": return colossal_door(rng, collide)
		&"hell_rift": return hell_rift(rng, collide)
		&"fallen_wing": return fallen_wing(rng, collide)
		&"corrupted_column": return corrupted_column(rng, collide)
	push_warning("SiteProps.build: unknown prop %s" % prop)
	return Node3D.new()


# ================================================================ materials

static func _m(key: StringName, maker: Callable) -> Material:
	if not _mats.has(key):
		_mats[key] = maker.call()
	return _mats[key]


static func copper() -> Material:
	return Art.mat(Color(0.55, 0.3, 0.17), 0.4, 0.9, 0.45, false, 0.0, &"gold")


static func verdigris() -> Material:
	return Art.mat(Color(0.26, 0.42, 0.36), 0.7, 0.4, 0.5, false, 0.0, &"rust")


static func canvas() -> Material:
	return Art.mat(Color(0.86, 0.82, 0.72), 0.95, 0.0, 0.35, false, 0.6, &"cloth")


static func canvas_burnt() -> Material:
	return Art.mat(Color(0.18, 0.14, 0.12), 1.0, 0.0, 0.6, false, 0.3, &"cloth")


static func cloth(c: Color) -> Material:
	return Art.mat(c, 0.95, 0.0, 0.3, false, 0.6, &"cloth")


static func wood() -> Material:
	return Art.mat(Color(0.3, 0.21, 0.14), 0.9, 0.0, 0.5, false, 0.0, &"wood")


static func charred() -> Material:
	return Art.mat(Color(0.07, 0.055, 0.05), 1.0, 0.0, 0.6, false, 0.0, &"wood")


static func pine() -> Material:
	return Art.mat(Color(0.07, 0.14, 0.09), 0.95, 0.0, 0.3, false, 0.4)


static func snow() -> Material:
	return _m(&"snow", func() -> Material:
		var m := Art.mat(Color(0.92, 0.94, 0.98), 0.75, 0.0, 0.0, false, 0.3).duplicate() as ShaderMaterial
		m.set_shader_parameter(&"contact_dark", 0.05)
		return m)


static func ice() -> Material:
	return Art.mat(Color(0.7, 0.82, 0.92), 0.08, 0.0, 0.05, false, 0.2, &"crystal")


static func pearl() -> Material:
	return Art.mat(Color(0.92, 0.9, 0.86), 0.25, 0.0, 0.15, false, 0.5, &"marble")


static func mirror() -> Material:
	return Art.mat(Color(1.0, 0.86, 0.55), 0.06, 1.0, 0.05, false)


static func storm_glow() -> Material:
	return Art.emissive(Color(0.6, 0.7, 1.0), Color(0.55, 0.75, 1.0), 3.5, 0.3, false)


static func holy_glow() -> Material:
	return Art.emissive(Color(0.9, 0.8, 0.5), Art.HOLY, 2.5, 0.4, false)


# ================================================================ helpers (PropKit's)

static func _at(pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> Transform3D:
	return PropKit._at(pos, rot, scl)


static func _done(b: PropBuilder, root: Node3D, collide: bool) -> Node3D:
	return PropKit._done(b, root, collide)


## Log / plank between two points (a tube with flat-ish ends).
static func _beam(b: PropBuilder, mat: Material, a: Vector3, c: Vector3, r: float, sides: int = 6) -> void:
	b.tube(mat, PackedVector3Array([a, c]), r, sides)


# ================================================================ storm spire

## Iron lightning mast on a stone plinth: copper coil wound around it, a crown of spikes and a
## glowing storm-blue tip, guy cables pegged to the ground.
static func lightning_rod(rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	var root := PropKit._root(rng, &"lightning_rod")
	var b := PropBuilder.new()
	var h := rng.randf_range(5.5, 7.0)
	var stone := Props.stone_mat(rng)
	b.box(stone, Vector3(1.3, 0.5, 1.3), _at(Vector3(0, 0.25, 0)))
	b.box(stone, Vector3(1.0, 0.3, 1.0), _at(Vector3(0, 0.65, 0)))
	b.cylinder(PropKit.iron(), 0.13, 0.06, h, 8, _at(Vector3(0, 0.8, 0)))
	# helical copper coil
	var coil := PackedVector3Array()
	var turns := 7.0
	for i in 64:
		var t := float(i) / 63.0
		var a := t * turns * TAU
		var y := 1.5 + t * (h * 0.55)
		var r := lerpf(0.2, 0.13, t)
		coil.append(Vector3(cos(a) * r, y, sin(a) * r))
	b.tube(copper(), coil, 0.035, 5, Transform3D.IDENTITY, true)
	for y: float in [1.4, 1.5 + h * 0.55 + 0.1]:
		b.torus(verdigris(), 0.2, 0.05, 12, 4, _at(Vector3(0, y, 0)))
	# crown of spikes + glowing tip
	var top := h + 0.8
	for i in 5:
		var a := TAU * float(i) / 5.0
		b.spike(PropKit.iron(), 0.04, 0.6, 4, Transform3D(Basis(Vector3(sin(a), 0, -cos(a)), 0.6), Vector3(0, top - 0.4, 0)))
	b.spike(PropKit.iron(), 0.06, 0.9, 4, _at(Vector3(0, top - 0.1, 0)))
	b.blob(storm_glow(), 0.12, rng, _at(Vector3(0, top + 0.8, 0)), 0.1, 1, false, false)
	# guy cables
	for i in 3:
		var a := TAU * float(i) / 3.0 + 0.4
		var foot := Vector3(cos(a) * 2.2, 0.05, sin(a) * 2.2)
		b.tube(PropKit.iron(), PackedVector3Array([Vector3(0, h * 0.7, 0), foot]), 0.02, 4, Transform3D.IDENTITY, false)
		b.box(PropKit.iron(), Vector3(0.12, 0.3, 0.12), _at(foot + Vector3(0, 0.1, 0)))
	b.collide_cylinder(0.7, 3.0)
	return _done(b, root, collide)


## Stump of a broken bell tower: four walls snapped off at different heights, a fallen bronze
## bell lying cracked beside it, beams and rubble.
static func bell_tower_ruin(rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	var root := PropKit._root(rng, &"bell_tower_ruin")
	var b := PropBuilder.new()
	var stone := Props.stone_mat(rng)
	var w := 3.2
	var t := 0.5
	for k in 4:
		var yaw := PI * 0.5 * float(k)
		var h := rng.randf_range(2.5, 7.5) * (0.6 if k == 0 else 1.0)  # front (camera side) stays low
		var poly := PackedVector2Array([Vector2(-w * 0.5, 0), Vector2(w * 0.5, 0)])
		var steps := 6
		for i in steps + 1:
			var x := lerpf(w * 0.5, -w * 0.5, float(i) / float(steps))
			poly.append(Vector2(x, h + rng.randf_range(-1.2, 0.4) * (1.0 if i > 0 and i < steps else 0.0)))
		var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO) * _at(Vector3(0, 0, w * 0.5 - t * 0.5))
		b.slab(stone, poly, t, xf)
		# arched belfry slit in the taller walls
		if h > 5.0:
			b.box(PropKit.void_mat(), Vector3(0.5, 1.3, t + 0.02), xf * _at(Vector3(0, h - 2.0, 0)), false)
	# corner quoins
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			b.box(stone, Vector3(0.6, rng.randf_range(1.5, 3.0), 0.6), _at(Vector3(sx * w * 0.5, 0.8, sz * w * 0.5)))
	# fallen bell
	var a := rng.randf_range(-0.6, 0.6) + PI * 0.5
	var bp := Vector3(cos(a) * 3.2, 0.75, sin(a) * 3.2)
	var bell_xf := _at(bp, Vector3(PI * 0.5 + 0.25, a, 0))
	b.lathe(PropKit.bronze(), PackedVector2Array([Vector2(0.95, -0.8), Vector2(0.75, -0.4), Vector2(0.55, 0.4),
			Vector2(0.5, 0.75), Vector2(0.0, 0.85)]), 18, bell_xf)
	b.torus(PropKit.bronze(), 0.9, 0.07, 18, 5, bell_xf * _at(Vector3(0, -0.78, 0)))
	# beams and rubble
	for i in 3:
		var ba := rng.randf() * TAU
		var p := Vector3(cos(ba) * 2.6, 0.15, sin(ba) * 2.6)
		_beam(b, charred(), p, p + Vector3(cos(ba + 1.2) * 2.4, rng.randf_range(0.2, 0.9), sin(ba + 1.2) * 2.4), 0.12, 5)
	for i in 6:
		var ra := rng.randf() * TAU
		b.blob(stone, rng.randf_range(0.2, 0.45), rng, _at(Vector3(cos(ra) * rng.randf_range(1.9, 3.0), 0.1, sin(ra) * rng.randf_range(1.9, 3.0))), 0.3, 0, true, true, 0.6, true)
	b.collide_box(Vector3(w + 0.4, 4.0, w + 0.4), _at(Vector3(0, 2.0, 0)))
	b.collide_sphere(1.0, _at(bp))
	return _done(b, root, collide)


# ================================================================ ashen wastes (angel war camp)

## Angelic war pavilion: canvas walls and peaked roof with gold trim, a pennant on the king pole.
## A third are burned out (charred canvas, roof slumped).
static func war_tent(rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	var root := PropKit._root(rng, &"war_tent")
	var b := PropBuilder.new()
	var burnt := rng.randf() < 0.33
	var cv := canvas_burnt() if burnt else canvas()
	var r := rng.randf_range(2.0, 2.4)
	var wall := 1.7
	var sides := 8
	var drape := func(a: float, _t: float) -> float: return 1.0 + 0.04 * sin(a * float(sides))
	b.lathe(cv, PackedVector2Array([Vector2(r, 0.0), Vector2(r * 0.98, wall)]), sides * 2, Transform3D.IDENTITY, true, drape, true, false)
	var peak := wall + rng.randf_range(1.6, 2.1) * (0.6 if burnt else 1.0)
	var tilt := Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15)) if burnt else Vector3.ZERO
	b.lathe(cv, PackedVector2Array([Vector2(r * 1.12, wall - 0.1), Vector2(r * 0.5, wall + (peak - wall) * 0.6),
			Vector2(0.0, peak)]), sides * 2, _at(Vector3.ZERO, tilt), true, drape, false, false)
	if not burnt:
		b.torus(PropKit.gold(), r * 1.1, 0.04, 24, 4, _at(Vector3(0, wall - 0.08, 0)))
		# door flap opening (dark) on the front
		b.slab(PropKit.void_mat(), PackedVector2Array([Vector2(-0.5, 0), Vector2(0.5, 0), Vector2(0, 1.5)]), 0.05,
				_at(Vector3(0, 0, r * 0.99)), false)
	else:
		for i in 5:
			var a := rng.randf() * TAU
			b.blob(PropKit.magma_dim(), rng.randf_range(0.05, 0.1), rng, _at(Vector3(cos(a) * r, 0.04, sin(a) * r)), 0.3, 0, true, false)
	# king pole, finial and pennant
	b.cylinder(wood(), 0.07, 0.06, peak + 0.9, 6)
	b.blob(PropKit.gold(), 0.12, rng, _at(Vector3(0, peak + 0.95, 0)), 0.0, 1, false)
	if not burnt:
		var col := Color(0.62, 0.08, 0.08) if rng.randf() < 0.5 else Color(0.9, 0.7, 0.25)
		b.slab(cloth(col), PackedVector2Array([Vector2(0, 0), Vector2(1.1, -0.15), Vector2(0, -0.35)]), 0.02,
				_at(Vector3(0.05, peak + 0.85, 0)), false)
	# guy ropes and pegs
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI / 4.0
		var foot := Vector3(cos(a) * (r + 1.0), 0.05, sin(a) * (r + 1.0))
		b.tube(Props.mat(Color(0.5, 0.42, 0.3), 0.9, 0.0, 0.4, 0.0, 0.0, &"rope"),
				PackedVector3Array([Vector3(cos(a) * r * 1.1, wall - 0.1, sin(a) * r * 1.1), foot]), 0.015, 4, Transform3D.IDENTITY, false)
	b.collide_cylinder(r, 2.5)
	return _done(b, root, collide)


## Siege ladder lying where it fell: two long rails and rungs, one end propped on a stone.
static func siege_ladder(rng: RandomNumberGenerator, _collide: bool = true) -> Node3D:
	var root := PropKit._root(rng, &"siege_ladder")
	var b := PropBuilder.new()
	var w := wood() if rng.randf() < 0.6 else charred()
	var length := rng.randf_range(4.5, 6.0)
	var lift := rng.randf_range(0.2, 0.6)
	var pitch := atan2(lift, length)
	var xf := _at(Vector3(0, 0.08, 0), Vector3(0, 0, pitch))
	for s: float in [-1.0, 1.0]:
		b.box(w, Vector3(length, 0.12, 0.1), xf * _at(Vector3(0, 0, s * 0.3)))
	var n := int(length / 0.42)
	for i in n:
		var x := -length * 0.5 + 0.25 + float(i) * 0.42
		if rng.randf() < 0.1:
			continue  # a missing rung
		b.cylinder(w, 0.035, 0.035, 0.6, 5, xf * _at(Vector3(x, 0.03, -0.3), Vector3(PI * 0.5, 0, 0)))
	b.blob(Props.stone_mat(rng), 0.35, rng, _at(Vector3(length * 0.5 - 0.2, lift * 0.5, 0)), 0.3, 0, true, true, 0.7, true)
	return _done(b, root, false)  # knee-high: never blocks movement (collide ignored)


## Charred supply cart: plank bed with side rails, one wheel on, the other broken off and lying flat.
static func burned_cart(rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	var root := PropKit._root(rng, &"burned_cart")
	var b := PropBuilder.new()
	var c := charred()
	var w := wood()
	var tilt := 0.18
	var bed := _at(Vector3(0, 0.55, 0), Vector3(0, 0, -tilt))  # sags toward the missing wheel side (-x)
	b.box(c, Vector3(1.4, 0.1, 2.4), bed)
	for s: float in [-1.0, 1.0]:
		b.box(c if rng.randf() < 0.7 else w, Vector3(0.08, 0.4, 2.4), bed * _at(Vector3(s * 0.66, 0.22, 0)))
	b.box(c, Vector3(1.4, 0.4, 0.08), bed * _at(Vector3(0, 0.22, -1.16)))
	# shafts
	for s: float in [-1.0, 1.0]:
		_beam(b, w, bed * Vector3(s * 0.4, 0.0, 1.2), Vector3(s * 0.35, 0.05, 2.8), 0.05, 5)
	# wheels
	var wheel := func(xf: Transform3D) -> void:
		b.torus(c, 0.55, 0.06, 18, 5, xf)
		for k in 6:
			var a := TAU * float(k) / 6.0
			_beam(b, c, xf * Vector3(0, 0, 0), xf * Vector3(cos(a) * 0.52, 0, sin(a) * 0.52), 0.03, 4)
		b.cylinder(PropKit.iron(), 0.1, 0.1, 0.15, 8, xf * _at(Vector3(0, -0.07, 0)))
	wheel.call(_at(Vector3(0.78, 0.58, 0.2), Vector3(0, 0, PI * 0.5)))
	wheel.call(_at(Vector3(-1.6, 0.07, 0.6), Vector3(0, 0.3, 0)))
	# embers in the ash
	for i in 6:
		var a := rng.randf() * TAU
		b.blob(PropKit.magma_dim(), rng.randf_range(0.04, 0.09), rng, _at(Vector3(cos(a) * 0.6, 0.6, sin(a) * 1.0)), 0.3, 0, true, false)
	b.collide_box(Vector3(1.6, 1.2, 2.6), _at(Vector3(0, 0.6, 0)))
	return _done(b, root, collide)


## Holy pyre: a heap of logs around a stake cross hung with chains, burning with white-gold fire.
static func crucifix_pyre(rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	var root := PropKit._root(rng, &"crucifix_pyre")
	var b := PropBuilder.new()
	var w := wood()
	var c := charred()
	for layer in 3:
		var n := 9 - layer * 2
		var rr := 1.1 - float(layer) * 0.3
		for i in n:
			var a := TAU * float(i) / float(n) + float(layer) * 0.4
			var p := Vector3(cos(a) * rr * 0.6, 0.15 + float(layer) * 0.2, sin(a) * rr * 0.6)
			var d := Vector3(-sin(a), rng.randf_range(-0.1, 0.1), cos(a)) * rr * 0.7
			_beam(b, c if (i + layer) % 2 == 0 else w, p - d, p + d, rng.randf_range(0.07, 0.11), 6)
	b.box(w, Vector3(0.18, 3.4, 0.18), _at(Vector3(0, 1.7, -0.1)))
	b.box(w, Vector3(1.5, 0.16, 0.16), _at(Vector3(0, 2.7, -0.1)))
	PropKit._chain(b, PropKit.rust_iron(), PackedVector3Array([Vector3(-0.6, 2.62, 0.0), Vector3(-0.35, 2.1, 0.05),
			Vector3(0.0, 1.9, 0.0), Vector3(0.35, 2.1, 0.05), Vector3(0.6, 2.62, 0.0)]), 0.14)
	b.collide_cylinder(1.0, 2.5)
	var root2 := _done(b, root, collide)
	PropKit._flames(root2, false, Vector3(0, 0.55, 0.2), 1.2)
	PropKit._light(root2, PropKit.HOLY_LIGHT, 2.4, 8.0, Vector3(0, 1.6, 0.5))
	return root2


## Wooden rack of spears and round shields.
static func weapon_rack(rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	var root := PropKit._root(rng, &"weapon_rack")
	var b := PropBuilder.new()
	var w := wood()
	for s: float in [-1.0, 1.0]:
		_beam(b, w, Vector3(s * 1.0, 0.0, -0.4), Vector3(s * 1.0, 1.5, 0.0), 0.05, 5)
		_beam(b, w, Vector3(s * 1.0, 0.0, 0.4), Vector3(s * 1.0, 1.5, 0.0), 0.05, 5)
	_beam(b, w, Vector3(-1.1, 1.45, 0.0), Vector3(1.1, 1.45, 0.0), 0.05, 5)
	for i in rng.randi_range(4, 6):
		var x := lerpf(-0.85, 0.85, float(i) / 5.0)
		var lean := rng.randf_range(0.15, 0.3)
		var base := Vector3(x, 0.0, 0.45)
		var tip := Vector3(x + rng.randf_range(-0.1, 0.1), 2.4, 0.45 - 2.4 * lean)
		_beam(b, w, base, tip, 0.025, 4)
		b.spike(PropKit.gold(), 0.05, 0.3, 4, Transform3D(Basis(Quaternion(Vector3.UP, (tip - base).normalized())), tip))
	for i in 2:
		var x := -0.5 + float(i) * 1.0
		var sxf := _at(Vector3(x, 0.55, -0.5), Vector3(-PI * 0.5 + 0.25, 0, 0))
		b.lathe(PropKit.marble(), PackedVector2Array([Vector2(0.45, 0.0), Vector2(0.4, 0.06), Vector2(0.0, 0.1)]), 16, sxf)
		b.torus(PropKit.gold(), 0.44, 0.03, 16, 4, sxf * _at(Vector3(0, 0.03, 0)))
		b.blob(PropKit.gold(), 0.08, rng, sxf * _at(Vector3(0, 0.12, 0)), 0.0, 1, false)
	b.collide_box(Vector3(2.2, 1.6, 1.0), _at(Vector3(0, 0.8, 0)))
	return _done(b, root, collide)


## Stacked supply crates and banded barrels.
static func supply_crates(rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	var root := PropKit._root(rng, &"supply_crates")
	var b := PropBuilder.new()
	var w := wood()
	var dark := Props.mat(Color(0.2, 0.14, 0.09), 0.9, 0.0, 0.5, 0.0, 0.0, &"wood")
	var crate := func(p: Vector3, s: float, yaw: float) -> void:
		var xf := _at(p + Vector3(0, s * 0.5, 0), Vector3(0, yaw, 0))
		b.box(w, Vector3(s, s, s), xf)
		# plank frame on the faces
		for e in 4:
			var ex := (float(e % 2) - 0.5) * s
			@warning_ignore("integer_division")
			var ez := (float(e / 2) - 0.5) * s
			b.box(dark, Vector3(0.06, s + 0.02, 0.06), xf * _at(Vector3(ex, 0, ez)))
		b.box(dark, Vector3(s + 0.02, 0.06, 0.08), xf * _at(Vector3(0, s * 0.5 - 0.03, s * 0.5)))
		b.box(dark, Vector3(s * 1.35, 0.05, 0.08), xf * _at(Vector3(0, 0, s * 0.5), Vector3(0, 0, 0.78)))
	crate.call(Vector3(0, 0, 0), 0.9, rng.randf_range(-0.2, 0.2))
	crate.call(Vector3(0.95, 0, 0.1), 0.8, rng.randf_range(-0.3, 0.3))
	if rng.randf() < 0.7:
		crate.call(Vector3(0.3, 0.9, 0.0), 0.7, rng.randf_range(-0.4, 0.4))
	for i in rng.randi_range(1, 3):
		var p := Vector3(-0.9 - float(i) * 0.15, 0, rng.randf_range(-0.7, 0.7))
		var bxf := _at(p)
		b.lathe(w, PackedVector2Array([Vector2(0.3, 0.0), Vector2(0.37, 0.45), Vector2(0.3, 0.9)]), 12, bxf)
		for y: float in [0.15, 0.75]:
			b.torus(PropKit.iron(), 0.33, 0.025, 12, 4, bxf * _at(Vector3(0, y, 0)))
	b.collide_box(Vector3(2.6, 1.4, 1.8), _at(Vector3(0, 0.7, 0)))
	return _done(b, root, collide)


# ================================================================ frozen monastery

## Two poles with a sagging cord of coloured prayer flags, little cairns at their feet.
static func prayer_flags(rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	var root := PropKit._root(rng, &"prayer_flags")
	var b := PropBuilder.new()
	var span := rng.randf_range(3.5, 4.5)
	var tops: Array[Vector3] = []
	for s: float in [-1.0, 1.0]:
		var h := rng.randf_range(2.6, 3.4)
		var p := Vector3(s * span * 0.5, 0, 0)
		b.cylinder(wood(), 0.06, 0.05, h, 6, _at(p))
		for k in 3:
			b.blob(Props.stone_mat(rng), 0.25 - float(k) * 0.05, rng, _at(p + Vector3(0, 0.1 + float(k) * 0.2, 0)), 0.25, 0, true, true, 0.55)
		b.blob(snow(), 0.22, rng, _at(p + Vector3(0, 0.62, 0)), 0.2, 0, false, false, 0.4)
		tops.append(p + Vector3(0, h - 0.1, 0))
		b.collide_cylinder(0.3, 2.0, _at(p))
	var cols := [Color(0.15, 0.3, 0.7), Color(0.85, 0.85, 0.82), Color(0.7, 0.12, 0.1), Color(0.15, 0.5, 0.25), Color(0.85, 0.7, 0.15)]
	var n := 10
	var pts := PackedVector3Array()
	for i in n + 1:
		var t := float(i) / float(n)
		var p := tops[0].lerp(tops[1], t)
		p.y -= 0.7 * 4.0 * t * (1.0 - t)
		pts.append(p)
	b.tube(Props.mat(Color(0.45, 0.38, 0.28), 0.9, 0.0, 0.3, 0.0, 0.0, &"rope"), pts, 0.012, 4, Transform3D.IDENTITY, false)
	for i in range(1, n):
		var p := pts[i]
		var col: Color = cols[i % cols.size()]
		b.slab(cloth(col), PackedVector2Array([Vector2(-0.14, 0), Vector2(0.14, 0), Vector2(0.14, -0.4), Vector2(-0.14, -0.36)]),
				0.01, _at(p, Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.3, 0.3), 0)), false)
	return _done(b, root, collide)


## Snow-laden pine: stacked boughs with snow caps and icicles.
static func ice_pine(rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	var root := PropKit._root(rng, &"ice_pine")
	var b := PropBuilder.new()
	var h := rng.randf_range(4.0, 6.5)
	b.cylinder(Props.bark_mat(false), 0.2, 0.08, h * 0.9, 7)
	var tiers := 5
	for i in tiers:
		var t := float(i) / float(tiers)
		var y := 0.8 + t * h * 0.75
		var r := lerpf(1.5, 0.4, t) * rng.randf_range(0.9, 1.1)
		var th := h * 0.32
		var xf := _at(Vector3(0, y, 0), Vector3(rng.randf_range(-0.05, 0.05), rng.randf() * TAU, rng.randf_range(-0.05, 0.05)))
		# bough skirt with a ragged edge
		var rag := func(a: float, tt: float) -> float: return 1.0 + 0.15 * sin(a * 9.0 + float(i)) * (1.0 - tt)
		b.lathe(pine(), PackedVector2Array([Vector2(r, 0.0), Vector2(r * 0.45, th * 0.5), Vector2(0.0, th)]), 9, xf, true, rag, true, true)
		# snow cap on the upper half
		# (follows the bough surface 6 cm above it, leaving a green rim)
		b.lathe(snow(), PackedVector2Array([Vector2(r * 0.8, th * 0.18 + 0.06), Vector2(r * 0.45, th * 0.5 + 0.06),
				Vector2(0.0, th + 0.06)]), 9, xf, true, rag, false, false)
		# icicles under the rim
		for k in 3:
			var a := rng.randf() * TAU
			b.spike(ice(), 0.04, 0.3, 4, xf * _at(Vector3(cos(a) * r * 0.9, 0.0, sin(a) * r * 0.9), Vector3(PI, 0, 0)), false)
	b.blob(snow(), 1.1, rng, _at(Vector3(0, 0, 0)), 0.15, 1, false, false, 0.18)
	b.collide_cylinder(0.5, 3.0)
	return _done(b, root, collide)


## Cairn of flat stones topped with snow, a carved prayer stone leaning on it.
static func snow_cairn(rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	var root := PropKit._root(rng, &"snow_cairn")
	var b := PropBuilder.new()
	var y := 0.0
	var n := rng.randi_range(4, 6)
	for i in n:
		var r := lerpf(0.55, 0.18, float(i) / float(n))
		b.blob(Props.stone_mat(rng), r, rng, _at(Vector3(rng.randf_range(-0.05, 0.05), y + r * 0.3, rng.randf_range(-0.05, 0.05))), 0.2, 1, true, true, 0.45)
		y += r * 0.55
	b.blob(snow(), 0.25, rng, _at(Vector3(0, y + 0.05, 0)), 0.2, 1, false, false, 0.5)
	b.blob(snow(), 0.7, rng, _at(Vector3(0, 0, 0)), 0.2, 1, false, false, 0.2)
	b.slab(PropKit.marble_old(), PackedVector2Array([Vector2(-0.22, 0), Vector2(0.22, 0), Vector2(0.18, 0.6), Vector2(0, 0.7), Vector2(-0.18, 0.6)]),
			0.08, _at(Vector3(0.5, 0.0, 0.2), Vector3(-0.3, 0.6, 0)))
	b.collide_cylinder(0.55, 1.2)
	return _done(b, root, collide)


# ================================================================ sunlit citadel

## Tall gilded banner pole with a long white-and-gold sun banner (swallow-tailed).
static func citadel_banner(rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	var root := PropKit._root(rng, &"citadel_banner")
	var b := PropBuilder.new()
	var h := rng.randf_range(5.5, 7.0)
	var m := PropKit.marble()
	b.box(m, Vector3(0.9, 0.4, 0.9), _at(Vector3(0, 0.2, 0)))
	b.lathe(m, PackedVector2Array([Vector2(0.35, 0.4), Vector2(0.25, 0.7), Vector2(0.12, 0.8)]), 12)
	b.cylinder(PropKit.gold(), 0.07, 0.06, h, 8, _at(Vector3(0, 0.8, 0)))
	b.blob(PropKit.gold(), 0.16, rng, _at(Vector3(0, h + 0.9, 0)), 0.0, 1, false)
	b.spike(PropKit.gold(), 0.07, 0.5, 4, _at(Vector3(0, h + 1.0, 0)))
	var bar := h + 0.55
	b.cylinder(PropKit.gold(), 0.04, 0.04, 1.6, 6, _at(Vector3(-0.8, bar, 0.1), Vector3(0, 0, -PI * 0.5)))
	var white := cloth(Color(0.9, 0.88, 0.82))
	var drop := rng.randf_range(2.6, 3.4)
	b.slab(white, PackedVector2Array([Vector2(-0.7, 0), Vector2(0.7, 0), Vector2(0.7, -drop), Vector2(0.0, -drop + 0.5),
			Vector2(-0.7, -drop)]), 0.03, _at(Vector3(0, bar, 0.14)))
	# gold sun emblem + border stripes
	var sun_xf := _at(Vector3(0, bar - 0.9, 0.17), Vector3(PI * 0.5, 0, 0))
	b.lathe(PropKit.gold(), PackedVector2Array([Vector2(0.28, 0.0), Vector2(0.0, 0.01)]), 16, sun_xf, false, Callable(), true, false)
	for k in 8:
		var a := TAU * float(k) / 8.0
		b.slab(PropKit.gold(), PackedVector2Array([Vector2(-0.05, 0.3), Vector2(0.05, 0.3), Vector2(0, 0.48)]), 0.01,
				_at(Vector3(0, bar - 0.9, 0.17), Vector3(0, 0, a)), false)
	for s: float in [-1.0, 1.0]:
		b.box(PropKit.gold(), Vector3(0.06, drop - 0.4, 0.01), _at(Vector3(s * 0.6, bar - (drop - 0.4) * 0.5, 0.165)), false)
	b.collide_cylinder(0.5, 2.0)
	return _done(b, root, collide)


## Great sun mirror: a polished gold dish on a gimbal yoke, angled at the sky, a holy glint at
## its focus.
static func sun_mirror(rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	var root := PropKit._root(rng, &"sun_mirror")
	var b := PropBuilder.new()
	var m := PropKit.marble()
	b.lathe(m, PackedVector2Array([Vector2(1.0, 0.0), Vector2(0.9, 0.3), Vector2(0.4, 0.45), Vector2(0.35, 1.4), Vector2(0.5, 1.6), Vector2(0.0, 1.65)]), 16)
	for s: float in [-1.0, 1.0]:
		b.box(PropKit.gold(), Vector3(0.12, 1.6, 0.25), _at(Vector3(s * 1.45, 2.35, 0)))
	b.box(PropKit.gold(), Vector3(3.0, 0.15, 0.3), _at(Vector3(0, 1.62, 0)))
	var pitch := rng.randf_range(0.5, 0.9)
	var dish := _at(Vector3(0, 2.9, 0), Vector3(-pitch, 0, 0)) * _at(Vector3.ZERO, Vector3(PI * 0.5, 0, 0))
	# concave front (mirror) and a gold back
	b.lathe(mirror(), PackedVector2Array([Vector2(1.3, 0.25), Vector2(0.8, 0.08), Vector2(0.0, 0.0)]), 24, dish)
	b.lathe(PropKit.gold(), PackedVector2Array([Vector2(0.0, -0.12), Vector2(1.0, 0.05), Vector2(1.35, 0.27)]), 24, dish)
	b.torus(PropKit.gold(), 1.33, 0.06, 28, 5, dish * _at(Vector3(0, 0.26, 0)))
	b.blob(PropKit.gold(), 0.12, rng, dish * _at(Vector3(0, 0.95, 0)), 0.0, 1, false)
	b.tube(PropKit.gold(), PackedVector3Array([dish * Vector3(0.9, 0.2, 0), dish * Vector3(0, 0.95, 0), dish * Vector3(-0.9, 0.2, 0)]), 0.02, 4)
	b.blob(holy_glow(), 0.09, rng, dish * _at(Vector3(0, 0.95, 0)), 0.0, 1, false, false)
	b.collide_cylinder(1.1, 3.0)
	var root2 := _done(b, root, collide)
	PropKit._light(root2, PropKit.HOLY_LIGHT, 1.4, 6.0, Vector3(0, 3.5, 0.6), true)
	return root2


# ================================================================ Heaven's Gate

## A flight of cloud steps: billowing slabs rising toward the gates (visual; tops stay low enough
## to read as a terrace edge in the planar game, so they never block).
static func cloud_steps(rng: RandomNumberGenerator, _collide: bool = true) -> Node3D:
	var root := PropKit._root(rng, &"cloud_steps", false)
	var b := PropBuilder.new()
	var c := PropKit.cloud()
	var n := rng.randi_range(4, 6)
	for i in n:
		var z := -float(i) * 0.9
		var y := float(i) * 0.12
		var w := 3.2 - float(i) * 0.1
		# flat tread + puffs along the riser
		b.lathe(c, PackedVector2Array([Vector2(1.0, -0.15), Vector2(0.9, 0.0), Vector2(0.0, 0.02)]), 20,
				_at(Vector3(0, y, z), Vector3.ZERO, Vector3(w * 0.5, 1.0, 0.55)), false)
		for k in 5:
			var x := lerpf(-w * 0.5, w * 0.5, float(k) / 4.0)
			b.blob(c, rng.randf_range(0.28, 0.4), rng, _at(Vector3(x, y - 0.12, z + 0.45)), 0.2, 1, false, false, 0.6)
	return _done(b, root, false)


## Colossal doors of pearl and gold in a marble frame with a pointed arch; 30% stand ajar.
static func colossal_door(rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	var root := PropKit._root(rng, &"colossal_door", false)
	var b := PropBuilder.new()
	var m := PropKit.marble()
	var g := PropKit.gold()
	var w := 8.0
	var h := 9.5
	var ajar := rng.randf() < 0.3
	# jambs and the pointed arch above
	for s: float in [-1.0, 1.0]:
		b.box(m, Vector3(1.6, h, 1.4), _at(Vector3(s * (w * 0.5 + 0.8), h * 0.5, 0)))
		b.box(g, Vector3(1.8, 0.3, 1.6), _at(Vector3(s * (w * 0.5 + 0.8), 0.15, 0)))
		b.box(g, Vector3(1.8, 0.3, 1.6), _at(Vector3(s * (w * 0.5 + 0.8), h, 0)))
		b.collide_box(Vector3(1.6, 4.0, 1.4), _at(Vector3(s * (w * 0.5 + 0.8), 2.0, 0)))
	var arch := PropKit.arch_curve(w + 3.2, 7.0, h + 4.5, 14)
	arch.append(Vector2(-(w + 3.2) * 0.5, h))
	arch.append(Vector2((w + 3.2) * 0.5, h))
	b.slab(m, arch, 1.2)
	b.blob(g, 0.6, rng, _at(Vector3(0, h + 4.6, 0)), 0.0, 1, false)
	# the two leaves: pearl panels in gold frames with studs
	for s: float in [-1.0, 1.0]:
		var swing := s * 0.9 if ajar else 0.0
		var leaf := Transform3D(Basis(Vector3.UP, swing), Vector3(s * w * 0.5, 0, 0.1))
		var lw := w * 0.5
		b.box(g, Vector3(lw, h, 0.35), leaf * _at(Vector3(-s * lw * 0.5, h * 0.5, 0)))
		for row in 3:
			var py := 1.4 + float(row) * 2.8
			b.box(pearl(), Vector3(lw - 0.8, 2.2, 0.2), leaf * _at(Vector3(-s * lw * 0.5, py + 0.6, 0.12)))
			for col in 3:
				b.blob(g, 0.1, rng, leaf * _at(Vector3(-s * (0.6 + float(col) * (lw - 1.2) / 2.0), py - 0.6, 0.25)), 0.0, 0, false)
		b.torus(g, 0.4, 0.06, 16, 4, leaf * _at(Vector3(-s * (lw - 0.6), h * 0.45, 0.3), Vector3(PI * 0.5, 0, 0)))
	if not ajar:
		b.collide_box(Vector3(w, 4.0, 0.6), _at(Vector3(0, 2.0, 0.1)))
	var root2 := _done(b, root, collide)
	PropKit._light(root2, PropKit.HOLY_LIGHT, 2.0, 10.0, Vector3(0, 5.0, 2.0), true)
	return root2


# ================================================================ The Breach

## A jagged fissure torn open by hell: molten lava down its throat, obsidian shards bristling from
## its lips, a hellish glow. Impassable.
static func hell_rift(rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	var root := PropKit._root(rng, &"hell_rift")
	var b := PropBuilder.new()
	var length := rng.randf_range(5.0, 7.0)
	var n := 9
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / float(n)
		var x := (t - 0.5) * length
		var wdt := sin(t * PI) * rng.randf_range(0.5, 0.9) + 0.05
		var off := sin(t * 5.0) * 0.25
		left.append(Vector2(x, off + wdt))
		right.append(Vector2(x, off - wdt))
	var poly := left.duplicate()
	right.reverse()
	poly.append_array(right)
	# lava ribbon (prism in XZ) just above ground, charred lips around it
	b.prism(PropKit.lava_mat(), poly, 0.0, 0.07, Transform3D.IDENTITY, false)
	var lips := PackedVector2Array()
	for p in poly:
		lips.append(p * Vector2(1.08, 1.6))
	b.prism(PropKit.hellstone(), lips, -0.1, 0.05, Transform3D.IDENTITY, true)
	# obsidian shards along both lips, leaning outward
	for i in 14:
		var src: PackedVector2Array = left if i % 2 == 0 else right
		var p2 := src[rng.randi_range(1, n - 1)]
		var out := 1.0 if i % 2 == 0 else -1.0
		var basis := Basis(Vector3.RIGHT, -out * rng.randf_range(0.3, 0.7)).rotated(Vector3.UP, rng.randf_range(-0.3, 0.3))
		b.spike(PropKit.obsidian() if i % 3 != 0 else PropKit.magma(), rng.randf_range(0.12, 0.25), rng.randf_range(0.5, 1.4), 5,
				Transform3D(basis, Vector3(p2.x, 0.0, p2.y + out * 0.15)), true, 0.7)
	b.collide_box(Vector3(length, 3.0, 1.6), _at(Vector3(0, 1.5, 0)))
	var root2 := _done(b, root, collide)
	PropKit._light(root2, PropKit.LAVA_LIGHT, 2.2, 7.0, Vector3(0, 1.0, 0), true)
	return root2


## A colossal angel wing torn off and fallen: layered marble feathers fanned on the ground.
static func fallen_wing(rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	var root := PropKit._root(rng, &"fallen_wing")
	var b := PropBuilder.new()
	var m := PropKit.marble_old()
	var span := rng.randf_range(4.5, 5.5)
	# arm bone of the wing
	b.tube(m, PackedVector3Array([Vector3(-span * 0.5, 0.35, 0), Vector3(-span * 0.1, 0.55, -0.4), Vector3(span * 0.5, 0.3, -0.2)]),
			0.22, 7, Transform3D.IDENTITY, true, PackedFloat32Array([0.3, 0.2, 0.12]))
	# three rows of feathers (primaries longest), slightly tilted, fanned
	for row in 3:
		var count := 9 - row * 2
		var flen := 2.4 - float(row) * 0.7
		for i in count:
			var t := float(i) / float(count - 1)
			var base := Vector3(lerpf(-span * 0.45, span * 0.45, t), 0.3 + float(row) * 0.08, -0.3)
			var ang := lerpf(-0.35, 0.6, t)
			var feather := PackedVector2Array([Vector2(0, -0.14), Vector2(flen * 0.85, -0.18), Vector2(flen, 0.0),
					Vector2(flen * 0.85, 0.18), Vector2(0, 0.14)])
			b.slab(m, feather, 0.06, _at(base, Vector3(PI * 0.5 - 0.08, PI * 0.5 + ang, 0)))
	# broken stump with gold at the root, a shattered halo nearby
	b.blob(m, 0.5, rng, _at(Vector3(-span * 0.5 - 0.2, 0.3, 0)), 0.35, 1, true)
	b.torus(PropKit.gold(), 0.7, 0.05, 20, 4, _at(Vector3(span * 0.3, 0.06, 1.6), Vector3(0.1, 0, 0)), true, TAU * 0.55)
	b.collide_box(Vector3(span, 1.2, 1.6), _at(Vector3(0, 0.6, 0.6)))
	return _done(b, root, collide)


## A marble column broken by hell: obsidian crystals bursting through the shaft, magma veins.
static func corrupted_column(rng: RandomNumberGenerator, collide: bool = true) -> Node3D:
	var root := PropKit._root(rng, &"corrupted_column")
	var b := PropBuilder.new()
	var m := PropKit.marble_old()
	var h := rng.randf_range(2.0, 3.6)
	b.box(m, Vector3(1.3, 0.3, 1.3), _at(Vector3(0, 0.15, 0)))
	var flutes := func(a: float, _t: float) -> float: return 1.0 - 0.07 * pow(1.0 - absf(sin(a * 8.0)), 4.0)
	b.lathe(m, PackedVector2Array([Vector2(0.46, 0.3), Vector2(0.43, h * 0.5), Vector2(0.4, h)]), 40, Transform3D.IDENTITY, true, flutes)
	for i in rng.randi_range(4, 7):
		var a := rng.randf() * TAU
		var y := rng.randf_range(0.4, h * 0.9)
		var dir := Vector3(cos(a), rng.randf_range(0.2, 0.9), sin(a)).normalized()
		b.spike(PropKit.obsidian(), rng.randf_range(0.12, 0.22), rng.randf_range(0.6, 1.3), 5,
				Transform3D(Basis(Quaternion(Vector3.UP, dir)), Vector3(cos(a) * 0.3, y, sin(a) * 0.3)), true, 0.7)
	# magma veins: thin glowing tubes crawling up the shaft
	for k in 2:
		var pts := PackedVector3Array()
		var a0 := rng.randf() * TAU
		for i in 8:
			var t := float(i) / 7.0
			var a := a0 + t * 1.6 + sin(t * 9.0) * 0.2
			pts.append(Vector3(cos(a) * 0.44, 0.3 + t * (h - 0.4), sin(a) * 0.44))
		b.tube(PropKit.magma(), pts, 0.03, 4, Transform3D.IDENTITY, false)
	b.lathe(PropKit.magma_dim(), PackedVector2Array([Vector2(0.8, 0.05), Vector2(0.5, 0.08)]), 12, Transform3D.IDENTITY, false, Callable(), true, false)
	b.collide_cylinder(0.7, 3.0)
	return _done(b, root, collide)
