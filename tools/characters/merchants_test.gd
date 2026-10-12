extends Node3D
## Basecamp merchant figures bench (characters-polish): the four HubShopkeepers side by side
## under hub-like light, frames saved over time to judge the craft idles.
##
##   godot --path . res://tools/characters/merchants_test.tscn -- --sheet=<abs png>
##         [--only=0,2] [--at=0.5,1.0,...] [--greet=2.0] [--view=front|game] [--size=640] [--focus]

var _t := 0.0
var _keepers: Array[HubShopkeeper] = []
var _shots: Array[float] = []
var _images: Array[Image] = []
var _sheet := ""
var _size := 640
var _greet_at := -1.0


func _ready() -> void:
	var looks: Array = [0, 1, 2, 3]
	var view := "front"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sheet="):
			_sheet = a.substr(8)
		elif a.begins_with("--only="):
			looks = Array(a.substr(7).split(",")).map(func(x: String) -> int: return x.to_int())
		elif a.begins_with("--at="):
			for p in a.substr(5).split(","):
				_shots.append(p.to_float())
		elif a.begins_with("--greet="):
			_greet_at = a.substr(8).to_float()
		elif a.begins_with("--view="):
			view = a.substr(7)
		elif a.begins_with("--size="):
			_size = a.substr(7).to_int()
	if _shots.is_empty():
		_shots = [0.6, 1.2, 1.9, 2.6, 3.3, 4.0, 4.8, 5.6]
	_stage()
	for i in looks.size():
		var k := HubShopkeeper.new()
		k.look = looks[i]
		k.position = Vector3((float(i) - float(looks.size() - 1) * 0.5) * 3.2, 0.0, 0.0)
		add_child(k)
		_keepers.append(k)
	var cam := Camera3D.new()
	cam.fov = 35.0
	add_child(cam)
	var w := float(looks.size()) * 3.2
	if view == "game":
		var pitch := deg_to_rad(55.0)
		cam.position = Vector3(0.0, sin(pitch), cos(pitch)) * maxf(w * 1.1, 14.0)
		cam.look_at(Vector3(0.0, 1.0, 0.0))
	else:
		cam.position = Vector3(0.0, 2.4, -maxf(w * 1.25, 6.5))
		cam.look_at(Vector3(0.0, 1.4, 0.0))


func _process(delta: float) -> void:
	_t += delta
	if OS.get_cmdline_user_args().has("--focus") and _t > 0.3:
		for k in _keepers:
			k.set_focused(true)
	if _greet_at >= 0.0 and _t >= _greet_at:
		_greet_at = -1.0
		for k in _keepers:
			k.interact()
	if _sheet == "" or _shots.is_empty() or _t < _shots[0]:
		return
	_shots.pop_front()
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	@warning_ignore("integer_division")
	img.resize(_size, _size * img.get_height() / img.get_width())
	_images.append(img)
	if _shots.is_empty():
		var iw := _images[0].get_width()
		var ih := _images[0].get_height()
		var rows := ceili(float(_images.size()) / 2.0)
		var sheet := Image.create(iw * 2, ih * rows, false, Image.FORMAT_RGBA8)
		for i in _images.size():
			_images[i].convert(Image.FORMAT_RGBA8)
			@warning_ignore("integer_division")
			sheet.blit_rect(_images[i], Rect2i(0, 0, iw, ih), Vector2i((i % 2) * iw, (i / 2) * ih))
		sheet.save_png(_sheet)
		print("SHEET ", _sheet)
		get_tree().quit()


func _stage() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.12, 0.05, 0.04)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.4, 0.35)
	env.environment.ambient_light_energy = 0.6
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment.glow_enabled = true
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 160.0, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60.0, 60.0)
	ground.mesh = pm
	ground.material_override = Art.mat(Color(0.2, 0.15, 0.13), 0.95, 0.0, 0.0)
	add_child(ground)
