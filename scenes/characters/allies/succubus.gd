extends DemonKit
## "Succubus": a tall, poised temptress of the Pit with ash-violet skin, swept-back ram horns, long
## black hair, a high-collared crimson gown slit at the side, a spade-tipped tail and great bat
## wings held half-open. Allies: a charming caster (wind-up: raises a palm of violet fire; attack
## kick: casts it). Basecamp: idle gestures (a beckoning hand, a wing stretch).
## `barkeep = true` (the Infernal Bar, npcs/infernal_bar.gd): a goblet in the left hand and a
## rag in the right, polishing behind the counter; gesture 0 slides a drink across, 1 a wing stretch.

## Barkeep variant (holds a goblet and a rag; polishing idle).
@export var barkeep := false

const HIP := 0.62
# Soul-rose rather than magenta: stays in the infernal palette (docs/team/art-style.md).
const CHARM := Color(0.95, 0.25, 0.42)

var _torso: Node3D
var _head: Node3D
var _hair: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _palm: MeshInstance3D


func build() -> void:
	light_color = CHARM
	stride = 1.3
	idle_gesture_every = 5.0
	var skin := m_skin(Color(0.55, 0.38, 0.5))
	var gown := Art.mat(Color(0.45, 0.04, 0.07), 0.45, 0.0, 0.2, true, 0.6, &"cloth")
	var horn := Art.mat(Color(0.12, 0.1, 0.12), 0.35, 0.0, 0.2, true, 0.0, &"bone")
	var hair := Art.mat(Color(0.05, 0.04, 0.06), 0.5, 0.0, 0.1, true, 0.6, &"cloth")
	_torso = biped(HIP, 0.04, skin, Art.mat(Art.OBSIDIAN, 0.3, 0.6), 0.07, 0.4)
	# Gown: a fitted bodice and a long skirt open at the side (one leg shows).
	Art.part(body, Art.cylinder(0.13, 0.22), gown, Vector3(-0.03, -0.26, 0.0), Vector3(0.8, 0.56, 0.9))
	Art.part(_torso, Art.cylinder(0.14, 0.11), gown, Vector3(0.0, 0.17, 0.0), Vector3(1.0, 0.36, 0.75))
	Art.part(_torso, Art.sphere(), gown, Vector3(0.0, 0.3, -0.02), Vector3(0.26, 0.16, 0.18))
	# High stiff collar fanning behind the neck.
	Art.part(_torso, Art.cone(0.5), gown, Vector3(0.0, 0.47, 0.06), Vector3(0.3, 0.22, 0.05), Vector3(-0.3, 0.0, 0.0))
	Art.part(_torso, Art.cylinder(0.5, 0.5), m_gold(), Vector3(0.0, 0.02, 0.0), Vector3(0.26, 0.03, 0.2))
	_head = animated(Art.pivot(_torso, Vector3(0.0, 0.5, 0.0)))
	Art.part(_head, Art.sphere(), skin, Vector3.ZERO, Vector3(0.14, 0.18, 0.15))
	Art.part(_head, Art.cone(0.5), skin, Vector3(0.0, -0.07, -0.02), Vector3(0.1, 0.08, 0.1), Vector3(PI, 0.0, 0.0))
	ember_eyes(_head, Vector3(0.035, 0.015, -0.068), 0.035, CHARM)
	Art.part(_head, Art.sphere(), Art.mat(Color(0.3, 0.02, 0.08), 0.3), Vector3(0.0, -0.05, -0.068), Vector3(0.035, 0.012, 0.01))
	horns(_head, Vector3(0.05, 0.07, 0.01), 0.18, 0.025, horn, 1.4, 0.35)
	_hair = animated(Art.pivot(_head, Vector3(0.0, 0.04, 0.05)))
	Art.part(_hair, Art.sphere(), hair, Vector3(0.0, 0.0, 0.0), Vector3(0.16, 0.16, 0.14))
	for i in 4:
		Art.part(_hair, Art.box(), hair, Vector3(0.0, -0.1 - i * 0.07, 0.02 + i * 0.01), Vector3(0.15 - i * 0.015, 0.1, 0.04))
	bat_wing_pair(_torso, Vector3(0.0, 0.33, 0.1), 0.9, horn, Art.mat(Color(0.25, 0.04, 0.12), 0.7, 0.0, 0.3, true, 0.3, &"leather"))
	tail(body, Vector3(0.0, -0.02, 0.1), 0.55, 0.018, skin, horn)
	var a := arm(_torso, Vector3(-0.16, 0.34, 0.0), 0.4, 0.03, skin, skin, 0.0, 0.0)
	_arm_l = a[0]
	var b := arm(_torso, Vector3(0.16, 0.34, 0.0), 0.4, 0.03, skin, skin, 0.0, 0.0)
	_arm_r = b[0]
	_palm = keep(Art.part(b[1], Art.sphere(), Art.glow(CHARM, 2.4), Vector3(0.0, -0.06, -0.02), Vector3.ONE * 0.08))
	if barkeep:
		# Black-glass goblet with something glowing in it, and a polishing rag.
		var glass := Art.mat(Color(0.1, 0.05, 0.08), 0.1, 0.0, 0.0, true, 0.9, &"crystal")
		Art.part(a[1], Art.cylinder(0.5, 0.3), glass, Vector3(0.0, 0.06, -0.03), Vector3(0.07, 0.08, 0.07))
		Art.part(a[1], Art.cylinder(0.5, 0.5), glass, Vector3(0.0, 0.0, -0.03), Vector3(0.015, 0.06, 0.015))
		Art.part(a[1], Art.cylinder(0.5, 0.5), Art.glow(Color(0.9, 0.15, 0.25), 1.6), Vector3(0.0, 0.09, -0.03), Vector3(0.06, 0.01, 0.06))
		Art.part(b[1], Art.sphere(), m_cloth(Color(0.8, 0.76, 0.68)), Vector3(0.0, -0.04, -0.02), Vector3(0.08, 0.05, 0.1))
	finish()


func bake_variant() -> String:
	return "barkeep" if barkeep else ""


func pose(_delta: float) -> void:
	biped_bob(HIP, 0.03)
	if barkeep:
		_pose_barkeep()
		return
	var cast := maxf(windup_w, attack_kick)
	# Hip sway and a slow, poised idle.
	body.rotation.z = sin(walk) * 0.06 * move_w + sin(t * 0.9) * 0.03 * (1.0 - move_w)
	_torso.rotation.y = sin(walk) * 0.15 * move_w + sin(t * 0.7) * 0.06
	_head.rotation = Vector3(sin(t * 0.6) * 0.06, sin(t * 0.5) * 0.25, 0.1 * sin(t * 0.4))
	_hair.rotation.x = 0.2 * move_w + sin(t * 1.4) * 0.05
	flap(2.5 + cast * 6.0, 0.08 + cast * 0.3 + (0.35 if gesture_id == 1 else 0.0) * gesture_w, 0.5 - cast * 0.5 - (0.5 if gesture_id == 1 else 0.0) * gesture_w)
	sway_tail(0.25, 1.6)
	# Left hand on the hip; right hand beckons (gesture 0) or raises a palm of fire (cast).
	_arm_l.rotation = Vector3(0.2 - sin(walk) * 0.25 * move_w, 0.0, -0.5)
	var beckon := gesture_w if gesture_id == 0 else 0.0
	var r := Vector3(0.2 + sin(walk) * 0.25 * move_w, 0.0, 0.15)
	r = mixv(r, Vector3(1.3, -0.2, 0.2 + sin(t * 6.0) * 0.15), beckon)
	r = mixv(r, Vector3(1.6 + attack_kick * 0.4, -0.1, 0.1), cast)
	_arm_r.rotation = r
	_palm.scale = Vector3.ONE * (0.02 + cast * 0.1 + beckon * 0.03)


## Behind the counter: goblet held at the bar, the rag circling inside it; gesture 0 slides a
## drink forward across the counter, gesture 1 stretches the wings.
func _pose_barkeep() -> void:
	var slide := gesture_w if gesture_id == 0 else 0.0
	var stretch := gesture_w if gesture_id == 1 else 0.0
	body.rotation.z = sin(t * 0.9) * 0.03
	_torso.rotation = Vector3(-0.15 - slide * 0.2, sin(t * 0.4) * 0.1, 0.0)
	_head.rotation = Vector3(0.15 + sin(t * 0.6) * 0.05, sin(t * 0.35) * 0.3, 0.12 * sin(t * 0.5))
	_hair.rotation.x = sin(t * 1.4) * 0.05
	flap(2.0, 0.06 + stretch * 0.4, 0.6 - stretch * 0.7)
	sway_tail(0.25, 1.4)
	_arm_l.rotation = mixv(Vector3(1.0, 0.5, -0.1), Vector3(1.45, 0.1, 0.0), slide)
	var c := t * 4.0
	_arm_r.rotation = Vector3(1.1 + sin(c) * 0.12, -0.5 + cos(c) * 0.12, 0.2) * (1.0 - slide) + Vector3(0.3, 0.0, 0.15) * slide
	_palm.scale = Vector3.ONE * 0.001
