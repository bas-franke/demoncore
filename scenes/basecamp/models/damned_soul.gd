extends ProcModel
## "Damned Soul": a gaunt, ash-grey sinner toiling in Basecamp Hell. Hunched, hollow-eyed, a
## faint soul-light leaking from its chest. `task` picks the labour: 0 hauls a stone block on its
## back, 1 swings a pick (gesture), 2 drags a ball and chain. Driven by HubWanderer (walks between
## jobs) or self-driven as an idle figure; gesture() = one pick swing / a stagger under the load.

## 0 carry stone, 1 pickaxe, 2 ball and chain.
@export var task := 0

var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D


func build() -> void:
	stride = 0.9
	idle_gesture_every = 3.0 if task == 1 else 6.0
	var skin := m_skin(Color(0.48, 0.46, 0.5))
	var dark := m_skin(Color(0.3, 0.29, 0.32))
	var rag := m_cloth(Color(0.18, 0.15, 0.13))
	_torso = biped(0.62, 0.045, skin, dark, 0.08, 0.45)
	# Loincloth of rags, a ribcage-thin chest, hunched forward.
	Art.part(body, Art.cylinder(0.12, 0.16), rag, Vector3(0.0, -0.06, 0.0), Vector3(1.0, 0.18, 0.9))
	Art.part(_torso, Art.capsule(0.11, 0.42), skin, Vector3(0.0, 0.22, 0.0), Vector3(1.0, 1.0, 0.8))
	for k in 3:
		Art.part(_torso, Art.torus(0.85, 1.0), dark, Vector3(0.0, 0.17 + k * 0.06, -0.01),
				Vector3(0.1, 0.06, 0.08), Vector3(PI * 0.5, 0.0, 0.0))
	# The soul-light: a dim cold glow in the chest, the only thing left of them.
	keep(Art.part(_torso, Art.sphere(), Art.glow(Color(0.5, 0.85, 0.8), 1.6), Vector3(0.0, 0.26, -0.08),
			Vector3.ONE * 0.06))
	_head = animated(Art.pivot(_torso, Vector3(0.0, 0.48, -0.04)))
	Art.part(_head, Art.sphere(), skin, Vector3.ZERO, Vector3(0.17, 0.2, 0.18))
	Art.part(_head, Art.sphere(), dark, Vector3(0.0, -0.07, -0.05), Vector3(0.11, 0.07, 0.09))
	for s: float in [-1.0, 1.0]:
		# Hollow, faintly lit eye sockets.
		Art.part(_head, Art.sphere(), Art.mat(Color(0.03, 0.03, 0.04), 1.0), Vector3(s * 0.04, 0.02, -0.075),
				Vector3(0.045, 0.035, 0.03))
		Art.part(_head, Art.sphere(), Art.glow(Color(0.5, 0.85, 0.8), 1.2), Vector3(s * 0.04, 0.02, -0.088),
				Vector3.ONE * 0.012)
	var a := arm(_torso, Vector3(-0.13, 0.4, 0.0), 0.42, 0.03, skin, dark, PI, 0.3)
	_arm_l = a[0]
	var b := arm(_torso, Vector3(0.13, 0.4, 0.0), 0.42, 0.03, skin, dark, 0.0, 0.3)
	_arm_r = b[0]
	match task:
		0:
			# A cut stone block strapped to the back.
			var stone := m_stone(Color(0.22, 0.18, 0.17))
			Art.part(_torso, Art.box(), stone, Vector3(0.0, 0.4, 0.17), Vector3(0.34, 0.26, 0.24), Vector3(0.2, 0.1, 0.0))
			Art.part(_torso, Art.box(), m_leather(), Vector3(0.0, 0.34, 0.03), Vector3(0.26, 0.03, 0.22))
		1:
			# Pickaxe in the right hand (iron head, splintered haft).
			var hand: Node3D = b[1]
			Art.part(hand, Art.cylinder(0.018, 0.018), m_wood(), Vector3(0.0, 0.0, -0.22), Vector3(1.0, 0.55, 1.0),
					Vector3(PI * 0.5, 0.0, 0.0))
			Art.part(hand, Art.box(), m_metal(Color(0.25, 0.24, 0.24), 0.5), Vector3(0.0, 0.0, -0.48),
					Vector3(0.4, 0.05, 0.05))
		2:
			# Iron shackle on the left ankle with a chain trailing to a ball (left on the floor).
			var iron := m_metal(Color(0.14, 0.13, 0.13), 0.5)
			Art.part(self, Art.sphere(), iron, Vector3(-0.25, 0.12, 0.45), Vector3.ONE * 0.24)
			for k in 4:
				Art.part(self, Art.torus(0.7, 1.0), iron, Vector3(-0.12 - k * 0.035, 0.04, 0.08 + k * 0.09),
						Vector3(0.05, 0.05, 0.05), Vector3(PI * 0.5 * (k % 2), 0.0, 0.0))
	finish()


func bake_variant() -> String:
	return str(task)


func pose(_delta: float) -> void:
	biped_bob(0.62, 0.05)
	# Bent under the load, heavier when carrying.
	var hunch := 0.35 + (0.2 if task == 0 else 0.0)
	_torso.rotation.x = -hunch - 0.08 * move_w + sin(t * 1.1) * 0.03
	_head.rotation.x = 0.25 + sin(t * 0.7) * 0.05
	match task:
		0:
			# Both hands gripping the straps at the chest; a stagger on gestures.
			_arm_l.rotation = deg(55.0, 0.0, -25.0)
			_arm_r.rotation = deg(55.0, 0.0, 25.0)
			_torso.rotation.z = sin(t * 9.0) * 0.08 * gesture_w
		1:
			# Pick swing: raise high, bite down (gesture), idle with it resting.
			var swing := sin(clampf(gesture_w, 0.0, 1.0) * PI)
			_arm_r.rotation = mixv(deg(20.0, 0.0, 10.0), deg(200.0, 0.0, 5.0), swing)
			_arm_l.rotation = mixv(deg(15.0, 0.0, -10.0), deg(170.0, 0.0, 20.0), swing)
			_torso.rotation.x -= swing * 0.3
		_:
			_arm_l.rotation.z = -0.15
			_arm_r.rotation.z = 0.15
