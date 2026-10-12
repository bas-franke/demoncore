extends ProcModel
## "Warrior Monk" (CHARGE): a shaven-headed brother in a rough brown habit with the sleeves bound
## up, a rope belt with a wooden rosary, bare forearms and a long iron-shod quarterstaff. Fast.
## CHARGE: sinks into a low stance with the staff levelled like a lance (wind-up), then rushes
## through you staff-first, habit flying; it straightens up while it recovers.

const HIP := 0.48

var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _skirt: Node3D


func build() -> void:
	feather_count = 0
	mote_count = 4
	stride = 1.2
	var habit := m_cloth(Color(0.33, 0.22, 0.14))
	var skin := m_skin(Color(0.8, 0.62, 0.5))
	var rope := Art.mat(Color(0.62, 0.52, 0.34), 0.95, 0.0, 0.3, true, 0.0, &"rope")
	_torso = biped(HIP, 0.045, habit, m_leather(), 0.08, 0.7)
	_skirt = animated(Art.pivot(body, Vector3.ZERO))
	Art.part(_skirt, Art.cylinder(0.15, 0.24), habit, Vector3(0.0, -0.2, 0.0), Vector3(1.0, 0.44, 0.9))
	Art.part(_torso, Art.cylinder(0.18, 0.15), habit, Vector3(0.0, 0.2, 0.0), Vector3(1.0, 0.42, 0.8))
	Art.part(_torso, Art.torus(0.75, 1.0), rope, Vector3(0.0, 0.01, 0.0), Vector3(0.17, 0.2, 0.14))
	# Knotted belt end and a wooden rosary loop.
	limb(_torso, Vector3(0.06, 0.0, -0.12), Vector3(0.08, -0.22, -0.13), 0.012, rope)
	for i in 8:
		var ang := TAU * float(i) / 8.0
		Art.part(_torso, Art.sphere(), m_wood(), Vector3(-0.07 + cos(ang) * 0.04, -0.08 + sin(ang) * 0.06, -0.13), Vector3.ONE * 0.022)
	# Cowl gathered at the shoulders.
	Art.part(_torso, Art.torus(0.5, 1.0), habit, Vector3(0.0, 0.4, 0.02), Vector3(0.17, 0.25, 0.16))
	_head = animated(Art.pivot(_torso, Vector3(0.0, 0.52, 0.0)))
	Art.part(_head, Art.sphere(), skin, Vector3.ZERO, Vector3(0.17, 0.2, 0.18))
	Art.part(_head, Art.sphere(), m_skin(Color(0.62, 0.5, 0.42)), Vector3(0.0, -0.02, 0.0), Vector3(0.175, 0.12, 0.185))
	Art.part(_head, Art.box(), Art.mat(Art.OBSIDIAN, 0.5), Vector3(0.0, 0.02, -0.088), Vector3(0.1, 0.012, 0.01))
	Art.part(_head, Art.cone(0.5), skin, Vector3(0.0, -0.01, -0.09), Vector3(0.035, 0.05, 0.04), Vector3(-PI * 0.5, 0.0, 0.0))
	var a := arm(_torso, Vector3(-0.2, 0.36, 0.0), 0.4, 0.04, skin, skin, 0.0, 0.0)
	_arm_l = a[0]
	Art.part(a[0], Art.cylinder(0.25, 0.5), habit, Vector3(0.0, -0.1, 0.0), Vector3(0.12, 0.2, 0.12))
	var b := arm(_torso, Vector3(0.2, 0.36, 0.0), 0.4, 0.04, skin, skin, 0.0, 0.0)
	_arm_r = b[0]
	Art.part(b[0], Art.cylinder(0.25, 0.5), habit, Vector3(0.0, -0.1, 0.0), Vector3(0.12, 0.2, 0.12))
	# Quarterstaff held in the right hand, running forward/back through the fist.
	var st := Art.pivot(b[1], Vector3.ZERO, Vector3(-PI * 0.5, 0.0, 0.0))
	limb(st, Vector3(0.0, -0.75, 0.0), Vector3(0.0, 0.85, 0.0), 0.022, m_wood())
	for y: float in [-0.75, 0.85]:
		Art.part(st, Art.cylinder(0.5, 0.5), m_metal(Art.STEEL.darkened(0.3), 0.5), Vector3(0.0, y, 0.0), Vector3(0.055, 0.1, 0.055))
	finish()


func pose(_delta: float) -> void:
	var crouch := windup_w
	var rush := strike_w
	body.position.y = HIP + (absf(cos(walk)) - 0.6) * 0.03 * move_w - crouch * 0.05 - rush * 0.03
	_torso.rotation.x = -0.15 * move_w - crouch * 0.35 - rush * 0.55 + recover_w * 0.1
	_torso.rotation.y = sin(walk) * 0.15 * move_w - crouch * 0.4
	_head.rotation.x = -_torso.rotation.x * 0.7
	_skirt.rotation.x = 0.3 * move_w + rush * 0.5
	# Staff: trailing at the side when walking; levelled forward like a lance when charging.
	var walk_r := Vector3(0.5 - sin(walk) * 0.35 * move_w, 0.0, 0.1)
	var level := Vector3(1.35 - crouch * 0.15, -0.3, 0.1)
	_arm_r.rotation = mixv(walk_r, level, maxf(crouch, rush))
	_arm_l.rotation = mixv(Vector3(sin(walk) * 0.4 * move_w, 0.0, -0.1), Vector3(1.4, 0.5, 0.0), maxf(crouch, rush))
	# Planted wide stance during the wind-up.
	for i in _legs.size():
		var s := -1.0 if i == 0 else 1.0
		_legs[i].rotation.z = s * crouch * 0.25
		_legs[i].rotation.x += s * crouch * 0.3 - rush * 0.0
