extends Node3D
## Death variety bench (characters-polish): real Enemies of each faction are killed by a blow from
## the left (+X knockback) and frames are saved as a contact sheet.
##
##   godot --path . res://tools/characters/death_test.tscn -- --sheet=<abs png>
##         [--only=holy_knight,cherub,saint_statue,...] [--at=0.6,0.75,...] [--size=480]

const DEFAULT_IDS := ["holy_knight", "villager_pitchfork", "holy_lion", "cherub", "seraph",
	"light_elemental", "saint_statue", "glass_golem", "bell_gargoyle"]

var _t := 0.0
var _killed := false
var _enemies: Array[Enemy] = []
## --models: bare EnemyModels (no Enemy / AI) killed via death_burst(), e.g. when enemy.gd is
## mid-edit elsewhere. The blow comes from the left.
var _bare: Array[EnemyModel] = []
var _bare_data: Array[EnemyData] = []
var _shots: Array[float] = []
var _images: Array[Image] = []
var _sheet := ""
var _size := 480


func _ready() -> void:
	var ids: Array = DEFAULT_IDS.duplicate()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sheet="):
			_sheet = a.substr(8)
		elif a.begins_with("--only="):
			ids = Array(a.substr(7).split(","))
		elif a.begins_with("--size="):
			_size = a.substr(7).to_int()
		elif a.begins_with("--at="):
			for p in a.substr(5).split(","):
				_shots.append(p.to_float())
	if _shots.is_empty():
		_shots = [0.55, 0.7, 0.85, 1.0, 1.2, 1.5, 1.9, 2.4]
	Game.world = self
	_stage()
	var bare := OS.get_cmdline_user_args().has("--models")
	for i in ids.size():
		var data := load("res://data/enemies/%s.tres" % ids[i]) as EnemyData
		if bare:
			var m := data.model.instantiate() as EnemyModel
			m.body_scale = data.size
			m.scale = Vector3.ONE * data.size
			m.position = Vector3((float(i) - float(ids.size() - 1) * 0.5) * 2.6, data.hover, 0.0)
			add_child(m)
			_bare.append(m)
			_bare_data.append(data)
			continue
		var e := (load("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate() as Enemy
		e.setup(data)
		e.position = Vector3((float(i) - float(ids.size() - 1) * 0.5) * 2.6, 0.0, 0.0)
		add_child(e)
		e.set_physics_process(false)  # no player here: just stand
		_enemies.append(e)
	var cam := Camera3D.new()
	cam.fov = 35.0
	add_child(cam)
	var pitch := deg_to_rad(55.0)
	cam.position = Vector3(0.0, sin(pitch), cos(pitch)) * maxf(8.0, float(ids.size()) * 2.6 * 1.1)
	cam.look_at(Vector3(0.0, 0.5, 0.0))


func _physics_process(delta: float) -> void:
	_t += delta
	for e in _enemies:
		if is_instance_valid(e) and e.model:
			e.model.animate(delta, 0.0, EnemyModel.State.MOVING)
	for m in _bare:
		if is_instance_valid(m) and m.get_parent() == self:
			m.animate(delta, 0.0, EnemyModel.State.MOVING)
	if _t >= 0.5 and not _killed:
		_killed = true
		for i in _bare.size():
			var m := _bare[i]
			m.jiggle_eyes(1.0, Vector3(-1.0, 0.0, 0.0))
			m.death_burst(m.global_position + Vector3(0.0, 0.45 * _bare_data[i].size, 0.0), _bare_data[i].size, false)
			if is_instance_valid(m) and m.get_parent() == self:
				m.queue_free()
		# Every enemy, including companions the models spawned themselves (pairs, flocks).
		for n in get_tree().get_nodes_in_group(&"enemies"):
			var e := n as Enemy
			if e and is_instance_valid(e) and not e.is_dying:
				e.take_damage(1.0e6, Vector3(1.0, 0.0, 0.0) * 6.0)


func _process(_delta: float) -> void:
	if _sheet == "" or _shots.is_empty() or _t < _shots[0]:
		return
	_shots.pop_front()
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	@warning_ignore("integer_division")
	img.resize(_size, _size * img.get_height() / img.get_width())
	_images.append(img)
	if _shots.is_empty():
		var w := _images[0].get_width()
		var h := _images[0].get_height()
		var cols := 2
		var rows := ceili(float(_images.size()) / float(cols))
		var sheet := Image.create(w * cols, h * rows, false, Image.FORMAT_RGBA8)
		for i in _images.size():
			_images[i].convert(Image.FORMAT_RGBA8)
			@warning_ignore("integer_division")
			sheet.blit_rect(_images[i], Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
		sheet.save_png(_sheet)
		print("SHEET ", _sheet)
		get_tree().quit()


func _stage() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.1, 0.09, 0.09)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.45, 0.42, 0.45)
	env.environment.ambient_light_energy = 0.5
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment.glow_enabled = true
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120.0, 120.0)
	ground.mesh = pm
	ground.material_override = Art.mat(Color(0.25, 0.22, 0.2), 0.95, 0.0, 0.0)
	add_child(ground)
