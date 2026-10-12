extends ProcModel
## "Gilded Harpy" (HOP dive, steals Ichor, gilded isles only): a magpie-angel of the treasure
## isles - a sharp-featured woman's face under a gold diadem, gilded feather wings, a bodice of
## gold scales, bird legs with long gold talons clutching a stolen coin-purse. It dives onto the
## demon; when a dive lands within STEAL_RADIUS of the demon it snatches STEAL_ICHOR Ichor
## (RunState.add_currency) and laughs off with it.

const STEAL_RADIUS := 1.6
const STEAL_ICHOR := 2
const HEIGHT := 0.7
const LEAP := 1.7

var _head: Node3D
var _talons: Array[Node3D] = []


func build() -> void:
	feather_count = 6
	feather_color = Art.GOLD
	debris = [&"gold"]
	debris_color = Art.GOLD
	wing_speed = 4.0
	wing_amp = 0.45
	stride = 1.3
	var gold := Art.mat(Art.GOLD, 0.35, 0.55, 0.15, true, 0.3, &"gold")
	var plume := Art.mat(Color(0.9, 0.75, 0.4), 0.5, 0.3, 0.1, true, 0.4, &"feather")
	var skin := m_skin(Color(0.85, 0.72, 0.62))
	var hair := Art.mat(Color(0.15, 0.1, 0.08), 0.5, 0.0, 0.1, true, 0.5, &"cloth")
	body = animated(Art.pivot(self, Vector3(0.0, HEIGHT, 0.0)))
	Art.part(body, Art.sphere(), Art.mat(Art.GOLD.darkened(0.2), 0.35, 0.5, 0.1, true, 0.3, &"scales"), Vector3(0.0, 0.0, 0.0), Vector3(0.24, 0.32, 0.22))
	Art.part(body, Art.cone(0.5), plume, Vector3(0.0, -0.12, 0.12), Vector3(0.16, 0.3, 0.08), Vector3(2.4, 0.0, 0.0))
	solid_wing_pair(body, Vector3(0.0, 0.1, 0.06), 0.75, plume, gold, gold, 0.08)
	_head = animated(Art.pivot(body, Vector3(0.0, 0.24, -0.02)))
	Art.part(_head, Art.sphere(), skin, Vector3.ZERO, Vector3(0.14, 0.17, 0.15))
	Art.part(_head, Art.sphere(), hair, Vector3(0.0, 0.03, 0.03), Vector3(0.16, 0.16, 0.16))
	Art.part(_head, Art.box(), hair, Vector3(0.0, -0.08, 0.07), Vector3(0.14, 0.2, 0.04))
	Art.part(_head, Art.cylinder(0.5, 0.5), gold, Vector3(0.0, 0.07, 0.0), Vector3(0.17, 0.03, 0.17))
	Art.part(_head, Art.cone(0.5), gold, Vector3(0.0, 0.11, -0.07), Vector3(0.03, 0.07, 0.02))
	for s: float in [-1.0, 1.0]:
		Art.part(_head, Art.sphere(), Art.glow(Color(1.0, 0.85, 0.3), 2.0), Vector3(s * 0.035, 0.01, -0.07), Vector3(0.025, 0.012, 0.01))
	# Bird legs with gold talons; a coin-purse in one.
	for s: float in [-1.0, 1.0]:
		var lg := limb_pivot(body, Vector3(s * 0.07, -0.12, 0.02))
		limb(lg, Vector3.ZERO, Vector3(0.0, -0.3, 0.04), 0.018, Art.mat(Color(0.6, 0.5, 0.3), 0.6))
		for c in 3:
			Art.part(lg, Art.cone(0.5), gold, Vector3((float(c) - 1.0) * 0.025, -0.33, -0.02), Vector3(0.015, 0.06, 0.015), Vector3(-PI * 0.5 - 0.5, 0.0, 0.0))
		if s > 0.0:
			Art.part(lg, Art.sphere(), m_leather(Color(0.45, 0.25, 0.12)), Vector3(0.0, -0.38, -0.02), Vector3(0.09, 0.1, 0.09))
		_talons.append(lg)
	finish()


func play_land() -> void:
	super.play_land()
	_steal()


func _steal() -> void:
	var e := host()
	var p := Game.player
	if e == null or p == null or p.is_dead:
		return
	if e.global_position.distance_to(p.global_position) > STEAL_RADIUS * maxf(body_scale, 1.0):
		return
	var rs := get_node_or_null(^"/root/RunState")
	if rs == null or int(rs.get(&"currency")) <= 0:
		return
	rs.call(&"add_currency", -STEAL_ICHOR)
	Sfx.play_at(&"ichor_steal", p.global_position + Vector3(0.0, 0.8, 0.0), 0.06, -2.0)
	EnemyModel.spawn_motes(p.global_position + Vector3(0.0, 0.8, 0.0), 6, 0.6, Art.GOLD)
	eye_flare = 1.0


func pose(_delta: float) -> void:
	var crouch := windup_w
	var dive := strike_w
	var lift := 0.0
	if dive > 0.05:
		lift = sin(clampf(state_progress, 0.0, 1.0) * PI) * LEAP * dive
	body.position.y = HEIGHT + sin(t * wing_speed) * 0.05 + crouch * 0.25 + lift - land_kick * 0.2
	var nose := clampf(state_progress * 2.0 - 0.8, 0.0, 1.0) * dive
	body.rotation.x = -0.12 * move_w + crouch * 0.3 - nose * 0.6
	wing_lift = 0.15 + crouch * 0.6 - nose * 0.4
	wing_sweep = 0.2 + nose * 0.8
	for l in _talons:
		l.rotation.x = lerpf(-0.6, 0.8, maxf(nose, land_kick))
	_head.rotation = Vector3(0.1 + sin(t * 2.0) * 0.08, sin(t * 0.9) * 0.4, 0.0)


func ragdoll_limbs() -> Array:
	return limbs_with([_head] + _talons)
