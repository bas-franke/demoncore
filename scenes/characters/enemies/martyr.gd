extends ProcModel
## "Martyr" (CHASE): a mortal saint who wants to die for the faith, and is more dangerous dead.
## Barefoot in a bloodied white shift, arrows standing out of the chest and back, hands raised in
## prayer, a thin gold halo and a calm face turned to the sky. On death the body bursts in a ring
## of holy fire (a short telegraphed PyreBurst: step away) and its soul rises as a Martyr's Shade
## (res://data/enemies/martyr_shade.tres), a fast vengeful ghost.

const HIP := 0.46
const SHADE_PATH := "res://data/enemies/martyr_shade.tres"
const BURST_RADIUS := 2.2
const BURST_TELL := 0.9
const BURST_DAMAGE := 14.0

var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D


func build() -> void:
	feather_count = 0
	mote_count = 8
	stride = 1.0
	var shift := m_cloth(Color(0.9, 0.88, 0.82))
	var blood := Art.mat(Color(0.5, 0.05, 0.05), 0.5, 0.0, 0.1, true, 0.2, &"cloth")
	var skin := m_skin(Color(0.85, 0.72, 0.62))
	var shaft := Art.mat(Color(0.45, 0.35, 0.24), 0.8, 0.0, 0.3, true, 0.0, &"wood")
	_torso = biped(HIP, 0.035, skin, skin, 0.07, 0.45)
	Art.part(body, Art.cylinder(0.13, 0.2), shift, Vector3(0.0, -0.14, 0.0), Vector3(1.0, 0.34, 0.85))
	Art.part(_torso, Art.cylinder(0.15, 0.13), shift, Vector3(0.0, 0.18, 0.0), Vector3(1.0, 0.38, 0.8))
	# Blood stains and arrows (shafts with white fletching) sticking out front and back.
	Art.part(_torso, Art.sphere(), blood, Vector3(0.04, 0.22, -0.1), Vector3(0.1, 0.12, 0.02))
	Art.part(_torso, Art.sphere(), blood, Vector3(-0.06, 0.06, -0.11), Vector3(0.08, 0.1, 0.02))
	for a: Array in [[Vector3(0.04, 0.22, -0.1), Vector3(0.08, 0.28, -0.32)], [Vector3(-0.06, 0.08, -0.1), Vector3(-0.12, 0.05, -0.3)],
			[Vector3(0.05, 0.3, 0.1), Vector3(0.12, 0.4, 0.32)]]:
		limb(_torso, a[0], a[1], 0.007, shaft)
		Art.part(_torso, Art.box(), m_cloth(Art.HOLY_WHITE), a[1], Vector3(0.04, 0.005, 0.05))
	_head = animated(Art.pivot(_torso, Vector3(0.0, 0.46, 0.0)))
	Art.part(_head, Art.sphere(), skin, Vector3.ZERO, Vector3(0.15, 0.18, 0.16))
	Art.part(_head, Art.sphere(), m_cloth(Color(0.3, 0.22, 0.15)), Vector3(0.0, 0.04, 0.02), Vector3(0.16, 0.13, 0.16))
	for s: float in [-1.0, 1.0]:
		Art.part(_head, Art.box(), Art.mat(Art.OBSIDIAN, 0.5), Vector3(s * 0.035, 0.01, -0.078), Vector3(0.03, 0.005, 0.01))
	halo(_head, Vector3(0.0, 0.14, 0.04), 0.12, 2.6)
	var a := arm(_torso, Vector3(-0.17, 0.34, 0.0), 0.34, 0.03, skin, skin, 0.0, 0.0)
	_arm_l = a[0]
	var b := arm(_torso, Vector3(0.17, 0.34, 0.0), 0.34, 0.03, skin, skin, 0.0, 0.0)
	_arm_r = b[0]
	finish()


func pose(_delta: float) -> void:
	biped_bob(HIP, 0.03)
	# A slow, serene walk with hands raised in prayer and the face lifted to heaven.
	_torso.rotation.x = 0.05 + sin(t * 1.1) * 0.03
	_head.rotation.x = -0.35 + sin(t * 0.8) * 0.05
	_head.rotation.y = sin(t * 0.5) * 0.15
	_arm_l.rotation = Vector3(1.9 + sin(t * 2.0) * 0.08, 0.0, 0.35)
	_arm_r.rotation = Vector3(1.9 + sin(t * 2.0) * 0.08, 0.0, -0.35)


## More dangerous after death: a ring of fire bursts from the body and its shade rises.
## (Called by Enemy.die() before any death FX, so a faction death can't skip it.)
func on_host_died(enemy: Enemy) -> void:
	var ground := Vector3(enemy.global_position.x, 0.0, enemy.global_position.z)
	PyreBurst.cast(ground, BURST_RADIUS * enemy.data.size, BURST_TELL, BURST_DAMAGE)
	_rise_shade.call_deferred(ground)


static func _rise_shade(at: Vector3) -> void:
	if Game.world == null or not ResourceLoader.exists(SHADE_PATH):
		return
	var data := load(SHADE_PATH) as EnemyData
	var e := (load("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate() as Enemy
	# [gameplay] scale like every spawned enemy (RunState difficulty: minutes + heat + map)
	e.setup(data, RunState.enemy_hp_mult(), RunState.enemy_damage_mult(), RunState.enemy_speed_mult())
	Game.spawn(e, at + Vector3(0.0, 0.0, 0.3))
	EnemyModel.light_flash(at + Vector3(0.0, 0.6, 0.0), 0.8, Art.HOLY_WHITE, false)
