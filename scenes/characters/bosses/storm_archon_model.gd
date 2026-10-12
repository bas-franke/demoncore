extends BossModel
## "Baraqiel, Archon of the Tempest" (boss model, storm spire): a storm-archon that conducts the
## spire's lightning like a choir. A tall angel in slate-blue and silver robes that end in a
## swirl of storm-cloud instead of legs (it floats), a tall copper collar crackling with sparks, a
## faceless silver mask, two pairs of storm-grey wings, a conductor's baton of lightning, and four
## copper lightning rods that orbit it with arcs leaping between them.
## Poses: chase / rain = baton raised, the rods spin up (lightning strikes); bells = both arms
## brought down (thunder rings); orbs = arms spread (ball lightning); cross / lanes = the baton
## slashes; summon = arms raised high; charge = it streaks forward, wings back.

const BOLT := Color(0.7, 0.75, 1.0)

var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _baton: MeshInstance3D
var _rods: Node3D
var _arcs: Array[MeshInstance3D] = []
var _cloud: Array[Node3D] = []
var _spin := 0.0


func build() -> void:
	light_color = BOLT
	wing_speed = 2.0
	wing_amp = 0.18
	wing_lift = 0.3
	var robe := Art.mat(Color(0.25, 0.3, 0.42), 0.6, 0.0, 0.2, true, 0.4, &"cloth")
	var silver := m_metal(Color(0.82, 0.84, 0.9), 0.25)
	var copper := Art.mat(Color(0.75, 0.42, 0.25), 0.35, 0.6, 0.2, true, 0.1, &"gold")
	var cloud := Art.mat(Color(0.35, 0.37, 0.45), 0.9, 0.0, 0.2, true, 0.3, &"cloth")
	body = animated(Art.pivot(self, Vector3(0.0, 0.35, 0.0)))
	# A swirl of storm-cloud below the robes (puffs that churn).
	for i in 5:
		var c := animated(Art.pivot(body, Vector3(0.0, -0.1 - i * 0.06, 0.0)))
		Art.part(c, Art.sphere(), cloud, Vector3(0.18 - i * 0.02, 0.0, 0.0), Vector3(0.42, 0.18, 0.36) * (1.0 - i * 0.12))
		Art.part(c, Art.sphere(), cloud, Vector3(-0.15 + i * 0.02, 0.0, 0.05), Vector3(0.36, 0.16, 0.3) * (1.0 - i * 0.12))
		_cloud.append(c)
	Art.part(body, Art.cylinder(0.2, 0.32), robe, Vector3(0.0, 0.3, 0.0), Vector3(1.0, 0.6, 0.9))
	_torso = animated(Art.pivot(body, Vector3(0.0, 0.6, 0.0)))
	Art.part(_torso, Art.cylinder(0.24, 0.2), robe, Vector3(0.0, 0.22, 0.0), Vector3(1.0, 0.46, 0.8))
	Art.part(_torso, Art.box(), silver, Vector3(0.0, 0.22, -0.16), Vector3(0.2, 0.4, 0.02))
	# Copper collar with sparks.
	Art.part(_torso, Art.cylinder(0.26, 0.2), copper, Vector3(0.0, 0.5, 0.04), Vector3(1.0, 0.22, 0.9))
	for k in 6:
		var theta := -1.2 + k * 0.48
		Art.part(_torso, Art.cone(0.5), copper, Vector3(sin(theta) * 0.22, 0.66, cos(theta) * 0.12 + 0.06), Vector3(0.03, 0.14, 0.03))
	_head = animated(Art.pivot(_torso, Vector3(0.0, 0.62, -0.02)))
	Art.part(_head, Art.sphere(), silver, Vector3.ZERO, Vector3(0.2, 0.25, 0.21))
	Art.part(_head, Art.box(), Art.glow(BOLT, 2.6), Vector3(0.0, 0.02, -0.105), Vector3(0.12, 0.012, 0.01))
	halo(_head, Vector3(0.0, 0.05, 0.16), 0.2, 2.8, true, false, BOLT)
	solid_wing_pair(_torso, Vector3(0.0, 0.42, 0.14), 0.9, Art.mat(Color(0.55, 0.58, 0.66), 0.7, 0.0, 0.2, true, 0.3, &"feather"), silver, null, 0.1)
	solid_wing_pair(_torso, Vector3(0.0, 0.22, 0.14), 0.6, Art.mat(Color(0.45, 0.48, 0.56), 0.7, 0.0, 0.2, true, 0.3, &"feather"), null, null, 0.1)
	var a := arm(_torso, Vector3(-0.28, 0.42, 0.0), 0.5, 0.05, robe, silver, 0.0, 0.0)
	_arm_l = a[0]
	var b := arm(_torso, Vector3(0.28, 0.42, 0.0), 0.5, 0.05, robe, silver, 0.0, 0.0)
	_arm_r = b[0]
	# Baton of lightning: a jagged line of glowing segments.
	var bt := Art.pivot(b[1], Vector3.ZERO, Vector3(-PI * 0.5, 0.0, 0.0))
	limb(bt, Vector3(0.0, -0.05, 0.0), Vector3(0.0, 0.1, 0.0), 0.015, silver)
	_baton = keep(Art.part(bt, Art.box(), Art.glow(BOLT, 2.8), Vector3(0.0, 0.4, 0.0), Vector3(0.025, 0.6, 0.025), Vector3(0.0, 0.0, 0.08)))
	# Four orbiting copper lightning rods, with arcs between them.
	_rods = animated(Art.pivot(self, Vector3(0.0, 0.9, 0.0)))
	for k in 4:
		var ang := TAU * float(k) / 4.0
		var p := Vector3(cos(ang), 0.0, sin(ang)) * 1.0
		limb(_rods, p + Vector3(0.0, -0.5, 0.0), p + Vector3(0.0, 0.55, 0.0), 0.025, copper)
		Art.part(_rods, Art.sphere(), copper, p + Vector3(0.0, 0.58, 0.0), Vector3.ONE * 0.08)
		Art.part(_rods, Art.torus(0.6, 1.0), copper, p + Vector3(0.0, 0.2, 0.0), Vector3.ONE * 0.06)
		var q := Vector3(cos(ang + TAU / 4.0), 0.0, sin(ang + TAU / 4.0)) * 1.0
		var arc := keep(EnemyModel.limb(_rods, p + Vector3(0.0, 0.58, 0.0), q + Vector3(0.0, 0.58, 0.0), 0.012, Art.glow(BOLT, 2.4)))
		arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_arcs.append(arc)
	finish()


func pose(delta: float) -> void:
	var strike := act([&"chase", &"rain"])
	var thunder := act([&"bells", &"pyre"])
	var spread := act([&"orbs"])
	var slash := act([&"cross", &"lanes", &"sweep"])
	var call_w := minf(act([&"summon"]) + rise_w, 1.0)
	var streak := act([&"charge"])
	body.position.y = 0.35 + sin(t * 1.6) * 0.06 + rise_w * 0.4 - kneel_w * 0.3
	body.rotation.x = -streak * 0.4 - kneel_w * 0.3
	_torso.rotation.x = -thunder * strike_w * 0.35 + call_w * 0.15 - kneel_w * 0.3
	_torso.rotation.y = slash * (0.5 - strike_w * 1.0)
	_head.rotation.x = -strike * 0.3 - call_w * 0.3
	var r := Vector3(0.6 + sin(t * 2.0) * 0.1, 0.0, 0.15)
	r = mixv(r, Vector3(2.9, 0.0, 0.1), strike)
	r = mixv(r, Vector3(lerpf(2.8, 0.8, strike_w), 0.0, 0.2), thunder)
	r = mixv(r, Vector3(1.2, 0.0, 1.4), spread)
	r = mixv(r, Vector3(1.4, -0.7 + strike_w * 1.4, 0.2), slash)
	r = mixv(r, Vector3(2.8, 0.0, 0.5), call_w)
	_arm_r.rotation = r
	var l := Vector3(0.5, 0.2, -0.15)
	l = mixv(l, Vector3(lerpf(2.8, 0.8, strike_w), 0.0, -0.2), thunder)
	l = mixv(l, Vector3(1.2, 0.0, -1.4), spread)
	l = mixv(l, Vector3(2.8, 0.0, -0.5), call_w)
	_arm_l.rotation = l
	wing_lift = 0.3 + call_w * 0.4 - streak * 0.4
	wing_sweep = 0.15 + streak * 0.9
	_spin += delta * (0.6 + strike * 4.0 + float(boss_phase) * 0.4)
	_rods.rotation.y = _spin
	_rods.position.y = 0.9 + body.position.y - 0.35
	var flick := 0.6 + 0.4 * absf(sin(t * 23.0)) + strike + thunder
	for i in _arcs.size():
		_arcs[i].visible = fmod(t * 7.0 + float(i) * 0.37, 1.0) < 0.55 + 0.3 * minf(flick, 1.0)
	_baton.scale = Vector3(0.025, 0.6, 0.025) * Vector3(1.0 + strike * 0.8, 1.0, 1.0 + strike * 0.8)
	for i in _cloud.size():
		_cloud[i].rotation.y = t * (0.8 + float(i) * 0.3) * (1.0 if i % 2 == 0 else -1.0)
