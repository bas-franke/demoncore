class_name SkinPicker
extends VBoxContainer
## Skin chooser row for any screen that shows a DemonModel (demon select, basecamp wardrobe):
##   SKIN   ‹  Soulfire  ›
##   "Burns with the stolen light of devoured souls."   /   LOCKED: Slay a herald of Heaven.
##
##   var picker := SkinPicker.new()
##   panel.add_child(picker)
##   picker.show_for(demon_model)      # whenever the shown demon changes
##
## Cycling previews every skin on the model; unlocked ones are also saved as that demon's choice
## (DemonSkins.select), locked ones only preview and show their unlock hint. Keys: W / S (or the
## move_up / move_down actions) cycle while `keyboard` is true.

signal skin_changed(skin_id: StringName, unlocked: bool)

const TEXT := Color(0.86, 0.82, 0.74)
const TEXT_DIM := Color(0.6, 0.56, 0.5)
const ACCENT := Color(1.0, 0.5, 0.22)
const LOCKED := Color(0.72, 0.28, 0.26)

## Handle W / S (move_up / move_down) to cycle skins.
var keyboard := true

var _model: DemonModel
var _demon_id := &""
var _skins: Array[Dictionary] = []
var _index := 0
var _name: Label
var _desc: Label


func _init() -> void:
	add_theme_constant_override("separation", 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	row.add_child(_label("SKIN", 12, ACCENT))
	var prev := _arrow("‹")
	prev.pressed.connect(func() -> void: step(-1))
	row.add_child(prev)
	_name = _label("", 19, TEXT)
	_name.custom_minimum_size = Vector2(190.0, 0.0)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_name)
	var next := _arrow("›")
	next.pressed.connect(func() -> void: step(1))
	row.add_child(next)
	_desc = _label("", 13, TEXT_DIM)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(380.0, 0.0)
	add_child(_desc)


## Shows (and lets the player change) the skin of `model`. The previously shown model goes back
## to its saved skin if a locked one was being previewed.
func show_for(model: DemonModel) -> void:
	if _model and is_instance_valid(_model) and _model != model:
		_revert_preview()
	_model = model
	if model == null or model.data == null:
		_skins.clear()
		_refresh()
		return
	_demon_id = DemonSkins.demon_id_of(model.data)
	_skins = DemonSkins.list_for(_demon_id)
	_index = 0
	var current := DemonSkins.selected_id(_demon_id)
	for i in _skins.size():
		if StringName(_skins[i].id) == current:
			_index = i
	if model.skin_id != current:
		model.set_skin(current)
	_refresh()


## Next / previous skin.
func step(dir: int) -> void:
	if _skins.size() < 2 or _model == null or not is_instance_valid(_model):
		return
	_index = wrapi(_index + dir, 0, _skins.size())
	var skin := _skins[_index]
	var id := StringName(skin.id)
	var ok := DemonSkins.is_unlocked(skin)
	if ok:
		DemonSkins.select(_demon_id, id)
	_model.set_skin(id)
	Sfx.play(&"ui_click")
	_refresh()
	skin_changed.emit(id, ok)


func _unhandled_input(event: InputEvent) -> void:
	if not keyboard or not is_visible_in_tree() or _model == null:
		return
	if event.is_action_pressed(&"move_up"):
		step(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"move_down"):
		step(1)
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	_revert_preview()


func _revert_preview() -> void:
	if _model == null or not is_instance_valid(_model) or _model.data == null:
		return
	var saved := DemonSkins.selected_id(DemonSkins.demon_id_of(_model.data))
	if _model.skin_id != saved:
		_model.set_skin(saved)


func _refresh() -> void:
	if _skins.is_empty():
		_name.text = "-"
		_desc.text = ""
		return
	var skin := _skins[_index]
	var ok := DemonSkins.is_unlocked(skin)
	_name.text = "%s  (%d/%d)" % [String(skin.get("name", skin.id)), _index + 1, _skins.size()]
	_name.add_theme_color_override("font_color", TEXT if ok else LOCKED)
	if ok:
		_desc.text = String(skin.get("description", ""))
		_desc.add_theme_color_override("font_color", TEXT_DIM)
	else:
		_desc.text = "LOCKED: %s" % DemonSkins.unlock_hint(skin)
		_desc.add_theme_color_override("font_color", LOCKED)


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"InkLabel"
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _arrow(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(34.0, 34.0)
	b.add_theme_font_size_override("font_size", 20)
	b.focus_mode = Control.FOCUS_NONE
	return b
