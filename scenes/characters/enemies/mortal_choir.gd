extends ProcModel
## "Mortal Choir" (HEAL + hymn buff): three parish singers in white surplices over red cassocks,
## hymnals open, mouths round, led by a precentor with a tall staff - one enemy that moves as a
## little procession. Their hymn emboldens the Host: at the end of each wind-up (the hymn), every
## angel within HYMN_RADIUS is blessed for HYMN_TIME seconds (+35% speed, +25% contact damage, a
## gold note ring over it). The choir itself is frail and keeps its distance (HEAL behaviour).

const HYMN_RADIUS := 7.0
const HYMN_TIME := 5.0
const NOTE := Color(1.0, 0.86, 0.45)

var _singers: Array[Node3D] = []
var _mouths: Array[MeshInstance3D] = []
var _prev_state := -1


func build() -> void:
	feather_count = 0
	mote_count = 6
	light_color = NOTE
	stride = 0.9
	var surplice := m_cloth(Color(0.92, 0.9, 0.86))
	var cassock := m_cloth(Color(0.5, 0.08, 0.08))
	var skin := m_skin(Color(0.84, 0.7, 0.6))
	var slots: Array[Vector3] = [Vector3(-0.3, 0.0, 0.1), Vector3(0.3, 0.0, 0.1), Vector3(0.0, 0.0, -0.3)]
	for i in 3:
		var m := animated(Art.pivot(self, slots[i]))
		_singers.append(m)
		Art.part(m, Art.cylinder(0.12, 0.2), cassock, Vector3(0.0, 0.3, 0.0), Vector3(1.0, 0.6, 0.9))
		Art.part(m, Art.cylinder(0.13, 0.21), surplice, Vector3(0.0, 0.55, 0.0), Vector3(1.0, 0.36, 0.9))
		Art.part(m, Art.sphere(), skin, Vector3(0.0, 0.84, 0.0), Vector3(0.15, 0.17, 0.15))
		Art.part(m, Art.sphere(), m_cloth(Color(0.3, 0.22, 0.15)), Vector3(0.0, 0.88, 0.015), Vector3(0.155, 0.11, 0.155))
		_mouths.append(keep(Art.part(m, Art.sphere(), Art.mat(Color(0.2, 0.05, 0.05), 0.5), Vector3(0.0, 0.8, -0.075), Vector3(0.035, 0.035, 0.015))))
		# Open hymnal held at the chest.
		var bk := Art.pivot(m, Vector3(0.0, 0.62, -0.14), Vector3(-0.8, 0.0, 0.0))
		for s: float in [-1.0, 1.0]:
			Art.part(bk, Art.box(), Art.mat(Art.IVORY, 0.8, 0.0, 0.2, true, 0.0, &"parchment"), Vector3(s * 0.045, 0.0, 0.0), Vector3(0.09, 0.008, 0.12), Vector3(0.0, 0.0, -s * 0.15))
			limb(m, Vector3(s * 0.12, 0.66, 0.0), Vector3(s * 0.07, 0.6, -0.13), 0.025, surplice)
		if i == 2:
			# The precentor's staff.
			limb(m, Vector3(0.16, 0.0, -0.04), Vector3(0.16, 1.3, -0.04), 0.014, m_wood())
			Art.part(m, Art.sphere(), Art.mat(Art.GOLD, 0.35, 0.6), Vector3(0.16, 1.32, -0.04), Vector3.ONE * 0.06)
	finish()


func pose(_delta: float) -> void:
	var hymn := windup_w
	for i in _singers.size():
		var m := _singers[i]
		# A slow procession: they sway rather than step.
		m.position.y = absf(sin(walk * 0.5 + float(i))) * 0.02 * move_w
		m.rotation.z = sin(walk * 0.5 + float(i) * 1.3) * 0.05 * move_w + sin(t * 1.2 + float(i)) * 0.02
		m.rotation.x = -hymn * 0.15
		var o := 1.0 + hymn * 1.2 + 0.3 * absf(sin(t * (3.0 + float(i))))
		_mouths[i].scale = Vector3(0.035, 0.035 * o, 0.015)


## The hymn lands when a wind-up completes (WINDUP -> attack or recovery; a wind-up cut short by
## a stagger goes back to MOVING and blesses nobody).
func _on_state_enter(state: int) -> void:
	super._on_state_enter(state)
	if _prev_state == State.WINDUP and (state == State.ATTACKING or state == State.RECOVER):
		_sing_blessing()
	_prev_state = state


func _sing_blessing() -> void:
	var e := host()
	if e == null:
		return
	EnemyModel.light_flash(e.global_position + Vector3(0.0, 1.0, 0.0), 1.0, NOTE, false)
	for other in enemies_near(e.global_position, HYMN_RADIUS):
		HymnBlessing.bless(other, HYMN_TIME)
