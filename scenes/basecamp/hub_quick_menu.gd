class_name HubQuickMenu
extends CanvasLayer
## Basecamp Hell quick menu (Tab / gamepad Back): every merchant, board and station in one list,
## so a returning player can jump straight to a shop. Picking one emits `chosen(entry)` (the hub
## walks the avatar there and uses it); Tab / Esc emits `closed`. Entries: {id, label, hint}.

signal chosen(entry: Dictionary)
signal closed

var _dim: ColorRect
var _panel: PanelContainer
var _grid: GridContainer


func _ready() -> void:
	layer = 21
	visible = false
	_build()


func open(entries: Array) -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	for i in entries.size():
		var e: Dictionary = entries[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(300.0, 52.0)
		b.text = "%s\n%s" % [String(e.label), String(e.hint)]
		b.add_theme_font_size_override(&"font_size", 16)
		b.theme_type_variation = &"CardButton"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_pick.bind(e))
		b.focus_entered.connect(Sfx.play.bind(&"ui_hover", 0.03, -4.0))
		_grid.add_child(b)
	visible = true
	Sfx.play(&"ui_click")
	_dim.modulate.a = 0.0
	_dim.create_tween().tween_property(_dim, "modulate:a", 1.0, 0.15)
	if _grid.get_child_count() > 0:
		(_grid.get_child(0) as Button).grab_focus.call_deferred()


func close() -> void:
	if not visible:
		return
	visible = false
	Sfx.play(&"ui_back")
	closed.emit()


func is_open() -> bool:
	return visible


func _pick(e: Dictionary) -> void:
	visible = false
	Sfx.play(&"select", 0.02, -4.0)
	chosen.emit(e)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"hub_menu") or event.is_action_pressed(&"ui_cancel") \
			or event.is_action_pressed(&"pause"):
		close()
		get_viewport().set_input_as_handled()


func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.0, 0.0, 0.55)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	center.add_child(_panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	_panel.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 10)
	margin.add_child(col)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = "Where to?"
	title.add_theme_font_size_override(&"font_size", 30)
	title.add_theme_color_override(&"font_color", UIPalette.BRIMSTONE)
	col.add_child(title)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override(&"h_separation", 8)
	_grid.add_theme_constant_override(&"v_separation", 8)
	col.add_child(_grid)
	var foot := Label.new()
	foot.theme_type_variation = &"InkLabel"
	foot.text = "Tab / Esc  close"
	foot.add_theme_font_size_override(&"font_size", 14)
	foot.add_theme_color_override(&"font_color", UIPalette.SMOKE)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(foot)
