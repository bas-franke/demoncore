extends ProcModel
## "Fanatical Flagellant" (CHASE, grows stronger as it bleeds): a gaunt penitent in a bloodied
## loincloth and a black hood, whipping its own back with a knotted scourge as it shambles on.
## Every wound feeds its frenzy: below full health it runs faster and hits harder (up to +100%
## speed and +80% contact damage near death), its whipping quickens, its back blazes with holy
## light and it stands straighter. The rage is applied to its Enemy here (model-side mechanic).

const MAX_SPEED_BONUS := 1.0
const MAX_DAMAGE_BONUS := 0.8
const HIP := 0.44

var _torso: Node3D
var _head: Node3D
var _arm_r: Node3D
var _arm_l: Node3D
var _scourge: Node3D
var _glow: MeshInstance3D
var _rage := 0.0
var _base_damage := -1.0


func build() -> void:
	feather_count = 0
	mote_count = 5
	stride = 1.1
	var skin := m_skin(Color(0.78, 0.62, 0.55))
	var blood := Art.mat(Color(0.45, 0.04, 0.04), 0.5, 0.0, 0.1, true, 0.3, &"skin")
	var black := m_cloth(Color(0.08, 0.07, 0.07))
	_torso = biped(HIP, 0.035, skin, skin, 0.07, 0.6)
	Art.part(body, Art.cylinder(0.13, 0.16), m_cloth(Color(0.55, 0.5, 0.42)), Vector3(0.0, -0.05, 0.0), Vector3(1.0, 0.16, 0.85))
	Art.part(_torso, Art.cylinder(0.15, 0.12), skin, Vector3(0.0, 0.18, 0.0), Vector3(1.0, 0.36, 0.75))
	# Weals across the back.
	for k in 5:
		Art.part(_torso, Art.box(), blood, Vector3(0.0, 0.08 + k * 0.06, 0.1), Vector3(0.22, 0.012, 0.01), Vector3(0.0, 0.0, 0.5 - k * 0.25))
	_glow = keep(Art.part(_torso, Art.sphere(), Art.glow(Art.HOLY, 1.6), Vector3(0.0, 0.22, 0.1), Vector3(0.01, 0.01, 0.01)))
	_head = animated(Art.pivot(_torso, Vector3(0.0, 0.44, -0.02)))
	Art.part(_head, Art.cone(0.5), black, Vector3(0.0, 0.08, 0.02), Vector3(0.2, 0.32, 0.2))
	Art.part(_head, Art.sphere(), black, Vector3(0.0, -0.02, 0.0), Vector3(0.18, 0.17, 0.18))
	for s: float in [-1.0, 1.0]:
		Art.part(_head, Art.sphere(), Art.glow(Art.HOLY_WHITE, 1.6), Vector3(s * 0.035, 0.0, -0.085), Vector3(0.03, 0.02, 0.015))
	var a := arm(_torso, Vector3(-0.17, 0.33, 0.0), 0.32, 0.03, skin, skin, 0.0, 0.0)
	_arm_l = a[0]
	var b := arm(_torso, Vector3(0.17, 0.33, 0.0), 0.32, 0.03, skin, skin, 0.0, 0.0)
	_arm_r = b[0]
	# Knotted scourge: three cords from a short handle (swung over the shoulder).
	limb(b[1], Vector3.ZERO, Vector3(0.0, -0.12, 0.0), 0.014, m_wood())
	_scourge = animated(Art.pivot(b[1], Vector3(0.0, -0.12, 0.0)))
	for k in 3:
		var x := (float(k) - 1.0) * 0.03
		limb(_scourge, Vector3.ZERO, Vector3(x, -0.3, 0.02), 0.006, m_leather(Color(0.3, 0.2, 0.12)))
		Art.part(_scourge, Art.sphere(), blood, Vector3(x, -0.3, 0.02), Vector3.ONE * 0.025)
	finish()


func pose(_delta: float) -> void:
	_apply_rage()
	var r := _rage
	biped_bob(HIP, 0.05)
	_torso.rotation.x = lerpf(-0.45, -0.15, r) - 0.15 * move_w
	_head.rotation.x = lerpf(0.3, -0.1, r)
	# The lash: over the shoulder onto the back, faster as the rage grows.
	var lash := sin(t * lerpf(4.0, 11.0, r))
	_arm_r.rotation = Vector3(lerpf(2.6, 1.4, (lash + 1.0) * 0.5), 0.0, 0.4)
	_scourge.rotation.x = -1.2 - lash * 0.8
	_arm_l.rotation = Vector3(0.8 + sin(walk) * 0.3 * move_w, 0.0, -0.2)
	_glow.scale = Vector3.ONE * (0.01 + r * 0.35 * (1.0 + 0.15 * sin(t * 14.0)))


## Frenzy from missing health: the host Enemy's speed (move factor "flagellant_rage") and contact
## damage (base captured on the first frame).
func _apply_rage() -> void:
	var e := host()
	if e == null or e.max_hp <= 0.0:
		return
	if _base_damage < 0.0:
		_base_damage = e.damage
	_rage = clampf(1.0 - e.hp / e.max_hp, 0.0, 1.0)
	# Speed through the Enemy's named move factors (stacks cleanly with slows / binds).
	e.set_move_factor(&"flagellant_rage", 1.0 + _rage * MAX_SPEED_BONUS)
	e.damage = _base_damage * (1.0 + _rage * MAX_DAMAGE_BONUS)
