extends ProcModel
## "Ice-Bound Penitent" (CHASE, frozen monastery only): a monk who knelt in the snow in penance
## until the ice took him, and still shuffles on inside it. A hunched robed figure entombed up to
## the shoulders in a jagged block of blue ice, only the bowed hooded head and clasped hands free,
## glowing faintly from within. Slow, very sturdy, hard to push. On death the ice bursts: a ring of
## frost shards flies outward (short-range orbs, frost tint) - don't kill it point-blank.

const FROST := Color(0.6, 0.85, 1.0)
const SHARDS := 8

var _block: Node3D
var _head: Node3D
var _glow: MeshInstance3D


func build() -> void:
	feather_count = 0
	mote_count = 6
	light_color = FROST
	debris = [&"shard", &"shard"]
	debris_color = FROST
	death_style = &"shrink"
	death_time = 0.25
	stride = 0.7
	var ice := Art.mat(Color(0.62, 0.82, 1.0), 0.06, 0.0, 0.0, true, 0.9, &"crystal")
	var robe := m_cloth(Color(0.3, 0.27, 0.25))
	body = animated(Art.pivot(self))
	# The figure inside (seen through the ice) and the ice block around it.
	Art.part(body, Art.cylinder(0.14, 0.2), robe, Vector3(0.0, 0.4, 0.0), Vector3(1.0, 0.8, 0.9))
	_glow = keep(Art.part(body, Art.sphere(), Art.glow(FROST, 0.8, true, 0.7), Vector3(0.0, 0.45, 0.0), Vector3(0.36, 0.6, 0.32)))
	_block = animated(Art.pivot(body))
	Art.part(_block, Art.box(), ice, Vector3(0.0, 0.42, 0.0), Vector3(0.58, 0.84, 0.5), Vector3(0.0, 0.2, 0.05))
	for c: Array in [[Vector3(0.28, 0.7, 0.1), Vector3(0.0, 0.0, -0.5), 0.4], [Vector3(-0.3, 0.6, -0.05), Vector3(0.2, 0.0, 0.6), 0.45],
			[Vector3(0.1, 0.88, -0.2), Vector3(-0.4, 0.0, -0.2), 0.3], [Vector3(-0.15, 0.2, 0.25), Vector3(0.6, 0.0, 0.3), 0.35]]:
		Art.part(_block, Art.prism(), ice, c[0], Vector3(0.16, c[2], 0.16), c[1])
	_head = animated(Art.pivot(body, Vector3(0.0, 0.92, -0.04)))
	Art.part(_head, Art.sphere(), robe, Vector3.ZERO, Vector3(0.2, 0.22, 0.2))
	Art.part(_head, Art.cone(0.5), robe, Vector3(0.0, 0.1, 0.03), Vector3(0.16, 0.18, 0.16), Vector3(0.4, 0.0, 0.0))
	Art.part(_head, Art.sphere(), Art.mat(Art.OBSIDIAN, 0.6), Vector3(0.0, -0.02, -0.08), Vector3(0.12, 0.13, 0.06))
	for s: float in [-1.0, 1.0]:
		Art.part(_head, Art.sphere(), Art.glow(FROST, 2.0), Vector3(s * 0.03, -0.01, -0.105), Vector3(0.025, 0.012, 0.01))
	# Clasped hands breaking out of the ice in front.
	Art.part(body, Art.sphere(), m_skin(Color(0.65, 0.72, 0.8)), Vector3(0.0, 0.66, -0.27), Vector3(0.12, 0.1, 0.1))
	finish()


func pose(_delta: float) -> void:
	# A grinding shuffle: the block rocks and drags rather than stepping.
	var rock := sin(walk) * 0.07 * move_w
	body.rotation.z = rock
	body.position.y = absf(rock) * 0.2
	body.rotation.x = -0.05 * move_w + attack_kick * 0.1
	_head.rotation.x = 0.35 + sin(t * 0.8) * 0.04
	_glow.scale = Vector3(0.36, 0.6, 0.32) * (1.0 + 0.08 * sin(t * 2.0) + eye_flare * 0.3)


## The ice bursts: a ring of frost shards (short-lived orbs).
## (Called by Enemy.die() before any death FX, so a faction death can't skip it.)
func on_host_died(enemy: Enemy) -> void:
	var at := enemy.global_position
	_burst_shards.call_deferred(Vector3(at.x, 0.0, at.z), enemy.data.size)


static func _burst_shards(at: Vector3, s: float) -> void:
	if Game.world == null:
		return
	Sfx.play_at(&"frost_shatter", at + Vector3(0.0, 0.6, 0.0), 0.06, -2.0)
	HolyFX.hazard_tint = FROST
	var base := randf() * TAU
	for i in SHARDS:
		var a := base + TAU * float(i) / float(SHARDS)
		var dir := Vector3(cos(a), 0.0, sin(a))
		SarielOrb.fire(at + dir * 0.6 * s + Vector3(0.0, 0.6, 0.0), dir * 5.0, 8.0, 0.9)
	HolyFX.hazard_tint = Art.HOLY
