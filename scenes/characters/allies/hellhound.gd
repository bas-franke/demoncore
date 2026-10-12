extends DemonKit
## "Hellhound": a gaunt black hound of the Pit, ribs showing through cracks of ember light, a
## heavy skull-like head with a molten maw, bone spines down the back and a smoking whip tail.
## Allies: a fast hunter that lunges (wind-up crouch, strike leap). Basecamp: lies by a fire,
## panting, and lifts its head on gestures (`resting = true`).

const SHOULDER := 0.42

## Basecamp variant: lies down, head on paws.
@export var resting := false

var _head: Node3D
var _jaw: Node3D
var _maw: MeshInstance3D
var _front: Array[Node3D] = []
var _back: Array[Node3D] = []


func build() -> void:
	stride = 1.5
	idle_gesture_every = 6.0
	var pelt := Art.mat(Color(0.06, 0.05, 0.05), 0.7, 0.0, 0.4, true, 0.1, &"leather")
	var bone := Art.mat(Art.BONE.darkened(0.2), 0.6, 0.0, 0.4, true, 0.0, &"bone")
	var crack := Art.glow(Art.EMBER, 2.0)
	body = animated(Art.pivot(self, Vector3(0.0, SHOULDER, 0.0)))
	# Deep chest, tucked waist, haunches.
	Art.part(body, Art.sphere(), pelt, Vector3(0.0, 0.02, -0.16), Vector3(0.26, 0.3, 0.34))
	Art.part(body, Art.sphere(), pelt, Vector3(0.0, 0.03, 0.18), Vector3(0.22, 0.24, 0.3))
	limb(body, Vector3(0.0, 0.0, -0.08), Vector3(0.0, 0.02, 0.12), 0.08, pelt)
	# Ember cracks along the ribs and bone spines along the back.
	for s: float in [-1.0, 1.0]:
		for k in 3:
			Art.part(body, Art.box(), crack, Vector3(s * 0.128, -0.02 + k * 0.05, -0.12 + k * 0.03), Vector3(0.01, 0.015, 0.12), Vector3(0.4, 0.0, 0.0))
	for k in 5:
		Art.part(body, Art.cone(0.5), bone, Vector3(0.0, 0.15 - absf(k - 1.5) * 0.01, -0.22 + k * 0.1), Vector3(0.04, 0.12 - k * 0.012, 0.05), Vector3(0.5, 0.0, 0.0))
	for s: float in [-1.0, 1.0]:
		_front.append(beast_leg(body, Vector3(s * 0.08, -0.04, -0.22), SHOULDER - 0.04, 0.035, pelt, bone, 0.0 if s < 0.0 else PI, 0.7))
		_back.append(beast_leg(body, Vector3(s * 0.08, -0.02, 0.24), SHOULDER - 0.02, 0.04, pelt, bone, PI if s < 0.0 else 0.0, 0.7, true))
	_head = animated(Art.pivot(body, Vector3(0.0, 0.1, -0.36)))
	# Skull-faced head: a bony brow plate and long muzzle, molten maw in the jaw.
	Art.part(_head, Art.sphere(), pelt, Vector3.ZERO, Vector3(0.18, 0.17, 0.2))
	Art.part(_head, Art.cylinder(0.05, 0.07), bone, Vector3(0.0, 0.0, -0.13), Vector3(1.0, 0.18, 0.9), Vector3(-PI * 0.5, 0.0, 0.0))
	Art.part(_head, Art.box(), bone, Vector3(0.0, 0.07, -0.04), Vector3(0.16, 0.04, 0.12))
	for s: float in [-1.0, 1.0]:
		Art.part(_head, Art.cone(0.5), bone, Vector3(s * 0.07, 0.1, 0.04), Vector3(0.04, 0.12, 0.04), Vector3(-0.6, 0.0, -s * 0.3))
	ember_eyes(_head, Vector3(0.05, 0.04, -0.09), 0.04)
	_jaw = animated(Art.pivot(_head, Vector3(0.0, -0.05, -0.05)))
	Art.part(_jaw, Art.box(), bone, Vector3(0.0, -0.01, -0.09), Vector3(0.09, 0.03, 0.16))
	_maw = keep(Art.part(_jaw, Art.sphere(), Art.glow(Art.HELLFIRE, 1.8), Vector3(0.0, 0.015, -0.08), Vector3(0.07, 0.03, 0.12)))
	tail(body, Vector3(0.0, 0.08, 0.36), 0.38, 0.016, pelt, crack)
	finish()


func bake_variant() -> String:
	return "r" if resting else ""


func pose(_delta: float) -> void:
	var crouch := windup_w
	var leap := strike_w
	if resting:
		# Lying down: legs folded flat, head low, slow panting; lifts its head on a gesture.
		body.position.y = 0.18 + sin(t * 4.0) * 0.008
		for l in _front:
			l.rotation.x = 1.45
		for l in _back:
			l.rotation.x = -1.45
		_head.rotation.x = -0.15 + gesture_w * 0.5
		_head.rotation.y = gesture_w * sin(t * 1.5) * 0.4
		_jaw.rotation.x = 0.2 + sin(t * 4.0) * 0.08
		sway_tail(0.15, 1.0)
		return
	body.position.y = SHOULDER + absf(sin(walk)) * 0.04 * move_w - crouch * 0.1 + sin(clampf(state_progress, 0.0, 1.0) * PI) * 0.4 * leap
	body.rotation.x = -crouch * 0.1 - leap * 0.15
	for l in _front:
		l.rotation.x += leap * 0.9 - crouch * 0.3
	for l in _back:
		l.rotation.x += -leap * 0.8 + crouch * 0.4
	_head.rotation.x = -0.1 * move_w + crouch * 0.2
	_jaw.rotation.x = maxf(crouch, leap) * 0.6 + attack_kick * 0.5 + 0.1 + sin(t * 5.0) * 0.05 * move_w
	_maw.scale = Vector3(0.07, 0.03, 0.12) * (1.0 + crouch * 0.8 + 0.15 * sin(t * 9.0))
	sway_tail(0.3 + move_w * 0.2, 2.5 + move_w * 3.0)


## Ragdoll death (characters-polish DeathFx): the pivots that flop loose.
func ragdoll_limbs() -> Array:
	return limbs_with([_head, _jaw] + _tail_segments)
