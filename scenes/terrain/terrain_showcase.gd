extends Node3D
## Stand-alone viewer for the terrain kit (no run, no enemies):
##   godot --path . res://scenes/terrain/terrain_showcase.tscn -- --theme=hell --view=arena
##   --theme=hell|heaven|sanctum   TerrainTheme from res://data/terrain/
##   --view=arena     a full TerrainPatch seen from the game camera (default)
##   --view=props     every PropKit prop of the theme's realm in a grid on flat ground
##   --view=overview  the whole patch from high above
##   --seed=N         layout seed;  --at=x,z  camera focus
##   --tshot=out.png --tshot-time=4   save a screenshot and quit (independent of the Game autoload)
## Controls: WASD / arrows pan, mouse wheel zoom, Q/E orbit, R rebuild with a new seed.

const GAME_CAM_OFFSET := Vector3(0, 21.7, 14.91)

var theme_name := "hell"
var view := "arena"
var seed_value := 1
var patch: TerrainPatch
var cam: Camera3D
var focus := Vector3.ZERO
var zoom := 1.0
var yaw := 0.0
var _shot_path := ""
var _shot_time := 4.0
var _zoom_arg := 0.0
## Props grid content: "" = the theme's realm, "holy", "hell" or "site" (SiteProps).
var prop_set := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--theme="):
			theme_name = arg.substr(8)
		elif arg.begins_with("--view="):
			view = arg.substr(7)
		elif arg.begins_with("--seed="):
			seed_value = arg.substr(7).to_int()
		elif arg.begins_with("--tshot="):
			_shot_path = arg.substr(8)
		elif arg.begins_with("--tshot-time="):
			_shot_time = arg.substr(13).to_float()
		elif arg.begins_with("--set="):
			prop_set = arg.substr(6)
		elif arg.begins_with("--zoom="):
			_zoom_arg = arg.substr(7).to_float()
		elif arg.begins_with("--yaw="):
			yaw = deg_to_rad(arg.substr(6).to_float())
		elif arg.begins_with("--at="):
			var p := arg.substr(5).split(",")
			if p.size() == 2:
				focus = Vector3(p[0].to_float(), 0, p[1].to_float())
	_build_environment()
	_build()
	if _shot_path != "":
		await get_tree().create_timer(_shot_time).timeout
		get_viewport().get_texture().get_image().save_png(_shot_path)
		print("TerrainShowcase: saved ", _shot_path)
		get_tree().quit()


## Lighting matches scenes/main.tscn (the default run look), lightly tinted per realm.
func _build_environment() -> void:
	var holy := theme_name == "heaven"
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.45, 0.6, 0.82) if holy else Color(0.2, 0.26, 0.32)
	sky_mat.sky_horizon_color = Color(1.0, 0.9, 0.72) if holy else Color(0.62, 0.52, 0.38)
	sky_mat.ground_horizon_color = Color(0.36, 0.31, 0.25)
	sky_mat.ground_bottom_color = Color(0.06, 0.06, 0.055)
	sky_mat.sky_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.76, 0.66) if holy else Color(0.4, 0.5, 0.62)
	env.ambient_light_energy = 0.75 if holy else 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.1 if holy else 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.65
	env.glow_bloom = 0.04
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 0.95
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.8
	env.fog_enabled = view != "overview"
	env.fog_light_color = Color(0.95, 0.9, 0.78) if holy else Color(0.36, 0.42, 0.48)
	env.fog_density = 0.008
	env.fog_sun_scatter = 0.35
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.541, -2.142, 0)
	sun.light_color = Color(1.0, 0.92, 0.76) if holy else Color(1.0, 0.83, 0.62)
	sun.light_energy = 2.7 if holy else 2.3
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.4
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)
	cam = Camera3D.new()
	cam.fov = 35.0
	cam.far = 300.0
	add_child(cam)
	cam.current = true


func _build() -> void:
	if patch:
		patch.free()
		patch = null
	for c in get_children():
		if c.name == "PropGrid":
			c.free()
	var theme := load("res://data/terrain/%s.tres" % theme_name) as TerrainTheme
	if view == "props":
		_build_prop_grid(theme)
	else:
		patch = TerrainPatch.new()
		patch.theme = theme
		patch.rng_seed = seed_value
		patch.build_on_ready = false
		if theme.edge == TerrainTheme.Edge.DROP_DOWN:
			# same proportions as the Gilded Isles map: room for satellite islands
			patch.size = Vector2(156, 156)
			patch.arena_radius = 40.0
		add_child(patch)
		patch.build()
		print("TerrainShowcase %s seed=%d %s" % [theme_name, seed_value, str(patch.stats())])
	if _zoom_arg > 0.0:
		zoom = _zoom_arg
	if view == "overview":
		PropKit.clear_visibility_ranges(self)
	_place_camera()


func _build_prop_grid(theme: TerrainTheme) -> void:
	var root := Node3D.new()
	root.name = "PropGrid"
	add_child(root)
	var holy := theme.edge == TerrainTheme.Edge.DROP_DOWN or theme_name == "heaven"
	var names: Array[StringName] = PropKit.HOLY if holy else PropKit.HELL
	match prop_set:
		"holy": names = PropKit.HOLY
		"hell": names = PropKit.HELL
		"site": names = SiteProps.NAMES
	# a flat terrain floor under the grid
	patch = TerrainPatch.new()
	patch.theme = theme
	patch.size = Vector2(80, 80)
	patch.auto_features = false
	patch.scatter_props = false
	patch.add_open_rect(Rect2(-38, -38, 76, 76))
	patch.rng_seed = 3
	patch.build_on_ready = false
	add_child(patch)
	patch.build()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var cols := 3 if names.size() <= 9 else 5
	for i in names.size():
		var x := (float(i % cols) - float(cols - 1) * 0.5) * 8.5
		@warning_ignore("integer_division")
		var z := float(i / cols) * 8.0 - 8.0
		var n := PropKit.build(names[i], rng)
		n.position = Vector3(x, 0, z)
		n.rotation.y = 0.4
		root.add_child(n)
		var label := Label3D.new()
		label.text = String(names[i])
		label.position = Vector3(x, 0.1, z + 3.0)
		label.rotation.x = -PI * 0.5
		label.font_size = 64
		label.pixel_size = 0.01
		root.add_child(label)
	if focus == Vector3.ZERO:
		focus = Vector3(0, 0, 4.0)
	zoom = 1.45


func _place_camera() -> void:
	if view == "overview":
		var s := patch.size.x if patch else 100.0
		cam.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-70), 0, 0)), focus + Vector3(0, s * 1.15, s * 0.42))
		return
	var off := GAME_CAM_OFFSET * zoom
	off = off.rotated(Vector3.UP, yaw)
	cam.global_position = focus + off
	cam.look_at(focus + Vector3(0, 0.5, 0))


func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.z -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.z += 1
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_physical_key_pressed(KEY_Q):
		yaw += delta
	if Input.is_physical_key_pressed(KEY_E):
		yaw -= delta
	if dir != Vector3.ZERO:
		focus += dir.normalized().rotated(Vector3.UP, yaw) * delta * 16.0 * zoom
	_place_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = maxf(zoom * 0.9, 0.3)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = minf(zoom * 1.1, 5.0)
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		seed_value = randi() % 100000
		_build()
