extends SceneTree
## Side-by-side Godot render of baked vs. untextured GLB models (tools/blender/bake.py).
##   godot --path . --script res://tools/bake_preview.gd -- out.png res://a.glb [res://b.glb | C:/abs/c.glb ...]
## Options (before the paths): --close (3/4 hero camera instead of the high game camera),
##   --flat (convert materials ignoring textures for EVERY model), --yaw=DEG (turn models),
##   --spacing=M (distance between models, default 2.4), --look=M (close-camera target height).
## Models face the camera (+Z in Godot = Blender -Y front).
## Models are laid out left -> right. Renders a few frames, saves the PNG, quits.

var _frames := 0
var _out := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var paths: Array[String] = []
	var close := false
	var flat := false
	var yaw := 0.0
	var spacing_opt := 2.4
	var look_h := 0.9
	for a in args:
		if a == "--close":
			close = true
		elif a == "--flat":
			flat = true
		elif a.begins_with("--spacing="):
			spacing_opt = a.substr(10).to_float()
		elif a.begins_with("--look="):
			look_h = a.substr(7).to_float()
		elif a.begins_with("--yaw="):
			yaw = a.substr(6).to_float()
		elif _out == "":
			_out = a
		else:
			paths.append(a)
	var root3 := Node3D.new()
	get_root().add_child(root3)
	_env(root3)
	var spacing := spacing_opt
	var x0 := -spacing * (paths.size() - 1) * 0.5
	for i in paths.size():
		var p := paths[i]
		var inst := _load_model(p)
		if inst == null:
			push_error("bake_preview: cannot load " + p)
			continue
		var holder := Node3D.new()
		holder.position = Vector3(x0 + spacing * i, 0, 0)
		holder.rotation_degrees.y = yaw
		root3.add_child(holder)
		holder.add_child(inst)
		GlbModel.convert_materials(inst, true, not flat)
	var cam := Camera3D.new()
	cam.fov = 40.0
	var w := spacing * maxf(1.0, paths.size())
	if close:
		cam.position = Vector3(1.2, 1.6, 2.6 + w * 0.35)
		root3.add_child(cam)
		cam.look_at_from_position(cam.position, Vector3(0, look_h, 0))
	else:
		cam.position = Vector3(0, 2.6 + w * 0.9, 2.0 + w * 0.75)
		root3.add_child(cam)
		cam.look_at_from_position(cam.position, Vector3(0, 0.7, 0))
	cam.current = true
	get_root().size = Vector2i(1280, 720)


## res:// paths load the imported scene; absolute file paths (e.g. a backup .glb outside the
## project) are parsed at runtime with GLTFDocument, so old and new builds compare side by side.
func _load_model(p: String) -> Node3D:
	if p.begins_with("res://"):
		var ps := load(p) as PackedScene
		return ps.instantiate() as Node3D if ps else null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(p, state) != OK:
		return null
	return doc.generate_scene(state) as Node3D


func _env(parent: Node3D) -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.36, 0.42)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.ssao_enabled = true
	we.environment = env
	parent.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.86, 0.68)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-48, -30, 0)
	parent.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.55, 0.65, 1.0)
	fill.light_energy = 0.5
	fill.rotation_degrees = Vector3(-30, 140, 0)
	parent.add_child(fill)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	ground.mesh = pm
	ground.material_override = Art.mat(Color(0.16, 0.15, 0.14), 0.95, 0.0, 0.3, false)
	parent.add_child(ground)


func _process(_dt: float) -> bool:
	_frames += 1
	if _frames == 12:
		var img := get_root().get_texture().get_image()
		img.save_png(_out)
		print("SHOT ", _out)
		return true
	return false
