extends Objective
## "Survive the Holy Siege": a dormant hellgate (a ring of obsidian spikes around a brazier).
## Step onto it (`trigger_radius`) to open it; then hold its circle (`radius`) for `duration`
## seconds while Heaven lays siege: waves of `attackers` descend on the circle's rim every
## `wave_interval` s, each `wave_growth` angels bigger than the last. Leaving the circle for more
## than `grace` seconds closes the gate (failed). Held to the end, the gate erupts: hellfire
## scours the circle (`finale_damage` to every angel inside).
## params: trigger_radius, radius, duration, grace, wave_interval, wave_size, wave_growth,
##         attackers (enemy ids), finale_damage.

var _radius := 9.0
var _duration := 40.0
var _grace := 5.0
var _outside_t := 0.0
var _wave_t := 0.0
var _wave := 0
var _zone: BossTelegraph
var _gate_zone: BossTelegraph
var _spikes: Array[Node3D] = []
var _light: OmniLight3D
var _end_t := 0.0


func _build() -> void:
	_radius = float(param("radius", 9.0))
	_duration = maxf(float(param("duration", 40.0)), 5.0)
	_grace = float(param("grace", 5.0))
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var brazier := Props.brazier(rng)
	add_child(brazier)
	var obsidian := Art.mat(Art.OBSIDIAN, 0.35, 0.3, 0.2, false, 0.0, &"stone")
	var n := 7
	for i in n:
		var a := TAU * float(i) / float(n)
		var spike := Art.pivot(self, Vector3(cos(a), 0.0, sin(a)) * 2.6, Vector3(randf_range(-0.2, 0.2), 0.0, randf_range(-0.2, 0.2)))
		Art.part(spike, Art.cone(0.5), obsidian, Vector3(0.0, 0.7, 0.0), Vector3(0.5, 1.4, 0.5))
		Art.part(spike, Art.cone(0.5), Art.emissive(Art.OBSIDIAN, Art.HELLFIRE, 1.6, 0.5, false),
				Vector3(0.0, 0.3, 0.0), Vector3(0.56, 0.12, 0.56))
		_spikes.append(spike)
	_light = Art.light(self, Art.HELLFIRE, 1.0, 9.0, Vector3(0.0, 1.0, 0.0))
	_zone = ObjectiveFX.zone(self)
	_gate_zone = ObjectiveFX.zone(self)
	status_text = "Step onto the gate"


func _tick(delta: float) -> void:
	var dist := _player_distance()
	if state == State.DORMANT:
		var k := 0.5 + 0.2 * sin(age * 2.5)
		_gate_zone.show_disc(global_position, float(param("trigger_radius", 2.4)) + 0.6, Art.HELLFIRE, 0.0, k, 1.1)
		if dist <= float(param("trigger_radius", 2.4)):
			activate()
		return
	var inside := dist <= _radius
	progress = clampf(active_time / _duration, 0.0, 1.0)
	_light.light_energy = 1.5 + 1.0 * sin(age * 6.0)
	_zone.show_disc(global_position, _radius, Art.HELLFIRE, progress, 0.9 if inside else 0.55 + 0.3 * sin(age * 12.0), 1.2)
	_gate_zone.show_disc(global_position, 3.0, Art.HELLFIRE, 1.0, 0.8, 1.6)
	if inside:
		_outside_t = maxf(_outside_t - delta * 2.0, 0.0)
		status_text = fmt_time(_duration - active_time)
	else:
		_outside_t += delta
		status_text = "Return! %s" % fmt_time(_grace - _outside_t)
		if _outside_t >= _grace:
			fail()
			return
	_wave_t -= delta
	if _wave_t <= 0.0 and active_time < _duration - 3.0:
		_wave_t = float(param("wave_interval", 3.5))
		_spawn_wave()
	if active_time >= _duration:
		complete()


func _on_activated() -> void:
	_toast("The gate opens. Heaven answers.", Art.HELLFIRE)
	ObjectiveFX.corruption_burst(global_position, 0.8)
	Sfx.play(&"boss_charge", 0.0, -2.0)
	_wave_t = 1.5
	for s in _spikes:
		var tw := s.create_tween()
		tw.tween_property(s, "scale", Vector3(1.0, 1.7, 1.0), 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _spawn_wave() -> void:
	var ids: Array = param("attackers", ["choir_wisp"])
	if ids.is_empty():
		return
	_wave += 1
	var count := int(float(param("wave_size", 5)) + float(param("wave_growth", 0.6)) * float(_wave - 1))
	# Each wave comes from one side, so the demon can read where the pressure is.
	var base := randf() * TAU
	@warning_ignore("integer_division")
	var pool := ids.slice(0, mini(ids.size(), 2 + _wave / 2))  # tougher angels join later waves
	for i in count:
		var a := base + randf_range(-0.9, 0.9)
		var at := global_position + Vector3(cos(a), 0.0, sin(a)) * (_radius + randf_range(2.0, 4.5))
		_spawn_enemy(str(pool.pick_random()), at)
	Sfx.play(&"choir", 0.1, -5.0)


func _on_finished(completed: bool) -> void:
	_gate_zone.hide_now()
	if not completed:
		_zone.hide_now()
		_light.light_energy = 0.0
		for s in _spikes:
			s.create_tween().tween_property(s, "scale", Vector3(1.0, 0.05, 1.0), 0.8)
		return
	_end_t = 0.0
	# Hellfire scours the circle.
	var dmg := float(param("finale_damage", 400.0))
	ObjectiveFX.damage_enemies(global_position, _radius + 1.5, dmg)
	ObjectiveFX.corruption_burst(global_position, 1.6)
	for i in 10:
		var p := ObjectiveFX.ring_point(global_position, randf_range(1.0, _radius))
		HolyFX.column(p, 0.5, 10.0, 0.7 + randf() * 0.4, Art.HELLFIRE, 1.6)
	Sfx.play(&"brimstone", 0.0, 3.0)
	Sfx.play(&"impact", 0.0, 2.0)


func _tick_finished(delta: float) -> void:
	if state != State.COMPLETED:
		_zone.hide_now()
		return
	_end_t += delta
	_zone.show_disc(global_position, _radius, Art.HELLFIRE, 1.0, clampf(1.0 - _end_t / LINGER, 0.0, 1.0), 1.8)
