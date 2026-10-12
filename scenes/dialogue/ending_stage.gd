extends Node3D
## The ending, staged in the world (story role): the stairs past the Seventh Gate, seven Archons
## kneeling along them, and the empty Throne at the top. The chosen demon climbs while the
## "ending" conversation plays (unpaused, so the camera and the Atmosphere blends keep moving).
## Lines with {"event": "stage_*"} drive the staging:
##   stage_climb     camera follows the demon up the stairs
##   stage_archons   slow pan across the kneeling Archons
##   stage_throne    rise to reveal the Throne; the demon stops before it
##   stage_sit       the demon sits; shadows lengthen (blood_moon preset, crimson flash)
##   stage_break     the demon breaks the Throne apart (ash storm, lightning, white flash)
##   stage_after     the camera pulls back and up over everything
## When the conversation ends the screen fades and Basecamp Hell loads (StoryHooks then plays the
## "ending_return" reactions and shows the Crown). Built in code; scene: ending_stage.tscn.
## Dev: godot --path . res://scenes/dialogue/ending_stage.tscn -- --story --story-save=user://x.json
##        [--auto-advance=1.6] [--pick=1]   (confirm every N s; which choice to take, 0 = sit)

const BASECAMP_SCENE := "res://scenes/basecamp/basecamp.tscn"
const STEP_RISE := 0.4
const STEP_RUN := 1.2
const STEPS := 30
const STAIR_WIDTH := 7.0
const TOP_Y := STEP_RISE * STEPS
const TOP_Z := -STEP_RUN * STEPS
const THRONE := Vector3(0.0, TOP_Y, TOP_Z - 7.0)
## Where the demon stops, a few steps before the Throne.
const HALT_Z := TOP_Z - 3.2
const WALK_SPEED := 2.3
const STONE := Color(0.86, 0.83, 0.76)
const MARBLE := Color(0.93, 0.91, 0.86)
const ARCHON_STEPS: Array[int] = [5, 9, 13, 17, 21, 25, 28]
## Gap between the stair edge and an Archon's plinth centre.
const ARCHON_OFFSET := 1.1

var _camera: Camera3D
var _demon: DemonModel
var _demon_z := 2.0
var _walking := false
var _cam_follow := true
var _throne: Node3D
var _throne_parts: Array[Node3D] = []
var _halo: MeshInstance3D
var _halo_mat: StandardMaterial3D
var _throne_light: OmniLight3D
var _fade: ColorRect
var _cam_tween: Tween


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # the camera moves in _process
	set_meta(&"atmosphere_preset", "heavens_gate")
	_build_world()
	_build_stairs()
	_build_archons()
	_build_throne()
	_build_demon()
	_build_camera()
	_build_fade()
	Sfx.play_music(&"menu")
	Dialogue.event_triggered.connect(_on_event)
	_fade_in()
	await get_tree().create_timer(1.6).timeout
	_walking = true
	_dev_auto_advance()
	if not Dialogue.start("ending", false):
		push_warning("EndingStage: no 'ending' conversation")
		_finish()
		return
	await Dialogue.conversation_finished
	_finish()


func _process(delta: float) -> void:
	if _walking:
		_demon_z = maxf(_demon_z - WALK_SPEED * delta, HALT_Z)
		if _demon_z <= HALT_Z:
			_walking = false
	if _demon and not _demon.has_meta(&"seated"):
		_demon.position = Vector3(0.0, _stair_height(_demon_z), _demon_z)
		_demon.ground_speed = WALK_SPEED if _walking else 0.0
		_demon.animate(delta, 1.0 if _walking else 0.0)
	elif _demon:
		_demon.animate(delta, 0.0)
	if _cam_follow and _camera:
		var target := _demon.position + Vector3(0.0, 4.2, 7.5)
		_camera.position = _camera.position.lerp(target, 1.0 - exp(-2.0 * delta))
		_camera.look_at(_demon.position + Vector3(0.0, 1.4, -4.0))
	if _halo:
		_halo.rotation.z += delta * 0.1


## Height of the stair surface at depth `z` (0 at the bottom step, TOP_Y on the platform).
func _stair_height(z: float) -> float:
	if z >= 0.0:
		return 0.0
	return minf(floorf(-z / STEP_RUN) + 1.0, STEPS) * STEP_RISE if z > TOP_Z else TOP_Y


# ---------------------------------------------------------------- staging cues

func _on_event(event_name: String, _conv_id: String) -> void:
	match event_name:
		"stage_climb":
			_cam_follow = true
		"stage_archons":
			_cam_follow = false
			var z := _demon_z
			_move_camera(Vector3(-6.5, _stair_height(z - 6.0) + 2.2, z - 3.0),
					Vector3(6.0, _stair_height(z - 10.0) + 1.0, z - 12.0), 6.0)
		"stage_throne":
			_walking = false
			_demon_z = HALT_Z
			_move_camera(Vector3(2.5, TOP_Y + 1.4, HALT_Z + 6.5), THRONE + Vector3(0.0, 2.2, 0.0), 4.5)
			_throne_light.light_energy = 0.0
			create_tween().tween_property(_throne_light, "light_energy", 3.0, 3.0)
		"stage_sit":
			_sit()
		"stage_break":
			_break_throne()
		"stage_after":
			_move_camera(THRONE + Vector3(0.0, 18.0, 30.0), Vector3(0.0, TOP_Y * 0.5, TOP_Z * 0.5), 9.0)


func _move_camera(to: Vector3, look: Vector3, time: float) -> void:
	_cam_follow = false
	if _cam_tween:
		_cam_tween.kill()
	var from_pos := _camera.position
	var from_look := _camera.global_position + -_camera.global_transform.basis.z * 10.0
	_cam_tween = create_tween()
	_cam_tween.tween_method(func(t: float) -> void:
		var e := smoothstep(0.0, 1.0, t)
		_camera.position = from_pos.lerp(to, e)
		_camera.look_at(from_look.lerp(look, e)), 0.0, 1.0, time)


func _sit() -> void:
	_demon.set_meta(&"seated", true)
	var tw := create_tween()
	tw.tween_property(_demon, "position", THRONE + Vector3(0.0, 0.55, 0.0), 1.8) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(_demon, "rotation:y", PI, 1.4)
	_move_camera(THRONE + Vector3(0.0, 1.0, 7.5), THRONE + Vector3(0.0, 2.0, 0.0), 5.0)
	var atmo := get_node_or_null(^"/root/Atmosphere")
	if atmo:
		atmo.call(&"flash", Color(0.8, 0.05, 0.02), 0.5, 1.5)
		atmo.call(&"apply_preset", "blood_moon", 6.0)
	Sfx.play(&"boss_roar", 0.0, -4.0)
	create_tween().tween_property(_halo_mat, "albedo_color", Color(1.4, 0.2, 0.06, 0.7), 4.0)
	create_tween().tween_property(_throne_light, "light_color", Color(1.0, 0.25, 0.1), 4.0)


func _break_throne() -> void:
	_demon.play_attack()
	Sfx.play(&"impact", 0.0, 2.0)
	Sfx.play(&"boss_death", 0.0, -2.0)
	var atmo := get_node_or_null(^"/root/Atmosphere")
	if atmo:
		atmo.call(&"flash", Color(1.0, 0.95, 0.85), 0.7, 2.0)
		atmo.call(&"strike_lightning", THRONE, 0.0)
		atmo.call(&"apply_preset", "sanctum_ash_storm", 5.0)
	# Each piece flies off on its own arc and tumbles.
	for p in _throne_parts:
		var dir := Vector3(randf_range(-1.0, 1.0), randf_range(0.3, 1.2), randf_range(-1.0, 0.4)).normalized()
		var tw := create_tween().set_parallel()
		tw.tween_property(p, "position", p.position + dir * randf_range(4.0, 9.0), 2.2) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(p, "rotation", Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-3, 3)), 2.2)
		tw.tween_property(p, "scale", Vector3.ONE * 0.6, 2.2)
	create_tween().tween_property(_halo, "scale", Vector3.ONE * 4.0, 1.5)
	create_tween().tween_property(_halo_mat, "albedo_color:a", 0.0, 1.5)
	_move_camera(THRONE + Vector3(4.0, 3.0, 9.0), THRONE + Vector3(0.0, 1.5, 0.0), 3.0)


func _finish() -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 2.5)
	await tw.finished
	Dialogue.hooks.finish_ending()
	var meta := get_node_or_null(^"/root/Meta")
	if meta and meta.has_method(&"go_to_basecamp"):
		meta.call(&"go_to_basecamp")
	else:
		get_tree().change_scene_to_file(BASECAMP_SCENE)


# ---------------------------------------------------------------- building

func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.95, 0.9, 0.78)
	sky_mat.sky_horizon_color = Color(1.0, 0.97, 0.9)
	sky_mat.ground_bottom_color = Color(0.9, 0.86, 0.78)
	sky_mat.ground_horizon_color = Color(1.0, 0.97, 0.9)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.fog_enabled = true
	env.fog_light_color = Color(1.0, 0.96, 0.88)
	env.fog_density = 0.012
	env.glow_enabled = true
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)
	# A sea of pale cloud-floor under the stairs.
	Art.part(self, Art.cylinder(0.5, 0.5), Art.mat(MARBLE, 0.9, 0.0, 0.05, false, 0.0, &"stone"),
			Vector3(0.0, -0.6, -20.0), Vector3(160.0, 1.0, 160.0))


func _build_stairs() -> void:
	var stone := Art.mat(STONE, 0.6, 0.0, 0.15, false, 0.0, &"stone")
	var gold := Art.mat(Art.GOLD, 0.35, 1.0, 0.2, false, 0.0, &"gold")
	for i in STEPS:
		var y := STEP_RISE * (i + 0.5)
		var z := -STEP_RUN * (i + 0.5)
		Art.part(self, Art.box(), stone, Vector3(0.0, y * 0.5 + STEP_RISE * 0.25, z),
				Vector3(STAIR_WIDTH, y + STEP_RISE * 0.5, STEP_RUN))
		Art.part(self, Art.box(), gold, Vector3(0.0, STEP_RISE * (i + 1) + 0.01, z + STEP_RUN * 0.45),
				Vector3(STAIR_WIDTH, 0.02, 0.06))
	# The platform at the top.
	Art.part(self, Art.box(), stone, Vector3(0.0, TOP_Y * 0.5, TOP_Z - 6.0), Vector3(18.0, TOP_Y, 12.0))
	# Pillars of light beside the stairs.
	for i in range(0, STEPS, 6):
		for s: float in [-1.0, 1.0]:
			var p := Vector3(s * (STAIR_WIDTH * 0.5 + 2.6), 0.0, -STEP_RUN * i)
			Art.part(self, Art.cylinder(0.35, 0.45), Art.mat(MARBLE, 0.5, 0.0, 0.1, false, 0.0, &"stone"),
					p + Vector3(0.0, 4.0 + STEP_RISE * i * 0.5, 0.0), Vector3(1.0, 8.0 + STEP_RISE * i, 1.0))
			Art.part(self, Art.cylinder(0.25, 0.25), Art.glow(Art.HOLY, 0.6, true, 0.25),
					p + Vector3(0.0, 30.0, 0.0), Vector3(1.0, 60.0, 1.0))


## Seven Archons kneel along the stairs, heads bowed, facing the climb.
func _build_archons() -> void:
	for k in ARCHON_STEPS.size():
		var step := ARCHON_STEPS[k]
		var side := -1.0 if k % 2 == 0 else 1.0
		var at := Vector3(side * (STAIR_WIDTH * 0.5 + ARCHON_OFFSET), STEP_RISE * (step + 1), -STEP_RUN * (step + 0.5))
		# A marble plinth from the cloud floor up to the step, so the Archon kneels on stone
		# beside the stair instead of floating in the air.
		var plinth := Art.mat(MARBLE, 0.55, 0.0, 0.12, false, 0.0, &"stone")
		Art.part(self, Art.box(), plinth, Vector3(at.x, (at.y - 0.6) * 0.5, at.z), Vector3(1.9, at.y + 0.6, 1.9))
		Art.part(self, Art.box(), Art.mat(Art.GOLD, 0.35, 1.0, 0.2, false, 0.0, &"gold"),
				Vector3(at.x, at.y - 0.04, at.z), Vector3(2.05, 0.08, 2.05))
		var holder := Art.pivot(self, at, Vector3(0.0, side * PI * 0.5, 0.0))
		var m: Node3D = null
		if ResourceLoader.exists("res://scenes/characters/enemies/archangel.tscn"):
			m = (load("res://scenes/characters/enemies/archangel.tscn") as PackedScene).instantiate() as Node3D
		if m:
			# Knelt (characters-new): the archangel's own kneeling pose (knee down, sword planted,
			# head bowed, wings folded) instead of tilting the whole model.
			m.set(&"kneeling", true)
			holder.add_child(m)
		else:
			Art.part(holder, Art.capsule(0.35, 1.4), Art.mat(MARBLE, 0.6), Vector3(0.0, 0.7, 0.0))


func _build_throne() -> void:
	_throne = Art.pivot(self, THRONE)
	var stone := Art.mat(Color(0.97, 0.95, 0.9), 0.55, 0.0, 0.25, false, 0.0, &"stone")
	var dust := Art.mat(Color(0.75, 0.72, 0.66), 0.95, 0.0, 0.6, false, 0.0, &"stone")
	var pieces := [
		[Vector3(0.0, 0.3, 0.0), Vector3(2.6, 0.6, 2.2), stone],  # dais
		[Vector3(0.0, 1.0, 0.0), Vector3(1.8, 0.8, 1.6), stone],  # seat block
		[Vector3(0.0, 3.0, -0.75), Vector3(1.9, 3.6, 0.35), stone],  # tall plain back
		[Vector3(-0.95, 1.65, 0.0), Vector3(0.3, 0.5, 1.6), stone],  # armrests
		[Vector3(0.95, 1.65, 0.0), Vector3(0.3, 0.5, 1.6), stone],
		[Vector3(-0.95, 1.92, 0.0), Vector3(0.32, 0.04, 1.62), dust],  # dust on the armrests
		[Vector3(0.95, 1.92, 0.0), Vector3(0.32, 0.04, 1.62), dust],
	]
	for p: Array in pieces:
		var piece := Art.pivot(_throne, p[0])
		Art.part(piece, Art.box(), p[2], Vector3.ZERO, p[1])
		_throne_parts.append(piece)
	_halo = Art.part(_throne, Art.torus(2.1, 2.3), Art.glow(Art.HOLY, 1.2, true, 0.7), Vector3(0.0, 4.4, -1.1),
			Vector3.ONE, Vector3(PI * 0.5, 0.0, 0.0))
	# Own copy of the (shared, cached) glow material so it can be recoloured.
	_halo_mat = (_halo.material_override as StandardMaterial3D).duplicate()
	_halo.material_override = _halo_mat
	_throne_light = Art.light(_throne, Color(1.0, 0.92, 0.75), 3.0, 14.0, Vector3(0.0, 4.0, 3.0))


func _build_demon() -> void:
	var demon := Game.selected_character as DemonData
	if demon == null:
		demon = load("res://data/demons/vharok.tres") as DemonData
	_demon = DemonModel.new()
	add_child(_demon)
	_demon.build(demon)
	_demon.rotation.y = 0.0  # faces -Z: up the stairs


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.fov = 50.0
	_camera.far = 400.0
	add_child(_camera)
	_camera.position = Vector3(0.0, 4.0, 12.0)
	_camera.look_at(Vector3(0.0, 2.0, -6.0))
	_camera.current = true


func _build_fade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 80
	_fade = ColorRect.new()
	_fade.color = Color(0.0, 0.0, 0.0, 1.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	add_child(layer)


func _fade_in() -> void:
	create_tween().tween_property(_fade, "color:a", 0.0, 2.5)


# ---------------------------------------------------------------- dev

## --auto-advance=<s>: presses confirm every <s> seconds (screenshots / QA); --pick=<i> picks a choice.
func _dev_auto_advance() -> void:
	var every := 0.0
	var pick := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--auto-advance="):
			every = a.substr(15).to_float()
		elif a.begins_with("--pick="):
			pick = a.substr(7).to_int()
	if every <= 0.0:
		return
	while is_inside_tree():
		await get_tree().create_timer(every, true).timeout
		var focus := get_viewport().gui_get_focus_owner()
		if focus is Button:
			var row := focus.get_parent()
			var target: Node = row.get_child(mini(pick, row.get_child_count() - 1))
			(target as Button).pressed.emit()
			continue
		var ev := InputEventAction.new()
		ev.action = &"ui_accept"
		ev.pressed = true
		Input.parse_input_event(ev)
