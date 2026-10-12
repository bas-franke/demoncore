class_name RunLedger
extends VBoxContainer
## "Ledger of the run" block for the end-of-run screen (game_over.gd adds it above the buttons):
##   - souls banked at Basecamp (Meta.pending_summary) with the reward breakdown, counting up
##   - secondary tallies from RunState.last_result: elites, bosses, damage taken, dodges
##   - the demon's powers and boons as small framed icons with their ranks
## Every source is optional (duck-typed autoload lookups), so it works in any scene.

const ICON := 34.0

## The "full ledger" button (focusable with keyboard / pad like the end-screen buttons).
var details_button: Button
var _breakdown: RunBreakdown
var _souls_label: Label
var _souls_target := 0
var _souls_shown := 0.0
## Seconds before the soul count starts rolling (the end screen fades the details in late).
var count_delay := 3.2
var _delay := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", 10)
	alignment = BoxContainer.ALIGNMENT_CENTER


func _process(delta: float) -> void:
	if _souls_label == null or _souls_shown >= _souls_target:
		return
	if _delay > 0.0:
		_delay -= delta
		return
	_souls_shown = minf(_souls_target, _souls_shown + maxf(_souls_target * 0.6, 20.0) * delta)
	_souls_label.text = "◈ %d" % int(_souls_shown)
	if int(_souls_shown) >= _souls_target:
		Sfx.play(&"coin", 0.05)


## Rebuilds the ledger from the run result (RunState.last_result) and Meta's banked summary.
func fill(result: Dictionary) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_souls_label = null

	var meta := get_node_or_null(^"/root/Meta")
	var summary: Dictionary = meta.get(&"pending_summary") if meta and meta.get(&"pending_summary") is Dictionary else {}
	if not summary.is_empty():
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override(&"separation", 14)
		add_child(row)
		var cap := _label("SOULS BANKED", &"CaptionLabel", 15, UIPalette.ASH_TEXT)
		cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(cap)
		_souls_target = int(summary.get("souls", 0))
		_souls_shown = 0.0
		_delay = count_delay
		_souls_label = _label("◈ 0", &"CostLabel", 30, UIPalette.SOUL)
		row.add_child(_souls_label)
		var mult := float(summary.get("multiplier", 1.0))
		var detail := "base %d" % int(summary.get("base", 0))
		if mult > 1.001:
			detail += "  ×%.2f" % mult
		if int(summary.get("ichor", 0)) > 0:
			detail += "  ·  %d ichor carried" % int(summary.get("ichor", 0))
		var d := _label(detail, &"LoreLabel", 15, UIPalette.ASH_TEXT)
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(d)

	# Progression: Sin Shards / Hellstone banked, heat bonus, relics found (docs/team/progression.md).
	var prog := get_node_or_null(^"/root/Progression")
	if prog and String(prog.call(&"rewards_text")) != "":
		var pc: Color = (prog.call(&"get_currency_def", &"sin_shards") as Dictionary).get("color", UIPalette.EMBER)
		var pl := _label(String(prog.call(&"rewards_text")), &"ValueLabel", 17, pc.lerp(UIPalette.BONE_BRIGHT, 0.35))
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(pl)

	# Objectives role (scenes/objectives/run_score.gd): the run's grade, score and objective tally.
	var obj: Dictionary = result.get("objectives", {}) if result.get("objectives", {}) is Dictionary else {}
	if not obj.is_empty():
		var line := "GRADE %s   ·   score %d   ·   %d objectives" % [str(obj.get("grade", "D")),
				int(obj.get("score", 0)), int(obj.get("completed", 0))]
		if int(obj.get("events", 0)) > 0:
			line += "  ·  %d events survived" % int(obj.get("events", 0))
		if int(obj.get("bonus_souls", 0)) > 0:
			line += "   (+%d souls)" % int(obj.get("bonus_souls", 0))
		var gl := _label(line, &"ValueLabel", 18, UIPalette.BRIMSTONE)
		gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(gl)

	var tallies := HBoxContainer.new()
	tallies.alignment = BoxContainer.ALIGNMENT_CENTER
	tallies.add_theme_constant_override(&"separation", 26)
	var pairs := [
		["elites", "Exalted slain"], ["bosses", "Heralds felled"], ["dodges", "Blows evaded"],
	]
	for pair: Array in pairs:
		if result.has(pair[0]) and int(result[pair[0]]) > 0:
			tallies.add_child(_tally(str(int(result[pair[0]])), pair[1]))
	if float(result.get("damage_taken", 0.0)) > 0.0:
		tallies.add_child(_tally(str(roundi(float(result.damage_taken))), "Wounds taken"))
	if tallies.get_child_count() > 0:
		add_child(tallies)

	var powers := _powers_row()
	if powers.get_child_count() > 0:
		add_child(powers)

	# Deep-dive: damage per source, kills per angel type, relics (scenes/ui/run_breakdown.gd).
	var more := Button.new()
	more.theme_type_variation = &"GhostButton"
	more.text = "◆  FULL LEDGER"
	more.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	more.pressed.connect(_open_breakdown)
	Sfx.wire_button(more)
	add_child(more)
	details_button = more


func _open_breakdown() -> void:
	if _breakdown == null:
		_breakdown = RunBreakdown.new()
		add_child(_breakdown)
		_breakdown.closed.connect(func() -> void:
			if is_instance_valid(details_button):
				details_button.grab_focus())
	_breakdown.open()


func _tally(value: String, caption: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 6)
	h.add_child(_label(value, &"ValueLabel", 18, UIPalette.BONE_BRIGHT))
	var c := _label(caption, &"LoreLabel", 15, UIPalette.ASH_TEXT)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(c)
	return h


func _powers_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 6)
	var p := Game.player
	if p == null or not is_instance_valid(p):
		return row
	for w in p.weapons:
		if is_instance_valid(w):
			row.add_child(_chip(Icons.for_weapon(w), w.icon, w.color,
				"✦" if w.is_max_level() else UIPalette.roman(w.level), w.display_name))
	if not p.passive_levels.is_empty() and row.get_child_count() > 0:
		var sep := VSeparator.new()
		sep.custom_minimum_size = Vector2(10.0, ICON)
		row.add_child(sep)
	for pd: PassiveData in p.passive_levels:
		var lv: int = p.passive_levels[pd]
		if lv > 0:
			row.add_child(_chip(Icons.for_passive(pd), pd.icon, pd.color,
				"✦" if lv >= pd.max_level else UIPalette.roman(lv), pd.display_name))
	return row


func _chip(tex: Texture2D, glyph: String, tint: Color, rank: String, tip: String) -> Control:
	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(ICON, ICON)
	chip.tooltip_text = tip
	var sb := UIPalette.box(UIPalette.SCORCH.lerp(tint, 0.12), Color(UIPalette.BRIMSTONE_DIM, 0.8), 1, 2, 1.0)
	chip.add_theme_stylebox_override(&"panel", sb)
	if tex:
		var art := TextureRect.new()
		art.texture = tex
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		chip.add_child(art)
	else:
		var g := GlyphIcon.new()
		g.glyph = glyph
		g.color = tint.lerp(UIPalette.BONE_BRIGHT, 0.4)
		chip.add_child(g)
	var lv := _label(rank, &"ValueLabel", 11, UIPalette.BONE_BRIGHT)
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lv.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	chip.add_child(lv)
	return chip


func _label(text: String, variation: StringName, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = text
	return l
