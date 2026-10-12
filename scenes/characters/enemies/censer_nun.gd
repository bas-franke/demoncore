extends ProcModel
## "Sister of the Thurible" (SHOOT, holy smoke): a nun in a black habit and a stiff white
## wimple-and-coif, eyes lowered, a long rosary at the waist, swinging a heavy silver censer on
## a chain that trails incense. She glides rather than walks. SHOOT: the censer is drawn back in
## a wide pendulum (wind-up), then flung forward, belching burning smoke (HolySmoke).

const SMOKE := Color(0.86, 0.82, 0.7)

var _torso: Node3D
var _arm_r: Node3D
var _arm_l: Node3D
var _chain: Node3D
var _coals: MeshInstance3D
var _swing := 0.0
var _swing_v := 0.0


func build() -> void:
	feather_count = 0
	mote_count = 5
	light_color = Art.HOLY
	death_style = &"sink"
	var habit := m_cloth(Color(0.07, 0.065, 0.075))
	var white := m_cloth(Color(0.93, 0.92, 0.88))
	var skin := m_skin(Color(0.86, 0.76, 0.68))
	var silver := m_metal(Color(0.78, 0.78, 0.8), 0.25)
	body = animated(Art.pivot(self, Vector3(0.0, 0.0, 0.0)))
	# Floor-length habit: a wide bell of cloth.
	Art.part(body, Art.cylinder(0.17, 0.3), habit, Vector3(0.0, 0.33, 0.0), Vector3(1.0, 0.66, 0.9))
	_torso = animated(Art.pivot(body, Vector3(0.0, 0.62, 0.0)))
	Art.part(_torso, Art.cylinder(0.16, 0.17), habit, Vector3(0.0, 0.12, 0.0), Vector3(1.0, 0.3, 0.85))
	# Wimple: white collar cape over the shoulders and the coif round the face.
	Art.part(_torso, Art.cylinder(0.09, 0.22), white, Vector3(0.0, 0.3, 0.0), Vector3(1.0, 0.14, 0.9))
	var head := Art.pivot(_torso, Vector3(0.0, 0.44, 0.0))
	Art.part(head, Art.sphere(), white, Vector3(0.0, 0.0, 0.01), Vector3(0.19, 0.22, 0.2))
	Art.part(head, Art.sphere(), skin, Vector3(0.0, -0.005, -0.06), Vector3(0.12, 0.15, 0.1))
	# Lowered eyes: two dark slits.
	for s: float in [-1.0, 1.0]:
		Art.part(head, Art.box(), Art.mat(Art.OBSIDIAN, 0.5), Vector3(s * 0.03, 0.01, -0.11), Vector3(0.035, 0.006, 0.01))
	# Black veil over the coif, falling down the back.
	Art.part(head, Art.sphere(), habit, Vector3(0.0, 0.03, 0.03), Vector3(0.22, 0.22, 0.22))
	Art.part(head, Art.box(), habit, Vector3(0.0, -0.12, 0.09), Vector3(0.2, 0.3, 0.04), Vector3(0.15, 0.0, 0.0))
	# Rosary hanging from the waist with a small silver cross.
	for i in 10:
		Art.part(_torso, Art.sphere(), m_wood(), Vector3(-0.1 + 0.005 * i, -0.02 - i * 0.03, -0.155 - 0.004 * i), Vector3.ONE * 0.022)
	Art.part(_torso, Art.box(), silver, Vector3(-0.055, -0.33, -0.2), Vector3(0.015, 0.06, 0.01))
	var a := arm(_torso, Vector3(-0.18, 0.24, 0.0), 0.36, 0.045, habit, skin, 0.0, 0.0)
	_arm_l = a[0]
	var b := arm(_torso, Vector3(0.18, 0.24, 0.0), 0.36, 0.045, habit, skin, 0.0, 0.0)
	_arm_r = b[0]
	# Censer: chain from the right hand (pendulum pivot) to a pierced silver globe of coals.
	_chain = animated(Art.pivot(b[1], Vector3(0.0, 0.0, 0.0)))
	limb(_chain, Vector3.ZERO, Vector3(0.0, -0.32, 0.0), 0.006, silver)
	Art.part(_chain, Art.sphere(), silver, Vector3(0.0, -0.4, 0.0), Vector3(0.13, 0.12, 0.13))
	Art.part(_chain, Art.cone(0.5), silver, Vector3(0.0, -0.31, 0.0), Vector3(0.1, 0.08, 0.1))
	Art.part(_chain, Art.cylinder(0.5, 0.3), silver, Vector3(0.0, -0.48, 0.0), Vector3(0.07, 0.05, 0.07))
	_coals = keep(Art.part(_chain, Art.sphere(), Art.glow(Color(1.0, 0.55, 0.25), 1.6), Vector3(0.0, -0.4, 0.0), Vector3.ONE * 0.15))
	finish()


func pose(delta: float) -> void:
	# Glide: a slow float and sway, no steps.
	body.position.y = 0.02 + sin(t * 2.0) * 0.015
	body.rotation.z = sin(t * 1.1) * 0.03
	_torso.rotation.x = -0.1 * move_w + windup_w * 0.12 - attack_kick * 0.2
	_torso.rotation.y = -windup_w * 0.3 + attack_kick * 0.3
	_arm_l.rotation = Vector3(0.6, 0.6, -0.1)
	# Censer: damped pendulum the arm drives; a big backswing on wind-up, a throw on the attack.
	var arm_x := 0.45 + sin(t * 2.2) * 0.12 - windup_w * 0.5 + attack_kick * 1.3
	_arm_r.rotation = Vector3(arm_x, 0.0, 0.1)
	var target := -arm_x * 0.6 - windup_w * 0.9 + attack_kick * 1.6
	_swing_v += ((target - _swing) * 30.0 - _swing_v * 3.0) * delta
	_swing += _swing_v * delta
	_chain.rotation.x = _swing
	var k := 1.0 + windup_w * 0.6 + attack_kick * 0.8 + 0.08 * sin(t * 12.0)
	_coals.scale = Vector3.ONE * 0.15 * k
