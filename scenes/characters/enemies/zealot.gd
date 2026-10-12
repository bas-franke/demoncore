extends ProcModel
## "Crusader Zealot" (CHASE, fast): a frenzied flagellant crusader. A pointed penitent's hood,
## bare scourged back, a ragged red-cross tabard, a banner pole strapped to his back with a
## white pennant, and a flail whirled over his head as he sprints at you. The flail cut is
## cosmetic (proximity_attack).

const HIP := 0.5

var _torso: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _flail: Node3D
var _banner: Node3D
var _spin := 0.0
## Holy fire kindling in his chest during a wind-up (EXPLODE: the fuse before he bursts).
var _fuse: MeshInstance3D


func build() -> void:
	feather_count = 0
	mote_count = 3
	stride = 1.4
	proximity_range = 1.5
	proximity_cooldown = 1.2
	var hood := m_cloth(Color(0.82, 0.8, 0.74))
	var skin := m_skin(Color(0.78, 0.6, 0.52))
	var red := m_cloth(Color(0.55, 0.07, 0.06))
	var rag := m_cloth(Color(0.68, 0.64, 0.56))
	_torso = biped(HIP, 0.042, m_cloth(Color(0.3, 0.25, 0.2)), m_leather(), 0.08, 0.75)
	Art.part(body, Art.cylinder(0.15, 0.2), rag, Vector3(0.0, -0.1, 0.0), Vector3(1.0, 0.24, 0.85))
	# Bare, scourged torso with a tabard over the front only.
	Art.part(_torso, Art.cylinder(0.17, 0.14), skin, Vector3(0.0, 0.2, 0.0), Vector3(1.0, 0.42, 0.75))
	for i in 3:
		Art.part(_torso, Art.box(), m_skin(Color(0.55, 0.12, 0.1)), Vector3(0.0, 0.14 + i * 0.09, 0.105), Vector3(0.22, 0.012, 0.01), Vector3(0.0, 0.0, 0.3 - i * 0.25))
	Art.part(_torso, Art.box(), rag, Vector3(0.0, 0.15, -0.1), Vector3(0.24, 0.5, 0.02))
	Art.part(_torso, Art.box(), red, Vector3(0.0, 0.2, -0.113), Vector3(0.05, 0.3, 0.01))
	Art.part(_torso, Art.box(), red, Vector3(0.0, 0.26, -0.113), Vector3(0.18, 0.05, 0.01))
	# art-style round 3: 2.2 -> 1.6 (the swelling fuse bloomed past the body).
	_fuse = keep(Art.part(_torso, Art.sphere(), Art.glow(Art.HOLY, 1.6), Vector3(0.0, 0.25, -0.05), Vector3.ONE * 0.01))
	# Tall pointed penitent's hood with eye holes.
	var head := Art.pivot(_torso, Vector3(0.0, 0.5, 0.0))
	Art.part(head, Art.cone(0.5), hood, Vector3(0.0, 0.14, 0.0), Vector3(0.22, 0.5, 0.22))
	Art.part(head, Art.cylinder(0.5, 0.5), hood, Vector3(0.0, -0.08, 0.0), Vector3(0.3, 0.1, 0.26))
	for s: float in [-1.0, 1.0]:
		Art.part(head, Art.sphere(), Art.glow(Art.HOLY_WHITE, 1.5), Vector3(s * 0.04, 0.03, -0.085), Vector3(0.035, 0.025, 0.02))
	# Banner pole on the back with a forked pennant (sways).
	limb(_torso, Vector3(0.08, -0.05, 0.13), Vector3(0.08, 1.05, 0.15), 0.014, m_wood())
	_banner = animated(Art.pivot(_torso, Vector3(0.08, 0.98, 0.15)))
	Art.part(_banner, Art.box(), m_cloth(Art.HOLY_WHITE.darkened(0.05)), Vector3(0.0, -0.12, 0.13), Vector3(0.012, 0.22, 0.26))
	Art.part(_banner, Art.box(), red, Vector3(-0.008, -0.12, 0.12), Vector3(0.006, 0.14, 0.04))
	var a := arm(_torso, Vector3(-0.19, 0.38, 0.0), 0.38, 0.038, skin, skin, 0.0, 0.0)
	_arm_l = a[0]
	var b := arm(_torso, Vector3(0.19, 0.38, 0.0), 0.38, 0.038, skin, skin, 0.0, 0.0)
	_arm_r = b[0]
	# Flail: a short haft, the chain head whirls around it (pivot spun in pose()).
	limb(b[1], Vector3(0.0, 0.0, 0.0), Vector3(0.0, -0.2, 0.0), 0.016, m_wood())
	_flail = animated(Art.pivot(b[1], Vector3(0.0, -0.2, 0.0)))
	var iron := m_metal(Art.STEEL.darkened(0.3), 0.5)
	limb(_flail, Vector3.ZERO, Vector3(0.0, -0.22, 0.0), 0.007, iron)
	Art.part(_flail, Art.sphere(), iron, Vector3(0.0, -0.26, 0.0), Vector3.ONE * 0.09)
	for i in 6:
		var d := Vector3(cos(TAU * i / 6.0), 0.0, sin(TAU * i / 6.0))
		Art.part(_flail, Art.cone(0.5), iron, Vector3(0.0, -0.26, 0.0) + d * 0.045, Vector3.ONE * 0.04, Vector3(d.z * 1.57, 0.0, -d.x * 1.57))
	finish()


func proximity_attack() -> void:
	play_attack()


func pose(delta: float) -> void:
	# Sprinting lean and a high, ragged bob.
	body.position.y = HIP + (absf(cos(walk)) - 0.6) * 0.06 * move_w
	_torso.rotation.x = -0.3 * move_w - attack_kick * 0.25
	_torso.rotation.y = sin(walk) * 0.15 * move_w
	_banner.rotation.x = 0.4 * move_w + sin(t * 6.0) * 0.12
	_banner.rotation.z = sin(t * 4.3) * 0.1
	_arm_l.rotation = Vector3(-sin(walk) * 0.6 * move_w + 0.2, 0.0, -0.15)
	# Flail arm raised overhead, whirling; slams down on a cut.
	_arm_r.rotation = mixv(deg(160.0, 0.0, 20.0), deg(60.0, 0.0, 0.0), attack_kick)
	_spin += delta * (9.0 + move_w * 5.0 + windup_w * 12.0)
	_flail.rotation = Vector3(1.2, _spin, 0.0)
	# Wind-up (fuse): arms flung wide, trembling, holy fire swelling in the chest.
	if windup_w > 0.01:
		var shake := sin(t * 47.0) * 0.04 * windup_w
		_torso.rotation.x = mixv(Vector3(_torso.rotation.x, 0, 0), Vector3(0.25 + shake, 0, 0), windup_w).x
		_arm_l.rotation = mixv(_arm_l.rotation, Vector3(2.4, 0.0, -0.9 + shake), windup_w)
		_arm_r.rotation = mixv(_arm_r.rotation, Vector3(2.4, 0.0, 0.9 - shake), windup_w)
	_fuse.scale = Vector3.ONE * (0.01 + windup_w * (0.35 + 0.15 * state_progress) * (1.0 + 0.2 * sin(t * 30.0)))
