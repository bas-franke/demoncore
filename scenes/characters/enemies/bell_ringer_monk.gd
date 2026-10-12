extends ProcModel
## "Bell-Ringer Monk" (SHOOT -> bell toll, frozen monastery only): the brother who rings the hours
## in the snow. A thin monk in a grey habit and a fur-lined hood, a yoke of three bronze handbells
## across his shoulders and a big handbell in his raised fist. He keeps his distance; when his
## wind-up completes he swings the bell down and a ring of frozen sound rolls outward from him
## (a BellRing, frost tint, via the bell_toll spell): get outside it or dash through it.

const HIP := 0.46

var _torso: Node3D
var _arm_r: Node3D
var _arm_l: Node3D
var _bells: Array[Node3D] = []


func build() -> void:
	feather_count = 0
	mote_count = 4
	stride = 1.0
	var habit := m_cloth(Color(0.42, 0.42, 0.44))
	var fur := m_fur(Color(0.85, 0.82, 0.78))
	var bronze := Art.mat(Art.BRONZE.lightened(0.15), 0.4, 0.5, 0.3, true, 0.2, &"gold")
	var skin := m_skin(Color(0.8, 0.68, 0.6))
	_torso = biped(HIP, 0.04, habit, m_leather(), 0.07, 0.5)
	Art.part(body, Art.cylinder(0.15, 0.24), habit, Vector3(0.0, -0.2, 0.0), Vector3(1.0, 0.44, 0.9))
	Art.part(_torso, Art.cylinder(0.16, 0.14), habit, Vector3(0.0, 0.18, 0.0), Vector3(1.0, 0.38, 0.8))
	var head := Art.pivot(_torso, Vector3(0.0, 0.46, 0.0))
	Art.part(head, Art.sphere(), skin, Vector3.ZERO, Vector3(0.15, 0.18, 0.16))
	Art.part(head, Art.sphere(), fur, Vector3(0.0, 0.03, 0.02), Vector3(0.22, 0.23, 0.22))
	Art.part(head, Art.sphere(), Art.mat(Art.OBSIDIAN, 0.6), Vector3(0.0, 0.0, -0.07), Vector3(0.13, 0.15, 0.06))
	for s: float in [-1.0, 1.0]:
		Art.part(head, Art.sphere(), Art.glow(Color(0.75, 0.9, 1.0), 1.8), Vector3(s * 0.03, 0.01, -0.1), Vector3(0.02, 0.012, 0.01))
	# Yoke of handbells across the shoulders (swing).
	limb(_torso, Vector3(-0.3, 0.38, 0.04), Vector3(0.3, 0.38, 0.04), 0.015, m_wood())
	for k in 3:
		var b := animated(Art.pivot(_torso, Vector3(-0.25 + k * 0.25, 0.37, 0.04)))
		limb(b, Vector3.ZERO, Vector3(0.0, -0.06, 0.0), 0.004, bronze)
		Art.part(b, Art.cylinder(0.04, 0.07), bronze, Vector3(0.0, -0.1, 0.0), Vector3(1.0, 0.08, 1.0))
		_bells.append(b)
	var a := arm(_torso, Vector3(-0.18, 0.34, 0.0), 0.36, 0.035, habit, skin, 0.0, 0.0)
	_arm_l = a[0]
	var bb := arm(_torso, Vector3(0.18, 0.34, 0.0), 0.36, 0.035, habit, skin, 0.0, 0.0)
	_arm_r = bb[0]
	# The great handbell (mouth down along the arm).
	limb(bb[1], Vector3.ZERO, Vector3(0.0, -0.08, 0.0), 0.015, m_wood())
	Art.part(bb[1], Art.cylinder(0.06, 0.12), bronze, Vector3(0.0, -0.16, 0.0), Vector3(1.0, 0.14, 1.0))
	finish()


func pose(_delta: float) -> void:
	biped_bob(HIP, 0.03)
	var ring := windup_w
	_torso.rotation.x = -0.08 * move_w + ring * 0.15 - attack_kick * 0.25
	# Bell lifted high in the wind-up, swung down on the toll.
	_arm_r.rotation = mixv(Vector3(0.5 + sin(t * 3.0) * 0.15, 0.0, 0.15), Vector3(2.8, 0.0, 0.1), ring)
	_arm_r.rotation.x -= attack_kick * 1.8
	_arm_l.rotation = Vector3(0.3 + sin(walk) * 0.2 * move_w, 0.2, -0.15)
	for i in _bells.size():
		_bells[i].rotation.x = sin(walk * 2.0 + float(i)) * 0.3 * move_w + sin(t * 9.0 + float(i)) * 0.25 * attack_kick
