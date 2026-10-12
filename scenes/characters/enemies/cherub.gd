extends ProcModel
## "Cherub": the lowest of the Host, a fat porcelain infant with a cap of gilded curls, a tiny
## halo and a pair of stubby wings that beat far too fast to hold it up. Swarms (CHASE, hovers).
## Pose: bobbing flight, dangling kicking legs, little arms reaching for you.

var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _kick: Array[Node3D] = []


func build() -> void:
	feather_count = 2
	mote_count = 3
	death_style = &"shrink"
	death_time = 0.35
	wing_speed = 22.0
	wing_amp = 0.55
	wing_lift = 0.25
	var skin := m_skin(Color(0.95, 0.84, 0.76))
	var gold := m_gold()
	body = animated(Art.pivot(self, Vector3(0.0, 0.42, 0.0)))
	# Pot belly + chest.
	Art.part(body, Art.sphere(), skin, Vector3(0.0, 0.0, 0.0), Vector3(0.36, 0.4, 0.34))
	Art.part(body, Art.sphere(), skin, Vector3(0.0, 0.14, -0.02), Vector3(0.3, 0.26, 0.28))
	# A wisp of gold sash across the belly.
	Art.part(body, Art.torus(0.8, 1.0), m_cloth(Art.GOLD), Vector3(0.0, 0.02, 0.0), Vector3(0.2, 0.16, 0.19), Vector3(0.3, 0.0, 0.2))
	_head = animated(Art.pivot(body, Vector3(0.0, 0.33, -0.02)))
	Art.part(_head, Art.sphere(), skin, Vector3.ZERO, Vector3(0.34, 0.32, 0.32))
	# Cheeks and a pursed mouth.
	for s: float in [-1.0, 1.0]:
		Art.part(_head, Art.sphere(), m_skin(Color(0.98, 0.72, 0.68)), Vector3(s * 0.085, -0.05, -0.12), Vector3.ONE * 0.09)
	# Gilded curls: a ring of small spheres plus a top tuft.
	for i in 9:
		var a := TAU * float(i) / 9.0
		Art.part(_head, Art.sphere(), gold, Vector3(cos(a) * 0.14, 0.1 + 0.02 * sin(a * 3.0), sin(a) * 0.13 + 0.02), Vector3.ONE * 0.09)
	Art.part(_head, Art.sphere(), gold, Vector3(0.0, 0.16, 0.0), Vector3(0.14, 0.08, 0.14))
	eye(_head, Vector3(-0.06, 0.0, -0.14), 0.045, Vector3.FORWARD)
	eye(_head, Vector3(0.06, 0.0, -0.14), 0.045, Vector3.FORWARD)
	halo(_head, Vector3(0.0, 0.26, 0.0), 0.13, 3.0)
	wing_pair(body, Vector3(0.0, 0.16, 0.12), 0.32, 4, null, null, 0.05)
	_arm_l = arm(body, Vector3(-0.17, 0.12, -0.02), 0.2, 0.05, skin, null, 0.0, 0.0)[0]
	_arm_r = arm(body, Vector3(0.17, 0.12, -0.02), 0.2, 0.05, skin, null, 0.0, 0.0)[0]
	# Stubby legs (no walk: they dangle and kick in pose()).
	for s: float in [-1.0, 1.0]:
		var hip := limb_pivot(body, Vector3(s * 0.09, -0.14, 0.0))
		_kick.append(hip)
		limb(hip, Vector3.ZERO, Vector3(0.0, -0.16, 0.03), 0.055, skin)
		Art.part(hip, Art.sphere(), skin, Vector3(0.0, -0.18, 0.02), Vector3(0.08, 0.06, 0.11))
	finish()


func pose(_delta: float) -> void:
	body.position.y = 0.42 + sin(t * 5.0) * 0.06
	body.rotation.x = -0.25 * move_w + sin(t * 2.3) * 0.08
	_head.rotation = Vector3(sin(t * 1.7) * 0.1, sin(t * 0.9) * 0.25, 0.0)
	# Reach forward with both arms (more when the eyes flare after a hit / attack).
	var reach := 0.9 + 0.3 * sin(t * 6.0) + eye_flare * 0.5
	_arm_l.rotation = Vector3(reach, 0.0, -0.3)
	_arm_r.rotation = Vector3(reach + 0.2 * sin(t * 6.0 + 1.0), 0.0, 0.3)
	# Legs kick alternately.
	for i in _kick.size():
		_kick[i].rotation.x = sin(t * 8.0 + PI * float(i)) * 0.5
