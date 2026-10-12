class_name InfernalBar
extends Control
## A themed meter drawn in code: dark well, lingering "lost" trail, glossy fill with a hot top edge,
## optional segment ticks and centred text. Use it for life, wrath/mana, shields, boss health.
##
##   var bar := InfernalBar.new()
##   bar.fill_color = UIPalette.WRATH
##   bar.set_values(30, 100)          # value, max (the fill eases, the trail lingers then drains)
##   bar.text_mode = InfernalBar.TEXT_VALUE_MAX
##
## Signals: emptied, filled (fire once when the value reaches 0 / max).

signal emptied
signal filled

enum { TEXT_NONE, TEXT_VALUE, TEXT_VALUE_MAX, TEXT_PERCENT, TEXT_CUSTOM }

@export var max_value := 100.0:
	set(v):
		max_value = maxf(v, 0.001)
		queue_redraw()
## Named setter: assignments to `value` inside _set_value write the field directly (no recursion).
@export var value := 100.0: set = _set_value
@export var fill_color := Color("b3201a"):
	set(v):
		fill_color = v
		queue_redraw()
## The lingering segment that shows recent loss (set alpha 0 to disable).
@export var trail_color := Color(0.95, 0.72, 0.4, 0.75)
@export var back_color := Color(0.0, 0.0, 0.0, 0.62)
@export var frame_color := Color("7a3218")
## Vertical lines every `segment_value` units (0 = none). Handy for "every 25 HP" ticks.
@export var segment_value := 0.0
@export var text_mode := TEXT_NONE:
	set(v):
		text_mode = v
		queue_redraw()
@export var custom_text := "":
	set(v):
		custom_text = v
		queue_redraw()
@export var font_size := 13
## Seconds the trail waits before draining; drain speed in fractions of max per second.
@export var trail_delay := 0.5
@export var trail_speed := 0.5
## Fill eases toward the target at this rate (higher = snappier). 0 = instant.
@export var ease_speed := 18.0
## Pulses the fill when below this fraction (0 = never). Used for low-life warnings.
@export var low_warning := 0.0

var _shown := 100.0
var _trail := 100.0
var _wait := 0.0
var _flash := 0.0
var _gain_flash := 0.0
var _was_empty := false
var _was_full := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shown = value
	_trail = value
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(160.0, 10.0)


## Sets max first, then value, so the ratio never spikes.
func set_values(v: float, max_v: float) -> void:
	max_value = max_v
	value = v


## Jumps the shown fill and trail to the current value (e.g. after a respawn).
func snap() -> void:
	_shown = value
	_trail = value
	_wait = 0.0
	queue_redraw()


func _set_value(v: float) -> void:
	var nv := clampf(v, 0.0, max_value)
	if nv < value - 0.0001:
		_wait = trail_delay
		_flash = 0.25 if UIPalette.calm() else 1.0
	elif nv > value + 0.0001:
		_gain_flash = 1.0
	value = nv
	if nv <= 0.0 and not _was_empty:
		_was_empty = true
		emptied.emit()
	elif nv > 0.0:
		_was_empty = false
	if nv >= max_value and not _was_full:
		_was_full = true
		filled.emit()
	elif nv < max_value:
		_was_full = false
	queue_redraw()


func _process(delta: float) -> void:
	var dirty := false
	if not is_equal_approx(_shown, value):
		_shown = value if ease_speed <= 0.0 else lerpf(_shown, value, 1.0 - exp(-ease_speed * delta))
		if absf(_shown - value) < max_value * 0.001:
			_shown = value
		dirty = true
	if _trail < _shown:
		_trail = _shown
		dirty = true
	elif _trail > _shown:
		if _wait > 0.0:
			_wait -= delta
		else:
			# Drain faster when the gap is large so big hits don't crawl.
			var gap := (_trail - _shown) / max_value
			_trail = maxf(_shown, _trail - max_value * trail_speed * (1.0 + gap * 3.0) * delta)
		dirty = true
	if _flash > 0.0 or _gain_flash > 0.0:
		_flash = maxf(_flash - delta * 4.0, 0.0)
		_gain_flash = maxf(_gain_flash - delta * 3.0, 0.0)
		dirty = true
	if low_warning > 0.0 and value / max_value <= low_warning and value > 0.0:
		dirty = true
	if dirty:
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	# Soft shadow, well, frame.
	draw_rect(r.grow(2.0), Color(0, 0, 0, 0.35))
	draw_rect(r, back_color)
	var inner := r.grow(-1.0)
	var w := inner.size.x
	var trail_r := clampf(_trail / max_value, 0.0, 1.0)
	var fill_r := clampf(_shown / max_value, 0.0, 1.0)
	if trail_r > fill_r and trail_color.a > 0.0:
		draw_rect(Rect2(inner.position, Vector2(w * trail_r, inner.size.y)), trail_color)
	if fill_r > 0.0:
		var col := fill_color
		if low_warning > 0.0 and value / max_value <= low_warning:
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.009)
			col = col.lerp(Color(1.0, 0.55, 0.4), pulse * 0.35)
		col = col.lerp(Color(1.0, 0.92, 0.8), _flash * 0.45)
		col = col.lerp(Color.WHITE, _gain_flash * 0.25)
		var fr := Rect2(inner.position, Vector2(w * fill_r, inner.size.y))
		draw_rect(fr, col)
		# Darker lower half and a hot top edge give the fill some volume.
		var lower_h := floorf(fr.size.y * 0.45)
		draw_rect(Rect2(fr.position.x, fr.end.y - lower_h, fr.size.x, lower_h), Color(0, 0, 0, 0.22))
		draw_rect(Rect2(fr.position, Vector2(fr.size.x, maxf(1.0, fr.size.y * 0.18))),
			Color(col.lightened(0.45), 0.7))
		# Bright leading edge.
		if fill_r < 1.0:
			draw_rect(Rect2(fr.end.x - 1.0, fr.position.y, 1.0, fr.size.y), Color(1, 0.9, 0.75, 0.55))
	if segment_value > 0.0 and max_value / segment_value < 60.0:
		var v := segment_value
		while v < max_value - 0.001:
			var x := inner.position.x + w * (v / max_value)
			draw_line(Vector2(x, inner.position.y), Vector2(x, inner.end.y), Color(0, 0, 0, 0.55), 1.0)
			v += segment_value
	draw_rect(r, frame_color, false, 1.0)
	_draw_text()


func _draw_text() -> void:
	var s := ""
	match text_mode:
		TEXT_VALUE: s = str(roundi(value))
		TEXT_VALUE_MAX: s = "%d / %d" % [roundi(value), roundi(max_value)]
		TEXT_PERCENT: s = "%d%%" % roundi(100.0 * value / max_value)
		TEXT_CUSTOM: s = custom_text
	if s.is_empty():
		return
	var font := UIPalette.serif_bold()
	var ts := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pos := Vector2((size.x - ts.x) * 0.5, (size.y + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5)
	draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0, 0, 0, 0.9))
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UIPalette.BONE_BRIGHT)
