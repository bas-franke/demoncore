extends DemonKit
## "Duchess Malphine of the Ashen Court" (Basecamp NPC): a tall, ancient demon noblewoman. Ash-grey
## skin, a crown of black horns grown into a circlet of iron spikes, a sweeping court gown of
## black and ember-red with a long train and a stiff fan collar, a lace veil over the lower face,
## a scepter topped with a caged soul-flame and slow embers drifting round her. ~2.1 m tall.
## Gestures: 0 = a regal turn of the scepter hand (talk), 1 = she raises the scepter, the flame
## flares. Drives itself when placed outside an Enemy (see ProcModel.autoplay).

const FLAME := Color(1.0, 0.35, 0.15)

var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _flame: MeshInstance3D
var _embers: Array[Node3D] = []


func build() -> void:
	idle_gesture_every = 6.0
	var skin := m_skin(Color(0.45, 0.43, 0.44))
	var gown := Art.mat(Color(0.05, 0.04, 0.05), 0.5, 0.0, 0.2, true, 0.5, &"cloth")
	var red := Art.mat(Color(0.5, 0.06, 0.04), 0.45, 0.0, 0.2, true, 0.6, &"cloth")
	var iron := m_metal(Color(0.15, 0.14, 0.15), 0.4)
	var horn := Art.mat(Color(0.06, 0.05, 0.06), 0.3, 0.0, 0.1, true, 0.0, &"bone")
	body = animated(Art.pivot(self))
	# Wide bell skirt with a red under-panel and a long train behind.
	Art.part(body, Art.cylinder(0.2, 0.5), gown, Vector3(0.0, 0.48, 0.03), Vector3(1.0, 0.96, 1.0))
	Art.part(body, Art.box(), red, Vector3(0.0, 0.4, -0.37), Vector3(0.26, 0.8, 0.02), Vector3(0.3, 0.0, 0.0))
	Art.part(body, Art.box(), gown, Vector3(0.0, 0.02, 0.6), Vector3(0.7, 0.03, 0.7))
	Art.part(body, Art.cylinder(0.5, 0.5), m_gold(), Vector3(0.0, 0.94, 0.0), Vector3(0.42, 0.04, 0.42))
	_torso = animated(Art.pivot(body, Vector3(0.0, 0.96, 0.0)))
	Art.part(_torso, Art.cylinder(0.17, 0.13), gown, Vector3(0.0, 0.2, 0.0), Vector3(1.0, 0.42, 0.75))
	Art.part(_torso, Art.box(), red, Vector3(0.0, 0.18, -0.105), Vector3(0.12, 0.36, 0.02))
	# Stiff fan collar rising behind the head.
	for i in 7:
		var ang := -0.9 + 0.3 * float(i)
		Art.part(_torso, Art.box(), red if i % 2 == 0 else gown, Vector3(sin(ang) * 0.14, 0.58, 0.1 + cos(ang) * 0.02),
				Vector3(0.07, 0.4, 0.015), Vector3(-0.25, 0.0, -ang * 0.8))
	for s: float in [-1.0, 1.0]:
		Art.part(_torso, Art.sphere(), gown, Vector3(s * 0.17, 0.38, 0.0), Vector3(0.16, 0.12, 0.15))
	_head = animated(Art.pivot(_torso, Vector3(0.0, 0.56, 0.0)))
	Art.part(_head, Art.sphere(), skin, Vector3.ZERO, Vector3(0.15, 0.19, 0.16))
	limb(_head, Vector3(0.0, -0.18, 0.0), Vector3(0.0, -0.06, 0.0), 0.04, skin)
	# Lace veil over mouth and chin.
	Art.part(_head, Art.sphere(), Art.mat(Color(0.08, 0.06, 0.07), 0.6, 0.0, 0.1, true, 0.4, &"cloth"), Vector3(0.0, -0.05, -0.03), Vector3(0.15, 0.1, 0.14))
	ember_eyes(_head, Vector3(0.035, 0.02, -0.07), 0.035, FLAME)
	# Crown: tall horns rising from an iron spike circlet.
	horns(_head, Vector3(0.05, 0.07, 0.0), 0.3, 0.025, horn, 0.4, 0.15)
	Art.part(_head, Art.torus(0.85, 1.0), iron, Vector3(0.0, 0.08, 0.0), Vector3.ONE * 0.09)
	for i in 7:
		var ang := TAU * float(i) / 7.0
		Art.part(_head, Art.cone(0.5), iron, Vector3(cos(ang) * 0.085, 0.13, sin(ang) * 0.085), Vector3(0.02, 0.08 + 0.03 * float(i % 2), 0.02))
	var a := arm(_torso, Vector3(-0.18, 0.36, 0.0), 0.42, 0.03, gown, skin, 0.0, 0.0)
	_arm_l = a[0]
	# Long hanging sleeve.
	Art.part(a[0], Art.cone(0.5), red, Vector3(0.0, -0.32, 0.02), Vector3(0.12, 0.3, 0.12))
	var b := arm(_torso, Vector3(0.18, 0.36, 0.0), 0.42, 0.03, gown, skin, 0.0, 0.0)
	_arm_r = b[0]
	Art.part(b[0], Art.cone(0.5), red, Vector3(0.0, -0.32, 0.02), Vector3(0.12, 0.3, 0.12))
	# Scepter with a caged flame.
	var sc := Art.pivot(b[1], Vector3.ZERO, Vector3(PI, 0.0, 0.0))
	limb(sc, Vector3(0.0, -0.2, 0.0), Vector3(0.0, 0.5, 0.0), 0.012, m_gold())
	for k in 4:
		var d := Vector3(cos(TAU * k / 4.0), 0.0, sin(TAU * k / 4.0)) * 0.05
		limb(sc, Vector3(0.0, 0.5, 0.0) + d * 0.3, Vector3(0.0, 0.6, 0.0) + d, 0.005, iron)
		limb(sc, Vector3(0.0, 0.6, 0.0) + d, Vector3(0.0, 0.7, 0.0), 0.005, iron)
	_flame = keep(Art.part(sc, Art.sphere(), Art.glow(FLAME, 2.6), Vector3(0.0, 0.6, 0.0), Vector3.ONE * 0.06))
	# Slow embers orbiting her.
	for i in 4:
		var e := animated(Art.pivot(body))
		Art.part(e, Art.sphere(), Art.glow(Art.EMBER, 2.4), Vector3(0.5, 0.0, 0.0), Vector3.ONE * 0.025)
		_embers.append(e)
	finish()


func pose(_delta: float) -> void:
	var talk_w := gesture_w if gesture_id == 0 else 0.0
	var raise := gesture_w if gesture_id == 1 else 0.0
	body.rotation.z = sin(t * 0.5) * 0.015
	_torso.rotation.x = 0.04 + sin(t * 0.9) * 0.015 - raise * 0.05
	_torso.rotation.y = talk_w * 0.2
	_head.rotation = Vector3(-0.05 + sin(t * 0.4) * 0.04, sin(t * 0.3) * 0.2 + talk_w * 0.2, 0.0)
	# Left hand folded at the waist; scepter hand turns while she speaks, raised high on gesture 1.
	_arm_l.rotation = Vector3(0.7, 0.4, -0.15)
	var r := Vector3(0.35, -0.1, 0.12)
	r = mixv(r, Vector3(0.9 + sin(t * 3.0) * 0.15, -0.4, 0.3), talk_w)
	r = mixv(r, Vector3(2.5, 0.0, 0.2), raise)
	_arm_r.rotation = r
	_flame.scale = Vector3.ONE * 0.06 * (1.0 + raise * 1.2 + 0.15 * sin(t * 7.0))
	for i in _embers.size():
		var e := _embers[i]
		e.rotation.y = t * (0.3 + 0.07 * float(i)) + float(i) * 1.6
		e.position.y = 0.4 + float(i) * 0.35 + sin(t * 0.8 + float(i)) * 0.15
