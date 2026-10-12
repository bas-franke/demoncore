extends ProcModel
## "Animated Saint" (SLAM, slow, heavy): a church statue of a bearded saint torn from its niche,
## still standing on a chunk of its pedestal. Marble robes, a gilt book clutched in one arm,
## the other hand raised in benediction, a gold disc nimbus behind the head; its blank eyes and
## the cracks in its robe glow. It grinds forward on its pedestal. SLAM: the blessing hand is
## lifted high and the whole statue rears back (wind-up), then brings the book down like a
## hammer (strike); it settles with a grinding shudder (recover). Sinks into rubble on death.

const BASE_H := 0.16

var _torso: Node3D
var _arm_r: Node3D
var _arm_l: Node3D
var _nimbus: MeshInstance3D


func build() -> void:
	feather_count = 0
	mote_count = 5
	debris = [&"shard"]
	debris_color = Art.STONE
	death_style = &"sink"
	death_time = 0.9
	var marble := m_stone(Color(0.78, 0.76, 0.72))
	var dark := m_stone(Color(0.52, 0.5, 0.47))
	var crack := Art.glow(Art.HOLY, 1.8)
	body = animated(Art.pivot(self))
	# Broken pedestal chunk with a gold-leaf inscription band.
	Art.part(body, Art.cylinder(0.3, 0.33), dark, Vector3(0.0, BASE_H * 0.5, 0.0), Vector3(1.0, BASE_H, 1.0))
	Art.part(body, Art.cylinder(0.5, 0.5), m_gold(), Vector3(0.0, BASE_H * 0.55, 0.0), Vector3(0.62, 0.025, 0.62))
	# Robed figure: long robe column, mantle folds, glowing cracks.
	_torso = animated(Art.pivot(body, Vector3(0.0, BASE_H, 0.0)))
	Art.part(_torso, Art.cylinder(0.17, 0.25), marble, Vector3(0.0, 0.42, 0.0), Vector3(1.0, 0.84, 0.85))
	Art.part(_torso, Art.cylinder(0.2, 0.22), marble, Vector3(0.0, 0.66, 0.02), Vector3(1.05, 0.4, 0.9), Vector3(0.1, 0.0, 0.08))
	for i in 3:
		Art.part(_torso, Art.box(), marble, Vector3(-0.12 + i * 0.12, 0.25, -0.17), Vector3(0.05, 0.5, 0.04), Vector3(0.1, 0.0, 0.0))
	Art.part(_torso, Art.box(), crack, Vector3(0.06, 0.45, -0.205), Vector3(0.012, 0.3, 0.01), Vector3(0.0, 0.0, 0.3))
	Art.part(_torso, Art.box(), crack, Vector3(-0.08, 0.6, -0.19), Vector3(0.01, 0.16, 0.01), Vector3(0.0, 0.0, -0.4))
	var head := Art.pivot(_torso, Vector3(0.0, 0.98, 0.0))
	Art.part(head, Art.sphere(), marble, Vector3.ZERO, Vector3(0.17, 0.2, 0.18))
	# Beard, hair cap and blank glowing eyes.
	Art.part(head, Art.cone(0.5), marble, Vector3(0.0, -0.1, -0.06), Vector3(0.14, 0.18, 0.1), Vector3(PI + 0.25, 0.0, 0.0))
	Art.part(head, Art.sphere(), dark, Vector3(0.0, 0.05, 0.02), Vector3(0.18, 0.13, 0.18))
	for s: float in [-1.0, 1.0]:
		Art.part(head, Art.sphere(), Art.glow(Art.HOLY_WHITE, 2.2), Vector3(s * 0.04, 0.01, -0.08), Vector3(0.03, 0.018, 0.015))
	# Nimbus: a gold disc behind the head (stone saints wear solid halos).
	_nimbus = keep(Art.part(head, Art.cylinder(0.5, 0.5), Art.emissive(Art.GOLD, Art.HOLY, 0.4, 0.35), Vector3(0.0, 0.04, 0.11), Vector3(0.36, 0.02, 0.36), Vector3(PI * 0.5, 0.0, 0.0)))
	# Left arm cradles the gilt book; right hand raised in blessing (two fingers up).
	var a := arm(_torso, Vector3(-0.2, 0.86, 0.0), 0.36, 0.05, marble, marble, 0.0, 0.0)
	_arm_l = a[0]
	var book := Art.pivot(a[1], Vector3(0.0, 0.0, -0.04))
	Art.part(book, Art.box(), Art.mat(Color(0.45, 0.12, 0.1), 0.6), Vector3.ZERO, Vector3(0.2, 0.06, 0.26))
	Art.part(book, Art.box(), m_gold(), Vector3(0.0, 0.032, 0.0), Vector3(0.16, 0.01, 0.2))
	Art.part(book, Art.box(), Art.mat(Art.IVORY, 0.8), Vector3(0.01, 0.0, 0.0), Vector3(0.19, 0.045, 0.24))
	var b := arm(_torso, Vector3(0.2, 0.86, 0.0), 0.36, 0.05, marble, marble, 0.0, 0.0)
	_arm_r = b[0]
	for x: float in [-0.012, 0.012]:
		limb(b[1], Vector3(x, 0.0, 0.0), Vector3(x, -0.09, -0.01), 0.011, marble)
	finish()


func pose(_delta: float) -> void:
	# Grinding shuffle: the pedestal rocks side to side instead of stepping.
	var rock := sin(walk) * 0.06 * move_w
	body.rotation.z = rock
	body.position.y = absf(rock) * 0.3
	var act := maxf(strike_w, recover_w)
	_torso.rotation.x = windup_w * 0.3 - act * 0.45 + sin(t * 30.0) * 0.006 * recover_w
	# Right hand raised in blessing at rest and lifted high in the wind-up.
	_arm_r.rotation = mixv(deg(110.0, 0.0, -10.0), deg(170.0, 0.0, -5.0), windup_w)
	_arm_r.rotation = mixv(_arm_r.rotation, deg(70.0, 0.0, 0.0), act)
	# The book arm swings overhead with it and smashes down.
	_arm_l.rotation = mixv(deg(60.0, -30.0, -5.0), deg(175.0, 0.0, 5.0), windup_w)
	_arm_l.rotation = mixv(_arm_l.rotation, deg(80.0, 0.0, 0.0), act)
	EnemyModel.glow(_nimbus, windup_w * 0.8 + 0.1 * sin(t * 2.0) + 0.1)
