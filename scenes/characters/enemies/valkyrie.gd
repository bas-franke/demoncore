extends ProcModel
## "Valkyrie" (HOP: diving strikes): a shieldmaiden of the high halls. Winged helm with white
## wing-crests, long braided gold hair, a silver scale corslet over a blue skirt, a round shield
## with a gold boss, and a spear. Great grey-white wings. HOP: she crouches and spreads her wings
## (wind-up), springs up in a high arc and dives spear-first onto the marked circle.

const HIP := 0.52
const LEAP := 1.6

var _torso: Node3D
var _head: Node3D
var _braid: Node3D
var _arm_l: Node3D
var _arm_r: Node3D


func build() -> void:
	feather_count = 7
	feather_color = Color(0.85, 0.85, 0.88)
	wing_speed = 3.5
	wing_amp = 0.25
	wing_lift = 0.1
	wing_sweep = 0.45
	stride = 1.3
	var scale_mail := Art.mat(Color(0.78, 0.79, 0.82), 0.35, 0.85, 0.2, true, 0.0, &"scales")
	var steel := m_metal(Color(0.8, 0.8, 0.83), 0.3)
	var skirt := m_cloth(Color(0.2, 0.3, 0.5))
	var skin := m_skin(Color(0.9, 0.78, 0.7))
	var hair := Art.mat(Color(0.92, 0.75, 0.4), 0.5, 0.2, 0.05, true, 0.4, &"rope")
	_torso = biped(HIP, 0.045, m_leather(Color(0.3, 0.22, 0.15)), steel, 0.08, 0.55)
	Art.part(body, Art.cylinder(0.14, 0.23), skirt, Vector3(0.0, -0.14, 0.0), Vector3(1.0, 0.32, 0.9))
	Art.part(_torso, Art.cylinder(0.17, 0.13), scale_mail, Vector3(0.0, 0.2, 0.0), Vector3(1.0, 0.42, 0.75))
	Art.part(_torso, Art.cylinder(0.5, 0.5), m_gold(), Vector3(0.0, 0.0, 0.0), Vector3(0.28, 0.04, 0.22))
	for s: float in [-1.0, 1.0]:
		Art.part(_torso, Art.sphere(), steel, Vector3(s * 0.18, 0.37, 0.0), Vector3(0.14, 0.1, 0.15))
	_head = animated(Art.pivot(_torso, Vector3(0.0, 0.5, 0.0)))
	Art.part(_head, Art.sphere(), skin, Vector3.ZERO, Vector3(0.15, 0.18, 0.16))
	Art.part(_head, Art.sphere(), steel, Vector3(0.0, 0.04, 0.01), Vector3(0.17, 0.14, 0.18))
	Art.part(_head, Art.box(), steel, Vector3(0.0, -0.01, -0.085), Vector3(0.02, 0.07, 0.02))
	for s: float in [-1.0, 1.0]:
		Art.part(_head, Art.sphere(), Art.glow(Color(0.6, 0.8, 1.0), 1.6), Vector3(s * 0.035, 0.0, -0.07), Vector3(0.025, 0.015, 0.012))
		# Helm wing-crests.
		var wc := Art.pivot(_head, Vector3(s * 0.09, 0.08, 0.02), Vector3(0.3, 0.0, s * -0.5))
		for k in 3:
			Art.part(wc, Art.sphere(), Art.mat(Art.HOLY_WHITE, 0.7, 0.0, 0.1, true, 0.3, &"feather"), Vector3(s * 0.02, 0.04 + k * 0.03, 0.03 + k * 0.03), Vector3(0.03, 0.1, 0.05))
	# Long braid down the back (sways).
	_braid = animated(Art.pivot(_head, Vector3(0.0, -0.02, 0.08)))
	for i in 5:
		Art.part(_braid, Art.sphere(), hair, Vector3(0.0, -0.05 - i * 0.07, 0.02), Vector3(0.06, 0.08, 0.06))
	solid_wing_pair(_torso, Vector3(0.0, 0.34, 0.1), 0.8, Art.mat(Color(0.86, 0.86, 0.88), 0.7, 0.0, 0.15, true, 0.3, &"feather"), null, Art.mat(Color(0.55, 0.56, 0.6), 0.7, 0.0, 0.15, true, 0.2, &"feather"), 0.08)
	var a := arm(_torso, Vector3(-0.21, 0.36, 0.0), 0.38, 0.038, skin, steel, 0.0, 0.0)
	_arm_l = a[0]
	# Round shield on the left forearm.
	var sh := Art.pivot(a[1], Vector3(-0.05, 0.1, 0.0), Vector3(0.0, 0.0, PI * 0.5))
	Art.part(sh, Art.cylinder(0.5, 0.5), m_wood(), Vector3.ZERO, Vector3(0.38, 0.03, 0.38))
	Art.part(sh, Art.torus(0.85, 1.0), steel, Vector3.ZERO, Vector3.ONE * 0.19)
	Art.part(sh, Art.sphere(), m_gold(), Vector3(0.0, 0.02, 0.0), Vector3(0.09, 0.05, 0.09))
	var b := arm(_torso, Vector3(0.21, 0.36, 0.0), 0.38, 0.038, skin, steel, 0.0, 0.0)
	_arm_r = b[0]
	var sp := Art.pivot(b[1], Vector3.ZERO, Vector3(-PI * 0.5, 0.0, 0.0))
	limb(sp, Vector3(0.0, -0.5, 0.0), Vector3(0.0, 0.75, 0.0), 0.016, m_wood())
	Art.part(sp, Art.cone(0.5), steel, Vector3(0.0, 0.84, 0.0), Vector3(0.06, 0.2, 0.02))
	Art.part(sp, Art.cylinder(0.5, 0.5), m_gold(), Vector3(0.0, 0.73, 0.0), Vector3(0.035, 0.04, 0.035))
	finish()


func pose(_delta: float) -> void:
	var crouch := windup_w
	var air := strike_w
	var lift := 0.0
	if air > 0.05:
		lift = sin(clampf(state_progress, 0.0, 1.0) * PI) * LEAP * air
	body.position.y = HIP + (absf(cos(walk)) - 0.6) * 0.03 * move_w - crouch * 0.06 - land_kick * 0.05 + lift
	# Crouch, then in the air pitch forward into the dive.
	var dive := clampf(state_progress * 2.0 - 0.6, 0.0, 1.0) * air
	_torso.rotation.x = -0.1 * move_w - crouch * 0.3 - dive * 0.6
	_head.rotation.x = crouch * 0.2 + dive * 0.3
	_braid.rotation.x = 0.2 * move_w + air * 0.8 + sin(t * 2.0) * 0.08
	wing_lift = 0.1 + crouch * 0.8 + air * (0.5 - dive * 0.9)
	wing_amp = 0.25 * (1.0 - crouch) + air * 0.2
	wing_sweep = 0.45 - crouch * 0.4 + dive * 0.5
	# Spear: carried upright, cocked back in the crouch, thrust down in the dive.
	_arm_r.rotation = mixv(Vector3(0.4 - sin(walk) * 0.2 * move_w, 0.0, 0.1), deg(150.0, 0.0, 10.0), crouch)
	_arm_r.rotation = mixv(_arm_r.rotation, deg(60.0, 0.0, 0.0), dive)
	_arm_l.rotation = mixv(Vector3(0.6, 0.3, -0.2), Vector3(1.2, 0.6, -0.4), maxf(crouch, air))
