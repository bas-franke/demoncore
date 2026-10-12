extends ProcModel
## "Golden Legionary" (CHASE, shield-first, sunlit citadel only): a soldier of the citadel's
## celestial legion - a gilded muscle cuirass, a crested golden helm with a full face-guard, a red
## sash and greaves, a tall curved rectangular scutum with a sunburst boss, and a short gladius.
## Shield up: while the demon is in front of it (within a 100-degree cone) it wards itself
## (Enemy.apply_ward: takes 65% less damage). Flank it. The cosmetic stab happens in reach.

const HIP := 0.55
const FRONT_COS := 0.64
const WARD := 0.65

var _torso: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _shield_up := 0.0


func build() -> void:
	feather_count = 0
	mote_count = 4
	debris = [&"gold", &"steel"]
	debris_color = Art.GOLD
	stride = 1.2
	proximity_range = 1.4
	proximity_cooldown = 1.4
	var gold := Art.mat(Art.GOLD, 0.3, 0.6, 0.15, true, 0.3, &"gold")
	var red := m_cloth(Color(0.6, 0.08, 0.06))
	var skin := m_skin(Color(0.75, 0.58, 0.45))
	_torso = biped(HIP, 0.05, skin, gold, 0.09, 0.5)
	Art.part(body, Art.cylinder(0.17, 0.22), red, Vector3(0.0, -0.1, 0.0), Vector3(1.0, 0.24, 0.85))
	for k in 6:
		var theta := -0.7 + k * 0.28
		Art.part(body, Art.box(), gold, Vector3(sin(theta) * 0.19, -0.16, -cos(theta) * 0.15), Vector3(0.06, 0.2, 0.01), Vector3(0.0, -theta, 0.0))
	Art.part(_torso, Art.cylinder(0.21, 0.17), gold, Vector3(0.0, 0.22, 0.0), Vector3(1.0, 0.44, 0.8))
	Art.part(_torso, Art.box(), red, Vector3(0.0, 0.05, -0.13), Vector3(0.36, 0.04, 0.03), Vector3(0.0, 0.0, 0.3))
	var head := Art.pivot(_torso, Vector3(0.0, 0.52, 0.0))
	Art.part(head, Art.sphere(), gold, Vector3.ZERO, Vector3(0.2, 0.22, 0.22))
	Art.part(head, Art.box(), Art.mat(Art.OBSIDIAN, 0.5), Vector3(0.0, 0.0, -0.105), Vector3(0.1, 0.02, 0.01))
	# Transverse crest of red horsehair.
	for k in 7:
		Art.part(head, Art.sphere(), red, Vector3(-0.15 + k * 0.05, 0.14 + 0.02 * sin(float(k) * 0.9), 0.0), Vector3(0.06, 0.1, 0.06))
	var a := arm(_torso, Vector3(-0.24, 0.4, 0.0), 0.42, 0.045, skin, gold, 0.0, 0.0)
	_arm_l = a[0]
	# Scutum: a tall curved shield with a sunburst boss.
	var sc := Art.pivot(a[1], Vector3(-0.04, 0.16, -0.08), Vector3(0.0, 0.0, 0.0))
	for k in 3:
		var ang := -0.35 + k * 0.35
		Art.part(sc, Art.box(), red, Vector3(sin(ang) * 0.14, 0.0, -cos(ang) * 0.06 + 0.06), Vector3(0.15, 0.78, 0.03), Vector3(0.0, -ang, 0.0))
	Art.part(sc, Art.sphere(), gold, Vector3(0.0, 0.0, -0.03), Vector3(0.14, 0.14, 0.08))
	Art.part(sc, Art.box(), gold, Vector3(0.0, 0.38, 0.0), Vector3(0.44, 0.03, 0.05))
	Art.part(sc, Art.box(), gold, Vector3(0.0, -0.38, 0.0), Vector3(0.44, 0.03, 0.05))
	var b := arm(_torso, Vector3(0.24, 0.4, 0.0), 0.42, 0.045, skin, gold, 0.0, 0.0)
	_arm_r = b[0]
	var gl := Art.pivot(b[1], Vector3.ZERO, Vector3(-PI * 0.5, 0.0, 0.0))
	Art.part(gl, Art.box(), m_metal(Art.STEEL, 0.3), Vector3(0.0, 0.25, 0.0), Vector3(0.05, 0.4, 0.012))
	Art.part(gl, Art.box(), gold, Vector3(0.0, 0.04, 0.0), Vector3(0.1, 0.025, 0.03))
	finish()


func proximity_attack() -> void:
	play_attack()


func pose(delta: float) -> void:
	biped_bob(HIP, 0.035)
	_shield_wall(delta)
	var stab := attack_kick
	_torso.rotation.x = -0.08 * move_w - stab * 0.15
	_torso.rotation.y = -_shield_up * 0.25 + stab * 0.3
	# Shield raised and forward when the demon is in front.
	_arm_l.rotation = mixv(Vector3(0.4, 0.4, -0.1), Vector3(1.25, 0.6, 0.0), _shield_up)
	_arm_r.rotation = mixv(Vector3(0.5 - sin(walk) * 0.2 * move_w, 0.0, 0.1), Vector3(1.6, -0.2, 0.1), stab)


## Wards the host while the demon is inside the shield's front cone.
func _shield_wall(delta: float) -> void:
	var e := host()
	var p := Game.player
	var front := false
	if e and p and model_facing_ok():
		var to := p.global_position - e.global_position
		to.y = 0.0
		var fwd := -global_transform.basis.z
		fwd.y = 0.0
		if to.length_squared() > 0.01 and fwd.length_squared() > 0.01:
			front = to.normalized().dot(fwd.normalized()) > FRONT_COS
	_shield_up = damp(_shield_up, 1.0 if front else 0.0, 8.0, delta)
	if front and e:
		e.apply_ward(0.3, WARD)


func model_facing_ok() -> bool:
	return is_inside_tree()


func ragdoll_limbs() -> Array:
	return limbs_with([])
