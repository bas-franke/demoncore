class_name HudWidgets
extends Control
## The HUD's extra widgets (owned by the UI role), created by hud.gd as a full-rect child of its root:
##   - resource bar (wrath / mana) under the life bar, hidden until something reports a resource
##   - ability dock, bottom-centre: a Dash slot automatically, plus any slots other systems add
##   - currencies, top-right under "Angels slain": run Ichor (RunState) and souls (Meta.run_souls)
##   - minimap, bottom-right
##   - low-life vignette: a red pulse at the screen edges below LOW_HP
## Public API is forwarded by hud.gd (see docs/team/ui.md, "HUD API").
##
## Pull protocols (no HUD calls needed, all optional, duck-typed on Game.player):
##   player.resource / player.max_resource (floats) [+ player.resource_color, player.resource_name]
##   player.get_hud_abilities() -> Array[Dictionary]: {id, title, glyph, icon, color, action,
##       remaining, total, charges (-1 = hide), disabled}

## The player pressed the key shown on an ability slot (ability_1..4). The abilities system may
## use it (manual cast / overcharge); the HUD itself only pulses the slot.
signal ability_key_pressed(id: StringName)

const DOCK_SLOT := 54.0
const DOCK_BOTTOM := 22.0
const MINIMAP_SIZE := 148.0
const LOW_HP := 0.3
const RESOURCE_HEIGHT := 6.0

var resource_bar: InfernalBar
var ability_dock: HBoxContainer
var minimap: Minimap
var ichor_counter: CurrencyCounter
var soul_counter: CurrencyCounter

var _currency_box: VBoxContainer
var _vignette: TextureRect
var _slots := {}  # StringName -> CooldownSlot
## Slots added without an action get ability_1..ability_4 in arrival order; remembered per id so a
## slot re-added on rank-up keeps its key.
var _auto_actions := {}  # StringName -> StringName
var _synergy_queue: Array = []  # [title, desc, color]
var _tracker_t := 0.0
var _dash_slot: CooldownSlot
var _resource_pushed := false
var _resource_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	add_child(RunTally.new())  # damage / kills per type for the end-screen breakdown
	add_child(MapOverview.new())  # full-screen map on Tab / M / pad Back
	var rs := get_node_or_null(^"/root/RunState")
	if rs and rs.has_signal(&"currency_changed"):
		rs.connect(&"currency_changed", _on_currency_changed)
		ichor_counter.set_amount(int(rs.get(&"currency")), true)


func _process(delta: float) -> void:
	var p := Game.player
	if p == null or not is_instance_valid(p):
		return
	_update_vignette(p, delta)
	_update_dash(p)
	_pull_resource(p)
	_pull_abilities(p)
	_tracker_t -= delta
	if _tracker_t <= 0.0:
		_tracker_t = 0.5
		_place_objective_list()
	var meta := get_node_or_null(^"/root/Meta")
	if meta:
		var s := int(meta.get(&"run_souls"))
		if s != soul_counter.amount:
			soul_counter.set_amount(s)
		soul_counter.visible = s > 0


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_type() or not event.is_pressed() or event.is_echo():
		return
	for id: StringName in _slots:
		var slot: CooldownSlot = _slots[id]
		var action: StringName = slot.get_meta(&"action", &"")
		if id != &"dash" and action != &"" and event.is_action_pressed(action):
			slot.trigger()
			ability_key_pressed.emit(id)
			return


# ---------------------------------------------------------------- public API

## Places the resource bar (hud.gd calls this so it sits under the life bar).
func place_resource(pos: Vector2, width: float) -> void:
	resource_bar.position = pos
	resource_bar.size = Vector2(width, RESOURCE_HEIGHT)
	resource_bar.custom_minimum_size = resource_bar.size
	_resource_label.position = pos + Vector2(width + 8.0, -6.0)


## Shows the resource bar with these values. Call every frame or on change.
func set_resource(value: float, max_value: float, color: Color = UIPalette.WRATH, label := "") -> void:
	_resource_pushed = true
	resource_bar.visible = true
	resource_bar.fill_color = color
	resource_bar.set_values(value, max_value)
	_resource_label.text = label
	_resource_label.visible = label != ""


func hide_resource() -> void:
	_resource_pushed = false
	resource_bar.visible = false
	_resource_label.visible = false


## Adds (or returns the existing) cooldown slot in the bottom dock. `action` is an InputMap action
## whose key is shown as the hint ("" = none).
func add_ability_slot(id: StringName, title: String, icon: Texture2D = null, glyph := "✦",
		tint: Color = UIPalette.EMBER, action: StringName = &"") -> CooldownSlot:
	if _slots.has(id):
		return _slots[id]
	if action == &"" and id != &"dash":
		action = _auto_action(id)
	var slot := CooldownSlot.new()
	slot.custom_minimum_size = Vector2(DOCK_SLOT, DOCK_SLOT)
	slot.setup(id, title, icon, glyph, tint, Keybinds.label(action) if action != &"" else "")
	slot.set_meta(&"action", action)
	ability_dock.add_child(slot)
	_slots[id] = slot
	slot.modulate.a = 0.0
	slot.create_tween().tween_property(slot, "modulate:a", 1.0, 0.5)
	return slot


## The InputMap action shown on (and meant to trigger) ability `id`'s slot, or &"".
func action_for(id: StringName) -> StringName:
	var slot: CooldownSlot = _slots.get(id)
	return slot.get_meta(&"action", &"") if slot else _auto_actions.get(id, &"")


func _auto_action(id: StringName) -> StringName:
	if _auto_actions.has(id):
		return _auto_actions[id]
	var used: Array = _auto_actions.values()
	for i in range(1, 5):
		var a := StringName("ability_%d" % i)
		if not used.has(a) and InputMap.has_action(a):
			_auto_actions[id] = a
			return a
	return &""


func get_ability_slot(id: StringName) -> CooldownSlot:
	return _slots.get(id)


func remove_ability_slot(id: StringName) -> void:
	var slot: CooldownSlot = _slots.get(id)
	if slot:
		_slots.erase(id)
		slot.queue_free()


func set_ability_cooldown(id: StringName, remaining: float, total: float) -> void:
	var slot: CooldownSlot = _slots.get(id)
	if slot:
		slot.set_cooldown(remaining, total)


## Pixels at the bottom of the screen the dock occupies (the boss bar sits above it).
func bottom_reserved() -> float:
	return DOCK_SLOT + DOCK_BOTTOM + 14.0 if ability_dock.get_child_count() > 0 else 0.0


## Two-line "SYNERGY FORGED" banner (name in its colour, description below). Queued: one at a time.
func show_synergy(title: String, desc: String, color: Color) -> void:
	_synergy_queue.append([title, desc, color])
	if _synergy_queue.size() == 1:
		_play_synergy()


func _play_synergy() -> void:
	if _synergy_queue.is_empty():
		return
	var entry: Array = _synergy_queue[0]
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 2)
	var cap := Label.new()
	cap.theme_type_variation = &"CaptionLabel"
	cap.text = "◆  SYNERGY FORGED  ◆"
	cap.add_theme_color_override(&"font_color", UIPalette.BRIMSTONE)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(cap)
	var name_l := Label.new()
	name_l.theme_type_variation = &"TitleLabel"
	name_l.add_theme_font_size_override(&"font_size", 38)
	name_l.add_theme_color_override(&"font_color", (entry[2] as Color).lerp(UIPalette.BONE_BRIGHT, 0.25))
	name_l.text = str(entry[0]).to_upper()
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_l)
	var r := UIPalette.rule(420.0, entry[2])
	box.add_child(r)
	if str(entry[1]) != "":
		var d := Label.new()
		d.theme_type_variation = &"LoreLabel"
		d.add_theme_font_size_override(&"font_size", 18)
		d.text = str(entry[1])
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(d)
	# Soft dark band behind the text so it reads on bright ground.
	var band := PanelContainer.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxTexture.new()
	sb.texture = UIPalette.gradient(PackedFloat32Array([0.0, 0.3, 0.7, 1.0]),
		PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.6), Color(0, 0, 0, 0.6), Color(0, 0, 0, 0)]))
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 12.0
	band.add_theme_stylebox_override(&"panel", sb)
	band.anchor_right = 1.0
	band.anchor_top = 0.3
	band.anchor_bottom = 0.3
	band.grow_vertical = Control.GROW_DIRECTION_BOTH
	band.add_child(box)
	add_child(band)
	band.modulate.a = 0.0
	Sfx.play(&"toast")
	var tw := band.create_tween()
	tw.tween_property(band, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(2.6)
	tw.tween_property(band, "modulate:a", 0.0, 0.9).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		band.queue_free()
		_synergy_queue.pop_front()
		_play_synergy())


## Refreshes every key hint (after a rebind).
func refresh_key_hints() -> void:
	for id: StringName in _slots:
		var slot: CooldownSlot = _slots[id]
		var action: StringName = slot.get_meta(&"action", &"")
		if action != &"":
			slot.key_hint = Keybinds.label(action)
			slot.queue_redraw()


# ---------------------------------------------------------------- updates

func _update_vignette(p: Player, delta: float) -> void:
	var ratio := clampf(p.hp / maxf(p.max_hp, 1.0), 0.0, 1.0)
	var want := 0.0
	if ratio < LOW_HP and not p.is_dead:
		var pulse := 0.5 if UIPalette.calm() else 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
		want = (1.0 - ratio / LOW_HP) * (0.55 + 0.45 * pulse)
	_vignette.modulate.a = move_toward(_vignette.modulate.a, want, delta * 3.0)
	_vignette.visible = _vignette.modulate.a > 0.01


func _update_dash(p: Player) -> void:
	var dash := p.get(&"dash") as PlayerDash
	if dash == null:
		return
	if _dash_slot == null:
		_dash_slot = add_ability_slot(&"dash", "Dash", null, "»", UIPalette.WRATH, &"dash")
		ability_dock.move_child(_dash_slot, 0)
	var max_c := dash.max_charges()
	var cd := maxf(float(p.dash_cooldown), 0.01)
	if dash.charges > 0:
		_dash_slot.set_cooldown(0.0, cd)
	else:
		_dash_slot.set_cooldown((1.0 - dash.recharge_ratio()) * cd, cd)
	_dash_slot.set_charges(dash.charges if max_c > 1 else -1)


func _pull_resource(p: Player) -> void:
	if _resource_pushed:
		return
	var v: Variant = p.get(&"resource")
	var m: Variant = p.get(&"max_resource")
	if (v is float or v is int) and (m is float or m is int) and float(m) > 0.0:
		var col: Variant = p.get(&"resource_color")
		var nm: Variant = p.get(&"resource_name")
		resource_bar.visible = true
		resource_bar.fill_color = col if col is Color else UIPalette.WRATH
		resource_bar.set_values(float(v), float(m))
		_resource_label.text = str(nm) if nm is String else ""
		_resource_label.visible = _resource_label.text != ""


func _pull_abilities(p: Player) -> void:
	if not p.has_method(&"get_hud_abilities"):
		return
	var list: Array = p.call(&"get_hud_abilities")
	for a: Dictionary in list:
		var id := StringName(str(a.get("id", "")))
		if id == &"":
			continue
		var slot := add_ability_slot(id, str(a.get("title", id)), a.get("icon", null) as Texture2D,
			str(a.get("glyph", "✦")), a.get("color", UIPalette.EMBER), StringName(str(a.get("action", ""))))
		slot.set_cooldown(float(a.get("remaining", 0.0)), float(a.get("total", 0.0)))
		slot.set_charges(int(a.get("charges", -1)))
		slot.set_disabled(bool(a.get("disabled", false)))


## Keeps the objectives role's tracker list (scenes/objectives/objective_tracker.gd) just under the
## currency counters, whichever of them are showing.
func _place_objective_list() -> void:
	var director := get_tree().get_first_node_in_group(&"objective_director")
	if director == null:
		return
	var top := _currency_box.position.y + _currency_box.get_combined_minimum_size().y + 14.0
	for child in director.get_children():
		if &"list_top" in child and absf(float(child.get(&"list_top")) - top) > 1.0:
			child.set(&"list_top", top)


func _on_currency_changed(total: int, _delta: int) -> void:
	ichor_counter.set_amount(total)


# ---------------------------------------------------------------- construction

func _build() -> void:
	# Low-life vignette (behind everything else in the HUD).
	_vignette = TextureRect.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(0.5, 0.0, 0.0, 0.0), Color(0.45, 0.0, 0.0, 0.0), Color(0.55, 0.02, 0.0, 0.85)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.05, 1.05)
	gt.width = 256
	gt.height = 256
	_vignette.texture = gt
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	_vignette.visible = false
	add_child(_vignette)

	resource_bar = InfernalBar.new()
	resource_bar.fill_color = UIPalette.WRATH
	resource_bar.trail_color = Color(UIPalette.HELLFIRE, 0.5)
	resource_bar.frame_color = UIPalette.IRON
	resource_bar.visible = false
	add_child(resource_bar)
	_resource_label = Label.new()
	_resource_label.theme_type_variation = &"CaptionLabel"
	_resource_label.add_theme_font_size_override(&"font_size", 12)
	_resource_label.add_theme_color_override(&"font_color", UIPalette.WRATH)
	_resource_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_resource_label.visible = false
	add_child(_resource_label)

	ability_dock = HBoxContainer.new()
	ability_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ability_dock.add_theme_constant_override(&"separation", 10)
	ability_dock.alignment = BoxContainer.ALIGNMENT_CENTER
	ability_dock.anchor_left = 0.5
	ability_dock.anchor_right = 0.5
	ability_dock.anchor_top = 1.0
	ability_dock.anchor_bottom = 1.0
	ability_dock.offset_left = -300.0
	ability_dock.offset_right = 300.0
	ability_dock.offset_top = -DOCK_SLOT - DOCK_BOTTOM
	ability_dock.offset_bottom = -DOCK_BOTTOM
	add_child(ability_dock)

	_currency_box = VBoxContainer.new()
	_currency_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_currency_box.add_theme_constant_override(&"separation", 0)
	_currency_box.anchor_left = 1.0
	_currency_box.anchor_right = 1.0
	_currency_box.offset_left = -260.0
	_currency_box.offset_right = -26.0
	_currency_box.offset_top = 56.0
	_currency_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(_currency_box)
	ichor_counter = CurrencyCounter.new()
	ichor_counter.font_size = 20
	var rs := get_node_or_null(^"/root/RunState")
	var ichor_name := str(rs.get(&"CURRENCY_NAME")) if rs and rs.get(&"CURRENCY_NAME") != null else "Ichor"
	ichor_counter.setup("◆", UIPalette.BLOOD_BRIGHT.lerp(UIPalette.WRATH, 0.35), ichor_name)
	_currency_box.add_child(ichor_counter)
	soul_counter = CurrencyCounter.new()
	soul_counter.font_size = 18
	soul_counter.setup("◈", UIPalette.SOUL, "Souls")
	soul_counter.visible = false
	_currency_box.add_child(soul_counter)

	minimap = Minimap.new()
	minimap.custom_minimum_size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	minimap.anchor_left = 1.0
	minimap.anchor_right = 1.0
	minimap.anchor_top = 1.0
	minimap.anchor_bottom = 1.0
	minimap.offset_left = -MINIMAP_SIZE - 26.0
	minimap.offset_right = -26.0
	minimap.offset_top = -MINIMAP_SIZE - 26.0
	minimap.offset_bottom = -26.0
	add_child(minimap)
