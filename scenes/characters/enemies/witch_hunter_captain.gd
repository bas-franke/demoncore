extends ProcModel
## "Witch-Hunter Captain" (CHARGE: a fencer's lunge): a lean veteran of the Order in a crimson
## doublet with a black leather buff coat, a gilt gorget, a tall plumed cavalier hat, a sash of
## silver holy symbols, a long silver rapier and a wheellock pistol in the off hand. CHARGE: drops
## into a fencing stance, rapier levelled, pistol raised (wind-up), then lunges through you.

const HIP := 0.52

var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _coat: Node3D
var _plume: Node3D
var _blade: MeshInstance3D


func build() -> void:
	feather_count = 0
	mote_count = 5
	debris = [&"steel"]
	stride = 1.35
	var buff := Art.mat(Color(0.34, 0.23, 0.13), 0.6, 0.0, 0.35, true, 0.2, &"leather")
	var red := m_cloth(Color(0.14, 0.18, 0.36))  # art-style: no red main albedo on heaven's side (navy)
	var boots := m_leather(Color(0.08, 0.06, 0.05))
	var silver := m_metal(Color(0.85, 0.85, 0.88), 0.2)
	var skin := m_skin(Color(0.78, 0.64, 0.55))
	_torso = biped(HIP, 0.04, boots, boots, 0.08, 0.6)
	_coat = animated(Art.pivot(body))
	Art.part(_coat, Art.cylinder(0.16, 0.24), buff, Vector3(0.0, -0.17, 0.02), Vector3(1.0, 0.36, 0.9))
	Art.part(_torso, Art.cylinder(0.17, 0.14), buff, Vector3(0.0, 0.2, 0.0), Vector3(1.0, 0.42, 0.75))
	Art.part(_torso, Art.box(), red, Vector3(0.0, 0.2, -0.11), Vector3(0.14, 0.38, 0.02))
	Art.part(_torso, Art.cylinder(0.12, 0.17), m_gold(), Vector3(0.0, 0.4, 0.0), Vector3(1.0, 0.07, 0.85))
	# Sash across the chest with silver symbols.
	Art.part(_torso, Art.box(), m_cloth(Color(0.15, 0.15, 0.25)), Vector3(0.0, 0.2, -0.12), Vector3(0.05, 0.42, 0.015), Vector3(0.0, 0.0, 0.6))
	for k in 3:
		Art.part(_torso, Art.sphere(), silver, Vector3(-0.08 + k * 0.08, 0.32 - k * 0.12, -0.13), Vector3.ONE * 0.03)
	_head = animated(Art.pivot(_torso, Vector3(0.0, 0.53, 0.0)))
	Art.part(_head, Art.sphere(), skin, Vector3.ZERO, Vector3(0.15, 0.19, 0.16))
	# Pointed beard and moustache.
	Art.part(_head, Art.cone(0.5), m_cloth(Color(0.3, 0.28, 0.26)), Vector3(0.0, -0.11, -0.05), Vector3(0.05, 0.08, 0.04), Vector3(PI + 0.3, 0.0, 0.0))
	Art.part(_head, Art.box(), m_cloth(Color(0.3, 0.28, 0.26)), Vector3(0.0, -0.035, -0.08), Vector3(0.08, 0.012, 0.012))
	for s: float in [-1.0, 1.0]:
		Art.part(_head, Art.sphere(), Art.glow(Art.HOLY_WHITE, 1.2), Vector3(s * 0.035, 0.02, -0.074), Vector3(0.025, 0.012, 0.01))
	# Cavalier hat with one brim pinned up and a tall white plume.
	Art.part(_head, Art.cylinder(0.5, 0.5), buff, Vector3(0.0, 0.1, 0.0), Vector3(0.42, 0.015, 0.42), Vector3(0.0, 0.0, 0.2))
	Art.part(_head, Art.cylinder(0.42, 0.5), buff, Vector3(0.0, 0.17, 0.0), Vector3(0.19, 0.12, 0.19))
	_plume = animated(Art.pivot(_head, Vector3(-0.07, 0.17, 0.02)))
	for i in 4:
		Art.part(_plume, Art.sphere(), m_cloth(Art.HOLY_WHITE), Vector3(-0.02 * i, 0.04 + 0.04 * i, 0.04 + 0.05 * i), Vector3(0.05, 0.06, 0.12))
	var a := arm(_torso, Vector3(-0.2, 0.36, 0.0), 0.4, 0.035, buff, m_leather(), 0.0, 0.0)
	_arm_l = a[0]
	# Wheellock pistol in the left hand.
	var pis := Art.pivot(a[1], Vector3.ZERO, Vector3(-PI * 0.5, 0.0, 0.0))
	Art.part(pis, Art.box(), m_wood(), Vector3(0.0, -0.02, 0.03), Vector3(0.03, 0.08, 0.06))
	Art.part(pis, Art.cylinder(0.5, 0.5), m_metal(Art.STEEL.darkened(0.3), 0.4), Vector3(0.0, 0.1, 0.0), Vector3(0.025, 0.22, 0.025))
	var b := arm(_torso, Vector3(0.2, 0.36, 0.0), 0.4, 0.035, buff, m_leather(), 0.0, 0.0)
	_arm_r = b[0]
	# Rapier: swept gold hilt, long thin silver blade.
	var rp := Art.pivot(b[1], Vector3.ZERO, Vector3(-PI * 0.5, 0.0, 0.0))
	Art.part(rp, Art.torus(0.7, 1.0), m_gold(), Vector3(0.0, 0.03, 0.0), Vector3.ONE * 0.05)
	Art.part(rp, Art.box(), m_gold(), Vector3(0.0, 0.05, 0.0), Vector3(0.14, 0.015, 0.015))
	_blade = keep(Art.part(rp, Art.box(), silver, Vector3(0.0, 0.48, 0.0), Vector3(0.015, 0.85, 0.008)))
	finish()


func pose(_delta: float) -> void:
	var stance := windup_w
	var lunge := strike_w
	biped_bob(HIP, 0.035)
	body.position.y -= stance * 0.05
	_torso.rotation.x = -0.08 * move_w - lunge * 0.4
	_torso.rotation.y = sin(walk) * 0.1 * move_w + stance * 0.6 + lunge * 0.4
	_head.rotation.y = -_torso.rotation.y * 0.8
	_coat.rotation.x = 0.25 * move_w + lunge * 0.5
	_plume.rotation.x = 0.3 * move_w + lunge * 0.6 + sin(t * 3.0) * 0.08
	# Fencing stance: rapier levelled forward, pistol raised high behind.
	var guard := Vector3(0.6 - sin(walk) * 0.25 * move_w, 0.0, 0.1)
	_arm_r.rotation = mixv(guard, Vector3(1.45, -0.5, 0.0), maxf(stance, lunge))
	_arm_l.rotation = mixv(Vector3(0.2 + sin(walk) * 0.3 * move_w, 0.0, -0.15), Vector3(2.4, 0.4, -0.5), stance * (1.0 - lunge))
	for i in _legs.size():
		var s := -1.0 if i == 0 else 1.0
		_legs[i].rotation.x += s * (stance * 0.4 + lunge * 0.6) * -1.0
	EnemyModel.glow(_blade, stance * 0.4 + lunge * 0.7)
