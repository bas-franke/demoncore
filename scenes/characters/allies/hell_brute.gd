extends DemonKit
## "Hell Brute": a hulking pit-demon bruiser, hunched with enormous shoulders and knuckle-dragging
## arms, cracked obsidian pelt glowing with magma seams, a small horned head sunk between the
## shoulders, iron shackles still on its wrists with broken chains. Allies: the tank / slam
## minion (wind-up: both fists raised; strike: ground pound + land_kick).

const HIP := 0.55

var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D


func build() -> void:
	stride = 1.2
	idle_gesture_every = 5.0
	var pelt := Art.mat(Color(0.12, 0.08, 0.08), 0.8, 0.0, 0.5, true, 0.0, &"stone")
	var magma := Art.glow(Art.HELLFIRE, 1.8)
	var iron := m_metal(Color(0.22, 0.2, 0.2), 0.6)
	var horn := Art.mat(Art.BONE.darkened(0.4), 0.6, 0.0, 0.4, true, 0.0, &"bone")
	_torso = biped(HIP, 0.085, pelt, pelt, 0.15, 0.4)
	Art.part(body, Art.sphere(), pelt, Vector3(0.0, -0.02, 0.0), Vector3(0.42, 0.26, 0.34))
	Art.part(body, Art.box(), m_leather(Color(0.2, 0.1, 0.06)), Vector3(0.0, -0.12, -0.15), Vector3(0.24, 0.26, 0.03))
	# Massive hunched upper body.
	Art.part(_torso, Art.sphere(), pelt, Vector3(0.0, 0.3, -0.04), Vector3(0.7, 0.55, 0.5))
	Art.part(_torso, Art.sphere(), pelt, Vector3(0.0, 0.45, 0.08), Vector3(0.55, 0.35, 0.4))
	# Magma seams across the chest and back.
	for k in 4:
		var a := -0.6 + k * 0.4
		Art.part(_torso, Art.box(), magma, Vector3(sin(a) * 0.22, 0.25 + k * 0.06, -0.27 + absf(a) * 0.05), Vector3(0.12, 0.012, 0.012), Vector3(0.0, a, 0.4 - k * 0.25))
	_head = animated(Art.pivot(_torso, Vector3(0.0, 0.45, -0.24)))
	Art.part(_head, Art.sphere(), pelt, Vector3.ZERO, Vector3(0.2, 0.18, 0.2))
	Art.part(_head, Art.box(), pelt, Vector3(0.0, -0.06, -0.06), Vector3(0.18, 0.08, 0.12))
	for s: float in [-1.0, 1.0]:
		Art.part(_head, Art.cone(0.5), Art.mat(Art.IVORY, 0.5), Vector3(s * 0.06, -0.02, -0.12), Vector3(0.03, 0.08, 0.03))
	ember_eyes(_head, Vector3(0.045, 0.02, -0.09), 0.04, Color(1.0, 0.3, 0.05))
	horns(_head, Vector3(0.08, 0.06, 0.0), 0.2, 0.04, horn, 0.9, 1.1)
	for s: float in [-1.0, 1.0]:
		var a := arm(_torso, Vector3(s * 0.36, 0.42, -0.02), 0.62, 0.075, pelt, pelt, 0.0, 0.0)
		# Huge fists and shackles with a broken chain end.
		Art.part(a[1], Art.sphere(), pelt, Vector3(0.0, -0.04, 0.0), Vector3(0.2, 0.2, 0.2))
		Art.part(a[0], Art.cylinder(0.5, 0.5), iron, Vector3(0.0, -0.48, -0.03), Vector3(0.17, 0.08, 0.17))
		for k in 3:
			Art.part(a[0], Art.torus(0.6, 1.0), iron, Vector3(s * 0.02, -0.53 - k * 0.05, 0.06), Vector3.ONE * 0.035, Vector3(0.0, 0.0, PI * 0.5 * float(k % 2)))
		if s < 0.0:
			_arm_l = a[0]
		else:
			_arm_r = a[0]
	finish()


func pose(_delta: float) -> void:
	biped_bob(HIP, 0.06)
	var raise := windup_w
	var pound := maxf(strike_w, recover_w)
	_torso.rotation.x = -0.35 - 0.1 * move_w + raise * 0.4 - pound * 0.35 + gesture_w * 0.25
	_torso.rotation.y = sin(walk) * 0.15 * move_w
	_head.rotation.x = 0.3 - raise * 0.3 + pound * 0.2
	# Knuckle-dragging arms swing with the stride; both fists overhead in the wind-up, slammed
	# down; a chest-beat on gestures.
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var arm_n := _arm_l if i == 0 else _arm_r
		var r := Vector3(0.25 + s * sin(walk) * 0.35 * move_w, 0.0, s * 0.18)
		r = mixv(r, Vector3(2.8, 0.0, s * 0.2), raise)
		r = mixv(r, Vector3(1.0, 0.0, s * 0.1), pound)
		r = mixv(r, Vector3(1.3 + absf(sin(t * 9.0 + float(i) * PI)) * 0.4, 0.0, -s * 0.5), gesture_w)
		arm_n.rotation = r
