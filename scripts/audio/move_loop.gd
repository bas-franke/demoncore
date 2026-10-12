extends Node
## A looping sound that follows a moving body and swells with its speed (owner: sfx role).
## SfxHooks adds one under the run's Player for demons listed in Sfx.DEMON_LOOPS (Nhazgul's
## fly buzz). Faint while standing, full at move speed; pitch rises a little with speed.

const FULL_DB := -9.0
const IDLE_DB := -26.0
const FLOOR_DB := -60.0
## Seconds to settle on a new level.
const SMOOTH := 0.25

var sound: StringName
var _body: CharacterBody3D
var _player: AudioStreamPlayer3D
var _lvl := 0.0


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	_player = Sfx.play_loop(sound, get_parent(), FLOOR_DB, Sfx.SFX_BUS, 6.0) as AudioStreamPlayer3D


func _process(delta: float) -> void:
	if _body == null or _player == null:
		return
	var dead: Variant = _body.get(&"is_dead")
	var max_speed := maxf(float(_body.get(&"move_speed")) if _body.get(&"move_speed") != null else 5.0, 0.1)
	var v := Vector2(_body.velocity.x, _body.velocity.z).length()
	var want := 0.0 if dead == true else clampf(v / max_speed, 0.0, 1.3)
	_lvl = lerpf(_lvl, want, clampf(delta / SMOOTH, 0.0, 1.0))
	# Idle hum when still, swelling to FULL_DB at full speed.
	_player.volume_db = FLOOR_DB if dead == true else lerpf(IDLE_DB, FULL_DB, minf(_lvl, 1.0))
	_player.pitch_scale = 0.95 + 0.12 * _lvl
