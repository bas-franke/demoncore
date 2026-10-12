extends BossModel
## "Aurelion, the Dawn Wyrm" (boss model, sunlit citadel): the great dragon of the morning, a
## grown Dawn Wyrmling. A long body of pearl and gold scales held aloft on vast solid wings, four
## clawed legs, a long arched neck, a horned crowned head with a burning maw, a sun-disc of light
## blazing behind its head, a tail of tapering segments with a golden fin.
## Poses per attack: lanes / sweep = breath (neck draws back on the tell, lunges and the maw blazes
## on the strike); orbs / rain = rears up and beats the wings; bells = a great downbeat; charge =
## wings swept back, neck flat; summon = the sun-disc flares.

const SEGMENTS := 8
const SUN := Color(1.0, 0.85, 0.45)

var _neck: Node3D
var _head: Node3D
var _jaw: Node3D
var _maw: MeshInstance3D
var _sun: Node3D
var _tail: Array[Node3D] = []
var _legs_all: Array[Node3D] = []


func build() -> void:
	light_color = SUN
	stride = 2.0
	wing_speed = 2.2
	wing_amp = 0.35
	wing_lift = 0.25
	wing_sweep = 0.2
	var scales := Art.mat(Color(0.93, 0.9, 0.82), 0.35, 0.15, 0.1, true, 0.4, &"scales")
	var gold := Art.mat(Art.GOLD, 0.35, 0.5, 0.15, true, 0.3, &"gold")
	var membrane := Art.mat(Color(0.98, 0.9, 0.7), 0.5, 0.0, 0.05, true, 0.6)
	body = animated(Art.pivot(self, Vector3(0.0, 0.6, 0.0)))
	Art.part(body, Art.sphere(), scales, Vector3(0.0, 0.0, 0.0), Vector3(0.5, 0.46, 0.9))
	Art.part(body, Art.sphere(), gold, Vector3(0.0, -0.1, -0.05), Vector3(0.38, 0.3, 0.8))
	for k in 5:
		Art.part(body, Art.cone(0.5), gold, Vector3(0.0, 0.23, -0.3 + k * 0.15), Vector3(0.05, 0.14, 0.08), Vector3(0.3, 0.0, 0.0))
	solid_wing_pair(body, Vector3(0.0, 0.18, -0.12), 1.4, membrane, gold, Art.mat(Color(1.0, 0.8, 0.45), 0.4, 0.0, 0.0, true, 0.6), 0.16)
	# Four clawed legs, tucked (it hovers) - folded in pose().
	for s: float in [-1.0, 1.0]:
		for z: float in [-0.25, 0.28]:
			var lg := limb_pivot(body, Vector3(s * 0.18, -0.12, z))
			limb(lg, Vector3.ZERO, Vector3(0.0, -0.3, 0.06), 0.05, scales)
			limb(lg, Vector3(0.0, -0.3, 0.06), Vector3(0.0, -0.46, -0.06), 0.035, scales)
			for c in 3:
				Art.part(lg, Art.cone(0.5), gold, Vector3((float(c) - 1.0) * 0.03, -0.48, -0.1), Vector3(0.02, 0.07, 0.02), Vector3(-PI * 0.5, 0.0, 0.0))
			_legs_all.append(lg)
	# Tail.
	var parent := body
	for i in SEGMENTS:
		var f := float(i) / float(SEGMENTS)
		var seg := animated(Art.pivot(parent, Vector3(0.0, 0.0, 0.42 if i == 0 else 0.22)))
		Art.part(seg, Art.sphere(), scales, Vector3(0.0, 0.0, 0.11), Vector3(0.3, 0.26, 0.32) * (1.0 - f * 0.75))
		Art.part(seg, Art.cone(0.5), gold, Vector3(0.0, 0.13 * (1.0 - f * 0.7), 0.1), Vector3(0.04, 0.12, 0.06) * (1.0 - f * 0.5))
		_tail.append(seg)
		parent = seg
	Art.part(parent, Art.prism(), gold, Vector3(0.0, 0.0, 0.3), Vector3(0.36, 0.3, 0.03), Vector3(PI * 0.5, 0.0, 0.0))
	# Neck and head.
	_neck = animated(Art.pivot(body, Vector3(0.0, 0.15, -0.4), Vector3(-0.6, 0.0, 0.0)))
	limb(_neck, Vector3.ZERO, Vector3(0.0, 0.0, -0.55), 0.13, scales)
	for k in 4:
		Art.part(_neck, Art.cone(0.5), gold, Vector3(0.0, 0.13, -0.08 - k * 0.13), Vector3(0.04, 0.12, 0.06), Vector3(0.3, 0.0, 0.0))
	_head = animated(Art.pivot(_neck, Vector3(0.0, 0.0, -0.58), Vector3(0.5, 0.0, 0.0)))
	Art.part(_head, Art.sphere(), scales, Vector3(0.0, 0.03, -0.06), Vector3(0.3, 0.22, 0.36))
	Art.part(_head, Art.cylinder(0.07, 0.11), scales, Vector3(0.0, 0.02, -0.28), Vector3(1.0, 0.3, 0.75), Vector3(-PI * 0.5, 0.0, 0.0))
	for s: float in [-1.0, 1.0]:
		Art.part(_head, Art.cone(0.5), gold, Vector3(s * 0.09, 0.16, 0.06), Vector3(0.05, 0.34, 0.05), Vector3(1.1, 0.0, -s * 0.25))
		Art.part(_head, Art.cone(0.5), gold, Vector3(s * 0.12, 0.08, 0.1), Vector3(0.035, 0.2, 0.035), Vector3(1.3, 0.0, -s * 0.6))
		Art.part(_head, Art.sphere(), Art.glow(Art.HOLY_WHITE, 2.6), Vector3(s * 0.09, 0.08, -0.15), Vector3(0.05, 0.03, 0.04))
	# Crown of gold tines between the horns.
	for k in 5:
		Art.part(_head, Art.cone(0.5), gold, Vector3((float(k) - 2.0) * 0.035, 0.2, 0.0), Vector3(0.025, 0.12 + 0.04 * float(2 - absi(k - 2)), 0.025))
	_jaw = animated(Art.pivot(_head, Vector3(0.0, -0.05, -0.08)))
	Art.part(_jaw, Art.box(), scales, Vector3(0.0, -0.02, -0.2), Vector3(0.14, 0.05, 0.3))
	_maw = keep(Art.part(_head, Art.sphere(), Art.glow(SUN, 2.8), Vector3(0.0, -0.02, -0.38), Vector3.ONE * 0.04))
	# Sun-disc behind the head.
	_sun = animated(Art.pivot(_head, Vector3(0.0, 0.2, 0.22)))
	Art.part(_sun, Art.torus(0.85, 1.0), Art.glow(SUN, 2.4), Vector3.ZERO, Vector3.ONE * 0.4, Vector3(PI * 0.5, 0.0, 0.0))
	Art.part(_sun, Art.cylinder(0.5, 0.5), Art.glow(SUN, 0.4), Vector3.ZERO, Vector3(0.78, 0.01, 0.78), Vector3(PI * 0.5, 0.0, 0.0))
	for k in 12:
		var a := TAU * float(k) / 12.0
		Art.part(_sun, Art.cone(0.5), Art.glow(SUN, 1.8), Vector3(cos(a), sin(a), 0.0) * 0.48, Vector3(0.04, 0.16, 0.02), Vector3(0.0, 0.0, a - PI * 0.5))
	finish()


func pose(delta: float) -> void:
	var breath := act([&"lanes", &"sweep", &"cross"])
	var rear := act([&"orbs", &"rain", &"chase"])
	var beat := act([&"bells", &"pyre"])
	var dive := act([&"charge"])
	var flare := act([&"summon"]) + rise_w
	body.position.y = 0.6 + sin(t * wing_speed) * 0.08 + rear * 0.3 + rise_w * 0.5 - kneel_w * 0.6
	body.rotation.x = rear * 0.45 - dive * 0.3 + kneel_w * -0.2
	wing_speed = 2.2 + rear * 1.5 + beat * 2.0
	wing_amp = 0.35 + rear * 0.15 + beat * 0.3 - dive * 0.3
	wing_lift = 0.25 + beat * 0.4 * (1.0 - strike_w * 2.0) - dive * 0.3 - kneel_w * 0.5
	wing_sweep = 0.2 + dive * 0.9
	# Breath: neck draws back on the tell, lunges on the strike.
	_neck.rotation.x = -0.6 + breath * (0.5 * windup_w - 0.6 * strike_w) - rear * 0.2 + dive * 0.4 + kneel_w * 0.5
	_neck.rotation.y = sin(t * 0.7) * 0.15 * (1.0 - breath)
	_head.rotation.x = 0.5 - breath * 0.3 * strike_w
	_jaw.rotation.x = 0.1 + breath * 0.6 + rear * 0.3 + sin(t * 2.0) * 0.03
	_maw.scale = Vector3.ONE * (0.04 + breath * 0.18 + windup_w * 0.05)
	_sun.rotate_object_local(Vector3.FORWARD, delta * (0.3 + flare * 2.0))
	_sun.scale = Vector3.ONE * (1.0 + flare * 0.4 + float(boss_phase) * 0.12)
	for l in _legs_all:
		l.rotation.x = 0.8 + sin(t * 1.5) * 0.08 - rear * 0.5 - dive * 0.6
	for i in _tail.size():
		_tail[i].rotation.y = sin(t * 2.0 - float(i) * 0.6) * 0.18
		_tail[i].rotation.x = 0.06 + sin(t * 1.2 - float(i) * 0.5) * 0.06
