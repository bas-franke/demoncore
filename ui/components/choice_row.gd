class_name ChoiceRow
extends PanelContainer
## One row of a choice list (maps at the cartographer, pacts at the Covenant, rites, ...): a painted
## medallion, title + subtitle, a description, tag chips, an optional warning line, and actions on
## the right (buttons and/or a rank stepper). The state shows as a coloured edge AND a shape
## (◉ chosen / ◆ active / ○ available / ✕ locked), so it never relies on colour alone.
##
##   var row := ChoiceRow.new()
##   row.setup({"glyph": "⛧", "color": tint, "title": "Cathedral City", "subtitle": "the white spires",
##       "description": "...", "tags": ["Peril ✠✠✠"], "state": &"available", "note": ""})
##   row.add_action("Choose", _on_choose.bind(id), &"AccentButton")
##   row.add_stepper(rank, max_rank, func(r: int) -> void: Progression.set_pact_rank(id, r))
## Put rows in ListPanel (ui/components/list_panel.gd) or any VBoxContainer.

signal hovered

const STATE_MARKS := {&"chosen": "◉", &"active": "◆", &"available": "○", &"locked": "✕"}

var state: StringName = &"available"
var accent := Color("e0662a")

var _icon: GlyphIcon
var _texts: VBoxContainer
var _actions: HBoxContainer
var _mark: Label
var _style: StyleBoxFlat


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style = UIPalette.box(Color(0.07, 0.035, 0.03, 0.9), UIPalette.IRON, 1, 2, 10.0)
	_style.border_width_left = 4
	add_theme_stylebox_override(&"panel", _style)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override(&"separation", 14)
	add_child(hb)
	_mark = Label.new()
	_mark.theme_type_variation = &"ValueLabel"
	_mark.custom_minimum_size.x = 18.0
	_mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(_mark)
	var medal := PanelContainer.new()
	medal.custom_minimum_size = Vector2(52, 52)
	medal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	medal.add_theme_stylebox_override(&"panel", UIPalette.box(UIPalette.SCORCH, UIPalette.EMBER_DIM, 1, 26, 8.0))
	hb.add_child(medal)
	_icon = GlyphIcon.new()
	medal.add_child(_icon)
	_texts = VBoxContainer.new()
	_texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_texts.add_theme_constant_override(&"separation", 2)
	hb.add_child(_texts)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override(&"separation", 8)
	_actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(_actions)
	mouse_entered.connect(func() -> void: hovered.emit())


## Fills the row. Keys: glyph, color, title, subtitle, description, tags (Array[String]),
## state (&"chosen" / &"active" / &"available" / &"locked"), note (warning line, e.g. a requirement).
func setup(d: Dictionary) -> void:
	for c in _texts.get_children():
		c.queue_free()
	accent = d.get("color", UIPalette.EMBER)
	state = StringName(str(d.get("state", "available")))
	var locked := state == &"locked"
	_icon.glyph = str(d.get("glyph", "✦"))
	_icon.color = UIPalette.LOCKED.lightened(0.15) if locked else accent.lerp(UIPalette.BONE_BRIGHT, 0.25)

	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 10)
	_texts.add_child(head)
	head.add_child(_label(str(d.get("title", "")), &"HeaderLabel", 20,
		UIPalette.ASH_TEXT if locked else UIPalette.BONE_BRIGHT))
	if str(d.get("subtitle", "")) != "":
		var sub := _label(str(d.subtitle), &"LoreLabel", 15, UIPalette.ASH_TEXT)
		sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(sub)
	if str(d.get("description", "")) != "":
		var desc := _label(str(d.description), &"InkLabel", 16, UIPalette.ASH_TEXT if locked else UIPalette.BONE)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size.x = 200.0
		_texts.add_child(desc)
	var tags: Array = d.get("tags", [])
	if not tags.is_empty():
		var tag_row := HBoxContainer.new()
		tag_row.add_theme_constant_override(&"separation", 8)
		_texts.add_child(tag_row)
		for t: Variant in tags:
			var chip := PanelContainer.new()
			chip.add_theme_stylebox_override(&"panel", UIPalette.box(Color(0, 0, 0, 0.35), UIPalette.IRON, 1, 2, 3.0))
			chip.add_child(_label(str(t), &"CaptionLabel", 12, UIPalette.BRIMSTONE_DIM.lightened(0.2)))
			tag_row.add_child(chip)
	if str(d.get("note", "")) != "":
		_texts.add_child(_label("✕ " + str(d.note), &"CaptionLabel", 13, UIPalette.DANGER))
	_refresh_state()


## Adds a button on the right. Returns it (set `disabled`, tooltip, ... as needed).
func add_action(text: String, cb: Callable, variation: StringName = &"", disabled := false) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(128, 44)
	b.disabled = disabled
	b.pressed.connect(cb)
	b.focus_entered.connect(func() -> void: hovered.emit())
	Sfx.wire_button(b)
	_actions.add_child(b)
	return b


## − ◆◆◇◇ + rank stepper; `on_change(new_rank)` is called with the requested rank.
func add_stepper(rank: int, max_rank: int, on_change: Callable) -> void:
	var minus := add_action("−", func() -> void: on_change.call(rank - 1), &"", rank <= 0)
	minus.custom_minimum_size = Vector2(46, 44)
	var pips := _label("◆".repeat(rank) + "◇".repeat(maxi(max_rank - rank, 0)), &"ValueLabel", 16,
		UIPalette.BLOOD_BRIGHT if rank > 0 else UIPalette.SMOKE)
	pips.custom_minimum_size.x = 14.0 * max_rank
	pips.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_actions.add_child(pips)
	var plus := add_action("+", func() -> void: on_change.call(rank + 1), &"AccentButton", rank >= max_rank)
	plus.custom_minimum_size = Vector2(46, 44)


## First focusable action (for keyboard / pad focus).
func first_button() -> Button:
	for c in _actions.get_children():
		if c is Button and not (c as Button).disabled:
			return c
	return null


func _refresh_state() -> void:
	_mark.text = STATE_MARKS.get(state, "○")
	var edge := accent
	match state:
		&"chosen":
			_style.bg_color = Color(0.16, 0.06, 0.035, 0.94)
			_style.shadow_color = Color(accent, 0.22)
			_style.shadow_size = 12
		&"active":
			_style.bg_color = Color(0.14, 0.045, 0.035, 0.92)
		&"locked":
			edge = UIPalette.LOCKED
			_style.bg_color = Color(0.05, 0.035, 0.03, 0.85)
	_style.border_color = Color(edge, 0.9)
	_mark.add_theme_color_override(&"font_color", edge.lerp(UIPalette.BONE_BRIGHT, 0.3))


func _label(text: String, variation: StringName, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_color", color)
	l.text = text
	return l
