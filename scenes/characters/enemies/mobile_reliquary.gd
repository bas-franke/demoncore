extends ProcModel
## "Mobile Reliquary" (SHIELD: wards nearby allies): a gilded shrine on a wheeled bier, carried
## into battle. A gold house-shaped reliquary with a crystal window in which a saint's skull
## glows, crowned with a cross, hung with white and red banners, borne on poles by two hooded
## acolytes walking front and back. During the wind-up the relic blazes and the banners lift
## (the ward pulses outward); its slam is the bier rammed forward.

const RELIC := Color(1.0, 0.86, 0.5)

var _bier: Node3D
var _relic: MeshInstance3D
var _banners: Array[Node3D] = []
var _bearers: Array[Node3D] = []


func build() -> void:
	feather_count = 0
	mote_count = 8
	debris = [&"gold", &"gold"]
	debris_color = Art.GOLD
	death_style = &"sink"
	stride = 0.9
	# Less metallic than m_gold(): a big mirror-gold box reads black without sky reflections.
	var gold := Art.mat(Art.GOLD, 0.4, 0.5, 0.2, true, 0.25, &"gold")
	var wood := m_wood()
	var robe := Art.mat(Color(0.5, 0.45, 0.38), 0.9, 0.0, 0.4, true, 0.0, &"cloth")
	_bier = animated(Art.pivot(self, Vector3(0.0, 0.55, 0.0)))
	# Carrying poles and the platform.
	for s: float in [-1.0, 1.0]:
		limb(_bier, Vector3(s * 0.22, 0.0, -0.75), Vector3(s * 0.22, 0.0, 0.75), 0.022, wood)
	Art.part(_bier, Art.box(), wood, Vector3(0.0, 0.03, 0.0), Vector3(0.5, 0.05, 0.6))
	Art.part(_bier, Art.box(), Art.mat(Color(0.18, 0.16, 0.42), 0.5, 0.0, 0.1, true, 0.6, &"cloth"), Vector3(0.0, -0.06, 0.0), Vector3(0.52, 0.14, 0.62))  # art-style: no red main albedo on heaven's side
	# The reliquary: a little golden house with a pitched roof, crystal window and cross.
	Art.part(_bier, Art.box(), gold, Vector3(0.0, 0.2, 0.0), Vector3(0.34, 0.28, 0.44))
	Art.part(_bier, Art.prism(), gold, Vector3(0.0, 0.42, 0.0), Vector3(0.38, 0.16, 0.46))
	Art.part(_bier, Art.box(), Art.mat(Color(0.7, 0.85, 1.0), 0.1, 0.0, 0.0, true, 0.8, &"crystal"), Vector3(0.0, 0.2, -0.225), Vector3(0.22, 0.18, 0.01))
	Art.part(_bier, Art.sphere(), Art.mat(Art.BONE, 0.6, 0.0, 0.3, true, 0.0, &"bone"), Vector3(0.0, 0.2, -0.13), Vector3(0.12, 0.12, 0.12))
	_relic = keep(Art.part(_bier, Art.sphere(), Art.glow(RELIC, 1.6), Vector3(0.0, 0.2, -0.13), Vector3.ONE * 0.2))
	Art.part(_bier, Art.box(), gold, Vector3(0.0, 0.62, 0.0), Vector3(0.03, 0.2, 0.03))
	Art.part(_bier, Art.box(), gold, Vector3(0.0, 0.65, 0.0), Vector3(0.12, 0.03, 0.03))
	for i in 6:
		Art.part(_bier, Art.sphere(), Art.mat(Art.CRIMSON, 0.2, 0.0, 0.0, true, 0.8, &"crystal"), Vector3(-0.15 + i * 0.06, 0.08, -0.225), Vector3.ONE * 0.03)
	# Banners on short poles at the corners (sway).
	for k in 2:
		var s := -1.0 if k == 0 else 1.0
		limb(_bier, Vector3(s * 0.2, 0.05, 0.24), Vector3(s * 0.2, 0.75, 0.24), 0.012, gold)
		var b := animated(Art.pivot(_bier, Vector3(s * 0.2, 0.72, 0.24)))
		Art.part(b, Art.box(), m_cloth(Art.HOLY_WHITE if k == 0 else Art.GOLD), Vector3(0.0, -0.15, 0.06), Vector3(0.01, 0.28, 0.12))  # art-style: no red main albedo on heaven's side
		_banners.append(b)
	# Two hooded bearers, one at each end of the poles.
	for z: float in [-0.68, 0.68]:
		var br := animated(Art.pivot(self, Vector3(0.0, 0.0, z)))
		Art.part(br, Art.cylinder(0.12, 0.17), robe, Vector3(0.0, 0.4, 0.0), Vector3(1.0, 0.4, 0.9))
		Art.part(br, Art.sphere(), robe, Vector3(0.0, 0.65, 0.0), Vector3(0.18, 0.2, 0.18))
		Art.part(br, Art.cone(0.5), robe, Vector3(0.0, 0.78, 0.03), Vector3(0.12, 0.16, 0.12), Vector3(0.3, 0.0, 0.0))
		Art.part(br, Art.sphere(), Art.mat(Art.OBSIDIAN, 0.5), Vector3(0.0, 0.64, -0.07 if z < 0.0 else -0.07), Vector3(0.1, 0.11, 0.05))
		# Arms up to the poles.
		for s: float in [-1.0, 1.0]:
			limb(br, Vector3(s * 0.13, 0.5, 0.0), Vector3(s * 0.22, 0.55, 0.0), 0.025, robe)
		for s: float in [-1.0, 1.0]:
			var lg := Art.pivot(br, Vector3(s * 0.06, 0.24, 0.0))
			limb(lg, Vector3.ZERO, Vector3(0.0, -0.22, 0.0), 0.03, robe)
			Art.part(lg, Art.box(), m_leather(), Vector3(0.0, -0.23, -0.03), Vector3(0.06, 0.03, 0.1))
			add_leg(lg, (0.0 if s < 0.0 else PI) + (0.0 if z < 0.0 else PI * 0.5), 0.45, 0.24)
		_bearers.append(br)
	finish()


func pose(_delta: float) -> void:
	var ward := windup_w
	var ram := maxf(strike_w, recover_w)
	_bier.position.y = 0.55 + absf(sin(walk)) * 0.02 * move_w + ward * 0.06
	_bier.position.z = -ram * 0.12
	_bier.rotation.z = sin(walk) * 0.02 * move_w
	for i in _bearers.size():
		_bearers[i].position.y = absf(sin(walk + float(i))) * 0.02 * move_w
	for i in _banners.size():
		_banners[i].rotation.x = 0.3 * move_w + sin(t * 2.0 + float(i)) * 0.15 - ward * 0.5
	_relic.scale = Vector3.ONE * 0.2 * (1.0 + ward * 0.8 + 0.08 * sin(t * 3.0))


## Ragdoll death (characters-polish DeathFx): the pivots that flop loose.
func ragdoll_limbs() -> Array:
	return limbs_with(_banners + _bearers)
