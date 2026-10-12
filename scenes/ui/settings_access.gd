class_name SettingsAccessPage
extends PanelContainer
## "Accessibility" page of the settings overlay (built in code by settings_menu.gd):
##   Text speed (Settings.text_speed, dialogue typing), Reduce flashes (Settings.reduce_flashes),
##   Screen shake intensity (Settings.screen_shake) and Interface scale (Settings.ui_scale, applied
##   on release so the page doesn't rescale under the cursor). Rarity always shows pips + a name,
##   so no colour-only cues need a toggle.

const TEXT_SPEEDS := [0.5, 1.0, 1.8, 100.0]
const TEXT_SPEED_NAMES := ["Slow", "Normal", "Fast", "Instant"]

var first_control: Control
var last_control: Control

var _speed: Button
var _flashes: CheckButton
var _shake: HSlider
var _shake_value: Label
var _scale: HSlider
var _scale_value: Label


func _ready() -> void:
	custom_minimum_size = Vector2(640, 0)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 14)
	add_child(box)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 18)
	grid.add_theme_constant_override(&"v_separation", 14)
	box.add_child(grid)

	_row_label(grid, "Text speed")
	_speed = Button.new()
	_speed.custom_minimum_size = Vector2(250, 38)
	_speed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speed.pressed.connect(_cycle_speed.bind(1))
	_speed.gui_input.connect(_on_speed_input)
	Sfx.wire_button(_speed)
	grid.add_child(_speed)
	grid.add_child(Control.new())

	_row_label(grid, "Screen shake")
	_shake = _slider(0.0, 1.0, 0.05)
	_shake.value_changed.connect(func(v: float) -> void:
		Settings.screen_shake = v
		_refresh())
	grid.add_child(_shake)
	_shake_value = _value_label()
	grid.add_child(_shake_value)

	_row_label(grid, "Interface scale")
	_scale = _slider(0.75, 1.5, 0.05)
	_scale.value_changed.connect(func(v: float) -> void: _scale_value.text = "%d%%" % roundi(v * 100.0))
	_scale.drag_ended.connect(func(_c: bool) -> void: Settings.ui_scale = _scale.value)
	# Keyboard / pad steps commit at once (no drag).
	_scale.gui_input.connect(func(e: InputEvent) -> void:
		if e.is_action_pressed(&"ui_left") or e.is_action_pressed(&"ui_right"):
			_commit_scale.call_deferred())
	grid.add_child(_scale)
	_scale_value = _value_label()
	grid.add_child(_scale_value)

	_flashes = CheckButton.new()
	_flashes.text = "Reduce flashes and pulses"
	_flashes.add_theme_font_size_override(&"font_size", 21)
	_flashes.toggled.connect(func(on: bool) -> void:
		Settings.reduce_flashes = on
		Sfx.play(&"ui_click"))
	box.add_child(_flashes)

	var note := Label.new()
	note.theme_type_variation = &"CaptionLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.text = "RARITY IS ALWAYS SHOWN AS PIPS AND A NAME:  ◆ COMMON  ·  ◆◆ UNCOMMON  ·  ◆◆◆ RARE  ·  ◆◆◆◆ EPIC  ·  ◆◆◆◆◆ LEGENDARY"
	box.add_child(note)

	_speed.focus_neighbor_bottom = _speed.get_path_to(_shake)
	_shake.focus_neighbor_top = _shake.get_path_to(_speed)
	_shake.focus_neighbor_bottom = _shake.get_path_to(_scale)
	_scale.focus_neighbor_top = _scale.get_path_to(_shake)
	_scale.focus_neighbor_bottom = _scale.get_path_to(_flashes)
	_flashes.focus_neighbor_top = _flashes.get_path_to(_scale)
	first_control = _speed
	last_control = _flashes
	refresh()


## Pulls every value from Settings (call when the page is shown).
func refresh() -> void:
	_shake.set_value_no_signal(Settings.screen_shake)
	_scale.set_value_no_signal(Settings.ui_scale)
	_flashes.set_pressed_no_signal(Settings.reduce_flashes)
	_refresh()


func _refresh() -> void:
	_speed.text = "‹   %s   ›" % TEXT_SPEED_NAMES[_speed_index()]
	_shake_value.text = "%d%%" % roundi(_shake.value * 100.0)
	_scale_value.text = "%d%%" % roundi(_scale.value * 100.0)


func _speed_index() -> int:
	var best := 1
	for i in TEXT_SPEEDS.size():
		if absf(TEXT_SPEEDS[i] - Settings.text_speed) < absf(TEXT_SPEEDS[best] - Settings.text_speed):
			best = i
	return best


func _cycle_speed(dir: int) -> void:
	Settings.text_speed = TEXT_SPEEDS[posmod(_speed_index() + dir, TEXT_SPEEDS.size())]
	_refresh()


func _on_speed_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_left"):
		_cycle_speed(-1)
		Sfx.play(&"ui_click")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_right"):
		_cycle_speed(1)
		Sfx.play(&"ui_click")
		get_viewport().set_input_as_handled()


func _commit_scale() -> void:
	Settings.ui_scale = _scale.value


func _row_label(grid: GridContainer, text: String) -> void:
	var l := Label.new()
	l.theme_type_variation = &"InkLabel"
	l.add_theme_font_size_override(&"font_size", 21)
	l.text = text
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(l)


func _slider(lo: float, hi: float, step: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(250, 26)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return s


func _value_label() -> Label:
	var l := Label.new()
	l.theme_type_variation = &"InkLabel"
	l.add_theme_font_size_override(&"font_size", 22)
	l.add_theme_color_override(&"font_color", UIPalette.BONE_BRIGHT)
	l.custom_minimum_size = Vector2(70, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l
