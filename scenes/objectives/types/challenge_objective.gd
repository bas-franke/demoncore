extends Objective
## "Ring the Bell of Challenge": a bronze bell hangs from a gallows frame. Stand beneath it for
## `ring_time` seconds to ring it and call a boss early (`boss` roster id, "" = the next in the
## rotation). Slay that boss for a large reward. Purely optional, purely a dare.
## params: radius, ring_time, boss.

var _radius := 2.2
var _ring := 0.0
var _bell: Node3D
var _zone: BossTelegraph
var _waiting_boss := false


func _build() -> void:
	_radius = float(param("radius", 2.2))
	var wood := Art.mat(Art.LEATHER.darkened(0.2), 0.9, 0.0, 0.5, false, 0.0, &"wood")
	var bronze := Art.mat(Art.BRONZE, 0.35, 1.0, 0.35, false, 0.0, &"gold")
	for sx: float in [-1.0, 1.0]:
		Art.part(self, Art.box(), wood, Vector3(sx * 1.1, 1.5, 0.0), Vector3(0.22, 3.0, 0.22))
	Art.part(self, Art.box(), wood, Vector3(0.0, 3.0, 0.0), Vector3(2.6, 0.24, 0.26))
	_bell = Art.pivot(self, Vector3(0.0, 2.88, 0.0))
	Art.part(_bell, Art.cylinder(0.25, 0.6), bronze, Vector3(0.0, -0.55, 0.0), Vector3(1.0, 0.9, 1.0))
	Art.part(_bell, Art.torus(0.85, 1.0), bronze, Vector3(0.0, -1.0, 0.0), Vector3.ONE * 0.62)
	Art.part(_bell, Art.sphere(), bronze, Vector3(0.0, -1.0, 0.0), Vector3.ONE * 0.16)
	_zone = ObjectiveFX.zone(self)
	status_text = "Ring the bell"
	Game.boss_died.connect(_on_boss_died)


func _tick(delta: float) -> void:
	if state == State.ACTIVE:
		_bell.rotation.z = sin(age * 3.0) * 0.08
		status_text = "Slay the boss" if get_tree().get_first_node_in_group(&"boss") else "It comes..."
		progress = 0.5
		return
	var inside := _player_distance() <= _radius
	_ring = clampf(_ring + (delta if inside else -delta) / maxf(float(param("ring_time", 2.0)), 0.1), 0.0, 1.0)
	_bell.rotation.z = sin(age * 9.0) * 0.35 * _ring
	_zone.show_disc(global_position, _radius, Art.HOLY, _ring, 0.5 + 0.4 * _ring, 1.2)
	status_text = "Ring it?" if _ring <= 0.0 else "%d%%" % roundi(_ring * 100.0)
	if _ring >= 1.0:
		activate()


func _on_activated() -> void:
	_zone.hide_now()
	Sfx.play(&"toll", 0.0, 6.0)
	Sfx.play(&"bell_distant", 0.0, 0.0)
	get_tree().call_group(&"camera_rig", &"shake", 0.3)
	HolyFX.flash(_bell.global_position + Vector3(0.0, -0.8, 0.0), 3.0, 0.6, Art.HOLY, 2.5)
	EnemyModel.shockwave(global_position, 8.0, Art.HOLY, 0.7)
	_toast("You have rung the bell. Heaven answers.", Color("fff4cf"))
	_waiting_boss = true
	var director := get_tree().get_first_node_in_group(&"objective_director")
	if director:
		director.call(&"summon_boss", str(param("boss", "")))


func _on_boss_died(_at: Vector3) -> void:
	if state == State.ACTIVE and _waiting_boss:
		complete()


func _on_finished(_completed: bool) -> void:
	_zone.hide_now()
	if Game.boss_died.is_connected(_on_boss_died):
		Game.boss_died.disconnect(_on_boss_died)
