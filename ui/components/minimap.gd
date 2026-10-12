class_name Minimap
extends Control
## Round "scrying" radar centred on the player, oriented to the active camera. Draws:
##   - group "enemies"          -> small holy-white dots (elites/bosses bigger, see below)
##   - group "boss"             -> large pulsing gold marker, pinned to the rim when out of range
##   - group "pickups"          -> soul-green specks
##   - group "minimap_marker"   -> anything else. Optional node metas:
##         minimap_color: Color, minimap_size: float (px), minimap_pin: bool (clamp to rim),
##         minimap_label: String (drawn next to the marker)
##     (objectives register themselves this way, see scenes/objectives/objective.gd)
## Refreshes at REFRESH_HZ to stay cheap with hundreds of enemies.
##
##   var mm := Minimap.new(); mm.custom_minimum_size = Vector2(150, 150); mm.world_radius = 32.0

const REFRESH_HZ := 15.0
const MAX_DOTS := 400

## World metres from the centre to the rim.
@export var world_radius := 32.0

var _acc := 0.0
var _dots: PackedVector2Array = []
var _dot_colors: PackedColorArray = []
var _dot_sizes: PackedFloat32Array = []
var _pins: Array = []  # [Vector2 pos, Color, float size, String label]


func _init() -> void:
	custom_minimum_size = Vector2(150.0, 150.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_acc += delta
	if _acc < 1.0 / REFRESH_HZ:
		return
	_acc = 0.0
	_collect()
	queue_redraw()


func _collect() -> void:
	_dots.clear()
	_dot_colors.clear()
	_dot_sizes.clear()
	_pins.clear()
	var p := Game.player
	if p == null or not is_instance_valid(p):
		return
	var origin := p.global_position
	var cam := get_viewport().get_camera_3d()
	var right := Vector3.RIGHT
	var fwd := Vector3.FORWARD
	if cam:
		right = cam.global_basis.x
		right.y = 0.0
		fwd = -cam.global_basis.z
		fwd.y = 0.0
		if right.length_squared() < 0.0001 or fwd.length_squared() < 0.0001:
			right = Vector3.RIGHT
			fwd = Vector3.FORWARD
		right = right.normalized()
		fwd = fwd.normalized()
	var radius_px := minf(size.x, size.y) * 0.5 - 4.0
	var scale_px := radius_px / maxf(world_radius, 1.0)
	var tree := get_tree()

	var n := 0
	for e: Node in Perf.enemies():
		if n >= MAX_DOTS:
			break
		var e3 := e as Node3D
		if e3 == null or e3.is_in_group(&"boss"):
			continue
		var d := e3.global_position - origin
		var v := Vector2(d.dot(right), -d.dot(fwd)) * scale_px
		if v.length() > radius_px:
			continue
		var elite: bool = e3.has_method(&"is_elite") and e3.call(&"is_elite")
		_dots.append(v)
		_dot_colors.append(UIPalette.HOLY_GOLD if elite else Color(UIPalette.HOLY, 0.85))
		_dot_sizes.append(3.2 if elite else 1.8)
		n += 1

	for pk: Node in tree.get_nodes_in_group(&"pickups"):
		var p3 := pk as Node3D
		if p3 == null:
			continue
		var d := p3.global_position - origin
		var v := Vector2(d.dot(right), -d.dot(fwd)) * scale_px
		if v.length() <= radius_px:
			_dots.append(v)
			_dot_colors.append(UIPalette.SOUL)
			_dot_sizes.append(2.2)

	for b: Node in tree.get_nodes_in_group(&"boss"):
		var b3 := b as Node3D
		if b3:
			_add_pin(b3.global_position - origin, right, fwd, scale_px, radius_px, UIPalette.HOLY_GOLD, 6.0, true, "")

	for m: Node in tree.get_nodes_in_group(&"minimap_marker"):
		var m3 := m as Node3D
		if m3 == null:
			continue
		_add_pin(m3.global_position - origin, right, fwd, scale_px, radius_px,
			m3.get_meta(&"minimap_color", UIPalette.EMBER), float(m3.get_meta(&"minimap_size", 4.5)),
			bool(m3.get_meta(&"minimap_pin", true)), str(m3.get_meta(&"minimap_label", "")))


func _add_pin(d: Vector3, right: Vector3, fwd: Vector3, scale_px: float, radius_px: float, col: Color,
		sz: float, pin: bool, label: String) -> void:
	var v := Vector2(d.dot(right), -d.dot(fwd)) * scale_px
	if v.length() > radius_px:
		if not pin:
			return
		v = v.normalized() * (radius_px - sz)
	_pins.append([v, col, sz, label])


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	# Disc, inner rings, cross hairs.
	draw_circle(c, r + 2.0, Color(0, 0, 0, 0.45))
	draw_circle(c, r, Color(0.07, 0.025, 0.02, 0.78))
	draw_arc(c, r * 0.5, 0.0, TAU, 48, Color(UIPalette.EMBER_DIM, 0.35), 1.0, true)
	draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(UIPalette.EMBER_DIM, 0.22), 1.0)
	draw_line(c - Vector2(0, r), c + Vector2(0, r), Color(UIPalette.EMBER_DIM, 0.22), 1.0)

	# Perf: hundreds of dots; a tiny square reads the same as a circle at 2-3 px and is far cheaper
	# to draw (draw_circle tessellates a polygon per call).
	for i in _dots.size():
		var sz := _dot_sizes[i]
		draw_rect(Rect2(c + _dots[i] - Vector2(sz, sz) * 0.8, Vector2(sz, sz) * 1.6), _dot_colors[i])

	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
	for pin: Array in _pins:
		var pos: Vector2 = c + pin[0]
		var col: Color = pin[1]
		var sz: float = pin[2]
		draw_circle(pos, sz + 3.0 * pulse, Color(col, 0.25 * (1.0 - pulse)))
		_draw_diamond(pos, sz, col)
		var label: String = pin[3]
		if label != "":
			var font := UIPalette.serif()
			draw_string_outline(font, pos + Vector2(sz + 3.0, 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color(0, 0, 0, 0.9))
			draw_string(font, pos + Vector2(sz + 3.0, 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)

	# The demon: an ember arrow-head at the centre.
	var pts := PackedVector2Array([c + Vector2(0, -6), c + Vector2(4.5, 4.5), c + Vector2(0, 2.5), c + Vector2(-4.5, 4.5)])
	draw_colored_polygon(pts, UIPalette.HELLFIRE)

	# Rim.
	draw_arc(c, r, 0.0, TAU, 64, UIPalette.EMBER_DIM, 2.0, true)
	draw_arc(c, r - 3.0, 0.0, TAU, 64, Color(UIPalette.BRIMSTONE_DIM, 0.35), 1.0, true)


func _draw_diamond(p: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)])
	draw_colored_polygon(pts, col)
	pts.append(pts[0])
	draw_polyline(pts, Color(0, 0, 0, 0.8), 1.0)
