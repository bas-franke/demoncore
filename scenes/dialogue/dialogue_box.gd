class_name DialogueBox
extends CanvasLayer
## Modal dialogue box: portrait, speaker name plate, typewriter text and choice buttons. Built in
## code and owned by the Dialogue autoload, which drives it line by line:
##   show_line(speaker, text) -> emits `advanced` once the player confirms the fully shown line
##   show_choices(texts)      -> emits `chosen(index)`
## Confirm (Enter / Space / E / left click / gamepad A) first completes the line, then advances.
## Runs while the tree is paused (Dialogue pauses the game during conversations).

signal advanced
signal chosen(index: int)

const LAYER := 95
const CHARS_PER_SEC := 52.0
## Extra pause after punctuation, seconds.
const PAUSE_STOP := 0.22
const PAUSE_COMMA := 0.07
## Ignore confirm presses for this long after a line appears (the key that opened the talk).
const INPUT_GRACE := 0.18
const BOX_WIDTH := 980.0
const PORTRAIT_SIZE := 148.0
const TEXT_COLOR := Color("eadcc4")
const NARRATOR_COLOR := Color("cdbfa5")
const EDGE := Color(0.75, 0.3, 0.12, 0.8)

var _root: Control
var _panel: PanelContainer
var _portrait: DialoguePortrait
var _name: Label
var _title: Label
var _text: RichTextLabel
var _choices: VBoxContainer
var _more: Label
var _shade: TextureRect

var _typing := false
var _waiting := false
var _shown := 0.0
var _pause := 0.0
var _grace := 0.0
var _t := 0.0
var _tick := 0
var _parsed := ""
var _speaker_id := ""  # whose voice the typing blips use (Sfx.play_blip)


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


func _process(delta: float) -> void:
	_t += delta
	_grace = maxf(_grace - delta, 0.0)
	if _typing:
		_type(delta)
	_more.modulate.a = (0.55 + 0.45 * sin(_t * 5.0)) if _waiting else 0.0


func _input(event: InputEvent) -> void:
	if not visible or _choices.visible:
		return
	if _is_confirm(event):
		get_viewport().set_input_as_handled()
		if _grace > 0.0:
			return
		if _typing:
			_finish_typing()
		elif _waiting:
			_waiting = false
			Sfx.play(&"ui_click", 0.05, -6.0)
			advanced.emit()
	elif event.is_action_pressed(&"pause"):
		# Keep the pause menu from opening over a conversation.
		get_viewport().set_input_as_handled()


func open() -> void:
	visible = true
	_panel.modulate.a = 0.0
	_shade.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(_panel, "modulate:a", 1.0, 0.18)
	tw.tween_property(_shade, "modulate:a", 1.0, 0.3)


func close() -> void:
	_typing = false
	_waiting = false
	_clear_choices()
	var tw := create_tween().set_parallel()
	tw.tween_property(_panel, "modulate:a", 0.0, 0.15)
	tw.tween_property(_shade, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(hide)


## Shows `text` (BBCode allowed) from `speaker` (DialogueDB speaker dict; empty = narrator).
func show_line(speaker: Dictionary, text: String) -> void:
	_clear_choices()
	var narrator := speaker.is_empty() or str(speaker.get("id", "")) == "narrator"
	_speaker_id = "narrator" if narrator else str(speaker.get("id", ""))
	_portrait.visible = not narrator
	_name.get_parent().visible = not narrator
	if not narrator:
		_portrait.set_speaker(speaker)
		_name.text = str(speaker.get("name", ""))
		_name.add_theme_color_override(&"font_color", speaker.get("color", TEXT_COLOR))
		_title.text = str(speaker.get("title", ""))
		_title.visible = _title.text != ""
	_text.add_theme_color_override(&"default_color", NARRATOR_COLOR if narrator else TEXT_COLOR)
	_text.text = ("[center][i]%s[/i][/center]" % text) if narrator else text
	_parsed = _text.get_parsed_text()
	_text.visible_characters = 0
	_shown = 0.0
	_pause = 0.0
	_typing = true
	_waiting = false
	_grace = INPUT_GRACE


## Shows the choice buttons under the current text; emits `chosen(index)`.
func show_choices(texts: Array) -> void:
	_finish_typing()
	_waiting = false
	_clear_choices()
	for i in texts.size():
		var b := Button.new()
		b.text = "  " + str(texts[i])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.flat = true
		b.focus_mode = Control.FOCUS_ALL
		b.add_theme_color_override(&"font_color", Color("b9a888"))
		b.add_theme_color_override(&"font_hover_color", Color("ffd9a0"))
		b.add_theme_color_override(&"font_focus_color", Color("ffd9a0"))
		b.add_theme_font_size_override(&"font_size", 20)
		var idx := i
		b.pressed.connect(func() -> void: _on_choice(idx))
		b.focus_entered.connect(func() -> void: Sfx.play(&"ui_hover", 0.03, -8.0))
		_choices.add_child(b)
	_choices.visible = true
	# Focus after a short delay so the confirm press that revealed the choices cannot pick one.
	get_tree().create_timer(INPUT_GRACE, true).timeout.connect(func() -> void:
		if _choices.visible and _choices.get_child_count() > 0:
			(_choices.get_child(0) as Control).grab_focus())


func _on_choice(i: int) -> void:
	if not _choices.visible:
		return
	Sfx.play(&"select", 0.02, -4.0)
	_clear_choices()
	chosen.emit(i)


func _clear_choices() -> void:
	_choices.visible = false
	for c in _choices.get_children():
		_choices.remove_child(c)
		c.queue_free()


func _type(delta: float) -> void:
	if _pause > 0.0:
		_pause -= delta
		return
	var before := int(_shown)
	_shown += delta * CHARS_PER_SEC * Settings.text_speed  # text speed: Settings > Accessibility
	var total := _parsed.length()
	var now := mini(int(_shown), total)
	if now > before:
		_text.visible_characters = now
		var ch := _parsed[now - 1]
		if ch in ".!?":
			_pause = PAUSE_STOP
		elif ch in ",;:":
			_pause = PAUSE_COMMA
		_tick += now - before
		if _tick >= 4 and ch != " ":
			_tick = 0
			Sfx.play_blip(_speaker_id)
	if now >= total:
		_finish_typing()


func _finish_typing() -> void:
	_typing = false
	_text.visible_characters = -1
	_waiting = true


func _is_confirm(event: InputEvent) -> bool:
	if event.is_echo():
		return false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	if event.is_action_pressed(&"ui_accept"):
		return true
	if InputMap.has_action(&"interact") and event.is_action_pressed(&"interact"):
		return true
	if event is InputEventKey:
		var k := event as InputEventKey
		return k.pressed and k.physical_keycode == KEY_E
	return false


# ---------------------------------------------------------------- layout

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Soft dark gradient behind the box so the text reads over any scene.
	_shade = TextureRect.new()
	_shade.texture = _shade_texture()
	_shade.stretch_mode = TextureRect.STRETCH_SCALE
	_shade.anchor_left = 0.0
	_shade.anchor_right = 1.0
	_shade.anchor_top = 0.55
	_shade.anchor_bottom = 1.0
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_shade)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override(&"panel", _panel_style())
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -BOX_WIDTH * 0.5
	_panel.offset_right = BOX_WIDTH * 0.5
	_panel.offset_bottom = -28.0
	_panel.offset_top = -28.0
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_root.add_child(_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 22)
	_panel.add_child(row)

	_portrait = DialoguePortrait.new()
	_portrait.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_portrait)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 6)
	row.add_child(col)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override(&"separation", 14)
	col.add_child(name_row)
	_name = Label.new()
	_name.theme_type_variation = &"TitleLabel"
	_name.add_theme_font_size_override(&"font_size", 30)
	name_row.add_child(_name)
	_title = Label.new()
	_title.theme_type_variation = &"LoreLabel"
	_title.add_theme_font_size_override(&"font_size", 17)
	_title.size_flags_vertical = Control.SIZE_SHRINK_END
	name_row.add_child(_title)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(0.0, 84.0)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	_text.add_theme_font_size_override(&"normal_font_size", 24)
	_text.add_theme_font_size_override(&"italics_font_size", 24)
	_text.add_theme_font_override(&"italics_font", _italic_font())
	_text.add_theme_constant_override(&"line_separation", 4)
	_text.add_theme_constant_override(&"outline_size", 3)
	_text.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.75))
	col.add_child(_text)

	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override(&"separation", 2)
	_choices.visible = false
	col.add_child(_choices)

	_more = Label.new()
	_more.text = "▼"
	_more.add_theme_color_override(&"font_color", Color("ff9a4a"))
	_more.add_theme_font_size_override(&"font_size", 16)
	_more.size_flags_horizontal = Control.SIZE_SHRINK_END
	col.add_child(_more)


func _italic_font() -> Font:
	var f := FontVariation.new()
	f.base_font = _root.get_theme_default_font()
	# Synthetic oblique: shear the glyphs, since the theme's serif may have no italic face.
	f.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(0.2, 1.0), Vector2.ZERO)
	return f


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.055, 0.03, 0.03, 0.94)
	s.border_color = EDGE
	s.set_border_width_all(2)
	s.border_width_top = 3
	s.set_corner_radius_all(6)
	s.shadow_color = Color(0.4, 0.06, 0.02, 0.45)
	s.shadow_size = 14
	s.content_margin_left = 24.0
	s.content_margin_right = 28.0
	s.content_margin_top = 18.0
	s.content_margin_bottom = 12.0
	return s


func _shade_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0.02, 0, 0, 0.75)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 1
	tex.height = 64
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	return tex
