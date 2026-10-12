extends ProcModel
## "Light Elemental" (SHOOT, hovers): a living mote of the First Light. A blazing core inside
## three counter-rotating rings of runes, crowned and skirted by orbiting shards of light that
## form a rough body, with two loose "hands" of light that drift beside it. No face, no wings.
## SHOOT: the rings snap together and the core swells (wind-up), then a pulse (holy orb) with
## the rings flung wide. Collapses into motes on death.

const CORE := Color(1.0, 0.92, 0.7)

var _core: MeshInstance3D
var _rings: Array[Node3D] = []
var _shards: Node3D
var _hands: Array[Node3D] = []


func build() -> void:
	feather_count = 0
	mote_count = 14
	light_color = CORE
	debris = [&"mote"]
	death_style = &"shrink"
	death_time = 0.3
	body = animated(Art.pivot(self, Vector3(0.0, 0.75, 0.0)))
	# art-style round 3: 3.0 -> 2.0 and less charge growth (the wind-up was one white disc).
	_core = keep(Art.part(body, Art.sphere(), Art.glow(Art.HOLY_WHITE, 2.0), Vector3.ZERO, Vector3.ONE * 0.24))
	Art.part(body, Art.sphere(), ArtStyle.holy_glow(Art.HOLY_WHITE, CORE, 1.0, 0.85), Vector3.ZERO, Vector3.ONE * 0.6)
	var gold := Art.emissive(Art.GOLD, Art.HOLY, 1.2, 0.3)
	for i in 3:
		var r := animated(Art.pivot(body, Vector3.ZERO, Vector3(0.4 * float(i), 0.0, 0.7 * float(i))))
		Art.part(r, Art.torus(0.9, 1.0), gold, Vector3.ZERO, Vector3.ONE * (0.3 + 0.06 * float(i)))
		# Rune studs on each ring.
		for k in 6:
			var a := TAU * float(k) / 6.0
			Art.part(r, Art.box(), Art.glow(Art.HOLY, 2.0), Vector3(cos(a), 0.0, sin(a)) * (0.3 + 0.06 * float(i)), Vector3.ONE * 0.03)
		_rings.append(r)
	# Orbiting shards: a crown above and a tapering skirt below.
	_shards = animated(Art.pivot(body))
	for i in 10:
		var a := TAU * float(i) / 10.0
		var up := i % 2 == 0
		var p := Vector3(cos(a) * (0.22 if up else 0.18), 0.32 if up else -0.38 - 0.06 * float(i % 3), sin(a) * (0.22 if up else 0.18))
		Art.part(_shards, Art.prism(), Art.glow(CORE, 1.5), p, Vector3(0.05, 0.18, 0.05), Vector3(0.0, a, PI if not up else 0.0))
	for s: float in [-1.0, 1.0]:
		var h := animated(Art.pivot(body, Vector3(s * 0.45, -0.05, -0.05)))
		Art.part(h, Art.sphere(), Art.glow(Art.HOLY_WHITE, 2.2), Vector3.ZERO, Vector3.ONE * 0.1)
		Art.part(h, Art.sphere(), Art.glow(CORE, 0.4), Vector3.ZERO, Vector3.ONE * 0.22)
		_hands.append(h)
	finish()


func pose(delta: float) -> void:
	var charge := windup_w
	body.position.y = 0.75 + sin(t * 2.4) * 0.08
	for i in _rings.size():
		var spd := (1.2 + float(i) * 0.6) * (1.0 if i % 2 == 0 else -1.0) * (1.0 + charge * 4.0)
		_rings[i].rotate_object_local(Vector3.UP, spd * delta)
		# Rings close in on the core while charging, fling outward on the pulse.
		_rings[i].scale = Vector3.ONE * (1.0 - charge * 0.35 + attack_kick * 0.5)
	_shards.rotation.y += delta * (0.8 + charge * 3.0)
	_core.scale = Vector3.ONE * 0.24 * (1.0 + charge * 0.4 + attack_kick * 0.3 + 0.06 * sin(t * 11.0))
	for i in _hands.size():
		var s := -1.0 if i == 0 else 1.0
		_hands[i].position = Vector3(s * (0.45 - charge * 0.25), -0.05 + sin(t * 1.8 + float(i)) * 0.08 + charge * 0.15, -0.05 - charge * 0.2)
