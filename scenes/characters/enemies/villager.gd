extends ProcModel
## "Torch-bearing Villager" / "Pitchfork Villager" (CHASE, weak, numerous): an angry mortal of
## the parish in a homespun tunic, apron or vest, a felt cap or a headscarf. `tool` picks what it
## carries: 0 = a burning torch held high (with a flickering flame and a small light on elites),
## 1 = a pitchfork levelled at you. The scene files set it (villager_torch / villager_pitchfork).
## Jab / torch-thrust is cosmetic (proximity_attack).

const HIP := 0.42

## 0 torch, 1 pitchfork.
@export var tool := 0
## Palette variant (0..2): tunic / cap colours.
@export var variant := 0

var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _flame: Node3D

const TUNICS := [Color(0.42, 0.36, 0.26), Color(0.3, 0.33, 0.25), Color(0.45, 0.28, 0.22)]
const CAPS := [Color(0.5, 0.15, 0.12), Color(0.24, 0.2, 0.16), Color(0.62, 0.58, 0.48)]


func build() -> void:
	feather_count = 0
	mote_count = 2
	light_color = Color(1.0, 0.75, 0.45)
	stride = 1.0
	proximity_range = 1.3 if tool == 1 else 1.1
	proximity_cooldown = 1.5
	var v := clampi(variant, 0, 2)
	var tunic := m_cloth(TUNICS[v])
	var skin := m_skin(Color(0.84, 0.66, 0.54) if v != 1 else Color(0.6, 0.45, 0.35))
	var trousers := m_cloth(Color(0.22, 0.2, 0.18))
	_torso = biped(HIP, 0.04, trousers, m_leather(Color(0.2, 0.13, 0.08)), 0.075, 0.6)
	Art.part(body, Art.cylinder(0.15, 0.19), tunic, Vector3(0.0, -0.06, 0.0), Vector3(1.0, 0.2, 0.85))
	# Stocky peasant torso, a rough apron or vest and a rope belt.
	Art.part(_torso, Art.cylinder(0.16, 0.17), tunic, Vector3(0.0, 0.17, 0.0), Vector3(1.0, 0.36, 0.85))
	if tool == 0:
		Art.part(_torso, Art.box(), m_cloth(Color(0.7, 0.66, 0.56)), Vector3(0.0, 0.06, -0.135), Vector3(0.22, 0.34, 0.02))
	else:
		Art.part(_torso, Art.cylinder(0.17, 0.175), m_leather(Color(0.3, 0.2, 0.12)), Vector3(0.0, 0.22, 0.0), Vector3(1.03, 0.24, 0.88))
	Art.part(_torso, Art.cylinder(0.5, 0.5), Art.mat(Color(0.55, 0.47, 0.3), 0.95, 0.0, 0.3, true, 0.0, &"rope"), Vector3(0.0, 0.02, 0.0), Vector3(0.33, 0.03, 0.28))
	_head = animated(Art.pivot(_torso, Vector3(0.0, 0.44, 0.0)))
	Art.part(_head, Art.sphere(), skin, Vector3.ZERO, Vector3(0.18, 0.2, 0.18))
	Art.part(_head, Art.sphere(), skin, Vector3(0.0, -0.01, -0.09), Vector3(0.045, 0.05, 0.05))
	# Furious brows and eyes.
	for s: float in [-1.0, 1.0]:
		Art.part(_head, Art.sphere(), Art.mat(Art.OBSIDIAN, 0.4), Vector3(s * 0.04, 0.02, -0.083), Vector3(0.025, 0.02, 0.012))
		Art.part(_head, Art.box(), Art.mat(Color(0.2, 0.14, 0.1), 0.9), Vector3(s * 0.04, 0.045, -0.085), Vector3(0.05, 0.012, 0.012), Vector3(0.0, 0.0, s * 0.4))
	# Shouting mouth.
	Art.part(_head, Art.sphere(), Art.mat(Color(0.25, 0.05, 0.05), 0.6), Vector3(0.0, -0.05, -0.08), Vector3(0.04, 0.03, 0.02))
	if v == 2:
		# Headscarf.
		Art.part(_head, Art.sphere(), m_cloth(CAPS[v]), Vector3(0.0, 0.03, 0.01), Vector3(0.2, 0.18, 0.2))
		Art.part(_head, Art.cone(0.5), m_cloth(CAPS[v]), Vector3(0.0, -0.06, 0.1), Vector3(0.1, 0.12, 0.04), Vector3(PI, 0.0, 0.0))
	else:
		# Felt cap flopping to one side.
		Art.part(_head, Art.cylinder(0.5, 0.5), m_cloth(CAPS[v]), Vector3(0.0, 0.07, 0.0), Vector3(0.19, 0.04, 0.19))
		Art.part(_head, Art.cone(0.5), m_cloth(CAPS[v]), Vector3(0.03, 0.12, 0.02), Vector3(0.17, 0.14, 0.17), Vector3(0.0, 0.0, -0.5))
	var a := arm(_torso, Vector3(-0.19, 0.32, 0.0), 0.34, 0.04, tunic, skin, 0.0, 0.0)
	_arm_l = a[0]
	var b := arm(_torso, Vector3(0.19, 0.32, 0.0), 0.34, 0.04, tunic, skin, 0.0, 0.0)
	_arm_r = b[0]
	if tool == 0:
		# Torch in the right hand, pointing up out of the fist.
		var torch := Art.pivot(b[1], Vector3.ZERO, Vector3(PI, 0.0, 0.0))
		limb(torch, Vector3(0.0, -0.1, 0.0), Vector3(0.0, 0.32, 0.0), 0.018, m_wood())
		Art.part(torch, Art.cylinder(0.5, 0.5), Art.mat(Color(0.25, 0.2, 0.15), 0.95, 0.0, 0.5, true, 0.0, &"rope"), Vector3(0.0, 0.3, 0.0), Vector3(0.06, 0.08, 0.06))
		_flame = animated(Art.pivot(torch, Vector3(0.0, 0.34, 0.0)))
		Art.part(_flame, Art.cone(0.5), Art.glow(Art.EMBER, 2.2), Vector3(0.0, 0.08, 0.0), Vector3(0.09, 0.2, 0.09))
		Art.part(_flame, Art.cone(0.5), Art.glow(Color(1.0, 0.8, 0.4), 2.5), Vector3(0.0, 0.05, 0.0), Vector3(0.05, 0.12, 0.05))
		Art.part(_flame, Art.sphere(), Art.glow(Art.EMBER, 0.35), Vector3(0.0, 0.06, 0.0), Vector3.ONE * 0.22)
	else:
		# Pitchfork held two-handed, tines forward.
		var pf := Art.pivot(b[1], Vector3.ZERO, Vector3(-PI * 0.5, 0.0, 0.0))
		limb(pf, Vector3(0.0, -0.45, 0.0), Vector3(0.0, 0.6, 0.0), 0.016, m_wood())
		var iron := m_metal(Art.STEEL.darkened(0.4), 0.6)
		Art.part(pf, Art.box(), iron, Vector3(0.0, 0.62, 0.0), Vector3(0.16, 0.025, 0.025))
		for x: float in [-0.07, 0.0, 0.07]:
			limb(pf, Vector3(x, 0.62, 0.0), Vector3(x, 0.84, 0.0), 0.008, iron)
	finish()


func bake_variant() -> String:
	return "%d_%d" % [tool, variant]


func proximity_attack() -> void:
	play_attack()


func pose(_delta: float) -> void:
	biped_bob(HIP, 0.04)
	var jab := attack_kick
	_torso.rotation.x = -0.15 * move_w - jab * 0.2
	_torso.rotation.y = sin(walk) * 0.12 * move_w
	_head.rotation.y = sin(t * 1.3) * 0.2
	_head.rotation.x = -0.1 + sin(t * 7.0) * 0.04  # shouting
	if tool == 0:
		# Torch held high, shaken, thrust forward on a jab.
		_arm_r.rotation = mixv(Vector3(2.6 + sin(t * 5.0) * 0.15, 0.0, 0.2), Vector3(1.5, 0.0, 0.1), jab)
		_arm_l.rotation = Vector3(-sin(walk) * 0.5 * move_w, 0.0, -0.15)
		_flame.scale = Vector3(1.0, 1.0 + 0.25 * sin(t * 15.0) + 0.1 * sin(t * 23.0), 1.0)
		_flame.rotation.x = -0.4 * move_w
	else:
		var level := 1.1 + jab * 0.3
		_arm_r.rotation = Vector3(level - sin(walk) * 0.1 * move_w, -0.25, 0.0)
		_arm_l.rotation = Vector3(level + 0.2, 0.45, -0.1)
		_torso.position.z = -jab * 0.08
