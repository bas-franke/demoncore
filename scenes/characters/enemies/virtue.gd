extends ProcModel
## "Virtue" (HEAL: a miracle that undoes your recent damage): an angel of miracles - a slender
## figure of rose-gold light in flowing pale robes, a veil, six slim wings held like a bell around
## it, a glowing heart-shaped reliquary at the breast and an hourglass of light turning above its
## head. It remembers how the Host stood a few seconds ago: when its wind-up (the miracle) completes,
## every angel within MIRACLE_RADIUS is restored to the health it had REWIND seconds earlier (if
## it had more then), with a golden rewind spiral. Kill it first, or your burst is undone.

const MIRACLE_RADIUS := 7.0
## Seconds of history the miracle reverses.
const REWIND := 3.0
const SAMPLE := 0.5
const ROSE := Color(1.0, 0.75, 0.6)

var _torso: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _heart: MeshInstance3D
var _glass: Node3D
## enemy instance id -> Array of [time, hp] samples (oldest first).
var _history := {}
var _sample_t := 0.0
var _prev_state := -1


func build() -> void:
	feather_count = 6
	feather_color = ROSE
	light_color = ROSE
	wing_speed = 2.2
	wing_amp = 0.12
	wing_lift = -0.1
	wing_sweep = 0.6
	var robe := Art.mat(Color(0.98, 0.92, 0.88), 0.6, 0.0, 0.05, true, 0.5, &"cloth")
	var veil := Art.glow(ROSE, 0.5, true, 0.6)
	var gold := Art.mat(Color(0.95, 0.72, 0.55), 0.35, 0.6, 0.1, true, 0.3, &"gold")
	body = animated(Art.pivot(self, Vector3(0.0, 0.3, 0.0)))
	Art.part(body, Art.cylinder(0.12, 0.28), robe, Vector3(0.0, 0.35, 0.0), Vector3(1.0, 0.7, 0.9))
	_torso = animated(Art.pivot(body, Vector3(0.0, 0.7, 0.0)))
	Art.part(_torso, Art.cylinder(0.15, 0.12), robe, Vector3(0.0, 0.16, 0.0), Vector3(1.0, 0.34, 0.8))
	_heart = keep(Art.part(_torso, Art.sphere(), Art.glow(ROSE, 2.4), Vector3(0.0, 0.2, -0.11), Vector3(0.09, 0.08, 0.05)))
	Art.part(_torso, Art.torus(0.75, 1.0), gold, Vector3(0.0, 0.2, -0.105), Vector3.ONE * 0.06, Vector3(PI * 0.5, 0.0, 0.0))
	var head := Art.pivot(_torso, Vector3(0.0, 0.42, 0.0))
	Art.part(head, Art.sphere(), Art.mat(Color(0.98, 0.88, 0.8), 0.4, 0.0, 0.0, true, 0.6, &"skin"), Vector3.ZERO, Vector3(0.14, 0.17, 0.15))
	Art.part(head, Art.sphere(), veil, Vector3(0.0, 0.02, 0.01), Vector3(0.19, 0.22, 0.19))
	Art.part(head, Art.box(), veil, Vector3(0.0, -0.18, 0.06), Vector3(0.18, 0.3, 0.02))
	# Hourglass of light above the head.
	_glass = animated(Art.pivot(head, Vector3(0.0, 0.26, 0.0)))
	Art.part(_glass, Art.cone(0.5), Art.glow(ROSE, 1.6), Vector3(0.0, 0.05, 0.0), Vector3(0.1, 0.1, 0.1), Vector3(PI, 0.0, 0.0))
	Art.part(_glass, Art.cone(0.5), Art.glow(ROSE, 1.6), Vector3(0.0, -0.05, 0.0), Vector3(0.1, 0.1, 0.1))
	for y: float in [-0.1, 0.1]:
		Art.part(_glass, Art.cylinder(0.5, 0.5), gold, Vector3(0.0, y, 0.0), Vector3(0.12, 0.012, 0.12))
	# Six slim wings held like a bell around it.
	solid_wing_pair(_torso, Vector3(0.0, 0.32, 0.08), 0.6, robe, gold, null, 0.06)
	solid_wing_pair(_torso, Vector3(0.0, 0.18, 0.08), 0.5, robe, gold, null, 0.06)
	solid_wing_pair(body, Vector3(0.0, 0.4, 0.08), 0.45, robe, gold, null, 0.06)
	var a := arm(_torso, Vector3(-0.16, 0.3, 0.0), 0.34, 0.025, robe, robe, 0.0, 0.0)
	_arm_l = a[0]
	var b := arm(_torso, Vector3(0.16, 0.3, 0.0), 0.34, 0.025, robe, robe, 0.0, 0.0)
	_arm_r = b[0]
	finish()


func pose(delta: float) -> void:
	var miracle := windup_w
	body.position.y = 0.3 + sin(t * 1.5) * 0.06
	_torso.rotation.x = -miracle * 0.15
	_arm_l.rotation = mixv(Vector3(0.9, 0.5, -0.1), Vector3(2.4, 0.0, -0.6), miracle)
	_arm_r.rotation = mixv(Vector3(0.9, -0.5, 0.1), Vector3(2.4, 0.0, 0.6), miracle)
	_heart.scale = Vector3(0.09, 0.08, 0.05) * (1.0 + miracle * 1.2 + 0.15 * sin(t * 4.0))
	_glass.rotation.z += delta * (0.6 + miracle * 6.0)
	wing_lift = -0.1 + miracle * 0.6
	wing_sweep = 0.6 - miracle * 0.5
	_record(delta)


## Samples the health of nearby angels every SAMPLE s, keeping REWIND s of history.
func _record(delta: float) -> void:
	_sample_t -= delta
	if _sample_t > 0.0:
		return
	_sample_t = SAMPLE
	var e := host()
	if e == null:
		return
	var now := t
	for other in enemies_near(e.global_position, MIRACLE_RADIUS + 3.0):
		var id := other.get_instance_id()
		var h: Array = _history.get(id, [])
		h.append([now, other.hp])
		while h.size() > 1 and now - float(h[0][0]) > REWIND + SAMPLE:
			h.pop_front()
		_history[id] = h


func _on_state_enter(state: int) -> void:
	super._on_state_enter(state)
	if _prev_state == State.WINDUP and (state == State.ATTACKING or state == State.RECOVER):
		_miracle()
	_prev_state = state


## Restores every nearby angel to its health REWIND seconds ago (never lower than now).
func _miracle() -> void:
	var e := host()
	if e == null:
		return
	EnemyModel.light_flash(e.global_position + Vector3(0.0, 1.0, 0.0), 1.4, ROSE, false)
	for other in enemies_near(e.global_position, MIRACLE_RADIUS):
		var h: Array = _history.get(other.get_instance_id(), [])
		if h.is_empty():
			continue
		var past := float(h[0][1])
		if past > other.hp and other.heal(past - other.hp, &"virtue_miracle") > 0.0:
			EnemyModel.spawn_motes(other.global_position + Vector3(0.0, 0.6, 0.0), 6, 0.8, ROSE)
			EnemyModel.shockwave(Vector3(other.global_position.x, 0.06, other.global_position.z), 1.0, ROSE, 0.4)
	_history.clear()
