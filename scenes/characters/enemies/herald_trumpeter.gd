extends ProcModel
## "Herald of the Last Trump" (SUMMON: calls reinforcements): a youthful angel in a gold-trimmed
## herald's tabard over white robes, a banner hanging from a long golden trumpet, wings held high.
## It keeps its distance; at the end of each wind-up it raises the trumpet and blows - cherubs
## answer the call (EnemyData `summon`). The trumpet's bell blazes during the wind-up.

var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _bell: MeshInstance3D
var _banner: Node3D


func build() -> void:
	feather_count = 5
	wing_speed = 3.0
	wing_amp = 0.2
	wing_lift = 0.4
	var robe := m_cloth(Color(0.93, 0.92, 0.88))
	var tabard := m_cloth(Color(0.25, 0.32, 0.6))
	var gold := Art.mat(Art.GOLD, 0.3, 0.6, 0.1, true, 0.3, &"gold")
	var skin := m_skin(Color(0.9, 0.8, 0.7))
	body = animated(Art.pivot(self, Vector3(0.0, 0.25, 0.0)))
	Art.part(body, Art.cylinder(0.13, 0.24), robe, Vector3(0.0, 0.3, 0.0), Vector3(1.0, 0.6, 0.9))
	_torso = animated(Art.pivot(body, Vector3(0.0, 0.6, 0.0)))
	Art.part(_torso, Art.cylinder(0.15, 0.13), robe, Vector3(0.0, 0.16, 0.0), Vector3(1.0, 0.34, 0.8))
	Art.part(_torso, Art.box(), tabard, Vector3(0.0, 0.08, -0.11), Vector3(0.2, 0.5, 0.02))
	Art.part(_torso, Art.box(), gold, Vector3(0.0, 0.08, -0.122), Vector3(0.21, 0.03, 0.01))
	_head = animated(Art.pivot(_torso, Vector3(0.0, 0.42, 0.0)))
	Art.part(_head, Art.sphere(), skin, Vector3.ZERO, Vector3(0.15, 0.18, 0.16))
	Art.part(_head, Art.sphere(), Art.mat(Art.GOLD.lightened(0.2), 0.6, 0.0, 0.1, true, 0.4, &"cloth"), Vector3(0.0, 0.05, 0.02), Vector3(0.17, 0.12, 0.17))
	halo(_head, Vector3(0.0, 0.14, 0.03), 0.11, 2.6)
	solid_wing_pair(_torso, Vector3(0.0, 0.32, 0.1), 0.7, null, gold, null, 0.08)
	var a := arm(_torso, Vector3(-0.17, 0.3, 0.0), 0.34, 0.03, robe, skin, 0.0, 0.0)
	_arm_l = a[0]
	var b := arm(_torso, Vector3(0.17, 0.3, 0.0), 0.34, 0.03, robe, skin, 0.0, 0.0)
	_arm_r = b[0]
	# The long trumpet in the right hand, pointing forward along the hand.
	var horn := Art.pivot(b[1], Vector3.ZERO, Vector3(-PI * 0.5, 0.0, 0.0))
	limb(horn, Vector3(0.0, -0.08, 0.0), Vector3(0.0, 0.7, 0.0), 0.015, gold)
	Art.part(horn, Art.cylinder(0.5, 0.15), gold, Vector3(0.0, 0.76, 0.0), Vector3(0.16, 0.14, 0.16))
	_bell = keep(Art.part(horn, Art.cylinder(0.5, 0.5), Art.glow(Art.HOLY_WHITE, 2.2), Vector3(0.0, 0.83, 0.0), Vector3(0.14, 0.01, 0.14)))
	_banner = animated(Art.pivot(horn, Vector3(0.0, 0.45, 0.0)))
	Art.part(_banner, Art.box(), tabard, Vector3(0.0, 0.0, 0.1), Vector3(0.008, 0.2, 0.18))
	Art.part(_banner, Art.box(), gold, Vector3(-0.005, 0.0, 0.1), Vector3(0.004, 0.08, 0.08))
	finish()


func pose(_delta: float) -> void:
	var call_w := windup_w
	var blow := maxf(strike_w, attack_kick)
	body.position.y = 0.25 + sin(t * 1.8) * 0.05
	_torso.rotation.x = call_w * 0.25 - blow * 0.1
	_head.rotation.x = -call_w * 0.35
	# Trumpet raised high toward the sky for the call.
	_arm_r.rotation = mixv(Vector3(0.6, -0.2, 0.15), Vector3(2.5, 0.0, 0.1), maxf(call_w, blow))
	_arm_l.rotation = mixv(Vector3(0.3, 0.2, -0.15), Vector3(2.3, 0.0, -0.1), maxf(call_w, blow))
	_bell.scale = Vector3(0.14, 0.01, 0.14) * (1.0 + call_w * 1.5 + blow * 2.0)
	_banner.rotation.x = sin(t * 3.0) * 0.2
	wing_lift = 0.4 + call_w * 0.4
