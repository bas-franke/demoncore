class_name DialoguePortrait
extends Control
## Speaker portrait for the dialogue box. Uses the speaker's "portrait" texture when it has one,
## otherwise draws a procedural medallion: a dark disc, a ring and rune ticks in the speaker's
## colour, and the speaker's glyph (a letter or symbol) in the middle. A slow ember pulse keeps it
## alive. Call set_speaker() with a DialogueDB speaker Dictionary.

var _color := Color("e8d6a6")
var _glyph := ""
var _texture: Texture2D
var _t := 0.0
var _font: Font


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func set_speaker(s: Dictionary) -> void:
	_color = s.get("color", Color("e8d6a6"))
	_glyph = str(s.get("glyph", ""))
	_texture = null
	var path := str(s.get("portrait", ""))
	if path != "" and ResourceLoader.exists(path):
		_texture = load(path) as Texture2D
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 4.0
	var pulse := 0.5 + 0.5 * sin(_t * 2.1)
	# Outer glow halo.
	for i in 4:
		var a := 0.06 * (4 - i) * (0.6 + 0.4 * pulse)
		draw_circle(c, r + 2.0 + i * 3.0, Color(_color, a))
	draw_circle(c, r, Color(0.05, 0.025, 0.025))
	if _texture:
		var side := r * 1.8
		draw_texture_rect(_texture, Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side)), false)
	else:
		# Inner ember gradient: stacked translucent discs.
		for i in 6:
			draw_circle(c + Vector2(0, r * 0.15), r * (0.85 - i * 0.12), Color(_color.darkened(0.6), 0.12))
		_draw_glyph(c, r, pulse)
	# Rings and rune ticks.
	draw_arc(c, r, 0.0, TAU, 64, _color.darkened(0.15), 3.0, true)
	draw_arc(c, r - 7.0, 0.0, TAU, 64, Color(_color, 0.35), 1.0, true)
	var spin := _t * 0.15
	for i in 12:
		var ang := spin + TAU * i / 12.0
		var d := Vector2.from_angle(ang)
		var tick_len := 6.0 if i % 3 == 0 else 3.0
		draw_line(c + d * (r - 7.0), c + d * (r - 7.0 - tick_len), Color(_color, 0.6), 1.5, true)


func _draw_glyph(c: Vector2, r: float, pulse: float) -> void:
	if _glyph == "" or _font == null:
		return
	var fs := int(r * 1.05)
	var w := _font.get_string_size(_glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := c + Vector2(-w * 0.5, fs * 0.36)
	draw_string_outline(_font, pos, _glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.8))
	draw_string(_font, pos, _glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			_color.lerp(Color(1, 0.95, 0.85), 0.15 + 0.15 * pulse))
