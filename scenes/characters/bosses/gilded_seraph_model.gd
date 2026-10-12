extends BossModel
## "Aurum, the Gilded Seraph" (boss model, gilded isles): the treasurer of Heaven, who long ago
## forgot what the treasure was for. A seraph whose six wings have turned to beaten gold plates,
## its body crusted with coins and gems, a face of polished gold with ruby eyes, a crown of
## stacked coin-towers, and a floating hoard below it: a gold chest overflowing with coins,
## chalices and a glowing gem, that it guards with its arms. Coin halos turn round it.
## Poses: orbs = it flings both arms out (coin bursts); rain = it raises the chest (gold falls);
## sweep / lanes = a wing slash (the wing pair arcs forward); bells = it slams the hoard down;
## summon = its gems flare; charge = it dives head-first, wings swept.

const GOLD_LIGHT := Color(1.0, 0.82, 0.35)

var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _hoard: Node3D
var _gem: MeshInstance3D
var _coins: Node3D


func build() -> void:
	light_color = GOLD_LIGHT
	debris = [&"gold", &"gold"]
	debris_color = Art.GOLD
	wing_speed = 2.4
	wing_amp = 0.22
	wing_lift = 0.35
	var gold := Art.mat(Art.GOLD, 0.35, 0.55, 0.15, true, 0.3, &"gold")
	var dark_gold := Art.mat(Art.GOLD.darkened(0.3), 0.4, 0.5, 0.25, true, 0.2, &"gold")
	var ruby := Art.mat(Color(0.7, 0.05, 0.1), 0.1, 0.0, 0.0, true, 0.9, &"crystal")
	var sapphire := Art.mat(Color(0.1, 0.2, 0.7), 0.1, 0.0, 0.0, true, 0.9, &"crystal")
	body = animated(Art.pivot(self, Vector3(0.0, 0.55, 0.0)))
	Art.part(body, Art.cylinder(0.18, 0.12), gold, Vector3(0.0, 0.1, 0.0), Vector3(1.0, 0.4, 0.9))
	_torso = animated(Art.pivot(body, Vector3(0.0, 0.3, 0.0)))
	Art.part(_torso, Art.cylinder(0.24, 0.18), gold, Vector3(0.0, 0.2, 0.0), Vector3(1.0, 0.42, 0.8))
	# Coins and gems crusted on the chest.
	for k in 9:
		var theta := -1.0 + float(k) * 0.25
		Art.part(_torso, Art.cylinder(0.5, 0.5), dark_gold, Vector3(sin(theta) * 0.2, 0.12 + 0.05 * float(k % 3), -0.14 + absf(theta) * 0.05), Vector3(0.07, 0.012, 0.07), Vector3(PI * 0.5 - 0.2, theta, 0.0))
	Art.part(_torso, Art.sphere(), ruby, Vector3(0.0, 0.28, -0.17), Vector3(0.09, 0.09, 0.05))
	_head = animated(Art.pivot(_torso, Vector3(0.0, 0.52, 0.0)))
	Art.part(_head, Art.sphere(), gold, Vector3.ZERO, Vector3(0.22, 0.26, 0.23))
	for s: float in [-1.0, 1.0]:
		Art.part(_head, Art.sphere(), Art.glow(Color(1.0, 0.2, 0.25), 2.4), Vector3(s * 0.05, 0.02, -0.105), Vector3(0.04, 0.025, 0.02))
	# Crown of coin towers.
	for k in 7:
		var theta := TAU * float(k) / 7.0
		for c in 2 + k % 3:
			Art.part(_head, Art.cylinder(0.5, 0.5), gold, Vector3(cos(theta) * 0.1, 0.13 + c * 0.025, sin(theta) * 0.1), Vector3(0.06, 0.02, 0.06))
	Art.part(_head, Art.sphere(), sapphire, Vector3(0.0, 0.16, -0.1), Vector3.ONE * 0.05)
	# Six gilded wings (three solid pairs).
	var plate := Art.mat(Art.GOLD.lightened(0.1), 0.3, 0.5, 0.1, true, 0.4, &"gold")
	solid_wing_pair(_torso, Vector3(0.0, 0.48, 0.12), 0.95, plate, dark_gold, null, 0.1)
	solid_wing_pair(_torso, Vector3(0.0, 0.3, 0.12), 0.75, plate, dark_gold, null, 0.1)
	solid_wing_pair(body, Vector3(0.0, 0.05, 0.1), 0.55, plate, dark_gold, null, 0.1)
	var a := arm(_torso, Vector3(-0.28, 0.42, 0.0), 0.5, 0.05, gold, gold, 0.0, 0.0)
	_arm_l = a[0]
	var b := arm(_torso, Vector3(0.28, 0.42, 0.0), 0.5, 0.05, gold, gold, 0.0, 0.0)
	_arm_r = b[0]
	# The hoard: a chest overflowing with coins, a chalice and a great gem, floating below.
	_hoard = animated(Art.pivot(self, Vector3(0.0, 0.35, -0.45)))
	var wood := Art.mat(Color(0.35, 0.18, 0.08), 0.6, 0.0, 0.3, true, 0.0, &"wood")
	Art.part(_hoard, Art.box(), wood, Vector3(0.0, 0.0, 0.0), Vector3(0.5, 0.26, 0.32))
	for x: float in [-0.22, 0.0, 0.22]:
		Art.part(_hoard, Art.box(), gold, Vector3(x, 0.0, 0.0), Vector3(0.04, 0.27, 0.33))
	Art.part(_hoard, Art.sphere(), gold, Vector3(0.0, 0.14, 0.0), Vector3(0.46, 0.16, 0.3))
	Art.part(_hoard, Art.box(), wood, Vector3(0.0, 0.22, 0.18), Vector3(0.5, 0.3, 0.04), Vector3(-0.5, 0.0, 0.0))
	Art.part(_hoard, Art.cylinder(0.4, 0.2), gold, Vector3(0.14, 0.27, 0.0), Vector3(0.08, 0.12, 0.08))
	_gem = keep(Art.part(_hoard, Art.sphere(), Art.glow(Color(0.4, 0.8, 1.0), 2.2), Vector3(-0.1, 0.25, 0.0), Vector3(0.1, 0.12, 0.1)))
	# Orbiting coins.
	_coins = animated(Art.pivot(self, Vector3(0.0, 1.0, 0.0)))
	for k in 10:
		var ang := TAU * float(k) / 10.0
		Art.part(_coins, Art.cylinder(0.5, 0.5), Art.glow(GOLD_LIGHT, 1.6), Vector3(cos(ang), 0.15 * sin(ang * 3.0), sin(ang)) * 0.85, Vector3(0.1, 0.015, 0.1), Vector3(PI * 0.5, -ang, 0.0))
	finish()


func pose(delta: float) -> void:
	var fling := act([&"orbs"])
	var lift := act([&"rain", &"chase"])
	var slash := act([&"sweep", &"lanes", &"cross"])
	var slam := act([&"bells", &"pyre"])
	var flare := minf(act([&"summon"]) + rise_w, 1.0)
	var dive := act([&"charge"])
	body.position.y = 0.55 + sin(t * 1.4) * 0.07 + rise_w * 0.4 - kneel_w * 0.4
	body.rotation.x = -dive * 0.5 - kneel_w * 0.3
	_torso.rotation.x = -slam * strike_w * 0.3 + lift * 0.15
	_torso.rotation.y = slash * (0.5 - strike_w * 1.0)
	_head.rotation.x = -lift * 0.2 + sin(t * 0.6) * 0.04
	# Arms: guarding the hoard at rest.
	var guard := Vector3(0.9, 0.4, 0.1)
	var r := mixv(Vector3(0.9, -0.4, -0.1), Vector3(1.1, 0.0, 1.3), fling)
	r = mixv(r, Vector3(2.6, 0.0, 0.2), lift + flare)
	r = mixv(r, Vector3(lerpf(2.4, 1.0, strike_w), 0.0, 0.1), slam)
	_arm_r.rotation = r
	var l := mixv(guard, Vector3(1.1, 0.0, -1.3), fling)
	l = mixv(l, Vector3(2.6, 0.0, -0.2), lift + flare)
	l = mixv(l, Vector3(lerpf(2.4, 1.0, strike_w), 0.0, -0.1), slam)
	_arm_l.rotation = l
	wing_lift = 0.35 + flare * 0.4 - dive * 0.4 + slash * (0.5 - strike_w)
	wing_sweep = 0.15 + dive * 0.9 - slash * 0.4 * strike_w
	_hoard.position.y = 0.35 + sin(t * 1.4 + 0.5) * 0.05 + lift * 0.7 - slam * strike_w * 0.3 + rise_w * 0.4 - kneel_w * 0.3
	_hoard.rotation.y = sin(t * 0.5) * 0.2
	_coins.rotation.y += delta * (0.6 + fling * 3.0 + float(boss_phase) * 0.3)
	_coins.scale = Vector3.ONE * (1.0 + fling * 0.4)
	_gem.scale = Vector3(0.1, 0.12, 0.1) * (1.0 + flare * 0.8 + 0.1 * sin(t * 4.0))
