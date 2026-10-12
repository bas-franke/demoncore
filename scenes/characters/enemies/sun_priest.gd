extends ProcModel
## "Sun-Priest" (KITE -> mirror beam, sunlit citadel only): a priest of the Dawn in white and gold
## vestments with a towering sunburst mitre, carrying a great round mirror of polished gold on a
## pole. He catches the light (the mirror swings up to face the sky, blazing) and throws it down a
## straight lane at the demon: a telegraphed beam (mirror_beam spell, dawn tint), long and narrow.

const SUN := Color(1.0, 0.82, 0.4)
const HIP := 0.5

var _torso: Node3D
var _arm_r: Node3D
var _arm_l: Node3D
var _mirror: Node3D
var _glare: MeshInstance3D


func build() -> void:
	feather_count = 0
	mote_count = 6
	light_color = SUN
	stride = 1.0
	var robe := m_cloth(Color(0.95, 0.93, 0.88))
	var gold := Art.mat(Art.GOLD, 0.3, 0.55, 0.1, true, 0.3, &"gold")
	var skin := m_skin(Color(0.72, 0.55, 0.42))
	_torso = biped(HIP, 0.04, robe, gold, 0.07, 0.45)
	Art.part(body, Art.cylinder(0.15, 0.27), robe, Vector3(0.0, -0.22, 0.0), Vector3(1.0, 0.5, 0.95))
	Art.part(_torso, Art.cylinder(0.17, 0.15), robe, Vector3(0.0, 0.2, 0.0), Vector3(1.0, 0.42, 0.8))
	Art.part(_torso, Art.box(), gold, Vector3(0.0, 0.0, -0.13), Vector3(0.08, 0.8, 0.02))
	Art.part(_torso, Art.cylinder(0.16, 0.24), gold, Vector3(0.0, 0.38, 0.0), Vector3(1.0, 0.08, 0.9))
	var head := Art.pivot(_torso, Vector3(0.0, 0.5, 0.0))
	Art.part(head, Art.sphere(), skin, Vector3.ZERO, Vector3(0.15, 0.18, 0.16))
	# Sunburst mitre: a gold disc behind the head ringed with rays.
	Art.part(head, Art.cylinder(0.5, 0.5), gold, Vector3(0.0, 0.16, 0.06), Vector3(0.26, 0.02, 0.26), Vector3(PI * 0.5, 0.0, 0.0))
	for k in 12:
		var ang := TAU * float(k) / 12.0
		Art.part(head, Art.cone(0.5), gold, Vector3(cos(ang) * 0.17, 0.16 + sin(ang) * 0.17, 0.06), Vector3(0.03, 0.1 + 0.04 * float(k % 2), 0.01), Vector3(0.0, 0.0, ang - PI * 0.5))
	var a := arm(_torso, Vector3(-0.19, 0.36, 0.0), 0.38, 0.035, robe, skin, 0.0, 0.0)
	_arm_l = a[0]
	var b := arm(_torso, Vector3(0.19, 0.36, 0.0), 0.38, 0.035, robe, skin, 0.0, 0.0)
	_arm_r = b[0]
	# The mirror on a pole, held up in both hands (on the right hand pivot).
	var pole := Art.pivot(b[1], Vector3.ZERO, Vector3(PI, 0.0, 0.0))
	limb(pole, Vector3(0.0, -0.3, 0.0), Vector3(0.0, 0.7, 0.0), 0.014, gold)
	_mirror = animated(Art.pivot(pole, Vector3(0.0, 0.8, 0.0)))
	Art.part(_mirror, Art.cylinder(0.5, 0.5), gold, Vector3.ZERO, Vector3(0.42, 0.03, 0.42), Vector3(PI * 0.5, 0.0, 0.0))
	Art.part(_mirror, Art.cylinder(0.5, 0.5), Art.mat(Color(1.0, 0.95, 0.8), 0.02, 1.0, 0.0, true, 0.9), Vector3(0.0, 0.0, -0.02), Vector3(0.36, 0.01, 0.36), Vector3(PI * 0.5, 0.0, 0.0))
	_glare = keep(Art.part(_mirror, Art.sphere(), Art.glow(SUN, 2.6), Vector3(0.0, 0.0, -0.04), Vector3(0.05, 0.05, 0.01)))
	finish()


func pose(_delta: float) -> void:
	biped_bob(HIP, 0.03)
	var catch_w := windup_w
	_torso.rotation.x = -0.05 * move_w + catch_w * 0.12 - attack_kick * 0.2
	_arm_r.rotation = mixv(Vector3(0.5, 0.0, 0.1), Vector3(1.9, 0.0, 0.05), catch_w)
	_arm_l.rotation = mixv(Vector3(0.6, 0.3, -0.1), Vector3(1.8, 0.2, -0.05), catch_w)
	# The mirror tilts to the sky to catch the sun, then snaps down at the demon.
	_mirror.rotation.x = lerpf(0.2, -1.2, catch_w) + attack_kick * 1.4
	_glare.scale = Vector3(0.05, 0.05, 0.01) * (1.0 + catch_w * 4.0 + attack_kick * 3.0) + Vector3(0.0, 0.0, 0.0)
