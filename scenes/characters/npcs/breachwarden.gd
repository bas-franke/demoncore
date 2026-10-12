extends DemonKit
## "Kesh, the Breachwarden" (Basecamp NPC, the Chainward): keeper of the portal out of Hell. A
## massive, stooped demon in blackened iron plates riveted straight into its hide, bound in
## heavy chains it carries as a mantle, a ring of great keys at its belt, a horned iron mask with
## a single burning eye-slit and a huge key-headed halberd planted beside it. ~2.4 m tall.
## Gestures: 0 = turns its masked head and rattles the keys (talk), 1 = lifts and slams the
## halberd butt (the portal opens). Drives itself when placed outside an Enemy.

const HIP := 0.95

var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _keys: Node3D
var _slit: MeshInstance3D


func build() -> void:
	idle_gesture_every = 7.0
	stride = 1.6
	var hide_m := Art.mat(Color(0.18, 0.1, 0.09), 0.8, 0.0, 0.5, true, 0.1, &"skin")
	var iron := m_metal(Color(0.12, 0.11, 0.11), 0.55)
	var rust := Art.mat(Color(0.3, 0.16, 0.1), 0.9, 0.5, 0.5, true, 0.0, &"rust")
	var horn := Art.mat(Art.BONE.darkened(0.45), 0.6, 0.0, 0.4, true, 0.0, &"bone")
	_torso = biped(HIP, 0.11, iron, iron, 0.2, 0.3)
	Art.part(body, Art.cylinder(0.3, 0.36), m_leather(Color(0.14, 0.09, 0.06)), Vector3(0.0, -0.2, 0.0), Vector3(1.0, 0.44, 0.9))
	# Barrel torso of riveted plates.
	Art.part(_torso, Art.sphere(), hide_m, Vector3(0.0, 0.42, 0.02), Vector3(0.78, 0.7, 0.56))
	Art.part(_torso, Art.box(), iron, Vector3(0.0, 0.42, -0.2), Vector3(0.5, 0.5, 0.1), Vector3(0.1, 0.0, 0.0))
	for i in 6:
		Art.part(_torso, Art.sphere(), rust, Vector3(-0.2 + 0.08 * float(i), 0.62, -0.25), Vector3.ONE * 0.035)
	# Mantle of chains: overlapping links draped over both shoulders.
	for s: float in [-1.0, 1.0]:
		for k in 7:
			var f := float(k) / 6.0
			Art.part(_torso, Art.torus(0.6, 1.0), iron, Vector3(s * lerpf(0.36, 0.05, f), lerpf(0.75, 0.25, f), lerpf(-0.08, -0.3, f)),
					Vector3.ONE * 0.07, Vector3(0.0, s * 0.5, PI * 0.5 * float(k % 2)))
		Art.part(_torso, Art.sphere(), iron, Vector3(s * 0.4, 0.72, 0.0), Vector3(0.32, 0.24, 0.3))
	# Belt with a ring of keys (swings).
	Art.part(_torso, Art.cylinder(0.5, 0.5), rust, Vector3(0.0, 0.08, 0.0), Vector3(0.6, 0.08, 0.48))
	_keys = animated(Art.pivot(_torso, Vector3(0.24, 0.05, -0.18)))
	Art.part(_keys, Art.torus(0.8, 1.0), iron, Vector3(0.0, -0.06, 0.0), Vector3.ONE * 0.06, Vector3(PI * 0.5, 0.0, 0.0))
	for k in 4:
		var ang := -0.5 + 0.33 * float(k)
		var kp := Art.pivot(_keys, Vector3(0.0, -0.1, 0.0), Vector3(0.0, 0.0, ang))
		limb(kp, Vector3.ZERO, Vector3(0.0, -0.16, 0.0), 0.008, m_gold())
		Art.part(kp, Art.box(), m_gold(), Vector3(0.015, -0.15, 0.0), Vector3(0.03, 0.03, 0.01))
	_head = animated(Art.pivot(_torso, Vector3(0.0, 0.8, -0.22)))
	# Iron mask with one burning slit, horns sweeping out of the iron.
	Art.part(_head, Art.sphere(), hide_m, Vector3.ZERO, Vector3(0.26, 0.26, 0.26))
	Art.part(_head, Art.cylinder(0.5, 0.45), iron, Vector3(0.0, 0.0, -0.06), Vector3(0.26, 0.28, 0.2), Vector3(-0.1, 0.0, 0.0))
	_slit = keep(Art.part(_head, Art.box(), Art.glow(Art.HELLFIRE, 2.6), Vector3(0.0, 0.03, -0.165), Vector3(0.16, 0.022, 0.02)))
	horns(_head, Vector3(0.11, 0.1, 0.02), 0.34, 0.05, horn, 1.2, 1.2)
	var a := arm(_torso, Vector3(-0.44, 0.66, 0.0), 0.7, 0.085, hide_m, iron, 0.0, 0.0)
	_arm_l = a[0]
	Art.part(a[0], Art.cylinder(0.5, 0.5), iron, Vector3(0.0, -0.5, -0.04), Vector3(0.22, 0.2, 0.22))
	var b := arm(_torso, Vector3(0.44, 0.66, 0.0), 0.7, 0.085, hide_m, iron, 0.0, 0.0)
	_arm_r = b[0]
	Art.part(b[0], Art.cylinder(0.5, 0.5), iron, Vector3(0.0, -0.5, -0.04), Vector3(0.22, 0.2, 0.22))
	# Key-halberd held upright: a long haft topped by a giant key bit and a crescent blade.
	var hb := Art.pivot(b[1], Vector3.ZERO, Vector3(PI, 0.0, 0.0))
	limb(hb, Vector3(0.0, -0.9, 0.0), Vector3(0.0, 1.5, 0.0), 0.03, m_wood())
	Art.part(hb, Art.torus(0.7, 1.0), m_gold(), Vector3(0.0, 1.62, 0.0), Vector3.ONE * 0.14, Vector3(PI * 0.5, 0.0, 0.0))
	Art.part(hb, Art.box(), m_gold(), Vector3(0.0, 1.32, -0.09), Vector3(0.04, 0.08, 0.16))
	Art.part(hb, Art.box(), m_gold(), Vector3(0.0, 1.22, -0.07), Vector3(0.04, 0.06, 0.12))
	Art.part(hb, Art.prism(), iron, Vector3(0.0, 1.38, 0.13), Vector3(0.03, 0.4, 0.2), Vector3(0.0, 0.0, 0.0))
	finish()


func pose(_delta: float) -> void:
	biped_bob(HIP, 0.04)
	var talk_w := gesture_w if gesture_id == 0 else 0.0
	var slam := gesture_w if gesture_id == 1 else 0.0
	# Heavy breathing stoop.
	_torso.rotation.x = -0.18 + sin(t * 1.2) * 0.03 - slam * 0.1
	_head.rotation = Vector3(0.1 + sin(t * 0.7) * 0.05, sin(t * 0.35) * 0.3 + talk_w * 0.4, 0.0)
	_keys.rotation.z = sin(t * 2.0) * 0.1 + talk_w * sin(t * 14.0) * 0.4
	_arm_l.rotation = mixv(Vector3(0.15, 0.0, -0.2), Vector3(0.5 + sin(t * 10.0) * 0.2, 0.0, -0.3), talk_w)
	# Halberd planted beside him; lifted then slammed down on gesture 1.
	var lift := sin(clampf(slam, 0.0, 1.0) * PI) * 0.6
	_arm_r.rotation = Vector3(0.45 + lift, 0.0, 0.18)
	_slit.scale = Vector3(0.16, 0.022 * (1.0 + talk_w * 0.6 + slam), 0.02)
