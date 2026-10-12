extends ProcModel
## "Plague Doctor of the Holy Order" (KITE / SHOOT, holy smoke): a physician-monk of the Order of
## the Purging Flame. A long waxed black coat, a white beaked mask stuffed with blessed herbs, round
## glass lenses glowing gold, a wide-brimmed hat, a tall pointer cane topped with a censer-orb, and
## a hanging bundle of herbs and phials. It backs away and sprays sanctified fumigation (the
## censer cane is thrust forward on the shot; the beak lifts as it sniffs you out).

const HIP := 0.5
const LENS := Color(1.0, 0.82, 0.4)

var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _coat: Node3D
var _orb: MeshInstance3D


func build() -> void:
	feather_count = 0
	mote_count = 4
	stride = 1.2
	var coat := Art.mat(Color(0.14, 0.13, 0.13), 0.35, 0.0, 0.3, true, 0.5, &"leather")
	var mask := Art.mat(Color(0.86, 0.82, 0.72), 0.6, 0.0, 0.3, true, 0.1, &"leather")
	var brass := Art.mat(Art.BRONZE, 0.35, 0.9, 0.2, true, 0.0, &"gold")
	_torso = biped(HIP, 0.04, coat, m_leather(Color(0.1, 0.07, 0.05)), 0.08, 0.5)
	_coat = animated(Art.pivot(body))
	Art.part(_coat, Art.cylinder(0.16, 0.27), coat, Vector3(0.0, -0.22, 0.02), Vector3(1.0, 0.5, 0.92))
	Art.part(_torso, Art.cylinder(0.18, 0.15), coat, Vector3(0.0, 0.2, 0.0), Vector3(1.0, 0.42, 0.78))
	Art.part(_torso, Art.cylinder(0.5, 0.5), m_leather(), Vector3(0.0, 0.02, 0.0), Vector3(0.33, 0.05, 0.26))
	# A red Order cross on the breast and a bandolier of phials.
	Art.part(_torso, Art.box(), Art.mat(Art.CRIMSON, 0.5), Vector3(-0.06, 0.25, -0.12), Vector3(0.03, 0.12, 0.01))
	Art.part(_torso, Art.box(), Art.mat(Art.CRIMSON, 0.5), Vector3(-0.06, 0.27, -0.12), Vector3(0.08, 0.03, 0.01))
	for k in 4:
		Art.part(_torso, Art.cylinder(0.5, 0.5), Art.emissive(Color(0.3, 0.5, 0.25), Color(0.5, 1.0, 0.4), 0.8), Vector3(0.12 - k * 0.05, 0.12 + k * 0.05, -0.13), Vector3(0.025, 0.06, 0.025), Vector3(0.0, 0.0, 0.7))
	_head = animated(Art.pivot(_torso, Vector3(0.0, 0.5, 0.0)))
	# Hood, the beaked mask (a long curving cone) and two gold lenses.
	Art.part(_head, Art.sphere(), coat, Vector3(0.0, 0.0, 0.02), Vector3(0.2, 0.22, 0.2))
	Art.part(_head, Art.sphere(), mask, Vector3(0.0, 0.0, -0.05), Vector3(0.16, 0.17, 0.14))
	Art.part(_head, Art.cone(0.5), mask, Vector3(0.0, -0.06, -0.2), Vector3(0.08, 0.28, 0.09), Vector3(-PI * 0.5 - 0.35, 0.0, 0.0))
	for s: float in [-1.0, 1.0]:
		Art.part(_head, Art.torus(0.7, 1.0), brass, Vector3(s * 0.045, 0.03, -0.11), Vector3.ONE * 0.035, Vector3(PI * 0.5, 0.0, 0.0))
		Art.part(_head, Art.sphere(), Art.glow(LENS, 2.0), Vector3(s * 0.045, 0.03, -0.115), Vector3(0.05, 0.05, 0.015))
	# Wide-brimmed hat.
	Art.part(_head, Art.cylinder(0.5, 0.5), coat, Vector3(0.0, 0.11, 0.0), Vector3(0.5, 0.015, 0.5))
	Art.part(_head, Art.cylinder(0.45, 0.5), coat, Vector3(0.0, 0.19, 0.0), Vector3(0.2, 0.15, 0.2))
	var a := arm(_torso, Vector3(-0.2, 0.38, 0.0), 0.4, 0.04, coat, m_leather(Color(0.1, 0.07, 0.05)), 0.0, 0.0)
	_arm_l = a[0]
	# Bundle of herbs and a phial in the left hand.
	Art.part(a[1], Art.cone(0.5), Art.mat(Color(0.3, 0.4, 0.2), 0.9, 0.0, 0.4), Vector3(0.0, -0.1, 0.0), Vector3(0.08, 0.16, 0.08), Vector3(PI, 0.0, 0.0))
	var b := arm(_torso, Vector3(0.2, 0.38, 0.0), 0.4, 0.04, coat, m_leather(Color(0.1, 0.07, 0.05)), 0.0, 0.0)
	_arm_r = b[0]
	# Censer cane: a long black rod with a brass orb that smokes and glows.
	var cane := Art.pivot(b[1], Vector3.ZERO, Vector3(-PI * 0.5, 0.0, 0.0))
	limb(cane, Vector3(0.0, -0.3, 0.0), Vector3(0.0, 0.6, 0.0), 0.012, coat)
	Art.part(cane, Art.sphere(), brass, Vector3(0.0, 0.64, 0.0), Vector3.ONE * 0.08)
	_orb = keep(Art.part(cane, Art.sphere(), Art.glow(Color(0.85, 1.0, 0.6), 1.4), Vector3(0.0, 0.64, 0.0), Vector3.ONE * 0.06))
	finish()


func pose(_delta: float) -> void:
	biped_bob(HIP, 0.03)
	var aim := maxf(windup_w, strike_w)
	_torso.rotation.x = -0.1 * move_w + 0.1 * aim + attack_kick * 0.1
	_head.rotation = Vector3(-0.2 * aim + sin(t * 1.7) * 0.06, sin(t * 0.9) * 0.3 * (1.0 - aim), 0.0)
	_coat.rotation.x = 0.25 * move_w + sin(walk * 2.0) * 0.04
	_arm_l.rotation = Vector3(0.5 - sin(walk) * 0.2 * move_w, 0.2, -0.1)
	_arm_r.rotation = mixv(Vector3(0.3 + sin(walk) * 0.25 * move_w, 0.0, 0.1), Vector3(1.35 + attack_kick * 0.3, 0.0, 0.0), aim)
	_orb.scale = Vector3.ONE * 0.06 * (1.0 + aim * 0.9 + 0.1 * sin(t * 7.0))
