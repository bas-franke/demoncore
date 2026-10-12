extends ProcModel
## "Carrion Angel" (HOP dive, feeds on the dead, ashen wastes only): an angel of the battlefield
## pyres turned vulture - a bald, grey-skinned head with a hooked bone beak-mask, a ruff of
## soot-black feathers, ragged ash-grey wings, a rusted censer of bones, long taloned feet. It
## circles low and dives on the demon. Whenever anything dies within FEED_RADIUS it gorges: heals
## FEED_HEAL of its max health (Enemy.heal) and its eyes flare.

const FEED_RADIUS := 7.0
const FEED_HEAL := 0.2
const HEIGHT := 0.65
const LEAP := 1.8

var _head: Node3D
var _legs_t: Array[Node3D] = []
var _connected := false


func build() -> void:
	feather_count = 6
	feather_color = Color(0.25, 0.23, 0.22)
	light_color = Color(1.0, 0.6, 0.3)
	wing_speed = 3.2
	wing_amp = 0.35
	wing_lift = 0.0
	wing_sweep = 0.3
	stride = 1.3
	var ash := Art.mat(Color(0.4, 0.39, 0.38), 0.9, 0.0, 0.4, true, 0.2, &"feather")
	var soot := Art.mat(Color(0.08, 0.07, 0.07), 0.9, 0.0, 0.3, true, 0.3, &"feather")
	var skin := m_skin(Color(0.55, 0.52, 0.5))
	var bone := Art.mat(Art.BONE.darkened(0.2), 0.6, 0.0, 0.4, true, 0.0, &"bone")
	body = animated(Art.pivot(self, Vector3(0.0, HEIGHT, 0.0)))
	Art.part(body, Art.sphere(), ash, Vector3(0.0, 0.0, 0.0), Vector3(0.3, 0.36, 0.4))
	Art.part(body, Art.torus(0.4, 1.0), soot, Vector3(0.0, 0.16, -0.08), Vector3(0.18, 0.22, 0.16))
	solid_wing_pair(body, Vector3(0.0, 0.12, 0.04), 0.85, ash, soot, soot, 0.1)
	_head = animated(Art.pivot(body, Vector3(0.0, 0.24, -0.18)))
	Art.part(_head, Art.sphere(), skin, Vector3.ZERO, Vector3(0.13, 0.15, 0.15))
	Art.part(_head, Art.cone(0.5), bone, Vector3(0.0, -0.02, -0.12), Vector3(0.06, 0.16, 0.07), Vector3(-PI * 0.5 - 0.5, 0.0, 0.0))
	for s: float in [-1.0, 1.0]:
		eye(_head, Vector3(s * 0.045, 0.02, -0.06), 0.025, Vector3(s * 0.5, 0.0, -1.0), true, Color(1.0, 0.55, 0.2))
	# A rusted bone censer hanging from a chain around the neck.
	limb(body, Vector3(0.0, 0.1, -0.2), Vector3(0.0, -0.12, -0.24), 0.005, m_metal(Color(0.4, 0.25, 0.15), 0.8))
	Art.part(body, Art.sphere(), bone, Vector3(0.0, -0.17, -0.25), Vector3(0.09, 0.09, 0.09))
	Art.part(body, Art.sphere(), Art.glow(Art.EMBER, 1.4), Vector3(0.0, -0.17, -0.25), Vector3.ONE * 0.05)
	# Long taloned legs, tucked when flying.
	for s: float in [-1.0, 1.0]:
		var lg := limb_pivot(body, Vector3(s * 0.08, -0.14, 0.04))
		limb(lg, Vector3.ZERO, Vector3(0.0, -0.32, 0.03), 0.02, skin)
		for c in 3:
			Art.part(lg, Art.cone(0.5), bone, Vector3((float(c) - 1.0) * 0.025, -0.34, -0.03), Vector3(0.015, 0.06, 0.015), Vector3(-PI * 0.5 - 0.6, 0.0, 0.0))
		_legs_t.append(lg)
	finish()


func pose(_delta: float) -> void:
	if not _connected and host():
		_connected = true
		Game.enemy_died.connect(_on_enemy_died)
	var crouch := windup_w
	var dive := strike_w
	var lift := 0.0
	if dive > 0.05:
		lift = sin(clampf(state_progress, 0.0, 1.0) * PI) * LEAP * dive
	body.position.y = HEIGHT + sin(t * wing_speed) * 0.05 + crouch * 0.3 + lift - land_kick * 0.2
	var nose := clampf(state_progress * 2.0 - 0.8, 0.0, 1.0) * dive
	body.rotation.x = -0.15 * move_w + crouch * 0.3 - nose * 0.7
	wing_lift = 0.0 + crouch * 0.7 - nose * 0.4
	wing_sweep = 0.3 + nose * 0.8
	for l in _legs_t:
		l.rotation.x = lerpf(-0.9, 0.6, maxf(nose, land_kick))
	_head.rotation.x = 0.2 + sin(t * 1.4) * 0.1 - crouch * 0.2


## Feeds on any death nearby (heals through the Enemy API so tallies / numbers see it).
func _on_enemy_died(pos: Vector3, _data: Resource) -> void:
	var e := host()
	if e == null or not is_instance_valid(e) or e.is_dying:
		return
	if e.global_position.distance_to(pos) > FEED_RADIUS:
		return
	if e.heal(e.max_hp * FEED_HEAL, &"carrion_feast") > 0.0:
		eye_flare = 1.0
		EnemyModel.spawn_motes(pos + Vector3(0.0, 0.3, 0.0), 4, 0.6, Color(0.6, 0.15, 0.1))


func _exit_tree() -> void:
	if Game.enemy_died.is_connected(_on_enemy_died):
		Game.enemy_died.disconnect(_on_enemy_died)


func ragdoll_limbs() -> Array:
	return limbs_with([_head] + _legs_t)
