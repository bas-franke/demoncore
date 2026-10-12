extends ProcModel
## "Archangel" (elite, SLAM): a general of the Host. Tall, in gold-chased plate over a white
## surcoat, a crested sallet helm with a burning visor slit, a red-gold cape, two pairs of great
## wings and a flaming two-handed sword. SLAM: the wind-up hauls the sword overhead while the
## wings flare and the halo swells; the strike brings it down into the lit circle; it then
## holds the blade in the ground (recover) before heaving it out.

# Holy fire: gold-white, never hellfire orange (docs/team/art-style.md palette).
const BLADE_FIRE := Color(1.0, 0.82, 0.5)

## Kneeling pose (cutscenes, e.g. the story ending's Archons on the stairs): one knee down, the
## sword planted point-first before it with both hands on the pommel, head bowed, wings folded
## down, halo dimmed. Set before adding to the tree, or any time (it blends in over ~0.5 s).
@export var kneeling := false

var _kneel := 0.0
var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _sword: Node3D
var _blade: MeshInstance3D
var _cape: Node3D


func build() -> void:
	_kneel = 1.0 if kneeling else 0.0  # start knelt when placed knelt (no stand-up blend)
	feather_count = 8
	debris = [&"gold", &"steel"]
	debris_color = Art.GOLD
	wing_speed = 2.2
	wing_amp = 0.18
	wing_lift = 0.35
	wing_sweep = 0.35
	stride = 1.6
	var plate := Art.mat(Color(0.88, 0.84, 0.74), 0.35, 0.75, 0.2, true, 0.0, &"metal")
	var gold := m_gold()
	var cloth := m_cloth(Art.HOLY_WHITE.darkened(0.1))
	var cape_mat := m_cloth(Color(0.55, 0.1, 0.08))
	body = animated(Art.pivot(self, Vector3(0.0, 0.78, 0.0)))
	# Hips / faulds and the surcoat skirt.
	Art.part(body, Art.cylinder(0.17, 0.26), cloth, Vector3(0.0, -0.18, 0.0), Vector3(1.0, 0.42, 0.85))
	Art.part(body, Art.cylinder(0.5, 0.5), gold, Vector3(0.0, 0.02, 0.0), Vector3(0.36, 0.05, 0.3))
	for s: float in [-1.0, 1.0]:
		leg(self, Vector3(s * 0.1, 0.72, 0.0), 0.72, 0.065, plate, gold, 0.0 if s < 0.0 else PI, 0.45)
	_torso = animated(Art.pivot(body, Vector3(0.0, 0.05, 0.0)))
	# Breastplate (a squashed sphere over a box) with a gold sunburst.
	Art.part(_torso, Art.cylinder(0.24, 0.16), plate, Vector3(0.0, 0.2, 0.0), Vector3(1.0, 0.4, 0.7))
	Art.part(_torso, Art.sphere(), plate, Vector3(0.0, 0.28, -0.04), Vector3(0.42, 0.3, 0.28))
	# Gold sunburst on the breast: a disc and rays.
	Art.part(_torso, Art.cylinder(0.5, 0.5), gold, Vector3(0.0, 0.28, -0.175), Vector3(0.08, 0.02, 0.08), Vector3(PI * 0.5, 0.0, 0.0))
	for i in 6:
		var ang := TAU * float(i) / 6.0
		Art.part(_torso, Art.box(), gold, Vector3(cos(ang) * 0.07, 0.28 + sin(ang) * 0.07, -0.17), Vector3(0.07, 0.015, 0.015), Vector3(0.0, 0.0, ang))
	for s: float in [-1.0, 1.0]:
		# Pauldrons.
		Art.part(_torso, Art.sphere(), plate, Vector3(s * 0.23, 0.38, 0.0), Vector3(0.2, 0.15, 0.22))
		Art.part(_torso, Art.torus(0.8, 1.0), gold, Vector3(s * 0.23, 0.36, 0.0), Vector3(0.11, 0.1, 0.12))
	_head = animated(Art.pivot(_torso, Vector3(0.0, 0.48, 0.0)))
	# Sallet helm with a burning visor slit and a tall crest.
	Art.part(_head, Art.sphere(), plate, Vector3(0.0, 0.06, 0.0), Vector3(0.22, 0.24, 0.26))
	Art.part(_head, Art.box(), Art.glow(BLADE_FIRE, 2.6), Vector3(0.0, 0.06, -0.125), Vector3(0.14, 0.02, 0.02))
	Art.part(_head, Art.box(), gold, Vector3(0.0, 0.2, 0.02), Vector3(0.03, 0.12, 0.28))
	halo(_head, Vector3(0.0, 0.08, 0.2), 0.22, 3.2, true, true)
	# Cape hanging from the shoulders (sways).
	_cape = animated(Art.pivot(_torso, Vector3(0.0, 0.4, 0.13)))
	Art.part(_cape, Art.box(), cape_mat, Vector3(0.0, -0.45, 0.02), Vector3(0.44, 0.9, 0.03))
	Art.part(_cape, Art.box(), gold, Vector3(0.0, -0.9, 0.02), Vector3(0.46, 0.03, 0.04))
	# Two pairs of wings (upper great pair, lower smaller pair).
	solid_wing_pair(_torso, Vector3(0.0, 0.36, 0.14), 1.0, null, Art.mat(Art.GOLD, 0.45, 0.6, 0.2, true, 0.0, &"gold"), null, 0.1)
	solid_wing_pair(_torso, Vector3(0.0, 0.16, 0.14), 0.6, null, null, null, 0.1)
	var a := arm(_torso, Vector3(-0.27, 0.34, 0.0), 0.5, 0.055, plate, gold, 0.0, 0.0)
	_arm_l = a[0]
	var b := arm(_torso, Vector3(0.27, 0.34, 0.0), 0.5, 0.055, plate, gold, 0.0, 0.0)
	_arm_r = b[0]
	# Flaming greatsword in the right hand (the hand pivot's -Y runs down the arm; the blade
	# points forward, -Z, from it at rest).
	_sword = animated(Art.pivot(b[1], Vector3.ZERO, Vector3(-PI * 0.5, 0.0, 0.0)))
	Art.part(_sword, Art.cylinder(0.5, 0.5), m_leather(), Vector3(0.0, 0.0, 0.0), Vector3(0.04, 0.24, 0.04))
	Art.part(_sword, Art.box(), gold, Vector3(0.0, 0.13, 0.0), Vector3(0.3, 0.04, 0.06))
	Art.part(_sword, Art.sphere(), gold, Vector3(0.0, -0.13, 0.0), Vector3.ONE * 0.07)
	_blade = keep(Art.part(_sword, Art.box(), Art.emissive(Art.HOLY_WHITE, BLADE_FIRE, 2.2), Vector3(0.0, 0.72, 0.0), Vector3(0.08, 1.1, 0.025)))
	Art.part(_sword, Art.box(), Art.glow(BLADE_FIRE, 0.6), Vector3(0.0, 0.72, 0.0), Vector3(0.18, 1.15, 0.08))
	finish()


func pose(delta: float) -> void:
	_kneel = damp(_kneel, 1.0 if kneeling else 0.0, 4.0, delta) if delta > 0.0 else _kneel
	if _kneel > 0.001:
		_pose_kneel()
		return
	# Heavy stride; lean forward walking.
	body.position.y = 0.78 + absf(sin(walk)) * 0.04 * move_w - recover_w * 0.12
	_torso.rotation.x = -0.12 * move_w + windup_w * 0.25 - strike_w * 0.45 - recover_w * 0.35
	_torso.rotation.y = sin(walk) * 0.12 * move_w
	_head.rotation.x = -_torso.rotation.x * 0.5
	_cape.rotation.x = 0.2 * move_w + sin(t * 2.0) * 0.05 + windup_w * 0.2
	# Sword: carried low and forward at rest, hauled overhead in the wind-up, struck down.
	var rest := deg(35.0, 0.0, 10.0) + Vector3(sin(walk) * 0.15 * move_w, 0.0, 0.0)
	var up := deg(200.0, 0.0, 15.0)
	var down := deg(70.0, 0.0, 5.0)
	var r := mixv(rest, up, windup_w)
	r = mixv(r, down, maxf(strike_w, recover_w))
	_arm_r.rotation = r
	# Left hand joins the grip when the sword is raised, otherwise swings.
	var l_rest := Vector3(-sin(walk) * 0.35 * move_w, 0.0, -0.15)
	_arm_l.rotation = mixv(l_rest, r + Vector3(0.0, 0.0, -0.35), maxf(windup_w, maxf(strike_w, recover_w)) * 0.9)
	wing_lift = 0.35 + windup_w * 0.55
	wing_amp = 0.18 + windup_w * 0.2
	set_halo_scale(0, 1.0 + windup_w * 0.5)
	EnemyModel.glow(_blade, windup_w * 0.6 + strike_w * 0.8)
	if delta > 0.0 and strike_w > 0.5:
		eye_flare = 1.0


## Knelt: hips sunk, front leg forward (knee up), back leg back (knee on the ground), torso and head
## bowed over the sword planted point-down in front, both hands on the pommel, wings folded down.
func _pose_kneel() -> void:
	var k := _kneel
	plant_feet = k < 0.5
	body.position.y = lerpf(0.78, 0.4, k)
	for i in _legs.size():
		var front := i == 0
		_legs[i].position.y = body.position.y - 0.06
		_legs[i].rotation = Vector3(lerpf(0.0, 1.05 if front else -1.15, k), 0.0, 0.0)
		_legs[i].scale = Vector3.ONE
	_torso.rotation = Vector3(lerpf(0.0, -0.55, k), 0.0, 0.0)
	_head.rotation = Vector3(lerpf(0.0, 0.45, k), 0.0, 0.0)
	_cape.rotation.x = lerpf(0.0, -0.35, k)
	_arm_r.rotation = mixv(Vector3(0.6, 0.0, 0.1), Vector3(0.95, 0.0, -0.25), k)
	_arm_l.rotation = mixv(Vector3(0.0, 0.0, -0.15), Vector3(0.95, 0.0, 0.25), k)
	_sword.rotation.x = lerp_angle(-PI * 0.5, -PI, k)
	wing_lift = lerpf(0.35, -0.35, k)
	wing_sweep = lerpf(0.35, 0.95, k)
	wing_amp = lerpf(0.18, 0.02, k)
	set_halo_scale(0, lerpf(1.0, 0.75, k))
	EnemyModel.glow(_blade, 0.05)
