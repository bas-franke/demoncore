extends Node
## Corruption spread (autoload `Corruption`, purely visual): the demon blights the ground it walks
## on. Paints a trail of "last blighted at" timestamps into a small world-space float texture and
## publishes it, with the player's position, as global shader uniforms (project.godot
## [shader_globals] corruption_*). Shaders read it via res://shaders/style/corruption.gdshaderinc.
##
##   Corruption.stamp(pos, 3.0)          # blight a spot (hellfire explosions, demon deaths, ...)
##   Corruption.ambient = 1.0            # whole map blighted (Basecamp Hell); 0 on run maps
##   Corruption.amount_at(pos) -> float  # 0..1 trail strength on the CPU (gameplay hooks)
##   Corruption.clear()                  # wipe the trail (done automatically on a new player)
##   Corruption.quality = 1              # 0 off, 1 low (crust only), 2 full (cracks, prop char)
##
## Dev args: --blight=<0..1> forces the ambient blight in every scene, --blight-quality=<0|1|2>.
##
## Cost: one small stamp (~250 texels) every STAMP_INTERVAL and one texture upload. The texture
## is toroidal (wraps every RES * texel_size meters); each texel also stores the id of the world
## tile it was painted in, so a wrapped trail never shows up a window-width away.

## Texture size in texels. Must match CORRUPTION_RES in corruption.gdshaderinc.
const RES := 256
## Seconds between trail stamps / texture uploads.
const STAMP_INTERVAL := 0.1

## World size of one texel (m). RES * texel_size = the window before wrapping (96 m).
var texel_size := 0.375
## Radius (m) of the trail brush painted under the player.
var trail_radius := 2.6
## Radius (m) of the live blight aura that follows the player (0 = none).
var aura_radius := 3.4
## Seconds a trail texel stays at full strength, then fades out by `lifetime`.
var hold_time := 14.0
var lifetime := 32.0
## Corruption everywhere (0..1). Basecamp Hell sets 1 in its _ready(). It belongs to the scene
## that set it: on a scene change it falls back to 0 (and the trail is wiped).
var ambient := 0.0:
	set(v):
		ambient = clampf(v, 0.0, 1.0)
		_ambient_scene = _scene_id()
		RenderingServer.global_shader_parameter_set(&"corruption_ambient", ambient)
## Master switch (e.g. for a holy-sanctuary map or the bestiary).
var enabled := true
## Shader quality: 0 = off, 1 = low (charred crust only: no crack network, no prop char), 2 = full.
## Global, so it applies to every corruption-aware shader at once (corruption_quality uniform).
var quality := 2:
	set(v):
		quality = clampi(v, 0, 2)
		RenderingServer.global_shader_parameter_set(&"corruption_quality", float(quality))
## Node the trail follows. Defaults to Game.player; set it for scenes without a Player (the hub
## avatar, menus). Cleared automatically when the node is freed.
var focus: Node3D
## Radius (m) / strength of the blight left where an angel dies (0 = off).
var kill_stamp_radius := 1.5
var kill_stamp_strength := 0.75

var _img: Image
var _tex: ImageTexture
## Starts well above hold_time + lifetime so even edge stamps (painted "older") stay > 0; a
## timestamp <= 0 means "never painted".
var _clock := 100.0
var _stamp_left := 0.0
var _dirty := false
var _player: Node3D
var _scene := 0
var _ambient_scene := 0
## --blight=<x> dev override of the ambient (< 0 = none).
var _forced_ambient := -1.0
## --blight-quality=<q> dev override (< 0 = follow the graphics preset).
var _forced_quality := -1


func _ready() -> void:
	_img = Image.create_empty(RES, RES, false, Image.FORMAT_RGF)
	_img.fill(Color(0.0, 0.0, 0.0, 1.0))
	_tex = ImageTexture.create_from_image(_img)
	RenderingServer.global_shader_parameter_set(&"corruption_map", _tex)
	RenderingServer.global_shader_parameter_set(&"corruption_ambient", ambient)
	_push_params()
	RenderingServer.global_shader_parameter_set(&"corruption_origin", Vector4(0.0, 0.0, 0.0, 0.0))
	Game.enemy_died.connect(_on_game_enemy_died)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--blight="):
			_forced_ambient = arg.substr(9).to_float()
		elif arg.begins_with("--blight-quality="):
			_forced_quality = arg.substr(17).to_int()
	Settings.graphics_changed.connect(_apply_quality)
	_apply_quality()


func _process(delta: float) -> void:
	_clock += delta
	var scene := _scene_id()
	if scene != _scene:
		# A new run / the hub: start from a clean map. Keep an ambient the new scene already set.
		_scene = scene
		clear()
		if _forced_ambient >= 0.0:
			ambient = _forced_ambient
		elif _ambient_scene != scene:
			ambient = 0.0
	_player = _find_player()
	var origin := Vector4.ZERO
	if enabled and _player:
		var pos := _player.global_position
		origin = Vector4(pos.x, pos.y, pos.z, aura_radius)
		_stamp_left -= delta
		if _stamp_left <= 0.0:
			_stamp_left = STAMP_INTERVAL
			stamp(pos, trail_radius)
	RenderingServer.global_shader_parameter_set(&"corruption_origin", origin)
	_push_params()
	if _dirty:
		_dirty = false
		_tex.update(_img)


## Blights a disc of `radius` meters around `pos`. `strength` < 1 paints it "older", so it fades
## sooner (0.5 = fades in about half the time).
func stamp(pos: Vector3, radius: float, strength: float = 1.0) -> void:
	if not enabled or radius <= 0.0:
		return
	var center := Vector2(pos.x, pos.z) / texel_size
	var r := radius / texel_size
	var lo := Vector2i(floori(center.x - r), floori(center.y - r))
	var hi := Vector2i(ceili(center.x + r), ceili(center.y + r))
	var base_age := (1.0 - clampf(strength, 0.0, 1.0)) * lifetime
	for iy in range(lo.y, hi.y + 1):
		for ix in range(lo.x, hi.x + 1):
			var d := Vector2(ix + 0.5, iy + 0.5).distance_to(center) / r
			if d > 1.0:
				continue
			# Texels toward the rim are stamped "older": the blob shrinks back from its edge.
			var stamp_time := _clock - base_age - d * d * hold_time * 0.9
			_write_texel(ix, iy, maxf(stamp_time, 0.001))
	_dirty = true


## Trail strength 0..1 at a world position (ignores the live aura and the shader's edge noise).
func amount_at(pos: Vector3) -> float:
	var ix := floori(pos.x / texel_size)
	var iy := floori(pos.z / texel_size)
	var tx := floori(float(ix) / RES)
	var ty := floori(float(iy) / RES)
	var c := _img.get_pixel(ix - tx * RES, iy - ty * RES)
	if absf(c.g - _tile_id(tx, ty)) > 0.5 or c.r <= 0.0:
		return ambient
	var age := _clock - c.r
	return maxf(ambient, 1.0 - smoothstep(hold_time, lifetime, age))


## Wipes the trail.
func clear() -> void:
	if _img:
		_img.fill(Color(0.0, 0.0, 0.0, 1.0))
		_dirty = true


func _write_texel(ix: int, iy: int, stamp_time: float) -> void:
	var tx := floori(float(ix) / RES)
	var ty := floori(float(iy) / RES)
	var lx := ix - tx * RES
	var ly := iy - ty * RES
	var id := _tile_id(tx, ty)
	var old := _img.get_pixel(lx, ly)
	# Same tile: keep the fresher stamp. Other tile: the old stamp is from far away, overwrite.
	if absf(old.g - id) < 0.5 and old.r >= stamp_time:
		return
	_img.set_pixel(lx, ly, Color(stamp_time, id, 0.0, 1.0))


## World tile id, packed exactly like the shader (10 bits per axis, two's-complement wrap).
func _tile_id(tx: int, ty: int) -> float:
	return float((tx & 1023) + (ty & 1023) * 1024)


func _push_params() -> void:
	RenderingServer.global_shader_parameter_set(&"corruption_params",
			Vector4(_clock, hold_time, lifetime, texel_size))


## Settings > Graphics > "Blight detail" (Settings.blight_quality; the Low preset sets 1 = crust
## only, saving ~0.2-0.4 ms GPU at 720p on a mid/high-end GPU, more on weak ones; see
## docs/team/art-style.md "Performance").
func _apply_quality() -> void:
	if _forced_quality >= 0:
		quality = _forced_quality
	else:
		quality = Settings.blight_quality


func _on_game_enemy_died(pos: Vector3, _data: Resource) -> void:
	if kill_stamp_radius > 0.0:
		stamp(pos, kill_stamp_radius, kill_stamp_strength)


func _scene_id() -> int:
	var tree := get_tree()
	return tree.current_scene.get_instance_id() if tree and tree.current_scene else 0


func _find_player() -> Node3D:
	if focus and is_instance_valid(focus) and focus.is_inside_tree():
		return focus
	if Game.player and is_instance_valid(Game.player) and Game.player.is_inside_tree():
		return Game.player
	return null
