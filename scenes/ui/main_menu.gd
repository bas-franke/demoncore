class_name MainMenu
extends CanvasLayer
## Title-screen menu (UI role). The title scene shows it after "Press any key": a column of
## forged buttons low on the screen, under the logo. Emits `descend_chosen` (start the game);
## Settings opens the shared overlay, Credits the role credits, Quit leaves. Keyboard / pad focus
## starts on Descend; a hint line at the bottom shows the controls.
##
##   var menu := MainMenu.new()
##   add_child(menu)
##   menu.descend_chosen.connect(_leave)

signal descend_chosen

const SETTINGS_SCENE := "res://scenes/ui/settings_menu.tscn"
const BUTTON_SIZE := Vector2(176.0, 46.0)

var _root: Control
var _col: HBoxContainer  # one row of buttons under the tagline
var _descend: Button
var _settings: CanvasLayer
var _credits: CreditsScreen
var _busy := false


func _ready() -> void:
	layer = 15
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = load("res://ui/theme.tres") as Theme
	add_child(_root)

	_col = HBoxContainer.new()
	_col.add_theme_constant_override(&"separation", 14)
	_col.anchor_right = 1.0
	_col.anchor_top = 1.0
	_col.anchor_bottom = 1.0
	_col.offset_top = -BUTTON_SIZE.y - 112.0
	_col.offset_bottom = -112.0
	_col.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_child(_col)

	_descend = _button("Descend", &"AccentButton", _on_descend)
	_button("Settings", &"", _on_settings)
	_button("Credits", &"", _on_credits)
	_button("Quit", &"GhostButton", _on_quit)
	var buttons := _col.get_children()
	for i in buttons.size():
		var b := buttons[i] as Button
		var prev := buttons[(i - 1 + buttons.size()) % buttons.size()] as Button
		var next := buttons[(i + 1) % buttons.size()] as Button
		# Left/right walk the row (wrapping); up/down do the same so either stick axis works.
		b.focus_neighbor_left = b.get_path_to(prev)
		b.focus_neighbor_right = b.get_path_to(next)
		b.focus_neighbor_top = b.get_path_to(prev)
		b.focus_neighbor_bottom = b.get_path_to(next)

	# Fade + rise in.
	_col.modulate.a = 0.0
	var tw := _col.create_tween().set_parallel()
	tw.tween_property(_col, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_col, "position:y", _col.position.y, 0.7).from(_col.position.y + 16.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_descend.grab_focus.call_deferred()

	var hint := Label.new()
	hint.theme_type_variation = &"CaptionLabel"
	hint.text = "← →  CHOOSE      ENTER / Ⓐ  CONFIRM      ESC / Ⓑ  BACK"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.anchor_right = 1.0
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_top = -40.0
	hint.offset_bottom = -18.0
	hint.modulate.a = 0.0
	_root.add_child(hint)
	hint.create_tween().tween_property(hint, "modulate:a", 0.75, 1.2).set_delay(0.6)


func _unhandled_input(event: InputEvent) -> void:
	if _busy or (_settings and _settings.visible) or (_credits and _credits.visible):
		return
	# Any direction / accept with nothing focused gives focus back to the row.
	UINav.recover_focus(event, _descend)


func _button(text: String, variation: StringName, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.theme_type_variation = variation
	b.custom_minimum_size = BUTTON_SIZE
	b.pressed.connect(cb)
	Sfx.wire_button(b)
	_col.add_child(b)
	return b


func _on_descend() -> void:
	if _busy:
		return
	_busy = true
	var tw := _col.create_tween()
	tw.tween_property(_col, "modulate:a", 0.0, 0.4)
	descend_chosen.emit()


func _on_settings() -> void:
	if _settings == null:
		var scene := load(SETTINGS_SCENE) as PackedScene
		if scene == null:
			return
		_settings = scene.instantiate() as CanvasLayer
		add_child(_settings)
		_settings.connect(&"closed", func() -> void: _descend.grab_focus())
	_settings.call(&"open")


func _on_credits() -> void:
	if _credits == null:
		_credits = CreditsScreen.new()
		add_child(_credits)
		_credits.closed.connect(func() -> void: _descend.grab_focus())
	_credits.open()


func _on_quit() -> void:
	_busy = true
	get_tree().quit()
