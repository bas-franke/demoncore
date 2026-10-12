extends Objective
## "The Cursed Coffer": a black-iron chest bound in gold chains, humming with sanctified wards.
## Stand at it for `open_time` s to break the lock: the wards spring an ambush. `waves` waves of
## angels (`wave_size`, from `ambushers`; the last wave led by a crowned `captain`) drop in around
## it. Slay every ambusher and the coffer bursts open with its rewards. No time limit; leaving
## does not fail it, but the ambushers follow.
## params: open_time, waves, wave_size, wave_gap, ambushers (enemy ids), captain (enemy id),
##         captain_hp.

var _open := 0.0
var _wave := 0
var _wave_t := 0.0
var _ambushers: Array[Enemy] = []
var _lid: Node3D
var _seam_mat: StandardMaterial3D
var _zone: BossTelegraph


func _build() -> void:
	var iron := Art.mat(Art.OBSIDIAN.lightened(0.08), 0.5, 0.8, 0.4, false, 0.0, &"metal")
	var gold := Art.mat(Art.GOLD, 0.3, 1.0, 0.2, false, 0.0, &"gold")
	Art.part(self, Art.box(), iron, Vector3(0.0, 0.4, 0.0), Vector3(1.4, 0.8, 0.9))
	for sx: float in [-0.45, 0.45]:
		Art.part(self, Art.box(), gold, Vector3(sx, 0.42, 0.0), Vector3(0.1, 0.84, 0.94))
	_lid = Art.pivot(self, Vector3(0.0, 0.8, 0.45))
	Art.part(_lid, Art.box(), iron, Vector3(0.0, 0.12, -0.45), Vector3(1.44, 0.24, 0.94))
	var seam := HolyFX.glow_part(self, Art.box(), Art.HOLY, 1.6, Vector3(0.0, 0.8, 0.0), Vector3(1.42, 0.03, 0.92))
	_seam_mat = seam.material_override as StandardMaterial3D
	# Golden chains crossing the lid.
	for sz: float in [-0.25, 0.25]:
		Art.part(self, Art.box(), gold, Vector3(0.0, 0.95, sz), Vector3(1.6, 0.05, 0.06))
	_zone = ObjectiveFX.zone(self)
	status_text = "Break the lock"


func _tick(delta: float) -> void:
	_seam_mat.albedo_color = HolyFX.scaled(Art.HOLY.lerp(Art.SOUL, _open), 1.4 + 0.5 * sin(age * 4.0))
	if state == State.DORMANT:
		var near := _player_distance() <= 2.2
		_open = clampf(_open + (delta if near else -delta) / maxf(float(param("open_time", 1.6)), 0.1), 0.0, 1.0)
		_zone.show_disc(global_position, 2.2, Art.HOLY, _open, 0.5 + 0.4 * _open, 1.1)
		status_text = "Break the lock" if _open <= 0.0 else "%d%%" % roundi(_open * 100.0)
		if _open >= 1.0:
			activate()
		return
	_ambushers.assign(_ambushers.filter(func(e: Variant) -> bool: return is_instance_valid(e) and not (e as Enemy).is_dying))
	var waves := maxi(int(param("waves", 3)), 1)
	progress = (float(_wave - 1) + (1.0 if _ambushers.is_empty() else 0.4)) / float(waves) if _wave > 0 else 0.0
	status_text = "Wave %d / %d  %d left" % [_wave, waves, _ambushers.size()]
	if _ambushers.is_empty():
		if _wave >= waves:
			complete()
			return
		_wave_t -= delta
		if _wave_t <= 0.0:
			_spawn_wave(_wave >= waves - 1)


func _spawn_wave(last: bool) -> void:
	_wave += 1
	_wave_t = float(param("wave_gap", 1.5))
	var ids: Array = param("ambushers", ["seraph_sentinel"])
	var n := int(param("wave_size", 6)) + _wave
	for i in n:
		if ids.is_empty():
			break
		var e := _spawn_enemy(str(ids.pick_random()), ObjectiveFX.ring_point(global_position, randf_range(5.0, 8.0)))
		if e:
			_ambushers.append(e)
	if last:
		var cap := _spawn_enemy(str(param("captain", "archon")), ObjectiveFX.ring_point(global_position, 5.0),
				float(param("captain_hp", 6.0)))
		if cap:
			_ambushers.append(cap)
			cap.add_to_group(&"champions")
			var crown := Art.pivot(cap, Vector3(0.0, cap.data.size * 1.55 + cap.data.hover, 0.0))
			HolyFX.glow_part(crown, Art.torus(0.82, 1.0), Art.GOLD, 2.4, Vector3.ZERO, Vector3.ONE * 0.4 * cap.data.size)
			_toast("The coffer's warden descends", Color("f2c66b"))
	Sfx.play(&"choir", 0.05, -2.0)
	EnemyModel.shockwave(global_position, 7.0, Art.HOLY, 0.5)


func _on_activated() -> void:
	_zone.hide_now()
	_toast("A trap! The coffer is warded.", Color("fff4cf"))
	Sfx.play(&"toll", 0.0, 0.0)
	_wave_t = 0.4


func _on_finished(completed: bool) -> void:
	_zone.hide_now()
	if completed:
		var tw := create_tween()
		tw.tween_property(_lid, "rotation:x", -1.9, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		ObjectiveFX.corruption_burst(global_position, 0.8)
		HolyFX.motes(global_position + Vector3(0.0, 1.0, 0.0), 30, Art.GOLD, 1.0, 3.0, 1.5)
		Sfx.play(&"gold", 0.0, 2.0)
