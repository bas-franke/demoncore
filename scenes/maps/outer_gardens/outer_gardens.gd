extends GameMap
## The Outer Gardens (heaven, difficulty 1). Circular garden terrace, radius 62.
##
## Layout (north = -Z = up on screen):
##   S  The Breach (player start): a burning hell-rift torn into the marble, an avenue of statues
##      leading to the outer hedge gate.
##   Two concentric hedge rings (r 38 and r 20) with OFFSET gaps (outer: S, WNW, ENE / inner: N, SE,
##   SW), so getting to the heart means walking around the ring corridor: a natural kiting loop.
##   Ring corridor: three reflecting pools (solid) and three flower parterres between them.
##   Heart: the Gilded Tree on a marble dais, ringed by six angel statues.
##   Outer terrace: Pearl Gate (N, angels pour out), Choir Pavilion (E), Fountain of Tears (W),
##   Gilded Orchard (SW), Garden of Saints (SE). Marble balustrade + cloud bank at the edge.

const OUTER_R := 38.0
const INNER_R := 20.0
const GAP_W := 9.5
## Gap angles in degrees (0 = +X / east, 90 = +Z / south).
const OUTER_GAPS := [90.0, 210.0, 330.0]
const INNER_GAPS := [30.0, 150.0, 270.0]
const POOL_ANGLES := [0.0, 120.0, 240.0]
const PARTERRE_ANGLES := [60.0, 180.0, 300.0]

var _marble: Material
var _marble_dark: Material
var _gold: Material
var _hedge: Material
var _hedge_dark: Material
var _water: Material
var _cloud: Material
var _flowers: Array[Material] = []


func _init() -> void:
	bounds_kind = Bounds.CIRCLE
	bounds_radius = 62.0


func _build_layout() -> void:
	_marble = mat(Color(0.86, 0.84, 0.79), 0.45, 0.0, 0.25, 0.0, &"marble")
	_marble_dark = mat(Color(0.7, 0.68, 0.64), 0.55, 0.0, 0.4, 0.15, &"stone")
	_gold = mat(Art.GOLD, 0.3, 0.9, 0.2, 0.0, &"metal")
	_hedge = mat(Color(0.12, 0.26, 0.08), 0.95, 0.0, 0.3, 0.0, &"")
	_hedge_dark = mat(Color(0.08, 0.18, 0.06), 0.95, 0.0, 0.3, 0.0, &"")
	_water = mat(Color(0.16, 0.32, 0.45), 0.04, 0.4, 0.0, 0.0, &"")
	_cloud = mat(Color(0.97, 0.96, 0.94), 1.0, 0.0, 0.0, 0.0, &"")
	for c in [Color(1.0, 0.97, 0.92), Color(1.0, 0.75, 0.82), Color(1.0, 0.85, 0.4), Color(0.8, 0.75, 1.0)]:
		_flowers.append(mat(c, 0.8, 0.0, 0.1, 0.0, &""))

	set_player_spawn(Vector3(0.0, 0.0, 51.0))
	_breach(Vector3(0.0, 0.0, 56.0))
	_statue_avenue()
	# --- per-run variety: gate angles, pool slots and terrace set pieces are rolled each run.
	# The south outer gate (the Breach's way in) is fixed; the other two swing by up to 20 degrees.
	var swing := float(pick_one([-20.0, 0.0, 20.0]))
	var outer_gaps := [90.0, 210.0 + swing, 330.0 - swing]
	# Inner gaps stay offset from the outer ones (never aligned: no straight run to the heart).
	var inner_gaps: Array = pick_one([INNER_GAPS, [0.0, 120.0, 240.0], [60.0, 180.0, 300.0]])
	_hedge_ring(OUTER_R, outer_gaps, 1.9)
	_hedge_ring(INNER_R, inner_gaps, 1.5)
	var slots: Array = []
	for k in 6:
		var a := float(k) * 60.0
		if not inner_gaps.has(a):
			slots.append(a)
	slots = shuffled(slots)
	var pool_angles := slots.slice(0, 3)
	for i in pool_angles.size():
		_pool(_polar(29.0, pool_angles[i]), pool_angles[i], i)
	var parterres := []
	for k in 6:
		var a := float(k) * 60.0
		if not pool_angles.has(a) and not inner_gaps.has(a):
			parterres.append(a)
	for a: float in [30.0, 90.0, 150.0, 210.0, 270.0, 330.0]:
		if not inner_gaps.has(a):
			parterres.append(a)
	parterres = shuffled(parterres)
	for i in mini(parterres.size(), 4):
		var p := _polar(29.0, parterres[i])
		if i < 2:
			font(p)  # holy fonts among the flower beds: they mend angels until corrupted
		else:
			_parterre(p)
	for a: float in inner_gaps:
		objective(&"altar", _polar(28.5, a))
		_lantern_pair(_polar(INNER_R + 2.5, a), deg_to_rad(a))
	for a: float in outer_gaps:
		_lantern_pair(_polar(OUTER_R + 2.5, a), deg_to_rad(a))
	_heart()
	_pearl_gate(Vector3(0.0, 0.0, -57.0))
	var terrace_slots := shuffled([Vector3(47.0, 0.0, -12.0), Vector3(-47.0, 0.0, -10.0),
			Vector3(-32.0, 0.0, 40.0), Vector3(33.0, 0.0, 41.0)])
	_choir_pavilion(terrace_slots[0])
	_fountain(terrace_slots[1])
	_orchard(terrace_slots[2])
	_saints_garden(terrace_slots[3])
	# destructible saints on the outer terrace
	for i in 4:
		var a := rng.randf_range(0.0, 360.0)
		var p := _polar(rng.randf_range(43.0, 52.0), a)
		if not _hits_blocker(Vector2(p.x, p.z), 3.0) and p.distance_to(get_player_spawn()) > 10.0:
			statue(p, &"saint", -deg_to_rad(a) - PI * 0.5)

	# Open-terrace enemy entries (cloud stairs) and spare objective anchors.
	for a: float in [160.0, 20.0, 250.0, 290.0]:
		enemy_spawn(_polar(56.0, a))
	objective(&"ritual", Vector3(0.0, 0.0, 44.0))
	objective(&"ritual", _polar(50.0, 230.0))
	objective(&"boss_arena", _polar(29.0, 90.0))

	var keep: Array[Vector3] = [Vector3(0, 0, 51), Vector3(0, 0, -50)]
	scatter({&"grass_tuft": 6.0, &"candles": 0.6, &"golden_tree": 0.5, &"marble_column": 0.3}, 70,
			Vector3.ZERO, OUTER_R + 3.0, 59.0, 2.0, keep)
	scatter({&"grass_tuft": 5.0, &"candles": 0.8}, 26, Vector3.ZERO, INNER_R + 2.0, OUTER_R - 2.5, 2.2, keep)
	for i in 36:
		var a := rng.randf() * TAU
		var r := rng.randf_range(OUTER_R + 3.0, 58.0)
		var p := Vector3(cos(a) * r, 0.0, sin(a) * r)
		if not _hits_blocker(Vector2(p.x, p.z), 1.5) and p.distance_to(get_player_spawn()) > 6.0:
			_flower_bush(p, rng.randf_range(0.5, 0.9))


func _dress_boundary() -> void:
	# Marble balustrade: posts every ~3 m with a rail, then a bank of cloud beyond.
	var pts := boundary_points(3.0)
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		box(Vector3(a.x, 0.0, a.y), Vector3(0.45, 1.15, 0.45), _marble, 0.0, false)
		var mid := (a + b) * 0.5
		var d := b - a
		box(Vector3(mid.x, 0.95, mid.y), Vector3(0.3, 0.22, d.length()), _marble_dark, atan2(d.x, d.y), false, false)
	for i in 70:
		var a := rng.randf() * TAU
		var r := bounds_radius + rng.randf_range(2.5, 12.0)
		var s := rng.randf_range(3.0, 7.0)
		# south (camera side) clouds sink so their tops stay low and never hide the player
		var y := 0.4 - 0.45 * s if sin(a) > 0.2 else rng.randf_range(-1.5, 0.2)
		sphere(Vector3(cos(a) * r, y, sin(a) * r), s, _cloud, 0.45, false)


# ---------------------------------------------------------------- pieces

func _polar(r: float, deg: float) -> Vector3:
	var a := deg_to_rad(deg)
	return Vector3(cos(a) * r, 0.0, sin(a) * r)


func _in_gap(deg: float, gaps: Array, r: float) -> bool:
	for g: float in gaps:
		var diff := absf(wrapf(deg - g, -180.0, 180.0))
		if deg_to_rad(diff) * r < GAP_W * 0.5:
			return true
	return false


## Ring of hedge segments with gaps; each segment solid. Gate posts flank every gap.
func _hedge_ring(r: float, gaps: Array, height: float) -> void:
	var n := ceili(TAU * r / 2.6)
	var seg := TAU * r / float(n)
	for i in n:
		var deg := 360.0 * (float(i) + 0.5) / float(n)
		if _in_gap(deg, gaps, r):
			continue
		var p := _polar(r, deg)
		var tangent_rot := -deg_to_rad(deg)  # box local Z along the tangent
		box(p, Vector3(1.5, height, seg + 0.15), _hedge if i % 3 else _hedge_dark, tangent_rot)
		# a few blossoms on top
		if rng.randf() < 0.6:
			sphere(p + Vector3(rng.randf_range(-0.4, 0.4), height + 0.05, rng.randf_range(-0.6, 0.6)), 0.16,
					_flowers[rng.randi() % _flowers.size()], 1.0, false)
	for g: float in gaps:
		var half := rad_to_deg(GAP_W * 0.5 / r) + 1.2
		for s: float in [-1.0, 1.0]:
			var p := _polar(r, g + s * half)
			box(p, Vector3(1.0, height + 0.9, 1.0), _marble, -deg_to_rad(g), true)
			sphere(p + Vector3(0, height + 1.15, 0), 0.32, _gold, 1.0, false)


func _breach(at: Vector3) -> void:
	# The rift: a sigil scorched into the marble, flames licking out of it, broken slabs around.
	var sig := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(7.0, 7.0)
	sig.mesh = pm
	sig.material_override = Props.sigil_material()
	sig.position = at + Vector3(0, 0.04, 0)
	sig.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sig.set_meta(&"keep", true)
	scenery.add_child(sig)
	for i in 5:
		var a := TAU * float(i) / 5.0 + 0.3
		flame(at + Vector3(cos(a) * 2.4, 0.0, sin(a) * 2.4), Vector2(0.8, 1.4))
	light(at + Vector3(0, 1.5, 0), Props.HELL_LIGHT, 3.5, 11.0, false, true)
	for i in 7:
		var a := rng.randf() * TAU
		var p := at + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(4.0, 6.0)
		if p.distance_to(get_player_spawn()) > 2.5:
			box(p, Vector3(rng.randf_range(0.8, 1.6), rng.randf_range(0.2, 0.5), rng.randf_range(0.8, 1.6)),
					_marble_dark, rng.randf() * TAU, false)
	landmark(&"the_breach", "The Breach", at, 7.0, &"start")


func _statue_avenue() -> void:
	for z: float in [43.0, 47.5]:
		for x: float in [-5.0, 5.0]:
			box(Vector3(x, 0.0, z), Vector3(1.4, 0.6, 1.4), _marble_dark, 0.0, true)
			prop(&"statue_angel", Vector3(x, 0.6, z), PI * 0.5 * signf(x), 0.9, 0.0)


func _pool(c: Vector3, deg: float, index: int = 0) -> void:
	disc(c, 4.4, _water)
	torus(c + Vector3(0, 0.15, 0), 4.3, 5.0, _marble)
	block_circle(c, 4.8, 1.0)
	cylinder(c, 0.5, 1.2, _marble, false)
	sphere(c + Vector3(0, 1.45, 0), 0.32, glow(Art.HOLY_WHITE, 1.6), 1.0, false)
	light(c + Vector3(0, 1.6, 0), Color(0.7, 0.85, 1.0), 1.4, 7.0, false)
	var names := ["Pool of Clear Mercy", "Pool of Still Waters", "Pool of Tears Unshed"]
	landmark(StringName("pool_%d" % int(deg)), names[index % names.size()], c, 6.0, &"pool")


func _parterre(c: Vector3) -> void:
	# low flower beds in a cross, walkable
	for i in 4:
		var a := PI * 0.5 * float(i) + PI * 0.25
		var p := c + Vector3(cos(a), 0, sin(a)) * 2.6
		box(p, Vector3(1.8, 0.25, 1.8), _hedge_dark, PI * 0.25, false, false)
		for k in 4:
			sphere(p + Vector3(rng.randf_range(-0.7, 0.7), 0.35, rng.randf_range(-0.7, 0.7)), 0.18,
					_flowers[rng.randi() % _flowers.size()], 1.0, false)
	prop(&"candles", c)


func _heart() -> void:
	disc(Vector3.ZERO, 8.0, _marble)
	torus(Vector3(0, 0.05, 0), 7.6, 8.1, _gold)
	disc(Vector3(0, 0.03, 0), 3.0, _marble_dark)
	prop(&"golden_tree", Vector3.ZERO, 0.0, 2.3, 1.4)
	light(Vector3(0, 4.5, 0), Props.HOLY_LIGHT, 2.6, 13.0, false, true)
	for i in 6:
		var a := TAU * float(i) / 6.0 + PI / 6.0
		var p := Vector3(cos(a), 0, sin(a)) * 6.0
		kit(&"broken_statue", p, -a + PI * 0.5, 1.0)  # PropKit (terrain role)
	landmark(&"gilded_tree", "The Gilded Tree", Vector3.ZERO, 9.0, &"heart")
	objective(&"relic", Vector3(0.0, 0.0, 10.5))


func _pearl_gate(at: Vector3) -> void:
	for x: float in [-5.5, 5.5]:
		var p := at + Vector3(x, 0, 0)
		cylinder(p, 2.0, 9.0, _marble, true, 1.8, 12)
		cylinder(p + Vector3(0, 9.0, 0), 2.1, 3.0, _gold, false, 0.05, 12)
		torus(p + Vector3(0, 6.5, 0), 1.85, 2.15, _gold, Vector3.ZERO)
	box(at + Vector3(0, 7.2, 0), Vector3(9.0, 1.4, 1.6), _marble, 0.0, false)
	box(at + Vector3(0, 8.6, 0), Vector3(6.0, 0.5, 1.0), _gold, 0.0, false)
	# the glowing veil of the gate itself (walk-through)
	box(at + Vector3(0, 0, -0.6), Vector3(7.0, 7.0, 0.1), glow(Art.HOLY_WHITE, 0.9), 0.0, false, false)
	light(at + Vector3(0, 4.0, 2.0), Props.HOLY_LIGHT, 3.0, 14.0, false, true)
	enemy_spawn(at + Vector3(0, 0, 3.5))
	enemy_spawn(at + Vector3(-9.0, 0, 4.0))
	enemy_spawn(at + Vector3(9.0, 0, 4.0))
	landmark(&"pearl_gate", "The Pearl Gate", at + Vector3(0, 0, 4.0), 9.0, &"gate")
	objective(&"ritual", at + Vector3(0, 0, 10.0))


func _choir_pavilion(c: Vector3) -> void:
	disc(c, 6.2, _marble)
	for i in 8:
		var a := TAU * float(i) / 8.0
		# visual-only kit column + a slim blocker: footprint blockers would seal the ring of columns
		kit(&"marble_column", c + Vector3(cos(a), 0, sin(a)) * 5.0, NAN, 1.0, false)
		block_circle(c + Vector3(cos(a), 0, sin(a)) * 5.0, 0.45, 4.0)
	sphere(c + Vector3(0, 0.9, 0), 0.5, glow(Art.HOLY, 2.2), 1.0, false)
	light(c + Vector3(0, 2.5, 0), Props.HOLY_LIGHT, 2.4, 10.0, false, true)
	prop(&"candles", c + Vector3(1.6, 0, 0))
	prop(&"candles", c + Vector3(-1.6, 0, 0.8))
	enemy_spawn(c)
	bell(c + Vector3(0, 0, -2.0))  # the choir bell: strike it to call the host (and its Ichor)
	landmark(&"choir_pavilion", "The Choir Pavilion", c, 7.0, &"shrine")
	objective(&"shrine", c)


func _fountain(c: Vector3) -> void:
	disc(c, 5.5, _marble_dark)
	cylinder(c, 3.6, 0.7, _marble, true, -1.0, 24)
	disc(c + Vector3(0, 0.66, 0), 3.3, _water, 24)
	cylinder(c, 1.4, 1.8, _marble, false, 1.0, 16)
	cylinder(c + Vector3(0, 1.8, 0), 1.6, 0.3, _gold, false, -1.0, 16)
	prop(&"statue_angel", c + Vector3(0, 2.1, 0), PI, 0.8)
	sphere(c + Vector3(0, 1.0, 0), 1.2, glow(Color(0.6, 0.8, 1.0), 0.5), 0.4, false)
	light(c + Vector3(0, 2.0, 0), Color(0.7, 0.85, 1.0), 2.0, 10.0, false, true)
	landmark(&"fountain_of_tears", "The Fountain of Tears", c, 7.0, &"shrine")
	objective(&"altar", c + Vector3(6.5, 0, 0))


func _orchard(c: Vector3) -> void:
	for gx in range(-2, 3):
		for gz in range(-1, 2):
			var p := c + Vector3(gx * 5.0 + rng.randf_range(-0.8, 0.8), 0, gz * 5.0 + rng.randf_range(-0.8, 0.8))
			if Vector2(p.x, p.z).length() > bounds_radius - 4.0:
				continue
			prop(&"golden_tree", p, NAN, rng.randf_range(0.8, 1.1), 0.7)
	enemy_spawn(c + Vector3(0, 0, -9.0))
	landmark(&"gilded_orchard", "The Gilded Orchard", c, 10.0, &"grove")


func _saints_garden(c: Vector3) -> void:
	var kinds: Array[StringName] = [&"broken_statue", &"statue_angel", &"broken_statue", &"statue_knight", &"marble_column"]
	for i in kinds.size():
		var a := TAU * float(i) / float(kinds.size())
		var p := c + Vector3(cos(a), 0, sin(a)) * 6.0
		box(p, Vector3(1.6, 0.5, 1.6), _marble_dark, a, true)
		prop(kinds[i], p + Vector3(0, 0.5, 0), -a + PI * 0.5, 1.0)
	disc(c, 3.0, _marble)
	prop(&"candles", c)
	landmark(&"garden_of_saints", "The Garden of Saints", c, 8.0, &"shrine")
	objective(&"altar", c)


func _lantern_pair(c: Vector3, ang: float) -> void:
	var side := Vector3(-sin(ang), 0, cos(ang)) * (GAP_W * 0.5 + 1.6)
	for s: float in [-1.0, 1.0]:
		var p := c + side * s
		kit(&"holy_brazier", p, 0.0, 0.9)
	light(c + Vector3(0, 2.6, 0), Props.HOLY_LIGHT, 1.3, 7.0, false)


func _flower_bush(p: Vector3, s: float) -> void:
	sphere(p + Vector3(0, s * 0.55, 0), s, _hedge, 0.8, true)
	for i in 4:
		var a := rng.randf() * TAU
		sphere(p + Vector3(cos(a) * s * 0.7, s * 0.85, sin(a) * s * 0.7), 0.13,
				_flowers[rng.randi() % _flowers.size()], 1.0, false)
