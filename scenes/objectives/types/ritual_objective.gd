extends Objective
## "Blood Sacrifice": a ritual circle of the demon's own making. Step into it to begin; then slay
## `kills` angels inside the circle (radius + a little) within `time_limit` seconds. The circle
## draws angels in: `lure_count` of the `lures` enemies arrive from its rim every `lure_interval`
## s. Done: a geyser of blood-fire erupts and scours the circle.
## params: radius, kills, time_limit, lure_interval, lure_count, lures (enemy ids), finale_damage.

var _radius := 7.0
var _need := 35
var _count := 0
var _time_limit := 60.0
var _lure_t := 0.0
var _zone: BossTelegraph
var _candles: Array[Node3D] = []
var _end_t := 0.0


func _build() -> void:
	_radius = float(param("radius", 7.0))
	_need = maxi(int(param("kills", 35)), 1)
	_time_limit = float(param("time_limit", 60.0))
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# Five black candles on the circle's points, a bone pile at its heart.
	for i in 5:
		var a := TAU * float(i) / 5.0 - PI * 0.5
		var c := Props.candles(rng, 3)
		c.position = Vector3(cos(a), 0.0, sin(a)) * (_radius - 0.6)
		add_child(c)
		_candles.append(c)
	var bones := Props.bone_pile(rng)
	add_child(bones)
	_zone = ObjectiveFX.zone(self)
	status_text = "Enter the circle"
	Game.enemy_died.connect(_on_enemy_died)


func _tick(delta: float) -> void:
	var inside := _player_distance() <= _radius
	if state == State.DORMANT:
		_zone.show_disc(global_position, _radius, Art.CRIMSON, 0.0, 0.45 + 0.15 * sin(age * 2.0), 1.4)
		if inside:
			activate()
		return
	var left := _time_limit - active_time
	progress = float(_count) / float(_need)
	status_text = "%d / %d  %s" % [_count, _need, fmt_time(left)]
	_zone.show_disc(global_position, _radius, Art.HELLFIRE.lerp(Art.CRIMSON, 0.4), progress, 0.9 if inside else 0.6, 1.5)
	_lure_t -= delta
	if _lure_t <= 0.0:
		_lure_t = float(param("lure_interval", 2.2))
		var ids: Array = param("lures", ["choir_wisp"])
		for i in int(param("lure_count", 3)):
			if not ids.is_empty():
				_spawn_enemy(str(ids.pick_random()), ObjectiveFX.ring_point(global_position, _radius + randf_range(3.0, 6.0)))
	if _count >= _need:
		complete()
	elif left <= 0.0:
		fail()


func _on_enemy_died(at: Vector3, _data: Resource) -> void:
	if state != State.ACTIVE:
		return
	var d := at - global_position
	d.y = 0.0
	if d.length() <= _radius + 1.0:
		_count += 1
		HolyFX.motes(at + Vector3(0.0, 0.4, 0.0), 3, Art.SOUL, 0.3, 1.2, 0.8)


func _on_activated() -> void:
	_toast("Spill their light within the circle", Art.CRIMSON)
	Sfx.play(&"boss_charge", 0.0, -4.0)
	ObjectiveFX.corruption_burst(global_position, 0.6)
	_lure_t = 0.8


func _on_finished(completed: bool) -> void:
	if Game.enemy_died.is_connected(_on_enemy_died):
		Game.enemy_died.disconnect(_on_enemy_died)
	if not completed:
		_zone.hide_now()
		return
	_end_t = 0.0
	ObjectiveFX.damage_enemies(global_position, _radius + 1.5, float(param("finale_damage", 300.0)))
	ObjectiveFX.corruption_burst(global_position, 1.5)
	for c in _candles:
		HolyFX.column(c.global_position, 0.4, 9.0, 0.9, Art.HELLFIRE, 1.6)
	Sfx.play(&"brimstone", 0.0, 3.0)


func _tick_finished(delta: float) -> void:
	if state != State.COMPLETED:
		_zone.hide_now()
		return
	_end_t += delta
	_zone.show_disc(global_position, _radius, Art.CRIMSON, 1.0, clampf(1.0 - _end_t / LINGER, 0.0, 1.0), 1.8)
