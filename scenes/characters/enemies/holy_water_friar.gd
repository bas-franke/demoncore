extends ProcModel
## "Holy-Water Friar" (SHOOT: lobbed flasks): a round, red-faced mendicant friar in a grey habit
## with a rope girdle, sandals, a tonsure, and a bandolier of glass flasks of holy water across his
## belly. He lobs them overhand in a high arc at where the demon stands; each shatters into a
## scalding puddle (HolyWaterFlask -> HolyPuddle). Wind-up: a flask drawn back over the shoulder.

const HIP := 0.42

var _torso: Node3D
var _head: Node3D
var _arm_r: Node3D
var _arm_l: Node3D
var _held: MeshInstance3D


func build() -> void:
	feather_count = 0
	mote_count = 4
	stride = 0.9
	var habit := m_cloth(Color(0.4, 0.38, 0.36))
	var skin := m_skin(Color(0.88, 0.62, 0.52))
	var glass := Art.mat(Color(0.7, 0.88, 1.0), 0.05, 0.0, 0.0, true, 0.9, &"crystal")
	_torso = biped(HIP, 0.04, skin, m_leather(), 0.08, 0.5)
	Art.part(body, Art.cylinder(0.2, 0.26), habit, Vector3(0.0, -0.18, 0.0), Vector3(1.0, 0.4, 0.95))
	# Round belly and a rope girdle.
	Art.part(_torso, Art.sphere(), habit, Vector3(0.0, 0.16, -0.02), Vector3(0.42, 0.42, 0.4))
	Art.part(_torso, Art.torus(0.8, 1.0), Art.mat(Color(0.6, 0.52, 0.34), 0.9, 0.0, 0.3, true, 0.0, &"rope"), Vector3(0.0, 0.06, -0.01), Vector3(0.21, 0.2, 0.2))
	# Bandolier of flasks across the belly.
	Art.part(_torso, Art.box(), m_leather(), Vector3(0.0, 0.2, -0.19), Vector3(0.05, 0.4, 0.02), Vector3(0.0, 0.0, 0.7))
	for k in 4:
		Art.part(_torso, Art.sphere(), glass, Vector3(-0.12 + k * 0.08, 0.08 + k * 0.07, -0.2), Vector3(0.06, 0.07, 0.06))
		Art.part(_torso, Art.sphere(), Art.glow(Color(0.7, 0.9, 1.0), 0.9), Vector3(-0.12 + k * 0.08, 0.08 + k * 0.07, -0.2), Vector3.ONE * 0.035)
	# Cowl at the back of the neck.
	Art.part(_torso, Art.sphere(), habit, Vector3(0.0, 0.36, 0.08), Vector3(0.26, 0.14, 0.16))
	_head = animated(Art.pivot(_torso, Vector3(0.0, 0.44, -0.02)))
	Art.part(_head, Art.sphere(), skin, Vector3.ZERO, Vector3(0.2, 0.2, 0.19))
	# Tonsure: a ring of hair round the bald crown.
	Art.part(_head, Art.torus(0.6, 1.0), m_cloth(Color(0.42, 0.3, 0.2)), Vector3(0.0, 0.05, 0.0), Vector3(0.1, 0.12, 0.1))
	Art.part(_head, Art.sphere(), m_skin(Color(0.95, 0.5, 0.45)), Vector3(0.0, -0.02, -0.095), Vector3(0.05, 0.04, 0.04))
	for s: float in [-1.0, 1.0]:
		Art.part(_head, Art.sphere(), Art.mat(Art.OBSIDIAN, 0.4), Vector3(s * 0.04, 0.02, -0.088), Vector3(0.025, 0.02, 0.01))
	var a := arm(_torso, Vector3(-0.21, 0.3, 0.0), 0.32, 0.04, habit, skin, 0.0, 0.0)
	_arm_l = a[0]
	var b := arm(_torso, Vector3(0.21, 0.3, 0.0), 0.32, 0.04, habit, skin, 0.0, 0.0)
	_arm_r = b[0]
	_held = keep(Art.part(b[1], Art.sphere(), glass, Vector3(0.0, -0.06, 0.0), Vector3(0.09, 0.11, 0.09)))
	finish()


func pose(_delta: float) -> void:
	biped_bob(HIP, 0.04)
	var draw := windup_w
	_torso.rotation.x = -0.05 * move_w + draw * 0.2 - attack_kick * 0.3
	_torso.rotation.y = -draw * 0.4 + attack_kick * 0.5
	_head.rotation.x = -draw * 0.15 + sin(t * 1.5) * 0.04
	# Overhand lob: drawn back over the shoulder, flung forward and up.
	_arm_r.rotation = mixv(Vector3(0.3 - sin(walk) * 0.3 * move_w, 0.0, 0.15), Vector3(-0.6, 0.0, 0.2), draw)
	_arm_r.rotation.x += attack_kick * 2.8
	_arm_l.rotation = Vector3(0.6 + draw * 0.6, 0.2, -0.2)
	# The flask in hand vanishes when thrown and a fresh one appears.
	_held.visible = attack_kick < 0.6
