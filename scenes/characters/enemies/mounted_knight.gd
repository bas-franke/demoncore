extends HolyHorse
## "Mounted Knight" (CHARGE: a fast lance pass): a knight of the holy orders on a barded grey
## destrier - white caparison with a red cross over the horse, the rider in plate and a white
## surcoat with a great helm, a long lance with a pennant couched under the arm and a heater
## shield. CHARGE: the lance drops level and the horse gathers (wind-up), then a long, very fast
## pass straight through the demon (the data gives it a long charge_time and a high speed).

var _rider: Node3D
var _lance: Node3D
var _pennant: Node3D


func build() -> void:
	mote_count = 6
	debris = [&"steel"]
	build_horse(Color(0.62, 0.62, 0.64), Color(0.25, 0.24, 0.24))
	stride = 2.0
	var white := m_cloth(Color(0.86, 0.84, 0.78))
	var red := m_cloth(Color(0.6, 0.07, 0.06))
	var plate := m_metal(Art.STEEL.lightened(0.05))
	# Caparison draped over the horse with a red cross on each flank.
	Art.part(body, Art.box(), white, Vector3(0.0, -0.02, 0.02), Vector3(0.34, 0.3, 0.86))
	for s: float in [-1.0, 1.0]:
		Art.part(body, Art.box(), red, Vector3(s * 0.172, 0.0, 0.05), Vector3(0.005, 0.2, 0.05))
		Art.part(body, Art.box(), red, Vector3(s * 0.172, 0.05, 0.05), Vector3(0.005, 0.05, 0.16))
	Art.part(head, Art.box(), plate, Vector3(0.0, 0.03, -0.12), Vector3(0.1, 0.08, 0.26))
	# The rider in the saddle.
	_rider = animated(Art.pivot(body, Vector3(0.0, 0.2, 0.05)))
	Art.part(_rider, Art.box(), m_leather(), Vector3(0.0, -0.02, 0.0), Vector3(0.2, 0.06, 0.26))
	for s: float in [-1.0, 1.0]:
		limb(_rider, Vector3(s * 0.1, 0.02, 0.0), Vector3(s * 0.2, -0.3, -0.04), 0.035, plate)
	Art.part(_rider, Art.cylinder(0.14, 0.12), plate, Vector3(0.0, 0.22, 0.0), Vector3(1.0, 0.38, 0.8))
	Art.part(_rider, Art.box(), white, Vector3(0.0, 0.18, -0.1), Vector3(0.2, 0.36, 0.02))
	Art.part(_rider, Art.box(), red, Vector3(0.0, 0.2, -0.112), Vector3(0.04, 0.24, 0.01))
	Art.part(_rider, Art.box(), red, Vector3(0.0, 0.26, -0.112), Vector3(0.15, 0.04, 0.01))
	var helm := Art.pivot(_rider, Vector3(0.0, 0.48, 0.0))
	Art.part(helm, Art.cylinder(0.5, 0.5), plate, Vector3.ZERO, Vector3(0.18, 0.22, 0.19))
	Art.part(helm, Art.box(), Art.mat(Art.OBSIDIAN, 0.5), Vector3(0.0, 0.03, -0.096), Vector3(0.13, 0.016, 0.01))
	Art.part(helm, Art.cone(0.5), red, Vector3(0.0, 0.17, 0.0), Vector3(0.05, 0.14, 0.05))
	# Shield on the left, lance couched on the right.
	Art.part(_rider, Art.box(), white, Vector3(-0.17, 0.22, -0.02), Vector3(0.03, 0.26, 0.2))
	Art.part(_rider, Art.box(), red, Vector3(-0.188, 0.24, -0.02), Vector3(0.01, 0.2, 0.04))
	_lance = animated(Art.pivot(_rider, Vector3(0.14, 0.24, 0.05)))
	limb(_lance, Vector3(0.0, 0.0, 0.35), Vector3(0.0, 0.0, -1.5), 0.022, m_wood())
	Art.part(_lance, Art.cone(0.5), plate, Vector3(0.0, 0.0, -1.58), Vector3(0.05, 0.18, 0.05), Vector3(-PI * 0.5, 0.0, 0.0))
	Art.part(_lance, Art.cone(0.5), plate, Vector3(0.0, 0.0, -0.2), Vector3(0.11, 0.18, 0.11), Vector3(-PI * 0.5, 0.0, 0.0))
	_pennant = animated(Art.pivot(_lance, Vector3(0.0, 0.03, -1.35)))
	Art.part(_pennant, Art.box(), white, Vector3(0.0, 0.07, 0.16), Vector3(0.005, 0.1, 0.3))
	finish()


func pose(_delta: float) -> void:
	horse_pose(windup_w * 0.35, strike_w)
	# Lance carried upright-ish when walking, couched level for the wind-up and the pass.
	var couch := maxf(windup_w, strike_w)
	_lance.rotation.x = lerpf(0.9, 0.0, couch)
	_rider.rotation.x = -couch * 0.25 + sin(walk * 2.0) * 0.03 * move_w
	_pennant.rotation.y = sin(t * 9.0) * 0.3 * (0.4 + strike_w)


## Ragdoll death (characters-polish DeathFx): the pivots that flop loose.
func ragdoll_limbs() -> Array:
	return limbs_with([neck, head, tail, _rider, _lance, _pennant])
