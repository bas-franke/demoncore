extends ProcModel
## "Choir Wraith" (SHOOT, hovers): the ghost of a choir boy who died mid-hymn and kept singing. A
## small pale figure in a red cassock under a white surplice with a stiff ruff, hymnal open in
## both hands, feet trailing away into mist, eyes closed, mouth a round O of light. SHOOT: it
## takes a breath (leans back, the mouth widens), then sings a note of light (holy orb).

const NOTE := Color(0.85, 0.9, 1.0)

var _torso: Node3D
var _head: Node3D
var _mouth: MeshInstance3D
var _book: Node3D
var _mist: Array[Node3D] = []


func build() -> void:
	feather_count = 0
	mote_count = 8
	light_color = NOTE
	death_style = &"shrink"
	death_time = 0.35
	var cassock := Art.mat(Color(0.14, 0.16, 0.36), 0.8, 0.0, 0.2, true, 0.3, &"cloth")  # art-style: no red main albedo on heaven's side
	var surplice := Art.mat(Color(0.92, 0.94, 0.98), 0.7, 0.0, 0.05, true, 0.5, &"cloth")
	var skin := Art.mat(Color(0.82, 0.85, 0.92), 0.6, 0.0, 0.0, true, 0.6, &"skin")
	body = animated(Art.pivot(self, Vector3(0.0, 0.5, 0.0)))
	# Cassock fading down into a trail of mist puffs.
	Art.part(body, Art.cylinder(0.12, 0.17), cassock, Vector3(0.0, 0.05, 0.0), Vector3(1.0, 0.3, 0.9))
	for i in 3:
		var m := animated(Art.pivot(body, Vector3(0.0, -0.14 - i * 0.11, 0.02 * i)))
		Art.part(m, Art.sphere(), Art.glow(NOTE, 0.6, true, 0.6), Vector3.ZERO, Vector3.ONE * (0.24 - i * 0.06))
		_mist.append(m)
	_torso = animated(Art.pivot(body, Vector3(0.0, 0.2, 0.0)))
	Art.part(_torso, Art.cylinder(0.11, 0.2), surplice, Vector3(0.0, 0.08, 0.0), Vector3(1.0, 0.3, 0.9))
	Art.part(_torso, Art.cylinder(0.12, 0.12), cassock, Vector3(0.0, 0.22, 0.0), Vector3(0.9, 0.12, 0.8))
	# Stiff white ruff.
	Art.part(_torso, Art.torus(0.4, 1.0), surplice, Vector3(0.0, 0.29, 0.0), Vector3(0.14, 0.2, 0.14))
	_head = animated(Art.pivot(_torso, Vector3(0.0, 0.38, 0.0)))
	Art.part(_head, Art.sphere(), skin, Vector3.ZERO, Vector3(0.15, 0.17, 0.15))
	Art.part(_head, Art.sphere(), Art.mat(Color(0.55, 0.45, 0.35), 0.7, 0.0, 0.2, true, 0.3, &"cloth"), Vector3(0.0, 0.04, 0.015), Vector3(0.16, 0.12, 0.16))
	for s: float in [-1.0, 1.0]:
		Art.part(_head, Art.box(), Art.mat(Color(0.3, 0.3, 0.4), 0.5), Vector3(s * 0.035, 0.015, -0.07), Vector3(0.035, 0.006, 0.01))
	_mouth = keep(Art.part(_head, Art.sphere(), Art.glow(Art.HOLY_WHITE, 2.4), Vector3(0.0, -0.04, -0.07), Vector3(0.035, 0.035, 0.02)))
	halo(_head, Vector3(0.0, 0.12, 0.03), 0.09, 2.0, false, false, NOTE)
	# Hymnal held open in both hands (arms baked into the book pivot: they move together).
	_book = animated(Art.pivot(_torso, Vector3(0.0, 0.14, -0.13), Vector3(-0.7, 0.0, 0.0)))
	for s: float in [-1.0, 1.0]:
		Art.part(_book, Art.box(), Art.mat(Color(0.3, 0.08, 0.08), 0.6), Vector3(s * 0.05, 0.0, 0.0), Vector3(0.1, 0.012, 0.13), Vector3(0.0, 0.0, -s * 0.15))
		Art.part(_book, Art.box(), Art.mat(Art.IVORY, 0.8, 0.0, 0.2, true, 0.0, &"parchment"), Vector3(s * 0.048, 0.01, 0.0), Vector3(0.09, 0.01, 0.12), Vector3(0.0, 0.0, -s * 0.15))
		limb(_book, Vector3(s * 0.1, -0.01, 0.0), Vector3(s * 0.11, 0.05, 0.13), 0.022, surplice)
	finish()


func pose(_delta: float) -> void:
	var breath := windup_w
	body.position.y = 0.5 + sin(t * 1.8) * 0.06
	body.rotation.x = -0.12 * move_w
	_torso.rotation.x = breath * 0.25 - attack_kick * 0.35
	_head.rotation.x = -0.25 - breath * 0.2 + sin(t * 2.4) * 0.04
	_head.rotation.z = sin(t * 1.3) * 0.08
	_book.rotation.x = -0.7 + sin(t * 2.4) * 0.05
	var o := 1.0 + breath * 1.2 + attack_kick * 1.6 + 0.2 * sin(t * 6.0)
	_mouth.scale = Vector3(0.035, 0.035 * o, 0.02)
	for i in _mist.size():
		_mist[i].position.x = sin(t * 2.0 - float(i) * 0.8) * 0.04 * float(i + 1)
