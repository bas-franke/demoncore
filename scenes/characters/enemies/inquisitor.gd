extends ProcModel
## "Inquisitor" (SHOOT, holy bolts): a gaunt witch-hunter in a wide-brimmed capotain hat, a long
## black greatcoat with a white falling collar, a silver holy symbol on a chain and a heavy
## repeating crossbow. SHOOT: shoulders the crossbow and sights down it (wind-up), the stock
## kicks back on the shot; the coat tails swing as it backs away.
## `grand = true`: the Grand Inquisitor, Judge of the Seventh Gate (elite): a scarlet cassock with
## gold trim and a tall gilt mitre instead of the hat, and a brighter lantern.

## Grand Inquisitor variant (elite look).
@export var grand := false

const HIP := 0.5

var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _coat: Node3D
var _lamp: MeshInstance3D


func build() -> void:
	feather_count = 0
	mote_count = 4
	death_style = &"topple"
	# Grand: bleached ivory (red belongs to the demon side, docs/team/art-style.md).
	var coat := m_cloth(Color(0.82, 0.78, 0.68) if grand else Color(0.08, 0.07, 0.08))
	var boots := m_leather(Color(0.12, 0.08, 0.06))
	var white := m_cloth(Color(0.9, 0.88, 0.82))
	var skin := m_skin(Color(0.78, 0.68, 0.6))
	_torso = biped(HIP, 0.045, m_cloth(Color(0.15, 0.13, 0.13)), boots, 0.08, 0.5)
	# Greatcoat skirt (swings), body, collar, belt with a buckle.
	_coat = animated(Art.pivot(body, Vector3(0.0, 0.05, 0.0)))
	Art.part(_coat, Art.cylinder(0.16, 0.25), coat, Vector3(0.0, -0.22, 0.02), Vector3(1.0, 0.48, 0.9))
	Art.part(_torso, Art.cylinder(0.19, 0.15), coat, Vector3(0.0, 0.22, 0.0), Vector3(1.0, 0.46, 0.75))
	Art.part(_torso, Art.cylinder(0.5, 0.5), m_leather(), Vector3(0.0, 0.02, 0.0), Vector3(0.32, 0.05, 0.25))
	Art.part(_torso, Art.box(), m_metal(Art.STEEL, 0.3), Vector3(0.0, 0.02, -0.13), Vector3(0.06, 0.05, 0.02))
	Art.part(_torso, Art.cylinder(0.12, 0.2), white, Vector3(0.0, 0.42, 0.0), Vector3(1.0, 0.07, 0.85))
	# Holy symbol: silver ring and cross on the chest.
	Art.part(_torso, Art.torus(0.75, 1.0), m_metal(Color(0.8, 0.8, 0.82), 0.25), Vector3(0.0, 0.3, -0.115), Vector3.ONE * 0.05, Vector3(PI * 0.5, 0.0, 0.0))
	_head = animated(Art.pivot(_torso, Vector3(0.0, 0.53, 0.0)))
	Art.part(_head, Art.sphere(), skin, Vector3(0.0, 0.0, 0.0), Vector3(0.16, 0.2, 0.17))
	Art.part(_head, Art.cone(0.5), skin, Vector3(0.0, -0.01, -0.09), Vector3(0.04, 0.07, 0.05), Vector3(-PI * 0.5, 0.0, 0.0))
	# Hard, pale eyes under the brim.
	for s: float in [-1.0, 1.0]:
		Art.part(_head, Art.sphere(), Art.glow(Art.HOLY_WHITE, 1.4), Vector3(s * 0.04, 0.02, -0.075), Vector3(0.03, 0.015, 0.02))
	if grand:
		# Gilt mitre: two tall peaked plates with a cross, lappets behind; gold trim on the coat.
		var gold := m_gold()
		for z: float in [-0.02, 0.02]:
			Art.part(_head, Art.prism(), Art.mat(Art.IVORY, 0.5, 0.1, 0.1, true, 0.3, &"cloth"), Vector3(0.0, 0.2, z), Vector3(0.17, 0.3, 0.03))
		Art.part(_head, Art.box(), gold, Vector3(0.0, 0.18, -0.04), Vector3(0.025, 0.14, 0.01))
		Art.part(_head, Art.box(), gold, Vector3(0.0, 0.2, -0.04), Vector3(0.09, 0.025, 0.01))
		Art.part(_head, Art.cylinder(0.5, 0.5), gold, Vector3(0.0, 0.08, 0.0), Vector3(0.18, 0.04, 0.18))
		Art.part(_torso, Art.box(), gold, Vector3(0.0, 0.2, -0.1), Vector3(0.05, 0.42, 0.02))
		Art.part(_coat, Art.cylinder(0.25, 0.25), gold, Vector3(0.0, -0.45, 0.02), Vector3(1.01, 0.03, 0.91))
		Art.part(_torso, Art.cylinder(0.12, 0.2), m_cloth(Color(0.9, 0.88, 0.8)), Vector3(0.0, 0.42, 0.0), Vector3(1.05, 0.09, 0.9))
	else:
		_capotain(coat)
	var a := arm(_torso, Vector3(-0.2, 0.38, 0.0), 0.4, 0.042, coat, m_leather(), 0.0, 0.0)
	_arm_l = a[0]
	# Hanging lantern of holy light in the left hand.
	var ln := Art.pivot(a[1], Vector3(0.0, -0.08, 0.0))
	Art.part(ln, Art.cylinder(0.4, 0.5), m_metal(Art.BRONZE, 0.4), Vector3(0.0, 0.0, 0.0), Vector3(0.09, 0.03, 0.09))
	_lamp = keep(Art.part(ln, Art.sphere(), Art.glow(Art.HOLY, 2.5), Vector3(0.0, -0.06, 0.0), Vector3(0.07, 0.09, 0.07)))
	Art.part(ln, Art.cylinder(0.5, 0.4), m_metal(Art.BRONZE, 0.4), Vector3(0.0, -0.12, 0.0), Vector3(0.09, 0.03, 0.09))
	var b := arm(_torso, Vector3(0.2, 0.38, 0.0), 0.4, 0.042, coat, m_leather(), 0.0, 0.0)
	_arm_r = b[0]
	# Repeating crossbow: stock along the hand's forward, steel prod across, a bolt laid in.
	var cb := Art.pivot(b[1], Vector3(0.0, 0.0, 0.0), Vector3(-PI * 0.5, 0.0, 0.0))
	Art.part(cb, Art.box(), m_wood(), Vector3(0.0, 0.18, 0.0), Vector3(0.05, 0.46, 0.06))
	Art.part(cb, Art.box(), m_wood(), Vector3(0.0, 0.24, 0.04), Vector3(0.06, 0.22, 0.06))
	var prod := m_metal(Art.STEEL.darkened(0.2), 0.4)
	for s: float in [-1.0, 1.0]:
		Art.part(cb, Art.box(), prod, Vector3(s * 0.13, 0.38, -0.01), Vector3(0.26, 0.025, 0.025), Vector3(0.0, 0.0, -s * 0.35))
	Art.part(cb, Art.box(), Art.mat(Art.GOLD, 0.3, 1.0), Vector3(0.0, 0.45, -0.035), Vector3(0.015, 0.14, 0.015))
	finish()


## Capotain: tall tapering crown, wide brim, buckle band.
func _capotain(coat: Material) -> void:
	Art.part(_head, Art.cylinder(0.5, 0.5), coat, Vector3(0.0, 0.08, 0.0), Vector3(0.5, 0.015, 0.5))
	Art.part(_head, Art.cylinder(0.42, 0.5), coat, Vector3(0.0, 0.2, 0.0), Vector3(0.2, 0.24, 0.2))
	Art.part(_head, Art.cylinder(0.5, 0.5), m_leather(), Vector3(0.0, 0.12, 0.0), Vector3(0.205, 0.035, 0.205))
	Art.part(_head, Art.box(), m_metal(Art.STEEL, 0.3), Vector3(0.0, 0.12, -0.1), Vector3(0.05, 0.04, 0.01))


func bake_variant() -> String:
	return "g" if grand else ""


func pose(_delta: float) -> void:
	biped_bob(HIP, 0.03)
	var aim := maxf(windup_w, strike_w)
	_torso.rotation.x = -0.06 * move_w + attack_kick * 0.15
	_torso.rotation.y = aim * -0.25
	_head.rotation.y = aim * 0.2
	_head.rotation.x = aim * 0.12
	_coat.rotation.x = 0.25 * move_w + sin(walk * 2.0) * 0.05 * move_w
	# Crossbow: held low at the hip, raised to the shoulder to aim, kicked up by the shot.
	var low := Vector3(0.35 - sin(walk) * 0.2 * move_w, 0.0, 0.05)
	var up := Vector3(1.45 + attack_kick * 0.35, 0.25, 0.0)
	_arm_r.rotation = mixv(low, up, aim)
	_arm_l.rotation = mixv(Vector3(0.15 + sin(walk) * 0.25 * move_w, 0.0, -0.1), Vector3(1.3, -0.5, 0.1), aim * 0.85)
	_lamp.scale = Vector3(0.07, 0.09, 0.07) * (1.0 + 0.1 * sin(t * 9.0))
