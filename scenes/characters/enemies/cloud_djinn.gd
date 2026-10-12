extends ProcModel
## "Cloud Djinn" (CHASE, blinks through the storm, storm spire only): a spirit of the high storm
## bound into the Host's service - a muscular torso of grey-blue thunderhead with crackling eyes, a
## silver-turbaned head and a beard of rain, arms crossed in silver cuffs, its lower body a
## swirling funnel of cloud. Every BLINK_EVERY s it bursts into a puff of storm and re-forms a few
## metres behind the demon (telegraphed by the funnel spinning up).

const BLINK_EVERY := 6.5
const BLINK_TELL := 0.8
const BEHIND := 3.0
const BOLT := Color(0.7, 0.78, 1.0)

var _torso: Node3D
var _funnel: Array[Node3D] = []
var _arm_l: Node3D
var _arm_r: Node3D
var _blink_t := 4.0
var _spin := 0.0


func build() -> void:
	feather_count = 0
	mote_count = 10
	light_color = BOLT
	death_style = &"shrink"
	var cloud := Art.mat(Color(0.5, 0.55, 0.65), 0.95, 0.0, 0.1, true, 0.5, &"cloth")
	var dark := Art.mat(Color(0.32, 0.36, 0.46), 0.95, 0.0, 0.1, true, 0.4, &"cloth")
	var silver := m_metal(Color(0.85, 0.86, 0.9), 0.25)
	body = animated(Art.pivot(self, Vector3(0.0, 0.2, 0.0)))
	# Funnel: stacked cloud rings that churn.
	for i in 5:
		var f := animated(Art.pivot(body, Vector3(0.0, 0.08 + i * 0.12, 0.0)))
		var r := 0.08 + i * 0.05
		for k in 4:
			var a := TAU * float(k) / 4.0
			Art.part(f, Art.sphere(), cloud if k % 2 == 0 else dark, Vector3(cos(a), 0.0, sin(a)) * r, Vector3.ONE * (0.12 + i * 0.03))
		_funnel.append(f)
	_torso = animated(Art.pivot(body, Vector3(0.0, 0.7, 0.0)))
	Art.part(_torso, Art.sphere(), cloud, Vector3(0.0, 0.15, 0.0), Vector3(0.5, 0.42, 0.36))
	Art.part(_torso, Art.sphere(), dark, Vector3(0.0, 0.05, 0.0), Vector3(0.36, 0.3, 0.3))
	var head := Art.pivot(_torso, Vector3(0.0, 0.46, 0.0))
	Art.part(head, Art.sphere(), cloud, Vector3.ZERO, Vector3(0.2, 0.22, 0.2))
	Art.part(head, Art.sphere(), silver, Vector3(0.0, 0.09, 0.0), Vector3(0.24, 0.14, 0.24))
	Art.part(head, Art.sphere(), Art.mat(Color(0.3, 0.5, 0.9), 0.1, 0.0, 0.0, true, 0.9, &"crystal"), Vector3(0.0, 0.12, -0.11), Vector3.ONE * 0.04)
	for s: float in [-1.0, 1.0]:
		Art.part(head, Art.sphere(), Art.glow(BOLT, 2.6), Vector3(s * 0.045, 0.01, -0.09), Vector3(0.04, 0.02, 0.015))
	# Beard of rain: thin glowing streaks.
	for k in 5:
		Art.part(head, Art.box(), Art.glow(Color(0.7, 0.85, 1.0), 0.8, true, 0.6), Vector3(-0.04 + k * 0.02, -0.16, -0.06), Vector3(0.006, 0.14, 0.006))
	for s: float in [-1.0, 1.0]:
		var p := limb_pivot(_torso, Vector3(s * 0.26, 0.28, 0.0))
		limb(p, Vector3.ZERO, Vector3(-s * 0.1, -0.2, -0.16), 0.07, cloud)
		Art.part(p, Art.cylinder(0.5, 0.5), silver, Vector3(-s * 0.08, -0.17, -0.13), Vector3(0.14, 0.06, 0.14), Vector3(0.6, 0.0, 0.0))
		if s < 0.0:
			_arm_l = p
		else:
			_arm_r = p
	finish()


func pose(delta: float) -> void:
	var tell := clampf(1.0 - _blink_t / BLINK_TELL, 0.0, 1.0)
	_spin += delta * (2.0 + move_w * 2.0 + tell * 14.0)
	for i in _funnel.size():
		_funnel[i].rotation.y = _spin * (1.0 + float(i) * 0.3) * (1.0 if i % 2 == 0 else -1.0)
	body.position.y = 0.2 + sin(t * 1.7) * 0.06
	_torso.rotation.x = -0.15 * move_w - attack_kick * 0.2
	_torso.scale = Vector3.ONE * (1.0 - tell * 0.5)
	_arm_l.rotation = Vector3(attack_kick * 1.2, 0.0, 0.0)
	_arm_r.rotation = Vector3(attack_kick * 1.4, 0.0, 0.0)
	_blink(delta)


## Bursts into storm and re-forms behind the demon.
func _blink(delta: float) -> void:
	var e := host()
	if e == null or e.is_dying:
		return
	_blink_t -= delta
	if _blink_t > 0.0:
		return
	_blink_t = BLINK_EVERY * randf_range(0.85, 1.2)
	var p := Game.player
	if p == null or p.is_dead:
		return
	var from := e.global_position
	var away := (p.global_position - from)
	away.y = 0.0
	var dir := away.normalized() if away.length_squared() > 0.01 else Vector3.FORWARD
	var to := p.global_position + dir * BEHIND
	to.y = 0.0
	if ResourceLoader.exists("res://scenes/objectives/objective_fx.gd"):
		to = ObjectiveFX.walkable(to)
	EnemyModel.poof(from + Vector3(0.0, 0.6, 0.0), Color(0.55, 0.6, 0.7), BOLT, 10, 0.5, 0.8)
	e.global_position = to
	e.reset_physics_interpolation()
	EnemyModel.light_flash(to + Vector3(0.0, 0.8, 0.0), 0.8, BOLT, false)
	Sfx.play_at(&"djinn_blink", to + Vector3(0.0, 0.8, 0.0), 0.08, -4.0)


func ragdoll_limbs() -> Array:
	return limbs_with([_torso])
