extends DemonKit
## "Imp": a knee-high red devil with a big head, long ears, stubby horns, a toothy grin, a
## barbed tail and little bat wings that let it hop-hover. Allies: a skittering swarm minion
## that claws (attack_kick) and throws fire. Basecamp: `outfit` 1 = porter (a sack over the
## shoulder), 2 = courier (satchel of letters and a feathered cap: Pip, see npcs/pip.tscn).

## 0 none, 1 porter sack, 2 courier satchel + cap.
@export var outfit := 0

var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D


func build() -> void:
	stride = 0.7
	idle_gesture_every = 4.0
	var skin := m_skin(Color(0.52, 0.1, 0.07))
	var dark := m_skin(Color(0.3, 0.06, 0.05))
	var horn := Art.mat(Color(0.2, 0.15, 0.12), 0.5, 0.0, 0.3, true, 0.0, &"bone")
	body = animated(Art.pivot(self, Vector3(0.0, 0.25, 0.0)))
	for s: float in [-1.0, 1.0]:
		# Digitigrade little legs.
		var hip := Art.pivot(body, Vector3(s * 0.06, 0.0, 0.0))
		limb(hip, Vector3.ZERO, Vector3(0.0, -0.12, -0.04), 0.03, skin)
		limb(hip, Vector3(0.0, -0.12, -0.04), Vector3(0.0, -0.23, 0.02), 0.022, dark)
		Art.part(hip, Art.cone(0.5), horn, Vector3(0.0, -0.24, -0.03), Vector3(0.05, 0.06, 0.08), Vector3(-PI * 0.5, 0.0, 0.0))
		add_leg(hip, 0.0 if s < 0.0 else PI, 0.7, 0.24)
	# Pot belly and narrow chest.
	Art.part(body, Art.sphere(), skin, Vector3(0.0, 0.06, 0.0), Vector3(0.2, 0.22, 0.18))
	Art.part(body, Art.sphere(), skin, Vector3(0.0, 0.16, 0.0), Vector3(0.17, 0.14, 0.14))
	_head = animated(Art.pivot(body, Vector3(0.0, 0.32, -0.02)))
	Art.part(_head, Art.sphere(), skin, Vector3.ZERO, Vector3(0.24, 0.2, 0.21))
	# Long pointed ears, snout, grin.
	for s: float in [-1.0, 1.0]:
		Art.part(_head, Art.cone(0.5), skin, Vector3(s * 0.14, 0.03, 0.02), Vector3(0.05, 0.16, 0.04), Vector3(0.0, 0.0, -s * 1.2))
	Art.part(_head, Art.sphere(), skin, Vector3(0.0, -0.03, -0.09), Vector3(0.1, 0.07, 0.08))
	Art.part(_head, Art.box(), Art.mat(Art.IVORY, 0.4), Vector3(0.0, -0.05, -0.115), Vector3(0.1, 0.018, 0.02))
	ember_eyes(_head, Vector3(0.05, 0.03, -0.095), 0.045, Color(1.0, 0.8, 0.2))
	horns(_head, Vector3(0.05, 0.08, -0.01), 0.08, 0.022, horn, 0.5, 0.3)
	bat_wing_pair(body, Vector3(0.0, 0.17, 0.07), 0.32, dark, Art.mat(Color(0.35, 0.07, 0.06), 0.8, 0.0, 0.3, true, 0.0, &"leather"))
	tail(body, Vector3(0.0, 0.0, 0.08), 0.28, 0.015, dark, horn)
	var a := arm(body, Vector3(-0.1, 0.17, 0.0), 0.16, 0.022, skin, dark, 0.0, 0.0)
	_arm_l = a[0]
	var b := arm(body, Vector3(0.1, 0.17, 0.0), 0.16, 0.022, skin, dark, 0.0, 0.0)
	_arm_r = b[0]
	if outfit == 2:
		# Courier: a satchel stuffed with sealed letters on a cross strap, and a feathered cap.
		var leather := m_leather(Color(0.35, 0.22, 0.12))
		Art.part(body, Art.box(), leather, Vector3(-0.11, 0.04, 0.02), Vector3(0.07, 0.12, 0.14))
		for k in 3:
			Art.part(body, Art.box(), Art.mat(Art.IVORY, 0.8, 0.0, 0.3, true, 0.0, &"parchment"), Vector3(-0.11, 0.11, -0.03 + k * 0.03), Vector3(0.05, 0.05, 0.012), Vector3(0.0, 0.0, 0.2 * k))
		Art.part(body, Art.sphere(), Art.mat(Art.CRIMSON, 0.4), Vector3(-0.15, 0.06, -0.02), Vector3.ONE * 0.025)
		Art.part(body, Art.torus(0.9, 1.0), leather, Vector3(0.0, 0.13, 0.0), Vector3(0.13, 0.2, 0.11), Vector3(0.0, 0.0, -0.7))
		Art.part(_head, Art.cylinder(0.45, 0.5), m_cloth(Color(0.2, 0.18, 0.3)), Vector3(0.0, 0.1, 0.0), Vector3(0.16, 0.06, 0.15))
		Art.part(_head, Art.cone(0.5), m_cloth(Color(0.85, 0.5, 0.2)), Vector3(0.06, 0.16, 0.04), Vector3(0.025, 0.16, 0.03), Vector3(0.6, 0.0, -0.5))
	if outfit == 1:
		# A lumpy sack slung over the right shoulder.
		Art.part(body, Art.sphere(), m_cloth(Color(0.45, 0.38, 0.26)), Vector3(0.1, 0.27, 0.08), Vector3(0.18, 0.2, 0.16))
		limb(body, Vector3(0.1, 0.27, 0.08), Vector3(0.06, 0.32, -0.03), 0.01, Art.mat(Color(0.5, 0.42, 0.28), 0.9, 0.0, 0.3, true, 0.0, &"rope"))
	finish()


func bake_variant() -> String:
	return str(outfit)


func pose(_delta: float) -> void:
	# Skittering hop with a quick wing flutter.
	body.position.y = 0.25 + absf(sin(walk)) * 0.06 * move_w + sin(t * 3.0) * 0.01 + gesture_w * absf(sin(t * 12.0)) * 0.06
	body.rotation.x = -0.2 * move_w - attack_kick * 0.3
	_head.rotation = Vector3(sin(t * 1.3) * 0.12, sin(t * 0.8) * 0.4 * (1.0 - move_w), sin(t * 2.1) * 0.08)
	flap(14.0 if move_w > 0.3 or gesture_w > 0.0 else 3.0, 0.6 if move_w > 0.3 else 0.15, 0.3 * (1.0 - move_w))
	sway_tail(0.35, 3.0)
	# Claws up and raking on attacks; waving on gestures; sack held when a porter.
	var claw := attack_kick
	_arm_l.rotation = Vector3(0.4 + claw * 1.6 + sin(walk) * 0.4 * move_w, 0.0, -0.3 - gesture_w * 1.2 * absf(sin(t * 8.0)))
	if outfit == 1:
		_arm_r.rotation = Vector3(2.6, 0.0, 0.3)
	else:
		_arm_r.rotation = Vector3(0.4 + claw * 1.9 - sin(walk) * 0.4 * move_w, 0.0, 0.3)
