extends ProcModel
## "Griffon" (CHARGE, flies low): eagle before, lion behind. A white-feathered eagle's head and
## breast with a hooked gold beak, taloned forelegs, tawny lion hindquarters and tail, and broad
## bronze-tipped wings. It flies low; CHARGE: it rises and draws its wings up with talons raised
## (wind-up), then stoops through you, wings swept back, talons forward.

const HEIGHT := 0.7

var _head: Node3D
var _tail: Node3D
var _fore: Array[Node3D] = []
var _hind: Array[Node3D] = []


func build() -> void:
	feather_count = 6
	feather_color = Color(0.95, 0.92, 0.85)
	wing_speed = 5.0
	wing_amp = 0.5
	wing_sweep = 0.2
	stride = 1.5
	var feathers := Art.mat(Color(0.95, 0.93, 0.88), 0.75, 0.0, 0.15, true, 0.3, &"feather")
	var fur := m_fur(Color(0.72, 0.56, 0.34))
	var gold := m_gold()
	body = animated(Art.pivot(self, Vector3(0.0, HEIGHT, 0.0)))
	# Feathered breast (front) blending into the lion's barrel and haunches.
	Art.part(body, Art.sphere(), feathers, Vector3(0.0, 0.03, -0.2), Vector3(0.32, 0.36, 0.38))
	Art.part(body, Art.sphere(), fur, Vector3(0.0, 0.0, 0.16), Vector3(0.28, 0.28, 0.44))
	# Taloned eagle forelegs, lion hind legs.
	var talon := Art.mat(Art.GOLD.darkened(0.2), 0.4, 0.6)
	for s: float in [-1.0, 1.0]:
		_fore.append(beast_leg(body, Vector3(s * 0.09, -0.08, -0.22), 0.4, 0.035, m_skin(Color(0.85, 0.7, 0.35)), talon, 0.0 if s < 0.0 else PI, 0.4))
		_hind.append(beast_leg(body, Vector3(s * 0.1, -0.04, 0.28), 0.42, 0.05, fur, fur, PI if s < 0.0 else 0.0, 0.4, true))
	_head = animated(Art.pivot(body, Vector3(0.0, 0.18, -0.38)))
	Art.part(_head, Art.sphere(), feathers, Vector3.ZERO, Vector3(0.18, 0.2, 0.22))
	# Hooked beak: an upper cone curving down, plus a smaller lower mandible.
	Art.part(_head, Art.cone(0.5), gold, Vector3(0.0, -0.01, -0.15), Vector3(0.08, 0.16, 0.09), Vector3(-PI * 0.5 - 0.35, 0.0, 0.0))
	Art.part(_head, Art.cone(0.5), gold, Vector3(0.0, -0.04, -0.12), Vector3(0.05, 0.08, 0.05), Vector3(-PI * 0.5 + 0.2, 0.0, 0.0))
	# Ear tufts / crest.
	for s: float in [-1.0, 1.0]:
		Art.part(_head, Art.cone(0.5), feathers, Vector3(s * 0.05, 0.11, 0.06), Vector3(0.04, 0.14, 0.04), Vector3(0.6, 0.0, s * 0.3))
		eye(_head, Vector3(s * 0.06, 0.03, -0.07), 0.03, Vector3(s * 0.6, 0.0, -1.0), false, Color(1.0, 0.8, 0.3))
	# Lion's tail with a tuft.
	_tail = animated(Art.pivot(body, Vector3(0.0, 0.05, 0.4)))
	limb(_tail, Vector3.ZERO, Vector3(0.0, 0.05, 0.36), 0.018, fur)
	Art.part(_tail, Art.sphere(), m_fur(Color(0.5, 0.36, 0.2)), Vector3(0.0, 0.06, 0.4), Vector3(0.07, 0.07, 0.12))
	solid_wing_pair(body, Vector3(0.0, 0.14, -0.1), 0.85, feathers, feathers, Art.mat(Art.BRONZE, 0.6, 0.3, 0.2, true, 0.0, &"feather"), 0.12)
	finish()


func pose(_delta: float) -> void:
	var rise := windup_w
	var stoop := strike_w
	body.position.y = HEIGHT + sin(t * wing_speed) * 0.05 + rise * 0.35 - stoop * 0.25
	body.rotation.x = -0.15 * move_w + rise * 0.35 - stoop * 0.35
	wing_amp = 0.5 * (1.0 - stoop) + rise * 0.2
	wing_lift = 0.15 + rise * 0.7 - stoop * 0.3
	wing_sweep = 0.2 + stoop * 0.9
	# Talons raised in the wind-up and thrust forward in the stoop; legs tuck while flying.
	for l in _fore:
		l.rotation.x = 0.4 + rise * 0.8 + stoop * 1.1 + sin(t * 3.0) * 0.05
	for l in _hind:
		l.rotation.x = -0.7 - stoop * 0.3
	_head.rotation.x = 0.1 - rise * 0.3 + stoop * 0.3
	_head.rotation.y = sin(t * 1.2) * 0.2 * (1.0 - stoop)
	_tail.rotation = Vector3(-0.2 + sin(t * 2.5) * 0.15, sin(t * 1.9) * 0.4, 0.0)


## Ragdoll death (characters-polish DeathFx): the pivots that flop loose.
func ragdoll_limbs() -> Array:
	return limbs_with([_head, _tail])
