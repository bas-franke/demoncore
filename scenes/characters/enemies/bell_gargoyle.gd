extends ProcModel
## "Bell-Tower Gargoyle" (HOP): a sacred gargoyle that guards the cathedral bells - a crouching
## lion-faced grotesque of pale limestone with stubby stone wings, a bronze bell hung from a yoke
## on its back and a holy rune glowing on its brow. It leaps from on high: crouches (wind-up, the
## bell swings), springs in a high arc, wings spread, and lands with a toll of the bell.

const SHOULDER := 0.42
const LEAP := 1.5

var _head: Node3D
var _bell: Node3D
var _front: Array[Node3D] = []
var _back: Array[Node3D] = []
var _bell_v := 0.0
var _bell_a := 0.0


func build() -> void:
	feather_count = 0
	mote_count = 4
	debris = [&"shard", &"shard"]
	debris_color = Color(0.7, 0.68, 0.62)
	death_style = &"sink"
	stride = 1.0
	wing_speed = 3.0
	wing_amp = 0.1
	wing_lift = -0.2
	wing_sweep = 0.9
	var stone := m_stone(Color(0.66, 0.64, 0.58))
	var dark := m_stone(Color(0.42, 0.4, 0.37))
	var bronze := Art.mat(Art.BRONZE.lightened(0.15), 0.4, 0.5, 0.3, true, 0.2, &"gold")
	body = animated(Art.pivot(self, Vector3(0.0, SHOULDER, 0.0)))
	# Hunched, heavy chest; small haunches.
	Art.part(body, Art.sphere(), stone, Vector3(0.0, 0.08, -0.1), Vector3(0.38, 0.38, 0.36))
	Art.part(body, Art.sphere(), stone, Vector3(0.0, 0.02, 0.16), Vector3(0.3, 0.28, 0.3))
	for s: float in [-1.0, 1.0]:
		_front.append(beast_leg(body, Vector3(s * 0.13, -0.02, -0.18), SHOULDER - 0.02, 0.05, stone, dark, 0.0 if s < 0.0 else PI, 0.5))
		_back.append(beast_leg(body, Vector3(s * 0.12, -0.04, 0.22), SHOULDER - 0.04, 0.055, stone, dark, PI if s < 0.0 else 0.0, 0.5, true))
	solid_wing_pair(body, Vector3(0.0, 0.2, 0.08), 0.5, stone, dark, dark, 0.1)
	_head = animated(Art.pivot(body, Vector3(0.0, 0.2, -0.3)))
	Art.part(_head, Art.sphere(), stone, Vector3.ZERO, Vector3(0.24, 0.22, 0.24))
	Art.part(_head, Art.sphere(), stone, Vector3(0.0, -0.05, -0.1), Vector3(0.16, 0.12, 0.14))
	Art.part(_head, Art.box(), dark, Vector3(0.0, -0.09, -0.12), Vector3(0.14, 0.04, 0.08))
	for s: float in [-1.0, 1.0]:
		Art.part(_head, Art.cone(0.5), dark, Vector3(s * 0.04, -0.07, -0.17), Vector3(0.02, 0.04, 0.02), Vector3(PI, 0.0, 0.0))
		Art.part(_head, Art.cone(0.5), stone, Vector3(s * 0.1, 0.1, 0.02), Vector3(0.05, 0.12, 0.05), Vector3(-0.4, 0.0, -s * 0.4))
		Art.part(_head, Art.sphere(), Art.glow(Art.HOLY, 2.0), Vector3(s * 0.05, 0.03, -0.11), Vector3(0.035, 0.025, 0.02))
	# Glowing rune on the brow.
	Art.part(_head, Art.box(), Art.glow(Art.HOLY, 2.2), Vector3(0.0, 0.08, -0.11), Vector3(0.012, 0.06, 0.01))
	Art.part(_head, Art.box(), Art.glow(Art.HOLY, 2.2), Vector3(0.0, 0.09, -0.11), Vector3(0.04, 0.012, 0.01))
	# Bell on a yoke over the back (swings on its own pendulum).
	limb(body, Vector3(-0.12, 0.18, 0.08), Vector3(-0.12, 0.42, 0.1), 0.02, m_wood())
	limb(body, Vector3(0.12, 0.18, 0.08), Vector3(0.12, 0.42, 0.1), 0.02, m_wood())
	limb(body, Vector3(-0.15, 0.42, 0.1), Vector3(0.15, 0.42, 0.1), 0.025, m_wood())
	_bell = animated(Art.pivot(body, Vector3(0.0, 0.42, 0.1)))
	Art.part(_bell, Art.cylinder(0.08, 0.15), bronze, Vector3(0.0, -0.12, 0.0), Vector3(1.0, 0.18, 1.0))
	Art.part(_bell, Art.sphere(), bronze, Vector3(0.0, -0.03, 0.0), Vector3(0.16, 0.08, 0.16))
	Art.part(_bell, Art.torus(0.85, 1.0), bronze, Vector3(0.0, -0.21, 0.0), Vector3.ONE * 0.15)
	Art.part(_bell, Art.sphere(), dark, Vector3(0.0, -0.2, 0.0), Vector3.ONE * 0.05)
	finish()


func play_land() -> void:
	super.play_land()
	_bell_v += 9.0  # the bell tolls on landing
	Sfx.play(&"toll", 0.1, -12.0)


func pose(delta: float) -> void:
	var crouch := windup_w
	var air := strike_w
	var lift := 0.0
	if air > 0.05:
		lift = sin(clampf(state_progress, 0.0, 1.0) * PI) * LEAP * air
	body.position.y = SHOULDER + absf(sin(walk)) * 0.03 * move_w - crouch * 0.12 - land_kick * 0.08 + lift
	body.rotation.x = crouch * 0.15 - air * 0.15
	for l in _front:
		l.rotation.x += air * 0.9 - crouch * 0.3
	for l in _back:
		l.rotation.x -= air * 0.8 - crouch * 0.4
	wing_lift = -0.2 + air * 0.9 + crouch * 0.3
	wing_sweep = 0.9 - air * 0.7
	wing_amp = 0.1 + air * 0.4
	_head.rotation.x = -0.1 * move_w + crouch * 0.2 + sin(t * 0.8) * 0.05
	_head.rotation.y = sin(t * 0.6) * 0.3 * (1.0 - crouch)
	# Bell pendulum driven by the body's motion.
	var drive := -body.rotation.x * 4.0 + sin(walk) * 0.3 * move_w + crouch * sin(t * 10.0) * 0.6
	_bell_v += ((drive - _bell_a) * 18.0 - _bell_v * 2.0) * delta
	_bell_a += _bell_v * delta
	_bell.rotation.x = _bell_a


## Ragdoll death (characters-polish DeathFx): the pivots that flop loose.
func ragdoll_limbs() -> Array:
	return limbs_with([_head, _bell])
