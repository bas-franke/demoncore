extends Objective
## "Storm the Seventh Gate" (the finale, definition "finale": true; placed by the director only on
## finale runs, see ObjectiveDirector.finale_available()). A colossal gilded gate stands on the
## north side of an arena circle, bound by `seals` seals of light.
##   1. SEALS:  hold the circle (`radius`) to break the seals one by one (`seal_time` s each,
##              drains outside) while Heaven throws `attackers` at you and pillars fall on you.
##   2. WARDEN: the doors swing open and the Archon of the Seventh Gate (roster `boss`) steps
##              through. Slay it.
## Done: the run is won with RunState.end_run(true, &"seventh_gate") (the story ending), after a
## short pause for the boss's death. params: radius, seals, seal_time, decay, wave_interval,
## wave_size, attackers, pillar_damage, boss, boss_hp_scale.

enum Stage { SEALS, WARDEN, OPEN }

const GATE_BACK := 7.5  # the gate stands this far north (-Z) of the arena centre
const END_DELAY := 4.0

var _stage := Stage.SEALS
var _radius := 7.0
var _seals := 7
var _seal_time := 3.5
var _broken := 0
var _seal_progress := 0.0
var _wave_t := 0.0
var _pillar_t := 0.0
var _boss: Enemy
var _zone: BossTelegraph
var _gate: Node3D
var _door_l: Node3D
var _door_r: Node3D
var _seal_nodes: Array[MeshInstance3D] = []
var _light: OmniLight3D


func _build() -> void:
	_radius = float(param("radius", 7.0))
	_seals = maxi(int(param("seals", 7)), 1)
	_seal_time = maxf(float(param("seal_time", 3.5)), 0.5)
	var marble := Art.mat(Art.IVORY, 0.5, 0.0, 0.3, false, 0.0, &"marble")
	var gold := Art.mat(Art.GOLD, 0.28, 1.0, 0.2, false, 0.0, &"gold")
	_gate = Art.pivot(self, Vector3(0.0, 0.0, -GATE_BACK))
	# Steps, two towering pillars, a lintel and a pointed crown.
	Art.part(_gate, Art.box(), marble, Vector3(0.0, 0.15, 0.6), Vector3(9.0, 0.3, 2.4))
	for sx: float in [-1.0, 1.0]:
		Art.part(_gate, Art.box(), marble, Vector3(sx * 3.4, 4.5, 0.0), Vector3(1.4, 9.0, 1.4))
		Art.part(_gate, Art.box(), gold, Vector3(sx * 3.4, 9.1, 0.0), Vector3(1.6, 0.25, 1.6))
		Art.part(_gate, Art.cone(0.5), gold, Vector3(sx * 3.4, 9.9, 0.0), Vector3(1.0, 1.4, 1.0))
	Art.part(_gate, Art.box(), marble, Vector3(0.0, 8.3, 0.0), Vector3(8.2, 1.2, 1.2))
	Art.part(_gate, Art.prism(), gold, Vector3(0.0, 9.6, 0.0), Vector3(5.0, 1.6, 0.6))
	# Doors, hinged at the pillars.
	_door_l = Art.pivot(_gate, Vector3(-2.7, 0.0, 0.1))
	_door_r = Art.pivot(_gate, Vector3(2.7, 0.0, 0.1))
	Art.part(_door_l, Art.box(), gold, Vector3(1.35, 3.85, 0.0), Vector3(2.7, 7.4, 0.3))
	Art.part(_door_r, Art.box(), gold, Vector3(-1.35, 3.85, 0.0), Vector3(2.7, 7.4, 0.3))
	# Seals of light in an arc over the doors.
	for i in _seals:
		var a := lerpf(-1.1, 1.1, float(i) / float(maxi(_seals - 1, 1)))
		var at := Vector3(sin(a) * 2.6, 5.6 + cos(a) * 1.6, 0.35)
		_seal_nodes.append(HolyFX.glow_part(_gate, Art.sphere(), Art.HOLY_WHITE, 2.6, at, Vector3.ONE * 0.45))
	_light = Art.light(_gate, Art.HOLY, 2.0, 14.0, Vector3(0.0, 5.0, 2.0))
	_zone = ObjectiveFX.zone(self)
	status_text = "Approach the Gate"


func marker_position() -> Vector3:
	if _stage == Stage.WARDEN and is_instance_valid(_boss):
		return _boss.global_position
	return global_position


func _tick(delta: float) -> void:
	var inside := _player_distance() <= _radius
	if state == State.DORMANT:
		_zone.show_disc(global_position, _radius, Art.HOLY, 0.0, 0.4 + 0.2 * sin(age * 2.0), 1.0)
		if inside:
			activate()
		return
	match _stage:
		Stage.SEALS:
			_seals_tick(delta, inside)
		Stage.WARDEN:
			if not is_instance_valid(_boss) or _boss.is_dying:
				_stage = Stage.OPEN
				complete()
				return
			progress = 0.6 + 0.4 * (1.0 - clampf(_boss.hp / maxf(_boss.max_hp, 1.0), 0.0, 1.0))
			status_text = "Slay the Warden  %d%%" % roundi(100.0 * _boss.hp / maxf(_boss.max_hp, 1.0))


func _seals_tick(delta: float, inside: bool) -> void:
	if inside:
		_seal_progress += delta / _seal_time
	else:
		_seal_progress = maxf(_seal_progress - delta * float(param("decay", 0.3)) / _seal_time, 0.0)
	_zone.show_disc(global_position, _radius, Art.HOLY.lerp(Art.HELLFIRE, float(_broken) / _seals), _seal_progress,
			0.85 if inside else 0.55, 1.3)
	if _broken < _seal_nodes.size():
		var s := _seal_nodes[_broken]
		s.scale = Vector3.ONE * 0.45 * (1.0 + 0.4 * _seal_progress + 0.1 * sin(age * 20.0) * _seal_progress)
	if _seal_progress >= 1.0:
		_break_seal()
	progress = 0.6 * (float(_broken) + clampf(_seal_progress, 0.0, 1.0)) / float(_seals)
	status_text = "Seal %d / %d%s" % [mini(_broken + 1, _seals), _seals, "" if inside else "  hold the circle!"]
	_wave_t -= delta
	if _wave_t <= 0.0:
		_wave_t = float(param("wave_interval", 3.0))
		_wave()
	_pillar_t -= delta
	if _pillar_t <= 0.0 and Game.player:
		_pillar_t = 3.6
		var p := Game.player.global_position
		var dmg := float(param("pillar_damage", 20.0))
		JudgementPillar.cast(p, 1.5, 1.2, dmg)
		@warning_ignore("integer_division")
		for i in 1 + _broken / 3:
			JudgementPillar.cast(ObjectiveFX.ring_point(p, 3.0), 1.5, 1.35, dmg)


func _wave() -> void:
	var ids: Array = param("attackers", ["choir_wisp"])
	if ids.is_empty():
		return
	@warning_ignore("integer_division")
	var n := int(param("wave_size", 5)) + _broken / 2
	@warning_ignore("integer_division")
	var pool := ids.slice(0, mini(ids.size(), 2 + _broken / 2))
	var base := randf() * TAU
	for i in n:
		var a := base + randf_range(-1.0, 1.0)
		_spawn_enemy(str(pool.pick_random()), global_position + Vector3(cos(a), 0.0, sin(a)) * (_radius + randf_range(3.0, 5.0)))


func _break_seal() -> void:
	_seal_progress = 0.0
	if _broken < _seal_nodes.size():
		var s := _seal_nodes[_broken]
		HolyFX.flash(s.global_position, 2.0, 0.5, Art.HOLY_WHITE, 3.0)
		HolyFX.feathers(s.global_position, 6, 0.8, 1.5)
		s.hide()
	_broken += 1
	Sfx.play(&"smite", 0.05, 0.0)
	Sfx.play(&"toll", 0.05, -4.0)
	get_tree().call_group(&"camera_rig", &"shake", 0.25)
	if _broken >= _seals:
		_open_gate()
	else:
		_toast("%d seals remain" % (_seals - _broken), Color("fff4cf"))


## The last seal breaks: the doors swing open and the warden steps through.
func _open_gate() -> void:
	_stage = Stage.WARDEN
	_zone.hide_now()
	get_tree().call_group(&"boss_hazards", &"dissipate")
	var tw := create_tween().set_parallel()
	tw.tween_property(_door_l, "rotation:y", 1.6, 2.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_door_r, "rotation:y", -1.6, 2.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_light.light_energy = 6.0
	HolyFX.column(_gate.global_position + Vector3(0.0, 0.0, 1.0), 2.6, 30.0, 2.5, Art.HOLY_WHITE, 2.0)
	Sfx.play(&"boss_charge", 0.0, 2.0)
	_toast("THE SEVENTH GATE OPENS", Color("fff4cf"))
	var director := get_tree().get_first_node_in_group(&"objective_director")
	if director == null or not director.has_method(&"make_boss"):
		complete()
		return
	_boss = director.call(&"make_boss", str(param("boss", "gate_archon")),
			float(param("boss_hp_scale", 1.0)) + Game.elapsed / 900.0)
	if _boss == null:
		complete()
		return
	Game.spawn(_boss, _gate.global_position + Vector3(0.0, 0.0, 2.5))


func _on_activated() -> void:
	_toast("Break the seven seals", Art.HELLFIRE)
	Sfx.play(&"boss_intro", 0.0, -4.0)
	_wave_t = 1.0
	_pillar_t = 3.0


func _on_finished(completed: bool) -> void:
	_zone.hide_now()
	if not completed:
		return
	_toast("THE SEVENTH GATE HAS FALLEN", UIPalette.HELLFIRE)
	ObjectiveFX.corruption_burst(_gate.global_position + Vector3(0.0, 0.0, 2.0), 2.0)
	var dlg := get_tree().root.get_node_or_null(^"Dialogue")
	if dlg and dlg.has_method(&"bark"):
		dlg.call(&"bark", "seventh_gate_falls", true)
	var director := get_tree().get_first_node_in_group(&"objective_director")
	if director and director.has_method(&"win_run"):
		director.call(&"win_run", &"seventh_gate", END_DELAY)
