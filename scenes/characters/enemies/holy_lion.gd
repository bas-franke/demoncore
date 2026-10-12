extends ProcModel
## "Lion of Judah" (HOP): a great white-gold lion with a blazing mane of light-tipped locks, a
## small halo, a gold collar and a heavy brow. It stalks with a low prowl, crouches with its
## haunches quivering (wind-up), then pounces in a high arc (the arc height is added here from
## state_progress; the Enemy moves it along the ground) and lands in a squash.

const SHOULDER := 0.5
const LEAP_HEIGHT := 1.1

var _head: Node3D
var _jaw: Node3D
var _tail: Node3D
var _front: Array[Node3D] = []
var _back: Array[Node3D] = []


func build() -> void:
	feather_count = 0
	mote_count = 8
	stride = 1.6
	var fur := m_fur(Color(0.86, 0.76, 0.55))
	var mane := m_fur(Color(0.9, 0.68, 0.32))
	var claw := Art.mat(Art.IVORY, 0.5)
	body = animated(Art.pivot(self, Vector3(0.0, SHOULDER, 0.0)))
	# Barrel: chest forward (-Z), narrower loins behind.
	Art.part(body, Art.sphere(), fur, Vector3(0.0, 0.02, -0.22), Vector3(0.36, 0.38, 0.42))
	Art.part(body, Art.sphere(), fur, Vector3(0.0, 0.0, 0.2), Vector3(0.3, 0.32, 0.46))
	Art.part(body, Art.cylinder(0.5, 0.5), m_gold(), Vector3(0.0, 0.12, -0.38), Vector3(0.3, 0.05, 0.28), Vector3(0.5, 0.0, 0.0))
	for s: float in [-1.0, 1.0]:
		_front.append(beast_leg(body, Vector3(s * 0.11, -0.04, -0.28), SHOULDER - 0.04, 0.05, fur, claw, 0.0 if s < 0.0 else PI, 0.6))
		_back.append(beast_leg(body, Vector3(s * 0.11, -0.02, 0.3), SHOULDER - 0.02, 0.055, fur, claw, PI if s < 0.0 else 0.0, 0.6, true))
	_head = animated(Art.pivot(body, Vector3(0.0, 0.14, -0.46)))
	# Mane: a ruff of locks around the head, tipped with light.
	for i in 14:
		var a := TAU * float(i) / 14.0
		var d := Vector3(cos(a), sin(a), 0.0)
		Art.part(_head, Art.sphere(), mane, d * 0.15 + Vector3(0.0, 0.0, 0.06), Vector3(0.14, 0.14, 0.22))
		if i % 2 == 0:
			Art.part(_head, Art.sphere(), Art.glow(Art.HOLY, 1.2), d * 0.24 + Vector3(0.0, 0.0, 0.08), Vector3.ONE * 0.05)
	Art.part(_head, Art.sphere(), mane, Vector3(0.0, 0.0, 0.1), Vector3(0.38, 0.38, 0.22))
	Art.part(_head, Art.sphere(), fur, Vector3(0.0, 0.0, -0.04), Vector3(0.24, 0.22, 0.24))
	# Muzzle, nose, brow, ears.
	Art.part(_head, Art.sphere(), fur, Vector3(0.0, -0.04, -0.15), Vector3(0.14, 0.11, 0.14))
	Art.part(_head, Art.sphere(), Art.mat(Color(0.25, 0.15, 0.13), 0.5), Vector3(0.0, -0.01, -0.22), Vector3(0.05, 0.035, 0.03))
	Art.part(_head, Art.box(), fur, Vector3(0.0, 0.05, -0.1), Vector3(0.18, 0.04, 0.06))
	for s: float in [-1.0, 1.0]:
		Art.part(_head, Art.sphere(), fur, Vector3(s * 0.09, 0.12, 0.0), Vector3(0.05, 0.06, 0.03))
		eye(_head, Vector3(s * 0.055, 0.025, -0.13), 0.035, Vector3(s * 0.2, 0.0, -1.0), false, Art.HOLY)
	_jaw = animated(Art.pivot(_head, Vector3(0.0, -0.07, -0.08)))
	Art.part(_jaw, Art.sphere(), fur, Vector3(0.0, -0.01, -0.06), Vector3(0.11, 0.05, 0.12))
	for s: float in [-1.0, 1.0]:
		Art.part(_jaw, Art.cone(0.5), claw, Vector3(s * 0.035, 0.03, -0.1), Vector3(0.018, 0.04, 0.018))
	halo(_head, Vector3(0.0, 0.25, 0.08), 0.12, 2.6)
	# Tail with a tuft (animated sway).
	_tail = animated(Art.pivot(body, Vector3(0.0, 0.08, 0.42)))
	limb(_tail, Vector3.ZERO, Vector3(0.0, -0.1, 0.35), 0.022, fur)
	Art.part(_tail, Art.sphere(), mane, Vector3(0.0, -0.11, 0.38), Vector3(0.08, 0.08, 0.12))
	finish()


func pose(_delta: float) -> void:
	var crouch := windup_w
	var air := strike_w
	var lift := 0.0
	if air > 0.05 and state_progress > 0.0:
		lift = sin(clampf(state_progress, 0.0, 1.0) * PI) * LEAP_HEIGHT * air
	var squash := land_kick
	body.position.y = SHOULDER + absf(sin(walk)) * 0.03 * move_w - crouch * 0.16 - squash * 0.12 + lift
	# Crouch with the haunches high and quivering; stretch out in the air.
	body.rotation.x = crouch * 0.12 + sin(t * 40.0) * 0.01 * crouch - air * 0.2 + squash * 0.1
	for l in _front:
		l.rotation.x = mixv(Vector3(l.rotation.x, 0, 0), Vector3(1.1, 0, 0), air).x - crouch * 0.4
	for l in _back:
		l.rotation.x = mixv(Vector3(l.rotation.x, 0, 0), Vector3(-0.9, 0, 0), air).x + crouch * 0.5
	_head.rotation.x = -0.1 * move_w + crouch * 0.25 - air * 0.15
	_head.rotation.y = sin(t * 0.7) * 0.15 * (1.0 - crouch)
	# Roar: jaw drops in the wind-up and the leap.
	_jaw.rotation.x = 0.5 * maxf(crouch, air) + 0.06 * sin(t * 3.0)
	_tail.rotation = Vector3(0.3 + crouch * 0.6 + sin(t * 2.0) * 0.1, sin(t * 1.6) * 0.5, 0.0)


## Ragdoll death (characters-polish DeathFx): the pivots that flop loose.
func ragdoll_limbs() -> Array:
	return limbs_with([_head, _jaw, _tail])
