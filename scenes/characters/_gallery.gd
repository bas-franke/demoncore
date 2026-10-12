extends Node3D
## Dev-only: lines up every procedural character model (scenes/characters/{enemies,allies,npcs})
## under game-like light, animating them through their states, for screenshots.
##   godot --path . res://scenes/characters/_gallery.tscn -- --shot=<abs png> --shot-time=3
## Options: --only=cherub,paladin (ids)  --dir=enemies|allies|npcs  --state=0..3 (fixed
## EnemyModel.State; default cycles moving -> windup -> attacking -> recover every 1.5 s)
##          --move=0..1  --cols=N  --close  (camera nearer)  --side (view from the side)

const DIRS := ["res://scenes/characters/enemies/", "res://scenes/characters/allies/", "res://scenes/characters/bosses/",
	"res://scenes/characters/npcs/"]
const SPACING := 2.6

var _models: Array[EnemyModel] = []
var _state := -1
var _move := 1.0
var _t := 0.0


func _ready() -> void:
	var only := PackedStringArray()
	var dir_filter := ""
	var cols := 6
	var close := false
	var side := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",")
		elif a.begins_with("--dir="):
			dir_filter = a.trim_prefix("--dir=")
		elif a.begins_with("--state="):
			_state = int(a.trim_prefix("--state="))
		elif a.begins_with("--move="):
			_move = float(a.trim_prefix("--move="))
		elif a.begins_with("--cols="):
			cols = int(a.trim_prefix("--cols="))
		elif a == "--close":
			close = true
		elif a == "--side":
			side = true
	_setup_world()
	var paths: Array[String] = []
	for d in DIRS:
		if dir_filter != "" and not d.contains("/%s/" % dir_filter):
			continue
		for f in ResourceLoader.list_directory(d):
			# (bosses/: only the *_model scenes; the boss bodies are CharacterBody3Ds)
			if f.ends_with(".tscn") and (only.is_empty() or f.get_basename() in only) 					and (not d.ends_with("bosses/") or f.ends_with("_model.tscn")):
				paths.append(d + f)
	var n := paths.size()
	cols = mini(cols, maxi(n, 1))
	var rows := ceili(float(n) / float(cols))
	for i in n:
		var m := (load(paths[i]) as PackedScene).instantiate() as EnemyModel
		if m is ProcModel:
			(m as ProcModel).autoplay = false
		var c := i % cols
		@warning_ignore("integer_division")  # grid row
		var r := i / cols
		m.position = Vector3((float(c) - float(cols - 1) * 0.5) * SPACING, 0.0, (float(r) - float(rows - 1) * 0.5) * SPACING)
		m.rotation.y = PI * (0.5 if side else 0.88)
		add_child(m)
		_models.append(m)
		var label := Label3D.new()
		label.text = paths[i].get_file().get_basename()
		label.pixel_size = 0.005
		label.font_size = 48
		label.outline_size = 12
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = m.position + Vector3(0.0, 0.05, 1.0)
		add_child(label)
	if "--stats" in OS.get_cmdline_user_args():
		_print_stats.call_deferred()
	var cam := Camera3D.new()
	cam.fov = 35.0
	# Fit the row width into the horizontal field of view (16:9), and the rows vertically.
	var dist := maxf(float(cols) * SPACING * 0.95, float(rows) * SPACING * 1.5) * (0.75 if close else 1.0) + 1.5
	cam.transform = Transform3D(Basis(Vector3.RIGHT, -0.75), Vector3(0.0, dist * 0.68 + 0.7, dist * 0.73))
	add_child(cam)
	cam.current = true


func _setup_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.04, 0.045)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.42, 0.45)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, -0.6, 0.0)
	sun.light_color = Color(1, 0.86, 0.7)
	sun.light_energy = 2.0
	sun.shadow_enabled = true
	add_child(sun)
	Art.part(self, Art.box(), Art.mat(Color(0.2, 0.17, 0.16), 0.9, 0.0, 0.4, false), Vector3(0, -0.05, 0), Vector3(80, 0.1, 80))


func _process(delta: float) -> void:
	_t += delta
	var st := _state
	if st < 0:
		st = int(_t / 1.5) % 4
	for m in _models:
		m.state_progress = fmod(_t, 1.5) / 1.5
		m.state_duration = 1.5
		m.ground_speed = 2.5 * _move if st == EnemyModel.State.MOVING else 0.0
		m.animate(delta, _move if st == EnemyModel.State.MOVING else 0.0, st)


## --stats: mesh instances / draw surfaces per model (after merging).
func _print_stats() -> void:
	await get_tree().process_frame
	for m in _models:
		var meshes := 0
		var surfaces := 0
		var stack: Array[Node] = [m]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			stack.append_array(n.get_children())
			var mi := n as MeshInstance3D
			if mi and mi.mesh and mi.visible and not mi.is_queued_for_deletion():
				meshes += 1
				surfaces += mi.mesh.get_surface_count()
		print("%-22s meshes %3d  surfaces %3d" % [m.name, meshes, surfaces])
