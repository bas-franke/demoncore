class_name CreditsScreen
extends CanvasLayer
## Credits (UI role): a slow upward scroll of every team role and what it made, over a dark
## veil. Opened from the title menu. Any of Esc / pause / ui_cancel / Return closes; up / down
## (keys, d-pad, stick) or the mouse wheel scroll by hand, which pauses the auto-scroll.
##
##   var c := CreditsScreen.new(); add_child(c); c.open()   # emits `closed`

signal closed

const SPEED := 38.0  # pixels per second
## [role, what they built]. Keep in sync with docs/team/*.md.
const ROLES := [
	["Core Gameplay", "the run, the dash, Ichor and the pacing of the Host"],
	["Abilities & Synergies", "forty ways to ruin an angel, and what happens when they meet"],
	["Progression & Upgrades", "relics, rarity, pacts of heat, Sin Shards and Hellstone"],
	["Basecamp Hell", "the hub, its shopkeepers, the hellgate and the Meta ledger"],
	["Objectives & Bosses", "shrines, reliquaries, sieges, Sariel and Ozias the Grand Inquisitor"],
	["Map Design", "the Ruined Sanctum and every road to the cathedral"],
	["Terrain & Environment", "cliffs, lava, cloud seas and the prop kit of two worlds"],
	["Visuals & Atmosphere", "light, fog, weather, lightning and the hellfire glow"],
	["Art Style", "the shared look, the shader library and the creeping corruption"],
	["Character Polish", "the demons' motion, skins and readable silhouettes"],
	["New Characters", "the new choirs of Heaven"],
	["Sound Effects", "every clang, hiss, toll and shattering halo"],
	["Music", "the score of the descent"],
	["Story & Dialogue", "the cast, the codex and every word spoken in the Pit"],
	["User Interface", "the infernal theme, the HUD, the menus and this scroll"],
	["Code Quality", "the architecture and the conventions everyone kept"],
	["QA & Integration", "the bugs that never reached you"],
]

var _root: Control
var _scroll: ScrollContainer
var _col: VBoxContainer
var _pos := 0.0
var _manual_t := 0.0
var _back: Button


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func open() -> void:
	visible = true
	_pos = 0.0
	_scroll.scroll_vertical = 0
	Sfx.play(&"ui_click")
	_back.grab_focus.call_deferred()
	_root.modulate.a = 0.0
	_root.create_tween().tween_property(_root, "modulate:a", 1.0, 0.6)


func close() -> void:
	if not visible:
		return
	visible = false
	Sfx.play(&"ui_back")
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and (
			(event as InputEventMouseButton).button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]):
		_pos += 60.0 if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_DOWN else -60.0
		_manual_t = 3.0
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_down", true) or event.is_action_pressed(&"ui_up", true):
		_pos += 90.0 if event.is_action_pressed(&"ui_down", true) else -90.0
		_manual_t = 3.0
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	if _manual_t > 0.0:
		_manual_t -= delta
	else:
		_pos += SPEED * delta
	var max_scroll := maxf(_col.size.y - _scroll.size.y, 0.0)
	if _pos > max_scroll + 120.0:
		_pos = 0.0  # loop
	_pos = clampf(_pos, 0.0, max_scroll + 120.0)
	_scroll.scroll_vertical = int(_pos)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = load("res://ui/theme.tres") as Theme
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.004, 0.003, 0.94)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_top = 40.0
	_scroll.offset_bottom = -90.0
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_root.add_child(_scroll)
	_col = VBoxContainer.new()
	_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_col.add_theme_constant_override(&"separation", 10)
	_scroll.add_child(_col)
	var top := Control.new()
	top.custom_minimum_size.y = 260.0
	_col.add_child(top)
	_col.add_child(_line("SINBOUND", &"TitleLabel", 72, UIPalette.BRIMSTONE))
	_col.add_child(_center(UIPalette.rule(520.0, UIPalette.EMBER)))
	_col.add_child(_line("made by a coven of seventeen", &"LoreLabel", 20, UIPalette.ASH_TEXT))
	var gap := Control.new()
	gap.custom_minimum_size.y = 50.0
	_col.add_child(gap)
	for r: Array in ROLES:
		_col.add_child(_line(String(r[0]).to_upper(), &"HeaderLabel", 24, UIPalette.BRIMSTONE))
		_col.add_child(_line(String(r[1]), &"LoreLabel", 18, UIPalette.BONE))
		var g := Control.new()
		g.custom_minimum_size.y = 22.0
		_col.add_child(g)
	_col.add_child(_center(UIPalette.rule(320.0, UIPalette.BLOOD)))
	_col.add_child(_line("Built in Godot. Every mesh, sound and note made from text.", &"LoreLabel", 18, UIPalette.ASH_TEXT))
	_col.add_child(_line("Heaven will not forget you.", &"HeaderLabel", 26, UIPalette.BLOOD_BRIGHT))
	var tail := Control.new()
	tail.custom_minimum_size.y = 400.0
	_col.add_child(tail)
	_back = Button.new()
	_back.text = "RETURN"
	_back.custom_minimum_size = Vector2(220, 46)
	_back.anchor_left = 0.5
	_back.anchor_right = 0.5
	_back.anchor_top = 1.0
	_back.anchor_bottom = 1.0
	_back.offset_left = -110.0
	_back.offset_right = 110.0
	_back.offset_top = -70.0
	_back.offset_bottom = -24.0
	_back.pressed.connect(close)
	Sfx.wire_button(_back, &"ui_back")
	_root.add_child(_back)


func _line(t: String, variation: StringName, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.add_theme_font_size_override(&"font_size", fs)
	l.add_theme_color_override(&"font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.text = t
	return l


func _center(c: Control) -> CenterContainer:
	var cc := CenterContainer.new()
	cc.add_child(c)
	return cc
