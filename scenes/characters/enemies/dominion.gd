extends ProcModel
## "Dominion" (SHIELD: ward caster with a shield-wall): one of the angelic lords of order. A tall
## angel in layered white and silver vestments with a high collar, a sceptre topped by an orb, a
## crown of five upright blades, and four great floating tower shields of white enamel and gold
## that circle it. During its ward (the wind-up) the shields lock into a wall in front of it and
## blaze; between wards they drift around it in slow orbit. Wards nearby angels (SHIELD), and
## slams with the sceptre when the demon comes close.

const SHIELDS := 4

var _torso: Node3D
var _head: Node3D
var _arm_r: Node3D
var _arm_l: Node3D
var _orb: MeshInstance3D
var _shields: Array[Node3D] = []
var _orbit := 0.0


func build() -> void:
	feather_count = 4
	debris = [&"steel", &"gold"]
	debris_color = Art.GOLD
	wing_speed = 2.0
	wing_amp = 0.12
	wing_lift = 0.2
	var robe := m_cloth(Color(0.9, 0.9, 0.92))
	var silver := m_metal(Color(0.82, 0.84, 0.88), 0.25)
	var gold := Art.mat(Art.GOLD, 0.35, 0.6, 0.15, true, 0.2, &"gold")
	var enamel := Art.mat(Color(0.95, 0.95, 0.93), 0.3, 0.0, 0.05, true, 0.5, &"marble")
	body = animated(Art.pivot(self, Vector3(0.0, 0.1, 0.0)))
	Art.part(body, Art.cylinder(0.2, 0.32), robe, Vector3(0.0, 0.42, 0.0), Vector3(1.0, 0.84, 0.9))
	Art.part(body, Art.cylinder(0.33, 0.33), gold, Vector3(0.0, 0.02, 0.0), Vector3(1.0, 0.03, 0.9))
	_torso = animated(Art.pivot(body, Vector3(0.0, 0.84, 0.0)))
	Art.part(_torso, Art.cylinder(0.22, 0.2), silver, Vector3(0.0, 0.2, 0.0), Vector3(1.0, 0.42, 0.8))
	Art.part(_torso, Art.cylinder(0.18, 0.26), robe, Vector3(0.0, 0.46, 0.04), Vector3(1.0, 0.18, 0.8))
	_head = animated(Art.pivot(_torso, Vector3(0.0, 0.58, 0.0)))
	Art.part(_head, Art.sphere(), enamel, Vector3.ZERO, Vector3(0.18, 0.22, 0.19))
	Art.part(_head, Art.box(), Art.glow(Art.HOLY_WHITE, 2.2), Vector3(0.0, 0.02, -0.095), Vector3(0.1, 0.012, 0.01))
	for k in 5:
		var ang := -0.8 + k * 0.4
		Art.part(_head, Art.box(), gold, Vector3(sin(ang) * 0.08, 0.17 + 0.03 * float(2 - absi(k - 2)), cos(ang) * 0.08 - 0.02), Vector3(0.02, 0.14, 0.035))
	solid_wing_pair(_torso, Vector3(0.0, 0.38, 0.12), 0.8, null, silver, null, 0.1)
	var a := arm(_torso, Vector3(-0.26, 0.38, 0.0), 0.5, 0.045, robe, enamel, 0.0, 0.0)
	_arm_l = a[0]
	var b := arm(_torso, Vector3(0.26, 0.38, 0.0), 0.5, 0.045, robe, enamel, 0.0, 0.0)
	_arm_r = b[0]
	# Sceptre with an orb.
	var sc := Art.pivot(b[1], Vector3.ZERO, Vector3(PI, 0.0, 0.0))
	limb(sc, Vector3(0.0, -0.1, 0.0), Vector3(0.0, 0.62, 0.0), 0.015, gold)
	_orb = keep(Art.part(sc, Art.sphere(), Art.glow(Art.HOLY, 2.2), Vector3(0.0, 0.68, 0.0), Vector3.ONE * 0.1))
	Art.part(sc, Art.torus(0.8, 1.0), gold, Vector3(0.0, 0.68, 0.0), Vector3.ONE * 0.07, Vector3(PI * 0.5, 0.0, 0.0))
	# Floating tower shields (each its own pivot: they orbit, then form the wall).
	for k in SHIELDS:
		var sh := animated(Art.pivot(self, Vector3(0.0, 0.75, 0.0)))
		Art.part(sh, Art.box(), enamel, Vector3(0.0, 0.0, 0.0), Vector3(0.36, 0.72, 0.05))
		Art.part(sh, Art.box(), gold, Vector3(0.0, 0.0, -0.03), Vector3(0.38, 0.74, 0.01))
		Art.part(sh, Art.box(), gold, Vector3(0.0, 0.08, -0.04), Vector3(0.05, 0.42, 0.01))
		Art.part(sh, Art.box(), gold, Vector3(0.0, 0.16, -0.04), Vector3(0.26, 0.05, 0.01))
		Art.part(sh, Art.cone(0.5), enamel, Vector3(0.0, -0.46, 0.0), Vector3(0.36, 0.2, 0.05), Vector3(PI, 0.0, 0.0))
		_shields.append(sh)
	finish()


func pose(delta: float) -> void:
	var ward := windup_w
	var slam := maxf(strike_w, recover_w)
	body.position.y = 0.1 + sin(t * 1.4) * 0.04
	_torso.rotation.x = -slam * 0.35 + ward * 0.1
	_head.rotation.x = sin(t * 0.7) * 0.04 - ward * 0.1
	_arm_r.rotation = mixv(Vector3(0.45, 0.0, 0.15), Vector3(2.7, 0.0, 0.1), ward)
	_arm_r.rotation = mixv(_arm_r.rotation, Vector3(1.0, 0.0, 0.1), slam)
	_arm_l.rotation = mixv(Vector3(0.6, 0.4, -0.2), Vector3(1.3, 0.0, -0.6), ward)
	_orb.scale = Vector3.ONE * 0.1 * (1.0 + ward * 1.0 + 0.1 * sin(t * 4.0))
	_orbit += delta * (0.8 - ward * 0.8)
	var lock := maxf(ward, slam * 0.5)
	for k in _shields.size():
		var a := _orbit + TAU * float(k) / float(_shields.size())
		var orbit_pos := Vector3(cos(a), 0.0, sin(a)) * 0.85 + Vector3(0.0, 0.75 + sin(t * 1.3 + float(k)) * 0.06, 0.0)
		# The wall: side by side in front (-Z), slightly curved.
		var x := (float(k) - float(_shields.size() - 1) * 0.5) * 0.4
		var wall_pos := Vector3(x, 0.6, -0.75 + absf(x) * 0.25)
		_shields[k].position = orbit_pos.lerp(wall_pos, lock)
		var orbit_yaw := -a + PI * 0.5
		_shields[k].rotation = Vector3(0.0, lerp_angle(orbit_yaw, -x * 0.6, lock), 0.0)
	wing_lift = 0.2 + ward * 0.3
