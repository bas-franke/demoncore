extends Node
## Weather beds (node Sfx/SfxHooks/WeatherAudio; owner: sfx role, docs/team/sfx.md).
## Follows the Atmosphere director's blended weather state and fades two stereo loops on the
## Ambience bus: &"amb_rain" by "weather.rain" and &"amb_gust_wide" by "weather.gust".
## Thunder is played by the lightning rig itself (Sfx.play(&"thunder")). Silent when there is no
## Atmosphere autoload or no active preset.

const POLL := 0.25
## Volume at full intensity, and the level below which a bed is stopped entirely.
const RAIN_DB := -7.0
const GUST_DB := -13.0
const FLOOR_DB := -42.0
## Seconds to reach a new target level (weather blends are slow, this only smooths the polling).
const SMOOTH := 1.5

var _rain: AudioStreamPlayer
var _gust: AudioStreamPlayer
var _rain_lvl := 0.0
var _gust_lvl := 0.0
var _poll_t := 0.0
var _rain_want := 0.0
var _gust_want := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rain = _bed()
	_gust = _bed()


func _process(delta: float) -> void:
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = POLL
		_poll()
	var k := clampf(delta / SMOOTH, 0.0, 1.0)
	_rain_lvl = lerpf(_rain_lvl, _rain_want, k)
	_gust_lvl = lerpf(_gust_lvl, _gust_want, k)
	_drive(_rain, &"amb_rain", _rain_lvl, RAIN_DB)
	_drive(_gust, &"amb_gust_wide", _gust_lvl, GUST_DB)


func _poll() -> void:
	var atmo := get_node_or_null(^"/root/Atmosphere")
	# Only inside a scene that uses the atmosphere (runs, hub); menus have no weather.
	var scene := get_tree().current_scene
	var in_world := is_instance_valid(Game.player) \
			or (scene != null and scene.scene_file_path.begins_with("res://scenes/basecamp/"))
	if atmo == null or not atmo.has_method(&"get_value") or not in_world:
		_rain_want = 0.0
		_gust_want = 0.0
		return
	_rain_want = clampf(_num(atmo.call(&"get_value", "weather.rain")), 0.0, 1.0)
	_gust_want = clampf(_num(atmo.call(&"get_value", "weather.gust")), 0.0, 1.0)


func _drive(p: AudioStreamPlayer, sound: StringName, lvl: float, full_db: float) -> void:
	var db := linear_to_db(maxf(lvl, 0.0001)) + full_db
	if db <= FLOOR_DB:
		if p.playing:
			p.stop()
		return
	if not p.playing:
		var st := Sfx.get_stream(sound)
		if st == null:
			return  # still rendering
		p.stream = st
		p.play(randf() * st.get_length())
	p.volume_db = db


func _bed() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = Sfx.AMB_BUS
	p.volume_db = -80.0
	add_child(p)
	return p


static func _num(v: Variant) -> float:
	if v is float or v is int:
		return float(v)
	return 0.0
