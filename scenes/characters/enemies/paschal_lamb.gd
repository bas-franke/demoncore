extends ProcModel
## "Paschal Lamb" (CHASE, harmless, punishes careless slaughter): a small spotless white lamb with
## a gold halo and a tiny banner of victory over its shoulder, trotting among the Host. It barely
## hurts you, but killing it is a sacrifice: it bursts in a wave of light that heals every angel
## within HEAL_RADIUS by HEAL_FRACTION of their max health. Kill it away from the crowd, or not at
## all.

const HEAL_RADIUS := 6.0
const HEAL_FRACTION := 0.4

var _head: Node3D
var _tail: Node3D


func build() -> void:
	feather_count = 0
	mote_count = 10
	stride = 0.8
	var wool := Art.mat(Color(0.96, 0.95, 0.92), 0.95, 0.0, 0.05, true, 0.4, &"cloth")
	var face := m_skin(Color(0.25, 0.22, 0.22))
	body = animated(Art.pivot(self, Vector3(0.0, 0.3, 0.0)))
	# Puffy wool body: a cluster of spheres.
	for c: Vector3 in [Vector3(0.0, 0.05, 0.0), Vector3(0.0, 0.08, -0.12), Vector3(0.0, 0.07, 0.12), Vector3(0.08, 0.06, 0.0), Vector3(-0.08, 0.06, 0.0)]:
		Art.part(body, Art.sphere(), wool, c, Vector3(0.22, 0.2, 0.24))
	for s: float in [-1.0, 1.0]:
		beast_leg(body, Vector3(s * 0.06, -0.02, -0.1), 0.3, 0.018, face, face, 0.0 if s < 0.0 else PI, 0.6)
		beast_leg(body, Vector3(s * 0.06, -0.02, 0.12), 0.3, 0.018, face, face, PI if s < 0.0 else 0.0, 0.6, true)
	_head = animated(Art.pivot(body, Vector3(0.0, 0.14, -0.22)))
	Art.part(_head, Art.sphere(), face, Vector3(0.0, 0.0, -0.03), Vector3(0.1, 0.11, 0.14))
	Art.part(_head, Art.sphere(), wool, Vector3(0.0, 0.05, 0.02), Vector3(0.13, 0.08, 0.12))
	for s: float in [-1.0, 1.0]:
		Art.part(_head, Art.sphere(), face, Vector3(s * 0.07, 0.02, 0.01), Vector3(0.08, 0.03, 0.04), Vector3(0.0, 0.0, -s * 0.4))
		Art.part(_head, Art.sphere(), Art.glow(Art.HOLY_WHITE, 1.6), Vector3(s * 0.035, 0.02, -0.08), Vector3.ONE * 0.02)
	halo(_head, Vector3(0.0, 0.14, 0.02), 0.08, 2.6)
	# The banner of victory: a little cross-staff with a white pennant over the shoulder.
	limb(body, Vector3(0.06, 0.1, 0.05), Vector3(0.14, 0.5, 0.12), 0.008, m_gold())
	Art.part(body, Art.box(), m_cloth(Art.HOLY_WHITE), Vector3(0.15, 0.44, 0.18), Vector3(0.006, 0.08, 0.12))
	Art.part(body, Art.box(), m_cloth(Color(0.6, 0.07, 0.06)), Vector3(0.155, 0.44, 0.18), Vector3(0.004, 0.06, 0.02))
	_tail = animated(Art.pivot(body, Vector3(0.0, 0.1, 0.24)))
	Art.part(_tail, Art.sphere(), wool, Vector3(0.0, 0.0, 0.03), Vector3.ONE * 0.07)
	finish()


func pose(_delta: float) -> void:
	body.position.y = 0.3 + absf(sin(walk)) * 0.04 * move_w
	_head.rotation.x = sin(t * 1.2) * 0.1 + (absf(sin(t * 0.4)) * 0.4 if move_w < 0.2 else 0.0)
	_tail.rotation.y = sin(t * 12.0) * 0.5


## The sacrifice: heals every nearby angel.
## (Called by Enemy.die() before any death FX, so a faction death can't skip it.)
func on_host_died(enemy: Enemy) -> void:
	var at := enemy.global_position
	for e in enemies_near(at, HEAL_RADIUS):
		e.heal(e.max_hp * HEAL_FRACTION, &"paschal_lamb")
		EnemyModel.spawn_motes(e.global_position + Vector3(0.0, 0.6, 0.0), 4, 0.7, Art.HOLY)
	EnemyModel.shockwave(Vector3(at.x, 0.06, at.z), HEAL_RADIUS, Art.HOLY, 0.6)
	EnemyModel.light_flash(at + Vector3(0.0, 0.5, 0.0), 1.8, Art.HOLY_WHITE, true)


## Ragdoll death (characters-polish DeathFx): the pivots that flop loose.
func ragdoll_limbs() -> Array:
	return limbs_with([_head, _tail])
