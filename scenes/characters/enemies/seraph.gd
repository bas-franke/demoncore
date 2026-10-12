extends ProcModel
## "Seraph": a burning one. A slender column of white flame in a gold-banded robe with six wings
## - two crossed over its face, two folded over its feet, two beating to hold it aloft. It has no
## arms; it burns. SHOOT: during the wind-up the face wings part to show the blazing face and
## every wing flares wide, then the fire is thrown (holy orb) with a recoil of the whole body.

# Holy flame: gold-white, never hellfire orange (docs/team/art-style.md palette).
const FLAME := Color(1.0, 0.8, 0.45)

var _face_wings: Node3D
var _foot_wings: Node3D
var _face: MeshInstance3D
var _flames: Array[Node3D] = []


func build() -> void:
	light_color = FLAME
	feather_color = Color(1.0, 0.9, 0.7)
	feather_count = 6
	wing_speed = 4.0
	wing_amp = 0.35
	death_style = &"shrink"
	body = animated(Art.pivot(self, Vector3(0.0, 0.2, 0.0)))
	var robe := Art.mat(Art.HOLY_WHITE.darkened(0.08), 0.6, 0.0, 0.1, true, 0.4, &"cloth")
	var gold := m_gold()
	# Robe: a long tapering cone that dissolves into flame at the hem.
	Art.part(body, Art.cylinder(0.14, 0.24), robe, Vector3(0.0, 0.45, 0.0), Vector3(1.0, 0.9, 1.0))
	Art.part(body, Art.cylinder(0.5, 0.5), gold, Vector3(0.0, 0.7, 0.0), Vector3(0.3, 0.04, 0.3))
	Art.part(body, Art.cylinder(0.5, 0.5), gold, Vector3(0.0, 0.2, 0.0), Vector3(0.44, 0.03, 0.44))
	Art.part(body, Art.sphere(), robe, Vector3(0.0, 0.92, 0.0), Vector3(0.32, 0.26, 0.26))
	# Hem fire: tongues of flame flickering below the robe (animated individually).
	for i in 5:
		var a := TAU * float(i) / 5.0
		var f := animated(Art.pivot(body, Vector3(cos(a) * 0.12, 0.02, sin(a) * 0.12)))
		Art.part(f, Art.cone(0.5), Art.glow(FLAME, 2.2), Vector3(0.0, -0.08, 0.0), Vector3(0.12, 0.3, 0.12), Vector3(PI, 0.0, 0.0))
		_flames.append(f)
	# Head: a sphere of white fire (hidden behind the face wings until it attacks).
	var head := Art.pivot(body, Vector3(0.0, 1.13, 0.0))
	# art-style round 3: face 2.6 -> 1.8, halo 3.5 -> 2.6 (wind-up bloomed out the whole model).
	_face = keep(Art.part(head, Art.sphere(), Art.glow(Art.HOLY_WHITE, 1.8), Vector3.ZERO, Vector3.ONE * 0.2))
	Art.part(head, Art.sphere(), ArtStyle.holy_glow(Art.HOLY_WHITE, FLAME, 1.2, 0.85), Vector3.ZERO, Vector3.ONE * 0.36)
	halo(body, Vector3(0.0, 1.32, 0.05), 0.2, 2.6, false, false, FLAME)
	# Flying pair (beats), face pair (crossed in front of the head), foot pair (folded down).
	solid_wing_pair(body, Vector3(0.0, 0.95, 0.1), 0.62, null, null, Art.mat(Art.GOLD, 0.5, 0.4), 0.06)
	_face_wings = animated(Art.pivot(body, Vector3(0.0, 1.12, -0.02)))
	_wing_on(_face_wings, 1.0)
	_foot_wings = animated(Art.pivot(body, Vector3(0.0, 0.4, 0.05)))
	_wing_on(_foot_wings, -1.0)
	finish()


## A static wing pair folded across the front (`up` = 1 sweeps up over the face, -1 down).
func _wing_on(root: Node3D, up: float) -> void:
	var feather := Art.mat(Art.HOLY_WHITE.darkened(0.04), 0.7, 0.0, 0.15, true, 0.35, &"feather")
	for s: float in [-1.0, 1.0]:
		var w := Art.pivot(root, Vector3(s * 0.08, 0.0, 0.0), Vector3(0.0, s * 0.35, s * up * 0.5))
		for i in 4:
			var f := float(i) / 3.0
			Art.part(w, Art.sphere(), feather, Vector3(s * (0.08 + f * 0.18), up * f * 0.05, -0.12 - f * 0.04),
					Vector3(0.09, 0.03, 0.36 - f * 0.1), Vector3(0.0, -s * (0.9 - f * 0.4), 0.0))


func pose(_delta: float) -> void:
	body.position.y = 0.2 + sin(t * 2.0) * 0.06
	body.rotation.x = -0.15 * move_w + attack_kick * 0.35
	# Face wings part during the wind-up (scale them apart sideways and up).
	var open := maxf(windup_w, attack_kick)
	_face_wings.rotation.x = -open * 1.1
	_face_wings.scale = Vector3(1.0 + open * 0.6, 1.0, 1.0)
	_foot_wings.rotation.x = sin(t * 1.3) * 0.08
	wing_amp = 0.35 + windup_w * 0.25
	wing_lift = 0.15 + windup_w * 0.45
	_face.scale = Vector3.ONE * 0.2 * (1.0 + open * 0.3 + 0.06 * sin(t * 13.0))
	for i in _flames.size():
		var k := 1.0 + 0.3 * sin(t * 11.0 + float(i) * 2.1) + windup_w * 0.6
		_flames[i].scale = Vector3(1.0, k, 1.0)
	set_halo_scale(0, 1.0 + windup_w * 0.4)
