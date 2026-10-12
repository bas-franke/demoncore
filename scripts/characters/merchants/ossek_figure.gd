extends MerchantFigure
## Wayfarer Ossek (cartographer): a lanky, long-limbed wanderer-demon in a weathered greatcoat
## with a ragged hem, a scarf, a wide-brimmed hat pierced by two swept horns, a satchel bristling
## with scroll cases, and a staff planted beside him with a soul lantern hanging from its crook.
## Idle: ponders an unrolled map held in both hands: studies it, turns it a quarter round, frowns,
## scratches his jaw, traces a route with a claw. Greets by lowering the map and tipping the hat;
## a sale gets a satisfied roll of the map.

const STUDY := 3.2
const ROTATE := 1.2
const SCRATCH := 1.6
const TEAL := Color(0.35, 0.95, 0.9)

var _arm_r: Array[Node3D] = []
var _arm_l: Array[Node3D] = []
var _map: Node3D
var _map_sheet: Node3D
var _lantern: Node3D
var _hat: Node3D


func build() -> void:
	var coat := Art.mat(Color(0.14, 0.13, 0.11), 0.9, 0.0, 0.5, true, 0.15, &"cloth")
	var coat_dk := Art.mat(Color(0.09, 0.08, 0.07), 0.9, 0.0, 0.5, true, 0.15, &"cloth")
	var leather := Art.mat(Art.LEATHER.darkened(0.25), 0.85, 0.0, 0.5, true, 0.0, &"leather")
	var skin := Art.mat(Color(0.34, 0.27, 0.22), 0.62, 0.0, 0.3, true, 0.12, &"skin")
	var paper := Art.mat(Color(0.78, 0.7, 0.55), 0.9, 0.0, 0.35, true, 0.0, &"parchment")
	var horn_m := Art.mat(Color(0.22, 0.2, 0.18), 0.6, 0.0, 0.4, true, 0.0, &"bone")
	var wood := Art.mat(Color(0.25, 0.18, 0.12), 0.85, 0.0, 0.4, true, 0.0, &"wood")

	# Long thin legs in boots under the coat.
	for s: float in [-1.0, 1.0]:
		EnemyModel.limb(self, Vector3(s * 0.12, 0.95, 0.0), Vector3(s * 0.14, 0.12, 0.02), 0.07, coat_dk)
		Art.part(self, Art.box(), leather, Vector3(s * 0.14, 0.09, -0.04), Vector3(0.14, 0.18, 0.28))
	torso = Art.pivot(self, Vector3(0.0, 0.95, 0.0), Vector3(-0.12, 0.0, 0.0))
	# Greatcoat: chest + long split skirt with a ragged hem.
	Art.part(torso, Art.sphere(), coat, Vector3(0.0, 0.38, 0.0), Vector3(0.6, 0.78, 0.4))
	Art.part(torso, Art.cylinder(0.3, 0.38), coat, Vector3(0.0, -0.25, 0.04), Vector3(1.0, 0.75, 1.0))
	for k in 9:
		var a := TAU * float(k) / 9.0 + 0.2
		Art.part(torso, Art.box(), coat_dk, Vector3(cos(a) * 0.36, -0.66, sin(a) * 0.36 + 0.04),
			Vector3(0.13, 0.12 + 0.06 * float(k % 3), 0.02), Vector3(0.0, -a + PI * 0.5, 0.0))
	# Scarf, belt, satchel with scroll cases.
	Art.part(torso, Art.torus(0.4, 0.55), Art.mat(Color(0.32, 0.1, 0.07), 0.9, 0.0, 0.4, true, 0.0, &"cloth"),
		Vector3(0.0, 0.72, 0.0), Vector3(0.5, 0.4, 0.45))
	Art.part(torso, Art.torus(0.42, 0.48), leather, Vector3(0.0, 0.08, 0.0), Vector3(0.66, 0.5, 0.44))
	EnemyModel.limb(torso, Vector3(-0.22, 0.7, -0.15), Vector3(0.24, 0.0, -0.16), 0.02, leather)
	var satchel := Art.pivot(torso, Vector3(0.3, 0.0, 0.08))
	Art.part(satchel, Art.box(), leather, Vector3.ZERO, Vector3(0.14, 0.3, 0.3))
	for k in 4:
		Art.part(satchel, Art.cylinder(0.5, 0.5), paper if k % 2 == 0 else leather,
			Vector3(0.0, 0.22, -0.1 + 0.07 * float(k)), Vector3(0.06, 0.34, 0.06), Vector3(0.15 * float(k - 1), 0.0, 0.25))

	_arm_r = arm(torso, Vector3(0.3, 0.66, 0.0), 0.42, 0.4, 0.065, 0.06, coat, skin, 0.08)
	_arm_l = arm(torso, Vector3(-0.3, 0.66, 0.0), 0.42, 0.4, 0.065, 0.06, coat, skin, 0.08)
	for a: Array[Node3D] in [_arm_r, _arm_l]:
		Art.part(a[1], Art.cylinder(0.5, 0.5), coat_dk, Vector3(0.0, -0.33, 0.0), Vector3(0.15, 0.08, 0.15))
		Art.part(a[2], Art.cone(0.5), horn_m, Vector3(0.0, -0.15, -0.02), Vector3(0.025, 0.08, 0.025), Vector3(PI, 0.0, 0.0))

	# Head: long gaunt face, teal eyes, wide-brimmed hat with horns through the crown.
	head = Art.pivot(torso, Vector3(0.0, 0.92, -0.03))
	Art.part(head, Art.sphere(), skin, Vector3.ZERO, Vector3(0.3, 0.38, 0.32))
	Art.part(head, Art.box(), skin, Vector3(0.0, -0.17, -0.06), Vector3(0.18, 0.14, 0.2))
	for s: float in [-1.0, 1.0]:
		Art.part(head, Art.sphere(), Art.glow(TEAL, 3.0), Vector3(s * 0.065, 0.03, -0.15), Vector3(0.05, 0.028, 0.03))
	_hat = Art.pivot(head, Vector3(0.0, 0.13, 0.0))
	Art.part(_hat, Art.cylinder(0.5, 0.5), leather, Vector3.ZERO, Vector3(0.85, 0.025, 0.85), Vector3(0.08, 0.0, 0.0))
	Art.part(_hat, Art.cylinder(0.3, 0.38), leather, Vector3(0.0, 0.12, 0.0), Vector3(0.5, 0.22, 0.5))
	Art.part(_hat, Art.cylinder(0.5, 0.5), Art.mat(Color(0.3, 0.1, 0.07), 0.9), Vector3(0.0, 0.05, 0.0),
		Vector3(0.39, 0.04, 0.39))
	for s: float in [-1.0, 1.0]:
		horn(_hat, Vector3(s * 0.12, 0.12, 0.02), [Vector3(s * 0.12, 0.14, 0.06), Vector3(s * 0.08, 0.14, 0.12)], 0.035,
			0.015, horn_m)

	# The map: two leaves of parchment with inked routes, held before him.
	_map = Art.pivot(self, Vector3(0.0, 1.45, -0.42), Vector3(-0.9, 0.0, 0.0))
	_map_sheet = Art.pivot(_map)
	for s: float in [-1.0, 1.0]:
		Art.part(_map_sheet, Art.box(), paper, Vector3(s * 0.2, 0.0, 0.0), Vector3(0.4, 0.008, 0.46), Vector3(0.0, 0.0, -s * 0.1))
	var ink := Art.mat(Color(0.15, 0.08, 0.05), 0.9)
	for k in 5:
		Art.part(_map_sheet, Art.box(), ink, Vector3(-0.3 + 0.14 * float(k), 0.012, -0.1 + 0.07 * sin(float(k) * 2.0)),
			Vector3(0.12, 0.002, 0.01), Vector3(0.0, 0.6 * sin(float(k) * 1.7), 0.0))
	Art.part(_map_sheet, Art.sphere(), Art.glow(Art.HELLFIRE, 2.5), Vector3(0.22, 0.015, 0.08), Vector3(0.03, 0.005, 0.03))

	# Staff planted beside him, soul lantern hanging from the crook.
	var staff := Art.pivot(self, Vector3(-0.62, 0.0, -0.1))
	EnemyModel.limb(staff, Vector3.ZERO, Vector3(0.05, 2.3, 0.0), 0.035, wood)
	EnemyModel.limb(staff, Vector3(0.05, 2.3, 0.0), Vector3(-0.15, 2.45, 0.0), 0.03, wood)
	_lantern = Art.pivot(staff, Vector3(-0.17, 2.42, 0.0))
	EnemyModel.limb(_lantern, Vector3.ZERO, Vector3(0.0, -0.2, 0.0), 0.006, Art.mat(Art.OBSIDIAN, 0.4, 0.8))
	# Open cage: a cap, a base and four corner bars around the soul flame.
	var cage := Art.mat(Art.OBSIDIAN, 0.4, 0.8)
	Art.part(_lantern, Art.cone(0.5), cage, Vector3(0.0, -0.17, 0.0), Vector3(0.18, 0.08, 0.18))
	Art.part(_lantern, Art.box(), cage, Vector3(0.0, -0.42, 0.0), Vector3(0.15, 0.03, 0.15))
	for k in 4:
		var a := TAU * float(k) / 4.0 + PI * 0.25
		EnemyModel.limb(_lantern, Vector3(cos(a) * 0.07, -0.2, sin(a) * 0.07), Vector3(cos(a) * 0.07, -0.41, sin(a) * 0.07),
			0.008, cage)
	Art.part(_lantern, Art.sphere(), Art.glow(TEAL, 2.6), Vector3(0.0, -0.3, 0.0), Vector3.ONE * 0.1)
	Art.light(_lantern, TEAL, 1.0, 4.0, Vector3(0.0, -0.3, 0.0))


func pose(_delta: float) -> void:
	var g := greet_w
	var j := joy_w
	var cycle := STUDY + ROTATE + STUDY + SCRATCH
	var c := fmod(t, cycle)
	var turned := 0.0   # map quarter-turn progress
	var scratch := 0.0  # left hand to the jaw
	var trace := 0.0    # right claw tracing the route
	var turn_count := int(t / cycle)
	if c < STUDY:
		trace = ss(0.3, 0.45, c / STUDY) * (1.0 - ss(0.75, 0.9, c / STUDY))
	elif c < STUDY + ROTATE:
		turned = ss(0.0, 1.0, (c - STUDY) / ROTATE)
	elif c < STUDY * 2.0 + ROTATE:
		turned = 1.0
	else:
		turned = 1.0 - ss(0.6, 1.0, (c - STUDY * 2.0 - ROTATE) / SCRATCH)
		var k := (c - STUDY * 2.0 - ROTATE) / SCRATCH
		scratch = ss(0.0, 0.25, k) * (1.0 - ss(0.75, 1.0, k))
	var base_yaw := float(turn_count % 2) * PI * 0.5
	var lowered := maxf(g, j)
	# Map: held at chest height, lowered to the side when greeting / rolled up on a sale.
	_map.position = Vector3(0.0, lerpf(1.45, 1.05, lowered), lerpf(-0.42, -0.3, lowered))
	_map.rotation = Vector3(lerpf(-0.9, -1.4, lowered), 0.0, 0.0)
	_map_sheet.rotation = Vector3(0.0, base_yaw + turned * PI * 0.5, 0.0)
	_map_sheet.scale = Vector3(lerpf(1.0, 0.25, j), 1.0, 1.0)
	# Arms: both hands at the map's edges; the left leaves to scratch the jaw; right traces.
	var r_sh := Vector3(1.05 + 0.15 * trace, 0.0, -0.08 - 0.12 * trace)
	var l_sh := Vector3(1.05, 0.0, 0.08)
	var l_el := 1.2
	l_sh = l_sh.lerp(Vector3(1.9, 0.0, 0.35), scratch)
	l_el = lerpf(l_el, 2.2, scratch)
	r_sh = r_sh.lerp(Vector3(0.6, 0.0, -0.1), lowered)
	l_sh = l_sh.lerp(Vector3(0.6, 0.0, 0.1), lowered)
	set_arm(_arm_r, r_sh + Vector3(0.0, 0.0, 0.08 * sin(turned * PI)), lerpf(1.15 + 0.2 * trace, 0.8, lowered))
	set_arm(_arm_l, l_sh, lerpf(l_el, 0.8, lowered), Vector3(0.0, 0.0, 0.3 * scratch * sin(t * 14.0)))
	# Head: tilts in thought, follows the turning map, looks up and tips the hat to greet.
	head.rotation = Vector3(-0.45 * (1.0 - g) + 0.15 * g, 0.25 * sin(t * 0.5) * (1.0 - g) - 0.2 * turned * (1.0 - turned),
		0.18 * sin(t * 0.37) * (1.0 - g) + 0.15 * scratch)
	_hat.rotation = Vector3(-0.35 * g, 0.0, 0.0)
	torso.rotation = Vector3(-0.12 - 0.08 * (1.0 - g), 0.0, 0.0)
	_lantern.rotation = Vector3(0.12 * sin(t * 1.3), 0.0, 0.1 * sin(t * 0.9))
