class_name CodexScreen
extends CanvasLayer
## The lore Codex (UI role): reads the story role's entries through Dialogue.codex_entries()
## ({id, category, title, text, unlocked, is_new}) and shows them as category tabs, a list on the
## left and the open entry on the right. Opening an entry marks it read (Dialogue.codex_mark_read).
## A "Relics" tab lists every relic from Progression.codex_entries() (silhouettes until found).
## A footer button opens the Bestiary (scenes/ui/bestiary.tscn). Built in code; works while paused.
##
##   var codex := CodexScreen.new()
##   add_child(codex)
##   codex.open()                 # emits `closed` when dismissed (Esc / pause / Return)
## Static helper for HUD-like badges: CodexScreen.new_count() -> unread unlocked entries.

signal closed

const BESTIARY_SCENE := "res://scenes/ui/bestiary.tscn"
const PANEL_MAX := Vector2(1100.0, 700.0)
const LIST_W := 330.0

var _root: Control
var _dim: ColorRect
var _frame: PanelContainer
var _tabs: HBoxContainer
var _list: VBoxContainer
var _title: Label
var _cat: Label
var _text: RichTextLabel
var _empty: Label
var _back: Button
var _entries: Array[Dictionary] = []
var _category := ""
var _selected := ""
var _buttons := {}  # entry id -> Button
var _bestiary: CanvasLayer
var _relic_slot: HBoxContainer


static func new_count() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	var d := tree.root.get_node_or_null(^"Dialogue") if tree else null
	if d and d.has_method(&"codex_new_count"):
		return int(d.call(&"codex_new_count"))
	return 0


func _ready() -> void:
	layer = 26
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func _input(event: InputEvent) -> void:
	if not visible or (_bestiary and _bestiary.visible):
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		close()
		get_viewport().set_input_as_handled()
	elif UINav.page_dir(event) != 0 and _tabs.get_child_count() > 1:
		_cycle_tab(UINav.page_dir(event))  # Q / E or pad LB / RB
		get_viewport().set_input_as_handled()
	else:
		var b: Button = _buttons.get(_selected)
		UINav.recover_focus(event, b if b else _back)


func open() -> void:
	_entries = _load_entries()
	visible = true
	Sfx.play(&"ui_click")
	_rebuild_tabs()
	_rebuild_list()
	_layout()
	_dim.modulate.a = 0.0
	_dim.create_tween().tween_property(_dim, "modulate:a", 1.0, 0.3)
	_frame.modulate.a = 0.0
	_frame.create_tween().tween_property(_frame, "modulate:a", 1.0, 0.3)


func close() -> void:
	if not visible:
		return
	visible = false
	Sfx.play(&"ui_back")
	closed.emit()


# ---------------------------------------------------------------- data

func _load_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d := get_node_or_null(^"/root/Dialogue")
	if d and d.has_method(&"codex_entries"):
		for e: Variant in d.call(&"codex_entries"):
			if e is Dictionary:
				out.append(e)
	# Relic codex (progression role): one page per relic, its own tab.
	var prog := get_node_or_null(^"/root/Progression")
	if prog and prog.has_method(&"codex_entries"):
		for r: Variant in prog.call(&"codex_entries"):
			if not r is Dictionary:
				continue
			var known := bool(r.get("discovered", false))
			var text := str(r.get("description", ""))
			if known and int(r.get("times_found", 0)) > 0:
				text += "\n\n[color=#a08a7c]Found %d time%s.[/color]" % [int(r.times_found),
					"" if int(r.times_found) == 1 else "s"]
			out.append({"id": "relic:" + str(r.get("id", "")), "category": "Relics",
				"title": str(r.get("name", "")) if known else "???", "text": text if known else "",
				"unlocked": known, "is_new": false, "relic": r})
	return out


func _categories() -> Array[String]:
	var cats: Array[String] = []
	for e in _entries:
		var c := str(e.get("category", "Lore"))
		if not cats.has(c):
			cats.append(c)
	return cats


# ---------------------------------------------------------------- building

func _rebuild_tabs() -> void:
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	var cats := _categories()
	if not cats.has(_category):
		_category = cats[0] if not cats.is_empty() else ""
	_tabs.visible = cats.size() > 1
	for c in cats:
		var b := Button.new()
		b.theme_type_variation = &"TabButton"
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		var unread := 0
		for e in _entries:
			if str(e.get("category", "Lore")) == c and bool(e.get("is_new", false)):
				unread += 1
		b.text = c.to_upper() + ("  •%d" % unread if unread > 0 else "")
		b.set_meta(&"cat", c)
		b.set_pressed_no_signal(c == _category)
		b.pressed.connect(_select_tab.bind(c))
		Sfx.wire_button(b)
		_tabs.add_child(b)


func _cycle_tab(dir: int) -> void:
	var cats := _categories()
	if cats.size() < 2:
		return
	_select_tab(cats[posmod(cats.find(_category) + dir, cats.size())])


func _select_tab(cat: String) -> void:
	_category = cat
	for b: Button in _tabs.get_children():
		b.set_pressed_no_signal(str(b.get_meta(&"cat", "")) == cat)
	_selected = ""
	_rebuild_list()


func _rebuild_list() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_buttons.clear()
	var first: Button = null
	var first_open := ""
	for e in _entries:
		if str(e.get("category", "Lore")) != _category:
			continue
		var id := str(e.get("id", ""))
		var open_e := bool(e.get("unlocked", false))
		var b := Button.new()
		b.theme_type_variation = &"GhostButton"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.custom_minimum_size = Vector2(LIST_W - 30.0, 34.0)
		# A shape as well as a colour marks unread entries (colour-blind safe).
		b.text = ("◆ " if bool(e.get("is_new", false)) else "   ") + str(e.get("title", "???"))
		if not open_e:
			b.add_theme_color_override(&"font_color", UIPalette.SMOKE)
		elif bool(e.get("is_new", false)):
			b.add_theme_color_override(&"font_color", UIPalette.HELLFIRE)
		else:
			b.add_theme_color_override(&"font_color", UIPalette.BONE)
		b.focus_entered.connect(_show.bind(id))
		b.pressed.connect(_show.bind(id))
		b.mouse_entered.connect(Sfx.play.bind(&"ui_hover", 0.03, -6.0))
		_list.add_child(b)
		_buttons[id] = b
		if first == null:
			first = b
		if first_open == "" and open_e:
			first_open = id
	_empty.visible = _entries.is_empty()
	if _entries.is_empty():
		_show("")
		_back.grab_focus.call_deferred()
		return
	var pick := first_open if first_open != "" else str(_buttons.keys()[0]) if not _buttons.is_empty() else ""
	_show(pick)
	if _buttons.has(pick):
		(_buttons[pick] as Button).grab_focus.call_deferred()


func _show(id: String) -> void:
	if id == _selected and id != "":
		return
	_selected = id
	var e: Dictionary = {}
	for x in _entries:
		if str(x.get("id", "")) == id:
			e = x
	if e.is_empty():
		_title.text = "The Codex is silent"
		_cat.text = ""
		_text.text = "[i]Nothing has been written yet. Descend, and the pages will fill.[/i]"
		return
	_cat.text = str(e.get("category", "Lore")).to_upper()
	for c in _relic_slot.get_children():
		c.queue_free()
	_relic_slot.visible = e.has("relic")
	if e.has("relic"):
		var r: Dictionary = e.relic
		_relic_slot.add_child(RelicView.chip(r, 64.0))
		var tier := Label.new()
		tier.theme_type_variation = &"CaptionLabel"
		var rid := RelicView.rarity_id(r)
		tier.text = "%s %s" % [UIPalette.rarity_mark(rid), String(rid).to_upper()]
		tier.add_theme_color_override(&"font_color", UIPalette.rarity_color(rid))
		tier.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_relic_slot.add_child(tier)
	if not bool(e.get("unlocked", false)):
		_title.text = "???"
		_text.text = "[color=#6d5a50][i]This page is sealed. Its secret waits further down the road.[/i][/color]" \
			if not e.has("relic") else "[color=#6d5a50][i]Not yet found. Elites and bosses carry relics out of Heaven.[/i][/color]"
		return
	_title.text = str(e.get("title", ""))
	_text.text = str(e.get("text", ""))
	_text.scroll_to_line(0)
	if bool(e.get("is_new", false)):
		e["is_new"] = false
		var d := get_node_or_null(^"/root/Dialogue")
		if d and d.has_method(&"codex_mark_read"):
			d.call(&"codex_mark_read", id)
		var b: Button = _buttons.get(id)
		if b:
			b.text = "   " + str(e.get("title", ""))
			b.add_theme_color_override(&"font_color", UIPalette.BONE)


func _open_bestiary() -> void:
	if _bestiary == null or not is_instance_valid(_bestiary):
		var ps := load(BESTIARY_SCENE) as PackedScene
		if ps == null:
			return
		_bestiary = ps.instantiate() as CanvasLayer
		_bestiary.layer = layer + 1
		add_child(_bestiary)
		_bestiary.connect(&"closed", func() -> void: _back.grab_focus())
	_bestiary.call(&"open")


func _layout() -> void:
	var vp := _root.size
	var w := minf(PANEL_MAX.x, vp.x * 0.92)
	var h := minf(PANEL_MAX.y, vp.y * 0.88)
	_frame.size = Vector2.ZERO
	_frame.size = Vector2(w, h)
	_frame.position = (vp - _frame.size) * 0.5


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = load("res://ui/theme.tres") as Theme
	add_child(_root)
	_root.resized.connect(_layout)
	_dim = ColorRect.new()
	_dim.color = Color(0.03, 0.006, 0.004, 0.78)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_dim)

	_frame = PanelContainer.new()
	_frame.theme_type_variation = &"InfernalPanel"
	_root.add_child(_frame)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 10)
	_frame.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	var t := Label.new()
	t.theme_type_variation = &"TitleLabel"
	t.add_theme_font_size_override(&"font_size", 40)
	t.text = "CODEX"
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var sub := Label.new()
	sub.theme_type_variation = &"LoreLabel"
	sub.text = "What the damned remember, and what Heaven would rather forget."
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(sub)
	col.add_child(HSeparator.new())
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override(&"separation", 4)
	col.add_child(_tabs)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 16)
	col.add_child(body)
	var list_panel := PanelContainer.new()
	list_panel.theme_type_variation = &"InsetPanel"
	list_panel.custom_minimum_size.x = LIST_W
	body.add_child(list_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	list_panel.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 2)
	scroll.add_child(_list)

	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override(&"separation", 4)
	body.add_child(page)
	_cat = Label.new()
	_cat.theme_type_variation = &"CaptionLabel"
	page.add_child(_cat)
	_title = Label.new()
	_title.theme_type_variation = &"HeaderLabel"
	_title.add_theme_font_size_override(&"font_size", 30)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size.x = 200.0
	page.add_child(_title)
	page.add_child(UIPalette.rule(360.0, UIPalette.EMBER))
	_relic_slot = HBoxContainer.new()
	_relic_slot.add_theme_constant_override(&"separation", 12)
	_relic_slot.visible = false
	page.add_child(_relic_slot)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.custom_minimum_size = Vector2(200.0, 120.0)
	_text.add_theme_font_size_override(&"normal_font_size", 19)
	_text.add_theme_font_size_override(&"italics_font_size", 19)
	_text.add_theme_constant_override(&"line_separation", 4)
	page.add_child(_text)
	_empty = Label.new()
	_empty.theme_type_variation = &"LoreLabel"
	_empty.visible = false
	_empty.text = "No pages yet."
	page.add_child(_empty)

	var foot := HBoxContainer.new()
	col.add_child(foot)
	var hint := Label.new()
	hint.theme_type_variation = &"CaptionLabel"
	hint.text = "◆ UNREAD      Q / E  CATEGORY      ESC  CLOSE"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(hint)
	if ResourceLoader.exists(BESTIARY_SCENE):
		var best := Button.new()
		best.theme_type_variation = &"GhostButton"
		best.text = "BESTIARY"
		best.pressed.connect(_open_bestiary)
		Sfx.wire_button(best)
		foot.add_child(best)
	_back = Button.new()
	_back.text = "RETURN"
	_back.pressed.connect(close)
	Sfx.wire_button(_back, &"ui_back")
	foot.add_child(_back)
