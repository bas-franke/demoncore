class_name HubLoadoutUI
extends CanvasLayer
## The hellgate's pre-run loadout window (Basecamp Hell): starting weapon (Player weapon pool,
## Progression weapon unlocks), starting rite (Abilities, Progression ability unlocks) and an
## optional keepsake (data/meta/keepsakes.json; given by an NPC at affinity >= its min_affinity,
## Dialogue offerings). Defaults to the last loadout (Meta.loadout). "Descend" emits
## `confirmed(choice)` with {weapon, ability, keepsake}; Esc / Back emits `closed`.

signal confirmed(choice: Dictionary)
signal closed

const PANEL_SIZE := Vector2(760.0, 560.0)

var _panel: PanelContainer
var _dim: ColorRect
var _road: Label
var _weapon: OptionButton
var _ability: OptionButton
var _keepsake: OptionButton
var _weapon_desc: Label
var _ability_desc: Label
var _keepsake_desc: Label
var _go: Button
var _weapons: Array[Dictionary] = []
var _abilities: Array[Dictionary] = []
var _keepsakes: Array[Dictionary] = []


func _ready() -> void:
	layer = 20
	visible = false
	_build()


func open() -> void:
	var m := Meta.get_map(Meta.selected_map)
	_road.text = "The road: %s" % String(m.get("name", "The Heavens"))
	_fill()
	visible = true
	Sfx.play(&"ui_click")
	_dim.modulate.a = 0.0
	_dim.create_tween().tween_property(_dim, "modulate:a", 1.0, 0.25)
	_panel.pivot_offset = _panel.size * 0.5
	var tw := _panel.create_tween()
	tw.tween_property(_panel, "modulate:a", 1.0, 0.25).from(0.0)
	tw.parallel().tween_property(_panel, "scale", Vector2.ONE, 0.3).from(Vector2(0.96, 0.96)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_go.grab_focus.call_deferred()


func close() -> void:
	if not visible:
		return
	visible = false
	Sfx.play(&"ui_back")
	closed.emit()


func is_open() -> bool:
	return visible


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause")):
		close()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- data

func _fill() -> void:
	var demon := Game.selected_character as DemonData
	if demon == null:
		demon = load(HubAvatar.DEFAULT_DEMON) as DemonData
	_weapon.clear()
	_weapons = [{"path": "", "name": "%s's own" % demon.display_name, "icon": "✦",
			"description": "The weapon this demon was summoned with.", "unlocked": true}]
	_weapons.append_array(RunLoadout.weapons())
	for w in _weapons:
		_add_item(_weapon, "%s  %s" % [w.icon, w.name] + ("" if w.unlocked else "   (sealed)"), not w.unlocked)
	_select(_weapon, _weapons, "path", Meta.loadout.weapon)

	_ability.clear()
	_abilities = [{"id": "", "name": "No rite", "icon": "–", "description": "Earn your rites in the field.",
			"unlocked": true, "school": ""}]
	_abilities.append_array(RunLoadout.abilities())
	for a in _abilities:
		var school := "   · %s" % String(a.school).capitalize() if String(a.school) != "" else ""
		_add_item(_ability, "%s  %s%s" % [a.icon, a.name, school] + ("" if a.unlocked else "   (sealed)"), not a.unlocked)
	_select(_ability, _abilities, "id", Meta.loadout.ability)

	_keepsake.clear()
	_keepsakes = [{"id": "", "name": "No keepsake", "icon": "–", "available": true,
			"description": "Gifts come to those who give. Make offerings (G) to the camp's folk."}]
	_keepsakes.append_array(RunLoadout.keepsakes())
	for k in _keepsakes:
		var lock := "" if k.available else "   (%s, affinity %d / %d)" % [k.giver_name, int(k.affinity), int(k.min_affinity)]
		_add_item(_keepsake, "%s  %s" % [k.icon, k.name] + lock, not k.available)
	_select(_keepsake, _keepsakes, "id", Meta.loadout.keepsake)
	_describe()


func _add_item(ob: OptionButton, text: String, disabled: bool) -> void:
	ob.add_item(text)
	ob.set_item_disabled(ob.item_count - 1, disabled)


## Selects the entry whose `key` equals `value` if it is still allowed, else the first.
func _select(ob: OptionButton, list: Array[Dictionary], key: String, value: String) -> void:
	ob.select(0)
	for i in list.size():
		if String(list[i].get(key, "")) == value and not ob.is_item_disabled(i):
			ob.select(i)


func _describe(_i: int = 0) -> void:
	_weapon_desc.text = String(_weapons[maxi(_weapon.selected, 0)].description)
	_ability_desc.text = String(_abilities[maxi(_ability.selected, 0)].description)
	var k: Dictionary = _keepsakes[maxi(_keepsake.selected, 0)]
	var from := "  (a gift from %s)" % k.giver_name if k.has("giver_name") else ""
	_keepsake_desc.text = String(k.description) + from


func _on_go() -> void:
	var choice := {
		"weapon": String(_weapons[maxi(_weapon.selected, 0)].path),
		"ability": String(_abilities[maxi(_ability.selected, 0)].id),
		"keepsake": String(_keepsakes[maxi(_keepsake.selected, 0)].id),
	}
	visible = false
	confirmed.emit(choice)


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
		margin.add_theme_constant_override("margin_" + side, 24)
	_panel.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 8)
	margin.add_child(col)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = "Before the Gate"
	title.add_theme_font_size_override(&"font_size", 34)
	title.add_theme_color_override(&"font_color", UIPalette.BRIMSTONE)
	col.add_child(title)
	_road = _label("", 17, UIPalette.ASH_TEXT)
	_road.theme_type_variation = &"LoreLabel"
	col.add_child(_road)
	col.add_child(HSeparator.new())
	_weapon = _section(col, "Weapon")
	_weapon_desc = _desc(col)
	_ability = _section(col, "Starting rite")
	_ability_desc = _desc(col)
	_keepsake = _section(col, "Keepsake")
	_keepsake_desc = _desc(col)
	for ob: OptionButton in [_weapon, _ability, _keepsake]:
		ob.item_selected.connect(_describe)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override(&"separation", 12)
	col.add_child(row)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(140.0, 48.0)
	back.pressed.connect(close)
	row.add_child(back)
	_go = Button.new()
	_go.text = "Descend"
	_go.theme_type_variation = &"AccentButton"
	_go.custom_minimum_size = Vector2(200.0, 48.0)
	_go.pressed.connect(_on_go)
	row.add_child(_go)


func _section(parent: Control, caption: String) -> OptionButton:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override(&"separation", 12)
	parent.add_child(hb)
	var l := _label(caption, 19, UIPalette.BONE)
	l.custom_minimum_size = Vector2(150.0, 0.0)
	hb.add_child(l)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.custom_minimum_size = Vector2(0.0, 40.0)
	ob.fit_to_longest_item = false
	hb.add_child(ob)
	return ob


func _desc(parent: Control) -> Label:
	var l := _label("", 15, UIPalette.ASH_TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(0.0, 40.0)
	parent.add_child(l)
	return l


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"InkLabel"
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_color", color)
	l.text = text
	return l
