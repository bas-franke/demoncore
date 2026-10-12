extends Objective
## Run event "The Pale Reaper" (data/objectives/events.json): Heaven's angel of death steps out of
## a column of light near the demon and hunts it for `duration` s (ReaperEnemy). Slay it for its
## rewards; outlast it and it departs (failed, no reward).

const REAPER_SCENE := preload("res://scenes/objectives/reaper/reaper.tscn")
const REAPER_MODEL := preload("res://scenes/objectives/reaper/reaper_model.tscn")

var _reaper: ReaperEnemy
var _last := Vector3.ZERO


func _build() -> void:
	status_text = "It hunts you"


func marker_position() -> Vector3:
	if is_instance_valid(_reaper):
		return _reaper.global_position
	return _last


func _tick(_delta: float) -> void:
	if state != State.ACTIVE:
		return
	if not is_instance_valid(_reaper) or _reaper.is_dying:
		global_position = Vector3(_last.x, 0.0, _last.z)
		reset_physics_interpolation()
		complete()
		return
	_last = _reaper.global_position
	var left := float(param("duration", 90.0)) - active_time
	progress = 1.0 - clampf(_reaper.hp / maxf(_reaper.max_hp, 1.0), 0.0, 1.0)
	status_text = "%d%%  %s" % [roundi((1.0 - progress) * 100.0), fmt_time(left)]
	if left <= 0.0:
		_reaper.depart()
		_toast("The Reaper departs. It will remember you.", Color("d8d8e8"))
		fail()


func _on_activated() -> void:
	var p := Game.player
	var at := ObjectiveFX.walkable((p.global_position if p else global_position) + Vector3(randf_range(-1.0, 1.0), 0.0, -1.0).normalized() * 9.0)
	var d := EnemyData.new()
	d.display_name = "The Pale Reaper"
	d.model = REAPER_MODEL
	d.size = 1.6
	d.hover = 0.0
	d.max_hp = float(param("hp", 1800.0)) + float(param("hp_per_minute", 260.0)) * Game.elapsed / 60.0
	d.speed = 2.7
	d.damage = 22.0
	d.xp_value = 60
	d.knockback_scale = 0.0
	_reaper = REAPER_SCENE.instantiate() as ReaperEnemy
	_reaper.setup(d, 1.0)
	_reaper.life = float(param("duration", 90.0)) + 1.0
	Game.spawn(_reaper, at)
	_last = at
	_minimap_follow(_reaper)
	HolyFX.column(at, 1.2, 28.0, 1.2, Color(0.8, 0.85, 1.0), 2.0)
	_toast(str(param("title", "THE PALE REAPER WALKS")), Color("d8d8e8"))
	Sfx.play(&"toll", 0.0, 4.0)
	Sfx.play(&"boss_roar", 0.0, -6.0)
