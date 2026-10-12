extends ProcModel
## "Burned Crusader Revenant" (CHASE, rises once, ashen wastes only): a crusader who burned with
## his city and was too stubborn to stay dead. Charred plate fused to blackened bone, a cracked
## great helm with embers for eyes, the rags of a red-cross surcoat smouldering, a broken sword
## still gripped. When it falls it lies in its ashes for a moment and then pulls itself together
## again ONCE (the second body carries meta "revenant_risen" and stays down), at 60% health.

const RISE_DELAY := 1.6
const RISE_HP := 0.6
const EMBER := Color(1.0, 0.45, 0.15)
const HIP := 0.52

var _torso: Node3D
var _arm_r: Node3D
var _arm_l: Node3D
var _risen := false


func build() -> void:
	feather_count = 0
	mote_count = 8
	light_color = EMBER
	debris = [&"steel"]
	stride = 1.0
	var char_m := m_metal(Color(0.12, 0.1, 0.09), 0.7)
	var bone := Art.mat(Art.BONE.darkened(0.35), 0.7, 0.0, 0.5, true, 0.0, &"bone")
	var rag := m_cloth(Color(0.4, 0.33, 0.28))
	var red := m_cloth(Color(0.35, 0.06, 0.05))
	_torso = biped(HIP, 0.05, char_m, char_m, 0.09, 0.45)
	Art.part(body, Art.cylinder(0.15, 0.22), rag, Vector3(0.0, -0.12, 0.0), Vector3(1.0, 0.28, 0.85))
	Art.part(_torso, Art.cylinder(0.19, 0.15), char_m, Vector3(0.0, 0.2, 0.0), Vector3(1.0, 0.42, 0.78))
	# Exposed ribs where the plate burned through, ember cracks, a scorched surcoat.
	for k in 3:
		Art.part(_torso, Art.torus(0.8, 1.0), bone, Vector3(0.06, 0.16 + k * 0.06, -0.08), Vector3(0.08, 0.05, 0.06), Vector3(PI * 0.5, 0.0, 0.0))
	for k in 4:
		Art.part(_torso, Art.box(), Art.glow(EMBER, 1.8), Vector3(-0.08 + k * 0.05, 0.1 + k * 0.08, -0.14), Vector3(0.05, 0.008, 0.008), Vector3(0.0, 0.0, 0.6 - k * 0.3))
	Art.part(_torso, Art.box(), rag, Vector3(-0.05, 0.12, -0.13), Vector3(0.14, 0.34, 0.015), Vector3(0.0, 0.0, 0.15))
	Art.part(_torso, Art.box(), red, Vector3(-0.05, 0.16, -0.14), Vector3(0.03, 0.18, 0.01), Vector3(0.0, 0.0, 0.15))
	var head := Art.pivot(_torso, Vector3(0.0, 0.52, 0.0))
	Art.part(head, Art.cylinder(0.5, 0.5), char_m, Vector3(0.0, 0.02, 0.0), Vector3(0.2, 0.24, 0.21))
	Art.part(head, Art.box(), Art.glow(EMBER, 2.4), Vector3(0.0, 0.04, -0.105), Vector3(0.13, 0.02, 0.01))
	Art.part(head, Art.box(), Art.glow(EMBER, 1.4), Vector3(0.05, 0.12, -0.1), Vector3(0.01, 0.08, 0.01), Vector3(0.0, 0.0, 0.4))
	var a := arm(_torso, Vector3(-0.22, 0.38, 0.0), 0.4, 0.04, bone, char_m, 0.0, 0.0)
	_arm_l = a[0]
	var b := arm(_torso, Vector3(0.22, 0.38, 0.0), 0.4, 0.04, char_m, char_m, 0.0, 0.0)
	_arm_r = b[0]
	# Broken sword (half a blade, glowing at the break).
	var sw := Art.pivot(b[1], Vector3.ZERO, Vector3(-PI * 0.5, 0.0, 0.0))
	Art.part(sw, Art.box(), m_metal(Color(0.3, 0.28, 0.27), 0.6), Vector3(0.0, 0.2, 0.0), Vector3(0.06, 0.32, 0.015))
	Art.part(sw, Art.box(), Art.glow(EMBER, 2.0), Vector3(0.0, 0.37, 0.0), Vector3(0.06, 0.02, 0.016))
	Art.part(sw, Art.box(), char_m, Vector3(0.0, 0.03, 0.0), Vector3(0.18, 0.03, 0.03))
	finish()


func pose(_delta: float) -> void:
	biped_bob(HIP, 0.05)
	# A stiff, lurching walk with the sword dragging; it raises it to hack when close.
	_torso.rotation.x = -0.2 - 0.1 * move_w + sin(walk * 0.5) * 0.05 - attack_kick * 0.2
	_torso.rotation.z = sin(walk) * 0.08 * move_w
	_arm_r.rotation = Vector3(0.3 + attack_kick * 1.8 + sin(t * 1.3) * 0.05, 0.0, 0.2)
	_arm_l.rotation = Vector3(0.5 - sin(walk) * 0.3 * move_w, 0.0, -0.3)
	if not _risen:
		_risen = true
		var e := host()
		if e and e.has_meta(&"revenant_risen"):
			# The second body rises from the ashes (spawned on its predecessor's spot).
			e.hp = e.max_hp * RISE_HP
			EnemyModel.light_flash(e.global_position + Vector3(0.0, 0.5, 0.0), 0.9, EMBER, false)


## The first death: leave ashes, then a new body rises RISE_DELAY s later (once).
## (Called by Enemy.die() before any death FX, so a faction death can't skip it.)
func on_host_died(enemy: Enemy) -> void:
	if enemy.has_meta(&"revenant_risen") or enemy.data == null:
		return
	var hp_scale := enemy.max_hp / maxf(enemy.data.max_hp, 0.01)
	var at := enemy.global_position
	_rise_later(Vector3(at.x, 0.0, at.z), enemy.data, hp_scale)


static func _rise_later(at: Vector3, data: EnemyData, hp_scale: float) -> void:
	if Game.world == null:
		return
	var tree := Engine.get_main_loop() as SceneTree
	EnemyModel.spawn_motes(at + Vector3(0.0, 0.3, 0.0), 10, 0.8, EMBER)
	await tree.create_timer(RISE_DELAY, false).timeout
	if Game.world == null or not is_instance_valid(Game.world):
		return
	var r := (load("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate() as Enemy
	r.setup(data, hp_scale)
	r.set_meta(&"revenant_risen", true)
	Game.spawn(r, at)
	EnemyModel.shockwave(Vector3(at.x, 0.06, at.z), 1.4, EMBER, 0.4)
	Sfx.play_at(&"revenant_rise", at + Vector3(0.0, 0.6, 0.0), 0.06, -3.0)


func ragdoll_limbs() -> Array:
	return limbs_with([])
