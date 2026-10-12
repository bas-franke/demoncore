extends SceneTree
## Generates res://ui/theme.tres — the DemonCore infernal UI theme (obsidian panels, ember-lit
## borders, brimstone-gold headings, bone-white text). Colours come from res://ui/palette.gd.
## Run: godot --headless --path <project> --script res://tools/build_theme.gd
##
## Type variations (see docs/team/ui.md for the full list with intended use):
##   Labels:   InkLabel (body), TitleLabel (big tracked display), LoreLabel (slanted flavour),
##             HeaderLabel (section heading), CaptionLabel (small muted caps), ValueLabel (bold gold
##             numbers), CostLabel (soul-coloured prices), DangerLabel (warnings)
##   Buttons:  CardButton (tall card), AccentButton (blood red call to action), GhostButton (flat
##             text button), TabButton (toggle tab with ember underline), SlotButton (square slot)
##   Panels:   HudPanel, Badge, Chip, LevelBadge, InfernalPanel (heavy modal frame), CardPanel,
##             HeaderBand (blood band behind headings), InsetPanel (sunken well)
##   Bars:     XPBar, HPBar, ResourceBar, SoulBar

const P := preload("res://ui/palette.gd")
const OUT_PATH := "res://ui/theme.tres"


func _init() -> void:
	var theme := _build()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://ui"))
	var err := ResourceSaver.save(theme, OUT_PATH)
	if err == OK:
		print("build_theme: saved ", OUT_PATH)
	else:
		push_error("build_theme: failed to save theme (error %d)" % err)
	quit(0 if err == OK else 1)


func _box(bg: Color, border: Color, border_w: int, radius: int, margin_h: float, margin_v: float,
		shadow_size := 0, shadow_color := Color(0, 0, 0, 0.55)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 4
	sb.anti_aliasing = true
	sb.content_margin_left = margin_h
	sb.content_margin_right = margin_h
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	if shadow_size > 0:
		sb.shadow_color = shadow_color
		sb.shadow_size = shadow_size
		sb.shadow_offset = Vector2.ZERO
	return sb


## "Forged" frame: thin border with a heavier bottom edge, like a plate set in iron.
func _forged(bg: Color, border: Color, margin_h: float, margin_v: float, shadow_size := 6,
		shadow_color := Color(0, 0, 0, 0.6)) -> StyleBoxFlat:
	var sb := _box(bg, border, 1, 2, margin_h, margin_v, shadow_size, shadow_color)
	sb.border_width_bottom = 2
	return sb


func _focus_ring() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = P.HELLFIRE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.set_expand_margin_all(4.0)
	sb.anti_aliasing = true
	sb.shadow_color = Color(P.EMBER, 0.35)
	sb.shadow_size = 12
	return sb


func _button_styles(t: Theme, type: StringName, normal_bg: Color, hover_bg: Color, pressed_bg: Color,
		border: Color, hover_border: Color, text: Color, hover_text: Color,
		margin_h: float, margin_v: float) -> void:
	var normal := _forged(normal_bg, border, margin_h, margin_v, 6)
	var hover := _forged(hover_bg, hover_border, margin_h, margin_v, 16, Color(P.EMBER, 0.28))
	var pressed := _forged(pressed_bg, P.HELLFIRE, margin_h, margin_v, 10, Color(P.EMBER, 0.4))
	var disabled := _box(Color(normal_bg, normal_bg.a * 0.55), Color(border, 0.35), 1, 2, margin_h,
		margin_v, 0)
	t.set_stylebox(&"normal", type, normal)
	t.set_stylebox(&"hover", type, hover)
	t.set_stylebox(&"pressed", type, pressed)
	t.set_stylebox(&"hover_pressed", type, pressed)
	t.set_stylebox(&"disabled", type, disabled)
	t.set_stylebox(&"focus", type, _focus_ring())
	t.set_color(&"font_color", type, text)
	t.set_color(&"font_focus_color", type, hover_text)
	t.set_color(&"font_hover_color", type, hover_text)
	t.set_color(&"font_pressed_color", type, P.HELLFIRE)
	t.set_color(&"font_hover_pressed_color", type, P.HELLFIRE)
	t.set_color(&"font_disabled_color", type, Color(text, 0.35))
	t.set_color(&"font_outline_color", type, Color(0, 0, 0, 0.9))
	t.set_color(&"icon_normal_color", type, text)
	t.set_color(&"icon_hover_color", type, hover_text)
	t.set_constant(&"outline_size", type, 3)
	t.set_constant(&"h_separation", type, 10)


func _label_type(t: Theme, type: StringName, font: Font, size: int, color: Color, outline: int,
		outline_alpha := 0.85) -> void:
	t.set_type_variation(type, &"Label")
	if font:
		t.set_font(&"font", type, font)
	if size > 0:
		t.set_font_size(&"font_size", type, size)
	t.set_color(&"font_color", type, color)
	t.set_color(&"font_outline_color", type, Color(0, 0, 0, outline_alpha))
	t.set_constant(&"outline_size", type, outline)


func _build() -> Theme:
	var t := Theme.new()

	var base := SystemFont.new()
	base.font_names = PackedStringArray(P.SERIF_NAMES)
	base.font_weight = 500
	base.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	base.hinting = TextServer.HINTING_LIGHT
	base.allow_system_fallback = true

	var bold := SystemFont.new()
	bold.font_names = PackedStringArray(P.SERIF_NAMES)
	bold.font_weight = 700
	bold.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	bold.hinting = TextServer.HINTING_LIGHT
	bold.allow_system_fallback = true

	# Body font: a touch of letter spacing everywhere.
	var body := FontVariation.new()
	body.base_font = base
	body.spacing_glyph = 1
	t.default_font = body
	t.default_font_size = 19

	# Display font: wide tracking for titles.
	var display := FontVariation.new()
	display.base_font = base
	display.spacing_glyph = 6
	display.variation_embolden = 0.2

	var header := FontVariation.new()
	header.base_font = base
	header.spacing_glyph = 4
	header.variation_embolden = 0.12

	var button_font := FontVariation.new()
	button_font.base_font = base
	button_font.spacing_glyph = 3
	button_font.variation_embolden = 0.08

	var caption := FontVariation.new()
	caption.base_font = base
	caption.spacing_glyph = 3

	var numbers := FontVariation.new()
	numbers.base_font = bold
	numbers.spacing_glyph = 1

	# Faux italic for lore / flavour text.
	var lore := FontVariation.new()
	lore.base_font = base
	lore.spacing_glyph = 1
	lore.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(0.2, 1.0), Vector2.ZERO)

	# ---------------------------------------------------------------- Buttons
	_button_styles(t, &"Button", Color(0.07, 0.035, 0.03, 0.92), Color(0.16, 0.06, 0.035, 0.95),
		Color(0.24, 0.05, 0.03, 0.97), P.EMBER_DIM, P.EMBER, P.BONE, P.BONE_BRIGHT, 26.0, 10.0)
	t.set_font(&"font", &"Button", button_font)
	t.set_font_size(&"font_size", &"Button", 21)

	t.set_type_variation(&"CardButton", &"Button")
	_button_styles(t, &"CardButton", Color(0.075, 0.038, 0.032, 0.94), Color(0.14, 0.06, 0.04, 0.96),
		Color(0.2, 0.05, 0.03, 0.97), P.IRON, P.EMBER, P.BONE, P.BONE_BRIGHT, 16.0, 16.0)

	t.set_type_variation(&"AccentButton", &"Button")
	_button_styles(t, &"AccentButton", Color(0.32, 0.05, 0.035, 0.94), Color(0.46, 0.08, 0.04, 0.96),
		Color(0.22, 0.03, 0.02, 0.97), Color("a3301c"), P.HELLFIRE, P.BONE_BRIGHT, Color.WHITE,
		26.0, 10.0)

	t.set_type_variation(&"GhostButton", &"Button")
	var ghost := StyleBoxEmpty.new()
	ghost.content_margin_left = 12.0
	ghost.content_margin_right = 12.0
	ghost.content_margin_top = 6.0
	ghost.content_margin_bottom = 6.0
	for st: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]:
		t.set_stylebox(st, &"GhostButton", ghost)
	t.set_stylebox(&"focus", &"GhostButton", _focus_ring())
	t.set_color(&"font_color", &"GhostButton", P.ASH_TEXT)
	t.set_color(&"font_hover_color", &"GhostButton", P.HELLFIRE)
	t.set_color(&"font_focus_color", &"GhostButton", P.HELLFIRE)
	t.set_color(&"font_pressed_color", &"GhostButton", P.BONE_BRIGHT)
	t.set_color(&"font_hover_pressed_color", &"GhostButton", P.BONE_BRIGHT)
	t.set_color(&"font_disabled_color", &"GhostButton", Color(P.ASH_TEXT, 0.35))

	# Tabs: flat until pressed, then an ember underline.
	t.set_type_variation(&"TabButton", &"Button")
	var tab_off := _box(Color(0, 0, 0, 0.25), Color(0, 0, 0, 0), 0, 0, 18.0, 8.0)
	var tab_hover := _box(Color(0.14, 0.05, 0.03, 0.6), Color(0, 0, 0, 0), 0, 0, 18.0, 8.0)
	var tab_on := _box(Color(0.18, 0.06, 0.035, 0.85), P.EMBER, 0, 0, 18.0, 8.0, 10, Color(P.EMBER, 0.18))
	tab_on.border_width_bottom = 2
	t.set_stylebox(&"normal", &"TabButton", tab_off)
	t.set_stylebox(&"hover", &"TabButton", tab_hover)
	t.set_stylebox(&"pressed", &"TabButton", tab_on)
	t.set_stylebox(&"hover_pressed", &"TabButton", tab_on)
	t.set_stylebox(&"disabled", &"TabButton", tab_off)
	t.set_stylebox(&"focus", &"TabButton", _focus_ring())
	t.set_color(&"font_color", &"TabButton", P.ASH_TEXT)
	t.set_color(&"font_hover_color", &"TabButton", P.BONE)
	t.set_color(&"font_focus_color", &"TabButton", P.BONE)
	t.set_color(&"font_pressed_color", &"TabButton", P.BRIMSTONE)
	t.set_color(&"font_hover_pressed_color", &"TabButton", P.HELLFIRE)
	t.set_font(&"font", &"TabButton", caption)
	t.set_font_size(&"font_size", &"TabButton", 18)

	t.set_type_variation(&"SlotButton", &"Button")
	_button_styles(t, &"SlotButton", Color(0.06, 0.03, 0.026, 0.94), Color(0.14, 0.055, 0.035, 0.96),
		Color(0.22, 0.05, 0.03, 0.97), P.IRON, P.EMBER, P.BONE, P.BONE_BRIGHT, 6.0, 6.0)

	# ---------------------------------------------------------------- Panels
	var panel := _box(P.OBSIDIAN, P.EMBER_DIM, 1, 3, 22.0, 20.0, 22, Color(0, 0, 0, 0.65))
	panel.border_width_top = 2
	t.set_stylebox(&"panel", &"PanelContainer", panel)
	t.set_stylebox(&"panel", &"Panel", panel)

	t.set_type_variation(&"InfernalPanel", &"PanelContainer")
	var heavy := _box(Color(0.05, 0.024, 0.022, 0.96), P.EMBER_DIM, 2, 4, 28.0, 24.0, 30,
		Color(P.EMBER, 0.12))
	heavy.border_width_top = 3
	heavy.border_color = Color("8a3a1a")
	t.set_stylebox(&"panel", &"InfernalPanel", heavy)

	t.set_type_variation(&"CardPanel", &"PanelContainer")
	t.set_stylebox(&"panel", &"CardPanel", _forged(Color(0.075, 0.038, 0.032, 0.94), P.IRON, 14.0, 12.0, 8))

	t.set_type_variation(&"InsetPanel", &"PanelContainer")
	var inset := _box(Color(0.0, 0.0, 0.0, 0.42), Color(P.IRON, 0.8), 1, 2, 12.0, 10.0)
	inset.border_width_bottom = 0
	t.set_stylebox(&"panel", &"InsetPanel", inset)

	t.set_type_variation(&"HeaderBand", &"PanelContainer")
	var band := _box(Color(0.28, 0.045, 0.03, 0.88), P.EMBER, 0, 0, 24.0, 6.0, 12, Color(P.BLOOD, 0.3))
	band.border_width_top = 1
	band.border_width_bottom = 1
	band.border_color = Color(P.EMBER, 0.7)
	t.set_stylebox(&"panel", &"HeaderBand", band)

	t.set_type_variation(&"HudPanel", &"PanelContainer")
	t.set_stylebox(&"panel", &"HudPanel", _box(P.OBSIDIAN_SOFT, P.IRON, 1, 2, 14.0, 4.0, 8))

	t.set_type_variation(&"Badge", &"PanelContainer")
	t.set_stylebox(&"panel", &"Badge", _box(Color(0.1, 0.035, 0.028, 0.92), P.BRIMSTONE_DIM, 1, 2, 8.0, 1.0, 4))

	t.set_type_variation(&"Chip", &"PanelContainer")
	t.set_stylebox(&"panel", &"Chip", _box(Color(0.06, 0.03, 0.026, 0.88), P.EMBER_DIM, 1, 2, 3.0, 3.0, 6))

	t.set_type_variation(&"LevelBadge", &"PanelContainer")
	var lvl := _box(Color(0.12, 0.03, 0.02, 0.92), P.BRIMSTONE, 1, 3, 6.0, 4.0, 12, Color(P.EMBER, 0.25))
	lvl.border_width_bottom = 2
	t.set_stylebox(&"panel", &"LevelBadge", lvl)

	# ---------------------------------------------------------------- Labels
	t.set_color(&"font_color", &"Label", P.BONE)
	t.set_color(&"font_outline_color", &"Label", Color(0, 0, 0, 0.85))
	t.set_constant(&"outline_size", &"Label", 4)
	t.set_color(&"font_shadow_color", &"Label", Color(0, 0, 0, 0.45))
	t.set_constant(&"shadow_offset_x", &"Label", 0)
	t.set_constant(&"shadow_offset_y", &"Label", 2)
	t.set_constant(&"shadow_outline_size", &"Label", 4)

	_label_type(t, &"InkLabel", null, 0, P.BONE, 2, 0.7)
	t.set_color(&"font_shadow_color", &"InkLabel", Color(0, 0, 0, 0))

	_label_type(t, &"TitleLabel", display, 60, P.BRIMSTONE, 6, 0.9)
	t.set_color(&"font_shadow_color", &"TitleLabel", Color(P.BLOOD_DEEP, 0.85))
	t.set_constant(&"shadow_offset_x", &"TitleLabel", 0)
	t.set_constant(&"shadow_offset_y", &"TitleLabel", 3)
	t.set_constant(&"shadow_outline_size", &"TitleLabel", 14)

	_label_type(t, &"LoreLabel", lore, 18, P.ASH_TEXT, 2, 0.7)
	t.set_color(&"font_shadow_color", &"LoreLabel", Color(0, 0, 0, 0))

	_label_type(t, &"HeaderLabel", header, 24, P.BRIMSTONE, 4, 0.9)
	t.set_color(&"font_shadow_color", &"HeaderLabel", Color(P.BLOOD_DEEP, 0.7))
	t.set_constant(&"shadow_outline_size", &"HeaderLabel", 8)

	_label_type(t, &"CaptionLabel", caption, 14, P.ASH_TEXT, 2, 0.7)
	t.set_color(&"font_shadow_color", &"CaptionLabel", Color(0, 0, 0, 0))

	_label_type(t, &"ValueLabel", numbers, 22, P.BRIMSTONE, 4, 0.9)

	_label_type(t, &"CostLabel", numbers, 20, P.SOUL, 4, 0.9)

	_label_type(t, &"DangerLabel", header, 20, P.DANGER, 4, 0.9)

	# ---------------------------------------------------------------- RichTextLabel
	t.set_color(&"default_color", &"RichTextLabel", P.BONE)
	t.set_color(&"font_outline_color", &"RichTextLabel", Color(0, 0, 0, 0.8))
	t.set_constant(&"outline_size", &"RichTextLabel", 2)
	t.set_font(&"bold_font", &"RichTextLabel", numbers)
	t.set_font(&"italics_font", &"RichTextLabel", lore)
	t.set_font_size(&"normal_font_size", &"RichTextLabel", 18)
	t.set_font_size(&"bold_font_size", &"RichTextLabel", 18)
	t.set_font_size(&"italics_font_size", &"RichTextLabel", 18)

	# ---------------------------------------------------------------- Progress bars
	t.set_stylebox(&"background", &"ProgressBar", _box(Color(0, 0, 0, 0.6), P.IRON, 1, 0, 0.0, 0.0, 4))
	t.set_stylebox(&"fill", &"ProgressBar", _box(P.BLOOD, Color(0, 0, 0, 0), 0, 0, 0.0, 0.0))
	t.set_color(&"font_color", &"ProgressBar", P.BONE)
	t.set_color(&"font_outline_color", &"ProgressBar", Color(0, 0, 0, 0.85))
	t.set_constant(&"outline_size", &"ProgressBar", 3)

	t.set_type_variation(&"XPBar", &"ProgressBar")
	t.set_stylebox(&"background", &"XPBar", _box(Color(0, 0, 0, 0.55), P.IRON, 1, 0, 0.0, 0.0, 3))
	t.set_stylebox(&"fill", &"XPBar", _box(P.ASCEND, Color(0, 0, 0, 0), 0, 0, 0.0, 0.0, 6, Color(P.HELLFIRE, 0.25)))

	t.set_type_variation(&"HPBar", &"ProgressBar")
	t.set_stylebox(&"background", &"HPBar", _box(Color(0, 0, 0, 0.62), P.EMBER_DIM, 1, 0, 0.0, 0.0, 4))
	t.set_stylebox(&"fill", &"HPBar", _box(P.BLOOD, Color(0, 0, 0, 0), 0, 0, 0.0, 0.0))

	t.set_type_variation(&"ResourceBar", &"ProgressBar")
	t.set_stylebox(&"background", &"ResourceBar", _box(Color(0, 0, 0, 0.6), P.IRON, 1, 0, 0.0, 0.0, 3))
	t.set_stylebox(&"fill", &"ResourceBar", _box(P.WRATH, Color(0, 0, 0, 0), 0, 0, 0.0, 0.0, 6, Color(P.WRATH, 0.25)))

	t.set_type_variation(&"SoulBar", &"ProgressBar")
	t.set_stylebox(&"background", &"SoulBar", _box(Color(0, 0, 0, 0.6), P.IRON, 1, 0, 0.0, 0.0, 3))
	t.set_stylebox(&"fill", &"SoulBar", _box(P.SOUL, Color(0, 0, 0, 0), 0, 0, 0.0, 0.0, 6, Color(P.SOUL, 0.2)))

	# ---------------------------------------------------------------- Sliders
	var track := _box(Color(0, 0, 0, 0.6), P.IRON, 1, 0, 0.0, 2.0)
	var track_fill := _box(Color(P.EMBER, 0.8), Color(0, 0, 0, 0), 0, 0, 0.0, 2.0)
	var track_hi := _box(P.HELLFIRE, Color(0, 0, 0, 0), 0, 0, 0.0, 2.0)
	t.set_stylebox(&"slider", &"HSlider", track)
	t.set_stylebox(&"grabber_area", &"HSlider", track_fill)
	t.set_stylebox(&"grabber_area_highlight", &"HSlider", track_hi)
	var slider_focus := _focus_ring()
	slider_focus.set_expand_margin_all(6.0)
	t.set_stylebox(&"focus", &"HSlider", slider_focus)

	# ---------------------------------------------------------------- Toggles
	for type: StringName in [&"CheckButton", &"CheckBox"]:
		var empty := StyleBoxEmpty.new()
		empty.set_content_margin_all(4.0)
		for st: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]:
			t.set_stylebox(st, type, empty)
		var ring := _focus_ring()
		ring.expand_margin_top = 0.0
		ring.expand_margin_bottom = 0.0
		t.set_stylebox(&"focus", type, ring)
		t.set_font(&"font", type, body)
		t.set_font_size(&"font_size", type, 20)
		t.set_color(&"font_color", type, P.BONE)
		t.set_color(&"font_hover_color", type, P.HELLFIRE)
		t.set_color(&"font_focus_color", type, P.HELLFIRE)
		t.set_color(&"font_pressed_color", type, P.BONE)
		t.set_color(&"font_hover_pressed_color", type, P.HELLFIRE)
		t.set_constant(&"outline_size", type, 2)

	# ---------------------------------------------------------------- Text input / dropdowns
	var field := _box(Color(0, 0, 0, 0.5), P.IRON, 1, 2, 10.0, 6.0)
	var field_focus := _box(Color(0.08, 0.03, 0.02, 0.6), P.EMBER, 1, 2, 10.0, 6.0, 8, Color(P.EMBER, 0.25))
	t.set_stylebox(&"normal", &"LineEdit", field)
	t.set_stylebox(&"focus", &"LineEdit", field_focus)
	t.set_stylebox(&"read_only", &"LineEdit", field)
	t.set_color(&"font_color", &"LineEdit", P.BONE)
	t.set_color(&"caret_color", &"LineEdit", P.HELLFIRE)
	t.set_color(&"selection_color", &"LineEdit", Color(P.EMBER, 0.4))
	t.set_color(&"font_placeholder_color", &"LineEdit", P.SMOKE)

	_button_styles(t, &"OptionButton", Color(0.07, 0.035, 0.03, 0.92), Color(0.16, 0.06, 0.035, 0.95),
		Color(0.24, 0.05, 0.03, 0.97), P.EMBER_DIM, P.EMBER, P.BONE, P.BONE_BRIGHT, 14.0, 6.0)
	t.set_font(&"font", &"OptionButton", body)
	t.set_font_size(&"font_size", &"OptionButton", 18)

	t.set_stylebox(&"panel", &"PopupMenu", _box(Color(0.05, 0.025, 0.022, 0.97), P.EMBER_DIM, 1, 2, 6.0, 6.0, 12))
	t.set_stylebox(&"hover", &"PopupMenu", _box(Color(0.24, 0.07, 0.035, 0.9), Color(0, 0, 0, 0), 0, 1, 6.0, 2.0))
	t.set_color(&"font_color", &"PopupMenu", P.BONE)
	t.set_color(&"font_hover_color", &"PopupMenu", P.HELLFIRE)
	t.set_color(&"font_disabled_color", &"PopupMenu", P.SMOKE)

	# ---------------------------------------------------------------- Scroll bars
	var sb_track := _box(Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 0, 0, 3.0, 3.0)
	var sb_grab := _box(Color(P.EMBER_DIM, 0.9), Color(0, 0, 0, 0), 0, 1, 3.0, 3.0)
	var sb_grab_hi := _box(P.EMBER, Color(0, 0, 0, 0), 0, 1, 3.0, 3.0)
	for type: StringName in [&"VScrollBar", &"HScrollBar"]:
		t.set_stylebox(&"scroll", type, sb_track)
		t.set_stylebox(&"grabber", type, sb_grab)
		t.set_stylebox(&"grabber_highlight", type, sb_grab_hi)
		t.set_stylebox(&"grabber_pressed", type, sb_grab_hi)

	# ---------------------------------------------------------------- Misc
	t.set_stylebox(&"panel", &"TooltipPanel", _box(Color(0.045, 0.022, 0.02, 0.96), P.EMBER_DIM, 1, 2, 12.0, 8.0, 8))
	t.set_color(&"font_color", &"TooltipLabel", P.BONE)
	t.set_font_size(&"font_size", &"TooltipLabel", 16)
	var hline := StyleBoxLine.new()
	hline.color = Color(P.EMBER_DIM, 0.85)
	hline.thickness = 1
	t.set_stylebox(&"separator", &"HSeparator", hline)
	t.set_constant(&"separation", &"HSeparator", 9)
	var vline := StyleBoxLine.new()
	vline.color = Color(P.EMBER_DIM, 0.85)
	vline.thickness = 1
	vline.vertical = true
	t.set_stylebox(&"separator", &"VSeparator", vline)
	t.set_constant(&"separation", &"VSeparator", 9)
	return t
