class_name HolyHorse
extends ProcModel
## Shared horse body for the Unicorn and the Pegasus: a slender white horse (barrel, chest,
## arched neck, long head), four legs with gold-shod hooves, a flowing mane and tail of light-
## tinted silk. Subclasses call build_horse() then add their horn / wings, and pose with
## horse_pose(). The neck, head and tail are animated pivots.

const SHOULDER := 0.62

var neck: Node3D
var head: Node3D
var tail: Node3D
var front_legs: Array[Node3D] = []
var back_legs: Array[Node3D] = []
var coat: Material
var mane_mat: Material


func build_horse(coat_color: Color, mane_color: Color) -> void:
	feather_count = 0
	stride = 1.8
	coat = Art.mat(coat_color, 0.6, 0.0, 0.15, true, 0.3, &"skin")
	mane_mat = Art.mat(mane_color, 0.5, 0.0, 0.1, true, 0.5, &"cloth")
	var hoof := m_gold()
	body = animated(Art.pivot(self, Vector3(0.0, SHOULDER, 0.0)))
	Art.part(body, Art.sphere(), coat, Vector3(0.0, 0.03, -0.2), Vector3(0.3, 0.34, 0.42))
	Art.part(body, Art.sphere(), coat, Vector3(0.0, 0.04, 0.2), Vector3(0.3, 0.32, 0.44))
	Art.part(body, Art.cylinder(0.5, 0.5), coat, Vector3(0.0, 0.03, 0.0), Vector3(0.27, 0.42, 0.3), Vector3(PI * 0.5, 0.0, 0.0))
	for s: float in [-1.0, 1.0]:
		front_legs.append(beast_leg(body, Vector3(s * 0.09, -0.06, -0.27), SHOULDER - 0.06, 0.04, coat, hoof, 0.0 if s < 0.0 else PI, 0.65))
		back_legs.append(beast_leg(body, Vector3(s * 0.09, -0.05, 0.3), SHOULDER - 0.05, 0.045, coat, hoof, PI if s < 0.0 else 0.0, 0.65, true))
	# Neck rises forward from the chest; head at its top, angled down.
	neck = animated(Art.pivot(body, Vector3(0.0, 0.12, -0.36), Vector3(-0.55, 0.0, 0.0)))
	limb(neck, Vector3.ZERO, Vector3(0.0, 0.36, 0.0), 0.085, coat)
	# Mane along the back of the neck.
	for i in 6:
		var f := float(i) / 5.0
		Art.part(neck, Art.sphere(), mane_mat, Vector3(0.0, 0.05 + f * 0.32, 0.07), Vector3(0.05, 0.1, 0.1))
	head = animated(Art.pivot(neck, Vector3(0.0, 0.38, 0.0), Vector3(0.25, 0.0, 0.0)))
	Art.part(head, Art.sphere(), coat, Vector3(0.0, 0.0, 0.0), Vector3(0.13, 0.15, 0.17))
	Art.part(head, Art.cylinder(0.055, 0.075), coat, Vector3(0.0, 0.0, -0.13), Vector3(1.0, 0.24, 0.9), Vector3(-PI * 0.5, 0.0, 0.0))
	Art.part(head, Art.sphere(), m_skin(coat_color.darkened(0.25)), Vector3(0.0, -0.01, -0.25), Vector3(0.1, 0.09, 0.08))
	for s: float in [-1.0, 1.0]:
		Art.part(head, Art.cone(0.5), coat, Vector3(s * 0.04, 0.1, 0.03), Vector3(0.035, 0.08, 0.03), Vector3(0.0, 0.0, -s * 0.2))
		eye(head, Vector3(s * 0.06, 0.02, -0.05), 0.026, Vector3(s, 0.0, -0.6), false, Art.HOLY)
	Art.part(head, Art.sphere(), mane_mat, Vector3(0.0, 0.09, -0.06), Vector3(0.05, 0.05, 0.1))
	# Tail of silk.
	tail = animated(Art.pivot(body, Vector3(0.0, 0.13, 0.42)))
	for i in 4:
		var f := float(i) / 3.0
		Art.part(tail, Art.sphere(), mane_mat, Vector3(0.0, -0.06 - f * 0.18, 0.08 + f * 0.04), Vector3(0.08 - f * 0.01, 0.16, 0.08))


## Gallop pose: body pitch, neck / head nod, tail stream. `rear` 0..1 rears onto the hind legs
## (wind-up), `rush` 0..1 flattens into a charge with the head down.
func horse_pose(rear: float, rush: float) -> void:
	var gallop := move_w + rush
	body.position.y = SHOULDER + absf(sin(walk)) * 0.05 * gallop + rear * 0.16
	body.rotation.x = sin(walk * 2.0) * 0.04 * gallop + rear * 0.7 - rush * 0.08
	for l in front_legs:
		l.rotation.x += rear * 1.1 + sin(t * 9.0) * rear * 0.3
	for l in back_legs:
		l.rotation.x -= rear * 0.6
	neck.rotation.x = -0.55 - sin(walk * 2.0) * 0.12 * gallop - rear * 0.2 - rush * 0.55
	head.rotation.x = 0.25 - rush * 0.35
	tail.rotation.x = 0.3 * gallop + 0.25 + sin(t * 3.0) * 0.08
	tail.rotation.y = sin(t * 1.7) * 0.25


## Ragdoll death (characters-polish DeathFx): the pivots that flop loose.
func ragdoll_limbs() -> Array:
	return limbs_with([neck, head, tail])
