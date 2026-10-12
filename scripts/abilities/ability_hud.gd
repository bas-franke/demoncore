extends CanvasLayer
## In-run ability display (added by the Abilities autoload when a run starts, as "AbilityHud"
## beside the main HUD).
## - Abilities go into the HUD's ability dock (hud.add_ability_slot / set_ability_cooldown, owned
##   by the UI role). Without a dock, a fallback row of gold-framed chips is drawn bottom centre.
## - Right edge: the Souls count (once a soul ability or weapon is held) and the active
##   synergies (hover for what they do). Same palette as scenes/ui/hud.gd.

const PARCHMENT := Color("d9cdb2")
const PALE_GOLD := Color("e8d6a6")
const GOLD := Color("c8a862")
const MUTED := Color("9c917c")
const CHIP := 48.0
const MARGIN := 26.0

## Below this cooldown a dock slot shows no sweep (auras and orbits would only flicker).
const MIN_SWEEP := 1.2

var _row: HBoxContainer
var _souls: Label
var _wrath: Label
var _greed: Label
var _girth: Label
var _dock: Node  # the main HUD, when it offers add_ability_slot()
var _dock_ranks := {}  # StringName -> int, last rank pushed to the dock
var _syn_box: VBoxContainer
var _chips := {}  # StringName -> Control
var _syn_rows := {}  # StringName -> Control


func _ready() -> void:
	layer = 4
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_row = HBoxContainer.new()
	_row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_row.offset_bottom = -MARGIN
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override(&"separation", 8)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_row)

	_syn_box = VBoxContainer.new()
	_syn_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_syn_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_syn_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_syn_box.offset_right = -MARGIN
	_syn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_syn_box.add_theme_constant_override(&"separation", 4)
	_syn_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_syn_box)
	_souls = _label("", 16, Color("ff6070"))
	_souls.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_souls.visible = false
	_souls.tooltip_text = "Soul-harvest stacks: one per angel slain this run. Soul abilities grow with them."
	_souls.mouse_filter = Control.MOUSE_FILTER_PASS
	_syn_box.add_child(_souls)
	_wrath = _resource_label(Color("ff4a2a"), "Wrath: builds as you are hurt or swarmed, drains when you are left alone.")
	_greed = _resource_label(Color("ffd040"), "Greed: Greed abilities hit harder for every Ichor you carry.")
	_girth = _resource_label(Color("c86a3a"), "Girth: one stack per angel devoured, each +2 max HP.")

	Abilities.synergy_activated.connect(_on_synergy_activated)


func _process(_delta: float) -> void:
	if _dock == null:
		var hud := get_tree().get_first_node_in_group(&"hud")
		if hud and hud.has_method(&"add_ability_slot"):
			_dock = hud
			# Ability keys (UI role's dock assigns ability_1..4): pressing one unleashes it early.
			var widgets: Object = hud.get(&"widgets")
			if widgets and widgets.has_signal(&"ability_key_pressed"):
				widgets.connect(&"ability_key_pressed", _on_ability_key_pressed)
	for id: StringName in Abilities.casters:
		var c := Abilities.casters[id] as AbilityCaster
		if not is_instance_valid(c):
			continue
		if is_instance_valid(_dock):
			_push_to_dock(id, c)
			continue
		var chip: Control = _chips.get(id)
		if chip == null:
			chip = _make_chip(c)
			_row.add_child(chip)
			_chips[id] = chip
			_pulse(chip)
		var veil := chip.get_meta(&"veil") as ColorRect
		var ready_ratio := c.cooldown_ratio()
		# Long cooldowns get a visible veil; auras/orbits (<1.2 s) would only flicker.
		veil.visible = c.get_cooldown() > 1.2
		veil.size = Vector2(CHIP, CHIP * (1.0 - ready_ratio))
		var lv := chip.get_meta(&"lv") as Label
		var rank := "✦" if c.is_max_level() else Upgrades.roman(c.level)
		if lv.text != rank:
			if lv.text != "":
				_pulse(chip)
			lv.text = rank
	# Evolved (replaced) abilities leave the dock / row.
	for id: StringName in _dock_ranks.keys():
		if not Abilities.casters.has(id):
			_dock_ranks.erase(id)
			if is_instance_valid(_dock):
				_dock.call(&"remove_ability_slot", id)
	for id: StringName in _chips.keys():
		if not Abilities.casters.has(id):
			(_chips[id] as Control).queue_free()
			_chips.erase(id)
	var show_souls := Abilities.owned_tags().has("soul")
	_souls.visible = show_souls
	if show_souls:
		_souls.text = "%d souls reaped  ❦" % Abilities.souls
	var tags := Abilities.owned_tags()
	_wrath.visible = tags.has("wrath")
	if _wrath.visible:
		_wrath.text = "%d wrath" % int(Abilities.wrath)
	_greed.visible = tags.has("greed")
	if _greed.visible:
		_greed.text = "greed x%.2f" % (1.0 + Abilities.greed() * 0.004)
	_girth.visible = Abilities.girth > 0
	if _girth.visible:
		_girth.text = "%d girth" % Abilities.girth


func _resource_label(color: Color, tip: String) -> Label:
	var l := _label("", 16, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.visible = false
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	_syn_box.add_child(l)
	return l


func _on_ability_key_pressed(id: StringName) -> void:
	var c := Abilities.get_caster(id)
	if c and not c.unleash():
		Sfx.play(&"ui_back", 0.0, -10.0)


func _push_to_dock(id: StringName, c: AbilityCaster) -> void:
	if int(_dock_ranks.get(id, 0)) != c.level:
		# Re-add on rank-up so the slot's title (tooltip) shows the new rank.
		if _dock_ranks.has(id):
			_dock.call(&"remove_ability_slot", id)
		_dock_ranks[id] = c.level
		var rank := "max" if c.is_max_level() else Upgrades.roman(c.level)
		_dock.call(&"add_ability_slot", id, "%s %s
%s" % [c.def.name, rank, c.def.desc], Icons.for_ability(c.def.id), c.def.icon, c.def.color)
	var total := c.get_cooldown()
	if total < MIN_SWEEP:
		_dock.call(&"set_ability_cooldown", id, 0.0, 0.0)
	else:
		_dock.call(&"set_ability_cooldown", id, maxf(c.cooldown_left, 0.0), total)


func _on_synergy_activated(id: StringName) -> void:
	if _syn_rows.has(id):
		return
	var s: Dictionary = Abilities.active_synergies.get(id, {})
	if _syn_rows.is_empty():
		var head := _label("SYNERGIES", 12, MUTED)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_syn_box.add_child(head)
	var color := Color.from_string(str(s.get("color", "#ffffff")), Color.WHITE)
	var l := _label("%s  %s" % [s.get("name", id), GlyphIcon.plain(str(s.get("icon", "✦")))], 15, color.lerp(PALE_GOLD, 0.35))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.tooltip_text = str(s.get("desc", ""))
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	_syn_box.add_child(l)
	_syn_rows[id] = l
	_pulse(l)


func _make_chip(c: AbilityCaster) -> Control:
	var chip := Control.new()
	chip.custom_minimum_size = Vector2(CHIP, CHIP)
	chip.tooltip_text = "%s\n%s" % [c.def.name, c.def.desc]
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.pivot_offset = Vector2(CHIP, CHIP) * 0.5
	var frame := Panel.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.034, 0.03, 0.88).lerp(Color(c.def.color, 1.0), 0.14)
	sb.border_color = Color(GOLD, 0.8)
	sb.set_border_width_all(1)
	sb.shadow_color = Color(c.def.color, 0.18)
	sb.shadow_size = 6
	frame.add_theme_stylebox_override(&"panel", sb)
	chip.add_child(frame)
	var tex := Icons.for_ability(c.def.id)  # painted icon (art-style), else the text glyph
	if tex:
		var row_tr := TextureRect.new()
		row_tr.texture = tex
		row_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		row_tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row_tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(row_tr)
	else:
		var glyph := _label(c.def.icon, 24, c.def.color.lerp(PALE_GOLD, 0.35))
		glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.add_theme_constant_override(&"outline_size", 5)
		chip.add_child(glyph)
	var veil := ColorRect.new()
	veil.color = Color(0.0, 0.0, 0.0, 0.62)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.position = Vector2.ZERO
	chip.add_child(veil)
	var lv := _label("", 11, PALE_GOLD)
	lv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lv.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	lv.offset_right = -3.0
	lv.offset_bottom = 2.0
	lv.add_theme_constant_override(&"outline_size", 4)
	chip.add_child(lv)
	chip.set_meta(&"veil", veil)
	chip.set_meta(&"lv", lv)
	return chip


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"InkLabel"
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = text
	return l


func _pulse(c: Control) -> void:
	c.modulate = Color(1.6, 1.4, 1.1, 0.0)
	var tw := c.create_tween()
	tw.tween_property(c, ^"modulate", Color.WHITE, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
