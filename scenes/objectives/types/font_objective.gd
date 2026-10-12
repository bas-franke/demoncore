extends Objective
## "Defile the Baptismal Font": a marble font brimming with holy water. Stand in its circle for
## `channel_time` s to foul it (drains outside at `decay` x). The water fights back: every
## `wave_interval` s a ring of purity rolls out from the font (a BellRing: step outside it or dash
## through it). Done: the water turns to blood and the land around becomes hell terrain for the rest
## of the run (ProfaneGround: the demon regenerates there, angels burn).
## params: radius, channel_time, decay, wave_interval, wave_damage, ground_radius, ground_regen,
##         ground_burn, ground_duration (-1 = the rest of the run).

var _radius := 3.4
var _channel := 8.0
var _wave_t := 0.0
var _zone: BossTelegraph
var _water: MeshInstance3D
var _water_mat: StandardMaterial3D
var _light: OmniLight3D
var _end_t := 0.0


func _build() -> void:
	_radius = float(param("radius", 3.4))
	_channel = maxf(float(param("channel_time", 8.0)), 0.5)
	var marble := Art.mat(Art.IVORY, 0.45, 0.0, 0.3, false, 0.0, &"marble")
	var gold := Art.mat(Art.GOLD, 0.3, 1.0, 0.2, false, 0.0, &"gold")
	Art.part(self, Art.cylinder(), marble, Vector3(0.0, 0.1, 0.0), Vector3(2.6, 0.2, 2.6))
	Art.part(self, Art.cylinder(0.25, 0.35), marble, Vector3(0.0, 0.55, 0.0), Vector3(1.0, 0.7, 1.0))
	Art.part(self, Art.cylinder(0.75, 0.5), marble, Vector3(0.0, 1.05, 0.0), Vector3(1.0, 0.35, 1.0))
	Art.part(self, Art.torus(0.88, 1.0), gold, Vector3(0.0, 1.22, 0.0), Vector3.ONE * 0.76)
	_water = HolyFX.glow_part(self, Art.cylinder(), Color(0.7, 0.85, 1.0), 1.4, Vector3(0.0, 1.18, 0.0), Vector3(1.36, 0.04, 1.36))
	_water_mat = _water.material_override as StandardMaterial3D
	_light = Art.light(self, Color(0.75, 0.88, 1.0), 1.6, 7.0, Vector3(0.0, 1.8, 0.0))
	_zone = ObjectiveFX.zone(self)
	status_text = "Foul the water"


func _tick(delta: float) -> void:
	var inside := _player_distance() <= _radius
	var water := Color(0.7, 0.85, 1.0).lerp(Art.BLOOD.lightened(0.2), progress)
	_water_mat.albedo_color = HolyFX.scaled(water, 1.4 + 0.3 * sin(age * 3.0))
	_light.light_color = water
	_zone.show_disc(global_position, _radius, Color(0.75, 0.88, 1.0).lerp(Art.CRIMSON, progress), progress,
			0.85 if inside else 0.5, 1.2)
	if state == State.DORMANT:
		if inside:
			activate()
		return
	if inside:
		progress = minf(progress + delta / _channel, 1.0)
	else:
		progress = maxf(progress - delta * float(param("decay", 0.4)) / _channel, 0.0)
	status_text = "%d%%%s" % [roundi(progress * 100.0), "" if inside else "  return!"]
	_wave_t -= delta
	if _wave_t <= 0.0:
		_wave_t = float(param("wave_interval", 3.0))
		BellRing.cast(global_position, _radius + 6.0, 5.5, 0.9, float(param("wave_damage", 12.0)), 0.6, false)
	if progress >= 1.0:
		complete()


func _on_activated() -> void:
	_toast("The water burns to the touch", Color("9fd4ff"))
	_wave_t = 1.5


func _on_finished(completed: bool) -> void:
	if not completed:
		_zone.hide_now()
		return
	_end_t = 0.0
	ObjectiveFX.corruption_burst(global_position, 1.4)
	HolyFX.column(global_position, 0.6, 12.0, 1.2, Art.CRIMSON, 2.0)
	ProfaneGround.create(global_position, float(param("ground_radius", 9.0)), float(param("ground_duration", -1.0)),
			float(param("ground_regen", 2.5)), float(param("ground_burn", 8.0)))
	_toast("The land here is yours now", Art.CRIMSON)
	Sfx.play(&"brimstone", 0.0, 2.0)


func _tick_finished(delta: float) -> void:
	_end_t += delta
	_zone.hide_now()
	if state == State.COMPLETED:
		_water_mat.albedo_color = HolyFX.scaled(Art.BLOOD.lightened(0.15), 1.8 + 0.4 * sin(age * 5.0))
		_light.light_color = Art.CRIMSON
