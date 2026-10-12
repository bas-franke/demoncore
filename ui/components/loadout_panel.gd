class_name LoadoutPanel
extends CanvasLayer
## Pre-run loadout screen for the hellgate (UI role component, used by Basecamp): three columns,
## Weapon / Ability / Keepsake, each a list of selectable cards (painted icon, name, description;
## locked entries show why), a summary line and DESCEND. Fully keyboard / pad navigable: up/down
## inside a column, left/right between columns, Enter picks, D or pad Start descends, Esc leaves.
##
##   var lp := LoadoutPanel.new()
##   add_child(lp)
##   lp.open({
##       "title": "The Hellgate", "subtitle": "Kesh holds the chain. Choose what you carry.",
##       "current": Meta.loadout,                      # {weapon, ability, keepsake} preselected
##       "weapons": RunLoadout.weapons(),              # [{path, name, icon, description, unlocked}]
##       "abilities": RunLoadout.abilities(),          # [{id, name, icon, description, color, unlocked}]
##       "keepsakes": RunLoadout.keepsakes(),          # [{id, name, icon, description, giver_name,
##                                                     #   min_affinity, affinity, available}]
##   })
##   lp.confirmed.connect(func(choice: Dictionary) -> void: Meta.start_run_with_loadout(choice))
##   lp.closed.connect(...)
## Any list may be omitted (that column is hidden). "" = the demon's own weapon / no ability / none.

signal confirmed(choice: Dictionary)
signal closed

const PANEL_MAX := Vector2(1180.0, 700.0)
const COLUMNS := [["weapon", "WEAPON", "weapons"], ["ability", "ABILITY", "abilities"],
	["keepsake", "KEEPSAKE", "keepsakes"]]

var _choice := {"weapon": "", "ability": "", "keepsake": ""}
var _root: Control
var _frame: PanelContainer
var _title: Label
var _subtitle: Label
var _cols: HBoxContainer
var _summary: Label
var _descend: Button
var _first_buttons: Array[Button] = []
var _names := {}  # "weapon:<id>" -> display name


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		close()
		get_viewport().set_input_as_handled()
	elif (event is InputEventKey and event.pressed and not event.echo
			and (event as InputEventKey).physical_keycode == KEY_D) \
			or (event is InputEventJoypadButton and event.pressed
			and (event as InputEventJoypadButton).button_index == JOY_BUTTON_START):
		_on_descend()
		get_viewport().set_input_as_handled()
	else:
		UINav.recover_focus(event, _first_buttons[0] if not _first_buttons.is_empty() else _descend)


func open(config: Dictionary) -> void:
	_title.text = str(config.get("title", "The Hellgate"))
	_subtitle.text = str(config.get("subtitle", "Choose what you carry into Heaven."))
	var cur: Dictionary = config.get("current", {})
	for k: String in _choice:
		_choice[k] = str(cur.get(k, ""))
	for c in _cols.get_children():
		_cols.remove_child(c)
		c.queue_free()
	_first_buttons.clear()
	_names.clear()
	for spec: Array in COLUMNS:
		if config.has(spec[2]):
			_cols.add_child(_column(spec[0], spec[1], config[spec[2]]))
	_update_summary()
	visible = true
	_layout()
	Sfx.play(&"ui_click")
	_frame.modulate.a = 0.0
	_frame.create_tween().tween_property(_frame, "modulate:a", 1.0, 0.25)
	_focus_first.call_deferred()


func close() -> void:
	if not visible:
		return
	visible = false
	Sfx.play(&"ui_back")
	closed.emit()


func get_choice() -> Dictionary:
	return _choice.duplicate()


# ---------------------------------------------------------------- columns

func _column(key: String, title: String, items: Array) -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 6)
	var h := Label.new()
	h.theme_type_variation = &"HeaderLabel"
	h.add_theme_font_size_override(&"font_size", 18)
	h.text = title
	col.add_child(h)
	col.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", 6)
	scroll.add_child(list)
	var group := ButtonGroup.new()
	var none_label: String = {"weapon": "The demon's own", "ability": "None", "keepsake": "None"}[key]
	var none_desc: String = {"weapon": "Descend with your demon's signature weapon.",
		"ability": "Earn your gifts on the way.", "keepsake": "Carry nothing but spite."}[key]
	var entries: Array = [{"_id": "", "name": none_label, "description": none_desc, "icon": "✦"}]
	for it: Variant in items:
		if it is Dictionary:
			var d: Dictionary = (it as Dictionary).duplicate()
			d["_id"] = str(d.get("path", d.get("id", "")))
			entries.append(d)
	var prev: Button = null
	for d: Dictionary in entries:
		var b := _card(key, d, group)
		list.add_child(b)
		_names["%s:%s" % [key, d._id]] = str(d.get("name", ""))
		if prev:
			prev.focus_neighbor_bottom = prev.get_path_to(b)
			b.focus_neighbor_top = b.get_path_to(prev)
		else:
			_first_buttons.append(b)
		prev = b
	if prev:
		prev.focus_neighbor_bottom = prev.get_path_to(_descend)
	return col


func _card(key: String, d: Dictionary, group: ButtonGroup) -> Button:
	var id := str(d._id)
	var locked := not bool(d.get("unlocked", d.get("available", true)))
	var b := Button.new()
	b.theme_type_variation = &"CardButton"
	b.toggle_mode = true
	b.button_group = group
	b.custom_minimum_size = Vector2(0, 74)
	b.disabled = locked
	b.set_pressed_no_signal(_choice[key] == id)
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: StringName in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		pad.add_theme_constant_override(side, 8)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(pad)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(row)
	var tint: Color = d.get("color", UIPalette.EMBER) if d.get("color") is Color else UIPalette.EMBER
	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(52, 52)
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_theme_stylebox_override(&"panel", UIPalette.box(UIPalette.SCORCH.lerp(tint, 0.12),
		Color(tint, 0.6) if not locked else UIPalette.IRON, 1, 2, 4.0))
	row.add_child(icon_box)
	var tex: Texture2D = Icons.get_icon(id.get_file().get_basename()) if key == "weapon" and id != "" else null
	if tex and not locked:
		var art := TextureRect.new()
		art.texture = tex
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_box.add_child(art)
	else:
		var g := GlyphIcon.new()
		g.glyph = "🔒" if locked else str(d.get("icon", "✦"))
		g.color = UIPalette.LOCKED.lightened(0.2) if locked else tint.lerp(UIPalette.BONE_BRIGHT, 0.3)
		icon_box.add_child(g)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override(&"separation", 0)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texts)
	var n := Label.new()
	n.theme_type_variation = &"InkLabel"
	n.add_theme_font_size_override(&"font_size", 17)
	n.add_theme_color_override(&"font_color", UIPalette.ASH_TEXT if locked else UIPalette.BONE_BRIGHT)
	n.text = str(d.get("name", ""))
	texts.add_child(n)
	var desc := Label.new()
	desc.theme_type_variation = &"LoreLabel"
	desc.add_theme_font_size_override(&"font_size", 14)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.max_lines_visible = 2
	desc.custom_minimum_size.x = 140.0
	var text := str(d.get("description", ""))
	if locked:
		text = _lock_reason(key, d)
		desc.add_theme_color_override(&"font_color", UIPalette.DANGER.lerp(UIPalette.ASH_TEXT, 0.4))
	desc.text = text
	texts.add_child(desc)
	b.tooltip_text = str(d.get("description", ""))
	b.toggled.connect(func(on: bool) -> void:
		if on:
			_choice[key] = id
			_update_summary())
	Sfx.wire_button(b)
	return b


func _lock_reason(key: String, d: Dictionary) -> String:
	if key == "keepsake":
		return "%s's trust %d / %d" % [str(d.get("giver_name", "?")), int(d.get("affinity", 0)),
			int(d.get("min_affinity", 3))]
	return "Sealed. Unseal it at Basecamp."


func _update_summary() -> void:
	var parts: PackedStringArray = []
	for spec: Array in COLUMNS:
		var k: String = spec[0]
		var nm: String = _names.get("%s:%s" % [k, _choice[k]], "")
		if nm != "":
			parts.append("%s: %s" % [String(spec[1]).capitalize(), nm])
	_summary.text = "  ·  ".join(parts)


func _focus_first() -> void:
	if not _first_buttons.is_empty():
		_first_buttons[0].grab_focus()
	else:
		_descend.grab_focus()


func _on_descend() -> void:
	if not visible:
		return
	visible = false
	Sfx.play(&"select")
	confirmed.emit(_choice.duplicate())


func _layout() -> void:
	var vp := _root.size
	_frame.size = Vector2.ZERO
	_frame.size = Vector2(minf(PANEL_MAX.x, vp.x * 0.94), minf(PANEL_MAX.y, vp.y * 0.9))
	_frame.position = (vp - _frame.size) * 0.5


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = load("res://ui/theme.tres") as Theme
	add_child(_root)
	_root.resized.connect(_layout)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.006, 0.004, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	_frame = PanelContainer.new()
	_frame.theme_type_variation = &"InfernalPanel"
	_root.add_child(_frame)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 10)
	_frame.add_child(col)
	_title = Label.new()
	_title.theme_type_variation = &"TitleLabel"
	_title.add_theme_font_size_override(&"font_size", 36)
	col.add_child(_title)
	_subtitle = Label.new()
	_subtitle.theme_type_variation = &"LoreLabel"
	col.add_child(_subtitle)
	_cols = HBoxContainer.new()
	_cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cols.add_theme_constant_override(&"separation", 18)
	col.add_child(_cols)
	col.add_child(HSeparator.new())
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override(&"separation", 14)
	col.add_child(foot)
	_summary = Label.new()
	_summary.theme_type_variation = &"CaptionLabel"
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	foot.add_child(_summary)
	var leave := Button.new()
	leave.theme_type_variation = &"GhostButton"
	leave.text = "LEAVE"
	leave.pressed.connect(close)
	Sfx.wire_button(leave, &"ui_back")
	foot.add_child(leave)
	_descend = Button.new()
	_descend.theme_type_variation = &"AccentButton"
	_descend.text = "DESCEND  [D]"
	_descend.custom_minimum_size = Vector2(220, 48)
	_descend.pressed.connect(_on_descend)
	Sfx.wire_button(_descend)
	foot.add_child(_descend)
