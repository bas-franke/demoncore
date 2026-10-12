extends ProcModel
## "Knight of the Dawn" (CHASE): a templar in mail and a white tabard with a red cross, flat-topped
## great helm with a cross-shaped breath slit, kite shield and arming sword. The rank and file of
## the holy orders. A CHASE enemy, so the sword cut is cosmetic: within reach it swings
## (proximity_attack -> play_attack -> attack_kick drives the cut).

const HIP := 0.55

var _torso: Node3D
var _arm_l: Node3D
var _arm_r: Node3D


func build() -> void:
	feather_count = 0
	debris = [&"steel"]
	stride = 1.25
	proximity_range = 1.6
	proximity_cooldown = 1.6
	var mail := Art.mat(Art.STEEL.darkened(0.15), 0.55, 0.8, 0.35, true, 0.0, &"chainmail")
	var steel := m_metal(Art.STEEL)
	var tabard := m_cloth(Color(0.86, 0.84, 0.78))
	# Gold cross / trim (red is the demon palette, docs/team/art-style.md). Name kept for the code below.
	var red := m_cloth(Art.GOLD)
	_torso = biped(HIP, 0.06, mail, m_leather(), 0.1, 0.55)
	Art.part(body, Art.cylinder(0.16, 0.22), tabard, Vector3(0.0, -0.13, 0.0), Vector3(1.0, 0.34, 0.85))
	Art.part(_torso, Art.cylinder(0.2, 0.16), mail, Vector3(0.0, 0.2, 0.0), Vector3(1.0, 0.42, 0.8))
	Art.part(_torso, Art.box(), tabard, Vector3(0.0, 0.17, -0.11), Vector3(0.28, 0.44, 0.03))
	Art.part(_torso, Art.box(), red, Vector3(0.0, 0.2, -0.13), Vector3(0.05, 0.3, 0.02))
	Art.part(_torso, Art.box(), red, Vector3(0.0, 0.26, -0.13), Vector3(0.2, 0.05, 0.02))
	Art.part(_torso, Art.cylinder(0.5, 0.5), m_leather(), Vector3(0.0, 0.0, 0.0), Vector3(0.36, 0.05, 0.28))
	# Great helm: flat-topped cylinder with a cross slit.
	var head := Art.pivot(_torso, Vector3(0.0, 0.52, 0.0))
	Art.part(head, Art.cylinder(0.5, 0.5), steel, Vector3(0.0, 0.03, 0.0), Vector3(0.22, 0.26, 0.23))
	Art.part(head, Art.box(), Art.mat(Art.OBSIDIAN, 0.5), Vector3(0.0, 0.06, -0.113), Vector3(0.16, 0.02, 0.01))
	Art.part(head, Art.box(), Art.mat(Art.OBSIDIAN, 0.5), Vector3(0.0, 0.0, -0.113), Vector3(0.02, 0.13, 0.01))
	Art.part(head, Art.cylinder(0.5, 0.5), m_gold(), Vector3(0.0, 0.15, 0.0), Vector3(0.23, 0.02, 0.24))
	var a := arm(_torso, Vector3(-0.24, 0.38, 0.0), 0.42, 0.05, mail, m_leather(), 0.0, 0.0)
	_arm_l = a[0]
	# Kite shield (white, red cross), on the forearm facing out to the left-front.
	var sh := Art.pivot(a[1], Vector3(-0.05, 0.1, -0.05), Vector3(0.0, -0.5, 0.0))
	Art.part(sh, Art.box(), tabard, Vector3.ZERO, Vector3(0.04, 0.38, 0.32))
	Art.part(sh, Art.cone(0.5), tabard, Vector3(0.0, -0.32, 0.0), Vector3(0.04, 0.26, 0.32), Vector3(PI, 0.0, 0.0))
	Art.part(sh, Art.box(), red, Vector3(-0.025, -0.03, 0.0), Vector3(0.01, 0.42, 0.05))
	Art.part(sh, Art.box(), red, Vector3(-0.025, 0.06, 0.0), Vector3(0.01, 0.05, 0.26))
	var b := arm(_torso, Vector3(0.24, 0.38, 0.0), 0.42, 0.05, mail, m_leather(), 0.0, 0.0)
	_arm_r = b[0]
	var sw := Art.pivot(b[1], Vector3.ZERO, Vector3(-PI * 0.5, 0.0, 0.0))
	Art.part(sw, Art.box(), steel, Vector3(0.0, 0.38, 0.0), Vector3(0.05, 0.62, 0.012))
	Art.part(sw, Art.box(), m_gold(), Vector3(0.0, 0.06, 0.0), Vector3(0.2, 0.03, 0.03))
	Art.part(sw, Art.cylinder(0.5, 0.5), m_leather(), Vector3(0.0, -0.02, 0.0), Vector3(0.03, 0.12, 0.03))
	finish()


func proximity_attack() -> void:
	play_attack()


func pose(_delta: float) -> void:
	biped_bob(HIP)
	var cut := attack_kick  # 1 -> 0 over 0.25 s
	_torso.rotation.x = -0.12 * move_w - cut * 0.2
	_torso.rotation.y = sin(walk) * 0.12 * move_w + (cut - 0.5) * cut * 0.8
	_arm_l.rotation = Vector3(0.7 + sin(walk) * 0.15 * move_w, 0.3, -0.1)
	# Sword: raised high when a cut starts, sweeping down as attack_kick decays.
	var guard := Vector3(0.6 - sin(walk) * 0.3 * move_w, 0.0, 0.1)
	_arm_r.rotation = mixv(guard, deg(lerpf(40.0, 170.0, cut), 0.0, lerpf(0.0, 25.0, cut)), minf(cut * 3.0, 1.0))
