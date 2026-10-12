extends ProcModel
## "Gryphon Rider" (HOP: dive-bomb): a knight of the sky-cavalry riding a griffon - eagle head,
## white-feathered breast and wings, tawny lion haunches - the rider in light silver armour with a
## blue-and-gold tabard, a winged helm and a short lance. It flies low; HOP: the griffon climbs
## with its wings flared (wind-up), arcs up and dives lance-first onto the marked circle.

const HEIGHT := 0.75
const LEAP := 2.0

var _head: Node3D
var _rider: Node3D
var _lance: Node3D
var _fore: Array[Node3D] = []
var _hind: Array[Node3D] = []


func build() -> void:
	feather_count = 6
	wing_speed = 4.5
	wing_amp = 0.5
	wing_sweep = 0.2
	stride = 1.6
	var feathers := Art.mat(Color(0.95, 0.93, 0.88), 0.75, 0.0, 0.15, true, 0.3, &"feather")
	var fur := m_fur(Color(0.72, 0.56, 0.34))
	var silver := m_metal(Color(0.82, 0.83, 0.86), 0.3)
	var blue := m_cloth(Color(0.18, 0.26, 0.55))
	body = animated(Art.pivot(self, Vector3(0.0, HEIGHT, 0.0)))
	Art.part(body, Art.sphere(), feathers, Vector3(0.0, 0.03, -0.2), Vector3(0.32, 0.36, 0.4))
	Art.part(body, Art.sphere(), fur, Vector3(0.0, 0.0, 0.18), Vector3(0.3, 0.3, 0.46))
	var talon := Art.mat(Art.GOLD.darkened(0.2), 0.4, 0.6)
	for s: float in [-1.0, 1.0]:
		_fore.append(beast_leg(body, Vector3(s * 0.09, -0.08, -0.22), 0.4, 0.035, m_skin(Color(0.85, 0.7, 0.35)), talon, 0.0 if s < 0.0 else PI, 0.4))
		_hind.append(beast_leg(body, Vector3(s * 0.1, -0.04, 0.3), 0.42, 0.05, fur, fur, PI if s < 0.0 else 0.0, 0.4, true))
	_head = animated(Art.pivot(body, Vector3(0.0, 0.2, -0.4)))
	Art.part(_head, Art.sphere(), feathers, Vector3.ZERO, Vector3(0.18, 0.2, 0.22))
	Art.part(_head, Art.cone(0.5), m_gold(), Vector3(0.0, -0.01, -0.15), Vector3(0.08, 0.16, 0.09), Vector3(-PI * 0.5 - 0.35, 0.0, 0.0))
	for s: float in [-1.0, 1.0]:
		eye(_head, Vector3(s * 0.06, 0.03, -0.07), 0.03, Vector3(s * 0.6, 0.0, -1.0), false, Color(1.0, 0.8, 0.3))
	solid_wing_pair(body, Vector3(0.0, 0.16, -0.05), 0.9, feathers, feathers, Art.mat(Color(0.3, 0.38, 0.6), 0.6, 0.0, 0.2, true, 0.0, &"feather"), 0.16)
	# Saddle and rider.
	Art.part(body, Art.box(), blue, Vector3(0.0, 0.16, 0.02), Vector3(0.3, 0.05, 0.32))
	_rider = animated(Art.pivot(body, Vector3(0.0, 0.2, 0.04)))
	for s: float in [-1.0, 1.0]:
		limb(_rider, Vector3(s * 0.08, 0.02, 0.0), Vector3(s * 0.17, -0.18, -0.08), 0.03, silver)
	Art.part(_rider, Art.cylinder(0.12, 0.1), silver, Vector3(0.0, 0.18, 0.0), Vector3(1.0, 0.32, 0.8))
	Art.part(_rider, Art.box(), blue, Vector3(0.0, 0.14, -0.085), Vector3(0.16, 0.28, 0.02))
	Art.part(_rider, Art.box(), m_gold(), Vector3(0.0, 0.18, -0.097), Vector3(0.04, 0.14, 0.01))
	var helm := Art.pivot(_rider, Vector3(0.0, 0.4, 0.0))
	Art.part(helm, Art.sphere(), silver, Vector3.ZERO, Vector3(0.15, 0.17, 0.16))
	for s: float in [-1.0, 1.0]:
		Art.part(helm, Art.sphere(), feathers, Vector3(s * 0.08, 0.06, 0.03), Vector3(0.03, 0.1, 0.08), Vector3(0.3, 0.0, s * -0.5))
	_lance = animated(Art.pivot(_rider, Vector3(0.12, 0.2, 0.02)))
	limb(_lance, Vector3(0.0, 0.0, 0.3), Vector3(0.0, 0.0, -0.9), 0.016, m_wood())
	Art.part(_lance, Art.cone(0.5), silver, Vector3(0.0, 0.0, -0.98), Vector3(0.04, 0.16, 0.04), Vector3(-PI * 0.5, 0.0, 0.0))
	finish()


func pose(_delta: float) -> void:
	var climb := windup_w
	var dive := strike_w
	var lift := 0.0
	if dive > 0.05:
		lift = sin(clampf(state_progress, 0.0, 1.0) * PI) * LEAP * dive
	body.position.y = HEIGHT + sin(t * wing_speed) * 0.05 + climb * 0.3 + lift - land_kick * 0.15
	# Dive: nose down over the second half of the arc.
	var nose := clampf(state_progress * 2.0 - 0.8, 0.0, 1.0) * dive
	body.rotation.x = -0.12 * move_w + climb * 0.35 - nose * 0.7
	wing_lift = 0.15 + climb * 0.7 - nose * 0.5
	wing_sweep = 0.2 + nose * 0.9
	wing_amp = 0.5 * (1.0 - nose)
	for l in _fore:
		l.rotation.x = 0.4 + climb * 0.5 + nose * 0.8
	for l in _hind:
		l.rotation.x = -0.7
	_lance.rotation.x = lerpf(0.6, 0.0, maxf(climb, dive)) - nose * 0.3
	_rider.rotation.x = -nose * 0.3 + climb * 0.1
	_head.rotation.x = 0.1 - climb * 0.3 + nose * 0.4


## Ragdoll death (characters-polish DeathFx): the pivots that flop loose.
func ragdoll_limbs() -> Array:
	return limbs_with([_head, _rider, _lance])
