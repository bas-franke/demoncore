class_name CurrencyCounter
extends HBoxContainer
## Glyph + amount that rolls toward its target, pops on gain and shakes red on a failed spend.
## Used on the HUD (souls this run) and in ShopPanel (meta currency). Duck-typed, no autoload needed.
##
##   var c := CurrencyCounter.new()
##   c.setup("◈", UIPalette.SOUL, "Souls")   # glyph, colour, tooltip
##   c.set_amount(120)                          # rolls; c.set_amount(120, true) snaps
##   c.deny()                                   # "can't afford" shake

## Optional painted icon; replaces the glyph when set.
var icon_texture: Texture2D:
	set(v):
		icon_texture = v
		_refresh_icon()

var amount := 0
var font_size := 22:
	set(v):
		font_size = v
		if _value:
			_value.add_theme_font_size_override(&"font_size", v)
			_glyph.custom_minimum_size = Vector2(v, v) * 0.9

var _shown := 0.0
var _glyph: GlyphIcon  # painted in code (no emoji font)
var _icon: TextureRect
var _value: Label
var _color := Color("7ff0c8")
var _pop_tw: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", 6)
	alignment = BoxContainer.ALIGNMENT_END
	_glyph = GlyphIcon.new()
	_glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_glyph)
	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.visible = false
	add_child(_icon)
	_value = Label.new()
	_value.theme_type_variation = &"ValueLabel"
	_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_value.text = "0"
	add_child(_value)
	font_size = font_size


func setup(glyph: String, color: Color, tooltip := "") -> void:
	_color = color
	_glyph.glyph = glyph
	_glyph.color = color
	_value.add_theme_color_override(&"font_color", color.lerp(UIPalette.BONE_BRIGHT, 0.35))
	tooltip_text = tooltip
	if tooltip != "":
		mouse_filter = Control.MOUSE_FILTER_PASS


func set_amount(v: int, snap := false) -> void:
	var gained := v > amount
	amount = v
	if snap:
		_shown = v
		_value.text = _fmt(v)
	elif gained:
		_pop()


## Shake + red flash, for "not enough".
func deny() -> void:
	var base_x := position.x
	var tw := create_tween()
	_value.add_theme_color_override(&"font_color", UIPalette.DANGER)
	for i in 4:
		tw.tween_property(self, "position:x", base_x + (6.0 if i % 2 == 0 else -6.0), 0.04)
	tw.tween_property(self, "position:x", base_x, 0.04)
	tw.tween_callback(func() -> void:
		_value.add_theme_color_override(&"font_color", _color.lerp(UIPalette.BONE_BRIGHT, 0.35)))


func _process(delta: float) -> void:
	if absf(_shown - amount) < 0.5:
		if int(_shown) != amount:
			_shown = amount
			_value.text = _fmt(amount)
		return
	# Roll quickly for big jumps, at least ~1 unit per frame for small ones.
	var step := maxf(absf(amount - _shown) * 10.0 * delta, 60.0 * delta)
	_shown = move_toward(_shown, amount, step)
	_value.text = _fmt(roundi(_shown))


func _pop() -> void:
	if _pop_tw and _pop_tw.is_valid():
		_pop_tw.kill()
	_value.pivot_offset = _value.size * 0.5
	_value.scale = Vector2(1.25, 1.25)
	_value.modulate = Color(1.5, 1.5, 1.5)
	_pop_tw = create_tween().set_parallel()
	_pop_tw.tween_property(_value, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop_tw.tween_property(_value, "modulate", Color.WHITE, 0.4)


func _refresh_icon() -> void:
	_icon.texture = icon_texture
	_icon.visible = icon_texture != null
	_glyph.visible = icon_texture == null
	_icon.custom_minimum_size = Vector2(font_size, font_size) * 1.1


## 1234567 -> "1,234,567"
static func _fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
