extends ProcModel
## "Cherubim" (CHARGE): the true cherub of Ezekiel, nothing like the fat babies. A bronze-hoofed
## beast with the straight legs and broad body of an ox, four wings (two raised, two folded down
## over the body) and a single head with FOUR faces: a man's to the front, a lion's to the right,
## an ox's to the left and an eagle's behind, under one burning crown. It turns its whole head as
## it walks so every face takes a look at you. CHARGE: the wings flare, all faces blaze, then it
## gores forward like a bull.

const BRONZE_FIRE := Color(1.0, 0.6, 0.25)
const SHOULDER := 0.62

var _head: Node3D
var _crown: MeshInstance3D
var _front: Array[Node3D] = []
var _back: Array[Node3D] = []
var _head_spin := 0.0


func build() -> void:
	feather_count = 8
	debris = [&"gold"]
	debris_color = Art.BRONZE
	stride = 1.7
	wing_speed = 2.5
	wing_amp = 0.2
	wing_lift = 0.6
	var hide_m := Art.mat(Color(0.82, 0.78, 0.7), 0.6, 0.0, 0.2, true, 0.2, &"skin")
	var bronze := Art.mat(Art.BRONZE, 0.3, 0.9, 0.2, true, 0.0, &"gold")
	var skin := m_skin(Color(0.86, 0.76, 0.66))
	var fur := m_fur(Color(0.85, 0.66, 0.35))
	body = animated(Art.pivot(self, Vector3(0.0, SHOULDER, 0.0)))
	Art.part(body, Art.sphere(), hide_m, Vector3(0.0, 0.05, -0.12), Vector3(0.42, 0.42, 0.5))
	Art.part(body, Art.sphere(), hide_m, Vector3(0.0, 0.04, 0.22), Vector3(0.38, 0.38, 0.46))
	for s: float in [-1.0, 1.0]:
		_front.append(beast_leg(body, Vector3(s * 0.13, -0.08, -0.26), SHOULDER - 0.08, 0.055, hide_m, bronze, 0.0 if s < 0.0 else PI, 0.5))
		_back.append(beast_leg(body, Vector3(s * 0.13, -0.06, 0.32), SHOULDER - 0.06, 0.06, hide_m, bronze, PI if s < 0.0 else 0.0, 0.5, true))
	# Four wings: two raised (flapping) and two folded down along the flanks.
	solid_wing_pair(body, Vector3(0.0, 0.25, -0.05), 0.8, null, Art.mat(Art.BRONZE, 0.4, 0.6), null, 0.12)
	for s: float in [-1.0, 1.0]:
		var fw := Art.pivot(body, Vector3(s * 0.2, 0.15, -0.1), Vector3(0.0, 0.0, s * 1.3))
		Art.part(fw, Art.sphere(), Art.mat(Art.HOLY_WHITE.darkened(0.08), 0.7, 0.0, 0.15, true, 0.3, &"feather"),
				Vector3(s * 0.25, 0.0, 0.18), Vector3(0.5, 0.04, 0.55))
	# The four-faced head on a thick neck. Faces sit on the four sides of one block.
	_head = animated(Art.pivot(body, Vector3(0.0, 0.35, -0.42)))
	Art.part(_head, Art.sphere(), hide_m, Vector3.ZERO, Vector3(0.3, 0.3, 0.3))
	# Man (front, -Z): a calm human face.
	Art.part(_head, Art.sphere(), skin, Vector3(0.0, 0.0, -0.13), Vector3(0.18, 0.22, 0.1))
	for s: float in [-1.0, 1.0]:
		Art.part(_head, Art.sphere(), Art.glow(Art.HOLY_WHITE, 2.0), Vector3(s * 0.04, 0.03, -0.18), Vector3(0.035, 0.02, 0.015))
	# Lion (right, +X): mane ring and a muzzle.
	for i in 8:
		var a := TAU * float(i) / 8.0
		Art.part(_head, Art.sphere(), fur, Vector3(0.14, sin(a) * 0.1, cos(a) * 0.1), Vector3(0.06, 0.08, 0.08))
	Art.part(_head, Art.sphere(), fur, Vector3(0.18, -0.02, 0.0), Vector3(0.1, 0.1, 0.12))
	# Ox (left, -X): a broad muzzle and two horns.
	Art.part(_head, Art.sphere(), hide_m, Vector3(-0.17, -0.03, 0.0), Vector3(0.12, 0.12, 0.15))
	for z: float in [-0.07, 0.07]:
		Art.part(_head, Art.cone(0.5), Art.mat(Art.IVORY, 0.4), Vector3(-0.12, 0.13, z), Vector3(0.04, 0.16, 0.04), Vector3(z * 6.0, 0.0, 0.6))
	# Eagle (back, +Z): a hooked gold beak and white feathers.
	Art.part(_head, Art.sphere(), Art.mat(Art.HOLY_WHITE, 0.7, 0.0, 0.1, true, 0.3, &"feather"), Vector3(0.0, 0.02, 0.13), Vector3(0.18, 0.18, 0.1))
	Art.part(_head, Art.cone(0.5), m_gold(), Vector3(0.0, -0.01, 0.22), Vector3(0.06, 0.12, 0.07), Vector3(PI * 0.5 + 0.35, 0.0, 0.0))
	# Burning crown over all four.
	_crown = keep(Art.part(_head, Art.torus(0.75, 1.0), Art.glow(BRONZE_FIRE, 2.2), Vector3(0.0, 0.2, 0.0), Vector3.ONE * 0.15))
	finish()


func pose(delta: float) -> void:
	var gore := windup_w
	var rush := strike_w
	body.position.y = SHOULDER + absf(sin(walk)) * 0.04 * (move_w + rush) - gore * 0.04
	body.rotation.x = -rush * 0.12 + gore * 0.08
	# The head slowly turns through all four faces; it snaps forward (the man's face) to charge.
	_head_spin += delta * 0.6 * (1.0 - maxf(gore, rush))
	var yaw := fposmod(_head_spin, TAU)
	_head.rotation.y = lerp_angle(yaw, 0.0, maxf(gore, rush))
	_head.rotation.x = rush * 0.4 + gore * 0.2
	wing_lift = 0.6 + gore * 0.5 - rush * 0.5
	wing_amp = 0.2 + gore * 0.15
	for l in _front:
		l.rotation.x += gore * sin(t * 12.0) * 0.25  # pawing the ground
	_crown.scale = Vector3.ONE * 0.15 * (1.0 + gore * 0.6 + 0.08 * sin(t * 9.0))
	eye_flare = maxf(eye_flare, gore)


## Ragdoll death (characters-polish DeathFx): the pivots that flop loose.
func ragdoll_limbs() -> Array:
	return limbs_with([_head])
