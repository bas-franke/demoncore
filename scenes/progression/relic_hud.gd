extends CanvasLayer
## In-run Progression strip, bottom-left: Sin Shards / Hellstone collected this run, reroll and
## banish charges, and a row of owned relics (rarity-framed glyphs; hover for the name and text).
## Added to the run scene by Progression.apply_to_player (node name "ProgressionHud").

const CHIP := 30.0

var _shards: CurrencyCounter
var _stone: CurrencyCounter
var _charges: Label
var _relics: HBoxContainer


func _ready() -> void:
	layer = 5
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	root.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 26)
	add_child(root)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override(&"separation", 6)
	root.add_child(col)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 14)
	col.add_child(row)
	_shards = _counter(row, &"sin_shards")
	_stone = _counter(row, &"hellstone")
	_charges = Label.new()
	_charges.theme_type_variation = &"CaptionLabel"
	_charges.add_theme_color_override(&"font_color", UIPalette.ASH_TEXT)
	row.add_child(_charges)

	_relics = HBoxContainer.new()
	_relics.add_theme_constant_override(&"separation", 4)
	col.add_child(_relics)

	Progression.relic_gained.connect(_on_relic)
	Progression.run_loot_changed.connect(_on_loot)
	for id in Progression.run_relics:
		_on_relic(Progression.get_relic(StringName(id)))
	_refresh()


func _process(_delta: float) -> void:
	# Cheap: a couple of int compares per frame keeps reroll/banish charges current.
	var t := _charges_text()
	if _charges.text != t:
		_charges.text = t


func _counter(parent: Control, id: StringName) -> CurrencyCounter:
	var def := Progression.get_currency_def(id)
	var c := CurrencyCounter.new()
	c.font_size = 18
	c.setup(String(def.icon), def.color, String(def.name))
	parent.add_child(c)
	return c


func _refresh() -> void:
	_shards.set_amount(Progression.run_shards, true)
	_stone.set_amount(Progression.run_hellstone, true)
	_stone.visible = Progression.run_hellstone > 0
	_charges.text = _charges_text()


func _charges_text() -> String:
	var parts: PackedStringArray = []
	if Progression.rerolls_left > 0:
		parts.append("↻ %d" % Progression.rerolls_left)
	if Progression.banishes_left > 0:
		parts.append("✕ %d" % Progression.banishes_left)
	if Progression.run_heat > 0:
		parts.append("Heat %d" % Progression.run_heat)
	return "   ".join(parts)


func _on_loot(id: StringName, amount: int) -> void:
	if id == &"hellstone":
		_stone.visible = true
		_stone.set_amount(amount)
	else:
		_shards.set_amount(amount)


func _on_relic(r: Dictionary) -> void:
	if r.is_empty():
		return
	var tier := int(r.get("tier", 0))
	var col := Rarity.color(tier)
	var chip := PanelContainer.new()
	chip.theme_type_variation = &"Chip"
	chip.custom_minimum_size = Vector2(CHIP, CHIP)
	chip.self_modulate = col.lerp(Color.WHITE, 0.3)
	chip.tooltip_text = "%s (%s)\n%s" % [r.get("name", ""), Rarity.display_name(tier), r.get("description", "")]
	# Painted in code (UI role's GlyphIcon), so emoji icons never depend on the OS font.
	var l := GlyphIcon.new()
	l.glyph = String(r.get("icon", "?"))
	l.color = col
	chip.add_child(l)
	_relics.add_child(chip)
	chip.pivot_offset = Vector2(CHIP, CHIP) * 0.5
	chip.scale = Vector2(1.6, 1.6)
	chip.create_tween().tween_property(chip, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
