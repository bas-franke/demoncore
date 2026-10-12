class_name UIPalette
## Shared colours and fonts for every DemonCore screen. The theme generator
## (tools/build_theme.gd) and all UI scripts read from here, so the infernal look stays cohesive.
##
## Use:  label.add_theme_color_override(&"font_color", UIPalette.BONE)
##       label.add_theme_font_override(&"font", UIPalette.display_font())
##
## Palette idea: obsidian panels, ember-lit borders, brimstone-gold headings, bone-white body text.
## Holy/enemy things use the cold HOLY tones so they read as "the other side" at a glance.

# ---------------------------------------------------------------- base
const VOID := Color("080404")              ## deepest backdrop
const OBSIDIAN := Color(0.055, 0.03, 0.028, 0.92)   ## default panel fill
const OBSIDIAN_SOFT := Color(0.055, 0.03, 0.028, 0.74)
const SCORCH := Color("1c0d0a")            ## raised surfaces (cards, slots)
const ASH := Color("2a1813")               ## hovered surfaces

# ---------------------------------------------------------------- lines and metals
const IRON := Color("4a2a1f")              ## dim borders
const EMBER_DIM := Color("7a3218")         ## default border
const EMBER := Color("e0662a")             ## hover / focus border, accents
const HELLFIRE := Color("ffb347")          ## hottest highlight
const BRIMSTONE := Color("e6b35a")         ## headings, numbers, gold
const BRIMSTONE_DIM := Color("a77b38")

# ---------------------------------------------------------------- text
const BONE := Color("eadcc4")              ## body text
const BONE_BRIGHT := Color("fff1da")       ## emphasised text
const ASH_TEXT := Color("a08a7c")          ## captions, flavour, disabled-ish
const SMOKE := Color("6d5a50")             ## faint text

# ---------------------------------------------------------------- semantic
const BLOOD := Color("b3201a")             ## player life
const BLOOD_DEEP := Color("5a0d0a")
const BLOOD_BRIGHT := Color("e8432c")
const WRATH := Color("ff7a1f")             ## player resource (wrath / fury / mana)
const WRATH_DEEP := Color("7a2a06")
const SOUL := Color("7ff0c8")              ## soul currency (run + meta)
const SOUL_DEEP := Color("1d5a4a")
const ASCEND := Color("f2c66b")            ## XP / ascension
const HOLY := Color("fff4cf")              ## angels, bosses, holy damage
const HOLY_GOLD := Color("ffd77a")
const HOLY_BLUE := Color("9fd4ff")
const VENOM := Color("9be05a")             ## healing / regeneration
const DANGER := Color("ff3b2f")
const LOCKED := Color("5b4b45")

# ---------------------------------------------------------------- rarity (boons, shop items)
const RARITY_COLORS := {
	&"common": Color("bfae9a"),
	&"uncommon": Color("7fd07a"),
	&"rare": Color("5fa8ff"),
	&"epic": Color("c46bff"),
	&"legendary": Color("ff9a2e"),
	&"cursed": Color("ff3b4f"),
}

## Font families tried in order. All are optional system fonts; Godot falls back gracefully.
const SERIF_NAMES := ["Cinzel", "Trajan Pro", "Cormorant Garamond", "EB Garamond", "Garamond",
	"Palatino Linotype", "Book Antiqua", "Constantia", "Georgia", "Times New Roman", "serif"]
const BLACKLETTER_NAMES := ["UnifrakturMaguntia", "Old English Text MT", "Cinzel Decorative",
	"Cinzel", "Trajan Pro", "Palatino Linotype", "Book Antiqua", "Georgia", "serif"]

static var _serif: SystemFont
static var _serif_bold: SystemFont
static var _display: FontVariation
static var _blackletter: SystemFont


## True when the player asked for fewer flashes (Settings.reduce_flashes): skip pulses and glows.
static func calm() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var st := tree.root.get_node_or_null(^"Settings") if tree else null
	return st != null and st.get(&"reduce_flashes") == true


## Colour-blind-safe rarity cue: a pip count that rises with the tier (always shown beside the
## tier name, never colour alone). "cursed" gets a cross.
const RARITY_MARKS := {
	&"common": "◆", &"uncommon": "◆◆", &"rare": "◆◆◆", &"epic": "◆◆◆◆", &"legendary": "◆◆◆◆◆",
	&"cursed": "✕",
}


static func rarity_mark(rarity: Variant) -> String:
	return RARITY_MARKS.get(StringName(str(rarity).to_lower()), "◆")


static func rarity_color(rarity: Variant) -> Color:
	var key := StringName(str(rarity).to_lower())
	return RARITY_COLORS.get(key, RARITY_COLORS[&"common"])


## Roman numeral for ranks and levels (shared implementation in TextFormat).
static func roman(n: int) -> String:
	return TextFormat.roman(n)


## Body serif (regular weight).
static func serif() -> SystemFont:
	if _serif == null:
		_serif = _sys(SERIF_NAMES, 500)
	return _serif


## Heavy serif for numbers on the HUD and damage figures.
static func serif_bold() -> SystemFont:
	if _serif_bold == null:
		_serif_bold = _sys(SERIF_NAMES, 700)
	return _serif_bold


## Wide-tracked display face for titles.
static func display_font() -> FontVariation:
	if _display == null:
		_display = FontVariation.new()
		_display.base_font = serif()
		_display.spacing_glyph = 6
		_display.variation_embolden = 0.2
	return _display


## Gothic face for big set pieces (death screen, logo). Falls back to the serif.
static func blackletter() -> SystemFont:
	if _blackletter == null:
		_blackletter = _sys(BLACKLETTER_NAMES, 600)
	return _blackletter


static func _sys(names: Array, weight: int) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(names)
	f.font_weight = weight
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_LIGHT
	f.allow_system_fallback = true
	return f


## Flat style box helper used by components that draw their own frames.
static func box(bg: Color, border: Color = Color.TRANSPARENT, border_w := 0, radius := 2,
		margin := 0.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 4
	sb.anti_aliasing = radius > 0
	sb.set_content_margin_all(margin)
	return sb


## Vertical/horizontal soft gradient texture (cheap backdrops, rules, vignettes).
static func gradient(offsets: PackedFloat32Array, colors: PackedColorArray, vertical := false) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = offsets
	g.colors = colors
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 1 if vertical else 256
	tex.height = 64 if vertical else 1
	tex.fill_from = Vector2.ZERO
	tex.fill_to = Vector2(0.0, 1.0) if vertical else Vector2(1.0, 0.0)
	return tex


## Thin rule that fades out at both ends (under titles, between sections).
static func rule(width: float, color: Color = BRIMSTONE) -> TextureRect:
	var r := TextureRect.new()
	r.texture = gradient(PackedFloat32Array([0.0, 0.5, 1.0]),
		PackedColorArray([Color(color, 0.0), Color(color, 0.9), Color(color, 0.0)]))
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.custom_minimum_size = Vector2(width, 2.0)
	r.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
