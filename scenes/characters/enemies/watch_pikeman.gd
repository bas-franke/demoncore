extends ProcModel
## "City-Watch Pikeman" (SLAM as a pike thrust, cathedral city only): a burly watchman of Saint
## Aurel in a quartered blue-and-gold tabard over a mail shirt, an open sallet and a very long
## pike. His "slam" is a thrust: the struck circle sits far ahead of him (long slam_reach, small
## radius), the pike drawn back in the wind-up and driven forward on the strike.

const HIP := 0.5

var _torso: Node3D
var _arm_r: Node3D
var _arm_l: Node3D
var _pike: Node3D


func build() -> void:
	feather_count = 0
	mote_count = 3
	debris = [&"steel"]
	stride = 1.1
	var mail := Art.mat(Art.STEEL.darkened(0.15), 0.55, 0.8, 0.35, true, 0.0, &"chainmail")
	var blue := m_cloth(Color(0.18, 0.26, 0.52))
	var gold := m_cloth(Color(0.85, 0.68, 0.25))
	var steel := m_metal(Art.STEEL)
	var skin := m_skin(Color(0.82, 0.65, 0.52))
	_torso = biped(HIP, 0.05, m_cloth(Color(0.25, 0.22, 0.2)), m_leather(), 0.09, 0.45)
	Art.part(body, Art.cylinder(0.17, 0.22), mail, Vector3(0.0, -0.1, 0.0), Vector3(1.0, 0.26, 0.85))
	Art.part(_torso, Art.cylinder(0.2, 0.17), mail, Vector3(0.0, 0.2, 0.0), Vector3(1.0, 0.42, 0.8))
	# Quartered tabard.
	for q in 4:
		var x := -0.06 if q % 2 == 0 else 0.06
		var y := 0.28 if q < 2 else 0.1
		Art.part(_torso, Art.box(), blue if (q == 0 or q == 3) else gold, Vector3(x, y, -0.135), Vector3(0.12, 0.18, 0.02))
	var head := Art.pivot(_torso, Vector3(0.0, 0.5, 0.0))
	Art.part(head, Art.sphere(), skin, Vector3.ZERO, Vector3(0.16, 0.18, 0.16))
	Art.part(head, Art.sphere(), steel, Vector3(0.0, 0.05, 0.02), Vector3(0.2, 0.13, 0.22))
	Art.part(head, Art.cone(0.5), steel, Vector3(0.0, 0.04, 0.14), Vector3(0.12, 0.12, 0.06), Vector3(1.4, 0.0, 0.0))
	Art.part(head, Art.box(), m_cloth(Color(0.35, 0.22, 0.12)), Vector3(0.0, -0.06, -0.08), Vector3(0.08, 0.03, 0.02))
	var a := arm(_torso, Vector3(-0.22, 0.38, 0.0), 0.4, 0.045, mail, m_leather(), 0.0, 0.0)
	_arm_l = a[0]
	var b := arm(_torso, Vector3(0.22, 0.38, 0.0), 0.4, 0.045, mail, m_leather(), 0.0, 0.0)
	_arm_r = b[0]
	# Pike: a long ash shaft through the right fist, a leaf head with a cross-guard.
	_pike = animated(Art.pivot(b[1], Vector3.ZERO, Vector3(-PI * 0.5, 0.0, 0.0)))
	limb(_pike, Vector3(0.0, -1.0, 0.0), Vector3(0.0, 1.6, 0.0), 0.016, m_wood())
	Art.part(_pike, Art.cone(0.5), steel, Vector3(0.0, 1.75, 0.0), Vector3(0.06, 0.3, 0.025))
	Art.part(_pike, Art.box(), steel, Vector3(0.0, 1.6, 0.0), Vector3(0.14, 0.02, 0.02))
	finish()


func pose(_delta: float) -> void:
	biped_bob(HIP, 0.035)
	var draw := windup_w
	var thrust := maxf(strike_w, recover_w)
	_torso.rotation.x = -0.1 * move_w + draw * 0.15 - thrust * 0.35
	_torso.rotation.y = -draw * 0.3
	# Pike levelled forward, drawn back for the wind-up, driven out on the thrust.
	var level := Vector3(1.35, -0.25, 0.1)
	_arm_r.rotation = mixv(Vector3(0.9 - sin(walk) * 0.1 * move_w, -0.2, 0.1), level, maxf(draw, thrust))
	_pike.position = Vector3(0.0, 0.0, lerpf(0.0, 0.45, draw) - thrust * 0.6)
	_arm_l.rotation = mixv(Vector3(1.0, 0.5, -0.1), Vector3(1.4, 0.45, -0.05), maxf(draw, thrust))
