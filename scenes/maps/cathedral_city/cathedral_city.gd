extends GameMap
## Cathedral City of Saint Aurel (mortal realm, difficulty 2). Walled square city, 140 x 140.
##
## Layout: a 4 x 4 grid of 32 m cells (24 m blocks, 8 m streets), north = -Z = up on screen.
##   row 0 (north):  [houses] [ CATHEDRAL (two cells) ] [graveyard + chapel of Saint Lune]
##   row 1:          [houses] [ cathedral plaza (two cells, open) ] [houses]
##   row 2:          [market square] [houses] [houses] [bell tower square]
##   row 3 (south):  [houses] [houses | south gate avenue | houses] [houses]
## The demon enters through the burning South Gate. Houses stand around the edge of each block
## with two lots left open, so every courtyard is reachable but the streets stay tight: kite down
## the avenues, fight in the plaza / market / graveyard. Some houses already burn.

const CELL := 32.0
const BLOCK := 24.0
const HALF := 64.0

var _stone: Material
var _stone_dark: Material
var _plaster: Array[Material] = []
var _roofs: Array[Material] = []
var _timber: Material
var _gold: Material
var _slate: Material
var _cloth: Array[Material] = []
var _stained: Material


func _init() -> void:
	bounds_kind = Bounds.RECT
	bounds_size = Vector2(140.0, 140.0)


func _build_layout() -> void:
	_stone = mat(Color(0.56, 0.53, 0.48), 0.85, 0.0, 0.55, 0.15, &"stone")
	_stone_dark = mat(Color(0.38, 0.36, 0.34), 0.9, 0.0, 0.6, 0.2, &"stone")
	for c in [Color(0.78, 0.72, 0.6), Color(0.7, 0.64, 0.54), Color(0.82, 0.78, 0.7), Color(0.66, 0.6, 0.5)]:
		_plaster.append(mat(c, 0.9, 0.0, 0.6, 0.0, &"stone"))
	for c in [Color(0.42, 0.16, 0.1), Color(0.3, 0.22, 0.2), Color(0.5, 0.24, 0.14), Color(0.22, 0.22, 0.26)]:
		_roofs.append(mat(c, 0.8, 0.0, 0.5, 0.1, &"wood"))
	_timber = mat(Color(0.2, 0.14, 0.09), 0.9, 0.0, 0.4, 0.0, &"wood")
	_gold = mat(Art.GOLD, 0.3, 0.9, 0.2, 0.0, &"metal")
	_slate = mat(Color(0.2, 0.22, 0.26), 0.7, 0.1, 0.4, 0.0, &"stone")
	for c in [Color(0.55, 0.1, 0.08), Color(0.12, 0.2, 0.42), Color(0.75, 0.6, 0.25)]:
		_cloth.append(mat(c, 0.95, 0.0, 0.3, 0.0, &"cloth"))
	_stained = glow(Color(0.55, 0.35, 0.9), 1.6)

	set_player_spawn(Vector3(0.0, 0.0, 62.0))
	_south_gate()
	# --- per-run variety: the graveyard, market and bell tower move between candidate cells, and the
	# house blocks / fires / alleys reroll. The cathedral, its plaza and the gate avenue are fixed.
	var graveyard_cell: String = pick_one(["30", "00"])
	var market_cell: String = pick_one(["02", "01", "03"])
	var bell_cell: String = pick_one(["32", "31"])
	for j in 4:
		for i in 4:
			var c := _city_cell(i, j)
			var cell := "%d%d" % [i, j]
			if cell == graveyard_cell:
				_graveyard(c)
				continue
			if cell == market_cell:
				_market(c)
				continue
			if cell == bell_cell:
				_bell_tower(c)
				continue
			match cell:
				"10":
					_cathedral(Vector3(0.0, 0.0, -48.0))
				"20", "21":
					pass  # covered by the cathedral / plaza builders
				"11":
					_plaza(Vector3(0.0, 0.0, -16.0))
				"13", "23":
					# narrower blocks either side of the wide gate avenue
					var sx := -1.0 if i == 1 else 1.0
					_house_block(c + Vector3(sx * 4.0, 0, 0), Vector2(BLOCK - 8.0, BLOCK))
				_:
					_house_block(c, Vector2(BLOCK, BLOCK))
	_street_dressing()
	# interactables: two holy fonts in the plaza corners, destructible saints along the avenues
	for p in shuffled([Vector3(-12, 0, -24), Vector3(12, 0, -24), Vector3(-12, 0, -8), Vector3(12, 0, -8)]).slice(0, 2):
		font(p)
	for p in shuffled([Vector3(-3, 0, 40), Vector3(3, 0, 30), Vector3(-3, 0, 20), Vector3(3, 0, 8),
			Vector3(-20, 0, -0.5), Vector3(20, 0, -0.5), Vector3(-36, 0, 0), Vector3(36, 0, 0)]).slice(0, 5):
		statue(p, &"saint")

	# city gates on the west and east walls + church doors: angels flood in from here
	enemy_spawn(Vector3(-66.0, 0.0, 16.0))
	enemy_spawn(Vector3(66.0, 0.0, -16.0))
	enemy_spawn(Vector3(-66.0, 0.0, -48.0))
	enemy_spawn(Vector3(66.0, 0.0, 48.0))
	landmark(&"west_gate", "The Pilgrims' Gate", Vector3(-64.0, 0.0, 16.0), 6.0, &"gate")
	landmark(&"east_gate", "The Bishop's Gate", Vector3(64.0, 0.0, -16.0), 6.0, &"gate")


func _city_cell(i: int, j: int) -> Vector3:
	return Vector3(-HALF + CELL * (float(i) + 0.5), 0.0, -HALF + CELL * (float(j) + 0.5))


# ---------------------------------------------------------------- houses

## A city block: a ring of house lots (3 x 3 grid minus the centre); two lots stay open as alleys.
func _house_block(c: Vector3, size: Vector2) -> void:
	var lots: Array[Vector2i] = []
	for gy in 3:
		for gx in 3:
			if gx == 1 and gy == 1:
				continue
			lots.append(Vector2i(gx, gy))
	# open one edge-middle lot (an alley into the courtyard) + one random other
	var edge_mids: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(2, 1), Vector2i(1, 2)]
	var alley := edge_mids[rng.randi() % 4]
	lots.erase(alley)
	lots.remove_at(rng.randi() % lots.size())
	var lot := Vector2(size.x / 3.0, size.y / 3.0)
	for l in lots:
		var p := c + Vector3((float(l.x) - 1.0) * lot.x, 0.0, (float(l.y) - 1.0) * lot.y)
		var w := minf(lot.x - rng.randf_range(0.8, 1.8), 7.8)
		var d := minf(lot.y - rng.randf_range(0.8, 1.8), 7.8)
		_house(p + Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4)), Vector2(w, d),
				rng.randf_range(3.0, 4.8), rng.randf() < 0.5)
	# courtyard: a well, a dead tree or a cart of rubble
	match rng.randi() % 3:
		0:
			cylinder(c, 0.9, 0.9, _stone_dark, true, -1.0, 12)
			box(c + Vector3(-0.9, 0, 0), Vector3(0.15, 2.0, 0.15), _timber, 0.0, false)
			box(c + Vector3(0.9, 0, 0), Vector3(0.15, 2.0, 0.15), _timber, 0.0, false)
			box(c + Vector3(0, 2.0, 0), Vector3(2.0, 0.15, 0.15), _timber, 0.0, false)
		1:
			prop(&"dead_tree", c, NAN, 0.8, 0.5)
		_:
			prop(&"rubble", c)
			prop(&"rubble", c + Vector3(1.2, 0, 0.8))


func _house(p: Vector3, size: Vector2, h: float, ridge_x: bool) -> void:
	var wall_m := _plaster[rng.randi() % _plaster.size()]
	box(p, Vector3(size.x, h, size.y), wall_m)
	# timber framing strips on the long sides
	box(p + Vector3(0, h - 0.25, 0), Vector3(size.x + 0.12, 0.25, size.y + 0.12), _timber, 0.0, false)
	box(p + Vector3(0, 0, 0), Vector3(size.x + 0.15, 0.5, size.y + 0.15), _stone_dark, 0.0, false, false)
	var roof_h := rng.randf_range(1.8, 2.8)
	var rsize := Vector3(size.x + 0.6, roof_h, size.y + 0.6) if not ridge_x else Vector3(size.y + 0.6, roof_h, size.x + 0.6)
	prism(p + Vector3(0, h, 0), rsize, _roofs[rng.randi() % _roofs.size()], 0.0 if not ridge_x else PI * 0.5)
	if rng.randf() < 0.4:
		box(p + Vector3(size.x * 0.25, h, size.y * 0.2), Vector3(0.6, roof_h + 0.6, 0.6), _stone_dark, 0.0, false)
	# the demon's arrival: some roofs are already ablaze
	if rng.randf() < 0.22:
		var top := p + Vector3(rng.randf_range(-1.0, 1.0), h + roof_h * 0.4, rng.randf_range(-1.0, 1.0))
		flame(top, Vector2(1.6, 2.6))
		flame(top + Vector3(0.8, -0.3, 0.4), Vector2(1.0, 1.8))
		light(top + Vector3(0, 1.5, 0), Props.FIRE_LIGHT, 2.8, 10.0)


# ---------------------------------------------------------------- set pieces

func _cathedral(c: Vector3) -> void:
	# nave along Z, facade toward the plaza (south, +Z)
	var nave := Vector3(16.0, 13.0, 26.0)
	box(c, nave, _stone)
	prism(c + Vector3(0, nave.y, 0), Vector3(nave.x + 1.0, 7.0, nave.z + 0.5), _slate)
	# transept
	box(c + Vector3(0, 0, -4.0), Vector3(30.0, 10.0, 8.0), _stone)
	prism(c + Vector3(0, 10.0, -4.0), Vector3(8.6, 5.0, 30.6), _slate, PI * 0.5)
	# apse
	cylinder(c + Vector3(0, 0, -13.0), 7.5, 11.0, _stone, true, -1.0, 16)
	cylinder(c + Vector3(0, 11.0, -13.0), 7.8, 4.0, _slate, false, 0.5, 16)
	# buttresses
	for k in 5:
		var z := c.z + 10.0 - float(k) * 5.0
		if k == 2:
			continue
		for s: float in [-1.0, 1.0]:
			box(Vector3(c.x + s * (nave.x * 0.5 + 0.9), 0, z), Vector3(1.8, 8.0, 1.2), _stone_dark)
	# twin towers + spires on the facade
	var front := c.z + nave.z * 0.5
	for s: float in [-1.0, 1.0]:
		var tp := Vector3(c.x + s * 6.5, 0, front - 1.0)
		box(tp, Vector3(6.0, 22.0, 6.0), _stone)
		box(tp + Vector3(0, 22.0, 0), Vector3(6.6, 0.8, 6.6), _stone_dark, 0.0, false)
		cylinder(tp + Vector3(0, 22.8, 0), 3.4, 11.0, _slate, false, 0.05, 8)
		sphere(tp + Vector3(0, 34.0, 0), 0.5, _gold, 1.0, false)
	# rose window + golden doors, glowing from the candles inside
	box(Vector3(c.x, 8.5, front + 0.05), Vector3(4.2, 4.2, 0.1), _stained, 0.0, false, false)
	torus(Vector3(c.x, 10.6, front + 0.12), 1.9, 2.3, _stone_dark, Vector3(PI * 0.5, 0, 0))
	box(Vector3(c.x, 0, front + 0.06), Vector3(3.4, 5.2, 0.12), glow(Art.HOLY, 1.2), 0.0, false, false)
	light(Vector3(c.x, 3.0, front + 2.5), Props.HOLY_LIGHT, 3.0, 12.0, false, true)
	enemy_spawn(Vector3(c.x, 0, front + 3.0))
	landmark(&"cathedral", "The Cathedral of Saint Aurel", Vector3(c.x, 0, front + 4.0), 12.0, &"cathedral")
	objective(&"relic", Vector3(c.x, 0, front + 6.0))
	# flanking side chapels' yards (the rest of row 0 middle cells)
	for s: float in [-1.0, 1.0]:
		prop(&"statue_angel", Vector3(c.x + s * 20.0, 0, front + 1.0), NAN, 1.1, 0.8)
		prop(&"crypt", Vector3(c.x + s * 22.0, 0, c.z - 6.0), NAN, 1.0, 1.4)


func _plaza(c: Vector3) -> void:
	# open plaza spanning two cells: fountain with Saint Aurel, braziers, banners, market litter
	cylinder(c, 3.4, 0.8, _stone, true, -1.0, 20)
	disc(c + Vector3(0, 0.76, 0), 3.1, mat(Color(0.18, 0.3, 0.38), 0.05, 0.3, 0.0, 0.0, &""), 20)
	box(c, Vector3(1.4, 2.4, 1.4), _stone_dark, PI * 0.25, false)
	prop(&"statue_knight", c + Vector3(0, 2.4, 0), PI, 1.15)
	for k in 4:
		var a := TAU * float(k) / 4.0 + PI * 0.25
		prop(&"brazier", c + Vector3(cos(a), 0, sin(a)) * 9.0, NAN, 1.0, 0.6)
	for x: float in [-14.0, 14.0]:
		prop(&"banner", c + Vector3(x, 0, -8.0), 0.0)
		prop(&"banner", c + Vector3(x, 0, 8.0), 0.0)
	scatter({&"candles": 1.0, &"rubble": 1.0, &"skull": 0.3}, 14, c, 5.0, 14.0, 2.5)
	landmark(&"plaza", "The Plaza of Saint Aurel", c, 12.0, &"plaza")
	objective(&"boss_arena", c + Vector3(0, 0, 6.0))
	objective(&"ritual", c + Vector3(-15.0, 0, 0))
	objective(&"altar", c + Vector3(15.0, 0, 0))


func _graveyard(c: Vector3) -> void:
	# low iron fence with a gate on the south side, rows of graves, a chapel at the back
	for k in 6:
		var x := c.x - 10.0 + float(k) * 4.0
		if absf(x - c.x) < 3.0:
			continue
		prop(&"iron_fence", Vector3(x, 0, c.z + 11.5), 0.0, 1.0)
		block_box(Vector3(x, 0, c.z + 11.5), Vector2(3.8, 0.4), 0.0, 1.5)
	for row in 3:
		for col in 6:
			var p := c + Vector3(-9.0 + col * 3.4, 0, -1.0 + row * 3.6)
			if absf(p.x - c.x) < 2.0:
				continue  # central path
			prop(&"holy_grave" if rng.randf() < 0.45 else &"gravestone", p + Vector3(rng.randf_range(-0.3, 0.3), 0, 0), rng.randf_range(-0.2, 0.2))
	prop(&"crypt", c + Vector3(-7.0, 0, 9.0), 0.0, 1.0, 1.2)
	prop(&"dead_tree", c + Vector3(8.5, 0, 8.0), NAN, 1.0, 0.5)
	# chapel of Saint Lune
	var ch := c + Vector3(0, 0, -8.0)
	kit(&"chapel", ch, 0.0, 1.0)  # PropKit chapel (terrain role); its own collision is off, nav blocker added
	light(Vector3(ch.x, 2.5, ch.z + 6.0), Props.HOLY_LIGHT, 2.0, 8.0, false, true)
	enemy_spawn(Vector3(ch.x, 0, ch.z + 6.5))
	landmark(&"graveyard", "The Graves of the Faithful", c, 12.0, &"graveyard")
	objective(&"altar", c + Vector3(0, 0, 3.0))
	scatter({&"candles": 1.0, &"skull": 0.6, &"grass_tuft": 2.0}, 12, c, 2.0, 11.0, 1.6)


func _market(c: Vector3) -> void:
	# stalls around the edge, gallows in the middle
	for k in 8:
		var a := TAU * float(k) / 8.0
		var p := c + Vector3(cos(a) * 9.5, 0, sin(a) * 9.5)
		var rot := -a + PI * 0.5
		box(p, Vector3(3.2, 1.0, 1.6), _timber, rot)
		for s: float in [-1.0, 1.0]:
			box(p + Basis(Vector3.UP, rot) * Vector3(s * 1.5, 0, 0.7), Vector3(0.12, 2.4, 0.12), _timber, rot, false)
		box(p + Vector3(0, 2.4, 0), Vector3(3.6, 0.1, 2.2), _cloth[k % _cloth.size()], rot, false)
	prop(&"gibbet", c, 0.0, 1.0, 0.8)
	prop(&"chains", c + Vector3(3.0, 0, 2.0))
	scatter({&"rubble": 1.0, &"candles": 0.4, &"bone_pile": 0.3}, 10, c, 2.5, 8.0, 2.0)
	landmark(&"market", "The Hay Market", c, 12.0, &"market")
	objective(&"ritual", c + Vector3(0, 0, 5.0))
	objective(&"altar", c + Vector3(-5.0, 0, -4.0))


func _bell_tower(c: Vector3) -> void:
	box(c, Vector3(7.0, 20.0, 7.0), _stone)
	# open belfry: four corner posts, the bell, a pyramid roof
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			box(c + Vector3(sx * 3.0, 20.0, sz * 3.0), Vector3(1.0, 5.0, 1.0), _stone_dark, 0.0, false)
	cylinder(c + Vector3(0, 21.0, 0), 1.6, 2.6, _gold, false, 0.7, 12)
	cylinder(c + Vector3(0, 25.0, 0), 5.2, 6.0, _slate, false, 0.05, 4)
	for k in 4:
		var a := TAU * float(k) / 4.0 + PI * 0.25
		prop(&"brazier", c + Vector3(cos(a), 0, sin(a)) * 8.0, NAN, 1.0, 0.6)
	enemy_spawn(c + Vector3(0, 0, 7.0))
	bell(c + Vector3(6.0, 0, 9.0))  # the tolling bell itself, brought down into the square
	landmark(&"bell_tower", "The Tower of the Tolling Bell", c, 10.0, &"tower")
	objective(&"altar", c + Vector3(-8.0, 0, 6.0))


func _south_gate() -> void:
	# The camera looks north from the south, so everything on the south edge stays low and sits
	# outside the bounds: tall pieces here would hide the player.
	var gz := HALF + 9.0
	for s: float in [-1.0, 1.0]:
		var tp := Vector3(s * 7.5, 0, gz)
		box(tp, Vector3(5.0, 6.0, 5.0), _stone, 0.0, false)
		cylinder(tp + Vector3(0, 6.0, 0), 3.2, 2.5, _roofs[0], false, 0.05, 4)
	# smashed portcullis, the breach is burning
	prop(&"rubble", Vector3(-4.5, 0, 66.0))
	prop(&"rubble", Vector3(4.0, 0, 67.0))
	for x: float in [-3.5, 3.5]:
		flame(Vector3(x, 0, 68.0), Vector2(1.2, 2.2))
	light(Vector3(0, 3.0, 66.0), Props.HELL_LIGHT, 3.0, 12.0)
	landmark(&"south_gate", "The Burning Gate", Vector3(0, 0, 58.0), 6.0, &"start")


## Banners, braziers and lanterns along the main avenues so the streets read from above.
func _street_dressing() -> void:
	for z in range(-24, 60, 12):
		if absf(z + 16.0) < 10.0:
			continue  # plaza
		for s: float in [-1.0, 1.0]:
			var p := Vector3(s * 3.4, 0, float(z))
			if rng.randf() < 0.5:
				cylinder(p, 0.1, 3.0, _timber, true, 0.08, 6)
				sphere(p + Vector3(0, 3.1, 0), 0.22, glow(Art.EMBER, 2.4), 1.0, false)
	# lanterns at the crossroads (lights are capped, so this is cheap)
	for x: float in [-32.0, 0.0, 32.0]:
		for z: float in [-32.0, 0.0, 32.0]:
			if x == 0.0 and z == -32.0:
				continue
			light(Vector3(x, 3.0, z), Props.FIRE_LIGHT, 1.6, 9.0)
			cylinder(Vector3(x + 2.8, 0, z + 2.8), 0.12, 3.2, _timber, true, 0.1, 6)
			sphere(Vector3(x + 2.8, 3.3, z + 2.8), 0.25, glow(Art.EMBER, 2.4), 1.0, false)
	scatter_rect({&"rubble": 2.0, &"banner": 0.3, &"skull": 0.3, &"bone_pile": 0.2}, 40,
			Vector3.ZERO, Vector2(128.0, 128.0), 0.0, 3.0, [get_player_spawn()])


func _dress_boundary() -> void:
	# city wall with crenellations and a tower every ~24 m (gates leave a gap in the merlons only)
	var h := bounds_size * 0.5
	var t := 2.4
	wall(Vector3(-h.x - t * 0.5, 0, -h.y - t), Vector3(h.x + t * 0.5, 0, -h.y - t), t, 6.0, _stone_dark, false)
	wall(Vector3(-h.x - t * 0.5, 0, h.y + t), Vector3(-8.0, 0, h.y + t), t, 3.0, _stone_dark, false)
	wall(Vector3(8.0, 0, h.y + t), Vector3(h.x + t * 0.5, 0, h.y + t), t, 3.0, _stone_dark, false)
	wall(Vector3(-h.x - t, 0, -h.y), Vector3(-h.x - t, 0, h.y), t, 6.0, _stone_dark, false)
	wall(Vector3(h.x + t, 0, -h.y), Vector3(h.x + t, 0, h.y), t, 6.0, _stone_dark, false)
	for k in range(-3, 4):
		var v := float(k) * 22.0
		for p: Vector3 in [Vector3(v, 0, -h.y - t), Vector3(-h.x - t, 0, v), Vector3(h.x + t, 0, v)]:
			cylinder(p, 2.6, 8.5, _stone, false, -1.0, 10)
			cylinder(p + Vector3(0, 8.5, 0), 3.0, 3.0, _roofs[3], false, 0.05, 10)
	# merlons along the inner edge
	for k in range(-34, 35):
		var v := float(k) * 2.0
		box(Vector3(v, 6.0, -h.y - t), Vector3(1.0, 0.8, t), _stone_dark, 0.0, false, false)
		box(Vector3(-h.x - t, 6.0, v), Vector3(t, 0.8, 1.0), _stone_dark, 0.0, false, false)
		box(Vector3(h.x + t, 6.0, v), Vector3(t, 0.8, 1.0), _stone_dark, 0.0, false, false)
		if absf(v) > 9.0:
			box(Vector3(v, 3.0, h.y + t), Vector3(1.0, 0.8, t), _stone_dark, 0.0, false, false)
	# gate arches in the west / east walls (visual)
	for s: float in [-1.0, 1.0]:
		var gz := 16.0 * -s
		box(Vector3(s * (h.x + t), 0, gz), Vector3(t + 0.4, 4.5, 5.0), glow(Art.HOLY, 0.5), 0.0, false, false)
