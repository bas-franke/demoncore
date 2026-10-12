extends GameMap
## The Sunlit Citadel (heaven, difficulty 4). Heaven's war-fortress on a round mesa, radius 66.
## North = -Z = up on screen.
##
##   Outer terrace (r 47-66): sun terraces with obelisks and gilded trees; the demon arrives at the
##       Sunward Approach (S).
##   Outer rampart (r 46): four gates (N, E, S, W) with gate towers.
##   Middle ward (r 25-45): barracks, the Hall of Lances training yard, the armoury, the reliquary of
##       the Host, braziers and banners. Tight but with a full ring corridor.
##   Inner rampart (r 24): only TWO gates, on the diagonals (SE and NW), offset from every outer gate,
##       so reaching the core always means a fight through the middle ward.
##   Core: the Sun Spire, a golden tower crowned by a burning sun, and the open Court of Noon around it.
## Ramparts are kept low (3.5 m) because the camera looks over them; gate towers are taller.

const OUTER_R := 46.0
const INNER_R := 24.0
const GATE_W := 7.0
const OUTER_GATES := [90.0, 0.0, 180.0, 270.0]
const INNER_GATES := [45.0, 225.0]

var _wall: Material
var _wall_dark: Material
var _gold: Material
var _white: Material
var _cloth: Material
var _roof: Material
var _rot := 0.0


func _init() -> void:
	bounds_kind = Bounds.CIRCLE
	bounds_radius = 66.0


func _build_layout() -> void:
	_wall = mat(Color(0.9, 0.84, 0.7), 0.6, 0.0, 0.35, 0.0, &"stone")
	_wall_dark = mat(Color(0.74, 0.66, 0.5), 0.7, 0.0, 0.45, 0.0, &"stone")
	_gold = mat(Art.GOLD, 0.28, 0.95, 0.15, 0.0, &"metal")
	_white = mat(Color(0.95, 0.93, 0.88), 0.4, 0.0, 0.2, 0.0, &"marble")
	_cloth = mat(Color(0.95, 0.85, 0.5), 0.9, 0.0, 0.2, 0.0, &"cloth")
	_roof = mat(Color(0.82, 0.62, 0.22), 0.4, 0.7, 0.25, 0.0, &"metal")

	set_player_spawn(Vector3(0.0, 0.0, 58.0))
	# --- per-run variety: the whole fortress turns by a multiple of 90 degrees (the four outer gates
	# stay cardinal, so the Sunward gate is always south), moving the inner gates, barracks, yard,
	# reliquary and gardens around the Spire.
	_rot = float(pick_one([0.0, 90.0, 180.0, 270.0]))
	_rampart(OUTER_R, OUTER_GATES, 3.5, 2.6)
	_rampart(INNER_R, INNER_GATES, 3.5, 2.2)
	for g: float in OUTER_GATES:
		_gate_towers(OUTER_R, g, 8.0)
		enemy_spawn(_polar(OUTER_R - 4.0, g) if g != 90.0 else _polar(OUTER_R + 5.0, 70.0))
	for g: float in INNER_GATES:
		_gate_towers(INNER_R, g, 7.0)
	_sun_spire()
	# the Spire sweeps its burning lance across the Court of Noon
	var beam := SweepingBeam.new()
	beam.center = Vector3.ZERO
	beam.length = INNER_R - 5.0
	beam.inner_radius = 4.5
	beam.start_delay = 20.0
	tune(beam, "sweeping_beam")
	hazard(beam)
	_middle_ward()
	_outer_terrace()
	# interactables: fonts of sunlight in the middle ward, the war bell of the Hall of Lances,
	# gilded saints to topple
	var mid := (OUTER_R + INNER_R) * 0.5
	for d: float in shuffled([100.0, 190.0, 280.0, 350.0]).slice(0, 2):
		font(_polar(mid, d))
	bell(_polar(mid + 4.5, 15.0), -deg_to_rad(15.0 + _rot))
	for d: float in shuffled([20.0, 75.0, 110.0, 175.0, 200.0, 235.0, 265.0, 290.0, 330.0]).slice(0, 6):
		var sp := _polar(mid + rng.randf_range(-5.0, 5.0), d)
		if not _hits_blocker(Vector2(sp.x, sp.z), 2.0):
			statue(sp, &"angel")
	landmark(&"sunward_approach", "The Sunward Approach", Vector3(0, 0, 56.0), 6.0, &"start")
	landmark(&"gate_of_noon", "The Gate of Noon", Vector3(0, 0, -OUTER_R), 7.0, &"gate")


func _polar(r: float, deg: float) -> Vector3:
	var a := deg_to_rad(deg + _rot)  # per-run rotation of the whole fortress (see _build_layout)
	return Vector3(cos(a) * r, 0.0, sin(a) * r)


func _in_gap(deg: float, gaps: Array, r: float, width: float) -> bool:
	for g: float in gaps:
		if deg_to_rad(absf(wrapf(deg - g, -180.0, 180.0))) * r < width * 0.5:
			return true
	return false


## Ring wall from arc segments with gaps; merlons along the top.
func _rampart(r: float, gaps: Array, h: float, thick: float) -> void:
	var n := ceili(TAU * r / 3.0)
	var seg := TAU * r / float(n)
	for i in n:
		var deg := 360.0 * (float(i) + 0.5) / float(n)
		if _in_gap(deg, gaps, r, GATE_W + 1.0):
			continue
		var p := _polar(r, deg)
		var rot := -deg_to_rad(deg)
		box(p, Vector3(thick, h, seg + 0.1), _wall if i % 4 else _wall_dark, rot)
		box(p + Vector3(0, h, 0), Vector3(thick * 0.35, 0.7, seg * 0.45), _wall_dark, rot, false, false)
		if i % 5 == 0:
			box(p + Vector3(0, h - 1.4, 0) + _polar(thick * 0.55, deg), Vector3(0.1, 1.2, 0.8), _gold, rot, false, false)


func _gate_towers(r: float, g: float, h: float) -> void:
	var half := rad_to_deg((GATE_W * 0.5 + 2.0) / r)
	for s: float in [-1.0, 1.0]:
		var p := _polar(r, g + s * half)
		cylinder(p, 2.2, h, _wall, true, 2.0, 10)
		cylinder(p + Vector3(0, h, 0), 2.5, 3.0, _roof, false, 0.05, 10)
		# gold sun disc on each tower
		sphere(p + Vector3(0, h + 3.2, 0), 0.35, _gold, 1.0, false)
	light(_polar(r, g) + Vector3(0, 3.0, 0), Props.HOLY_LIGHT, 1.8, 9.0, false)


func _sun_spire() -> void:
	disc(Vector3.ZERO, 12.0, _white)
	torus(Vector3(0, 0.04, 0), 11.6, 12.2, _gold)
	disc(Vector3(0, 0.03, 0), 6.0, _wall_dark)
	cylinder(Vector3.ZERO, 4.0, 3.0, _wall, true, 3.6, 16)
	cylinder(Vector3(0, 3.0, 0), 3.0, 14.0, _white, false, 2.4, 16)
	cylinder(Vector3(0, 17.0, 0), 3.2, 1.0, _gold, false, -1.0, 16)
	cylinder(Vector3(0, 18.0, 0), 2.4, 4.0, _gold, false, 0.4, 16)
	sphere(Vector3(0, 23.5, 0), 2.0, glow(Color(1.0, 0.86, 0.45), 3.0), 1.0, false)
	torus(Vector3(0, 23.5, 0), 2.6, 3.0, glow(Color(1.0, 0.8, 0.4), 2.0), Vector3(PI * 0.5, 0, 0))
	light(Vector3(0, 6.0, 0), Props.HOLY_LIGHT, 3.2, 18.0, false, true)
	for k in 4:
		var a := TAU * float(k) / 4.0 + PI * 0.25
		var p := Vector3(cos(a), 0, sin(a)) * 9.0
		_obelisk(p, 5.5)
	landmark(&"sun_spire", "The Sun Spire", Vector3.ZERO, 12.0, &"heart")
	objective(&"relic", Vector3(0, 0, 7.0))
	objective(&"boss_arena", Vector3(-10.0, 0, -10.0))
	enemy_spawn(Vector3(0, 0, -8.0))


func _obelisk(p: Vector3, h: float) -> void:
	box(p, Vector3(1.6, 0.5, 1.6), _wall_dark)
	cylinder(p + Vector3(0, 0.5, 0), 0.6, h, _white, false, 0.4, 4)
	cylinder(p + Vector3(0, 0.5 + h, 0), 0.42, 0.8, _gold, false, 0.02, 4)


func _middle_ward() -> void:
	var mid := (OUTER_R + INNER_R) * 0.5  # 35
	# barracks: long halls laid along the ring (tangent), leaving the corridor on both sides
	for deg: float in [120.0, 160.0, 300.0, 340.0]:
		var p := _polar(mid, deg)
		var rot := -deg_to_rad(deg)
		box(p, Vector3(7.0, 5.0, 12.0), _wall, rot)
		prism(p + Vector3(0, 5.0, 0), Vector3(7.6, 2.4, 12.6), _roof, rot)
		box(p + _polar(-3.55, deg), Vector3(0.1, 2.6, 1.8), glow(Art.HOLY, 0.9), rot, false, false)
	landmark(&"barracks", "The Barracks of the Host", _polar(mid, 140.0), 10.0, &"barracks")
	enemy_spawn(_polar(mid - 6.0, 140.0))
	enemy_spawn(_polar(mid + 6.0, 320.0))
	# Hall of Lances: training yard with kneeling knights and lance racks (east)
	var yard := _polar(mid, 30.0)
	for k in 6:
		var a := TAU * float(k) / 6.0
		var p := yard + Vector3(cos(a), 0, sin(a)) * 5.0
		prop(&"statue_knight", p, -a + PI * 0.5, 1.0, 0.8)
	for s: float in [-1.0, 1.0]:
		var rack := yard + _polar(s * 7.0, 120.0)
		box(rack, Vector3(3.0, 0.2, 0.4), _wall_dark, deg_to_rad(-30.0))
		for k in 5:
			box(rack + Vector3(float(k) * 0.55 - 1.1, 0, 0), Vector3(0.08, 3.4, 0.08), _gold, 0.0, false, false)
	landmark(&"hall_of_lances", "The Hall of Lances", yard, 8.0, &"yard")
	objective(&"ritual", yard)
	# reliquary of the Host (west): a domed shrine
	var rel := _polar(mid, 210.0)
	cylinder(rel, 4.0, 4.0, _white, true, -1.0, 14)
	sphere(rel + Vector3(0, 4.0, 0), 4.0, _roof, 0.6, false)
	box(rel + _polar(4.05, 30.0), Vector3(0.1, 2.6, 1.8), glow(Art.HOLY, 1.0), deg_to_rad(-30.0), false, false)
	light(rel + _polar(6.0, 30.0) + Vector3(0, 2.0, 0), Props.HOLY_LIGHT, 2.0, 9.0, false, true)
	landmark(&"reliquary", "The Reliquary of the Host", rel, 7.0, &"shrine")
	objective(&"altar", rel + _polar(7.0, 30.0))
	# the armoury yard (south-east, right inside the Sunward gate): crates of holy arms
	var arm := _polar(mid, 60.0)
	for k in 5:
		box(arm + Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-3, 3)), Vector3(1.4, 1.0, 1.0), _wall_dark, rng.randf() * TAU)
	objective(&"altar", _polar(mid, 250.0))
	# braziers and banners around the ring corridor
	for deg in range(0, 360, 30):
		var d := float(deg)
		if _in_gap(d, INNER_GATES, INNER_R, 12.0) or _in_gap(d, OUTER_GATES, OUTER_R, 12.0):
			continue
		var p := _polar(INNER_R + 3.2, d + 15.0)
		kit(&"holy_brazier", p)
		prop(&"banner", _polar(OUTER_R - 3.0, d), -deg_to_rad(d) + PI * 0.5)


func _outer_terrace() -> void:
	# obelisk garden (north-west) and gilded trees around the rim
	var og := _polar(56.0, 225.0)
	for k in 5:
		_obelisk(og + Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-5, 5)), rng.randf_range(4.0, 7.0))
	landmark(&"obelisk_garden", "The Garden of Obelisks", og, 9.0, &"garden")
	objective(&"altar", og + Vector3(0, 0, 6.0))
	for k in 18:
		var deg := rng.randf_range(0.0, 360.0)
		if _in_gap(deg, OUTER_GATES, 56.0, 14.0):
			continue
		var p := _polar(rng.randf_range(51.0, 61.0), deg)
		if p.distance_to(get_player_spawn()) < 8.0 or _hits_blocker(Vector2(p.x, p.z), 2.0):
			continue
		prop(&"golden_tree", p, NAN, rng.randf_range(0.8, 1.05), 0.7)
	# the Sunward Approach: braziers either side of the path to the south gate
	for z: float in [50.0, 54.0]:
		for x: float in [-5.0, 5.0]:
			kit(&"holy_brazier", Vector3(x, 0, z))
	objective(&"ritual", _polar(56.0, 20.0))
	scatter({&"candles": 1.0, &"rubble": 0.8, &"banner": 0.2}, 30, Vector3.ZERO, OUTER_R + 3.0, 63.0, 3.0,
			[get_player_spawn()])


func _dress_boundary() -> void:
	# low gilded parapet at the mesa's edge; sun-bleached cliffs beyond (only north / sides tall)
	var pts := boundary_points(2.5)
	for i in pts.size():
		var p := pts[i]
		box(Vector3(p.x, 0, p.y), Vector3(0.6, 0.9, 0.6), _wall_dark if i % 2 else _wall, 0.0, false)
		if i % 6 == 0:
			sphere(Vector3(p.x, 1.05, p.y), 0.22, _gold, 1.0, false)
	for i in 24:
		var a := TAU * float(i) / 24.0
		var south := sin(a) > 0.3
		var r := bounds_radius + rng.randf_range(4.0, 9.0)
		var s := rng.randf_range(5.0, 9.0)
		# south (camera side) clouds sink so their tops stay below ~0.5 m and never hide the player
		var h := 0.5 - 0.4 * s if south else rng.randf_range(-2.0, 1.0)
		sphere(Vector3(cos(a) * r, h, sin(a) * r), s, mat(Color(0.97, 0.95, 0.9), 1.0, 0.0, 0.0, 0.0, &""), 0.4, false)
