extends Objective
## Run event "Crusade" (data/objectives/events.json): a crusading army marches on the demon from
## one side. Waves of `soldiers` arrive every `wave_interval` s (`wave_size` + `wave_growth` per
## wave) for `duration` s; on the second wave its Captain (a crowned `captain`, x`captain_hp` HP)
## takes the field. Slay the Captain to break the crusade (rewards); outlast it and it withdraws
## (no reward).

var _front := Vector3.FORWARD
var _wave := 0
var _wave_t := 0.0
var _captain: Enemy
var _captain_spawned := false
var _banner_mat: StandardMaterial3D


func _build() -> void:
	var a := randf() * TAU
	_front = Vector3(cos(a), 0.0, sin(a))
	status_text = "The crusade approaches"


func marker_position() -> Vector3:
	if is_instance_valid(_captain):
		return _captain.global_position
	var p := Game.player
	return (p.global_position if p else global_position) + _front * 14.0


func _tick(delta: float) -> void:
	if state != State.ACTIVE:
		return
	var duration := float(param("duration", 50.0))
	var left := duration - active_time
	if _captain_spawned:
		if not is_instance_valid(_captain) or _captain.is_dying:
			var p := Game.player
			if p:
				global_position = Vector3(p.global_position.x, 0.0, p.global_position.z)
				reset_physics_interpolation()
			complete()
			return
		progress = 1.0 - clampf(_captain.hp / maxf(_captain.max_hp, 1.0), 0.0, 1.0)
		status_text = "Slay the Captain  %s" % fmt_time(left)
	else:
		status_text = "Hold  %s" % fmt_time(left)
	_wave_t -= delta
	if _wave_t <= 0.0 and left > 6.0:
		_wave_t = float(param("wave_interval", 3.5))
		_spawn_wave()
	if left <= 0.0:
		_toast("The crusade withdraws", Color("f2c66b"))
		fail()


func _spawn_wave() -> void:
	var p := Game.player
	if p == null:
		return
	_wave += 1
	# The front swings slowly so the army wraps around the demon.
	_front = _front.rotated(Vector3.UP, randf_range(-0.35, 0.35))
	var ids: Array = param("soldiers", ["seraph_sentinel"])
	var n := int(float(param("wave_size", 7)) + float(param("wave_growth", 0.5)) * float(_wave - 1))
	@warning_ignore("integer_division")
	var pool := ids.slice(0, mini(ids.size(), 2 + _wave / 2))
	var center := p.global_position + _front * 15.0
	for i in n:
		if pool.is_empty():
			break
		var side := Vector3(-_front.z, 0.0, _front.x) * randf_range(-7.0, 7.0)
		_spawn_enemy(str(pool.pick_random()), center + side + _front * randf_range(-1.5, 2.5))
	if _wave == 2 and not _captain_spawned:
		_spawn_captain(center)
	Sfx.play(&"choir", 0.1, -3.0)


func _spawn_captain(at: Vector3) -> void:
	_captain_spawned = true
	_captain = _spawn_enemy(str(param("captain", "archon")), at, float(param("captain_hp", 18.0)))
	if _captain == null:
		return
	_captain.add_to_group(&"champions")
	_minimap_follow(_captain)
	var s := _captain.data.size
	var crown := Art.pivot(_captain, Vector3(0.0, s * 1.6 + _captain.data.hover, 0.0))
	HolyFX.glow_part(crown, Art.torus(0.82, 1.0), Art.GOLD, 2.6, Vector3.ZERO, Vector3.ONE * 0.45 * s)
	# A tall banner pole rising from its back.
	var pole := Art.pivot(_captain, Vector3(0.0, 0.0, 0.35 * s))
	Art.part(pole, Art.cylinder(), Art.mat(Art.GOLD, 0.3, 1.0, 0.2), Vector3(0.0, s * 1.7, 0.0), Vector3(0.05, s * 1.8, 0.05))
	var cloth := HolyFX.glow_part(pole, Art.box(), Art.HOLY_WHITE, 0.9, Vector3(0.0, s * 2.3, 0.25), Vector3(0.04, 0.8, 0.5))
	_banner_mat = cloth.material_override as StandardMaterial3D
	_toast("THE CAPTAIN OF THE CRUSADE TAKES THE FIELD", Color("f2c66b"))


func _on_activated() -> void:
	_toast(str(param("title", "A CRUSADE MARCHES ON YOU")), Color("f2c66b"))
	Sfx.play(&"toll", 0.0, 3.0)
	Sfx.play(&"boss_intro", 0.0, -8.0)
	_wave_t = 2.0
