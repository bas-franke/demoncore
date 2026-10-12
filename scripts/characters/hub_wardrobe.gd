class_name HubWardrobe
extends Node3D
## Basecamp Hell wardrobe (characters-polish): "the Vanity of the Fallen", an obsidian standing
## mirror with a dais where the chosen demon's likeness stands in the skin it wears. Interact ->
## a window with a turning preview of the demon and the SkinPicker; unlocked skins are saved
## (DemonSkins.select) and the hub avatar changes into them when the window closes.
##
##   HubWardrobe.install(basecamp)     # one line in Basecamp._ready (after the avatar exists)
##   HubWardrobe.open_now              # true while the window owns the input (Basecamp._menu_open)
## Dev arg: --hub-wardrobe opens the window at once.
##
## Everything is built in code (Art kit + DemonModel + SkinPicker).

## Where it stands in the hub (between the bonfire and the summoning circle) and which way the
## mirror faces (toward the plaza).
const SPOT := Vector3(5.4, 0.0, 3.2)
const YAW := -2.2
const DEFAULT_DEMON := "res://data/demons/vharok.tres"

## True while the wardrobe window is open.
static var open_now := false

var _basecamp: Node
var _likeness: DemonModel
var _demon: DemonData
var _ui: CanvasLayer
var _preview: DemonModel
var _turn: Node3D
var _picker: SkinPicker
var _title: Label
var _spin := 0.0


## Adds the wardrobe to `basecamp` (a Basecamp node: needs `avatar` and add_interactable()).
static func install(basecamp: Node) -> HubWardrobe:
	var w := HubWardrobe.new()
	w.name = "Wardrobe"
	w._basecamp = basecamp
	w.position = SPOT
	w.rotation.y = YAW
	basecamp.add_child(w)
	return w


func _ready() -> void:
	open_now = false
	_demon = Game.selected_character as DemonData
	if _demon == null:
		_demon = load(DEFAULT_DEMON) as DemonData
	_build_prop()
	var it := HubInteractable.new()
	it.verb = "Change skin"
	it.label = "Vanity of the Fallen"
	it.radius = 2.2
	it.prompt_height = 3.0
	it.highlight = _likeness
	if _basecamp and _basecamp.has_method(&"add_interactable"):
		_basecamp.call(&"add_interactable", it)
		it.global_transform = global_transform
	else:
		add_child(it)
	it.interacted.connect(open)
	# Dev: -- --hub-wardrobe opens the window right away (screenshots).
	if OS.get_cmdline_user_args().has("--hub-wardrobe"):
		get_tree().create_timer(0.8).timeout.connect(open)


func _exit_tree() -> void:
	open_now = false


func _process(delta: float) -> void:
	if _likeness:
		_likeness.animate(delta, 0.0)
	if _preview and _ui and _ui.visible:
		_spin += delta * 0.6
		_turn.rotation.y = _spin
		_preview.animate(delta, 0.0)


# ---------------------------------------------------------------- window

func open() -> void:
	if open_now:
		return
	if _ui == null:
		_build_ui()
	open_now = true
	_freeze(true)
	_ui.visible = true
	_preview.build(_demon)
	_preview.play_cheer()
	_picker.show_for(_preview)
	_title.text = "%s, %s" % [_demon.display_name, _demon.title] if _demon.title != "" else _demon.display_name
	Sfx.play(&"ui_click")


func close() -> void:
	if not open_now:
		return
	open_now = false
	_ui.visible = false
	_freeze(false)
	Sfx.play(&"ui_back")
	# Wear the saved choice (a locked skin was only previewed).
	var saved := DemonSkins.selected_id(DemonSkins.demon_id_of(_demon))
	if _likeness and _likeness.skin_id != saved:
		_likeness.set_skin(saved)
	var avatar: Variant = _basecamp.get(&"avatar") if _basecamp else null
	if avatar is HubAvatar and (avatar as HubAvatar).model and (avatar as HubAvatar).model.skin_id != saved:
		(avatar as HubAvatar).model.set_skin(saved)


func _freeze(on: bool) -> void:
	var avatar: Variant = _basecamp.get(&"avatar") if _basecamp else null
	if avatar is HubAvatar:
		(avatar as HubAvatar).frozen = on
		if on:
			(avatar as HubAvatar).face(global_position)


func _unhandled_input(event: InputEvent) -> void:
	if not open_now:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause") \
			or event.is_action_pressed(&"interact"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left"):
		_picker.step(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_right"):
		_picker.step(1)
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 20
	_ui.visible = false
	add_child(_ui)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.0, 0.0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(860.0, 540.0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 22)
	margin.add_child(row)

	# Left: the turning likeness (its own little world in a SubViewport).
	var svc := SubViewportContainer.new()
	svc.custom_minimum_size = Vector2(380.0, 490.0)
	svc.stretch = true
	row.add_child(svc)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.transparent_bg = false
	sv.msaa_3d = Viewport.MSAA_2X
	svc.add_child(sv)
	_build_preview_world(sv)

	# Right: name, picker, how-to.
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 8)
	row.add_child(col)
	var head := Label.new()
	head.theme_type_variation = &"TitleLabel"
	head.text = "Vanity of the Fallen"
	head.add_theme_font_size_override(&"font_size", 32)
	head.add_theme_color_override(&"font_color", UIPalette.BRIMSTONE)
	col.add_child(head)
	_title = _label("", 18, UIPalette.ASH_TEXT)
	col.add_child(_title)
	var lore := _label("The obsidian shows you as you wish Heaven to remember you.", 15, UIPalette.SMOKE)
	lore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(lore)
	col.add_child(HSeparator.new())
	_picker = SkinPicker.new()
	_picker.keyboard = true
	col.add_child(_picker)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(gap)
	var done := Button.new()
	done.text = "Done"
	done.theme_type_variation = &"AccentButton"
	done.custom_minimum_size = Vector2(200.0, 46.0)
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	done.focus_mode = Control.FOCUS_NONE
	done.pressed.connect(close)
	col.add_child(done)
	var foot := _label("A / D or W / S  skin        E / Esc  close", 14, UIPalette.SMOKE)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(foot)


func _build_preview_world(sv: SubViewport) -> void:
	var root := Node3D.new()
	sv.add_child(root)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.05, 0.025, 0.025)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.42, 0.42)
	env.environment.ambient_light_energy = 0.55
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment.glow_enabled = true
	root.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35.0, -30.0, 0.0)
	key.light_energy = 1.2
	key.shadow_enabled = true
	root.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20.0, 150.0, 0.0)
	rim.light_color = Color(1.0, 0.45, 0.2)
	rim.light_energy = 1.4
	root.add_child(rim)
	Art.part(root, Art.cylinder(0.5, 0.56), Art.mat(Art.OBSIDIAN, 0.35, 0.3, 0.1), Vector3(0.0, -0.08, 0.0),
		Vector3(2.4, 0.16, 2.4))
	_turn = Art.pivot(root)
	_preview = DemonModel.new()
	_turn.add_child(_preview)
	var cam := Camera3D.new()
	cam.fov = 32.0
	cam.position = Vector3(0.0, 1.7, 7.4)
	root.add_child(cam)
	cam.look_at(Vector3(0.0, 1.3, 0.0))
	cam.current = true


# ---------------------------------------------------------------- the prop

func _build_prop() -> void:
	var iron := Art.mat(Art.OBSIDIAN.lightened(0.05), 0.4, 0.8, 0.3, false, 0.0, &"metal")
	var stone := Art.mat(Color(0.16, 0.12, 0.11), 0.85, 0.0, 0.5)
	var glass := Art.mat(Color(0.03, 0.02, 0.03), 0.06, 0.9, 0.0, false)
	var ember := Art.emissive(Color(0.4, 0.08, 0.02), Art.EMBER, 3.0)
	# Dais for the likeness.
	Art.part(self, Art.cylinder(0.5, 0.58), stone, Vector3(0.0, 0.09, 0.0), Vector3(1.9, 0.18, 1.9))
	Art.part(self, Art.torus(0.9, 1.0), ember, Vector3(0.0, 0.185, 0.0), Vector3(0.88, 0.4, 0.88))
	# Standing mirror behind the dais: tall obsidian pane in a spiked iron frame.
	var m := Art.pivot(self, Vector3(0.0, 0.0, -1.25))
	Art.part(m, Art.box(), glass, Vector3(0.0, 1.55, 0.0), Vector3(1.25, 2.5, 0.06))
	for s: float in [-1.0, 1.0]:
		Art.part(m, Art.box(), iron, Vector3(s * 0.68, 1.5, 0.0), Vector3(0.12, 2.9, 0.14))
		Art.part(m, Art.cone(0.5), iron, Vector3(s * 0.68, 3.1, 0.0), Vector3(0.14, 0.4, 0.14))
		Art.part(m, Art.box(), ember, Vector3(s * 0.68, 1.5, 0.075), Vector3(0.025, 2.2, 0.01))
	Art.part(m, Art.box(), iron, Vector3(0.0, 2.85, 0.0), Vector3(1.5, 0.14, 0.16))
	Art.part(m, Art.box(), iron, Vector3(0.0, 0.25, 0.0), Vector3(1.5, 0.14, 0.18))
	Art.part(m, Art.cone(0.5), iron, Vector3(0.0, 3.15, 0.0), Vector3(0.2, 0.55, 0.2))
	Art.light(m, Art.EMBER, 0.8, 3.0, Vector3(0.0, 1.6, 0.6))
	# The likeness: the chosen demon in the skin it wears.
	_likeness = DemonModel.new()
	_likeness.position = Vector3(0.0, 0.18, 0.0)
	_likeness.rotation.y = PI  # faces away from the mirror, toward the plaza
	add_child(_likeness)
	_likeness.build(_demon)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"InkLabel"
	l.text = text
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	return l
