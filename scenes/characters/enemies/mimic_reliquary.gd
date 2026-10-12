extends ProcModel
## "Treasure-Mimic Reliquary" (CHASE ambusher, gilded isles only): a gilded reliquary chest that
## sits perfectly still among the isles' treasure, lid shut, a soft glow at the keyhole - until the
## demon comes within WAKE_RANGE. Then the lid splits into a mouth of gold teeth with a long red
## tongue, four jointed gilt legs unfold, and it runs at you fast. Asleep, it doesn't move (its
## Enemy is held with set_move_factor(&"mimic", 0)) and it takes little knockback.

const WAKE_RANGE := 5.0

var _lid: Node3D
var _legs_m: Array[Node3D] = []
var _tongue: Node3D
var _keyhole: MeshInstance3D
var _awake := 0.0
var _woke := false


func build() -> void:
	feather_count = 0
	mote_count = 6
	debris = [&"gold", &"gold"]
	debris_color = Art.GOLD
	death_style = &"sink"
	stride = 1.0
	var gold := Art.mat(Art.GOLD, 0.35, 0.55, 0.15, true, 0.3, &"gold")
	var wood := Art.mat(Color(0.35, 0.18, 0.08), 0.6, 0.0, 0.3, true, 0.0, &"wood")
	var ruby := Art.mat(Color(0.7, 0.05, 0.1), 0.1, 0.0, 0.0, true, 0.9, &"crystal")
	body = animated(Art.pivot(self, Vector3(0.0, 0.0, 0.0)))
	# Chest box with gold bands and a gem-studded front.
	Art.part(body, Art.box(), wood, Vector3(0.0, 0.25, 0.0), Vector3(0.7, 0.36, 0.48))
	for x: float in [-0.3, 0.0, 0.3]:
		Art.part(body, Art.box(), gold, Vector3(x, 0.25, 0.0), Vector3(0.05, 0.37, 0.49))
	for k in 3:
		Art.part(body, Art.sphere(), ruby, Vector3(-0.15 + k * 0.15, 0.3, -0.245), Vector3(0.05, 0.05, 0.03))
	_keyhole = keep(Art.part(body, Art.box(), Art.glow(Color(1.0, 0.8, 0.4), 2.0), Vector3(0.0, 0.16, -0.245), Vector3(0.025, 0.06, 0.01)))
	# Lower jaw teeth along the rim.
	for k in 8:
		Art.part(body, Art.cone(0.5), Art.mat(Art.IVORY, 0.4), Vector3(-0.3 + k * 0.085, 0.45, -0.2), Vector3(0.04, 0.08, 0.04))
	# Lid (hinged at the back) with upper teeth and a domed top.
	_lid = animated(Art.pivot(body, Vector3(0.0, 0.43, 0.24)))
	Art.part(_lid, Art.box(), wood, Vector3(0.0, 0.06, -0.24), Vector3(0.7, 0.1, 0.48))
	Art.part(_lid, Art.cylinder(0.5, 0.5), gold, Vector3(0.0, 0.12, -0.24), Vector3(0.48, 0.7, 0.48), Vector3(0.0, 0.0, PI * 0.5))
	for k in 8:
		Art.part(_lid, Art.cone(0.5), Art.mat(Art.IVORY, 0.4), Vector3(-0.3 + k * 0.085, -0.02, -0.44), Vector3(0.04, 0.08, 0.04), Vector3(PI, 0.0, 0.0))
	for s: float in [-1.0, 1.0]:
		Art.part(_lid, Art.sphere(), Art.glow(Color(1.0, 0.85, 0.3), 2.4), Vector3(s * 0.18, 0.1, -0.46), Vector3(0.05, 0.03, 0.02))
	_tongue = animated(Art.pivot(body, Vector3(0.0, 0.4, -0.1)))
	Art.part(_tongue, Art.sphere(), Art.mat(Color(0.6, 0.1, 0.12), 0.4, 0.0, 0.1, true, 0.5, &"skin"), Vector3(0.0, 0.0, -0.18), Vector3(0.12, 0.03, 0.4))
	# Four gilt spider-legs folded underneath (unfold when awake).
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var lg := Art.pivot(body, Vector3(sx * 0.3, 0.12, sz * 0.18))
			limb(lg, Vector3.ZERO, Vector3(sx * 0.18, 0.08, 0.0), 0.025, gold)
			limb(lg, Vector3(sx * 0.18, 0.08, 0.0), Vector3(sx * 0.22, -0.2, 0.0), 0.02, gold)
			add_leg(lg, (0.0 if sx * sz > 0.0 else PI), 0.5)
			_legs_m.append(lg)
	finish()


func pose(delta: float) -> void:
	var e := host()
	var near := false
	if e and Game.player:
		near = e.global_position.distance_to(Game.player.global_position) < WAKE_RANGE
	if near and not _woke:
		_woke = true
		Sfx.play_at(&"mimic_snap", e.global_position if e else Game.player.global_position, 0.05, -2.0)
	if e:
		e.set_move_factor(&"mimic", 1.0 if _woke else 0.0)
	_awake = damp(_awake, 1.0 if _woke else 0.0, 6.0, delta)
	var gape := 0.35 + 0.25 * absf(sin(t * 6.0)) + attack_kick * 0.4
	_lid.rotation.x = -_awake * gape
	_tongue.scale = Vector3(1.0, 1.0, 0.2 + _awake * (0.8 + 0.3 * sin(t * 10.0)))
	body.position.y = _awake * (0.2 + absf(sin(walk)) * 0.04 * move_w)
	body.rotation.z = sin(walk) * 0.06 * move_w
	for lg in _legs_m:
		lg.scale = Vector3.ONE * maxf(_awake, 0.05)
	_keyhole.scale = Vector3(0.025, 0.06, 0.01) * (1.0 - _awake * 0.9) + Vector3(0.0001, 0.0001, 0.0001)


func ragdoll_limbs() -> Array:
	return limbs_with([_lid, _tongue])
