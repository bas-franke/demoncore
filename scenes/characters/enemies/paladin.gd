extends ProcModel
## "Paladin" (SLAM): a broad knight in heavy steel plate under a white surcoat with a gold cross,
## a visored bascinet with a white plume, a great tower shield on the left arm and a two-handed
## warhammer. Slow and heavy. SLAM: the shield braces forward, the hammer is hoisted over the
## shoulder (wind-up) and brought down on the circle (strike); it leans on the haft (recover).

const HIP := 0.62

var _torso: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _plume: Node3D
var _hammer_head: MeshInstance3D


func build() -> void:
	feather_count = 0
	mote_count = 5
	debris = [&"steel", &"gold"]
	debris_color = Art.GOLD
	stride = 1.1
	var steel := m_metal(Art.STEEL.lightened(0.1))
	var dark := m_metal(Art.STEEL.darkened(0.35), 0.5)
	var gold := m_gold()
	var tabard := m_cloth(Art.HOLY_WHITE.darkened(0.12))
	_torso = biped(HIP, 0.075, steel, dark, 0.12, 0.42)
	# Skirt of the surcoat.
	Art.part(body, Art.cylinder(0.2, 0.27), tabard, Vector3(0.0, -0.12, 0.0), Vector3(1.0, 0.36, 0.9))
	# Barrel chest: tapered cylinder + rounded breast, surcoat front panel with a gold cross.
	Art.part(_torso, Art.cylinder(0.27, 0.2), steel, Vector3(0.0, 0.22, 0.0), Vector3(1.0, 0.44, 0.75))
	Art.part(_torso, Art.sphere(), steel, Vector3(0.0, 0.3, -0.02), Vector3(0.5, 0.32, 0.34))
	Art.part(_torso, Art.box(), tabard, Vector3(0.0, 0.16, -0.16), Vector3(0.3, 0.42, 0.03))
	Art.part(_torso, Art.box(), gold, Vector3(0.0, 0.22, -0.18), Vector3(0.05, 0.24, 0.02))
	Art.part(_torso, Art.box(), gold, Vector3(0.0, 0.27, -0.18), Vector3(0.18, 0.05, 0.02))
	Art.part(_torso, Art.cylinder(0.5, 0.5), m_leather(), Vector3(0.0, 0.0, 0.0), Vector3(0.44, 0.05, 0.34))
	for s: float in [-1.0, 1.0]:
		Art.part(_torso, Art.sphere(), steel, Vector3(s * 0.27, 0.42, 0.0), Vector3(0.26, 0.2, 0.26))
		Art.part(_torso, Art.sphere(), gold, Vector3(s * 0.27, 0.42, 0.0), Vector3(0.27, 0.06, 0.27))
	# Bascinet with a pointed visor, eye slit and plume.
	var head := Art.pivot(_torso, Vector3(0.0, 0.56, 0.0))
	Art.part(head, Art.sphere(), steel, Vector3(0.0, 0.04, 0.0), Vector3(0.24, 0.27, 0.25))
	Art.part(head, Art.cone(0.5), steel, Vector3(0.0, 0.0, -0.12), Vector3(0.16, 0.16, 0.18), Vector3(-PI * 0.5, 0.0, 0.0))
	Art.part(head, Art.box(), Art.glow(Art.HOLY, 1.8), Vector3(0.0, 0.07, -0.125), Vector3(0.15, 0.018, 0.04))
	Art.part(head, Art.cylinder(0.5, 0.5), gold, Vector3(0.0, -0.06, 0.0), Vector3(0.26, 0.05, 0.26))
	_plume = animated(Art.pivot(head, Vector3(0.0, 0.17, 0.04)))
	for i in 4:
		Art.part(_plume, Art.sphere(), m_cloth(Art.HOLY_WHITE), Vector3(0.0, 0.03 + i * 0.01, 0.05 + i * 0.07),
				Vector3(0.07, 0.07, 0.14))
	# Left arm with the tower shield (white field, gold cross, steel rim).
	var a := arm(_torso, Vector3(-0.32, 0.4, 0.0), 0.48, 0.065, steel, dark, 0.0, 0.0)
	_arm_l = a[0]
	var sh := Art.pivot(a[1], Vector3(-0.06, 0.12, -0.08))
	Art.part(sh, Art.box(), dark, Vector3.ZERO, Vector3(0.05, 0.78, 0.5))
	Art.part(sh, Art.box(), Art.mat(Art.IVORY, 0.6, 0.1), Vector3(-0.012, 0.0, 0.0), Vector3(0.04, 0.72, 0.44))
	Art.part(sh, Art.box(), gold, Vector3(-0.035, 0.05, 0.0), Vector3(0.02, 0.5, 0.08))
	Art.part(sh, Art.box(), gold, Vector3(-0.035, 0.14, 0.0), Vector3(0.02, 0.08, 0.32))
	Art.part(sh, Art.cone(0.5), dark, Vector3(0.0, -0.46, 0.0), Vector3(0.05, 0.16, 0.5), Vector3(PI, 0.0, 0.0))
	# Right arm with the warhammer (haft along the hand's -Z at rest).
	var b := arm(_torso, Vector3(0.32, 0.4, 0.0), 0.48, 0.065, steel, dark, 0.0, 0.0)
	_arm_r = b[0]
	var hm := animated(Art.pivot(b[1], Vector3.ZERO, Vector3(-PI * 0.5, 0.0, 0.0)))
	limb(hm, Vector3(0.0, -0.25, 0.0), Vector3(0.0, 0.75, 0.0), 0.025, m_wood())
	_hammer_head = keep(Art.part(hm, Art.box(), Art.emissive(Art.STEEL, Art.HOLY, 0.0, 0.35), Vector3(0.0, 0.75, 0.0), Vector3(0.14, 0.14, 0.3)))
	Art.part(hm, Art.cylinder(0.5, 0.5), gold, Vector3(0.0, 0.75, 0.0), Vector3(0.16, 0.05, 0.16))
	Art.part(hm, Art.cone(0.5), dark, Vector3(0.0, 0.9, 0.0), Vector3(0.06, 0.14, 0.06))
	finish()


func pose(_delta: float) -> void:
	biped_bob(HIP, 0.05)
	var act := maxf(strike_w, recover_w)
	_torso.rotation.x = -0.08 * move_w + windup_w * 0.2 - act * 0.4
	_torso.rotation.y = sin(walk) * 0.1 * move_w - windup_w * 0.35 + act * 0.2
	_plume.rotation.x = 0.25 * move_w + sin(t * 3.0) * 0.06
	# Shield arm: held across the body, braced forward during the attack.
	_arm_l.rotation = mixv(Vector3(0.5 + sin(walk) * 0.1 * move_w, 0.35, -0.15), Vector3(1.1, 0.5, -0.1), maxf(windup_w, act))
	# Hammer: shouldered at rest, hoisted overhead, struck down.
	var rest := Vector3(0.5 - sin(walk) * 0.2 * move_w, 0.0, 0.15)
	var r := mixv(rest, deg(195.0, -10.0, 10.0), windup_w)
	_arm_r.rotation = mixv(r, deg(75.0, 0.0, -5.0), act)
	EnemyModel.glow(_hammer_head, windup_w * 0.7 + strike_w)
