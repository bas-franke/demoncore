extends ProcModel
## "Seraphic Honour Guard" (CHARGE in pairs, heaven's gate only): the ceremonial guard of the
## Throne's approach - tall, slender seraphs in white enamel and silver parade armour, plumed
## helms with a burning visor, two pairs of tall swept wings, and twin curved sabres. They always
## come in pairs (the first one brings its twin) and cross their sabres in salute before each
## charge (the wind-up), then dash through the demon blades first.

var _torso: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _plume: Node3D
var _paired := false


func build() -> void:
	feather_count = 6
	wing_speed = 2.6
	wing_amp = 0.15
	wing_lift = 0.45
	wing_sweep = 0.4
	stride = 1.4
	var enamel := Art.mat(Color(0.95, 0.95, 0.96), 0.25, 0.1, 0.05, true, 0.5, &"marble")
	var silver := m_metal(Color(0.82, 0.84, 0.9), 0.25)
	var blue := m_cloth(Color(0.25, 0.32, 0.6))
	_torso = biped(0.6, 0.045, enamel, silver, 0.08, 0.5)
	Art.part(body, Art.cylinder(0.14, 0.22), blue, Vector3(0.0, -0.14, 0.0), Vector3(1.0, 0.3, 0.85))
	Art.part(_torso, Art.cylinder(0.18, 0.13), enamel, Vector3(0.0, 0.22, 0.0), Vector3(1.0, 0.44, 0.75))
	Art.part(_torso, Art.box(), silver, Vector3(0.0, 0.26, -0.1), Vector3(0.18, 0.3, 0.02))
	Art.part(_torso, Art.box(), blue, Vector3(0.0, 0.3, -0.105), Vector3(0.36, 0.04, 0.02), Vector3(0.0, 0.0, -0.5))
	var head := Art.pivot(_torso, Vector3(0.0, 0.54, 0.0))
	Art.part(head, Art.sphere(), enamel, Vector3.ZERO, Vector3(0.17, 0.21, 0.19))
	Art.part(head, Art.box(), Art.glow(Art.HOLY, 2.4), Vector3(0.0, 0.02, -0.095), Vector3(0.1, 0.014, 0.01))
	_plume = animated(Art.pivot(head, Vector3(0.0, 0.12, 0.02)))
	for k in 5:
		Art.part(_plume, Art.sphere(), m_cloth(Color(0.3, 0.4, 0.8)), Vector3(0.0, 0.04 + k * 0.02, 0.04 + k * 0.06), Vector3(0.05, 0.06, 0.12))
	solid_wing_pair(_torso, Vector3(0.0, 0.4, 0.12), 0.8, enamel, silver, null, 0.08)
	solid_wing_pair(_torso, Vector3(0.0, 0.2, 0.12), 0.55, enamel, null, null, 0.08)
	var sabre := func(hand: Node3D) -> void:
		var sp := Art.pivot(hand, Vector3.ZERO, Vector3(-PI * 0.5, 0.0, 0.0))
		Art.part(sp, Art.box(), silver, Vector3(0.02, 0.3, 0.0), Vector3(0.04, 0.5, 0.01), Vector3(0.0, 0.0, -0.12))
		Art.part(sp, Art.box(), Art.glow(Art.HOLY_WHITE, 1.2), Vector3(0.05, 0.4, 0.0), Vector3(0.012, 0.36, 0.012), Vector3(0.0, 0.0, -0.15))
		Art.part(sp, Art.torus(0.7, 1.0), m_gold(), Vector3(0.0, 0.03, 0.0), Vector3.ONE * 0.04)
	var a := arm(_torso, Vector3(-0.2, 0.38, 0.0), 0.42, 0.035, enamel, silver, 0.0, 0.0)
	_arm_l = a[0]
	sabre.call(a[1])
	var b := arm(_torso, Vector3(0.2, 0.38, 0.0), 0.42, 0.035, enamel, silver, 0.0, 0.0)
	_arm_r = b[0]
	sabre.call(b[1])
	finish()


func pose(_delta: float) -> void:
	if not _paired:
		_paired = true
		spawn_companions(1, &"honour_guard_pair", 1.4)
	biped_bob(0.6, 0.03)
	var salute := windup_w
	var dash := strike_w
	_torso.rotation.x = -0.08 * move_w - dash * 0.45 + salute * 0.08
	_plume.rotation.x = 0.2 * move_w + dash * 0.6 + sin(t * 2.0) * 0.05
	# Sabres crossed before the face in salute, then swept back for the dash.
	var l := mixv(Vector3(0.4 - sin(walk) * 0.2 * move_w, 0.0, -0.1), Vector3(2.2, -0.6, 0.3), salute)
	var r := mixv(Vector3(0.4 + sin(walk) * 0.2 * move_w, 0.0, 0.1), Vector3(2.2, 0.6, -0.3), salute)
	_arm_l.rotation = mixv(l, Vector3(1.2, -0.6, -0.6), dash)
	_arm_r.rotation = mixv(r, Vector3(1.2, 0.6, 0.6), dash)
	wing_sweep = 0.4 + dash * 0.7
	wing_lift = 0.45 - dash * 0.3


func ragdoll_limbs() -> Array:
	return limbs_with([_plume])
