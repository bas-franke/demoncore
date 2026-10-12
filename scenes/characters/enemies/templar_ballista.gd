extends ProcModel
## "Templar Ballista" (SHOOT, long range, slow): a siege engine of the Knights Templar. A heavy
## oak carriage on four iron-rimmed wheels, a great steel-limbed bow with a winch, a white
## mantlet painted with the red cross, and a hooded sergeant crouched behind it cranking the
## winch. SHOOT: the bow is drawn back (the arms bend, the winch turns), then it looses a huge
## blessed bolt (HolyBolt) with a recoil that rocks the carriage. Its wheels roll with the real
## ground speed. Knockback-proof. Breaks apart in splinters and steel on death.

const WHEEL_R := 0.16

var _carriage: Node3D
var _bow: Node3D
var _limbs: Array[Node3D] = []
var _wheels: Array[Node3D] = []
var _crank: Node3D
var _crew_arm: Node3D
var _roll := 0.0


func build() -> void:
	feather_count = 0
	mote_count = 4
	debris = [&"steel", &"shard"]
	debris_color = Color(0.45, 0.32, 0.2)
	death_style = &"sink"
	var wood := m_wood()
	var iron := m_metal(Color(0.25, 0.24, 0.24), 0.5)
	var white := m_cloth(Color(0.88, 0.86, 0.8))
	var red := m_cloth(Art.GOLD)  # art-style: no red main albedo on heaven's side (gold cross)
	_carriage = animated(Art.pivot(self, Vector3(0.0, WHEEL_R, 0.0)))
	Art.part(_carriage, Art.box(), wood, Vector3(0.0, 0.08, 0.05), Vector3(0.4, 0.08, 0.8))
	Art.part(_carriage, Art.box(), wood, Vector3(0.0, 0.2, -0.05), Vector3(0.12, 0.18, 0.7))
	for s: float in [-1.0, 1.0]:
		for z: float in [-0.25, 0.32]:
			var w := animated(Art.pivot(_carriage, Vector3(s * 0.24, 0.0, z)))
			Art.part(w, Art.cylinder(0.5, 0.5), wood, Vector3.ZERO, Vector3(WHEEL_R * 2.0, 0.05, WHEEL_R * 2.0), Vector3(0.0, 0.0, PI * 0.5))
			Art.part(w, Art.torus(0.85, 1.0), iron, Vector3.ZERO, Vector3.ONE * WHEEL_R, Vector3(0.0, 0.0, PI * 0.5))
			Art.part(w, Art.box(), iron, Vector3.ZERO, Vector3(0.06, WHEEL_R * 1.8, 0.02))
			_wheels.append(w)
	# Mantlet shield at the front with the red cross.
	Art.part(_carriage, Art.box(), white, Vector3(0.0, 0.32, -0.36), Vector3(0.5, 0.42, 0.03))
	Art.part(_carriage, Art.box(), red, Vector3(0.0, 0.34, -0.38), Vector3(0.06, 0.32, 0.01))
	Art.part(_carriage, Art.box(), red, Vector3(0.0, 0.4, -0.38), Vector3(0.3, 0.06, 0.01))
	# Bow assembly on top: stock, two steel limbs (they bend when drawn), the bolt laid in.
	_bow = animated(Art.pivot(_carriage, Vector3(0.0, 0.34, 0.0)))
	Art.part(_bow, Art.box(), wood, Vector3(0.0, 0.0, 0.0), Vector3(0.1, 0.08, 0.9))
	for s: float in [-1.0, 1.0]:
		var l := animated(Art.pivot(_bow, Vector3(s * 0.05, 0.02, -0.38)))
		limb(l, Vector3.ZERO, Vector3(s * 0.5, 0.0, 0.1), 0.025, iron)
		Art.part(l, Art.sphere(), iron, Vector3(s * 0.5, 0.0, 0.1), Vector3.ONE * 0.05)
		_limbs.append(l)
	limb(_bow, Vector3(0.0, 0.06, 0.25), Vector3(0.0, 0.06, -0.6), 0.02, Art.mat(Art.IVORY, 0.6))
	Art.part(_bow, Art.cone(0.5), m_gold(), Vector3(0.0, 0.06, -0.66), Vector3(0.07, 0.14, 0.07), Vector3(-PI * 0.5, 0.0, 0.0))
	_crank = animated(Art.pivot(_bow, Vector3(0.0, 0.0, 0.42)))
	limb(_crank, Vector3(-0.12, 0.0, 0.0), Vector3(0.12, 0.0, 0.0), 0.03, wood)
	limb(_crank, Vector3(0.12, 0.0, 0.0), Vector3(0.12, 0.1, 0.0), 0.015, iron)
	# Hooded sergeant crouched at the back.
	var crew := Art.pivot(self, Vector3(0.0, 0.0, 0.62))
	Art.part(crew, Art.cylinder(0.12, 0.17), Art.mat(Color(0.25, 0.22, 0.18), 0.9, 0.0, 0.4, true, 0.0, &"cloth"), Vector3(0.0, 0.25, 0.0), Vector3(1.0, 0.5, 0.9))
	Art.part(crew, Art.box(), white, Vector3(0.0, 0.33, -0.1), Vector3(0.2, 0.3, 0.02))
	Art.part(crew, Art.box(), red, Vector3(0.0, 0.36, -0.115), Vector3(0.04, 0.18, 0.01))
	Art.part(crew, Art.sphere(), Art.mat(Color(0.25, 0.22, 0.18), 0.9, 0.0, 0.4, true, 0.0, &"cloth"), Vector3(0.0, 0.58, 0.02), Vector3(0.16, 0.18, 0.17))
	Art.part(crew, Art.sphere(), Art.mat(Art.OBSIDIAN, 0.5), Vector3(0.0, 0.57, -0.05), Vector3(0.1, 0.1, 0.06))
	_crew_arm = animated(Art.pivot(crew, Vector3(0.13, 0.46, -0.05)))
	limb(_crew_arm, Vector3.ZERO, Vector3(0.0, -0.08, -0.22), 0.03, Art.mat(Color(0.25, 0.22, 0.18), 0.9, 0.0, 0.4, true, 0.0, &"cloth"))
	finish()


func pose(delta: float) -> void:
	_roll += (ground_speed if ground_speed >= 0.0 else move_w * 1.5) / maxf(WHEEL_R * body_scale, 0.05) * delta
	for w in _wheels:
		w.rotation.x = -_roll
	var draw := windup_w
	# Carriage rocks back on the recoil.
	_carriage.rotation.x = attack_kick * 0.12 + sin(t * 9.0) * 0.01 * move_w
	_bow.rotation.x = -0.05 - draw * 0.05
	for i in _limbs.size():
		var s := -1.0 if i == 0 else 1.0
		_limbs[i].rotation.y = s * (draw * 0.45 - attack_kick * 0.2)
	_crank.rotation.x += delta * draw * 9.0
	_crew_arm.rotation.x = sin(_crank.rotation.x) * 0.5 * draw


## Ragdoll death (characters-polish DeathFx): the pivots that flop loose.
func ragdoll_limbs() -> Array:
	return limbs_with([_crank, _crew_arm] + _limbs)
