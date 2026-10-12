extends ProcModel
## "Dryad Priestess" (HEAL): a nature-saint of the Eden gardens. A tall, willowy woman of pale
## birch bark with green-gold leaf robes that trail into roots, long hair of hanging willow
## fronds, a crown of white lilies and a blossoming staff of living wood. HEAL: she plants the
## staff and lifts her free hand; the lilies and her staff blossom with golden light while she
## channels the healing circle over her allies (the wind-up).

const BLOOM := Color(1.0, 0.95, 0.6)

var _torso: Node3D
var _head: Node3D
var _hair: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _bloom: MeshInstance3D
var _roots: Array[Node3D] = []


func build() -> void:
	feather_count = 0
	mote_count = 10
	light_color = BLOOM
	death_style = &"sink"
	var bark := Art.mat(Color(0.82, 0.8, 0.72), 0.8, 0.0, 0.3, true, 0.0, &"wood")
	var leaves := Art.mat(Color(0.35, 0.5, 0.22), 0.7, 0.0, 0.2, true, 0.4, &"cloth")
	var gold_leaf := Art.mat(Color(0.7, 0.6, 0.25), 0.5, 0.4, 0.2, true, 0.2, &"cloth")
	var lily := Art.mat(Color(0.97, 0.97, 0.92), 0.5, 0.0, 0.0, true, 0.5)
	body = animated(Art.pivot(self))
	# Leaf robe falling into a skirt of roots (roots creep in pose()).
	Art.part(body, Art.cylinder(0.12, 0.26), leaves, Vector3(0.0, 0.4, 0.0), Vector3(1.0, 0.8, 0.9))
	for k in 6:
		var ang := TAU * float(k) / 6.0
		Art.part(body, Art.sphere(), gold_leaf, Vector3(cos(ang) * 0.2, 0.15, sin(ang) * 0.18), Vector3(0.1, 0.22, 0.04), Vector3(0.0, -ang, 0.0))
		var r := animated(Art.pivot(body, Vector3(cos(ang) * 0.22, 0.02, sin(ang) * 0.2), Vector3(0.0, -ang, 0.0)))
		limb(r, Vector3.ZERO, Vector3(0.14, -0.02, 0.0), 0.02, bark)
		_roots.append(r)
	_torso = animated(Art.pivot(body, Vector3(0.0, 0.78, 0.0)))
	Art.part(_torso, Art.cylinder(0.12, 0.12), bark, Vector3(0.0, 0.15, 0.0), Vector3(1.0, 0.34, 0.75))
	Art.part(_torso, Art.cylinder(0.13, 0.15), leaves, Vector3(0.0, 0.1, 0.0), Vector3(1.02, 0.26, 0.78))
	_head = animated(Art.pivot(_torso, Vector3(0.0, 0.42, 0.0)))
	Art.part(_head, Art.sphere(), bark, Vector3.ZERO, Vector3(0.13, 0.17, 0.14))
	for s: float in [-1.0, 1.0]:
		Art.part(_head, Art.sphere(), Art.glow(Color(0.7, 1.0, 0.5), 1.6), Vector3(s * 0.03, 0.015, -0.065), Vector3(0.025, 0.012, 0.01))
	# Lily crown.
	for k in 6:
		var ang := TAU * float(k) / 6.0
		Art.part(_head, Art.cone(0.5), lily, Vector3(cos(ang) * 0.07, 0.1, sin(ang) * 0.07), Vector3(0.04, 0.07, 0.04), Vector3(sin(ang) * 0.5, 0.0, -cos(ang) * 0.5))
	# Willow-frond hair down the back.
	_hair = animated(Art.pivot(_head, Vector3(0.0, 0.05, 0.05)))
	for k in 5:
		var x := -0.06 + k * 0.03
		limb(_hair, Vector3(x, 0.0, 0.0), Vector3(x * 1.4, -0.42, 0.06), 0.012, leaves)
	var a := arm(_torso, Vector3(-0.15, 0.27, 0.0), 0.36, 0.025, bark, bark, 0.0, 0.0)
	_arm_l = a[0]
	var b := arm(_torso, Vector3(0.15, 0.27, 0.0), 0.36, 0.025, bark, bark, 0.0, 0.0)
	_arm_r = b[0]
	# Living staff: crooked wood with leaves and a blossom at the top.
	var st := Art.pivot(b[1], Vector3.ZERO, Vector3(PI, 0.0, 0.0))
	limb(st, Vector3(0.0, -0.5, 0.0), Vector3(0.02, 0.25, 0.0), 0.016, m_wood())
	limb(st, Vector3(0.02, 0.25, 0.0), Vector3(-0.02, 0.62, 0.0), 0.014, m_wood())
	for k in 4:
		Art.part(st, Art.sphere(), leaves, Vector3(0.04 * (1.0 if k % 2 == 0 else -1.0), 0.4 + k * 0.06, 0.0), Vector3(0.06, 0.03, 0.04))
	_bloom = keep(Art.part(st, Art.sphere(), Art.glow(BLOOM, 2.0), Vector3(-0.02, 0.66, 0.0), Vector3.ONE * 0.06))
	finish()


func pose(_delta: float) -> void:
	var channel := windup_w
	body.rotation.z = sin(t * 0.8) * 0.03
	body.position.y = sin(t * 1.4) * 0.01
	_torso.rotation.x = -0.05 * move_w - channel * 0.1
	_torso.rotation.z = sin(t * 0.9) * 0.05
	_head.rotation.x = -channel * 0.35 + sin(t * 0.7) * 0.05
	_hair.rotation.x = 0.15 + 0.2 * move_w + sin(t * 1.3) * 0.08
	_arm_r.rotation = Vector3(0.35 + sin(walk) * 0.15 * move_w, 0.0, 0.15)
	_arm_l.rotation = mixv(Vector3(0.2 - sin(walk) * 0.2 * move_w, 0.0, -0.2), Vector3(2.4, 0.2, -0.4), channel)
	for i in _roots.size():
		_roots[i].rotation.z = sin(t * 2.0 + float(i)) * 0.15 + move_w * 0.2
	_bloom.scale = Vector3.ONE * 0.06 * (1.0 + channel * 2.0 + 0.1 * sin(t * 3.0))
