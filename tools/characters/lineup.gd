extends Node3D
## Character polish: every enemy (at its EnemyData.size) next to the player's demon, seen through
## the real game camera angle, to judge readability and proportions as the player sees them.
##
##   godot --path . res://tools/characters/lineup.tscn -- --shot=<abs png> [--only=id,id]
##         [--cols=8] [--dist=26] [--state=0..3] [--time=1.5] [--bosses (adds data/bosses)]
## Without --shot it just runs. State 1 (wind-up) cycles progress so telegraphs can be judged.

var spacing := 3.2

var _models: Array[EnemyModel] = []
var _state := 0
var _t := 0.0


func _ready() -> void:
	var shot := ""
	var only := PackedStringArray()
	var cols := 8
	var dist := 26.0
	var shot_time := 1.5
	var dirs := ["res://data/enemies"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.substr(7)
		elif a.begins_with("--only="):
			only = a.substr(7).split(",")
		elif a.begins_with("--cols="):
			cols = a.substr(7).to_int()
		elif a.begins_with("--dist="):
			dist = a.substr(7).to_float()
		elif a.begins_with("--state="):
			_state = a.substr(8).to_int()
		elif a.begins_with("--spacing="):
			spacing = a.substr(10).to_float()
		elif a == "--bosses":
			dirs.append("res://data/bosses")
		elif a.begins_with("--time="):
			shot_time = a.substr(7).to_float()
	Game.world = self
	_stage()
	var ids: Array[String] = []
	for dir: String in dirs:
		var d := DirAccess.open(dir)
		for f in d.get_files():
			if f.ends_with(".tres") and (only.is_empty() or f.get_basename() in only):
				ids.append(dir.path_join(f))
	ids.sort()
	var n := ids.size() + 1
	cols = mini(cols, n)
	var rows := ceili(float(n) / float(cols))
	for i in n:
		@warning_ignore("integer_division")
		var pos := Vector3((float(i % cols) - float(cols - 1) * 0.5) * spacing, 0.0,
				(float(i / cols) - float(rows - 1) * 0.5) * spacing)
		if i == 0:
			var demon := DemonModel.new()
			add_child(demon)
			demon.position = pos
			demon.build(load("res://data/demons/vharok.tres") as DemonData)
			_label(pos, "PLAYER")
			continue
		var data := load(ids[i - 1]) as EnemyData
		if data == null or data.model == null:
			continue
		var m := data.model.instantiate() as EnemyModel
		m.body_scale = data.size
		m.scale = Vector3.ONE * data.size
		m.position = pos + Vector3(0.0, data.hover, 0.0)
		add_child(m)
		_models.append(m)
		ArtStyle.apply_faction(m, ArtStyle.Faction.HOLY, data.xp_value >= 20)
		_label(pos, ids[i - 1].get_file().get_basename())
	var cam := Camera3D.new()
	cam.fov = 35.0
	add_child(cam)
	var pitch := deg_to_rad(55.0)
	# `dist` is the game camera's distance (26); pulled back so the whole grid fits.
	var fit := maxf(float(cols) * spacing * 0.95, float(rows) * spacing * 1.7)
	cam.position = Vector3(0.0, sin(pitch), cos(pitch)) * maxf(dist, fit)
	cam.look_at(Vector3.ZERO)
	if shot != "":
		await get_tree().create_timer(shot_time).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot)
		get_tree().quit()


func _physics_process(delta: float) -> void:
	_t += delta
	for m in _models:
		m.state_progress = fmod(_t, 1.5) / 1.5
		m.state_duration = 1.5
		m.ground_speed = 0.0
		m.animate(delta, 0.0, _state)


func _label(pos: Vector3, text: String) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = 0.004
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = pos + Vector3(0.0, 0.05, 1.1)
	add_child(l)


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
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120.0, 120.0)
	ground.mesh = pm
	ground.material_override = Art.mat(Color(0.2, 0.17, 0.15), 0.95, 0.0, 0.0)
	add_child(ground)
