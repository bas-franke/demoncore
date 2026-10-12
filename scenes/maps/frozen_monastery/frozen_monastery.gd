extends GameMap
## The Frozen Monastery (mortal realm, difficulty 3). An irregular mountain plateau (polygon bounds,
## ~130 x 125) under snow. North = -Z = up on screen.
##
##   S   The Pilgrims' Stair: the demon climbs onto the plateau here (player start).
##   W   The Mirror of Penance: a wide frozen lake (walkable, open: the boss arena), penitents
##       frozen into the ice.
##   E   The Circle of Silent Stones: a ring of meditation stones around a flat altar stone.
##   N   The Cloister of the Silent Brothers: a walled courtyard with three gates, a bell stupa in the
##       middle and the Hall of Silence behind it. Beyond it, the Summit Shrine (NE).
## Three rock spurs and four pine groves break the plateau into lanes, so hordes funnel and you
## can't just run in circles: pick a lane, cut through a grove, or hold the lake.

const OUTLINE := [
	Vector2(-20, 64), Vector2(20, 66), Vector2(45, 54), Vector2(62, 30), Vector2(67, 0),
	Vector2(59, -30), Vector2(42, -54), Vector2(12, -66), Vector2(-18, -64), Vector2(-45, -51),
	Vector2(-63, -24), Vector2(-67, 8), Vector2(-56, 38), Vector2(-40, 56),
]

var _snow: Material
var _rock: Material
var _rock_dark: Material
var _pine: Material
var _bark: Material
var _ice: Material
var _wood: Material
var _plaster: Material
var _roof: Material
var _gold: Material
var _flags: Array[Material] = []


func _init() -> void:
	bounds_kind = Bounds.POLYGON
	bounds_polygon = PackedVector2Array(OUTLINE)


func _build_layout() -> void:
	_snow = mat(Color(0.9, 0.92, 0.96), 0.9, 0.0, 0.1, 0.0, &"")
	_rock = mat(Color(0.46, 0.48, 0.52), 0.9, 0.0, 0.5, 0.0, &"stone")
	_rock_dark = mat(Color(0.32, 0.34, 0.38), 0.9, 0.0, 0.6, 0.0, &"stone")
	_pine = mat(Color(0.08, 0.16, 0.12), 0.95, 0.0, 0.3, 0.0, &"")
	_bark = Props.bark_mat()
	_ice = mat(Color(0.62, 0.78, 0.9), 0.06, 0.25, 0.0, 0.0, &"")
	_wood = mat(Color(0.3, 0.16, 0.1), 0.85, 0.0, 0.4, 0.0, &"wood")
	_plaster = mat(Color(0.78, 0.74, 0.68), 0.9, 0.0, 0.5, 0.0, &"stone")
	_roof = mat(Color(0.42, 0.12, 0.1), 0.8, 0.0, 0.4, 0.0, &"wood")
	_gold = mat(Art.GOLD, 0.3, 0.9, 0.2, 0.0, &"metal")
	for c in [Color(0.8, 0.15, 0.12), Color(0.95, 0.8, 0.2), Color(0.15, 0.4, 0.8), Color(0.2, 0.6, 0.3), Color(0.95, 0.95, 0.9)]:
		_flags.append(mat(c, 0.95, 0.0, 0.2, 0.0, &"cloth"))

	set_player_spawn(Vector3(0.0, 0.0, 57.0))
	_pilgrim_stair(Vector3(0.0, 0.0, 60.0))
	# --- per-run variety: the lake and the stone circle swap sides, 4 of 6 rock spurs rise, the
	# groves drift and the interactables move between slots.
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	_frozen_lake(Vector3(-32.0 * side, 0.0, 4.0))
	_stone_circle(Vector3(36.0 * side, 0.0, 10.0))
	_cloister(Vector3(0.0, 0.0, -36.0))
	_summit_shrine(Vector3(30.0, 0.0, -46.0))

	# rock spurs: the lanes of the plateau
	var ridges := [
		[Vector2(-12, 30), Vector2(-4, 14)], [Vector2(14, -6), Vector2(25, -20)],
		[Vector2(-22, -18), Vector2(-8, -24)], [Vector2(18, 40), Vector2(30, 34)],
		[Vector2(-26, -38), Vector2(-14, -42)], [Vector2(6, 8), Vector2(16, 14)],
	]
	for r: Array in shuffled(ridges).slice(0, 4):
		_ridge(r[0], r[1])
	# pine groves (drift a few metres per run)
	for g: Array in [[Vector3(-36.0, 0, 38.0), 9.0, 12], [Vector3(50.0, 0, -12.0), 8.0, 9],
			[Vector3(-46.0, 0, -26.0), 8.0, 10], [Vector3(12.0, 0, 22.0), 6.0, 6], [Vector3(-14.0, 0, -52.0), 6.0, 6]]:
		var jitter := Vector3(rng.randf_range(-5.0, 5.0), 0.0, rng.randf_range(-4.0, 4.0))
		_grove(g[0] + jitter, g[1], g[2])
	# interactables: the cloister bell, a holy font, frozen saints to shatter
	bell(Vector3(7.0, 0.0, -40.0))
	font(pick_one([Vector3(22.0, 0.0, -38.0), Vector3(-20.0, 0.0, -4.0), Vector3(20.0, 0.0, 26.0)]))
	for p in shuffled([Vector3(-6, 0, 24), Vector3(10, 0, -2), Vector3(-26, 0, 30), Vector3(44, 0, 22),
			Vector3(-44, 0, 20), Vector3(26, 0, -30), Vector3(-30, 0, -40)]).slice(0, 4):
		if not _hits_blocker(Vector2(p.x, p.z), 2.0):
			statue(p, &"saint")
	# prayer flags strung along the main lanes
	_flag_line(Vector3(-6.0, 0, 44.0), Vector3(8.0, 0, 40.0))
	_flag_line(Vector3(20.0, 0, 2.0), Vector3(28.0, 0, -6.0))
	_flag_line(Vector3(-16.0, 0, -12.0), Vector3(-4.0, 0, -16.0))
	_flag_line(Vector3(10.0, 0, -18.0), Vector3(18.0, 0, -30.0))

	enemy_spawn(Vector3(-58.0, 0.0, 6.0))
	enemy_spawn(Vector3(58.0, 0.0, -24.0))
	enemy_spawn(Vector3(48.0, 0.0, 38.0))
	enemy_spawn(Vector3(-46.0, 0.0, 46.0))
	objective(&"ritual", Vector3(-4.0, 0.0, 36.0))
	objective(&"altar", Vector3(-48.0, 0.0, -8.0))

	scatter({&"rubble": 2.0, &"dead_shrub": 2.0, &"skull": 0.4, &"bone_pile": 0.3, &"candles": 0.3}, 60,
			Vector3.ZERO, 6.0, 62.0, 3.0, [get_player_spawn()])
	for i in 40:
		var a := rng.randf() * TAU
		var r := rng.randf_range(8.0, 60.0)
		var p := Vector3(cos(a) * r, 0.0, sin(a) * r)
		if _inside_bounds(Vector2(p.x, p.z), 3.0) and not _hits_blocker(Vector2(p.x, p.z), 1.0):
			sphere(p, rng.randf_range(0.6, 1.4), _snow, 0.35, false)  # snow drift, walkable


func _dress_boundary() -> void:
	# cliff edge: boulders just outside the outline; small ones on the south (camera) side
	var pts := boundary_points(3.0)
	for i in pts.size():
		var p := pts[i]
		var out := outward_at(p)
		var low := out.y > 0.35
		var s := rng.randf_range(0.6, 1.1) if low else rng.randf_range(1.6, 3.2)
		var q := p + out * (s * 0.7 + rng.randf_range(0.2, 1.2))
		sphere(Vector3(q.x, s * 0.2, q.y), s, _rock if i % 2 else _rock_dark, 0.7, not low)
		if not low and rng.randf() < 0.5:
			sphere(Vector3(q.x, s * 0.75, q.y), s * 0.55, _snow, 0.45, false)
	# far peaks to the north so the plateau reads as high ground
	for i in 16:
		var x := rng.randf_range(-90.0, 90.0)
		var z := rng.randf_range(-100.0, -78.0)
		var h := rng.randf_range(16.0, 34.0)
		cylinder(Vector3(x, -2.0, z), rng.randf_range(10.0, 18.0), h, _rock_dark, false, 0.5, 7)
		cylinder(Vector3(x, h * 0.62 - 2.0, z), h * 0.18, h * 0.38, _snow, false, 0.3, 7)


# ---------------------------------------------------------------- pieces

func _pine_tree(p: Vector3, s: float) -> void:
	cylinder(p, 0.28 * s, 1.4 * s, _bark, false, 0.22 * s, 6)
	block_circle(p, 0.55 * s, 3.0)
	for k in 3:
		var y := (1.0 + float(k) * 1.25) * s
		var r := (1.9 - float(k) * 0.5) * s
		cylinder(p + Vector3(0, y, 0), r, 1.9 * s, _pine, false, 0.05, 8)
		cylinder(p + Vector3(0, y + 0.55 * s, 0), r * 0.62, 0.7 * s, _snow, false, 0.05, 8, false)


func _grove(c: Vector3, r: float, count: int) -> void:
	var placed: Array[Vector3] = []
	for _i in count * 3:
		if placed.size() >= count:
			break
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * r
		var p := c + Vector3(cos(a) * d, 0, sin(a) * d)
		if not _inside_bounds(Vector2(p.x, p.z), 3.0) or p.distance_to(get_player_spawn()) < 7.0:
			continue
		var ok := true
		for q in placed:
			if q.distance_to(p) < 3.4:
				ok = false
				break
		if ok:
			placed.append(p)
			_pine_tree(p, rng.randf_range(0.85, 1.3))


func _ridge(a: Vector2, b: Vector2) -> void:
	var n := ceili(a.distance_to(b) / 2.4)
	for i in n + 1:
		var t := float(i) / float(n)
		var p := a.lerp(b, t) + Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))
		var s := rng.randf_range(1.4, 2.2) * (0.7 + 0.3 * sin(t * PI))
		sphere(Vector3(p.x, s * 0.3, p.y), s, _rock if i % 2 else _rock_dark, 0.8)
		sphere(Vector3(p.x, s * 0.95, p.y), s * 0.6, _snow, 0.4, false)
		block_circle(Vector3(p.x, 0, p.y), s * 0.95, 3.0)


func _flag_line(a: Vector3, b: Vector3) -> void:
	for p: Vector3 in [a, b]:
		cylinder(p, 0.1, 3.4, _wood, true, 0.08, 6)
	var n := ceili(a.distance_to(b) / 0.9)
	for i in n:
		var t := (float(i) + 0.5) / float(n)
		var sag := sin(t * PI) * 0.6
		var p := a.lerp(b, t) + Vector3(0, 3.2 - sag - 0.25, 0)
		var d := b - a
		box(p, Vector3(0.5, 0.42, 0.04), _flags[i % _flags.size()], atan2(d.x, d.z) + PI * 0.5, false, false)


func _pilgrim_stair(c: Vector3) -> void:
	for k in 4:
		box(c + Vector3(0, 0, float(k) * 1.4 - 1.0), Vector3(8.0 - float(k) * 0.6, 0.08 + 0.04 * k, 1.3), _rock, 0.0, false, false)
	for s: float in [-1.0, 1.0]:
		var p := c + Vector3(s * 5.0, 0, -4.0)
		box(p, Vector3(0.6, 1.8, 0.6), _rock_dark, 0.0, true)
		sphere(p + Vector3(0, 2.0, 0), 0.25, glow(Art.EMBER, 2.4), 1.0, false)
		light(p + Vector3(0, 2.2, 0), Props.FIRE_LIGHT, 1.4, 7.0)
	landmark(&"pilgrim_stair", "The Pilgrims' Stair", c, 6.0, &"start")


func _frozen_lake(c: Vector3) -> void:
	# ellipse of ice made from overlapping discs (walkable), dark cracks, penitents frozen in it
	for k in 7:
		var a := TAU * float(k) / 7.0
		disc(c + Vector3(cos(a) * 6.0, 0.0, sin(a) * 3.5), 9.5, _ice, 28)
	disc(c, 10.0, _ice, 28)
	for k in 9:
		var a := rng.randf() * TAU
		var p := c + Vector3(cos(a) * rng.randf_range(2.0, 11.0), 0.05, sin(a) * rng.randf_range(1.5, 7.0))
		box(p, Vector3(0.08, 0.02, rng.randf_range(2.0, 5.0)), _rock_dark, rng.randf() * TAU, false, false)
	for k in 4:
		var a := TAU * float(k) / 4.0 + 0.4
		var p := c + Vector3(cos(a) * 9.0, 0, sin(a) * 5.0)
		prop(&"statue_knight", p, rng.randf() * TAU, 1.0, 0.9)
		cylinder(p, 1.3, 1.1, _ice, false, 1.1, 10)
	light(c + Vector3(0, 4.0, 0), Color(0.6, 0.8, 1.0), 1.6, 16.0, false, true)
	landmark(&"frozen_lake", "The Mirror of Penance", c, 14.0, &"lake")
	objective(&"boss_arena", c)
	objective(&"altar", c + Vector3(14.0, 0, -6.0))


func _stone_circle(c: Vector3) -> void:
	for k in 9:
		var a := TAU * float(k) / 9.0
		var p := c + Vector3(cos(a), 0, sin(a)) * 8.0
		var h := rng.randf_range(2.4, 3.6)
		box(p, Vector3(1.2, h, 0.7), _rock_dark, -a, true)
		box(p + Vector3(0, h, 0), Vector3(1.25, 0.25, 0.75), _snow, -a, false, false)
	cylinder(c, 2.2, 0.35, _rock, false, 2.0, 10)
	prop(&"candles", c + Vector3(0, 0.35, 0))
	light(c + Vector3(0, 1.5, 0), Props.FIRE_LIGHT, 1.8, 8.0)
	landmark(&"stone_circle", "The Circle of Silent Stones", c, 9.0, &"shrine")
	objective(&"ritual", c)


func _cloister(c: Vector3) -> void:
	var w := 30.0
	var d := 24.0
	var hgt := 4.5
	var t := 1.2
	var gate := 6.0
	# south wall with central gate
	wall(c + Vector3(-w * 0.5, 0, d * 0.5), c + Vector3(-gate * 0.5, 0, d * 0.5), t, hgt, _plaster)
	wall(c + Vector3(gate * 0.5, 0, d * 0.5), c + Vector3(w * 0.5, 0, d * 0.5), t, hgt, _plaster)
	# west / east walls with side gates
	for s: float in [-1.0, 1.0]:
		wall(c + Vector3(s * w * 0.5, 0, -d * 0.5), c + Vector3(s * w * 0.5, 0, -gate * 0.5), t, hgt, _plaster)
		wall(c + Vector3(s * w * 0.5, 0, gate * 0.5), c + Vector3(s * w * 0.5, 0, d * 0.5), t, hgt, _plaster)
	# the Hall of Silence forms the north side
	var hall := c + Vector3(0, 0, -d * 0.5 - 3.0)
	box(hall, Vector3(w + 2.0, 7.0, 7.0), _plaster)
	prism(hall + Vector3(0, 7.0, 0), Vector3(w + 3.0, 3.6, 8.2), _roof, PI * 0.5)
	box(Vector3(hall.x, 0, hall.z + 3.56), Vector3(2.4, 3.6, 0.1), glow(Art.HOLY, 1.1), 0.0, false, false)
	# roof caps on the walls (snowy)
	for s: float in [-1.0, 1.0]:
		box(c + Vector3(s * w * 0.5, hgt, 0), Vector3(t + 0.5, 0.3, d + 0.5), _snow, 0.0, false, false)
	# arcade columns inside, bell stupa in the middle
	for k in 6:
		var x := c.x - 10.0 + float(k) * 4.0
		cylinder(Vector3(x, 0, c.z - 7.5), 0.35, 3.6, _plaster, true, 0.3, 8)
	cylinder(c, 2.6, 1.2, _plaster, true, 2.4, 12)
	cylinder(c + Vector3(0, 1.2, 0), 1.8, 2.4, _plaster, false, 1.0, 12)
	cylinder(c + Vector3(0, 3.6, 0), 1.0, 2.6, _gold, false, 0.05, 12)
	torus(c + Vector3(0, 2.2, 0), 1.75, 2.0, _gold)
	for x: float in [-9.0, 9.0]:
		prop(&"brazier", c + Vector3(x, 0, 5.0), NAN, 1.0, 0.6)
	light(c + Vector3(0, 3.0, 0), Props.HOLY_LIGHT, 2.4, 12.0, false, true)
	enemy_spawn(Vector3(hall.x, 0, hall.z + 6.0))
	landmark(&"cloister", "The Cloister of the Silent Brothers", c, 12.0, &"monastery")
	objective(&"relic", c + Vector3(0, 0, 5.0))


func _summit_shrine(c: Vector3) -> void:
	# a small three-tier pagoda on a stone platform
	box(c, Vector3(7.0, 0.5, 7.0), _rock, PI * 0.25, true)
	var y := 0.5
	for k in 3:
		var s := 4.4 - float(k) * 1.1
		box(c + Vector3(0, y, 0), Vector3(s, 1.8, s), _wood if k == 0 else _plaster, PI * 0.25, false)
		y += 1.8
		cylinder(c + Vector3(0, y, 0), s * 0.95, 0.9, _roof, false, 0.15, 4)
		y += 0.7
	sphere(c + Vector3(0, y + 0.4, 0), 0.4, _gold, 1.0, false)
	light(c + Vector3(0, 2.0, 3.0), Props.HOLY_LIGHT, 2.0, 9.0, false, true)
	_flag_line(c + Vector3(-6.0, 0, 5.0), c + Vector3(6.0, 0, 5.0))
	enemy_spawn(c + Vector3(-7.0, 0, -4.0))
	landmark(&"summit_shrine", "The Summit Shrine", c, 8.0, &"shrine")
	objective(&"altar", c + Vector3(0, 0, 7.5))
