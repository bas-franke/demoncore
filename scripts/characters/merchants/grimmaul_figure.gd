extends MerchantFigure
## Grimmaul, the Blacksmith: a hunched, barrel-chested forge-demon with crimson skin seamed by
## ember cracks, ram horns, a beard of smouldering embers, a scorched leather apron and iron
## bracers. Idle: hammers a glowing ingot on his anvil (three blows with sparks, then lifts it in
## the tongs to squint at it); greets by resting the hammer on his shoulder; a sale gets the hammer
## raised high.

const STRIKE := 1.15  # seconds per hammer blow
const BLOWS := 3
const INSPECT := 2.4
const IMPACT := 0.72  # fraction of a blow where the hammer lands

var _arm_r: Array[Node3D] = []
var _arm_l: Array[Node3D] = []
var _anvil: Node3D
var _ingot_glow: MeshInstance3D
var _ingot_m: StandardMaterial3D
var _heat := 0.0
var _last_u := 0.0


func build() -> void:
	var skin := Art.mat(Color(0.26, 0.075, 0.05), 0.62, 0.0, 0.3, true, 0.15, &"skin")
	var leather := Art.mat(Art.LEATHER.darkened(0.15), 0.85, 0.0, 0.55, true, 0.0, &"leather")
	var cloth := Art.mat(Color(0.12, 0.09, 0.08), 0.9, 0.0, 0.5, true, 0.0, &"cloth")
	var iron := Art.mat(Art.OBSIDIAN.lightened(0.08), 0.4, 0.85, 0.4, true, 0.0, &"metal")
	var horn_m := Art.mat(Color(0.3, 0.26, 0.22), 0.6, 0.0, 0.4, true, 0.0, &"bone")
	var ember := Art.glow(Art.EMBER, 2.4)
	var crack := Art.glow(Art.HELLFIRE, 1.8)

	# Legs in sooty trousers, iron-shod boots.
	for s: float in [-1.0, 1.0]:
		EnemyModel.limb(self, Vector3(s * 0.2, 0.86, 0.05), Vector3(s * 0.25, 0.14, 0.0), 0.13, cloth)
		Art.part(self, Art.box(), iron, Vector3(s * 0.26, 0.08, -0.05), Vector3(0.24, 0.16, 0.36))
	torso = Art.pivot(self, Vector3(0.0, 0.88, 0.0), Vector3(-0.28, 0.0, 0.0))
	Art.part(torso, Art.sphere(), skin, Vector3(0.0, 0.3, 0.02), Vector3(0.95, 0.78, 0.8))       # belly
	Art.part(torso, Art.sphere(), skin, Vector3(0.0, 0.76, 0.0), Vector3(1.3, 0.82, 0.88))       # chest
	Art.part(torso, Art.sphere(), skin, Vector3(0.0, 1.0, 0.12), Vector3(0.9, 0.5, 0.6))         # hump
	Art.part(torso, Art.torus(0.4, 0.5), iron, Vector3(0.0, 0.1, 0.0), Vector3(1.0, 0.7, 0.85))  # belt
	Art.part(torso, Art.box(), iron, Vector3(0.0, 0.1, -0.42), Vector3(0.2, 0.16, 0.06))         # buckle
	# Apron: bib + skirt, scorched hem.
	Art.part(torso, Art.box(), leather, Vector3(0.0, 0.62, -0.43), Vector3(0.62, 0.62, 0.05), Vector3(0.12, 0.0, 0.0))
	Art.part(torso, Art.box(), leather, Vector3(0.0, -0.18, -0.4), Vector3(0.78, 0.66, 0.05), Vector3(-0.2, 0.0, 0.0))
	Art.part(torso, Art.box(), ember, Vector3(0.0, -0.5, -0.47), Vector3(0.7, 0.025, 0.02), Vector3(-0.2, 0.0, 0.0))
	for s: float in [-1.0, 1.0]:
		EnemyModel.limb(torso, Vector3(s * 0.28, 0.9, -0.36), Vector3(s * 0.16, 1.12, -0.12), 0.025, leather)
		# Ember seams across the chest and back.
		Art.part(torso, Art.box(), crack, Vector3(s * 0.38, 0.86, -0.3), Vector3(0.02, 0.32, 0.02),
			Vector3(0.0, 0.0, s * 0.5))
		Art.part(torso, Art.box(), crack, Vector3(s * 0.25, 0.9, 0.42), Vector3(0.02, 0.38, 0.02),
			Vector3(0.0, 0.0, -s * 0.35))
		Art.part(torso, Art.sphere(), skin, Vector3(s * 0.62, 0.98, 0.0), Vector3(0.46, 0.4, 0.46))  # deltoid
	# Left shoulder: a riveted iron guard.
	Art.part(torso, Art.sphere(), iron, Vector3(-0.66, 1.06, 0.0), Vector3(0.5, 0.26, 0.5))

	# Arms: huge, bare, iron bracers.
	_arm_r = arm(torso, Vector3(0.7, 0.96, 0.0), 0.48, 0.45, 0.13, 0.12, skin, skin, 0.17)
	_arm_l = arm(torso, Vector3(-0.7, 0.96, 0.0), 0.48, 0.45, 0.13, 0.12, skin, skin, 0.17)
	for a: Array[Node3D] in [_arm_r, _arm_l]:
		Art.part(a[1], Art.cylinder(0.5, 0.56), iron, Vector3(0.0, -0.27, 0.0), Vector3(0.3, 0.3, 0.3))
		Art.part(a[1], Art.box(), crack, Vector3(0.0, -0.1, -0.12), Vector3(0.02, 0.14, 0.02))

	# Hammer in the right hand: the handle continues the forearm, head across it.
	var wood := Art.mat(Color(0.2, 0.13, 0.08), 0.85, 0.0, 0.4, true, 0.0, &"wood")
	var hammer := Art.pivot(_arm_r[2], Vector3(0.0, -0.08, 0.0))
	EnemyModel.limb(hammer, Vector3(0.0, 0.12, 0.0), Vector3(0.0, -0.5, 0.0), 0.035, wood)
	Art.part(hammer, Art.box(), iron, Vector3(0.0, -0.52, 0.0), Vector3(0.2, 0.2, 0.42))
	Art.part(hammer, Art.box(), ember, Vector3(0.0, -0.52, -0.215), Vector3(0.2, 0.2, 0.01))

	# Tongs in the left hand, gripping the ingot.
	var tongs := Art.pivot(_arm_l[2], Vector3(0.0, -0.08, 0.0))
	for s: float in [-1.0, 1.0]:
		EnemyModel.limb(tongs, Vector3(s * 0.02, 0.05, 0.0), Vector3(s * 0.035, -0.48, 0.0), 0.014, iron)
	_ingot_m = StandardMaterial3D.new()
	_ingot_m.albedo_color = Color(1.0, 0.55, 0.2)
	_ingot_m.emission_enabled = true
	_ingot_m.emission = Color(1.0, 0.4, 0.1)
	_ingot_m.emission_energy_multiplier = 2.0
	_ingot_glow = Art.part(tongs, Art.box(), _ingot_m, Vector3(0.0, -0.52, 0.0), Vector3(0.09, 0.08, 0.26))

	# Head: low between the shoulders, heavy brow, underbite with tusks, ram horns, ember beard.
	head = Art.pivot(torso, Vector3(0.0, 1.16, -0.22))
	Art.part(head, Art.sphere(), skin, Vector3.ZERO, Vector3(0.44, 0.4, 0.46))
	Art.part(head, Art.box(), skin, Vector3(0.0, 0.08, -0.18), Vector3(0.4, 0.08, 0.14), Vector3(0.3, 0.0, 0.0))
	Art.part(head, Art.box(), skin, Vector3(0.0, -0.15, -0.1), Vector3(0.36, 0.16, 0.32))
	for s: float in [-1.0, 1.0]:
		Art.part(head, Art.sphere(), ember, Vector3(s * 0.1, 0.03, -0.21), Vector3(0.06, 0.035, 0.03))
		Art.part(head, Art.cone(0.5), horn_m, Vector3(s * 0.11, -0.08, -0.25), Vector3(0.05, 0.12, 0.05))
		# Ram horns: out to the side, curling back, down and forward round the ear.
		horn(head, Vector3(s * 0.17, 0.1, 0.02), [Vector3(s * 0.2, 0.07, 0.05), Vector3(s * 0.1, -0.03, 0.13),
			Vector3(s * -0.02, -0.14, 0.03), Vector3(s * -0.02, -0.06, -0.11)], 0.075, 0.03, horn_m)
	for k in 5:
		var x := (float(k) - 2.0) * 0.07
		Art.part(head, Art.cone(0.5), Art.glow(Art.EMBER.lerp(Art.HELLFIRE, float(k % 2)), 2.0),
			Vector3(x, -0.3 - absf(x) * 0.3, -0.16), Vector3(0.07, 0.24 - absf(x), 0.07), Vector3(PI + 0.2, 0.0, x * 1.5))

	# The anvil in front of him (moves with him as he turns to watch the player).
	_anvil = Art.pivot(self, Vector3(0.0, 0.0, -1.0))
	Art.part(_anvil, Art.box(), iron, Vector3(0.0, 0.17, 0.0), Vector3(0.46, 0.34, 0.34))
	Art.part(_anvil, Art.box(), iron, Vector3(0.0, 0.42, 0.0), Vector3(0.22, 0.2, 0.2))
	Art.part(_anvil, Art.box(), iron, Vector3(0.05, 0.59, 0.0), Vector3(0.62, 0.15, 0.3))
	Art.part(_anvil, Art.cone(0.5), iron, Vector3(-0.42, 0.6, 0.0), Vector3(0.14, 0.32, 0.14), Vector3(0.0, 0.0, PI * 0.5))
	Art.light(_anvil, Art.EMBER, 0.9, 2.5, Vector3(0.0, 0.9, 0.0))


func pose(delta: float) -> void:
	var cycle := STRIKE * BLOWS + INSPECT
	var c := fmod(t, cycle)
	var raise := 0.0      # hammer: 0 on the anvil, 1 overhead
	var inspect := 0.0    # tongs lifted to the eye
	var u := 0.0
	if c < STRIKE * BLOWS:
		u = fmod(c, STRIKE) / STRIKE
		if u < 0.55:
			raise = ss(0.0, 0.55, u)
		elif u < 0.62:
			raise = 1.0
		elif u < IMPACT:
			var k := (u - 0.62) / (IMPACT - 0.62)
			raise = 1.0 - k * k
		else:
			raise = 0.12 * sin((u - IMPACT) / (1.0 - IMPACT) * PI) * (1.0 - (u - IMPACT))
		# Impact: sparks, a ring of iron, the ingot flares.
		if _last_u < IMPACT and u >= IMPACT and greet_w < 0.5:
			sparks(_anvil, Vector3(0.0, 0.72, 0.0), Art.EMBER, 14, 3.0)
			if near:
				Sfx.play_at(&"metal", _anvil.global_position, 0.12, -14.0)
			_heat = 1.0
		_last_u = u
	else:
		var k := (c - STRIKE * BLOWS) / INSPECT
		inspect = ss(0.0, 0.25, k) * (1.0 - ss(0.75, 1.0, k))
		_last_u = 0.0
	_heat = maxf(_heat - delta * 2.5, 0.0)
	_ingot_m.emission_energy_multiplier = 2.0 + _heat * 4.0

	var g := greet_w
	var j := joy_w
	# Right (hammer) arm: strike pose -> overhead; greeting rests it on the shoulder; joy lifts it.
	var r_sh := Vector3(lerpf(0.95, 2.75, raise), 0.0, lerpf(-0.42, -0.2, raise))
	var r_el := lerpf(0.15, 1.65, raise)
	r_sh = r_sh.lerp(Vector3(1.2, 0.0, -0.1), inspect * 0.6)
	r_sh = r_sh.lerp(Vector3(2.2, 0.0, 0.25), g)
	r_el = lerpf(lerpf(r_el, 0.4, inspect * 0.6), 2.3, g)
	r_sh = r_sh.lerp(Vector3(3.0, 0.0, 0.3), j)
	r_el = lerpf(r_el, 0.25, j)
	set_arm(_arm_r, r_sh, r_el)
	# Left (tongs) arm: holds the ingot on the anvil, lifts it to the eye to inspect.
	var l_sh := Vector3(0.95, 0.0, 0.42).lerp(Vector3(1.25, 0.0, 0.45), inspect)
	var l_el := lerpf(0.3, 0.95, inspect)
	l_sh = l_sh.lerp(Vector3(0.4, 0.0, 0.15), g)
	# Inspecting: the tongs swing level, the ingot held up before his face, turned in the light.
	set_arm(_arm_l, l_sh, lerpf(l_el, 0.5, g), Vector3(-1.2 * inspect, 0.0, inspect * 0.5 * sin(t * 2.0)))
	# Body: wind up and lean into the blow; head follows the work or looks up at the customer.
	torso.rotation = Vector3(-0.28 - 0.12 * (1.0 - raise) * (1.0 - g) + 0.08 * raise, 0.18 * raise * (1.0 - g), 0.0)
	var look_down := 0.35 * (1.0 - g) * (1.0 - inspect) + 0.1 * inspect
	head.rotation = Vector3(-look_down + 0.25 * g + 0.15 * j, -0.35 * inspect, 0.08 * sin(t * 0.7) * inspect)
