extends CanvasLayer
## "Respite". Esc / Start toggles pause (ignored while another menu has paused the game).
## Also lists the demon's powers and attributes.

const DEMON_SELECT_SCENE := "res://scenes/menu/demon_select.tscn"
const SETTINGS_SCENE := "res://scenes/ui/settings_menu.tscn"
## Colours from the shared infernal palette (ui/palette.gd).
const PARCHMENT := UIPalette.BONE
const PALE_GOLD := UIPalette.BONE_BRIGHT
const GOLD := UIPalette.BRIMSTONE
const MUTED := UIPalette.ASH_TEXT

@onready var resume_button: Button = %Resume
@onready var center: Control = %Center
@onready var dim: ColorRect = $Root/Dim
@onready var title: Label = %Title
@onready var weapons_box: VBoxContainer = %Weapons
@onready var stats_grid: GridContainer = %StatsGrid
@onready var settings_button: Button = %SettingsButton

var _settings: CanvasLayer
var _syn_box: VBoxContainer  # active synergies, built on first open
var _relic_box: VBoxContainer  # relics carried this run (Progression.run_relics)
var _codex_button: Button
var _codex: CodexScreen


func _ready() -> void:
	visible = false
	resume_button.pressed.connect(close)
	%Restart.pressed.connect(_on_restart)
	%ChangeDemon.pressed.connect(_on_change_demon)
	(%ChangeDemon as Button).text = "Abandon Run"
	%Quit.pressed.connect(get_tree().quit)
	settings_button.pressed.connect(_on_settings)
	for b: Button in [resume_button, settings_button, %Restart, %ChangeDemon, %Quit]:
		b.mouse_entered.connect(_hover)
		b.focus_entered.connect(_hover)
		if b != resume_button and b != settings_button:
			b.pressed.connect(Sfx.play.bind(&"ui_click", 0.03, 0.0))
	# Codex (lore, scenes/ui/codex_screen.gd) right under Settings.
	_codex_button = Button.new()
	_codex_button.custom_minimum_size = settings_button.custom_minimum_size
	_codex_button.theme_type_variation = settings_button.theme_type_variation
	_codex_button.text = "Codex"
	settings_button.add_sibling(_codex_button)
	_codex_button.pressed.connect(_on_codex)
	_codex_button.mouse_entered.connect(_hover)
	_codex_button.focus_entered.connect(_hover)


func _input(event: InputEvent) -> void:
	# Keyboard / pad: if a mouse click left nothing focused, the next direction refocuses Resume.
	if visible and not (_settings and _settings.visible) and not (_codex and _codex.visible):
		UINav.recover_focus(event, resume_button)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause"):
		return
	if _settings and _settings.visible:
		return  # the settings overlay handles its own Esc
	if _codex and _codex.visible:
		return
	if visible:
		close()
	elif not get_tree().paused:
		open()
	get_viewport().set_input_as_handled()


func open() -> void:
	_fill_stats()
	_refresh_codex_label()
	_fill_run_line()
	_fit_to_screen.call_deferred()
	visible = true
	Sfx.play(&"ui_click")
	get_tree().paused = true
	resume_button.grab_focus()

	var dt := dim.create_tween()
	dt.tween_property(dim, "modulate:a", 1.0, 0.45).from(0.0).set_trans(Tween.TRANS_SINE)
	center.pivot_offset = center.size * 0.5
	var tw := center.create_tween()
	tw.tween_property(center, "modulate:a", 1.0, 0.45).from(0.0).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(center, "scale", Vector2.ONE, 0.6).from(Vector2(1.015, 1.015)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func close() -> void:
	if _settings and _settings.visible:
		_settings.call(&"close")
	if _codex and _codex.visible:
		_codex.close()
	visible = false
	get_tree().paused = false
	Sfx.play(&"ui_back")


func _hover() -> void:
	Sfx.play(&"ui_hover", 0.03)


func _on_codex() -> void:
	Sfx.play(&"ui_click", 0.03)
	if _codex == null:
		_codex = CodexScreen.new()
		add_child(_codex)
		_codex.closed.connect(func() -> void:
			_refresh_codex_label()
			if visible:
				_codex_button.grab_focus())
	_codex.open()


## "Codex  ◆2" when unread pages wait (the shape keeps it readable without colour).
func _refresh_codex_label() -> void:
	var n := CodexScreen.new_count()
	_codex_button.text = "Codex  ◆%d" % n if n > 0 else "Codex"


func _on_settings() -> void:
	Sfx.play(&"ui_click", 0.03)
	if _settings == null:
		var scene := load(SETTINGS_SCENE) as PackedScene
		if scene == null:
			return
		_settings = scene.instantiate() as CanvasLayer
		add_child(_settings)
		_settings.connect(&"closed", _on_settings_closed)
	_settings.call(&"open")


func _on_settings_closed() -> void:
	if visible:
		settings_button.grab_focus()


func _on_restart() -> void:
	RunState.restart_run()


## "Abandon Run": ends the run (cause &"abandoned", Ichor still carried home) and returns to
## Basecamp Hell via RunState.
func _on_change_demon() -> void:
	RunState.return_to_basecamp()


## Subtitle: where and how deep into the run we are ("The Ruined Sanctum · 04:12 · 37 Ichor").
func _fill_run_line() -> void:
	var sub := get_node_or_null(^"Root/Center/VBox/Subtitle") as Label
	if sub == null:
		return
	var parts: PackedStringArray = []
	var maps := get_node_or_null(^"/root/Maps")
	if maps:
		var def: Variant = maps.call(&"get_def", maps.get(&"selected_id"))
		if def is Dictionary and str(def.get("name", "")) != "":
			parts.append(str(def.name))
	parts.append(TextFormat.clock(Game.elapsed))
	var rs := get_node_or_null(^"/root/RunState")
	if rs:
		parts.append("%d %s" % [int(rs.get(&"currency")), str(rs.get(&"CURRENCY_NAME"))])
	sub.text = "  ·  ".join(parts)


## Scales the menu down when the window (or a large UI scale) leaves too little room.
func _fit_to_screen() -> void:
	var box := center.get_child(0) as Control
	if box == null:
		return
	var avail := get_viewport().get_visible_rect().size * Vector2(0.94, 0.92)
	var need := box.get_combined_minimum_size()
	var k := minf(1.0, minf(avail.x / maxf(need.x, 1.0), avail.y / maxf(need.y, 1.0)))
	box.pivot_offset = need * 0.5
	box.scale = Vector2(k, k)


func _fill_stats() -> void:
	for c in weapons_box.get_children():
		weapons_box.remove_child(c)
		c.queue_free()
	for c in stats_grid.get_children():
		stats_grid.remove_child(c)
		c.queue_free()
	var p := Game.player
	if p == null or not is_instance_valid(p):
		return

	if p.weapons.is_empty():
		var none := _label("No power yet answers thee.", 17, MUTED)
		none.theme_type_variation = &"LoreLabel"
		weapons_box.add_child(none)
	for w in p.weapons:
		if not is_instance_valid(w):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 10)
		var tex := Icons.for_weapon(w)
		if tex:
			var art := TextureRect.new()
			art.texture = tex
			art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			art.custom_minimum_size = Vector2(30.0, 30.0)
			row.add_child(art)
		else:
			var icon := GlyphIcon.new()  # painted in code, no emoji font
			icon.glyph = w.icon
			icon.color = w.color.lerp(PALE_GOLD, 0.5)
			icon.custom_minimum_size = Vector2(26.0, 26.0)
			row.add_child(icon)
		var name_label := _label(w.display_name, 18, PARCHMENT)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var lv_text := "✦" if w.is_max_level() else TextFormat.roman(w.level)
		row.add_child(_label(lv_text, 18, GOLD))
		for c in row.get_children():
			if c is Label:
				(c as Label).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		weapons_box.add_child(row)

	_stat("Vigor", "%d / %d" % [roundi(p.hp), roundi(p.max_hp)])
	_stat("Wrath", "%d%%" % roundi(p.might * 100.0))
	_stat("Swiftness", "%.1f" % p.move_speed)
	_stat("Dominion", "%d%%" % roundi(p.area * 100.0))
	_stat("Haste", "%d%%" % roundi(p.cooldown * 100.0))
	_stat("Soul reach", "%.1f" % p.pickup_radius)
	_stat("Armor", "%.0f" % p.armor)
	_stat("Blood pact", "%.1f/s" % p.regen)
	_fill_synergies()
	_fill_relics()


## "RELICS" block: every relic carried this run as a framed painted icon (hover / focus for the
## name and effect), rarity pips on the tooltip line.
func _fill_relics() -> void:
	if _relic_box == null:
		_relic_box = VBoxContainer.new()
		_relic_box.add_theme_constant_override(&"separation", 4)
		stats_grid.get_parent().add_child(_relic_box)
	for c in _relic_box.get_children():
		_relic_box.remove_child(c)
		c.queue_free()
	var prog := get_node_or_null(^"/root/Progression")
	var ids: Array = prog.get(&"run_relics") if prog and prog.get(&"run_relics") is Array else []
	_relic_box.visible = not ids.is_empty()
	if ids.is_empty():
		return
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	_relic_box.add_child(spacer)
	var head := _label("RELICS  (%d)" % ids.size(), 15, GOLD)
	head.theme_type_variation = &"HeaderLabel"
	head.add_theme_font_size_override(&"font_size", 15)
	_relic_box.add_child(head)
	_relic_box.add_child(HSeparator.new())
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override(&"h_separation", 6)
	grid.add_theme_constant_override(&"v_separation", 6)
	_relic_box.add_child(grid)
	for id: Variant in ids:
		var r: Dictionary = prog.call(&"get_relic", StringName(str(id)))
		if r.is_empty():
			continue
		var chip := RelicView.chip(r, 34.0)
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		grid.add_child(chip)


## "SYNERGIES" block under the attributes: every active Abilities synergy, its colour and effect.
func _fill_synergies() -> void:
	if _syn_box == null:
		_syn_box = VBoxContainer.new()
		_syn_box.add_theme_constant_override(&"separation", 4)
		stats_grid.get_parent().add_child(_syn_box)
	for c in _syn_box.get_children():
		_syn_box.remove_child(c)
		c.queue_free()
	var ab := get_node_or_null(^"/root/Abilities")
	var active: Dictionary = ab.get(&"active_synergies") if ab and ab.get(&"active_synergies") is Dictionary else {}
	_syn_box.visible = not active.is_empty()
	if active.is_empty():
		return
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	_syn_box.add_child(spacer)
	var head := _label("SYNERGIES", 15, GOLD)
	head.theme_type_variation = &"HeaderLabel"
	head.add_theme_font_size_override(&"font_size", 15)
	_syn_box.add_child(head)
	_syn_box.add_child(HSeparator.new())
	for id: Variant in active:
		var def: Dictionary = active[id]
		var col := Color.from_string(str(def.get("color", "#ffb347")), UIPalette.HELLFIRE)
		var name_l := _label("◆ " + str(def.get("name", id)), 18, col.lerp(PALE_GOLD, 0.3))
		_syn_box.add_child(name_l)
		var desc := str(def.get("desc", ""))
		if desc != "":
			var d := _label(desc, 15, MUTED)
			d.theme_type_variation = &"LoreLabel"
			d.add_theme_font_size_override(&"font_size", 15)
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			d.custom_minimum_size.x = 260.0
			_syn_box.add_child(d)


func _stat(stat_name: String, value: String) -> void:
	var n := _label(stat_name, 18, PARCHMENT)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_grid.add_child(n)
	var v := _label(value, 18, PALE_GOLD)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stats_grid.add_child(v)


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"InkLabel"
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_color", color)
	l.text = text
	return l
