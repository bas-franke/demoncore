extends Objective
## "Desecrate the Shrine": a weathered angel statue on a gilded altar with a holy flame. Stand in
## its circle of light for `channel_time` seconds (progress drains at `decay` x speed outside).
## While the demon channels, guard angels answer in waves from the circle's edge. Done: the flame
## turns to hellfire, the gold blackens, the statue cracks and sinks.
## params: radius, channel_time, decay, guard_interval, guards_per_wave, guards (enemy ids).

var _radius := 3.4
var _channel := 9.0
var _decay := 0.4
var _guard_t := 0.0
var _zone: BossTelegraph
var _statue: Node3D
var _flame: MeshInstance3D
var _flame_mat: StandardMaterial3D
var _flame_light: OmniLight3D
var _altar_gold: MeshInstance3D
var _inside := false
var _sink_t := 0.0
var _ritual: AudioStreamPlayer3D  # channel drone (Sfx &"amb_ritual"), loud while the demon is inside


func _build() -> void:
	_radius = float(param("radius", 3.4))
	_channel = maxf(float(param("channel_time", 9.0)), 0.5)
	_decay = float(param("decay", 0.4))
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# Stepped plinth and a gilded altar.
	var stone := Art.mat(Art.STONE, 0.9, 0.0, 0.5, false, 0.0, &"stone")
	Art.part(self, Art.cylinder(), stone, Vector3(0.0, 0.1, 0.0), Vector3(2.4, 0.2, 2.4))
	Art.part(self, Art.cylinder(), stone, Vector3(0.0, 0.28, 0.0), Vector3(1.8, 0.18, 1.8))
	Art.part(self, Art.box(), Art.mat(Art.IVORY, 0.6, 0.0, 0.3, false, 0.0, &"marble"),
			Vector3(0.0, 0.75, 0.6), Vector3(0.9, 0.8, 0.6))
	_altar_gold = Art.part(self, Art.box(), Art.mat(Art.GOLD, 0.3, 1.0, 0.2, false, 0.0, &"gold"),
			Vector3(0.0, 1.18, 0.6), Vector3(1.0, 0.08, 0.7))
	# A holy flame in a bowl on the altar.
	Art.part(self, Art.cylinder(0.32, 0.18), Art.mat(Art.GOLD, 0.35, 1.0, 0.2, false), Vector3(0.0, 1.32, 0.6),
			Vector3(0.6, 0.2, 0.6))
	_flame = HolyFX.glow_part(self, Art.cone(0.5), Art.HOLY, 2.2, Vector3(0.0, 1.75, 0.6), Vector3(0.45, 0.8, 0.45))
	_flame_mat = _flame.material_override as StandardMaterial3D
	_flame_light = Art.light(self, Art.HOLY, 2.2, 7.0, Vector3(0.0, 2.2, 0.6))
	# The statue the shrine is raised to, and candles at its feet.
	_statue = Props.statue_angel(rng)
	_statue.position = Vector3(0.0, 0.38, -0.5)
	_statue.rotation.y = 0.0
	add_child(_statue)
	for i in 3:
		var c := Props.candles(rng, 4)
		var a := PI * 0.25 + PI * 0.5 * float(i) + PI * 0.5
		c.position = Vector3(cos(a) * 1.6, 0.0, sin(a) * 1.6 + 0.3)
		add_child(c)
	_zone = ObjectiveFX.zone(self)
	status_text = "Stand in the light"


func _tick(delta: float) -> void:
	_inside = _player_distance() <= _radius
	if state == State.DORMANT and _inside:
		activate()
	# The flame flickers; it gutters toward red as the desecration progresses.
	var flick := 0.85 + 0.15 * sin(age * 13.0) * sin(age * 7.3)
	_flame.scale = Vector3(0.45, 0.8 * flick, 0.45) * (1.0 - progress * 0.3)
	_flame_mat.albedo_color = HolyFX.scaled(Art.HOLY.lerp(Art.HELLFIRE, progress), 2.2 * flick)
	_flame_light.light_color = Art.HOLY.lerp(Art.HELLFIRE, progress)
	var zone_col := Art.HOLY.lerp(Art.HELLFIRE, progress)
	var alpha := 0.55 if state == State.DORMANT else (0.9 if _inside else 0.6)
	_zone.show_disc(global_position, _radius, zone_col, progress, alpha, 1.3 if _inside else 0.9)
	if _ritual:
		var want := lerpf(-10.0, -2.0, progress) if (_inside and state == State.ACTIVE) else -40.0
		_ritual.volume_db = move_toward(_ritual.volume_db, want, delta * 30.0)
	if state != State.ACTIVE:
		return
	if _inside:
		progress = minf(progress + delta / _channel, 1.0)
		status_text = "%d%%" % roundi(progress * 100.0)
		if randf() < delta * 14.0:
			HolyFX.motes(ObjectiveFX.ring_point(global_position, _radius * randf()) + Vector3(0.0, 0.1, 0.0),
					1, Art.EMBER, 0.2, 1.4, 0.8)
	else:
		progress = maxf(progress - delta * _decay / _channel, 0.0)
		status_text = "%d%%  return!" % roundi(progress * 100.0)
	_guard_t -= delta
	if _guard_t <= 0.0:
		_guard_t = float(param("guard_interval", 3.2))
		_spawn_guards()
	if progress >= 1.0:
		complete()


func _on_activated() -> void:
	_toast("The shrine resists your presence")
	_guard_t = 1.2
	_ritual = Sfx.play_loop(&"amb_ritual", self, -40.0, Sfx.SFX_BUS, 6.0) as AudioStreamPlayer3D


func _spawn_guards() -> void:
	var ids: Array = param("guards", ["choir_wisp"])
	if ids.is_empty():
		return
	for i in int(param("guards_per_wave", 3)):
		_spawn_enemy(str(ids.pick_random()), ObjectiveFX.ring_point(global_position, _radius + randf_range(3.0, 5.0)))


func _on_finished(completed: bool) -> void:
	if _ritual:
		_ritual.queue_free()
		_ritual = null
	if not completed:
		_zone.hide_now()
		return
	ObjectiveFX.corruption_burst(global_position + Vector3(0.0, 0.5, 0.0), 1.2)
	ObjectiveFX.damage_enemies(global_position, _radius + 2.0, 60.0)
	Sfx.play(&"brimstone", 0.0, 2.0)
	Sfx.play(&"desecrate", 0.0, 0.0)
	_altar_gold.material_override = Art.mat(Art.OBSIDIAN, 0.6, 0.6, 0.6, false)
	_flame_light.light_color = Art.HELLFIRE
	_sink_t = 0.0


func _tick_finished(delta: float) -> void:
	if state != State.COMPLETED:
		return
	_sink_t += delta
	# The flame roars up in hellfire, then the statue cracks and sinks into the ground.
	var flick := 0.8 + 0.2 * sin(age * 17.0)
	_flame.scale = Vector3(0.7, 1.6 * flick, 0.7)
	_flame_mat.albedo_color = HolyFX.scaled(Art.HELLFIRE, 2.8 * flick)
	_statue.position.y = 0.38 - smoothstep(0.4, 2.8, _sink_t) * 2.4
	_statue.rotation.z = smoothstep(0.4, 2.8, _sink_t) * 0.35
	_zone.show_disc(global_position, _radius, Art.HELLFIRE, 1.0, clampf(1.0 - _sink_t / LINGER, 0.0, 1.0), 1.4)
