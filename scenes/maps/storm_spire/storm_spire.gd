extends GameMap
## The Storm Spire (heaven, difficulty 5). A lightning-wracked bastion: three stepped tiers climb
## around the Spire (radius 64). North = -Z = up on screen.
##
##   Outer tier (r 50-64): the Thunder Stair (player start, S), the Shattered Bastion ruins.
##   Tier walls at r 50 / 34 / 18 are low parapets with only TWO stair gaps each, and every ring's
##   stairs are turned 90 degrees from the ring outside it, so climbing to the Spire is a spiral:
##   half a lap per tier, fighting on narrow terraces.
##   Inner tier (r < 18): the Conductor's Ring of lightning rods at the foot of the Spire.
## Hazard: LightningStorm. Bolts fall around the demon all run (telegraphed), and any bolt landing
## near a lightning rod is pulled into the rod and arcs through the angels around it: lure them to
## the rods, keep off them yourself.
## Per-run variety: the stair angles, rod positions, the Bastion's place and the interactables.

const OUTER_R := 50.0
const MID_R := 34.0
const INNER_R := 18.0
const GAP_W := 6.0

var _slate: Material
var _slate_dark: Material
var _stone: Material
var _iron: Material
var _gold: Material
var _bolt: Material
var _rods: Array[Vector3] = []


func _init() -> void:
	bounds_kind = Bounds.CIRCLE
	bounds_radius = 64.0


func _build_layout() -> void:
	_slate = mat(Color(0.34, 0.36, 0.42), 0.8, 0.0, 0.5, 0.0, &"stone")
	_slate_dark = mat(Color(0.22, 0.23, 0.28), 0.85, 0.0, 0.6, 0.0, &"stone")
	_stone = mat(Color(0.55, 0.56, 0.6), 0.75, 0.0, 0.45, 0.1, &"stone")
	_iron = mat(Color(0.16, 0.17, 0.2), 0.45, 0.85, 0.4, 0.0, &"metal")
	_gold = mat(Art.GOLD, 0.3, 0.9, 0.2, 0.0, &"metal")
	_bolt = glow(Color(0.65, 0.82, 1.0), 2.6)

	set_player_spawn(Vector3(0.0, 0.0, 58.0))
	# tier floors (visual): darker the higher you climb
	disc(Vector3(0, 0.0, 0), OUTER_R, _slate, 48)
	disc(Vector3(0, 0.02, 0), MID_R, _stone, 40)
	disc(Vector3(0, 0.04, 0), INNER_R, _slate_dark, 32)

	var j := float(pick_one([-30.0, 0.0, 30.0]))
	var outer_gaps := [90.0 + j, 270.0 + j]
	var mid_gaps := [0.0 + j, 180.0 + j]
	var inner_gaps := [90.0 + j + 45.0, 270.0 + j + 45.0]
	_tier_wall(OUTER_R, outer_gaps)
	_tier_wall(MID_R, mid_gaps)
	_tier_wall(INNER_R, inner_gaps)
	_spire()

	# lightning rods: 2-3 per tier, never in a stairway
	var bands := [[INNER_R + 4.0, MID_R - 4.0, 3], [MID_R + 4.0, OUTER_R - 4.0, 4], [OUTER_R + 4.0, 60.0, 2]]
	for b: Array in bands:
		var placed := 0
		for _try in 30:
			if placed >= int(b[2]):
				break
			var a := rng.randf_range(0.0, 360.0)
			var p := _polar(rng.randf_range(b[0], b[1]), a)
			if _hits_blocker(Vector2(p.x, p.z), 4.0) or p.distance_to(get_player_spawn()) < 9.0:
				continue
			_rod(p)
			placed += 1
	_conductors_ring()
	_bastion(_polar(56.0, float(pick_one([160.0, 200.0, 20.0, 340.0]))))
	_thunder_stair(Vector3(0, 0, 60.0))

	var storm := LightningStorm.new()
	storm.rods = _rods
	tune(storm, "lightning")
	hazard(storm)

	# interactables
	for a: float in shuffled([45.0, 135.0, 225.0, 315.0]).slice(0, 2):
		bell(_polar((MID_R + OUTER_R) * 0.5, a + j), -deg_to_rad(a + j))
	font(_polar((INNER_R + MID_R) * 0.5, float(pick_one([30.0, 150.0, 210.0, 330.0])) + j))
	for i in 5:
		var p := _polar(rng.randf_range(INNER_R + 3.0, OUTER_R - 3.0), rng.randf_range(0.0, 360.0))
		if not _hits_blocker(Vector2(p.x, p.z), 2.5):
			statue(p, &"angel")

	# spawns, anchors, landmarks
	for a: float in [200.0, 250.0, 290.0, 340.0]:
		enemy_spawn(_polar(58.0, a + j))
	enemy_spawn(Vector3(0, 0, -9.0))
	for a: float in [30.0, 150.0, 250.0]:
		objective(&"altar", _polar(57.0, a + j))
	objective(&"ritual", _polar(42.0, 120.0 + j))
	objective(&"ritual", _polar(42.0, 300.0 + j))
	objective(&"relic", Vector3(0, 0, 9.5))
	objective(&"boss_arena", _polar(26.0, 60.0 + j))
	landmark(&"storm_spire", "The Storm Spire", Vector3.ZERO, 10.0, &"heart")

	scatter({&"rubble": 3.0, &"marble_column": 0.4, &"skull": 0.4, &"chains": 0.4, &"broken_statue": 0.3}, 50,
			Vector3.ZERO, 8.0, 61.0, 3.0, [get_player_spawn()])


func _dress_boundary() -> void:
	# a low iron rail at the edge, storm-black crags beyond (only north / sides stand tall)
	var pts := boundary_points(3.0)
	for i in pts.size():
		var p := pts[i]
		box(Vector3(p.x, 0, p.y), Vector3(0.3, 1.0, 0.3), _iron, 0.0, false)
	for i in 30:
		var a := TAU * float(i) / 30.0
		var south := sin(a) > 0.25
		var r := bounds_radius + rng.randf_range(4.0, 10.0)
		var s := rng.randf_range(4.0, 8.0)
		var y := 0.3 - 0.7 * s if south else rng.randf_range(-2.0, 2.0)
		sphere(Vector3(cos(a) * r, y, sin(a) * r), s, _slate_dark, 0.8, not south)


# ---------------------------------------------------------------- pieces

func _polar(r: float, deg: float) -> Vector3:
	var a := deg_to_rad(deg)
	return Vector3(cos(a) * r, 0.0, sin(a) * r)


func _in_gap(deg: float, gaps: Array, r: float) -> bool:
	for g: float in gaps:
		if deg_to_rad(absf(wrapf(deg - g, -180.0, 180.0))) * r < GAP_W * 0.5:
			return true
	return false


## A tier edge: low parapet in arc segments (solid), with stairs climbing through the gaps.
func _tier_wall(r: float, gaps: Array) -> void:
	var n := ceili(TAU * r / 3.0)
	var seg := TAU * r / float(n)
	for i in n:
		var deg := 360.0 * (float(i) + 0.5) / float(n)
		if _in_gap(deg, gaps, r):
			continue
		var p := _polar(r, deg)
		box(p, Vector3(1.6, 1.3, seg + 0.1), _stone if i % 3 else _slate, -deg_to_rad(deg))
	for g: float in gaps:
		# steps rising toward the centre (visual; the floor stays walkable) + rod-lamps either side
		for k in 4:
			var p := _polar(r + 1.6 - float(k) * 0.8, g)
			box(p + Vector3(0, 0, 0), Vector3(0.8, 0.12 + 0.08 * k, GAP_W - 0.4), _slate_dark, -deg_to_rad(g), false, false)
		for s: float in [-1.0, 1.0]:
			var q := _polar(r, g + s * rad_to_deg((GAP_W * 0.5 + 0.8) / r))
			cylinder(q, 0.5, 2.0, _stone, true, 0.4, 8)
			sphere(q + Vector3(0, 2.2, 0), 0.25, _bolt, 1.0, false)


func _spire() -> void:
	cylinder(Vector3.ZERO, 5.5, 3.0, _stone, true, 5.0, 16)
	cylinder(Vector3(0, 3.0, 0), 3.4, 14.0, _slate, false, 2.2, 12)
	for y: float in [6.0, 10.0, 14.0]:
		torus(Vector3(0, y, 0), 2.6 - y * 0.03, 3.2 - y * 0.03, _gold)
	cylinder(Vector3(0, 17.0, 0), 0.25, 9.0, _iron, false, 0.05, 6)
	sphere(Vector3(0, 21.0, 0), 1.2, _bolt, 1.0, false)
	light(Vector3(0, 8.0, 0), Color(0.6, 0.78, 1.0), 3.0, 18.0, false, true)


func _rod(p: Vector3) -> void:
	cylinder(p, 0.35, 0.5, _slate_dark, false, 0.3, 8)
	cylinder(p + Vector3(0, 0.5, 0), 0.1, 5.5, _iron, false, 0.06, 6)
	sphere(p + Vector3(0, 6.1, 0), 0.22, _bolt, 1.0, false)
	block_circle(p, 0.4, 6.0)
	light(p + Vector3(0, 5.8, 0), Color(0.6, 0.8, 1.0), 1.0, 6.0, false, true)
	_rods.append(p)


func _conductors_ring() -> void:
	for k in 4:
		var a := TAU * float(k) / 4.0 + PI * 0.25
		_rod(Vector3(cos(a), 0, sin(a)) * 12.0)
	landmark(&"conductors_ring", "The Conductor's Ring", Vector3(0, 0, 12.0), 8.0, &"rods")


func _bastion(c: Vector3) -> void:
	# a broken corner of the old bastion: columns, a fallen wall, a desecrated saint
	for k in 5:
		var a := TAU * float(k) / 5.0
		kit(&"marble_column", c + Vector3(cos(a), 0, sin(a)) * 4.5)
	kit(&"broken_statue", c, NAN, 1.2)
	wall(c + Vector3(-5.0, 0, -6.0), c + Vector3(3.0, 0, -7.0), 1.2, 2.2, _stone)
	landmark(&"shattered_bastion", "The Shattered Bastion", c, 8.0, &"ruin")


func _thunder_stair(c: Vector3) -> void:
	for k in 4:
		box(c + Vector3(0, 0, -float(k) * 1.2), Vector3(7.0 - float(k) * 0.5, 0.1 + 0.05 * k, 1.1), _slate_dark, 0.0, false, false)
	landmark(&"thunder_stair", "The Thunder Stair", c, 6.0, &"start")
