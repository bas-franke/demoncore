class_name HubShopUI
extends CanvasLayer
## Basecamp Hell list window for the things that are choices rather than purchases (upgrade shops
## use the UI role's ShopPanel instead). Built in code. Modes:
##   open_maps()   - the cartographer's roads (Maps registry): choose / unseal the next hunt's map
##   open_pacts()  - the Covenant: raise / lower Progression heat pacts for harder, richer runs
##   open_rites()  - the Proving Pit: bind up to MAX_RITES abilities to try on the training dummies
## Esc / E / gamepad B closes it. Emits `closed`.

signal closed
signal map_chosen(id: StringName)
signal pacts_changed
## The player bound these ability ids and asked to enter the Proving Pit.
signal rites_chosen(ids: Array)

const PANEL_SIZE := Vector2(820.0, 560.0)
## The Maps autoload script, for its static helpers (calling them through the autoload instance
## triggers the "static called on instance" warning).
const MapsScript := preload("res://autoload/maps.gd")
## Abilities that can be bound at once for the Proving Pit.
const MAX_RITES := 3

var _mode := ""
var _dim: ColorRect
var _panel: PanelContainer
var _name: Label
var _title: Label
var _greeting: Label
var _wallet: Label
var _summary: Label
var _list: VBoxContainer
var _footer: Label
var _accent := UIPalette.EMBER
var _rites: Array[StringName] = []


func _ready() -> void:
	layer = 20
	visible = false
	_build()
	Meta.souls_changed.connect(func(_t: int) -> void: _update_wallet())


func open_maps() -> void:
	_mode = "maps"
	_open("cartographer")


func open_pacts() -> void:
	_mode = "pacts"
	_open("covenant")


func open_rites() -> void:
	_mode = "rites"
	_open("pit")


func close() -> void:
	if not visible:
		return
	visible = false
	Sfx.play(&"ui_back")
	closed.emit()


func is_open() -> bool:
	return visible


func _open(shop_id: String) -> void:
	var shop: Dictionary = Meta.shops.get(shop_id, {})
	_accent = Color.from_string(String(shop.get("color", "")), UIPalette.EMBER)
	_name.text = String(shop.get("name", shop_id.capitalize()))
	_name.add_theme_color_override(&"font_color", _accent.lerp(UIPalette.BONE_BRIGHT, 0.35))
	_title.text = String(shop.get("title", ""))
	_greeting.text = "“%s”" % String(shop.get("greeting", ""))
	var sb := _panel.get_theme_stylebox(&"panel").duplicate() as StyleBox
	if sb is StyleBoxFlat:
		(sb as StyleBoxFlat).border_color = _accent.darkened(0.25)
	_panel.add_theme_stylebox_override(&"panel", sb)
	_footer.text = {
		"maps": "Esc  leave        The hellgate opens onto the chosen road.",
		"pacts": "Esc  leave        Pacts take hold from your next descent.",
		"rites": "Esc  leave        In the pit, Esc or E climbs back out.",
	}.get(_mode, "Esc  leave")
	_rebuild()
	visible = true
	Sfx.play(&"ui_click")
	_panel.pivot_offset = _panel.size * 0.5
	var tw := _panel.create_tween()
	tw.tween_property(_panel, "modulate:a", 1.0, 0.25).from(0.0)
	tw.parallel().tween_property(_panel, "scale", Vector2.ONE, 0.3).from(Vector2(0.96, 0.96)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_dim.modulate.a = 0.0
	_dim.create_tween().tween_property(_dim, "modulate:a", 1.0, 0.25)
	_focus_first.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause") \
			or event.is_action_pressed(&"interact"):
		close()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- building

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
		margin.add_theme_constant_override("margin_" + side, 22)
	_panel.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 6)
	margin.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override(&"separation", 0)
	head.add_child(names)
	_name = Label.new()
	_name.theme_type_variation = &"TitleLabel"
	_name.add_theme_font_size_override(&"font_size", 34)
	names.add_child(_name)
	_title = _label("", 17, UIPalette.ASH_TEXT)
	_title.theme_type_variation = &"LoreLabel"
	names.add_child(_title)
	_wallet = _label("", 22, UIPalette.SOUL)
	_wallet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_wallet.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(_wallet)

	_greeting = _label("", 17, UIPalette.BONE)
	_greeting.theme_type_variation = &"LoreLabel"
	_greeting.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_greeting)
	_summary = _label("", 17, UIPalette.BRIMSTONE)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_summary)
	col.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 8)
	scroll.add_child(_list)

	_footer = _label("", 15, UIPalette.SMOKE)
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_footer)


func _rebuild() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_update_wallet()
	_summary.visible = false
	if _mode == "maps":
		for m in Meta.get_maps():
			_list.add_child(_map_row(m))
	elif _mode == "pacts":
		var prog := get_node_or_null(^"/root/Progression")
		if prog == null or (prog.get(&"pact_defs") as Array).is_empty():
			_list.add_child(_label("No pacts are offered yet. Heaven has not earned your contempt.", 18,
					UIPalette.ASH_TEXT))
			return
		_summary.visible = true
		_update_heat_summary(prog)
		for d: Dictionary in prog.get(&"pact_defs"):
			_list.add_child(_pact_row(prog, d))
	elif _mode == "rites":
		_rebuild_rites()


func _map_row(m: Dictionary) -> Control:
	var id := StringName(m.id)
	var row := _row_frame()
	var hb := row.get_child(0).get_child(0) as HBoxContainer
	var chosen := Meta.selected_map == id
	var unlocked := Meta.is_map_unlocked(id)
	var tint := MapsScript.color_of(m.get("portal", {}).get("color", null), _accent) if m.has("portal") else _accent

	hb.add_child(_glyph("◉" if chosen else ("○" if unlocked else "✖"),
			tint if chosen else (UIPalette.BONE if unlocked else UIPalette.LOCKED)))
	var text := _text_column(hb)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override(&"separation", 10)
	text.add_child(name_row)
	name_row.add_child(_label(String(m.get("name", id)), 20, UIPalette.BONE_BRIGHT if unlocked else UIPalette.ASH_TEXT))
	if String(m.get("subtitle", "")) != "":
		var sub := _label(String(m.subtitle), 15, UIPalette.ASH_TEXT)
		sub.theme_type_variation = &"LoreLabel"
		sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_row.add_child(sub)
	var desc := _label(String(m.get("description", "")), 16, UIPalette.ASH_TEXT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(desc)
	var peril := int(m.get("difficulty", 0))
	if peril > 0:
		text.add_child(_label("Peril  " + "✠".repeat(peril), 15, UIPalette.BRIMSTONE_DIM))
	var req := Meta.map_requirement(id)
	if not unlocked and req != "":
		text.add_child(_label(req, 15, UIPalette.DANGER))

	var btn := _button()
	if chosen:
		btn.text = "Chosen"
		btn.disabled = true
	elif unlocked:
		btn.text = "Choose"
		btn.theme_type_variation = &"AccentButton"
		btn.pressed.connect(_on_choose_map.bind(id))
	else:
		btn.text = "Unseal  ✧%d" % Meta.map_cost(id)
		btn.theme_type_variation = &"AccentButton"
		btn.disabled = Meta.souls < Meta.map_cost(id) or req != ""
		btn.pressed.connect(_on_unlock_map.bind(id))
	hb.add_child(btn)
	return row


func _pact_row(prog: Node, d: Dictionary) -> Control:
	var id := StringName(d.id)
	var rank := int(prog.call(&"get_pact_rank", id))
	var max_rank := int(d.get("max_rank", 1))
	var row := _row_frame()
	var hb := row.get_child(0).get_child(0) as HBoxContainer
	hb.add_child(_glyph(String(d.get("icon", "✠")), _accent if rank > 0 else UIPalette.ASH_TEXT))
	var text := _text_column(hb)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override(&"separation", 10)
	text.add_child(name_row)
	name_row.add_child(_label(String(d.get("name", id)), 20, UIPalette.BONE_BRIGHT))
	var pips := _label("◆".repeat(rank) + "◇".repeat(max_rank - rank), 15,
			UIPalette.BLOOD_BRIGHT if rank > 0 else UIPalette.SMOKE)
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(pips)
	var heat := _label("+%d heat / rank" % int(d.get("heat_per_rank", 1)), 14, UIPalette.SMOKE)
	heat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(heat)
	var desc := _label(String(d.get("description", "")), 16, UIPalette.ASH_TEXT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(desc)

	var minus := _button()
	minus.custom_minimum_size = Vector2(52.0, 48.0)
	minus.text = "−"
	minus.disabled = rank <= 0
	minus.pressed.connect(_on_pact.bind(prog, id, rank - 1))
	hb.add_child(minus)
	var plus := _button()
	plus.custom_minimum_size = Vector2(52.0, 48.0)
	plus.text = "+"
	plus.theme_type_variation = &"AccentButton"
	plus.disabled = rank >= max_rank
	plus.pressed.connect(_on_pact.bind(prog, id, rank + 1))
	hb.add_child(plus)
	return row


## The Proving Pit: a "descend" row, then every ability the player may use (Abilities registry,
## filtered by Progression unlocks) with a Bind / Unbind toggle.
func _rebuild_rites() -> void:
	var ab := get_node_or_null(^"/root/Abilities")
	if ab == null:
		_list.add_child(_label("No rites are known in this age.", 18, UIPalette.ASH_TEXT))
		return
	var prog := get_node_or_null(^"/root/Progression")
	_summary.visible = true
	var names: PackedStringArray = []
	var defs: Dictionary = ab.get(&"defs")
	for id in _rites:
		names.append(String((defs[id] as AbilityDef).name) if defs.has(id) else String(id))
	_summary.text = "Bound (%d / %d): %s" % [_rites.size(), MAX_RITES, ", ".join(names) if not names.is_empty()
			else "nothing yet. Your weapons alone will do the talking."]
	var go_row := _row_frame()
	var go_hb := go_row.get_child(0).get_child(0) as HBoxContainer
	go_hb.add_child(_glyph("⛧", _accent))
	var go_text := _text_column(go_hb)
	go_text.add_child(_label("Descend into the Proving Pit", 20, UIPalette.BONE_BRIGHT))
	go_text.add_child(_label("Straw angels on stakes. They feel nothing and never fall.", 16, UIPalette.ASH_TEXT))
	var go := _button()
	go.text = "Enter"
	go.theme_type_variation = &"AccentButton"
	go.pressed.connect(func() -> void:
		var row_ids: Array = _rites.duplicate()
		close()
		rites_chosen.emit(row_ids))
	go_hb.add_child(go)
	_list.add_child(go_row)
	var ids: Array = defs.keys()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		var da := defs[a] as AbilityDef
		var db := defs[b] as AbilityDef
		return da.school + da.name < db.school + db.name)
	for id: StringName in ids:
		var d := defs[id] as AbilityDef
		var locked := prog != null and not bool(prog.call(&"is_ability_unlocked", id))
		var row := _row_frame()
		var hb := row.get_child(0).get_child(0) as HBoxContainer
		hb.add_child(_glyph(d.icon, d.color if not locked else UIPalette.LOCKED))
		var text := _text_column(hb)
		var name_row := HBoxContainer.new()
		name_row.add_theme_constant_override(&"separation", 10)
		text.add_child(name_row)
		name_row.add_child(_label(d.name, 19, UIPalette.BONE_BRIGHT if not locked else UIPalette.ASH_TEXT))
		var school := _label(d.school.capitalize(), 14, UIPalette.SMOKE)
		school.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_row.add_child(school)
		var desc := _label(d.desc if not locked else "Sealed. Unlock it in the camp first.", 15, UIPalette.ASH_TEXT)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(desc)
		var btn := _button()
		btn.custom_minimum_size = Vector2(120.0, 44.0)
		var bound := _rites.has(id)
		btn.text = "Unbind" if bound else "Bind"
		if not bound:
			btn.theme_type_variation = &"AccentButton"
		btn.disabled = locked or (not bound and _rites.size() >= MAX_RITES)
		btn.pressed.connect(_on_rite.bind(id))
		hb.add_child(btn)
		_list.add_child(row)


func _on_rite(id: StringName) -> void:
	if _rites.has(id):
		_rites.erase(id)
		Sfx.play(&"ui_back")
	elif _rites.size() < MAX_RITES:
		_rites.append(id)
		Sfx.play(&"cast", 0.05, -8.0)
	_rebuild_keep_focus()


## PanelContainer > MarginContainer > HBoxContainer, for one list entry.
func _row_frame() -> PanelContainer:
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UIPalette.SCORCH
	sb.border_color = UIPalette.IRON
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	row.add_theme_stylebox_override(&"panel", sb)
	var m := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 8)
	row.add_child(m)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override(&"separation", 12)
	m.add_child(hb)
	return row


func _text_column(parent: Control) -> VBoxContainer:
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override(&"separation", 0)
	parent.add_child(text)
	return text


func _glyph(g: String, color: Color) -> Label:
	var icon := _label(g, 28, color)
	icon.custom_minimum_size = Vector2(44.0, 0.0)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return icon


func _button() -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(170.0, 48.0)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.mouse_entered.connect(_hover)
	btn.focus_entered.connect(_hover)
	return btn


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"InkLabel"
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_color", color)
	l.text = text
	return l


# ---------------------------------------------------------------- actions

func _on_choose_map(id: StringName) -> void:
	if Meta.select_map(id):
		Sfx.play(&"select")
		map_chosen.emit(id)
		_rebuild_keep_focus()


func _on_unlock_map(id: StringName) -> void:
	if Meta.unlock_map(id):
		Sfx.play(&"unlock", 0.02)
		Meta.select_map(id)
		map_chosen.emit(id)
		_rebuild_keep_focus()
	else:
		Sfx.play(&"shop_deny")


func _on_pact(prog: Node, id: StringName, rank: int) -> void:
	prog.call(&"set_pact_rank", id, rank)
	Sfx.play(&"toll" if rank > 0 else &"ui_click", 0.05, -6.0)
	pacts_changed.emit()
	_rebuild_keep_focus()


func _update_heat_summary(prog: Node) -> void:
	var heat := int(prog.call(&"get_heat"))
	var r: Dictionary = prog.call(&"heat_rewards", heat)
	if heat <= 0:
		_summary.text = "Heat 0  ·  no pacts sworn. Swear one and Heaven will hunt you harder, and pay more."
	else:
		_summary.text = "Heat %d  ·  +%d%% Souls  ·  +%d%% Sin Shards  ·  +%d Hellstone on a worthy run" % [
			heat, roundi(float(r.soul_bonus) * 100.0), roundi(float(r.shard_bonus) * 100.0), int(r.hellstone)]


## Rebuilds the list, then puts focus back on the same row (or the first usable button).
func _rebuild_keep_focus() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	var index := -1
	var sub := 0
	if focused:
		for i in _list.get_child_count():
			if _list.get_child(i).is_ancestor_of(focused):
				index = i
				sub = _buttons(_list.get_child(i)).find(focused)
	_rebuild()
	await get_tree().process_frame
	if index >= 0 and index < _list.get_child_count():
		var bs := _buttons(_list.get_child(index))
		for k in range(maxi(sub, 0), bs.size()) + range(0, maxi(sub, 0)):
			if not bs[k].disabled:
				bs[k].grab_focus()
				return
	_focus_first()


func _focus_first() -> void:
	for row in _list.get_children():
		for b in _buttons(row):
			if not b.disabled:
				b.grab_focus()
				return


func _buttons(n: Node) -> Array[Button]:
	var out: Array[Button] = []
	if n is Button:
		out.append(n as Button)
	for c in n.get_children():
		out.append_array(_buttons(c))
	return out


func _update_wallet() -> void:
	if _wallet == null:
		return
	var text := "✧ %d Souls" % Meta.souls
	var prog := get_node_or_null(^"/root/Progression")
	if prog and _mode == "pacts":
		var sd: Dictionary = prog.call(&"get_currency_def", &"sin_shards")
		text += "    %s %d" % [String(sd.get("icon", "◆")), int(prog.call(&"get_currency", &"sin_shards"))]
	_wallet.text = text


func _hover() -> void:
	Sfx.play(&"ui_hover", 0.03)
