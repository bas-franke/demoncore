extends ProcModel
## "Frost-Blessed Hermit" (KITE: keeps away, casts): an ascetic of the frozen monastery who has
## prayed on the mountain so long the cold blessed him back. Bent and gaunt in layered grey wool
## and a white bear pelt, a long beard of icicles, frost-white eyes, a crook of blue ice with a
## burning-cold star at its tip and a rime of snow on his shoulders. KITE/SHOOT: he raises the
## crook (wind-up, frost gathering) and flings a mote of holy frost (holy orb).

const FROST := Color(0.7, 0.9, 1.0)
const HIP := 0.44

var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _star: MeshInstance3D


func build() -> void:
	feather_count = 0
	mote_count = 8
	light_color = FROST
	debris = [&"shard"]
	debris_color = FROST
	stride = 0.9
	var wool := m_cloth(Color(0.42, 0.42, 0.44))
	var pelt := m_fur(Color(0.9, 0.9, 0.88))
	var ice := Art.mat(Color(0.72, 0.88, 1.0), 0.1, 0.0, 0.0, true, 0.8, &"crystal")
	var skin := m_skin(Color(0.75, 0.75, 0.8))
	_torso = biped(HIP, 0.035, wool, m_fur(Color(0.4, 0.35, 0.3)), 0.07, 0.4)
	Art.part(body, Art.cylinder(0.15, 0.24), wool, Vector3(0.0, -0.18, 0.0), Vector3(1.0, 0.4, 0.9))
	Art.part(_torso, Art.cylinder(0.17, 0.15), wool, Vector3(0.0, 0.16, 0.02), Vector3(1.0, 0.36, 0.85))
	# Bear-pelt mantle with snow on top, the bear's head as a hood.
	Art.part(_torso, Art.sphere(), pelt, Vector3(0.0, 0.3, 0.05), Vector3(0.42, 0.24, 0.36))
	Art.part(_torso, Art.sphere(), m_cloth(Color(0.96, 0.97, 1.0)), Vector3(0.0, 0.38, 0.06), Vector3(0.34, 0.08, 0.28))
	_head = animated(Art.pivot(_torso, Vector3(0.0, 0.42, -0.06)))
	Art.part(_head, Art.sphere(), skin, Vector3.ZERO, Vector3(0.14, 0.17, 0.15))
	Art.part(_head, Art.sphere(), pelt, Vector3(0.0, 0.06, 0.02), Vector3(0.2, 0.16, 0.2))
	for s: float in [-1.0, 1.0]:
		Art.part(_head, Art.sphere(), pelt, Vector3(s * 0.08, 0.13, 0.02), Vector3.ONE * 0.05)
		Art.part(_head, Art.sphere(), Art.glow(FROST, 2.0), Vector3(s * 0.035, 0.01, -0.07), Vector3(0.025, 0.012, 0.01))
	# Beard of icicles.
	for i in 5:
		var x := -0.04 + i * 0.02
		Art.part(_head, Art.cone(0.5), ice, Vector3(x, -0.12 - absf(x) * 0.5, -0.06), Vector3(0.025, 0.12 - absf(x) * 1.2, 0.025), Vector3(PI, 0.0, 0.0))
	var a := arm(_torso, Vector3(-0.18, 0.3, 0.0), 0.36, 0.035, wool, skin, 0.0, 0.0)
	_arm_l = a[0]
	var b := arm(_torso, Vector3(0.18, 0.3, 0.0), 0.36, 0.035, wool, skin, 0.0, 0.0)
	_arm_r = b[0]
	# Ice crook, planted beside him: shaft up out of the fist, a hooked top with a cold star.
	var cr := Art.pivot(b[1], Vector3.ZERO, Vector3(PI, 0.0, 0.0))
	limb(cr, Vector3(0.0, -0.25, 0.0), Vector3(0.0, 0.7, 0.0), 0.016, ice)
	Art.part(cr, Art.torus(0.75, 1.0), ice, Vector3(0.0, 0.78, -0.07), Vector3.ONE * 0.09, Vector3(0.0, 0.0, PI * 0.5))
	_star = keep(Art.part(cr, Art.sphere(), Art.glow(FROST, 2.6), Vector3(0.0, 0.76, -0.14), Vector3.ONE * 0.06))
	finish()


func pose(_delta: float) -> void:
	biped_bob(HIP, 0.02)
	var cast := windup_w
	# Bent with age; straightens to cast.
	_torso.rotation.x = -0.3 + cast * 0.3 - attack_kick * 0.15
	_head.rotation.x = 0.15 - cast * 0.3
	_head.rotation.y = sin(t * 0.6) * 0.2
	# Crook used as a walking staff, raised high to cast.
	_arm_r.rotation = mixv(Vector3(0.5 + sin(walk) * 0.15 * move_w, 0.0, 0.15), Vector3(2.6, 0.0, 0.1), cast)
	_arm_r.rotation.x -= attack_kick * 0.8
	_arm_l.rotation = mixv(Vector3(0.3, 0.3, -0.1), Vector3(1.2, 0.4, -0.3), cast)
	_star.scale = Vector3.ONE * 0.06 * (1.0 + cast * 1.4 + 0.12 * sin(t * 6.0))
