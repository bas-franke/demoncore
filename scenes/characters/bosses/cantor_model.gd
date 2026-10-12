extends BossModel
## "Cantor Seraphiel, the Broken Choir" (boss model, ruined sanctum variant): the choirmaster of
## the fallen sanctum, still conducting a hymn no one sings any more. A gaunt, very tall angel in
## a tattered white-and-violet choir cope, a cracked porcelain mask with a singing mouth, a halo
## of broken organ pipes behind the head that breathe light, a hymnal chained to the belt, two
## pairs of ragged grey wings and a long silver baton. Its feet never touch the ground.
## Poses: bells = it sings (the pipes and mouth blaze, head thrown back); lanes / cross = baton
## cuts; chase / rain = baton raised high (notes fall as pillars); orbs = arms spread (a burst of
## notes); pyre = arms brought down; summon = it lifts the hymnal (choir wraiths answer).

const NOTE := Color(0.88, 0.85, 1.0)

var _torso: Node3D
var _head: Node3D
var _mouth: MeshInstance3D
var _pipes: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _hem: Array[Node3D] = []


func build() -> void:
	light_color = NOTE
	wing_speed = 1.8
	wing_amp = 0.15
	wing_lift = 0.0
	wing_sweep = 0.4
	var white := Art.mat(Color(0.86, 0.84, 0.8), 0.8, 0.0, 0.35, true, 0.3, &"cloth")
	var violet := Art.mat(Color(0.32, 0.18, 0.4), 0.7, 0.0, 0.3, true, 0.4, &"cloth")
	var porcelain := Art.mat(Color(0.94, 0.92, 0.88), 0.25, 0.0, 0.1, true, 0.5, &"marble")
	var pipe := m_metal(Color(0.7, 0.68, 0.62), 0.35)
	body = animated(Art.pivot(self, Vector3(0.0, 0.25, 0.0)))
	Art.part(body, Art.cylinder(0.2, 0.34), white, Vector3(0.0, 0.42, 0.0), Vector3(1.0, 0.84, 0.9))
	Art.part(body, Art.box(), violet, Vector3(0.0, 0.42, -0.25), Vector3(0.16, 0.8, 0.02), Vector3(0.16, 0.0, 0.0))
	# Tattered hem strips (sway).
	for k in 7:
		var ang := TAU * float(k) / 7.0
		var h := animated(Art.pivot(body, Vector3(cos(ang) * 0.3, 0.02, sin(ang) * 0.28), Vector3(0.0, -ang, 0.0)))
		Art.part(h, Art.box(), white, Vector3(0.0, -0.12, 0.0), Vector3(0.1, 0.26, 0.01))
		_hem.append(h)
	_torso = animated(Art.pivot(body, Vector3(0.0, 0.84, 0.0)))
	Art.part(_torso, Art.cylinder(0.22, 0.2), white, Vector3(0.0, 0.2, 0.0), Vector3(1.0, 0.42, 0.8))
	Art.part(_torso, Art.cylinder(0.24, 0.28), violet, Vector3(0.0, 0.36, 0.02), Vector3(1.0, 0.14, 0.9))
	# Hymnal chained at the hip.
	Art.part(_torso, Art.box(), Art.mat(Color(0.25, 0.1, 0.12), 0.6), Vector3(0.2, -0.05, -0.1), Vector3(0.12, 0.16, 0.05))
	_head = animated(Art.pivot(_torso, Vector3(0.0, 0.56, 0.0)))
	Art.part(_head, Art.sphere(), porcelain, Vector3.ZERO, Vector3(0.2, 0.27, 0.21))
	Art.part(_head, Art.box(), Art.mat(Art.OBSIDIAN, 0.5), Vector3(0.04, 0.05, -0.1), Vector3(0.008, 0.16, 0.01), Vector3(0.0, 0.0, 0.3))
	for s: float in [-1.0, 1.0]:
		Art.part(_head, Art.sphere(), Art.mat(Art.OBSIDIAN, 0.4), Vector3(s * 0.045, 0.04, -0.095), Vector3(0.04, 0.03, 0.02))
	_mouth = keep(Art.part(_head, Art.sphere(), Art.glow(NOTE, 2.4), Vector3(0.0, -0.07, -0.1), Vector3(0.05, 0.05, 0.02)))
	# Halo of broken organ pipes (a fan behind the head), glowing at their mouths.
	_pipes = animated(Art.pivot(_head, Vector3(0.0, 0.02, 0.16)))
	for k in 9:
		var ang := -1.2 + float(k) * 0.3
		var length := 0.25 + 0.15 * float(4 - absi(k - 4)) * 0.5 - (0.1 if k % 3 == 1 else 0.0)
		var d := Vector3(sin(ang), cos(ang), 0.0)
		limb(_pipes, d * 0.12, d * (0.12 + length), 0.03, pipe)
		Art.part(_pipes, Art.sphere(), Art.glow(NOTE, 1.8), d * (0.12 + length), Vector3.ONE * 0.05)
	solid_wing_pair(_torso, Vector3(0.0, 0.38, 0.14), 0.85, Art.mat(Color(0.6, 0.58, 0.6), 0.8, 0.0, 0.4, true, 0.3, &"feather"), null, null, 0.1)
	solid_wing_pair(_torso, Vector3(0.0, 0.18, 0.14), 0.55, Art.mat(Color(0.5, 0.48, 0.52), 0.8, 0.0, 0.4, true, 0.3, &"feather"), null, null, 0.1)
	var a := arm(_torso, Vector3(-0.26, 0.34, 0.0), 0.56, 0.04, white, porcelain, 0.0, 0.0)
	_arm_l = a[0]
	var b := arm(_torso, Vector3(0.26, 0.34, 0.0), 0.56, 0.04, white, porcelain, 0.0, 0.0)
	_arm_r = b[0]
	var bt := Art.pivot(b[1], Vector3.ZERO, Vector3(-PI * 0.5, 0.0, 0.0))
	limb(bt, Vector3(0.0, -0.05, 0.0), Vector3(0.0, 0.6, 0.0), 0.01, m_metal(Color(0.85, 0.85, 0.9), 0.2))
	Art.part(bt, Art.sphere(), Art.glow(NOTE, 2.0), Vector3(0.0, 0.62, 0.0), Vector3.ONE * 0.04)
	finish()


func pose(_delta: float) -> void:
	var sing := act([&"bells"])
	var cut := act([&"lanes", &"cross", &"sweep"])
	var raise := act([&"chase", &"rain"])
	var spread := act([&"orbs"])
	var down := act([&"pyre"])
	var book := minf(act([&"summon"]) + rise_w, 1.0)
	body.position.y = 0.25 + sin(t * 1.3) * 0.05 + rise_w * 0.4 - kneel_w * 0.3
	_torso.rotation.x = sing * 0.25 - down * strike_w * 0.3 - kneel_w * 0.4
	_torso.rotation.y = cut * (0.5 - strike_w * 1.0)
	_head.rotation.x = -sing * 0.5 + sin(t * 0.9) * 0.05
	_head.rotation.z = sin(t * 0.7) * 0.08
	var conduct := sin(t * 3.0) * 0.25
	var r := Vector3(1.2 + conduct, -0.2, 0.25)
	r = mixv(r, Vector3(1.5, -0.7 + strike_w * 1.4, 0.2), cut)
	r = mixv(r, Vector3(2.9, 0.0, 0.1), raise)
	r = mixv(r, Vector3(1.1, 0.0, 1.4), spread)
	r = mixv(r, Vector3(lerpf(2.6, 0.9, strike_w), 0.0, 0.2), down)
	_arm_r.rotation = r
	var l := Vector3(0.9 - conduct * 0.5, 0.3, -0.25)
	l = mixv(l, Vector3(1.1, 0.0, -1.4), spread)
	l = mixv(l, Vector3(lerpf(2.6, 0.9, strike_w), 0.0, -0.2), down)
	l = mixv(l, Vector3(2.6, 0.0, -0.3), book)
	_arm_l.rotation = l
	_mouth.scale = Vector3(0.05, 0.05 * (1.0 + sing * 1.5 + 0.3 * absf(sin(t * 6.0))), 0.02)
	_pipes.scale = Vector3.ONE * (1.0 + sing * 0.25 + float(boss_phase) * 0.1 + 0.03 * sin(t * 5.0))
	for i in _hem.size():
		_hem[i].rotation.x = sin(t * 2.0 + float(i)) * 0.25
