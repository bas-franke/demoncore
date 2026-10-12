class_name GlyphIcon
extends Control
## A small icon drawn in code from a glyph string, so the UI never depends on the OS emoji font.
## Known glyphs (emoji and a few symbols used across data/*.json) map to vector icons painted with
## polygons and arcs in `color`; anything else is drawn as a plain serif text glyph with an outline.
##
##   var g := GlyphIcon.new()
##   g.glyph = "🔥"            # -> painted flame
##   g.color = UIPalette.WRATH
##   g.custom_minimum_size = Vector2(32, 32)
##
## GlyphIcon.icon_id("⛓") -> &"chain" (or &"" if not a painted icon).
## GlyphIcon.plain("🔥")   -> a text-safe stand-in for Labels that can't host a GlyphIcon.

## glyph -> painted icon id
const MAP := {
	"🔥": &"flame", "🜂": &"flame", "♨": &"flame",
	"🩸": &"drop", "💧": &"drop",
	"⛓": &"chain", "🔗": &"chain",
	"🔒": &"lock",
	"⚡": &"bolt", "ϟ": &"bolt",
	"☠": &"skull", "💀": &"skull",
	"♥": &"heart", "♡": &"heart", "❤": &"heart",
	"⚔": &"swords", "🗡": &"swords",
	"♛": &"crown", "♕": &"crown", "👑": &"crown",
	"⛨": &"shield", "🛡": &"shield",
	"⛧": &"pentagram", "⛤": &"pentagram",
	"🏮": &"lantern",
	"🜏": &"sigil",
	"⌛": &"hourglass", "⏳": &"hourglass",
	"»": &"dash",
	"👁": &"eye",
	"🕯": &"candle",
}
## Text stand-ins for Labels (plain symbols every serif fallback has).
const PLAIN := {
	&"flame": "♦", &"drop": "♦", &"chain": "∞", &"lock": "×", &"bolt": "↯", &"skull": "☠",
	&"heart": "♥", &"swords": "✕", &"crown": "♛", &"shield": "◊", &"pentagram": "✶",
	&"lantern": "◊", &"sigil": "△", &"hourglass": "⧗", &"dash": "»", &"eye": "◉", &"candle": "ı",
}

@export var glyph := "✦":
	set(v):
		glyph = v
		queue_redraw()
@export var color := Color("e0662a"):
	set(v):
		color = v
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(24.0, 24.0)


static func icon_id(g: String) -> StringName:
	return MAP.get(g.strip_edges().replace("️", ""), &"")


static func plain(g: String) -> String:
	var id := icon_id(g)
	return PLAIN.get(id, g) if id != &"" else g


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var id := icon_id(glyph)
	if id == &"":
		_draw_text(s, o)
		return
	# Work in a 0..1 box: p(x, y) maps into the control.
	var dark := Color(0, 0, 0, 0.75)
	var hi := color.lightened(0.35)
	match id:
		&"flame":
			_poly(o, s, [[0.5, 0.05], [0.66, 0.3], [0.78, 0.5], [0.76, 0.72], [0.62, 0.9], [0.5, 0.95],
				[0.36, 0.9], [0.24, 0.72], [0.24, 0.5], [0.36, 0.38], [0.42, 0.55], [0.48, 0.3]], color, dark)
			_poly(o, s, [[0.5, 0.48], [0.6, 0.66], [0.58, 0.82], [0.5, 0.88], [0.42, 0.82], [0.42, 0.66]], hi, Color.TRANSPARENT)
		&"drop":
			_drop(o, s, dark)
		&"chain":
			for i in 3:
				var c := o + Vector2(0.25 + 0.25 * i, 0.5) * s
				_ring(c, Vector2(0.16, 0.11) * s, s * 0.07, color, i % 2 == 1)
		&"lock":
			draw_arc(o + Vector2(0.5, 0.42) * s, 0.18 * s, PI, TAU, 16, dark, s * 0.13)
			draw_arc(o + Vector2(0.5, 0.42) * s, 0.18 * s, PI, TAU, 16, color, s * 0.08)
			_rect(o, s, Rect2(0.24, 0.42, 0.52, 0.46), color, dark)
			draw_circle(o + Vector2(0.5, 0.62) * s, s * 0.06, dark)
		&"bolt":
			_poly(o, s, [[0.58, 0.04], [0.22, 0.56], [0.46, 0.56], [0.38, 0.96], [0.8, 0.4], [0.54, 0.4]], color, dark)
		&"skull":
			draw_circle(o + Vector2(0.5, 0.42) * s, s * 0.32 + 1.5, dark)
			draw_circle(o + Vector2(0.5, 0.42) * s, s * 0.32, color)
			_rect(o, s, Rect2(0.34, 0.62, 0.32, 0.24), color, dark)
			draw_circle(o + Vector2(0.38, 0.44) * s, s * 0.085, dark)
			draw_circle(o + Vector2(0.62, 0.44) * s, s * 0.085, dark)
			_poly(o, s, [[0.5, 0.55], [0.46, 0.63], [0.54, 0.63]], dark, Color.TRANSPARENT)
		&"heart":
			var pts := PackedVector2Array()
			for i in 33:
				var t := TAU * float(i) / 32.0
				var x := 16.0 * pow(sin(t), 3)
				var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
				pts.append(o + Vector2(0.5 + x / 38.0, 0.48 - y / 38.0) * s)
			_outline_fill(pts, color, dark)
		&"swords":
			for dir in [-1.0, 1.0]:
				var a := o + Vector2(0.5 - 0.34 * dir, 0.14) * s
				var b := o + Vector2(0.5 + 0.3 * dir, 0.8) * s
				draw_line(a, b, dark, s * 0.13)
				draw_line(a, b, color, s * 0.07)
				var g := o + Vector2(0.5 + 0.2 * dir, 0.68) * s
				var n := Vector2(0.6, 0.5 * -dir).normalized() * s * 0.13
				draw_line(g - n, g + n, hi, s * 0.06)
		&"crown":
			_poly(o, s, [[0.14, 0.78], [0.14, 0.3], [0.32, 0.5], [0.5, 0.2], [0.68, 0.5], [0.86, 0.3], [0.86, 0.78]], color, dark)
			for x in [0.14, 0.5, 0.86]:
				draw_circle(o + Vector2(x, 0.24 if x == 0.5 else 0.28) * s, s * 0.05, hi)
		&"shield":
			_poly(o, s, [[0.5, 0.08], [0.84, 0.2], [0.8, 0.56], [0.5, 0.92], [0.2, 0.56], [0.16, 0.2]], color, dark)
			draw_line(o + Vector2(0.5, 0.2) * s, o + Vector2(0.5, 0.78) * s, hi, s * 0.05)
		&"pentagram":
			var pts := PackedVector2Array()
			for i in 6:
				var a := PI * 0.5 + TAU * float(i * 2) / 5.0  # inverted: one point down
				pts.append(o + (Vector2(0.5, 0.5) + Vector2(cos(a), sin(a)) * 0.4) * s)
			draw_polyline(pts, dark, s * 0.11, true)
			draw_polyline(pts, color, s * 0.06, true)
			draw_arc(o + Vector2(0.5, 0.5) * s, 0.43 * s, 0.0, TAU, 32, color, s * 0.04, true)
		&"lantern":
			_rect(o, s, Rect2(0.3, 0.26, 0.4, 0.56), color, dark)
			_rect(o, s, Rect2(0.38, 0.36, 0.24, 0.36), hi, Color.TRANSPARENT)
			draw_arc(o + Vector2(0.5, 0.24) * s, 0.1 * s, PI, TAU, 10, color, s * 0.05)
		&"sigil":
			draw_arc(o + Vector2(0.5, 0.52) * s, 0.4 * s, 0.0, TAU, 32, dark, s * 0.1, true)
			draw_arc(o + Vector2(0.5, 0.52) * s, 0.4 * s, 0.0, TAU, 32, color, s * 0.05, true)
			var tri := PackedVector2Array([o + Vector2(0.5, 0.82) * s, o + Vector2(0.16, 0.3) * s,
				o + Vector2(0.84, 0.3) * s, o + Vector2(0.5, 0.82) * s])
			draw_polyline(tri, color, s * 0.05, true)
		&"hourglass":
			_poly(o, s, [[0.24, 0.12], [0.76, 0.12], [0.54, 0.5], [0.76, 0.88], [0.24, 0.88], [0.46, 0.5]], color, dark)
			_poly(o, s, [[0.36, 0.78], [0.64, 0.78], [0.5, 0.6]], hi, Color.TRANSPARENT)
		&"dash":
			for i in 2:
				var x := 0.2 + 0.3 * i
				_poly(o, s, [[x, 0.2], [x + 0.3, 0.5], [x, 0.8], [x + 0.1, 0.5]], color if i == 1 else Color(color, 0.6), dark)
		&"eye":
			_poly(o, s, [[0.08, 0.5], [0.3, 0.3], [0.5, 0.25], [0.7, 0.3], [0.92, 0.5], [0.7, 0.7], [0.5, 0.75], [0.3, 0.7]], color, dark)
			draw_circle(o + Vector2(0.5, 0.5) * s, s * 0.15, dark)
			draw_circle(o + Vector2(0.5, 0.5) * s, s * 0.06, hi)
		&"candle":
			_rect(o, s, Rect2(0.38, 0.42, 0.24, 0.48), color.lerp(UIPalette.BONE, 0.6), dark)
			_poly(o, s, [[0.5, 0.1], [0.6, 0.3], [0.5, 0.38], [0.4, 0.3]], UIPalette.HELLFIRE, Color.TRANSPARENT)


func _p(o: Vector2, s: float, xy: Array) -> Vector2:
	return o + Vector2(float(xy[0]), float(xy[1])) * s


func _poly(o: Vector2, s: float, pts01: Array, fill: Color, outline: Color) -> void:
	var pts := PackedVector2Array()
	for xy: Array in pts01:
		pts.append(_p(o, s, xy))
	_outline_fill(pts, fill, outline)


func _outline_fill(pts: PackedVector2Array, fill: Color, outline: Color) -> void:
	if outline.a > 0.0:
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, outline, maxf(2.0, size.y * 0.06), true)
	if Geometry2D.triangulate_polygon(pts).size() > 0:
		draw_colored_polygon(pts, fill)


func _rect(o: Vector2, s: float, r: Rect2, fill: Color, outline: Color) -> void:
	var rr := Rect2(o + r.position * s, r.size * s)
	if outline.a > 0.0:
		draw_rect(rr.grow(1.5), outline)
	draw_rect(rr, fill)


func _ring(c: Vector2, radius: Vector2, width: float, col: Color, vertical: bool) -> void:
	var pts := PackedVector2Array()
	for i in 25:
		var a := TAU * float(i) / 24.0
		var v := Vector2(cos(a) * radius.x, sin(a) * radius.y)
		pts.append(c + (Vector2(v.y, v.x) if vertical else v))
	draw_polyline(pts, Color(0, 0, 0, 0.75), width + 3.0, true)
	draw_polyline(pts, col, width, true)


func _drop(o: Vector2, s: float, outline: Color) -> void:
	var pts := PackedVector2Array([_p(o, s, [0.5, 0.06])])
	# Clockwise (screen space, y down) around the bulb from its upper-right tangent to the upper-left.
	for i in 17:
		var a := -PI / 6.0 + (PI * 4.0 / 3.0) * float(i) / 16.0
		pts.append(o + (Vector2(0.5, 0.62) + Vector2(cos(a), sin(a)) * 0.28) * s)
	_outline_fill(pts, color, outline)
	draw_circle(o + Vector2(0.42, 0.62) * s, s * 0.06, color.lightened(0.45))


func _draw_text(s: float, o: Vector2) -> void:
	var font := UIPalette.serif_bold()
	var fs := maxi(8, int(s * 0.7))
	var g := glyph
	var sz := font.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var pos := o + Vector2((s - sz.x) * 0.5, (s + font.get_ascent(fs) - font.get_descent(fs)) * 0.5)
	draw_string_outline(font, pos, g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, int(fs / 6.0)), Color(0, 0, 0, 0.85))
	draw_string(font, pos, g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
