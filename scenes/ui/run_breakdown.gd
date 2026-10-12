class_name RunBreakdown
extends CanvasLayer
## End-of-run "full ledger" (UI role), opened from the run ledger on the end screen:
##   - Damage by source: each ability (Abilities.damage_report()), afflictions (DoT), effects and
##     synergies, and the weapons (all damage that is not an ability's: RunTally.total_damage minus
##     the ability total). Horizontal bars with share and amount.
##   - Kills by angel type (RunTally.kills_by_type), elites counted separately.
##   - Relics carried this run (Progression.run_relics), with painted icons and rarity pips.
## Works while paused; Esc / Return closes.

signal closed

const PANEL_MAX := Vector2(1160.0, 660.0)
const BAR_W := 230.0

var _root: Control
var _frame: PanelContainer
var _cols: HBoxContainer
var _back: Button


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func _input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause")):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	for c in _cols.get_children():
		_cols.remove_child(c)
		c.queue_free()
	_cols.add_child(_damage_column())
	_cols.add_child(VSeparator.new())
	_cols.add_child(_kills_column())
	_cols.add_child(VSeparator.new())
	_cols.add_child(_relics_column())
	visible = true
	_layout()
	Sfx.play(&"ui_click")
	_back.grab_focus.call_deferred()


func close() -> void:
	if not visible:
		return
	visible = false
	Sfx.play(&"ui_back")
	closed.emit()


# ---------------------------------------------------------------- columns

func _damage_column() -> Control:
	var col := _column("DAMAGE BY SOURCE")
	var rows: Array = []  # [label, amount, color]
	var ab := get_node_or_null(^"/root/Abilities")
	var ability_total := 0.0
	if ab and ab.has_method(&"damage_report"):
		var rep: Dictionary = ab.call(&"damage_report")
		var defs: Dictionary = ab.get(&"defs") if ab.get(&"defs") is Dictionary else {}
		for id: Variant in rep:
			var dmg := float((rep[id] as Array)[1])
			if dmg <= 0.0:
				continue
			ability_total += dmg
			var label := str(id).capitalize()
			var color := UIPalette.WRATH
			if str(id) == "dot":
				label = "Afflictions (over time)"
				color = UIPalette.VENOM
			elif str(id) == "effect":
				label = "Synergies & effects"
				color = UIPalette.HELLFIRE
			else:
				var def: Variant = defs.get(StringName(str(id)))
				if def != null:
					label = str(def.get(&"name"))
					var dc: Variant = def.get(&"color")
					if dc is Color:
						color = dc
			rows.append([label, dmg, color])
	var weapons := maxf(RunTally.total_damage - ability_total, 0.0)
	if weapons > 0.0:
		rows.append([_weapon_label(), weapons, UIPalette.BLOOD_BRIGHT])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	var total := 0.0
	for r: Array in rows:
		total += float(r[1])
	if rows.is_empty():
		col.add_child(_muted("No blood was spilled."))
	for r: Array in rows:
		col.add_child(_bar_row(str(r[0]), float(r[1]), total, r[2]))
	col.add_child(_spacer())
	col.add_child(_kv("Total damage", _fmt(total)))
	col.add_child(_kv("Heaviest blow", _fmt(RunTally.biggest_hit)))
	return col


func _weapon_label() -> String:
	var p := Game.player
	if p == null or not is_instance_valid(p) or p.weapons.is_empty():
		return "Weapons"
	var names: PackedStringArray = []
	for w in p.weapons:
		if is_instance_valid(w):
			names.append(w.display_name)
	return "Weapons (%s)" % ", ".join(names) if names.size() <= 2 else "Weapons (%d)" % names.size()


func _kills_column() -> Control:
	var col := _column("ANGELS SLAIN")
	var rows: Array = []
	for k: Variant in RunTally.kills_by_type:
		var v: Array = RunTally.kills_by_type[k]
		rows.append([str(k), int(v[0]), int(v[1])])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1]) > int(b[1]))
	if rows.is_empty():
		col.add_child(_muted("None fell to you."))
	var max_n := int(rows[0][1]) if not rows.is_empty() else 1
	for i in mini(rows.size(), 10):
		var r: Array = rows[i]
		var label := str(r[0]) + ("   ✠%d elite" % int(r[2]) if int(r[2]) > 0 else "")
		col.add_child(_bar_row(label, float(r[1]), float(max_n), UIPalette.HOLY_GOLD, false))
	if rows.size() > 10:
		col.add_child(_muted("…and %d more kinds" % (rows.size() - 10)))
	return col


func _relics_column() -> Control:
	var col := _column("RELICS CARRIED")
	var prog := get_node_or_null(^"/root/Progression")
	var ids: Array = prog.get(&"run_relics") if prog and prog.get(&"run_relics") is Array else []
	if ids.is_empty():
		col.add_child(_muted("You carried nothing holy out of Heaven."))
	for id: Variant in ids:
		var r: Dictionary = prog.call(&"get_relic", StringName(str(id)))
		if r.is_empty():
			continue
		col.add_child(RelicView.row(r))
	return col


# ---------------------------------------------------------------- pieces

func _column(title: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 6)
	var h := Label.new()
	h.theme_type_variation = &"HeaderLabel"
	h.add_theme_font_size_override(&"font_size", 18)
	h.text = title
	col.add_child(h)
	col.add_child(HSeparator.new())
	return col


func _bar_row(label: String, value: float, total: float, color: Color, show_share := true) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 1)
	var top := HBoxContainer.new()
	box.add_child(top)
	var l := Label.new()
	l.theme_type_variation = &"InkLabel"
	l.add_theme_font_size_override(&"font_size", 15)
	l.text = label
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 80.0
	top.add_child(l)
	var v := Label.new()
	v.theme_type_variation = &"ValueLabel"
	v.add_theme_font_size_override(&"font_size", 15)
	var share := (value / total * 100.0) if total > 0.0 else 0.0
	v.text = ("%s  %d%%" % [_fmt(value), roundi(share)]) if show_share else _fmt(value)
	top.add_child(v)
	var bar := InfernalBar.new()
	bar.custom_minimum_size = Vector2(BAR_W, 6.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.fill_color = color
	bar.trail_color = Color(0, 0, 0, 0)
	bar.ease_speed = 6.0
	bar.max_value = maxf(total, 1.0)
	bar.value = 0.0
	bar.snap()
	bar.value = value  # grows in
	box.add_child(bar)
	return box


func _kv(k: String, v: String) -> Control:
	var h := HBoxContainer.new()
	var a := Label.new()
	a.theme_type_variation = &"CaptionLabel"
	a.text = k.to_upper()
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(a)
	var b := Label.new()
	b.theme_type_variation = &"ValueLabel"
	b.add_theme_font_size_override(&"font_size", 16)
	b.text = v
	h.add_child(b)
	return h


func _muted(t: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"LoreLabel"
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 160.0
	return l


func _spacer() -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = 6.0
	return c


static func _fmt(v: float) -> String:
	if v >= 1_000_000.0:
		return "%.1fM" % (v / 1_000_000.0)
	if v >= 10_000.0:
		return "%.1fk" % (v / 1000.0)
	return str(roundi(v))


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
	dim.color = Color(0.02, 0.005, 0.004, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	_frame = PanelContainer.new()
	_frame.theme_type_variation = &"InfernalPanel"
	_root.add_child(_frame)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 10)
	_frame.add_child(col)
	var t := Label.new()
	t.theme_type_variation = &"TitleLabel"
	t.add_theme_font_size_override(&"font_size", 34)
	t.text = "THE FULL LEDGER"
	col.add_child(t)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_cols = HBoxContainer.new()
	_cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cols.add_theme_constant_override(&"separation", 18)
	scroll.add_child(_cols)
	_back = Button.new()
	_back.text = "RETURN"
	_back.size_flags_horizontal = Control.SIZE_SHRINK_END
	_back.pressed.connect(close)
	Sfx.wire_button(_back, &"ui_back")
	col.add_child(_back)
