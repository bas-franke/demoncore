class_name CooldownSlot
extends Control
## Square ability slot: framed icon (texture or text glyph), a dark clockwise sweep while on
## cooldown with the seconds left, a key hint in the corner, optional charge count, and an ember
## flash when it comes off cooldown. Drawn in code, so it scales with custom_minimum_size.
##
##   var slot := CooldownSlot.new()
##   slot.setup(&"dash", "Dash", icon_tex_or_null, "⚡", UIPalette.WRATH, "Space")
##   slot.set_cooldown(remaining, total)   # call every frame or on change
##   slot.set_charges(2)                   # -1 hides the counter
##   slot.set_disabled(true)               # e.g. not enough wrath: greys the icon
##   slot.trigger()                        # brief press pulse when the ability fires

signal ready_again

var ability_id: StringName
var title := ""
var icon: Texture2D
var glyph := "?"
var tint := Color("e0662a")
var key_hint := ""

var _remaining := 0.0
var _total := 0.0
var _charges := -1
var _disabled := false
var _ready_flash := 0.0
var _press := 0.0
## Glyph fallback painted by GlyphIcon (no emoji font needed); the overlay draws the sweep, frame
## and texts above it.
var _glyph_node: GlyphIcon
var _overlay: Control


func _init() -> void:
	custom_minimum_size = Vector2(54.0, 54.0)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_glyph_node = GlyphIcon.new()
	_glyph_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["offset_left", "offset_top"]:
		_glyph_node.set(side, 9.0)
	for side: String in ["offset_right", "offset_bottom"]:
		_glyph_node.set(side, -9.0)
	add_child(_glyph_node)
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


## Redraws the well and the overlay together.
func _redraw() -> void:
	queue_redraw()
	if _overlay:
		_overlay.queue_redraw()


func setup(id: StringName, p_title: String, p_icon: Texture2D, p_glyph: String, p_tint: Color,
		p_key: String = "") -> void:
	ability_id = id
	title = p_title
	icon = p_icon
	glyph = p_glyph
	tint = p_tint
	key_hint = p_key
	tooltip_text = p_title
	_glyph_node.glyph = p_glyph
	_glyph_node.visible = p_icon == null
	_redraw()


func set_cooldown(remaining: float, total: float) -> void:
	var was_cooling := _remaining > 0.0
	_remaining = maxf(remaining, 0.0)
	_total = maxf(total, 0.0)
	if was_cooling and _remaining <= 0.0:
		_ready_flash = 0.3 if UIPalette.calm() else 1.0
		ready_again.emit()
	_redraw()


func set_charges(n: int) -> void:
	_charges = n
	_redraw()


func set_disabled(on: bool) -> void:
	if _disabled != on:
		_disabled = on
		_redraw()


func trigger() -> void:
	_press = 1.0
	_redraw()


func is_ready() -> bool:
	return _remaining <= 0.0 and not _disabled


func _process(delta: float) -> void:
	if _ready_flash > 0.0 or _press > 0.0:
		_ready_flash = maxf(_ready_flash - delta * 2.2, 0.0)
		_press = maxf(_press - delta * 6.0, 0.0)
		_redraw()


func _draw() -> void:
	var s := size
	var shrink := _press * 2.0
	var r := Rect2(Vector2(shrink, shrink), s - Vector2(shrink, shrink) * 2.0)
	# Shadow + well.
	draw_rect(r.grow(3.0), Color(0, 0, 0, 0.45))
	draw_rect(r, UIPalette.SCORCH.lerp(tint, 0.12))

	var inner := r.grow(-3.0)
	var dim := 1.0
	if _disabled:
		dim = 0.35
	elif _remaining > 0.0:
		dim = 0.6
	if icon:
		draw_texture_rect(icon, inner, false, Color(dim, dim, dim, 1.0))
	var col := tint.lerp(UIPalette.BONE_BRIGHT, 0.4)
	_glyph_node.color = Color(col.r * dim, col.g * dim, col.b * dim)


## Above the glyph: cooldown sweep, frame, key hint and charges.
func _draw_overlay() -> void:
	var s := size
	var shrink := _press * 2.0
	var r := Rect2(Vector2(shrink, shrink), s - Vector2(shrink, shrink) * 2.0)
	var inner := r.grow(-3.0)
	# Cooldown sweep: a dark pie covering the part still recharging, starting at 12 o'clock.
	if _remaining > 0.0 and _total > 0.0:
		var frac := clampf(_remaining / _total, 0.0, 1.0)
		_draw_sweep(inner, frac)
		var secs := ("%.1f" % _remaining) if _remaining < 3.0 else str(ceili(_remaining))
		_text_centered(inner, secs, int(inner.size.y * 0.36), UIPalette.BONE_BRIGHT)

	# Frame: ember when ready, iron while cooling, hot flash when it comes back.
	var frame := UIPalette.EMBER if is_ready() else UIPalette.IRON
	frame = frame.lerp(UIPalette.HELLFIRE, _ready_flash)
	_overlay.draw_rect(r, frame, false, 1.0 + _ready_flash * 1.5)
	if _ready_flash > 0.0:
		_overlay.draw_rect(r.grow(2.0 + 4.0 * (1.0 - _ready_flash)), Color(UIPalette.HELLFIRE, _ready_flash * 0.6), false, 1.5)

	# Key hint (top-left) and charges (bottom-right).
	var small := maxi(10, int(s.y * 0.22))
	if key_hint != "":
		var font := UIPalette.serif_bold()
		var kp := r.position + Vector2(3.0, font.get_ascent(small) + 1.0)
		_overlay.draw_string_outline(font, kp, key_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, small, 4, Color(0, 0, 0, 0.95))
		_overlay.draw_string(font, kp, key_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, small, UIPalette.BRIMSTONE)
	if _charges >= 0:
		var font := UIPalette.serif_bold()
		var t := str(_charges)
		var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
		var cp := r.end - Vector2(tw + 3.0, 3.0)
		_overlay.draw_string_outline(font, cp, t, HORIZONTAL_ALIGNMENT_LEFT, -1, small, 4, Color(0, 0, 0, 0.95))
		_overlay.draw_string(font, cp, t, HORIZONTAL_ALIGNMENT_LEFT, -1, small,
			UIPalette.BONE_BRIGHT if _charges > 0 else UIPalette.DANGER)


func _draw_sweep(rect: Rect2, frac: float) -> void:
	var c := rect.get_center()
	var radius := rect.size.length() * 0.5 + 1.0
	if frac >= 0.999:
		_overlay.draw_rect(rect, Color(0.0, 0.0, 0.0, 0.62))
		return
	var pts := PackedVector2Array([c])
	var steps := maxi(3, int(48.0 * frac))
	# The recharged part grows clockwise from 12 o'clock; the dark pie covers the rest of the turn.
	var start := -PI * 0.5 + TAU * (1.0 - frac)
	var end := -PI * 0.5 + TAU
	for i in steps + 1:
		var a := lerpf(start, end, float(i) / steps)
		var p := c + Vector2(cos(a), sin(a)) * radius
		# Clamp the circle to the square so the sweep fills the corners too.
		p = Vector2(clampf(p.x, rect.position.x, rect.end.x), clampf(p.y, rect.position.y, rect.end.y))
		# Skip near-duplicate points (they appear at the corners) so triangulation stays valid.
		if pts[pts.size() - 1].distance_squared_to(p) > 0.25:
			pts.append(p)
	# Draw as a triangle fan: the clamped outline has collinear runs that polygon triangulation
	# rejects, while single triangles (degenerate ones skipped) always draw.
	var shade := Color(0.0, 0.0, 0.0, 0.62)
	var cols := PackedColorArray([shade, shade, shade])
	for i in range(1, pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		if absf((a - c).cross(b - c)) > 0.01:
			_overlay.draw_primitive(PackedVector2Array([c, a, b]), cols, PackedVector2Array())
	# Ember hand on the sweep's leading edge so progress reads even on dark icons.
	if pts.size() >= 2:
		_overlay.draw_line(c, pts[1], Color(UIPalette.HELLFIRE, 0.8), 1.5, true)


func _text_centered(rect: Rect2, t: String, fs: int, col: Color) -> void:
	var font := UIPalette.serif_bold()
	var sz := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var p := rect.position + Vector2((rect.size.x - sz.x) * 0.5,
		(rect.size.y + font.get_ascent(fs) - font.get_descent(fs)) * 0.5)
	_overlay.draw_string_outline(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.95))
	_overlay.draw_string(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
