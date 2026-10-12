extends ProcModel
## "Dawn Wyrmling" (SHOOT, flies): a young dragon of light. A long, sinuous serpentine body of
## pearl-white scales with gold belly plates, a horned wedge head, a mane of light down its spine,
## two broad solid wings and a tail that ripples in an S-wave as it flies. SHOOT: it rears its
## head back with light gathering in the jaws (wind-up), then breathes a bolt of dawn (holy orb).

const SEGMENTS := 7
const BREATH := Color(1.0, 0.9, 0.6)

var _neck: Node3D
var _head: Node3D
var _jaw: Node3D
var _maw: MeshInstance3D
var _segs: Array[Node3D] = []


func build() -> void:
	feather_count = 0
	mote_count = 10
	light_color = BREATH
	debris = [&"mote", &"gold"]
	debris_color = Art.GOLD
	death_style = &"shrink"
	wing_speed = 4.0
	wing_amp = 0.55
	var scales := Art.mat(Color(0.92, 0.9, 0.84), 0.35, 0.2, 0.1, true, 0.4, &"scales")
	var gold := m_gold()
	body = animated(Art.pivot(self, Vector3(0.0, 0.85, 0.0)))
	Art.part(body, Art.sphere(), scales, Vector3.ZERO, Vector3(0.24, 0.24, 0.42))
	Art.part(body, Art.sphere(), gold, Vector3(0.0, -0.06, 0.0), Vector3(0.18, 0.14, 0.38))
	solid_wing_pair(body, Vector3(0.0, 0.08, -0.05), 0.75, Art.mat(Color(0.95, 0.92, 0.85), 0.5, 0.0, 0.05, true, 0.5), Art.mat(Art.GOLD, 0.4, 0.4, 0.1, true, 0.3), Art.mat(Color(1.0, 0.95, 0.8), 0.4, 0.0, 0.0, true, 0.6), 0.08)
	# Little forelegs tucked under.
	for s: float in [-1.0, 1.0]:
		limb(body, Vector3(s * 0.08, -0.08, -0.12), Vector3(s * 0.09, -0.2, -0.2), 0.02, scales)
	# Tail: a chain of shrinking segments (each one a pivot, rippled in pose()).
	var parent := body
	for i in SEGMENTS:
		var f := float(i) / float(SEGMENTS)
		var seg := animated(Art.pivot(parent, Vector3(0.0, 0.0, 0.16 if i > 0 else 0.2)))
		Art.part(seg, Art.sphere(), scales, Vector3(0.0, 0.0, 0.08), Vector3(0.17, 0.15, 0.22) * (1.0 - f * 0.75))
		Art.part(seg, Art.cone(0.5), Art.glow(BREATH, 1.6), Vector3(0.0, 0.07 * (1.0 - f * 0.7), 0.06), Vector3(0.03, 0.08, 0.03) * (1.0 - f * 0.5))
		_segs.append(seg)
		parent = seg
	Art.part(parent, Art.prism(), gold, Vector3(0.0, 0.0, 0.2), Vector3(0.14, 0.12, 0.02), Vector3(PI * 0.5, 0.0, 0.0))
	# Neck and head forward.
	_neck = animated(Art.pivot(body, Vector3(0.0, 0.06, -0.18), Vector3(-0.4, 0.0, 0.0)))
	limb(_neck, Vector3.ZERO, Vector3(0.0, 0.0, -0.28), 0.07, scales)
	_head = animated(Art.pivot(_neck, Vector3(0.0, 0.0, -0.3)))
	Art.part(_head, Art.sphere(), scales, Vector3(0.0, 0.02, -0.04), Vector3(0.16, 0.12, 0.2))
	Art.part(_head, Art.cylinder(0.04, 0.06), scales, Vector3(0.0, 0.02, -0.16), Vector3(1.0, 0.16, 0.8), Vector3(-PI * 0.5, 0.0, 0.0))
	for s: float in [-1.0, 1.0]:
		Art.part(_head, Art.cone(0.5), gold, Vector3(s * 0.05, 0.08, 0.04), Vector3(0.025, 0.16, 0.025), Vector3(1.0, 0.0, -s * 0.2))
		Art.part(_head, Art.sphere(), Art.glow(Art.HOLY_WHITE, 2.4), Vector3(s * 0.05, 0.05, -0.08), Vector3(0.03, 0.02, 0.025))
	_jaw = animated(Art.pivot(_head, Vector3(0.0, -0.03, -0.04)))
	Art.part(_jaw, Art.box(), scales, Vector3(0.0, -0.01, -0.1), Vector3(0.07, 0.025, 0.14))
	_maw = keep(Art.part(_head, Art.sphere(), Art.glow(BREATH, 2.6), Vector3(0.0, -0.01, -0.18), Vector3.ONE * 0.02))
	finish()


func pose(_delta: float) -> void:
	var breath := windup_w
	body.position.y = 0.85 + sin(t * wing_speed) * 0.06
	body.rotation.x = -0.1 * move_w + breath * 0.2 - attack_kick * 0.15
	body.rotation.z = sin(t * 1.2) * 0.08
	for i in _segs.size():
		_segs[i].rotation.y = sin(t * 4.0 - float(i) * 0.7) * 0.25
		_segs[i].rotation.x = sin(t * 2.0 - float(i) * 0.5) * 0.08
	_neck.rotation.x = -0.4 + breath * 0.5 - attack_kick * 0.6
	_head.rotation.x = -breath * 0.4 + attack_kick * 0.4
	_jaw.rotation.x = 0.1 + breath * 0.3 + attack_kick * 0.5
	_maw.scale = Vector3.ONE * (0.02 + breath * 0.12 + attack_kick * 0.08)
	wing_amp = 0.55 - breath * 0.3


## Ragdoll death (characters-polish DeathFx): the pivots that flop loose.
func ragdoll_limbs() -> Array:
	return limbs_with([_neck, _head, _jaw] + _segs)
