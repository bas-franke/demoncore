extends BossModel
## "Ysmir, the Frost Abbot" (boss model, frozen monastery): the abbot of the frozen monastery who
## prayed in the snow until the mountain answered. A towering figure in a grey-white abbatial
## cope, the lower body sheathed in blue ice, great ice crystals grown out of the shoulders and
## back, a mitre of clear ice, a long beard of icicles, frost-white burning eyes, and a crozier of
## ice topped by a star with a small bronze bell hanging from the crook.
## Poses per attack: lanes / cross = crozier swept forward; chase / rain = crozier raised to the
## sky; pyre / bells = crozier slammed to the ground (the bell swings); orbs = arms flung wide;
## summon = both hands raised; charge = leaning glide, crozier levelled.

const FROST := Color(0.7, 0.9, 1.0)

var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _bell: Node3D
var _star: MeshInstance3D
var _crystals: Node3D


func build() -> void:
	light_color = FROST
	stride = 1.4
	var cope := Art.mat(Color(0.78, 0.8, 0.84), 0.7, 0.0, 0.2, true, 0.4, &"cloth")
	var trim := Art.mat(Color(0.5, 0.65, 0.85), 0.4, 0.3, 0.1, true, 0.3, &"cloth")
	var ice := Art.mat(Color(0.65, 0.85, 1.0), 0.08, 0.0, 0.0, true, 0.9, &"crystal")
	var skin := m_skin(Color(0.7, 0.74, 0.8))
	body = animated(Art.pivot(self))
	# Lower body: a cope flaring into a skirt of ice that grips the ground.
	Art.part(body, Art.cylinder(0.25, 0.42), cope, Vector3(0.0, 0.42, 0.0), Vector3(1.0, 0.84, 0.95))
	Art.part(body, Art.cylinder(0.4, 0.5), ice, Vector3(0.0, 0.14, 0.0), Vector3(1.05, 0.28, 1.0))
	for k in 7:
		var ang := TAU * float(k) / 7.0
		Art.part(body, Art.cone(0.5), ice, Vector3(cos(ang) * 0.45, 0.18, sin(ang) * 0.42), Vector3(0.12, 0.42, 0.12), Vector3(sin(ang) * 0.5, 0.0, -cos(ang) * 0.5))
	Art.part(body, Art.box(), trim, Vector3(0.0, 0.45, -0.31), Vector3(0.14, 0.8, 0.02), Vector3(0.2, 0.0, 0.0))
	_torso = animated(Art.pivot(body, Vector3(0.0, 0.84, 0.0)))
	Art.part(_torso, Art.cylinder(0.28, 0.25), cope, Vector3(0.0, 0.2, 0.0), Vector3(1.0, 0.42, 0.85))
	Art.part(_torso, Art.sphere(), cope, Vector3(0.0, 0.36, 0.0), Vector3(0.7, 0.3, 0.5))
	Art.part(_torso, Art.torus(0.7, 1.0), trim, Vector3(0.0, 0.4, 0.0), Vector3(0.24, 0.2, 0.2))
	# Ice crystals grown out of the shoulders and back.
	_crystals = animated(Art.pivot(_torso, Vector3(0.0, 0.35, 0.12)))
	for c: Array in [[Vector3(-0.3, 0.1, 0.0), Vector3(0.0, 0.0, 0.6), 0.5], [Vector3(0.3, 0.1, 0.0), Vector3(0.0, 0.0, -0.6), 0.5],
			[Vector3(-0.12, 0.2, 0.1), Vector3(-0.4, 0.0, 0.25), 0.7], [Vector3(0.12, 0.2, 0.1), Vector3(-0.4, 0.0, -0.25), 0.7],
			[Vector3(0.0, 0.25, 0.14), Vector3(-0.5, 0.0, 0.0), 0.85]]:
		Art.part(_crystals, Art.prism(), ice, c[0] + Vector3(0.0, float(c[2]) * 0.4, 0.0), Vector3(0.14, c[2], 0.14), c[1])
	_head = animated(Art.pivot(_torso, Vector3(0.0, 0.58, -0.04)))
	Art.part(_head, Art.sphere(), skin, Vector3.ZERO, Vector3(0.24, 0.28, 0.25))
	for s: float in [-1.0, 1.0]:
		Art.part(_head, Art.sphere(), Art.glow(FROST, 2.6), Vector3(s * 0.055, 0.03, -0.11), Vector3(0.045, 0.02, 0.02))
	# Beard of icicles.
	for i in 7:
		var x := -0.09 + i * 0.03
		Art.part(_head, Art.cone(0.5), ice, Vector3(x, -0.2 - absf(x) * 0.6, -0.08), Vector3(0.04, 0.3 - absf(x) * 1.5, 0.04), Vector3(PI + 0.15, 0.0, 0.0))
	# Mitre of clear ice with a gold band.
	for z: float in [-0.03, 0.03]:
		Art.part(_head, Art.prism(), ice, Vector3(0.0, 0.3, z), Vector3(0.24, 0.36, 0.04))
	Art.part(_head, Art.cylinder(0.5, 0.5), Art.mat(Art.GOLD, 0.4, 0.4, 0.1, true, 0.3, &"gold"), Vector3(0.0, 0.13, 0.0), Vector3(0.26, 0.04, 0.26))
	var a := arm(_torso, Vector3(-0.36, 0.38, 0.0), 0.62, 0.065, cope, skin, 0.0, 0.0)
	_arm_l = a[0]
	Art.part(a[0], Art.cone(0.5), cope, Vector3(0.0, -0.45, 0.03), Vector3(0.22, 0.4, 0.22))
	var b := arm(_torso, Vector3(0.36, 0.38, 0.0), 0.62, 0.065, cope, skin, 0.0, 0.0)
	_arm_r = b[0]
	Art.part(b[0], Art.cone(0.5), cope, Vector3(0.0, -0.45, 0.03), Vector3(0.22, 0.4, 0.22))
	# Crozier of ice: shaft out of the fist (up), a crook with a star and a hanging bell.
	var cz := Art.pivot(b[1], Vector3.ZERO, Vector3(PI, 0.0, 0.0))
	limb(cz, Vector3(0.0, -0.75, 0.0), Vector3(0.0, 1.0, 0.0), 0.028, ice)
	Art.part(cz, Art.torus(0.8, 1.0), ice, Vector3(0.0, 1.12, -0.12), Vector3.ONE * 0.14, Vector3(0.0, 0.0, PI * 0.5))
	_star = keep(Art.part(cz, Art.sphere(), Art.glow(FROST, 2.8), Vector3(0.0, 1.0, -0.2), Vector3.ONE * 0.1))
	_bell = animated(Art.pivot(cz, Vector3(0.0, 1.1, -0.26)))
	limb(_bell, Vector3.ZERO, Vector3(0.0, -0.12, 0.0), 0.006, m_metal(Art.BRONZE, 0.4))
	Art.part(_bell, Art.cylinder(0.04, 0.08), Art.mat(Art.BRONZE.lightened(0.1), 0.4, 0.5, 0.2, true, 0.2, &"gold"), Vector3(0.0, -0.17, 0.0), Vector3(1.0, 0.1, 1.0))
	finish()


func pose(_delta: float) -> void:
	var sweep := act([&"lanes", &"cross", &"sweep"])
	var raise := act([&"chase", &"rain"])
	var slam := act([&"pyre", &"bells"])
	var wide := act([&"orbs"])
	var summon_w := act([&"summon"])
	var glide := act([&"charge"])
	body.position.y = sin(t * 1.2) * 0.02 + rise_w * 0.5 - kneel_w * 0.35
	body.rotation.x = -glide * 0.25 + kneel_w * -0.35
	_torso.rotation.x = 0.05 - sweep * 0.25 + raise * 0.15 - slam * 0.35 * strike_w + kneel_w * -0.3 + rise_w * 0.2
	_torso.rotation.y = sweep * (0.5 - strike_w * 1.0)
	_head.rotation.x = -raise * 0.3 + slam * 0.2 + sin(t * 0.7) * 0.04
	# Crozier arm.
	var r := Vector3(0.5 + sin(walk) * 0.15 * move_w, 0.0, 0.12)
	r = mixv(r, Vector3(1.4, -0.6 + strike_w * 1.2, 0.2), sweep)
	r = mixv(r, Vector3(2.9, 0.0, 0.1), raise)
	r = mixv(r, Vector3(lerpf(2.6, 0.9, strike_w), 0.0, 0.15), slam)
	r = mixv(r, Vector3(1.0, 0.0, 1.3), wide)
	r = mixv(r, Vector3(2.7, 0.0, 0.4), summon_w + rise_w)
	r = mixv(r, Vector3(1.5, -0.3, 0.1), glide)
	_arm_r.rotation = r
	var l := Vector3(0.3, 0.2, -0.15)
	l = mixv(l, Vector3(1.0, 0.0, -1.3), wide)
	l = mixv(l, Vector3(2.7, 0.0, -0.4), summon_w + rise_w)
	l = mixv(l, Vector3(1.2, 0.4, -0.2), raise)
	_arm_l.rotation = l
	_bell.rotation.x = sin(t * 3.0) * 0.2 + slam * sin(t * 18.0) * 0.6
	_star.scale = Vector3.ONE * 0.1 * (1.0 + windup_w * 1.0 + 0.1 * sin(t * 5.0) + float(boss_phase) * 0.2)
	_crystals.scale = Vector3.ONE * (1.0 + float(boss_phase) * 0.15 + rise_w * 0.2)
