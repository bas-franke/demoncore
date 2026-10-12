class_name SettingsControlsPage
extends PanelContainer
## "Controls" page of the settings overlay: one row per rebindable action (ui/keybinds.gd) with
## the current key on a button. Press the button, then any key or mouse button to rebind; Esc
## cancels. Gamepad bindings are left as authored. Built in code by settings_menu.gd.

signal rebound(action: StringName)

var first_control: Control
var last_control: Control

var _buttons := {}  # StringName -> Button
var _waiting: StringName = &""
var _reset_all: Button


func _ready() -> void:
	custom_minimum_size = Vector2(640, 0)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", 8)
	scroll.add_child(box)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override(&"h_separation", 18)
	grid.add_theme_constant_override(&"v_separation", 8)
	box.add_child(grid)
	var prev: Control = null
	for entry: Array in Keybinds.ACTIONS:
		var action: StringName = entry[0]
		if not InputMap.has_action(action):
			continue
		var l := Label.new()
		l.theme_type_variation = &"InkLabel"
		l.add_theme_font_size_override(&"font_size", 20)
		l.text = entry[1]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(l)
		var b := Button.new()
		b.custom_minimum_size = Vector2(200, 38)
		b.add_theme_font_size_override(&"font_size", 19)
		b.pressed.connect(_begin.bind(action))
		Sfx.wire_button(b)
		grid.add_child(b)
		_buttons[action] = b
		var r := Button.new()
		r.theme_type_variation = &"GhostButton"
		r.text = "Reset"
		r.tooltip_text = "Restore the default key"
		r.add_theme_font_size_override(&"font_size", 15)
		r.pressed.connect(_reset.bind(action))
		Sfx.wire_button(r, &"ui_back")
		grid.add_child(r)
		if first_control == null:
			first_control = b
		if prev:
			prev.focus_neighbor_bottom = prev.get_path_to(b)
			b.focus_neighbor_top = b.get_path_to(prev)
		prev = b

	var hint := Label.new()
	hint.theme_type_variation = &"CaptionLabel"
	hint.text = "PRESS A BINDING, THEN THE NEW KEY  ·  ESC CANCELS  ·  GAMEPAD STAYS AS IS"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	_reset_all = Button.new()
	_reset_all.theme_type_variation = &"GhostButton"
	_reset_all.text = "Restore all defaults"
	_reset_all.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_reset_all.pressed.connect(_on_reset_all)
	Sfx.wire_button(_reset_all, &"ui_back")
	box.add_child(_reset_all)
	if prev:
		prev.focus_neighbor_bottom = prev.get_path_to(_reset_all)
		_reset_all.focus_neighbor_top = _reset_all.get_path_to(prev)
	last_control = _reset_all
	refresh()


## True while waiting for a key (the settings overlay must not treat Esc as "close").
func is_capturing() -> bool:
	return _waiting != &""


func refresh() -> void:
	for action: StringName in _buttons:
		var b: Button = _buttons[action]
		var t := Keybinds.label(action)
		b.text = t if t != "" else "—"
		b.modulate = Color.WHITE


func _begin(action: StringName) -> void:
	refresh()
	_waiting = action
	var b: Button = _buttons[action]
	b.text = "Press a key…"
	b.modulate = Color(1.35, 1.1, 0.9)


func _input(event: InputEvent) -> void:
	if _waiting == &"" or not is_visible_in_tree():
		return
	var ev: InputEvent = null
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.physical_keycode == KEY_ESCAPE or k.keycode == KEY_ESCAPE:
			_finish(false)
			get_viewport().set_input_as_handled()
			return
		var nk := InputEventKey.new()
		nk.physical_keycode = k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		ev = nk
	elif event is InputEventMouseButton and event.pressed:
		var m := event as InputEventMouseButton
		if m.button_index == MOUSE_BUTTON_WHEEL_UP or m.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			return
		var nm := InputEventMouseButton.new()
		nm.button_index = m.button_index
		ev = nm
	if ev == null:
		return
	get_viewport().set_input_as_handled()
	var action := _waiting
	Keybinds.rebind(action, ev)
	_finish(true)
	rebound.emit(action)


func _finish(changed: bool) -> void:
	var action := _waiting
	_waiting = &""
	refresh()
	Sfx.play(&"ui_click" if changed else &"ui_back", 0.03)
	var b: Button = _buttons.get(action)
	if b:
		# Defer so the release of the key just pressed doesn't re-trigger the button.
		b.grab_focus.call_deferred()


func _reset(action: StringName) -> void:
	Keybinds.reset(action)
	refresh()
	rebound.emit(action)


func _on_reset_all() -> void:
	Keybinds.reset_all()
	refresh()
	rebound.emit(&"")
