extends ProcModel
## "Lesser Ophan" (CHASE, swarm, hovers): a wheel within a wheel no bigger than a shield - two
## crossed gold rings studded with lidded eyes turning around a white-hot hub, trailing sparks.
## They come in swarms (the Ophanim swarm). Biblically accurate and very small. No legs, no
## wings: the rings spin faster the faster it flies.

const SPARK := Color(1.0, 0.8, 0.45)

var _ring_a: Node3D
var _ring_b: Node3D
var _hub: MeshInstance3D
var _spin := 0.0


func build() -> void:
	feather_count = 0
	mote_count = 4
	debris = [&"gold"]
	debris_color = Art.GOLD
	death_style = &"shrink"
	death_time = 0.25
	var gold := m_gold()
	body = animated(Art.pivot(self, Vector3(0.0, 0.55, 0.0)))
	_ring_a = animated(Art.pivot(body))
	Art.part(_ring_a, Art.torus(0.8, 1.0), gold, Vector3.ZERO, Vector3.ONE * 0.3, Vector3(0.0, 0.0, PI * 0.5))
	for i in 4:
		var a := TAU * float(i) / 4.0
		var d := Vector3(0.0, cos(a), sin(a))
		eye(_ring_a, d * 0.3, 0.06, d, true)
	_ring_b = animated(Art.pivot(body))
	Art.part(_ring_b, Art.torus(0.8, 1.0), gold, Vector3.ZERO, Vector3.ONE * 0.24, Vector3(PI * 0.5, 0.0, 0.0))
	for i in 3:
		var a := TAU * float(i) / 3.0 + 0.5
		var d := Vector3(cos(a), sin(a), 0.0)
		eye(_ring_b, d * 0.24, 0.05, d, true)
	_hub = keep(Art.part(body, Art.sphere(), Art.glow(Art.HOLY_WHITE, 2.8), Vector3.ZERO, Vector3.ONE * 0.11))
	Art.part(body, Art.sphere(), Art.glow(SPARK, 0.5), Vector3.ZERO, Vector3.ONE * 0.26)
	finish()


func pose(delta: float) -> void:
	_spin += delta * (2.5 + move_w * 6.0 + attack_kick * 8.0)
	_ring_a.rotation = Vector3(_spin, 0.0, 0.0)
	_ring_b.rotation = Vector3(0.0, _spin * 0.7, _spin * 1.3)
	body.position.y = 0.55 + sin(t * 3.1) * 0.08
	body.rotation.y = sin(t * 0.7) * 0.6
	_hub.scale = Vector3.ONE * 0.11 * (1.0 + 0.15 * sin(t * 15.0) + eye_flare * 0.4)
