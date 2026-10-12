extends BossModel
## "Lord-Marshal Caddoc, the Burning Crusade" (boss model, ashen wastes): a crusader warlord
## riding a burning war-chariot. A bronze-plated chariot box with scythed, flame-rimmed wheels,
## pulled by two barded white warhorses with burning manes, the warlord standing in it in
## blackened plate and a red-cross surcoat with a crested great helm, a crusade banner on the
## chariot's back and a flaming greatsword. The wheels spin with the real ground speed.
## Poses: charge = the horses rear then gallop, the warlord leans in sword forward; lanes / sweep
## = a sword sweep; pyre = the sword raised then plunged; rain = the banner raised (fire arrows);
## summon = the warlord raises his sword to the sky; chase / cross = pointing.

const FIRE := Color(1.0, 0.5, 0.18)
const WHEEL_R := 0.32

var _chariot: Node3D
var _wheels: Array[Node3D] = []
var _horses: Array[Node3D] = []
var _horse_legs: Array[Node3D] = []
var _rider: Node3D
var _arm_r: Node3D
var _arm_l: Node3D
var _banner: Node3D
var _blade: MeshInstance3D
var _roll := 0.0
var _gallop := 0.0


func build() -> void:
	light_color = FIRE
	stride = 2.2
	var bronze := Art.mat(Art.BRONZE.lightened(0.1), 0.35, 0.6, 0.3, true, 0.1, &"gold")
	var iron := m_metal(Color(0.16, 0.15, 0.15), 0.45)
	var wood := m_wood()
	var white := m_cloth(Color(0.85, 0.82, 0.76))
	var red := m_cloth(Color(0.55, 0.06, 0.05))
	var horse := Art.mat(Color(0.88, 0.86, 0.82), 0.6, 0.0, 0.2, true, 0.3, &"skin")
	body = animated(Art.pivot(self))
	_chariot = animated(Art.pivot(body, Vector3(0.0, WHEEL_R, 0.25)))
	# Chariot box: floor, curved bronze front and sides, axle.
	Art.part(_chariot, Art.box(), wood, Vector3(0.0, 0.08, 0.0), Vector3(0.7, 0.06, 0.6))
	Art.part(_chariot, Art.box(), bronze, Vector3(0.0, 0.3, -0.3), Vector3(0.72, 0.42, 0.05))
	for s: float in [-1.0, 1.0]:
		Art.part(_chariot, Art.box(), bronze, Vector3(s * 0.36, 0.24, 0.0), Vector3(0.05, 0.3, 0.6))
	Art.part(_chariot, Art.box(), red, Vector3(0.0, 0.32, -0.33), Vector3(0.1, 0.32, 0.01))
	Art.part(_chariot, Art.box(), red, Vector3(0.0, 0.4, -0.33), Vector3(0.36, 0.08, 0.01))
	limb(_chariot, Vector3(-0.5, 0.0, 0.05), Vector3(0.5, 0.0, 0.05), 0.03, iron)
	for s: float in [-1.0, 1.0]:
		var w := animated(Art.pivot(_chariot, Vector3(s * 0.48, 0.0, 0.05)))
		Art.part(w, Art.torus(0.82, 1.0), iron, Vector3.ZERO, Vector3.ONE * WHEEL_R, Vector3(0.0, 0.0, PI * 0.5))
		Art.part(w, Art.torus(0.7, 1.0), Art.glow(FIRE, 1.8), Vector3.ZERO, Vector3.ONE * (WHEEL_R + 0.04), Vector3(0.0, 0.0, PI * 0.5))
		for k in 6:
			var ang := TAU * float(k) / 6.0
			limb(w, Vector3.ZERO, Vector3(0.0, cos(ang), sin(ang)) * WHEEL_R * 0.95, 0.015, wood)
		# Scythe blade out of the hub.
		Art.part(w, Art.cone(0.5), iron, Vector3(s * 0.12, 0.0, 0.0), Vector3(0.05, 0.3, 0.05), Vector3(0.0, 0.0, -s * PI * 0.5))
		_wheels.append(w)
	# Banner on the back.
	limb(_chariot, Vector3(0.28, 0.1, 0.28), Vector3(0.28, 1.5, 0.28), 0.018, wood)
	_banner = animated(Art.pivot(_chariot, Vector3(0.28, 1.45, 0.28)))
	Art.part(_banner, Art.box(), white, Vector3(0.0, -0.22, 0.18), Vector3(0.015, 0.42, 0.34))
	Art.part(_banner, Art.box(), red, Vector3(-0.01, -0.22, 0.18), Vector3(0.006, 0.34, 0.07))
	Art.part(_banner, Art.box(), red, Vector3(-0.01, -0.12, 0.18), Vector3(0.006, 0.07, 0.24))
	# The warlord.
	_rider = animated(Art.pivot(_chariot, Vector3(0.0, 0.1, 0.05)))
	var plate := m_metal(Color(0.22, 0.2, 0.2), 0.4)
	Art.part(_rider, Art.cylinder(0.14, 0.18), plate, Vector3(0.0, 0.25, 0.0), Vector3(1.0, 0.5, 0.9))
	Art.part(_rider, Art.cylinder(0.2, 0.15), plate, Vector3(0.0, 0.66, 0.0), Vector3(1.0, 0.38, 0.8))
	Art.part(_rider, Art.box(), white, Vector3(0.0, 0.6, -0.13), Vector3(0.26, 0.5, 0.02))
	Art.part(_rider, Art.box(), red, Vector3(0.0, 0.62, -0.145), Vector3(0.05, 0.32, 0.01))
	Art.part(_rider, Art.box(), red, Vector3(0.0, 0.7, -0.145), Vector3(0.2, 0.05, 0.01))
	for s: float in [-1.0, 1.0]:
		Art.part(_rider, Art.sphere(), plate, Vector3(s * 0.2, 0.84, 0.0), Vector3(0.18, 0.14, 0.18))
	var head := Art.pivot(_rider, Vector3(0.0, 0.98, 0.0))
	Art.part(head, Art.cylinder(0.5, 0.5), plate, Vector3(0.0, 0.03, 0.0), Vector3(0.2, 0.24, 0.21))
	Art.part(head, Art.box(), Art.glow(FIRE, 2.4), Vector3(0.0, 0.05, -0.105), Vector3(0.14, 0.02, 0.01))
	Art.part(head, Art.box(), red, Vector3(0.0, 0.2, 0.02), Vector3(0.03, 0.14, 0.26))
	var a := arm(_rider, Vector3(-0.24, 0.82, 0.0), 0.44, 0.05, plate, iron, 0.0, 0.0)
	_arm_l = a[0]
	var b := arm(_rider, Vector3(0.24, 0.82, 0.0), 0.44, 0.05, plate, iron, 0.0, 0.0)
	_arm_r = b[0]
	var sw := Art.pivot(b[1], Vector3.ZERO, Vector3(-PI * 0.5, 0.0, 0.0))
	Art.part(sw, Art.box(), m_gold(), Vector3(0.0, 0.08, 0.0), Vector3(0.24, 0.035, 0.05))
	_blade = keep(Art.part(sw, Art.box(), Art.emissive(Color(0.3, 0.15, 0.1), FIRE, 1.6), Vector3(0.0, 0.62, 0.0), Vector3(0.07, 1.0, 0.02)))
	Art.part(sw, Art.box(), Art.glow(FIRE, 0.6), Vector3(0.0, 0.62, 0.0), Vector3(0.16, 1.05, 0.06))
	# Two barded warhorses with burning manes, harnessed in front.
	for s: float in [-1.0, 1.0]:
		var h := animated(Art.pivot(body, Vector3(s * 0.26, 0.55, -0.7)))
		Art.part(h, Art.sphere(), horse, Vector3(0.0, 0.0, 0.0), Vector3(0.24, 0.28, 0.62))
		Art.part(h, Art.box(), red, Vector3(0.0, 0.02, 0.0), Vector3(0.27, 0.22, 0.5))
		var neck := Art.pivot(h, Vector3(0.0, 0.12, -0.26), Vector3(-0.6, 0.0, 0.0))
		limb(neck, Vector3.ZERO, Vector3(0.0, 0.3, 0.0), 0.07, horse)
		Art.part(neck, Art.sphere(), horse, Vector3(0.0, 0.34, -0.08), Vector3(0.12, 0.14, 0.26))
		Art.part(neck, Art.box(), iron, Vector3(0.0, 0.37, -0.1), Vector3(0.13, 0.08, 0.2))
		for k in 4:
			Art.part(neck, Art.cone(0.5), Art.glow(FIRE, 2.0), Vector3(0.0, 0.08 + k * 0.08, 0.07), Vector3(0.05, 0.14, 0.05), Vector3(-0.6, 0.0, 0.0))
		for fz: float in [-0.2, 0.2]:
			for fx: float in [-0.08, 0.08]:
				var lg := Art.pivot(h, Vector3(fx, -0.1, fz))
				limb(lg, Vector3.ZERO, Vector3(0.0, -0.42, 0.0), 0.03, horse)
				Art.part(lg, Art.cylinder(0.5, 0.5), iron, Vector3(0.0, -0.43, 0.0), Vector3(0.06, 0.04, 0.07))
				_horse_legs.append(animated(lg))
		# Harness pole to the chariot.
		limb(body, Vector3(s * 0.26, 0.5, -0.4), Vector3(s * 0.1, WHEEL_R + 0.1, -0.05), 0.015, wood)
		_horses.append(h)
	finish()


func pose(delta: float) -> void:
	var rush := act([&"charge"])
	var sweep := act([&"lanes", &"sweep"])
	var plunge := act([&"pyre", &"bells"])
	var banner := act([&"rain", &"orbs"])
	var point := act([&"chase", &"cross"])
	var cry := act([&"summon"]) + rise_w
	var spd := ground_speed if ground_speed >= 0.0 else move_w * 2.0
	_roll += spd / maxf(WHEEL_R * body_scale, 0.05) * delta
	for w in _wheels:
		w.rotation.x = -_roll
	_gallop += delta * (4.0 + spd * 2.0)
	var g := clampf(move_w + strike_w * rush, 0.0, 1.0)
	for i in _horses.size():
		var h := _horses[i]
		# Rearing on the charge tell, galloping when moving.
		h.rotation.x = rush * windup_w * 0.6 + sin(_gallop + float(i)) * 0.05 * g - kneel_w * 0.4
		h.position.y = 0.55 + absf(sin(_gallop + float(i))) * 0.05 * g + rush * windup_w * 0.12 - kneel_w * 0.25
	for i in _horse_legs.size():
		var front := (i % 4) < 2
		_horse_legs[i].rotation.x = sin(_gallop + float(i) * 1.7) * 0.6 * g + (rush * windup_w * 1.0 if front else 0.0)
	_chariot.rotation.x = sin(_gallop * 2.0) * 0.02 * g - kneel_w * 0.1
	_rider.rotation.x = -rush * 0.3 - plunge * strike_w * 0.3 - kneel_w * 0.5
	_rider.rotation.y = sweep * (0.6 - strike_w * 1.2)
	_rider.position.y = 0.1 + rise_w * 0.3
	var r := Vector3(0.5, 0.0, 0.15)
	r = mixv(r, Vector3(1.4, -0.6 + strike_w * 1.4, 0.2), sweep)
	r = mixv(r, Vector3(lerpf(2.9, 0.8, strike_w), 0.0, 0.1), plunge)
	r = mixv(r, Vector3(1.5, -0.2, 0.1), rush)
	r = mixv(r, Vector3(2.9, 0.0, 0.2), minf(cry, 1.0))
	r = mixv(r, Vector3(1.5, 0.0, 0.0), point)
	_arm_r.rotation = r
	_arm_l.rotation = mixv(Vector3(0.6, 0.3, -0.2), Vector3(2.7, 0.0, -0.3), banner)
	_banner.rotation.x = 0.3 * g + sin(t * 4.0) * 0.12 - banner * 0.4
	EnemyModel.glow(_blade, windup_w * 0.6 + strike_w * 0.6)
