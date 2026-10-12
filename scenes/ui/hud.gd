extends CanvasLayer
## In-run HUD, in the manner of the old souls: a thin crimson life bar (with a lingering
## "lost life" trail) and a thinner pale-gold ascension bar top-left beside a small level numeral,
## gold-framed power and boon squares beneath, the timer top-centre, "Angels slain" top-right,
## a faint life thread under the demon when wounded, and slow serif banners for announcements.
##
## Banners from anywhere:
##     var hud := get_tree().get_first_node_in_group(&"hud")
##     if hud: hud.toast("The Seraph descends", Color("e8d6a6"))

## Colours come from the shared infernal palette (ui/palette.gd); names kept for older code.
const PARCHMENT := UIPalette.BONE
const PALE_GOLD := UIPalette.BONE_BRIGHT
const GOLD := UIPalette.BRIMSTONE
const BRONZE := UIPalette.EMBER_DIM
const MUTED := UIPalette.ASH_TEXT
const CRIMSON := UIPalette.BLOOD
const CRIMSON_DEEP := UIPalette.BLOOD_DEEP
const TRAIL := Color("e8a65a")

const MARGIN := 26.0
const LEVEL_BOX := 46.0
const HP_HEIGHT := 9.0
const XP_HEIGHT := 4.0
const HP_MIN_W := 220.0
const HP_MAX_W := 520.0
const HP_W_PER_HP := 1.6
const XP_W := 240.0
const ICON_SIZE := 38.0
const TOAST_TOP_RATIO := 0.2
const TOAST_GAP := 6.0
const TOAST_IN := 0.7
const TOAST_HOLD := 2.4
const TOAST_OUT := 1.1
const MAX_TOASTS := 3
const TRAIL_DELAY := 0.55
const TRAIL_SPEED := 0.45  # fraction of max per second
const FLOAT_BAR_SIZE := Vector2(58.0, 3.0)

var xp_bar: ProgressBar
var hp_bar: ProgressBar  # the main life bar, top-left (kept as `hp_bar` for older callers)
var level_badge: PanelContainer
var level_label: Label
var time_label: Label
var kills_panel: Control
var kills_label: Label
var weapon_row: HBoxContainer
var passive_row: HBoxContainer
## Resource bar, ability dock, currencies, minimap, low-life vignette (scenes/ui/hud_widgets.gd).
var widgets: HudWidgets

var _hp_trail: ProgressBar
var _float_bar: ProgressBar
var _float_alpha := 0.0
var _trail_wait := 0.0
var _toast_root: Control
var _toasts: Array[Control] = []
var _band_tex: GradientTexture2D
var _line_l_tex: GradientTexture2D
var _line_r_tex: GradientTexture2D
var _last_level := -1
var _last_kills := -1
var _last_hp := -1.0
var _last_max_hp := -1.0
var _chips := {}  # weapon instance id (int) -> Control
var _chip_levels := {}  # weapon instance id (int) -> int
var _boons := {}  # PassiveData -> Control
var _boon_levels := {}  # PassiveData -> int

@onready var root: Control = $Root


func _ready() -> void:
	add_to_group(&"hud")
	_build()


func _process(delta: float) -> void:
	var p := Game.player
	if p == null or not is_instance_valid(p):
		_float_bar.visible = false
		return

	# Ascension (XP) + level numeral
	xp_bar.max_value = maxf(float(p.xp_to_next), 1.0)
	xp_bar.value = p.xp
	if p.level != _last_level:
		level_label.text = str(p.level)
		if _last_level != -1:
			_glow(level_badge)
		_last_level = p.level

	# Timer + kills
	time_label.text = TextFormat.clock(Game.elapsed)
	if Game.kills != _last_kills:
		kills_label.text = str(Game.kills)
		_last_kills = Game.kills

	_update_hp(p, delta)
	_update_weapons(p)
	_update_boons(p)
	_update_float_bar(p, delta)


# ---------------------------------------------------------------- widget API (see HudWidgets)

## Shows the resource (wrath / mana) bar under the ascension bar. Call on change or every frame.
func set_resource(value: float, max_value: float, color: Color = UIPalette.WRATH, label := "") -> void:
	widgets.set_resource(value, max_value, color, label)


func hide_resource() -> void:
	widgets.hide_resource()


## Adds a cooldown slot to the bottom-centre dock (returns it; it is reused if `id` exists).
func add_ability_slot(id: StringName, title: String, icon: Texture2D = null, glyph := "✦",
		tint: Color = UIPalette.EMBER, action: StringName = &"") -> CooldownSlot:
	return widgets.add_ability_slot(id, title, icon, glyph, tint, action)


func set_ability_cooldown(id: StringName, remaining: float, total: float) -> void:
	widgets.set_ability_cooldown(id, remaining, total)


func remove_ability_slot(id: StringName) -> void:
	widgets.remove_ability_slot(id)


## Big two-line banner for a newly forged ability synergy (called by the Abilities autoload).
func synergy_banner(title: String, desc: String, color: Color = UIPalette.HELLFIRE) -> void:
	widgets.show_synergy(title, desc, color)


## InputMap action bound to ability `id`'s slot (ability_1..4 by dock order unless one was given).
func action_for(id: StringName) -> StringName:
	return widgets.action_for(id)


## Screen pixels the ability dock takes at the bottom (the boss bar sits above it).
func bottom_reserved() -> float:
	return widgets.bottom_reserved() if widgets else 0.0


# ---------------------------------------------------------------- toasts

## Shows a centred serif banner with fine lines either side; fades in, holds, fades away.
func toast(text: String, color: Color = PALE_GOLD) -> void:
	if _toast_root == null:
		return
	Sfx.play(&"toast")
	var tint := color.lerp(PARCHMENT, 0.35)

	var banner := PanelContainer.new()
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var band := StyleBoxTexture.new()
	band.texture = _band_tex
	band.content_margin_left = 80.0
	band.content_margin_right = 80.0
	band.content_margin_top = 10.0
	band.content_margin_bottom = 10.0
	banner.add_theme_stylebox_override(&"panel", band)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 18)
	banner.add_child(row)
	row.add_child(_line(_line_l_tex, tint))
	var label := Label.new()
	label.theme_type_variation = &"TitleLabel"
	label.add_theme_font_size_override(&"font_size", 26)
	label.add_theme_color_override(&"font_color", tint)
	label.add_theme_constant_override(&"outline_size", 4)
	label.add_theme_constant_override(&"shadow_outline_size", 8)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	row.add_child(_line(_line_r_tex, tint))
	_toast_root.add_child(banner)

	var sz := banner.get_combined_minimum_size()
	banner.anchor_left = 0.5
	banner.anchor_right = 0.5
	banner.offset_left = -sz.x * 0.5
	banner.offset_right = sz.x * 0.5
	var top := _toast_top()
	banner.offset_top = top
	banner.offset_bottom = top + sz.y
	banner.pivot_offset = sz * 0.5
	banner.modulate.a = 0.0
	banner.scale = Vector2(0.985, 0.985)

	_toasts.push_front(banner)
	while _toasts.size() > MAX_TOASTS:
		var old: Control = _toasts.pop_back()
		if is_instance_valid(old):
			old.queue_free()
	_layout_toasts()

	var tw := banner.create_tween()
	tw.tween_property(banner, "modulate:a", 1.0, TOAST_IN).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(banner, "scale", Vector2.ONE, TOAST_IN + TOAST_HOLD) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_interval(TOAST_HOLD * 0.7)
	tw.tween_property(banner, "modulate:a", 0.0, TOAST_OUT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(_remove_toast.bind(banner))


func _toast_top() -> float:
	return get_viewport().get_visible_rect().size.y * TOAST_TOP_RATIO


func _line(tex: Texture2D, tint: Color) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.custom_minimum_size = Vector2(150.0, 1.0)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.modulate = Color(tint, 0.85)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _remove_toast(panel: Control) -> void:
	_toasts.erase(panel)
	if is_instance_valid(panel):
		panel.queue_free()
	_layout_toasts()


func _layout_toasts() -> void:
	var y := _toast_top()
	for t in _toasts:
		if not is_instance_valid(t):
			continue
		if t.has_meta(&"layout_tw"):
			var old := t.get_meta(&"layout_tw") as Tween
			if old and old.is_valid():
				old.kill()
		var tw := t.create_tween()
		tw.tween_property(t, "position:y", y, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		t.set_meta(&"layout_tw", tw)
		y += t.size.y + TOAST_GAP


# ---------------------------------------------------------------- per-frame updates

func _update_hp(p: Player, delta: float) -> void:
	var max_hp := maxf(p.max_hp, 1.0)
	if not is_equal_approx(max_hp, _last_max_hp):
		_last_max_hp = max_hp
		var w := clampf(HP_MIN_W + max_hp * HP_W_PER_HP * 0.5, HP_MIN_W, HP_MAX_W)
		hp_bar.custom_minimum_size.x = w
		hp_bar.size.x = w
		_hp_trail.custom_minimum_size.x = w
		_hp_trail.size.x = w
	hp_bar.max_value = max_hp
	_hp_trail.max_value = max_hp
	hp_bar.value = p.hp

	if _last_hp >= 0.0 and p.hp < _last_hp - 0.001:
		_trail_wait = TRAIL_DELAY
	_last_hp = p.hp
	if _hp_trail.value < p.hp:
		_hp_trail.value = p.hp
	elif _trail_wait > 0.0:
		_trail_wait -= delta
	else:
		_hp_trail.value = maxf(p.hp, _hp_trail.value - max_hp * TRAIL_SPEED * delta)


func _update_float_bar(p: Player, delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var ratio := clampf(p.hp / maxf(p.max_hp, 1.0), 0.0, 1.0)
	var want := 1.0 if ratio < 0.999 else 0.0
	_float_alpha = move_toward(_float_alpha, want, delta * (1.5 if want > 0.0 else 0.6))
	if cam == null or _float_alpha <= 0.001:
		_float_bar.visible = false
		return
	var world_pos := p.get_global_transform_interpolated().origin
	if cam.is_position_behind(world_pos):
		_float_bar.visible = false
		return
	_float_bar.visible = true
	_float_bar.modulate.a = _float_alpha * 0.85
	_float_bar.max_value = maxf(p.max_hp, 1.0)
	_float_bar.value = p.hp
	_float_bar.position = cam.unproject_position(world_pos) + Vector2(-FLOAT_BAR_SIZE.x * 0.5, 22.0)


func _update_weapons(p: Player) -> void:
	for w in p.weapons:
		if not is_instance_valid(w):
			continue
		var id := w.get_instance_id()
		if not _chips.has(id):
			var chip := _make_icon(w.icon, w.color, Icons.for_weapon(w))
			weapon_row.add_child(chip)
			_chips[id] = chip
			_chip_levels[id] = w.level
			_set_icon_level(chip, w.level, w.is_max_level())
			_fade_in(chip)
		elif int(_chip_levels[id]) != w.level:
			_chip_levels[id] = w.level
			var c: Control = _chips[id]
			_set_icon_level(c, w.level, w.is_max_level())
			_glow(c)


func _update_boons(p: Player) -> void:
	for pd: PassiveData in p.passive_levels:
		var lv: int = p.passive_levels[pd]
		if lv <= 0:
			continue
		if not _boons.has(pd):
			var chip := _make_icon(pd.icon, pd.color, Icons.for_passive(pd))
			chip.custom_minimum_size = Vector2.ONE * (ICON_SIZE - 8.0)
			passive_row.add_child(chip)
			_boons[pd] = chip
			_boon_levels[pd] = lv
			_set_icon_level(chip, lv, lv >= pd.max_level)
			_fade_in(chip)
		elif int(_boon_levels[pd]) != lv:
			_boon_levels[pd] = lv
			var c: Control = _boons[pd]
			_set_icon_level(c, lv, lv >= pd.max_level)
			_glow(c)


# ---------------------------------------------------------------- construction

func _build() -> void:
	_band_tex = _gradient_tex(
		PackedFloat32Array([0.0, 0.22, 0.5, 0.78, 1.0]),
		PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.5), Color(0, 0, 0, 0.62),
			Color(0, 0, 0, 0.5), Color(0, 0, 0, 0)]))
	_line_l_tex = _gradient_tex(PackedFloat32Array([0.0, 1.0]),
		PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1)]))
	_line_r_tex = _gradient_tex(PackedFloat32Array([0.0, 1.0]),
		PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)]))

	# Added first so its low-life vignette draws behind every other HUD element.
	widgets = HudWidgets.new()
	root.add_child(widgets)

	# Faint darkening behind the top-left cluster so the bars read on bright ground.
	var vignette := TextureRect.new()
	vignette.texture = _gradient_tex(PackedFloat32Array([0.0, 1.0]),
		PackedColorArray([Color(0, 0, 0, 0.42), Color(0, 0, 0, 0)]), true)
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.anchor_right = 1.0
	vignette.offset_bottom = 120.0
	root.add_child(vignette)

	# Level numeral.
	level_badge = PanelContainer.new()
	level_badge.theme_type_variation = &"LevelBadge"
	level_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_badge.custom_minimum_size = Vector2(LEVEL_BOX, LEVEL_BOX)
	level_badge.position = Vector2(MARGIN, MARGIN - 4.0)
	level_badge.size = level_badge.custom_minimum_size
	level_label = _label("1", 24, PALE_GOLD)
	level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level_badge.add_child(level_label)
	root.add_child(level_badge)

	var bars_x := MARGIN + LEVEL_BOX + 12.0
	# Life: lingering trail behind, crimson fill on top.
	_hp_trail = _bar(&"HPBar", Vector2(bars_x, MARGIN + 6.0), Vector2(HP_MIN_W, HP_HEIGHT))
	var trail_fill := StyleBoxFlat.new()
	trail_fill.bg_color = Color(TRAIL, 0.7)
	_hp_trail.add_theme_stylebox_override(&"fill", trail_fill)
	root.add_child(_hp_trail)
	hp_bar = _bar(&"HPBar", Vector2(bars_x, MARGIN + 6.0), Vector2(HP_MIN_W, HP_HEIGHT))
	hp_bar.add_theme_stylebox_override(&"background", StyleBoxEmpty.new())
	var hp_fill := StyleBoxFlat.new()
	hp_fill.bg_color = CRIMSON
	hp_fill.border_color = Color("d0503c")
	hp_fill.border_width_top = 1
	hp_bar.add_theme_stylebox_override(&"fill", hp_fill)
	root.add_child(hp_bar)

	# Ascension.
	xp_bar = _bar(&"XPBar", Vector2(bars_x, MARGIN + 6.0 + HP_HEIGHT + 8.0), Vector2(XP_W, XP_HEIGHT))
	xp_bar.max_value = 5.0
	xp_bar.value = 0.0
	root.add_child(xp_bar)
	widgets.place_resource(Vector2(bars_x, xp_bar.position.y + XP_HEIGHT + 6.0), XP_W)

	# Powers, then boons.
	weapon_row = HBoxContainer.new()
	weapon_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_row.add_theme_constant_override(&"separation", 8)
	weapon_row.position = Vector2(MARGIN, MARGIN + LEVEL_BOX + 12.0)
	root.add_child(weapon_row)
	passive_row = HBoxContainer.new()
	passive_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	passive_row.add_theme_constant_override(&"separation", 6)
	passive_row.position = Vector2(MARGIN, MARGIN + LEVEL_BOX + 12.0 + ICON_SIZE + 10.0)
	root.add_child(passive_row)

	# Timer, top-centre.
	time_label = _label("00:00", 30, PARCHMENT)
	time_label.theme_type_variation = &"TitleLabel"
	time_label.add_theme_font_size_override(&"font_size", 30)
	time_label.add_theme_color_override(&"font_color", PARCHMENT)
	time_label.anchor_left = 0.5
	time_label.anchor_right = 0.5
	time_label.offset_left = -120.0
	time_label.offset_right = 120.0
	time_label.offset_top = MARGIN - 8.0
	root.add_child(time_label)

	# "Angels slain", top-right.
	var kills_box := HBoxContainer.new()
	kills_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kills_box.add_theme_constant_override(&"separation", 10)
	kills_box.alignment = BoxContainer.ALIGNMENT_END
	kills_box.anchor_left = 1.0
	kills_box.anchor_right = 1.0
	kills_box.offset_left = -360.0
	kills_box.offset_right = -MARGIN
	kills_box.offset_top = MARGIN - 2.0
	var caption := _label("Angels slain:", 18, MUTED)
	caption.theme_type_variation = &"LoreLabel"
	caption.add_theme_font_size_override(&"font_size", 18)
	kills_box.add_child(caption)
	kills_label = _label("0", 24, PALE_GOLD)
	kills_label.custom_minimum_size.x = 44.0
	kills_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	kills_box.add_child(kills_label)
	root.add_child(kills_box)
	kills_panel = kills_box

	# Banner layer.
	_toast_root = Control.new()
	_toast_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_toast_root)

	# Faint life thread under the demon (only while wounded).
	_float_bar = _bar(&"HPBar", Vector2.ZERO, FLOAT_BAR_SIZE)
	var fbg := StyleBoxFlat.new()
	fbg.bg_color = Color(0, 0, 0, 0.55)
	_float_bar.add_theme_stylebox_override(&"background", fbg)
	var ffill := StyleBoxFlat.new()
	ffill.bg_color = CRIMSON
	_float_bar.add_theme_stylebox_override(&"fill", ffill)
	_float_bar.visible = false
	root.add_child(_float_bar)


func _bar(variation: StringName, pos: Vector2, sz: Vector2) -> ProgressBar:
	var b := ProgressBar.new()
	b.theme_type_variation = variation
	b.show_percentage = false
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.custom_minimum_size = sz
	b.position = pos
	b.size = sz
	b.max_value = 100.0
	b.value = 100.0
	return b


func _make_icon(icon_text: String, tint: Color, tex: Texture2D = null) -> Control:
	var chip := Control.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)

	var frame := PanelContainer.new()
	frame.theme_type_variation = &"Chip"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.034, 0.03, 0.85).lerp(Color(tint, 1.0), 0.1)
	sb.border_color = Color(GOLD, 0.75)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(1)
	sb.set_content_margin_all(1.0)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 5
	frame.add_theme_stylebox_override(&"panel", sb)
	if tex:
		# Painted icon (its own dark vignette sits inside the gold frame).
		var art := TextureRect.new()
		art.texture = tex
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		frame.add_child(art)
	else:
		var icon := GlyphIcon.new()  # painted in code, no emoji font
		icon.glyph = icon_text
		icon.color = tint.lerp(PALE_GOLD, 0.45)
		frame.add_child(icon)
	chip.add_child(frame)

	var lv := _label("I", 11, PALE_GOLD)
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lv.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	lv.add_theme_constant_override(&"outline_size", 4)
	lv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lv.offset_right = -2.0
	lv.offset_bottom = 3.0
	chip.add_child(lv)
	chip.set_meta(&"lv", lv)
	chip.set_meta(&"frame", sb)
	return chip


func _set_icon_level(chip: Control, level: int, maxed: bool) -> void:
	var lv := chip.get_meta(&"lv") as Label
	if lv:
		lv.text = "✦" if maxed else roman(level)
	var sb := chip.get_meta(&"frame") as StyleBoxFlat
	if sb:
		sb.border_color = PALE_GOLD if maxed else Color(GOLD, 0.75)


static func roman(n: int) -> String:
	return TextFormat.roman(n)


# ---------------------------------------------------------------- helpers

func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"InkLabel"
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = text
	return l


func _gradient_tex(offsets: PackedFloat32Array, colors: PackedColorArray, vertical := false) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = offsets
	g.colors = colors
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 1 if vertical else 256
	tex.height = 64 if vertical else 1
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0) if vertical else Vector2(1.0, 0.0)
	return tex


func _fade_in(c: Control) -> void:
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.tween_property(c, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Restrained acknowledgement: a brief warm brightening that settles back.
func _glow(c: Control) -> void:
	if c.has_meta(&"glow_tw"):
		var old := c.get_meta(&"glow_tw") as Tween
		if old and old.is_valid():
			old.kill()
	c.modulate = Color(1.6, 1.35, 0.95, c.modulate.a)
	var tw := c.create_tween()
	tw.tween_property(c, "modulate", Color(1, 1, 1, c.modulate.a), 0.9) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	c.set_meta(&"glow_tw", tw)
