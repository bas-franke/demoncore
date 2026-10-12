extends Node3D
## Run-time map loader (node Main/Map in scenes/main.tscn; it must sit BEFORE Atmosphere, Player,
## and EnemySpawner so it can configure them before their _ready runs).
##
## Reads the selected definition from the Maps autoload and:
##   1. tints the WorldEnvironment / Sun / ground shader from "env" and "ground" (duplicated first, so
##      the scene's shared resources are never modified)
##   2. instantiates the map ("scene" .tscn or "generator" script, both GameMap) and builds it
##      (no scene/generator = the open, endless sanctum: an unbounded GameMap + the stock Decor)
##   3. removes Main/Decor unless "decor" is "sanctum"
##   4. places the player at the map's spawn, configures EnemySpawner from "enemy_pool" / "elite" /
##      "boss" / "spawner", Atmosphere from "atmosphere" (weather: the Atmosphere autoload)
##   5. starts the map's music (when Sfx knows the track) and shows the map title card
##   6. registers the map with Maps (Maps.map_loaded fires)

const TITLE_TIME := 4.0
## The Maps autoload script, for its static helpers (calling them through the autoload instance
## triggers the "static called on instance" warning).
const MapsScript := preload("res://autoload/maps.gd")

var map: GameMap
var def: Dictionary


func _ready() -> void:
	def = Maps.selected_def()
	if def.is_empty():
		push_warning("MapLoader: no map definitions found in %s" % Maps.MAP_DIR)
		def = Maps.DEFAULTS.duplicate(true)
		def["id"] = "open"
	var main := get_parent()
	_apply_env(main)
	_apply_ground(main)
	map = _instantiate()
	map.name = "Map_%s" % def["id"]
	add_child(map)
	map.build(def)
	if String(def.get("decor", "none")) != "sanctum":
		var decor := main.get_node_or_null(^"Decor")
		if decor:
			decor.queue_free()
	var particles := String((def.get("weather", {}) as Dictionary).get("particles", ""))
	if particles != "":
		map.ambient_particles(StringName(particles), int((def["weather"] as Dictionary).get("particle_amount", 500)))
	_place_player(main)
	_configure_spawner(main)
	_configure_props(main.get_node_or_null(^"Atmosphere"), def.get("atmosphere", {}))
	# Lighting presets: the Atmosphere autoload (docs/team/visuals.md) listens to Maps.map_loaded and
	# applies def["atmosphere_preset"]; the "env" block above is only the fallback look.
	_start_music.call_deferred()
	map.landmark_discovered.connect(_on_landmark_discovered)
	Maps._register(map, def)
	_show_title()
	if "--map-overview" in OS.get_cmdline_user_args():
		_overview_camera.call_deferred()


## Dev: --map-overview swaps to a high orthographic camera framing the whole map (for screenshots).
func _overview_camera() -> void:
	var r := map.bounds_rect() if map.bounds_kind != GameMap.Bounds.NONE else Rect2(-50, -50, 100, 100)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(r.size.x, r.size.y) * 1.08
	cam.far = 400.0
	add_child(cam)
	var c := r.get_center()
	# steep 70-degree view so walls still read as walls
	cam.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-70.0), 0.0, 0.0)),
			Vector3(c.x, 120.0 * sin(deg_to_rad(70.0)), c.y + 120.0 * cos(deg_to_rad(70.0))))
	cam.make_current()
	# Its own clean Environment: a Camera3D environment overrides the WorldEnvironment entirely, so the
	# Atmosphere director's fog / volumetrics / glow (re-applied every frame) can't wash the shot out.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.08, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.78)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	cam.environment = env
	cam.attributes = null
	_hide_post_layers.call_deferred()
	for g in get_tree().get_nodes_in_group(&"ground"):
		(g as Node3D).scale = Vector3(3.0, 1.0, 3.0)  # cover the whole map, not just around the player


func _instantiate() -> GameMap:
	var scene_path := String(def.get("scene", ""))
	var gen_path := String(def.get("generator", ""))
	if scene_path != "" and ResourceLoader.exists(scene_path):
		var inst := (load(scene_path) as PackedScene).instantiate()
		if inst is GameMap:
			return inst
		push_warning("MapLoader: %s root is not a GameMap" % scene_path)
		inst.free()
	elif gen_path != "" and ResourceLoader.exists(gen_path):
		var obj: Object = (load(gen_path) as Script).new()
		if obj is GameMap:
			return obj
		push_warning("MapLoader: %s does not extend GameMap" % gen_path)
		if not obj is RefCounted:
			obj.free()
	elif scene_path != "" or gen_path != "":
		push_warning("MapLoader: missing map scene/generator for %s" % def["id"])
	var open := GameMap.new()
	open.bounds_kind = GameMap.Bounds.NONE
	return open


# ================================================================ environment

func _apply_env(main: Node) -> void:
	var env_def: Dictionary = def.get("env", {})
	if env_def.is_empty():
		return
	var we := main.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if we and we.environment:
		var env := we.environment.duplicate(true) as Environment
		we.environment = env
		var sky: ProceduralSkyMaterial = null
		if env.sky:
			sky = env.sky.sky_material as ProceduralSkyMaterial
		for k: String in env_def:
			var v: Variant = env_def[k]
			match k:
				"sky_top":
					if sky: sky.sky_top_color = MapsScript.color_of(v)
				"sky_horizon":
					if sky: sky.sky_horizon_color = MapsScript.color_of(v)
				"ground_horizon":
					if sky: sky.ground_horizon_color = MapsScript.color_of(v)
				"ground_bottom":
					if sky: sky.ground_bottom_color = MapsScript.color_of(v)
				"background":
					env.background_color = MapsScript.color_of(v)
				"ambient":
					env.ambient_light_color = MapsScript.color_of(v)
				"ambient_energy":
					env.ambient_light_energy = float(v)
				"fog_color":
					env.fog_light_color = MapsScript.color_of(v)
				"fog_density":
					env.fog_density = float(v)
				"fog_sun_scatter":
					env.fog_sun_scatter = float(v)
				"fog_height_density":
					env.fog_height_density = float(v)
				"exposure":
					env.tonemap_exposure = float(v)
				"glow_intensity":
					env.glow_intensity = float(v)
				"vol_fog_albedo":
					env.volumetric_fog_albedo = MapsScript.color_of(v)
				"vol_fog_emission":
					env.volumetric_fog_emission = MapsScript.color_of(v)
	var sun := main.get_node_or_null(^"Sun") as DirectionalLight3D
	if sun:
		if env_def.has("sun_color"):
			sun.light_color = MapsScript.color_of(env_def["sun_color"])
		if env_def.has("sun_energy"):
			sun.light_energy = float(env_def["sun_energy"])
		if env_def.has("sun_pitch") or env_def.has("sun_yaw"):
			sun.rotation = Vector3(deg_to_rad(float(env_def.get("sun_pitch", rad_to_deg(sun.rotation.x)))),
					deg_to_rad(float(env_def.get("sun_yaw", rad_to_deg(sun.rotation.y)))), 0.0)


## "ground": {uniform_name: [r,g,b] | number} -> the ground shader (see scenes/world/ground.gdshader).
func _apply_ground(main: Node) -> void:
	var g: Dictionary = def.get("ground", {})
	if g.is_empty():
		return
	var ground := main.get_node_or_null(^"Ground") as MeshInstance3D
	if ground == null or ground.mesh == null:
		return
	var m := ground.get_active_material(0) as ShaderMaterial
	if m == null:
		return
	m = m.duplicate() as ShaderMaterial
	ground.material_override = m
	for k: String in g:
		var v: Variant = g[k]
		if v is Array:
			var c := MapsScript.color_of(v)
			m.set_shader_parameter(k, Vector3(c.r, c.g, c.b))
		else:
			m.set_shader_parameter(k, v)


# ================================================================ run wiring

func _place_player(main: Node) -> void:
	var p := main.get_node_or_null(^"Player") as Node3D
	var at := map.get_player_spawn()
	if p:
		p.global_position = at
		p.reset_physics_interpolation()
	_snap_camera.call_deferred(at)


func _snap_camera(at: Vector3) -> void:
	var rig := get_tree().get_first_node_in_group(&"camera_rig") as Node3D
	if rig:
		rig.global_position = Vector3(at.x, 0.0, at.z)


func _configure_spawner(main: Node) -> void:
	var sp := main.get_node_or_null(^"EnemySpawner") as EnemySpawner
	if sp == null:
		return
	var pool: Array = def.get("enemy_pool", [])
	if not pool.is_empty():
		var rules: Array[SpawnRule] = []
		for e: Dictionary in pool:
			var data := Maps.load_enemy(String(e.get("enemy", ""))) as EnemyData
			if data == null:
				continue
			var r := SpawnRule.new()
			r.enemy = data
			r.start_time = float(e.get("start", 0.0))
			r.end_time = float(e.get("end", -1.0))
			r.weight = float(e.get("weight", 1.0))
			rules.append(r)
		if not rules.is_empty():
			sp.rules = rules
	var elite := Maps.load_enemy(String(def.get("elite", ""))) as EnemyData
	if elite:
		sp.elite = elite
	var boss := Maps.load_boss(String(def.get("boss", ""))) as EnemyData
	if boss:
		sp.boss = boss
	_configure_props(sp, def.get("spawner", {}))


## Copies {property: value} onto `target` for every property it actually has.
func _configure_props(target: Object, values: Dictionary) -> void:
	if target == null:
		return
	for k: String in values:
		if not k in target:
			push_warning("MapLoader: %s has no property %s" % [target, k])
			continue
		var cur: Variant = target.get(k)
		var v: Variant = values[k]
		if cur is Vector2 and v is Array:
			v = Vector2(float(v[0]), float(v[1]))
		elif cur is Vector3 and v is Array:
			v = Vector3(float(v[0]), float(v[1]), float(v[2]))
		elif cur is Color:
			v = MapsScript.color_of(v)
		elif cur is int:
			v = int(v)
		target.set(k, v)


## Known Sfx tracks: Sfx.has_track() if the audio worker adds it, else the two stock tracks.
func _music_known(track: StringName) -> bool:
	if Sfx.has_method(&"has_track"):
		return Sfx.call(&"has_track", track)
	return track in [&"backyard", &"menu"]


func _start_music() -> void:
	if get_node_or_null(^"/root/MusicManager"):
		return  # MusicManager picks the map's "music" / "music_fallback" itself (docs/team/music.md)
	var track := StringName(def.get("music", ""))
	if track == &"" or not _music_known(track):
		track = StringName(def.get("music_fallback", "backyard"))
	if track != &"" and _music_known(track):
		Sfx.play_music(track)


# ================================================================ presentation

func _show_title() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var layer := CanvasLayer.new()
	layer.layer = 4
	layer.name = "MapTitle"
	add_child(layer)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	box.position.y += 110.0
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(box)
	var title := Label.new()
	title.text = String(def.get("name", "")).to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override(&"font_size", 42)
	title.add_theme_color_override(&"font_color", Color(1.0, 0.86, 0.62))
	title.add_theme_color_override(&"font_outline_color", Color(0.08, 0.02, 0.02))
	title.add_theme_constant_override(&"outline_size", 10)
	box.add_child(title)
	var sub := Label.new()
	sub.text = String(def.get("subtitle", ""))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override(&"font_size", 20)
	sub.add_theme_color_override(&"font_color", Maps.portal_color(StringName(def["id"])).lightened(0.35))
	sub.add_theme_color_override(&"font_outline_color", Color(0.05, 0.01, 0.01))
	sub.add_theme_constant_override(&"outline_size", 6)
	box.add_child(sub)
	box.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(box, ^"modulate:a", 1.0, 0.8).set_delay(0.4)
	tw.tween_interval(TITLE_TIME - 1.8)
	tw.tween_property(box, ^"modulate:a", 0.0, 1.0)
	tw.tween_callback(layer.queue_free)


func _on_landmark_discovered(_id: StringName, display_name: String, _marker: Node3D) -> void:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	var l := Label.new()
	l.text = display_name
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	l.position.y -= 120.0
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override(&"font_size", 22)
	l.add_theme_color_override(&"font_color", Color(0.95, 0.85, 0.65))
	l.add_theme_color_override(&"font_outline_color", Color(0.05, 0.01, 0.01))
	l.add_theme_constant_override(&"outline_size", 6)
	layer.add_child(l)
	l.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(l, ^"modulate:a", 1.0, 0.5)
	tw.tween_interval(2.2)
	tw.tween_property(l, ^"modulate:a", 0.0, 0.8)
	tw.tween_callback(layer.queue_free)


## --map-overview: hides full-screen post passes (CanvasLayers below the UI: grade, vignette,
## gloom) and keeps doing so, since the Atmosphere rig may build them after the map.
func _hide_post_layers() -> void:
	for i in 10:
		for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
			var cl := n as CanvasLayer
			if cl.layer <= 0:
				cl.visible = false
		await get_tree().create_timer(0.5).timeout
