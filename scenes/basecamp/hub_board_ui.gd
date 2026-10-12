class_name HubBoardUI
extends CanvasLayer
## Read-only info window for Basecamp Hell boards: the Ledger of the Damned (lifetime stats) and the
## trophy wall (bosses slain). Built in code; Esc / E closes it. Emits `closed`.
##
##   board.open_board("Title", "flavour line", [{"label": "Descents", "value": "12", "note": ""}, ...])

signal closed

const PANEL_SIZE := Vector2(680.0, 520.0)

var _dim: ColorRect
var _panel: PanelContainer
var _title: Label
var _sub: Label
var _list: VBoxContainer
var _action_button: Button
var _action := Callable()


func _ready() -> void:
	layer = 20
	visible = false
	_build()


## `rows`: [{label, value, note?, color?, dim?}] (dim = greyed out, e.g. a locked trophy).
## Optional `action_text` + `action` add a call-to-action button (e.g. "Accept the Trial"); pressing
## it closes the board and calls `action`.
func open_board(title: String, subtitle: String, rows: Array, action_text: String = "",
		action: Callable = Callable()) -> void:
	_action = action
	_action_button.text = action_text
	_action_button.visible = action_text != ""
	_title.text = title
	_sub.text = subtitle
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for r: Dictionary in rows:
		_list.add_child(_row(r))
	visible = true
	Sfx.play(&"ui_click")
	_panel.pivot_offset = _panel.size * 0.5
	var tw := _panel.create_tween()
	tw.tween_property(_panel, "modulate:a", 1.0, 0.25).from(0.0)
	tw.parallel().tween_property(_panel, "scale", Vector2.ONE, 0.3).from(Vector2(0.96, 0.96)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _action_button.visible:
		_action_button.grab_focus.call_deferred()


func close() -> void:
	if not visible:
		return
	visible = false
	Sfx.play(&"ui_back")
	closed.emit()


func is_open() -> bool:
	return visible


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause") \
			or event.is_action_pressed(&"interact"):
		close()
		get_viewport().set_input_as_handled()


func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.0, 0.0, 0.6)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = PANEL_SIZE
	center.add_child(_panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	_panel.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 6)
	margin.add_child(col)
	_title = Label.new()
	_title.theme_type_variation = &"TitleLabel"
	_title.add_theme_font_size_override(&"font_size", 34)
	_title.add_theme_color_override(&"font_color", UIPalette.BRIMSTONE)
	col.add_child(_title)
	_sub = _label("", 17, UIPalette.ASH_TEXT)
	_sub.theme_type_variation = &"LoreLabel"
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_sub)
	col.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 4)
	scroll.add_child(_list)
	_action_button = Button.new()
	_action_button.theme_type_variation = &"AccentButton"
	_action_button.custom_minimum_size = Vector2(240.0, 48.0)
	_action_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_action_button.visible = false
	_action_button.pressed.connect(_on_action)
	col.add_child(_action_button)
	var foot := _label("Esc  close", 15, UIPalette.SMOKE)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(foot)


func _on_action() -> void:
	var act := _action
	visible = false
	closed.emit()
	if act.is_valid():
		act.call()


func _row(r: Dictionary) -> Control:
	var dim := bool(r.get("dim", false))
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 0)
	var hb := HBoxContainer.new()
	box.add_child(hb)
	var name_l := _label(String(r.get("label", "")), 19, UIPalette.LOCKED if dim else UIPalette.BONE)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(name_l)
	var value_l := _label(String(r.get("value", "")), 21,
			UIPalette.LOCKED if dim else r.get("color", UIPalette.BRIMSTONE))
	value_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(value_l)
	var note := String(r.get("note", ""))
	if note != "":
		var n := _label(note, 15, UIPalette.SMOKE if dim else UIPalette.ASH_TEXT)
		n.theme_type_variation = &"LoreLabel"
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(n)
	return box


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"InkLabel"
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_color", color)
	l.text = text
	return l
