extends Node3D
## Character polish test bench: a demon (or an angel) runs a scripted course (accelerate, sprint,
## stop dead, hard turns, hits from different sides, attack, death) and frames are saved as a
## contact sheet, so procedural motion can be judged without playing.
##
##   godot --path . res://tools/characters/motion_test.tscn -- --demon=vharok --sheet=out.png
##   options: --enemy=seraph_sentinel (angel instead of a demon) --view=game|side|front
##            --at=0.5,1.0,... (capture times, s) --cols=4 --size=360 --skin=<skin id>
##            --victory (the ASCENDANT roar at 8.5 s instead of the death)
## Without --sheet it just runs (watch it in a window).

const COURSE_SPEED := 6.0

var _demon: DemonModel
var _enemy: EnemyModel
var _mover: Node3D
var _cam: Camera3D
var _t := 0.0
var _pos := Vector3.ZERO
var _vel := Vector3.ZERO
var _yaw := 0.0
var _shots: Array[float] = []
var _images: Array[Image] = []
var _sheet := ""
var _cols := 4
var _size := 360
var _view := "side"
var _hits_done := {}
var _hide: PackedStringArray = PackedStringArray()
## Camera distance multiplier (big angels / bosses).
var _cam_k := 1.0


func _ready() -> void:
	var demon_id := "vharok"
	var enemy_id := ""
	var skin_id := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--demon="):
			demon_id = a.substr(8)
		elif a.begins_with("--enemy="):
			enemy_id = a.substr(8)
		elif a.begins_with("--sheet="):
			_sheet = a.substr(8)
		elif a.begins_with("--view="):
			_view = a.substr(7)
		elif a.begins_with("--cols="):
			_cols = a.substr(7).to_int()
		elif a.begins_with("--size="):
			_size = a.substr(7).to_int()
		elif a.begins_with("--skin="):
			skin_id = a.substr(7)
		elif a.begins_with("--at="):
			for p in a.substr(5).split(","):
				_shots.append(p.to_float())
	if _shots.is_empty():
		_shots = [0.4, 1.3, 1.8, 2.4, 3.05, 3.3, 3.6, 4.2, 4.9, 5.6, 6.4, 7.6]
	_build_stage()
	Game.world = self
	_mover = Node3D.new()
	add_child(_mover)
	if enemy_id != "":
		var path := enemy_id if enemy_id.begins_with("res://") else "res://data/enemies/%s.tres" % enemy_id
		var data := load(path) as EnemyData
		_enemy = data.model.instantiate() as EnemyModel
		_enemy.scale = Vector3.ONE * data.size
		_enemy.body_scale = data.size
		_cam_k = maxf(data.size, 1.0)
		_mover.add_child(_enemy)
	else:
		_demon = DemonModel.new()
		_mover.add_child(_demon)
		_demon.build(load("res://data/demons/%s.tres" % demon_id) as DemonData)
		if skin_id != "":
			_demon.build(_demon.data, StringName(skin_id))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hide="):
			# Debug: hide every node of a class or name, e.g. --hide=OmniLight3D,grimoire
			_hide.append_array(a.substr(7).split(","))


func _build_stage() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.15, 0.16)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.48, 0.5)
	env.environment.ambient_light_energy = 0.6
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment.glow_enabled = true
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80.0, 80.0)
	ground.mesh = pm
	ground.material_override = Art.mat(Color(0.32, 0.3, 0.29), 0.95, 0.0, 0.0)
	add_child(ground)
	# Grid lines every metre so motion against the ground reads.
	for i in range(-20, 21):
		for along: int in [0, 1]:
			var line := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(40.0, 0.004, 0.02) if along == 0 else Vector3(0.02, 0.004, 40.0)
			line.mesh = bm
			line.material_override = Art.mat(Color(0.2, 0.19, 0.19), 1.0, 0.0, 0.0)
			line.position = Vector3(0.0, 0.002, float(i)) if along == 0 else Vector3(float(i), 0.002, 0.0)
			add_child(line)
	_cam = Camera3D.new()
	_cam.fov = 35.0
	add_child(_cam)


## Scripted course: returns the desired velocity at time t.
func _course(t: float) -> Vector3:
	if t < 1.0:
		return Vector3.ZERO  # idle
	if t < 3.0:
		return Vector3(1.0, 0.0, 0.0) * COURSE_SPEED  # sprint along +X
	if t < 4.0:
		return Vector3.ZERO  # stop dead (hit at 3.3 from the front)
	if t < 6.5:
		# Hard circle (banking).
		var a := (t - 4.0) * 2.4
		return Vector3(cos(a), 0.0, -sin(a)) * COURSE_SPEED
	return Vector3.ZERO  # attack at 6.8, hit from behind at 7.3, death at 8.5


func _physics_process(delta: float) -> void:
	_t += delta
	var want := _course(_t)
	_vel = _vel.move_toward(want, 40.0 * delta)
	_pos += _vel * delta
	_mover.position = _pos
	if _vel.length() > 0.2:
		_yaw = lerp_angle(_yaw, atan2(-_vel.x, -_vel.z), 1.0 - exp(-15.0 * delta))
	_mover.rotation.y = _yaw
	if _demon:
		_demon.ground_speed = _vel.length()
		_demon.animate(delta, _vel.length() / COURSE_SPEED)
	elif _enemy:
		# Angels: wind-up 6.5-7.6 s (telegraph), strike 7.6-7.9 s, recover to 8.5 s.
		var st := EnemyModel.State.MOVING
		if _t >= 6.5 and _t < 7.6:
			st = EnemyModel.State.WINDUP
			_enemy.state_progress = (_t - 6.5) / 1.1
			_enemy.state_duration = 1.1
		elif _t >= 7.6 and _t < 7.9:
			st = EnemyModel.State.ATTACKING
			_enemy.state_progress = (_t - 7.6) / 0.3
			_enemy.state_duration = 0.3
		elif _t >= 7.9 and _t < 8.5:
			st = EnemyModel.State.RECOVER
			_enemy.state_progress = (_t - 7.9) / 0.6
			_enemy.state_duration = 0.6
		_event(7.6, func() -> void: _enemy.play_attack())
		_enemy.ground_speed = _vel.length()
		_enemy.animate(delta, _vel.length() / COURSE_SPEED, st)
	_event(3.3, func() -> void: _hit(_mover.global_position + _forward() * 2.0))
	_event(6.8, func() -> void: if _demon: _demon.play_attack())
	_event(7.3, func() -> void: _hit(_mover.global_position - _forward() * 2.0))
	if OS.get_cmdline_user_args().has("--victory"):
		_event(8.5, func() -> void: if _demon: _demon.play_victory())
	else:
		_event(8.5, func() -> void: if _demon: _demon.play_faint())
	_update_camera()
	if not _hide.is_empty():
		_apply_hide(_mover)
	if OS.get_cmdline_user_args().has("--debug") and _demon and _demon._motion \
			and fmod(_t, 0.25) < delta:
		var m := _demon._motion
		print("lv=%s t=%.2f v=%.1f lean=%s wing0=%s dangle0=%s joints=%d" % [m._vel, _t, _vel.length(), m._lean,
			m._wing_s[0] if m._wing_s.size() > 0 else Vector2.ZERO,
			m._dangle_s[0] if m._dangle_s.size() > 0 else Vector2.ZERO, m.joint_count()])


func _apply_hide(n: Node) -> void:
	for h in _hide:
		if (n.get_class() == h or String(n.name) == h) and n is Node3D:
			(n as Node3D).visible = false
	for c in n.get_children():
		_apply_hide(c)


func _forward() -> Vector3:
	return -_mover.global_basis.z


func _hit(from: Vector3) -> void:
	if _demon:
		_demon.play_hurt(from - _mover.global_position)
	elif _enemy:
		_enemy.jiggle_eyes(1.0)
		_enemy.hit_from(from - _mover.global_position, 1.0)


func _event(at: float, f: Callable) -> void:
	if _t >= at and not _hits_done.has(at):
		_hits_done[at] = true
		f.call()


func _update_camera() -> void:
	var focus := _mover.global_position + Vector3(0.0, 1.0 * _cam_k, 0.0)
	match _view:
		"game":
			var pitch := deg_to_rad(55.0)
			_cam.position = focus + Vector3(0.0, sin(pitch), cos(pitch)) * 16.0 * _cam_k
		"front":
			_cam.position = focus + (_forward() * 7.0 + Vector3(0.0, 1.0, 0.0)) * _cam_k
		_:
			var side := _mover.global_basis.x
			_cam.position = focus + (side * 6.5 + _forward() * 2.5 + Vector3(0.0, 1.2, 0.0)) * _cam_k
	_cam.look_at(focus)


func _process(_delta: float) -> void:
	if _sheet == "" or _shots.is_empty():
		return
	if _t >= _shots[0]:
		_shots.pop_front()
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var h := img.get_height()
		@warning_ignore("integer_division")
		img = img.get_region(Rect2i((img.get_width() - h) / 2, 0, h, h))
		img.resize(_size, _size)
		_images.append(img)
		if _shots.is_empty():
			_save_sheet()


func _save_sheet() -> void:
	var rows := ceili(float(_images.size()) / float(_cols))
	var sheet := Image.create(_size * _cols, _size * rows, false, Image.FORMAT_RGBA8)
	for i in _images.size():
		var im := _images[i]
		im.convert(Image.FORMAT_RGBA8)
		@warning_ignore("integer_division")
		sheet.blit_rect(im, Rect2i(0, 0, _size, _size), Vector2i((i % _cols) * _size, (i / _cols) * _size))
	sheet.save_png(_sheet)
	print("SHEET ", _sheet)
	get_tree().quit()
