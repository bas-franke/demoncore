extends ProcModel
## "Rooftop Archer" (KITE, long range, cathedral city only): a lean hooded bowman who fights from the
## rooftops - he carries his own perch, a section of slate roof with a chimney pot, and stands on
## its ridge (hover), a tall yew longbow, a quiver on the hip and a blue city-watch cloak. Keeps far
## away and shoots heavy arrows (HolyBolt) from up high; when the demon closes in he jumps down
## with the roof chunk and scurries off.

var _perch: Node3D
var _archer: Node3D
var _arm_r: Node3D
var _arm_l: Node3D
var _string: MeshInstance3D


func build() -> void:
	feather_count = 0
	mote_count = 3
	stride = 1.0
	var slate := m_stone(Color(0.28, 0.3, 0.34))
	var brick := Art.mat(Color(0.45, 0.22, 0.16), 0.9, 0.0, 0.4, true, 0.0, &"stone")
	var cloak := m_cloth(Color(0.18, 0.24, 0.42))
	var leather := m_leather(Color(0.35, 0.24, 0.14))
	var skin := m_skin(Color(0.82, 0.66, 0.54))
	body = animated(Art.pivot(self))
	# The roof chunk: two slate slopes meeting at a ridge, a chimney pot.
	_perch = animated(Art.pivot(body))
	for s: float in [-1.0, 1.0]:
		Art.part(_perch, Art.box(), slate, Vector3(s * 0.2, 0.28, 0.0), Vector3(0.46, 0.04, 0.7), Vector3(0.0, 0.0, -s * 0.6))
	Art.part(_perch, Art.box(), brick, Vector3(0.0, 0.2, 0.0), Vector3(0.6, 0.28, 0.66))
	Art.part(_perch, Art.box(), brick, Vector3(0.18, 0.62, 0.22), Vector3(0.14, 0.3, 0.14))
	Art.part(_perch, Art.cylinder(0.5, 0.4), Art.mat(Color(0.5, 0.3, 0.2), 0.8), Vector3(0.18, 0.8, 0.22), Vector3(0.1, 0.08, 0.1))
	# The archer on the ridge.
	_archer = animated(Art.pivot(body, Vector3(0.0, 0.46, -0.05)))
	for s: float in [-1.0, 1.0]:
		var hip := Art.pivot(_archer, Vector3(s * 0.07, 0.42, 0.0))
		limb(hip, Vector3.ZERO, Vector3(s * 0.05, -0.4, 0.0), 0.035, leather)
		add_leg(hip, 0.0 if s < 0.0 else PI, 0.4)
	Art.part(_archer, Art.cylinder(0.13, 0.14), leather, Vector3(0.0, 0.58, 0.0), Vector3(1.0, 0.34, 0.8))
	Art.part(_archer, Art.cylinder(0.12, 0.24), cloak, Vector3(0.0, 0.5, 0.05), Vector3(1.0, 0.5, 0.9))
	Art.part(_archer, Art.sphere(), cloak, Vector3(0.0, 0.85, 0.02), Vector3(0.2, 0.22, 0.2))
	Art.part(_archer, Art.sphere(), skin, Vector3(0.0, 0.84, -0.05), Vector3(0.12, 0.14, 0.1))
	Art.part(_archer, Art.box(), leather, Vector3(0.12, 0.6, 0.12), Vector3(0.08, 0.3, 0.08), Vector3(0.3, 0.0, 0.0))
	for k in 4:
		limb(_archer, Vector3(0.1 + k * 0.012, 0.75, 0.15), Vector3(0.1 + k * 0.012, 0.88, 0.2), 0.004, m_cloth(Art.HOLY_WHITE))
	var a := arm(_archer, Vector3(-0.15, 0.7, 0.0), 0.32, 0.03, cloak, skin, 0.0, 0.0)
	_arm_l = a[0]
	# Longbow held in the left hand (vertical when drawn), its string to the right hand.
	var bow := Art.pivot(a[1], Vector3.ZERO, Vector3(0.0, 0.0, PI * 0.5))
	for s: float in [-1.0, 1.0]:
		limb(bow, Vector3.ZERO, Vector3(s * 0.55, 0.0, 0.1), 0.012, m_wood())
	_string = keep(EnemyModel.limb(bow, Vector3(-0.55, 0.0, 0.1), Vector3(0.55, 0.0, 0.1), 0.003, Art.mat(Art.IVORY, 0.8)))
	var b := arm(_archer, Vector3(0.15, 0.7, 0.0), 0.32, 0.03, cloak, skin, 0.0, 0.0)
	_arm_r = b[0]
	finish()


func pose(_delta: float) -> void:
	var draw := windup_w
	var near := 0.0
	var e := host()
	if e and Game.player:
		near = clampf(1.0 - e.global_position.distance_to(Game.player.global_position) / 5.0, 0.0, 1.0)
	# Up on the ridge while shooting; hops down to run when the demon is close.
	_archer.position.y = 0.46 * (1.0 - maxf(near, move_w * 0.6)) + absf(sin(walk)) * 0.03 * move_w
	_perch.rotation.x = -0.15 * move_w
	_archer.rotation.y = -draw * 0.5
	_arm_l.rotation = mixv(Vector3(0.3, 0.0, -0.1), Vector3(1.5, 0.3, 0.0), draw)
	_arm_r.rotation = mixv(Vector3(0.3 + sin(walk) * 0.2 * move_w, 0.0, 0.1), Vector3(1.4, -0.9, 0.3), draw)
	_arm_r.rotation.x += attack_kick * 0.6
