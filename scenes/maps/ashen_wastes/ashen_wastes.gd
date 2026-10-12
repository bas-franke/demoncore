extends GameMap
## The Ashen Wastes (the Verge, difficulty 3). A burned battlefield where Hell has already broken
## through: two rivers of cinder-lava cut the plain from west to east. North = -Z = up on screen.
##
##   S   The Pit's Mouth: the rift the demon climbs out of (player start).
##   Lower field: the Field of the Fallen Host (broken angel statues, impaler stakes).
##   Two lava rivers, each crossable only at two fords (rolled per run): you choose a ford, the
##   horde funnels through it. Between them, the burning Ballista.
##   N   The Angel War Camp: white tents, the war bell, holy fonts; the host marches out of it.
## Hazard: FissureField. Vents (lava pools) and the ground near the demon erupt in hellfire after a
## red warning: angels caught in it burn badly (Hell is on your side here), the demon only singes.

const OUTLINE := [
	Vector2(-24, 64), Vector2(26, 62), Vector2(52, 48), Vector2(66, 18), Vector2(64, -18),
	Vector2(50, -48), Vector2(18, -64), Vector2(-22, -62), Vector2(-50, -46), Vector2(-66, -14),
	Vector2(-64, 22), Vector2(-50, 50),
]
const RIVER_Z := [24.0, -18.0]
const FORD_W := 8.0

var _ash: Material
var _basalt: Material
var _lava: Material
var _cloth: Material
var _wood: Material
var _gold: Material
var _vents: Array[Vector3] = []


func _init() -> void:
	bounds_kind = Bounds.POLYGON
	bounds_polygon = PackedVector2Array(OUTLINE)


func _build_layout() -> void:
	_ash = mat(Color(0.26, 0.24, 0.23), 0.95, 0.0, 0.6, 0.0, &"stone")
	_basalt = mat(Color(0.12, 0.11, 0.12), 0.7, 0.0, 0.5, 0.0, &"stone")
	_lava = glow(Color(1.0, 0.36, 0.08), 1.15, false)
	_cloth = mat(Color(0.86, 0.82, 0.72), 0.95, 0.0, 0.4, 0.0, &"cloth")
	_wood = mat(Color(0.18, 0.12, 0.08), 0.9, 0.0, 0.5, 0.0, &"wood")
	_gold = mat(Art.GOLD, 0.35, 0.9, 0.3, 0.0, &"metal")

	set_player_spawn(Vector3(0.0, 0.0, 54.0))
	_pit_mouth(Vector3(0.0, 0.0, 58.0))
	# rivers with two fords each; the fords never line up (no straight run north)
	var fords_a := shuffled([-40.0, -20.0, 0.0, 20.0, 40.0]).slice(0, 2)
	var fords_b := []
	for x: float in shuffled([-40.0, -20.0, 0.0, 20.0, 40.0]):
		if fords_b.size() < 2 and not fords_a.has(x):
			fords_b.append(x)
	_river(RIVER_Z[0], fords_a, rng.randf() * TAU)
	_river(RIVER_Z[1], fords_b, rng.randf() * TAU)
	landmark(&"river_of_cinders", "The River of Cinders", Vector3(float(fords_a[0]), 0, RIVER_Z[0]), 8.0, &"river")
	_fallen_host(Vector3(rng.randf_range(-20.0, 20.0), 0, 42.0))
	_ballista(Vector3(float(pick_one([-28.0, 28.0])), 0, 3.0))
	_war_camp(Vector3(0.0, 0.0, -42.0))

	# lava vents (hazard targets) scattered over the field
	for i in 7:
		for _try in 20:
			var p := Vector3(rng.randf_range(-54.0, 54.0), 0, rng.randf_range(-50.0, 50.0))
			if not _inside_bounds(Vector2(p.x, p.z), 6.0) or _hits_blocker(Vector2(p.x, p.z), 4.0) \
					or p.distance_to(get_player_spawn()) < 12.0:
				continue
			kit(&"lava_pool", p, NAN, 1.0)
			_vents.append(p)
			break
	var vents := FissureField.new()
	vents.vents = _vents
	tune(vents, "fissures")
	hazard(vents)

	scatter({&"obsidian_spire": 1.0, &"basalt_columns": 1.0, &"brimstone_rock": 1.4, &"bone_heap": 1.2,
			&"impaler_spikes": 0.6, &"chain_posts": 0.5, &"dead_tree": 1.0, &"skull": 1.2, &"rubble": 1.5}, 70,
			Vector3.ZERO, 6.0, 64.0, 3.5, [get_player_spawn()])
	for p: Vector3 in [Vector3(-60, 0, 0), Vector3(60, 0, 4), Vector3(-44, 0, -44), Vector3(44, 0, -44)]:
		enemy_spawn(p)
	objective(&"ritual", Vector3(-30.0, 0, 46.0))
	objective(&"ritual", Vector3(30.0, 0, -4.0))
	objective(&"altar", Vector3(-38.0, 0, 6.0))
	objective(&"boss_arena", Vector3(0.0, 0, 3.0))


func _dress_boundary() -> void:
	var pts := boundary_points(3.5)
	for i in pts.size():
		var p := pts[i]
		var out := outward_at(p)
		var low := out.y > 0.35
		var s := rng.randf_range(0.7, 1.2) if low else rng.randf_range(1.6, 3.4)
		var q := p + out * (s * 0.6 + 0.5)
		sphere(Vector3(q.x, s * 0.15, q.y), s, _basalt, 0.7, not low)
		if not low and i % 4 == 0:
			kit(&"obsidian_spire", Vector3(q.x, 0, q.y) + Vector3(out.x, 0, out.y) * 2.5, NAN, 1.3, false)


# ---------------------------------------------------------------- pieces

## A river of cinder-lava across the whole map at `z` (sine-meandering), solid except at `fords`.
func _river(z: float, fords: Array, phase: float) -> void:
	var x := -70.0
	var step := 3.0
	while x < 70.0:
		var mid := x + step * 0.5
		var zc := z + sin(mid * 0.07 + phase) * 4.0
		var ford := false
		for f: float in fords:
			if absf(mid - f) < FORD_W * 0.5:
				ford = true
		var dz := (sin((mid + 0.1) * 0.07 + phase) - sin((mid - 0.1) * 0.07 + phase)) * 4.0 / 0.2
		var rot := atan2(1.0, dz) # local Z along the river direction (1, dz)
		if not ford:
			box(Vector3(mid, 0.0, zc), Vector3(4.2, 0.06, step + 0.4), _lava, rot, false, false)
			block_box(Vector3(mid, 0.0, zc), Vector2(4.2, step + 0.4), rot, 2.0)  # lava: impassable
			box(Vector3(mid, 0.0, zc) + Vector3(-sin(rot + PI * 0.5), 0, -cos(rot + PI * 0.5)) * 2.6,
					Vector3(1.0, 0.35, step + 0.3), _basalt, rot, false)
			box(Vector3(mid, 0.0, zc) + Vector3(sin(rot + PI * 0.5), 0, cos(rot + PI * 0.5)) * 2.6,
					Vector3(1.0, 0.35, step + 0.3), _basalt, rot, false)
		else:
			# ford stones: basalt slabs across the gap, glowing seams
			box(Vector3(mid, 0.0, zc), Vector3(4.6, 0.08, step), _basalt, rot, false, false)
		x += step
	for f: float in fords:
		var zc := z + sin(f * 0.07 + phase) * 4.0
		for s: float in [-1.0, 1.0]:
			kit(&"hell_brazier", Vector3(f + s * (FORD_W * 0.5 + 1.0), 0, zc + 3.4), 0.0, 1.0)
		light(Vector3(f, 1.5, zc), Props.HELL_LIGHT, 1.8, 10.0)


func _pit_mouth(c: Vector3) -> void:
	var sig := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8.0, 8.0)
	sig.mesh = pm
	sig.material_override = Props.sigil_material()
	sig.position = c + Vector3(0, 0.05, 0)
	sig.set_meta(&"keep", true)
	sig.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scenery.add_child(sig)
	for i in 6:
		var a := TAU * float(i) / 6.0
		flame(c + Vector3(cos(a), 0, sin(a)) * 3.2, Vector2(0.9, 1.6))
	light(c + Vector3(0, 1.5, 0), Props.HELL_LIGHT, 3.5, 12.0, false, true)
	landmark(&"pit_mouth", "The Pit's Mouth", c, 7.0, &"start")


func _fallen_host(c: Vector3) -> void:
	for i in 7:
		var p := c + Vector3(rng.randf_range(-12.0, 12.0), 0, rng.randf_range(-6.0, 6.0))
		if p.distance_to(get_player_spawn()) > 7.0 and not _hits_blocker(Vector2(p.x, p.z), 2.0):
			kit(&"broken_statue", p, NAN, rng.randf_range(0.9, 1.2))
	for i in 3:
		var p := c + Vector3(rng.randf_range(-14.0, 14.0), 0, rng.randf_range(-7.0, 7.0))
		if p.distance_to(get_player_spawn()) > 7.0 and not _hits_blocker(Vector2(p.x, p.z), 2.0):
			kit(&"impaler_spikes", p)
	landmark(&"fallen_host", "The Field of the Fallen Host", c, 12.0, &"field")
	objective(&"altar", c + Vector3(0, 0, -8.0))


func _ballista(c: Vector3) -> void:
	# a wrecked angelic siege engine, still burning
	box(c, Vector3(4.0, 1.2, 7.0), _wood, 0.4)
	box(c + Vector3(0, 1.2, 0), Vector3(0.6, 0.6, 9.0), _wood, 0.4, false)
	box(c + Vector3(0, 1.6, -1.0), Vector3(7.0, 0.35, 0.35), _gold, 0.4, false)
	for k in 3:
		flame(c + Vector3(rng.randf_range(-1.5, 1.5), 1.2, rng.randf_range(-2.5, 2.5)), Vector2(1.2, 2.0))
	light(c + Vector3(0, 2.5, 0), Props.FIRE_LIGHT, 2.5, 10.0)
	landmark(&"burning_ballista", "The Burning Ballista", c, 7.0, &"wreck")
	objective(&"relic", c + Vector3(0, 0, 7.0))


func _war_camp(c: Vector3) -> void:
	# white tents in two rows, standards, the war bell, fonts of the host
	for row in 2:
		for col in 4:
			var p := c + Vector3(-21.0 + col * 14.0, 0, -6.0 + row * 14.0)
			if rng.randf() < 0.2:
				kit(&"bone_heap", p)  # a tent already burned to the ground
				continue
			box(p, Vector3(5.0, 0.4, 5.0), _wood, 0.0)
			prism(p + Vector3(0, 0.4, 0), Vector3(5.2, 3.4, 5.2), _cloth)
			prop(&"banner", p + Vector3(3.2, 0, 2.8), 0.0)
	bell(c + Vector3(0, 0, 1.0))
	font(c + Vector3(float(pick_one([-14.0, 14.0])), 0, 1.0))
	for i in 3:
		statue(c + Vector3(rng.randf_range(-24.0, 24.0), 0, 15.0 + rng.randf_range(0.0, 4.0)), &"angel")
	enemy_spawn(c + Vector3(-8.0, 0, -12.0))
	enemy_spawn(c + Vector3(8.0, 0, -12.0))
	landmark(&"war_camp", "The Angel War Camp", c, 14.0, &"camp")
	objective(&"altar", c + Vector3(-28.0, 0, 8.0))
