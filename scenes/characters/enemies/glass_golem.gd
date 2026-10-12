extends ProcModel
## "Stained-Glass Golem" (CHASE, tanky, slow): a cathedral rose window given legs. A hulking body
## of coloured glass panes in black lead came, a round rose-window chest that burns with light
## from within, a small lancet-arch head and huge arms of glass shards. Glass is lit from inside
## (emissive panes), so it reads as a stained window at night. Shatters into shards on death.
## Cosmetic backhand swing near the player.

const HIP := 0.5
# Heaven's glass: sky blues, gold, pale violet, ivory. No blood red / leaf green (art-style palette).
const PANES := [Color(0.22, 0.4, 0.78), Color(0.9, 0.72, 0.3), Color(0.62, 0.5, 0.8), Color(0.45, 0.68, 0.85), Color(0.9, 0.85, 0.7)]

var _torso: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _rose: Node3D


func build() -> void:
	feather_count = 0
	mote_count = 6
	debris = [&"shard", &"shard", &"mote"]
	debris_color = Color(0.5, 0.6, 0.9)
	light_color = Color(0.85, 0.75, 1.0)
	death_style = &"shrink"
	death_time = 0.4
	stride = 1.0
	proximity_range = 1.7
	proximity_cooldown = 2.2
	var lead := Art.mat(Color(0.08, 0.08, 0.09), 0.5, 0.6)
	var glass: Array[Material] = []
	for c: Color in PANES:
		glass.append(Art.emissive(c.darkened(0.45), c.darkened(0.15), 0.55, 0.15))
	_torso = biped(HIP, 0.07, lead, lead, 0.13, 0.4)
	# Legs: add stained panes down the shins.
	for i in _legs.size():
		Art.part(_legs[i], Art.box(), glass[(i + 2) % 5], Vector3(0.0, -HIP * 0.55, -0.02), Vector3(0.1, HIP * 0.7, 0.1))
	# Body: a stack of lead-framed panes.
	Art.part(_torso, Art.box(), lead, Vector3(0.0, 0.32, 0.0), Vector3(0.56, 0.62, 0.3))
	for i in 6:
		var x := -0.18 + float(i % 3) * 0.18
		@warning_ignore("integer_division")  # row index
		var y := 0.16 + float(i / 3) * 0.34
		Art.part(_torso, Art.box(), glass[i % 5], Vector3(x, y, 0.0), Vector3(0.15, 0.28, 0.32))
	# Rose window on the chest: a disc ringed with lead and petals (it slowly turns).
	_rose = animated(Art.pivot(_torso, Vector3(0.0, 0.36, -0.17), Vector3(PI * 0.5, 0.0, 0.0)))
	Art.part(_rose, Art.cylinder(0.5, 0.5), lead, Vector3.ZERO, Vector3(0.44, 0.03, 0.44))
	for i in 8:
		var a := TAU * float(i) / 8.0
		Art.part(_rose, Art.sphere(), glass[i % 5], Vector3(cos(a) * 0.12, -0.02, sin(a) * 0.12), Vector3(0.1, 0.03, 0.1))
	Art.part(_rose, Art.sphere(), Art.glow(Art.HOLY_WHITE, 2.2), Vector3(0.0, -0.02, 0.0), Vector3(0.1, 0.04, 0.1))
	Art.part(_rose, Art.torus(0.85, 1.0), lead, Vector3(0.0, -0.02, 0.0), Vector3.ONE * 0.22)
	# Head: a small lancet arch (pointed window) with a glowing slit.
	var head := Art.pivot(_torso, Vector3(0.0, 0.7, 0.0))
	Art.part(head, Art.box(), lead, Vector3(0.0, 0.06, 0.0), Vector3(0.2, 0.14, 0.16))
	Art.part(head, Art.prism(), lead, Vector3(0.0, 0.18, 0.0), Vector3(0.2, 0.12, 0.16))
	Art.part(head, Art.box(), glass[2], Vector3(0.0, 0.08, -0.04), Vector3(0.14, 0.1, 0.1))
	Art.part(head, Art.box(), Art.glow(Art.HOLY_WHITE, 2.5), Vector3(0.0, 0.08, -0.09), Vector3(0.1, 0.015, 0.01))
	# Arms: heaps of long shards.
	for s: float in [-1.0, 1.0]:
		var a := arm(_torso, Vector3(s * 0.34, 0.56, 0.0), 0.56, 0.06, lead, lead, 0.0 if s < 0.0 else PI, 0.3)
		for k in 4:
			var f := float(k) / 3.0
			Art.part(a[0], Art.prism(), glass[(k + (2 if s > 0.0 else 0)) % 5], Vector3(s * 0.03, -0.1 - f * 0.4, 0.0),
					Vector3(0.14 - f * 0.02, 0.2, 0.12), Vector3(0.0, f, PI * (0.0 if k % 2 == 0 else 1.0)))
		Art.part(a[1], Art.prism(), glass[1], Vector3(0.0, -0.08, 0.0), Vector3(0.16, 0.22, 0.14), Vector3(PI, 0.0, 0.0))
		if s < 0.0:
			_arm_l = a[0]
		else:
			_arm_r = a[0]
	finish()


func proximity_attack() -> void:
	play_attack()


func pose(delta: float) -> void:
	biped_bob(HIP, 0.05)
	var k := attack_kick
	_torso.rotation.x = -0.05 * move_w - k * 0.15
	_torso.rotation.y = sin(walk) * 0.1 * move_w + k * 0.5
	_torso.rotation.z = sin(walk) * 0.05 * move_w
	_rose.rotate_object_local(Vector3.UP, delta * 0.5)
	# Heavy arms hang forward; a backhand sweep on attack.
	_arm_l.rotation.z = -0.15
	_arm_r.rotation = mixv(Vector3(_arm_r.rotation.x, 0.0, 0.15), Vector3(1.2, -0.8, 0.6), k)
