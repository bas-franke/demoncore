extends GameMap
## Heaven's Gate (heaven, difficulty 5, the final map). A processional of cloud terraces climbing
## north to the Seventh Gate (rect 90 x 150). North = -Z = up on screen.
##
##   S   The Last Stair: the demon arrives at the foot of the processional (player start).
##   Three Terraces of Ascent, each closed by a balustrade with two openings that zig-zag from
##   terrace to terrace (rolled per run), cloud banks and fonts on the terraces.
##   N   The Plaza of the Gate and the Seventh Gate itself, sealed by three Gate Wards (MapStatue
##       "ward") placed among five plinths. Break the wards, fell a guardian (any boss), then stand in
##       the opened Gate: RunState.end_run(true, &"seventh_gate") - the story ending
##       (docs/team/story.md). Without the story flag "known.march" the Gate stays shut (hint toast).
## Hazard: SweepingBeam x2 from the gate towers. Lances of light sweep down the processional,
## telegraphed by a line on the ground; they burn the demon, never the angels.

const HALF := Vector2(45.0, 75.0)
const GAP_W := 7.0
const TERRACE_Z := [40.0, 6.0, -28.0]
const GAP_X := [-30.0, -15.0, 0.0, 15.0, 30.0]

var _marble: Material
var _marble_dark: Material
var _gold: Material
var _pearl: Material
var _gate: SeventhGate


func _init() -> void:
	bounds_kind = Bounds.RECT
	bounds_size = HALF * 2.0


func _build_layout() -> void:
	_marble = mat(Color(0.9, 0.88, 0.83), 0.4, 0.0, 0.2, 0.0, &"marble")
	_marble_dark = mat(Color(0.74, 0.72, 0.67), 0.5, 0.0, 0.35, 0.0, &"stone")
	_gold = mat(Art.GOLD, 0.25, 0.95, 0.15, 0.0, &"metal")
	_pearl = mat(Color(0.95, 0.94, 0.9), 0.3, 0.1, 0.1, 0.0, &"marble")

	set_player_spawn(Vector3(0.0, 0.0, 66.0))
	landmark(&"last_stair", "The Last Stair", Vector3(0, 0, 66.0), 6.0, &"start")
	for k in 5:
		box(Vector3(0, 0, 72.0 - float(k) * 1.3), Vector3(10.0 - float(k) * 0.6, 0.08 + 0.05 * k, 1.2), _marble_dark, 0.0, false, false)

	# --- terraces: openings zig-zag (never the same x twice in a row) -> a long switchback climb
	var prev: Array = []
	var names := ["The Lower Terrace", "The Middle Terrace", "The Upper Terrace"]
	for t in TERRACE_Z.size():
		var choices := []
		for x: float in GAP_X:
			if not prev.has(x):
				choices.append(x)
		choices = shuffled(choices)
		var gaps := [choices[0]]
		for x: float in choices:
			if absf(x - float(choices[0])) >= 30.0:
				gaps.append(x)
				break
		_balustrade(TERRACE_Z[t], gaps)
		prev = gaps
		landmark(StringName("terrace_%d" % t), names[t], Vector3(0, 0, TERRACE_Z[t] + 12.0), 10.0, &"terrace")
	# terrace furniture: cloud banks (solid), cloud islands (walkable), fonts, saints
	for t in 3:
		var z0: float = TERRACE_Z[t] + 4.0
		var z1: float = (TERRACE_Z[t - 1] if t > 0 else 62.0) - 4.0
		for i in 3:
			var p := Vector3(rng.randf_range(-36.0, 36.0), 0, rng.randf_range(z0 + 2.0, z1 - 2.0))
			if not _hits_blocker(Vector2(p.x, p.z), 4.0) and p.distance_to(get_player_spawn()) > 10.0:
				kit(&"cloud_bank", p, NAN, rng.randf_range(1.2, 1.8))
		for i in 2:
			var p := Vector3(rng.randf_range(-38.0, 38.0), 0, rng.randf_range(z0, z1))
			kit(&"cloud_platform", p, NAN, 1.0, false)
		objective(&"altar", Vector3(rng.randf_range(-25.0, 25.0), 0, (z0 + z1) * 0.5))
		var sp := Vector3(rng.randf_range(-30.0, 30.0), 0, rng.randf_range(z0, z1))
		if not _hits_blocker(Vector2(sp.x, sp.z), 2.5):
			statue(sp, &"saint")
	for p in shuffled([Vector3(-28, 0, 22), Vector3(28, 0, 22), Vector3(-28, 0, -12), Vector3(28, 0, -12)]).slice(0, 2):
		font(p)
	bell(Vector3(float(pick_one([-32.0, 32.0])), 0, -42.0))
	objective(&"ritual", Vector3(-20.0, 0, 52.0))
	objective(&"ritual", Vector3(20.0, 0, -6.0))

	_plaza()
	for x: float in [-40.0, 40.0]:
		for z: float in [50.0, 20.0, -14.0]:
			kit(&"golden_gate", Vector3(x, 0, z), PI * 0.5 * signf(x), 1.0, true)
	for p: Vector3 in [Vector3(-41, 0, 34), Vector3(41, 0, 0), Vector3(-41, 0, -34), Vector3(41, 0, 52)]:
		enemy_spawn(p)


func _balustrade(z: float, gaps: Array) -> void:
	var x := -HALF.x
	while x < HALF.x:
		var nx := x + 3.0
		var mid := (x + nx) * 0.5
		var open := false
		for g: float in gaps:
			if absf(mid - g) < GAP_W * 0.5:
				open = true
		if not open:
			box(Vector3(mid, 0, z), Vector3(3.05, 1.0, 0.7), _marble)
			box(Vector3(x, 0, z), Vector3(0.5, 1.25, 0.9), _marble_dark, 0.0, false)
		x = nx
	for g: float in gaps:
		for s: float in [-1.0, 1.0]:
			kit(&"holy_brazier", Vector3(g + s * (GAP_W * 0.5 + 0.9), 0, z), 0.0, 1.0)


func _plaza() -> void:
	# The Seventh Gate on the north edge: tall pieces only up here, where they can't hide the demon.
	var gz := -HALF.y + 3.5
	disc(Vector3(0, 0, -50.0), 16.0, _pearl, 40)
	torus(Vector3(0, 0.05, -50.0), 15.5, 16.2, _gold)
	for s: float in [-1.0, 1.0]:
		var tp := Vector3(s * 11.0, 0, gz - 1.0)
		cylinder(tp, 3.2, 20.0, _marble, true, 2.6, 14)
		cylinder(tp + Vector3(0, 20.0, 0), 3.4, 6.0, _gold, false, 0.1, 14)
		sphere(tp + Vector3(0, 26.5, 0), 0.9, glow(Art.HOLY_WHITE, 3.0), 1.0, false)
		light(tp + Vector3(0, 8.0, 3.0), Art.HOLY, 2.6, 14.0, false, true)
		wall(Vector3(s * 14.0, 0, gz - 1.5), Vector3(s * HALF.x, 0, gz - 1.5), 2.0, 12.0, _marble_dark)
	box(Vector3(0, 9.0, gz - 1.0), Vector3(19.0, 3.0, 2.4), _marble, 0.0, false)
	box(Vector3(0, 12.0, gz - 1.0), Vector3(15.0, 1.0, 1.6), _gold, 0.0, false)
	# side blockers so the doorway is the only way "in"
	block_box(Vector3(-6.6, 0, gz - 1.0), Vector2(1.6, 2.0), 0.0, 8.0)
	block_box(Vector3(6.6, 0, gz - 1.0), Vector2(1.6, 2.0), 0.0, 8.0)
	_gate = SeventhGate.new()
	tune(_gate, "seventh_gate")
	hazard(_gate, Vector3(0, 0, gz - 1.0))
	statue_spawned.connect(func(st: MapStatue) -> void:
		if st.variant == &"ward":
			_gate.add_ward(st))
	# three Gate Wards on five plinths (rolled per run)
	var plinths := [Vector3(-24, 0, -50), Vector3(24, 0, -50), Vector3(-13, 0, -61), Vector3(13, 0, -61), Vector3(0, 0, -40)]
	for p: Vector3 in plinths:
		disc(p, 2.2, _marble_dark, 16)
	for p: Vector3 in shuffled(plinths).slice(0, 3):
		statue(p, &"ward", PI)
	# the gate towers sweep the processional with lances of light
	for s: float in [-1.0, 1.0]:
		var beam := SweepingBeam.new()
		beam.center = Vector3(s * 11.0, 0, gz - 1.0)
		beam.length = 60.0
		beam.inner_radius = 4.0
		beam.arc = PI * 0.55
		beam.rest = 14.0 + 4.0 * (s + 1.0)
		beam.start_delay = 30.0 + 15.0 * (s + 1.0)  # first lance at 30 s, the second at 60 s
		tune(beam, "sweeping_beam")
		hazard(beam)
	enemy_spawn(Vector3(0, 0, gz + 8.0))
	enemy_spawn(Vector3(-30, 0, -64.0))
	enemy_spawn(Vector3(30, 0, -64.0))
	landmark(&"seventh_gate", "The Seventh Gate", Vector3(0, 0, gz + 4.0), 10.0, &"gate")
	objective(&"relic", Vector3(-8.0, 0, -50.0))
	objective(&"boss_arena", Vector3(8.0, 0, -50.0))


func _dress_boundary() -> void:
	# cloud sea all around; on the south (camera) side the clouds sink below the terrace
	for i in 60:
		var side := i % 3
		var p: Vector3
		if side == 0:
			p = Vector3(-HALF.x - rng.randf_range(3.0, 9.0), 0, rng.randf_range(-HALF.y, HALF.y))
		elif side == 1:
			p = Vector3(HALF.x + rng.randf_range(3.0, 9.0), 0, rng.randf_range(-HALF.y, HALF.y))
		else:
			p = Vector3(rng.randf_range(-HALF.x, HALF.x), 0, HALF.y + rng.randf_range(3.0, 9.0))
		var s := rng.randf_range(4.0, 8.0)
		var y := (0.3 - 0.45 * s) if side == 2 else rng.randf_range(-1.5, 0.5)
		sphere(Vector3(p.x, y, p.z), s, _pearl, 0.45, false)
	# low gilded rail on the long sides
	for z in range(-70, 75, 3):
		for x: float in [-HALF.x, HALF.x]:
			box(Vector3(x, 0, float(z)), Vector3(0.4, 1.0, 0.4), _gold, 0.0, false)
