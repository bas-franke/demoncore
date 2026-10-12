extends ProcModel
## "Crossbow Militia" (SHOOT, a squad that moves as one): three townsmen of the parish watch in a
## tight triangle - quilted gambesons in the city colours, kettle helmets, a sergeant with a
## halberd and a banner at the back, two crossbowmen in front. One enemy, one hit box, but the
## volley is three bolts: the Enemy fires the centre one (HolyBolt), the two flankers fire theirs
## on the same beat in a narrow fan. Wind-up: both crossbows raised and aimed together.

const SPREAD := 0.22
const BOLT_SCENE := "res://scenes/characters/projectiles/holy_bolt.tscn"

var _men: Array[Node3D] = []
var _bow_arms: Array[Node3D] = []
var _banner: Node3D


func build() -> void:
	feather_count = 0
	mote_count = 4
	stride = 1.0
	var tunic := m_cloth(Color(0.42, 0.36, 0.22))
	var blue := m_cloth(Color(0.2, 0.26, 0.42))
	var skin := m_skin(Color(0.82, 0.66, 0.54))
	var iron := m_metal(Color(0.45, 0.45, 0.46), 0.5)
	var slots: Array[Vector3] = [Vector3(-0.32, 0.0, -0.2), Vector3(0.32, 0.0, -0.2), Vector3(0.0, 0.0, 0.35)]
	for i in 3:
		var m := animated(Art.pivot(self, slots[i]))
		_men.append(m)
		for s: float in [-1.0, 1.0]:
			var hip := Art.pivot(m, Vector3(s * 0.06, 0.4, 0.0))
			limb(hip, Vector3.ZERO, Vector3(0.0, -0.37, 0.0), 0.035, m_cloth(Color(0.2, 0.18, 0.16)))
			Art.part(hip, Art.box(), m_leather(), Vector3(0.0, -0.39, -0.03), Vector3(0.07, 0.04, 0.12))
			add_leg(hip, (0.0 if s < 0.0 else PI) + float(i) * 0.6, 0.55, 0.42)
		# Quilted gambeson in the watch colours, kettle hat.
		Art.part(m, Art.cylinder(0.15, 0.18), tunic, Vector3(0.0, 0.55, 0.0), Vector3(1.0, 0.36, 0.85))
		Art.part(m, Art.box(), blue, Vector3(0.0, 0.58, -0.135), Vector3(0.1, 0.3, 0.02))
		Art.part(m, Art.sphere(), skin, Vector3(0.0, 0.84, 0.0), Vector3(0.15, 0.17, 0.15))
		Art.part(m, Art.cylinder(0.5, 0.5), iron, Vector3(0.0, 0.89, 0.0), Vector3(0.28, 0.02, 0.28))
		Art.part(m, Art.sphere(), iron, Vector3(0.0, 0.92, 0.0), Vector3(0.16, 0.1, 0.16))
		var sh := limb_pivot(m, Vector3(0.16, 0.68, 0.0))
		limb(sh, Vector3.ZERO, Vector3(0.0, -0.3, -0.02), 0.03, tunic)
		if i < 2:
			# Crossbow along the arm's forward when raised.
			var cb := Art.pivot(sh, Vector3(0.0, -0.3, -0.02), Vector3(-PI * 0.5, 0.0, 0.0))
			Art.part(cb, Art.box(), m_wood(), Vector3(0.0, 0.12, 0.0), Vector3(0.04, 0.32, 0.05))
			for s: float in [-1.0, 1.0]:
				Art.part(cb, Art.box(), iron, Vector3(s * 0.1, 0.26, 0.0), Vector3(0.2, 0.02, 0.02), Vector3(0.0, 0.0, -s * 0.3))
			_bow_arms.append(sh)
		else:
			# Sergeant: halberd and the watch banner.
			var hb := Art.pivot(sh, Vector3(0.0, -0.3, -0.02), Vector3(PI, 0.0, 0.0))
			limb(hb, Vector3(0.0, -0.3, 0.0), Vector3(0.0, 0.9, 0.0), 0.014, m_wood())
			Art.part(hb, Art.prism(), iron, Vector3(0.0, 0.85, -0.05), Vector3(0.02, 0.18, 0.12))
			limb(m, Vector3(-0.12, 0.4, 0.08), Vector3(-0.12, 1.5, 0.08), 0.012, m_wood())
			_banner = animated(Art.pivot(m, Vector3(-0.12, 1.45, 0.08)))
			Art.part(_banner, Art.box(), blue, Vector3(0.0, -0.18, 0.14), Vector3(0.01, 0.32, 0.26))
			Art.part(_banner, Art.box(), m_cloth(Color(0.9, 0.8, 0.4)), Vector3(-0.006, -0.18, 0.14), Vector3(0.005, 0.1, 0.1))
	finish()


func play_attack() -> void:
	super.play_attack()
	_flank_volley()


## The two flankers loose with the centre bolt: aimed at the demon, fanned by SPREAD.
func _flank_volley() -> void:
	var e := host()
	var p := Game.player
	if e == null or p == null or Game.world == null or not ResourceLoader.exists(BOLT_SCENE):
		return
	var to := p.global_position - e.global_position
	to.y = 0.0
	if to.length_squared() < 0.01:
		return
	var dir := to.normalized()
	var scene := load(BOLT_SCENE) as PackedScene
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var b := scene.instantiate() as Node3D
		b.set(&"velocity", dir.rotated(Vector3.UP, side * SPREAD) * e.data.projectile_speed)
		b.set(&"damage", e.data.projectile_damage * 0.75)
		var muzzle := _men[i].global_position + Vector3(0.0, 0.7 * body_scale, 0.0) + dir * 0.3
		Game.spawn.call_deferred(b, muzzle)


func pose(_delta: float) -> void:
	var aim := maxf(windup_w, strike_w)
	for i in _men.size():
		_men[i].position.y = absf(sin(walk + float(i))) * 0.025 * move_w
		_men[i].rotation.x = -0.06 * move_w
	for a in _bow_arms:
		a.rotation = mixv(Vector3(0.4 - sin(walk) * 0.15 * move_w, 0.0, 0.0), Vector3(1.5 + attack_kick * 0.3, 0.0, 0.0), aim)
	if _banner:
		_banner.rotation.x = 0.3 * move_w + sin(t * 3.0) * 0.1


## Ragdoll death (characters-polish DeathFx): the pivots that flop loose.
func ragdoll_limbs() -> Array:
	return limbs_with(_men + _bow_arms)
