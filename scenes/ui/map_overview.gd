class_name MapOverview
extends CanvasLayer
## Full-screen map of the current run (UI role), toggled with the `map_overview` action (Tab / M /
## pad Back). Pauses the game while open. Draws, oriented like the game camera:
##   - the map bounds (GameMap circle / rectangle / polygon; endless maps show a 70 m area)
##   - landmarks (Maps.landmarks(): Marker3D metas display_name, radius)
##   - objectives (group "objectives": glyph, colour, title; marker_position()), the boss, allies
##   - the demon as an ember arrow
## plus a side list of open objectives with their status and distance. HUD adds one per run.

const ENDLESS_RADIUS := 70.0
const MARGIN := 70.0

var _root: Control
var _canvas: Control
var _list: VBoxContainer
var _title: Label
var _right := Vector3.RIGHT
var _fwd := Vector3.FORWARD
var _scale := 1.0
var _origin := Vector2.ZERO
var _was_paused := false
var _outline := PackedVector2Array()  # bounds outline, rotated, unscaled


func _ready() -> void:
	layer = 18
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


## _input (not _unhandled) so Esc closes the map before the pause menu sees it.
func _input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause")):
		close()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not InputMap.has_action(&"map_overview") or not event.is_action_pressed(&"map_overview"):
		return
	if visible:
		close()
	elif not get_tree().paused:
		open()
	get_viewport().set_input_as_handled()


func open() -> void:
	if Game.player == null or not is_instance_valid(Game.player):
		return
	_was_paused = get_tree().paused
	get_tree().paused = true
	visible = true
	Sfx.play(&"ui_click")
	_fill_list()
	_canvas.queue_redraw()
	_root.modulate.a = 0.0
	_root.create_tween().tween_property(_root, "modulate:a", 1.0, 0.2)


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = _was_paused
	Sfx.play(&"ui_back")


# ---------------------------------------------------------------- projection

func _setup_projection() -> Rect2:
	var cam := get_viewport().get_camera_3d()
	_right = Vector3.RIGHT
	_fwd = Vector3.FORWARD
	if cam:
		var r := cam.global_basis.x
		var f := -cam.global_basis.z
		r.y = 0.0
		f.y = 0.0
		if r.length_squared() > 0.0001 and f.length_squared() > 0.0001:
			_right = r.normalized()
			_fwd = f.normalized()
	# World area to show.
	var pts: Array[Vector2] = []  # (x, z) outline points
	var gm: Node = _game_map()
	if gm:
		match int(gm.get(&"bounds_kind")):
			1:  # CIRCLE
				var c: Vector2 = gm.get(&"bounds_center")
				var rad := float(gm.get(&"bounds_radius"))
				for i in 48:
					var a := TAU * float(i) / 48.0
					pts.append(c + Vector2(cos(a), sin(a)) * rad)
			2:  # RECT
				var c: Vector2 = gm.get(&"bounds_center")
				var h: Vector2 = Vector2(gm.get(&"bounds_size")) * 0.5
				pts = [c + Vector2(-h.x, -h.y), c + Vector2(h.x, -h.y), c + Vector2(h.x, h.y), c + Vector2(-h.x, h.y)]
			3:  # POLYGON
				for p: Vector2 in gm.get(&"bounds_polygon"):
					pts.append(p)
	var p3 := Game.player.global_position
	if pts.is_empty():
		for i in 48:
			var a := TAU * float(i) / 48.0
			pts.append(Vector2(p3.x, p3.z) + Vector2(cos(a), sin(a)) * ENDLESS_RADIUS)
	_outline = PackedVector2Array()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		var v := _rot(Vector3(p.x, 0.0, p.y))
		_outline.append(v)
		lo = lo.min(v)
		hi = hi.max(v)
	var area := _canvas.size - Vector2(MARGIN, MARGIN) * 2.0
	_scale = minf(area.x / maxf(hi.x - lo.x, 1.0), area.y / maxf(hi.y - lo.y, 1.0))
	_origin = _canvas.size * 0.5 - (lo + hi) * 0.5 * _scale
	return Rect2(lo, hi - lo)


## World position -> unscaled 2D (x right, y down on screen).
func _rot(w: Vector3) -> Vector2:
	return Vector2(w.dot(_right), -w.dot(_fwd))


func _to_screen(w: Vector3) -> Vector2:
	return _origin + _rot(w) * _scale


# ---------------------------------------------------------------- drawing

func _draw_map() -> void:
	if not visible or Game.player == null or not is_instance_valid(Game.player):
		return
	_setup_projection()
	var c := _canvas
	# Ground.
	var poly := PackedVector2Array()
	for v in _outline:
		poly.append(_origin + v * _scale)
	if Geometry2D.triangulate_polygon(poly).size() > 0:
		c.draw_colored_polygon(poly, Color(0.12, 0.05, 0.035, 0.85))
	var closed := poly.duplicate()
	if not closed.is_empty():
		closed.append(closed[0])
		c.draw_polyline(closed, UIPalette.EMBER_DIM, 3.0, true)
	var font := UIPalette.serif()
	# Landmarks.
	var maps := get_node_or_null(^"/root/Maps")
	if maps and maps.has_method(&"landmarks"):
		for mk: Node3D in maps.call(&"landmarks"):
			if not is_instance_valid(mk):
				continue
			var sp := _to_screen(mk.global_position)
			var rad := float(mk.get_meta(&"radius", 4.0)) * _scale
			c.draw_arc(sp, maxf(rad, 6.0), 0.0, TAU, 32, Color(UIPalette.BRIMSTONE_DIM, 0.45), 1.5, true)
			_diamond(c, sp, 5.0, UIPalette.BRIMSTONE)
			var label := str(mk.get_meta(&"display_name", mk.get_meta(&"id", "")))
			if label != "":
				_text(c, font, sp + Vector2(9.0, 5.0), label, 15, UIPalette.BONE)
	# [maps] Map interactables (holy fonts, bells, the Seventh Gate; group map_interactables, see
	# docs/team/maps.md): a ring in their tint, dimmed once spent; breakable statues as marble squares.
	for it: Node in get_tree().get_nodes_in_group(&"map_interactables"):
		var i3 := it as Node3D
		if i3 == null:
			continue
		var ip := _to_screen(i3.global_position)
		var spent := not bool(i3.call(&"is_ready")) if i3.has_method(&"is_ready") else false
		var icol: Color = i3.get_meta(&"minimap_color", UIPalette.BONE)
		c.draw_arc(ip, 7.0, 0.0, TAU, 20, Color(icol, 0.35 if spent else 0.95), 2.0, true)
		_text(c, font, ip + Vector2(10.0, 4.0), str(i3.get(&"display_name")), 13, Color(icol, 0.5 if spent else 0.9))
	for s: Node in get_tree().get_nodes_in_group(&"map_features"):
		if s is Node3D:
			var spp := _to_screen((s as Node3D).global_position)
			c.draw_rect(Rect2(spp - Vector2(3.5, 3.5), Vector2(7.0, 7.0)), Color(0.9, 0.88, 0.8, 0.8))
	# The Host: faint holy specks (capped, so huge hordes stay cheap).
	var n := 0
	for e: Node in get_tree().get_nodes_in_group(&"enemies"):
		if n >= 400:
			break
		if e is Node3D and not e.is_in_group(&"boss") and not e.is_in_group(&"map_features"):  # [maps]
			c.draw_circle(_to_screen((e as Node3D).global_position), 1.8, Color(UIPalette.HOLY, 0.45))
			n += 1
	# Allies, boss.
	for a: Node in get_tree().get_nodes_in_group(&"allies"):
		if a is Node3D:
			c.draw_circle(_to_screen((a as Node3D).global_position), 3.0, UIPalette.SOUL)
	for b: Node in get_tree().get_nodes_in_group(&"boss"):
		if b is Node3D:
			var bp := _to_screen((b as Node3D).global_position)
			c.draw_circle(bp, 12.0, Color(UIPalette.HOLY_GOLD, 0.25))
			_diamond(c, bp, 8.0, UIPalette.HOLY_GOLD)
			_text(c, font, bp + Vector2(12.0, 5.0), "BOSS", 14, UIPalette.HOLY_GOLD)
	# Objectives.
	for o: Node in get_tree().get_nodes_in_group(&"objectives"):
		var o3 := o as Node3D
		if o3 == null:
			continue
		var at: Vector3 = o3.call(&"marker_position") if o3.has_method(&"marker_position") else o3.global_position
		var sp := _to_screen(at)
		var col: Color = o3.get(&"color") if o3.get(&"color") is Color else UIPalette.EMBER
		c.draw_circle(sp, 15.0, Color(0, 0, 0, 0.6))
		c.draw_arc(sp, 15.0, 0.0, TAU, 32, col, 2.0, true)
		_glyph_at(c, sp, str(o3.get(&"glyph") if o3.get(&"glyph") != null else "◆"), col)
		_text(c, font, sp + Vector2(19.0, 5.0), str(o3.get(&"title") if o3.get(&"title") != null else ""), 15, col.lerp(UIPalette.BONE_BRIGHT, 0.4))
	# The demon.
	var pp := _to_screen(Game.player.global_position)
	var face: Vector3 = Game.player.facing
	var d := _rot(face).normalized()
	if d == Vector2.ZERO:
		d = Vector2.UP
	var side := Vector2(-d.y, d.x)
	c.draw_circle(pp, 14.0, Color(UIPalette.HELLFIRE, 0.18))
	var tri := PackedVector2Array([pp + d * 12.0, pp - d * 7.0 + side * 8.0, pp - d * 3.0, pp - d * 7.0 - side * 8.0])
	c.draw_colored_polygon(tri, UIPalette.HELLFIRE)
	tri.append(tri[0])
	c.draw_polyline(tri, Color(0, 0, 0, 0.8), 1.5, true)


## Painted glyph at a point, via a temporary GlyphIcon-like draw (plain text fallback).
func _glyph_at(c: Control, at: Vector2, g: String, col: Color) -> void:
	var font := UIPalette.serif_bold()
	var t := GlyphIcon.plain(g)
	var sz := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	_text(c, font, at + Vector2(-sz.x * 0.5, 6.0), t, 16, col)


func _diamond(c: Control, p: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)])
	c.draw_colored_polygon(pts, col)
	pts.append(pts[0])
	c.draw_polyline(pts, Color(0, 0, 0, 0.85), 1.5, true)


func _text(c: Control, font: Font, at: Vector2, t: String, fs: int, col: Color) -> void:
	c.draw_string_outline(font, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.9))
	c.draw_string(font, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _game_map() -> Node:
	var maps := get_node_or_null(^"/root/Maps")
	if maps == null:
		return null
	var m: Variant = maps.get(&"current_map")
	return m if m is Node and is_instance_valid(m) else null


# ---------------------------------------------------------------- side list

func _fill_list() -> void:
	for ch in _list.get_children():
		ch.queue_free()
	var maps := get_node_or_null(^"/root/Maps")
	var title := "The Heavens"
	if maps:
		var def: Variant = maps.call(&"get_def", maps.get(&"selected_id"))
		if def is Dictionary and str(def.get("name", "")) != "":
			title = str(def.name)
	_title.text = title.to_upper()
	var any := false
	var p := Game.player.global_position
	for o: Node in get_tree().get_nodes_in_group(&"objectives"):
		var o3 := o as Node3D
		if o3 == null:
			continue
		any = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		var col: Color = o3.get(&"color") if o3.get(&"color") is Color else UIPalette.EMBER
		var gi := GlyphIcon.new()
		gi.glyph = str(o3.get(&"glyph") if o3.get(&"glyph") != null else "◆")
		gi.color = col
		gi.custom_minimum_size = Vector2(22, 22)
		row.add_child(gi)
		var texts := VBoxContainer.new()
		texts.add_theme_constant_override(&"separation", 0)
		row.add_child(texts)
		var t := Label.new()
		t.theme_type_variation = &"InkLabel"
		t.add_theme_font_size_override(&"font_size", 16)
		t.text = str(o3.get(&"title") if o3.get(&"title") != null else "Objective")
		texts.add_child(t)
		var at: Vector3 = o3.call(&"marker_position") if o3.has_method(&"marker_position") else o3.global_position
		var status := str(o3.get(&"status_text") if o3.get(&"status_text") != null else "")
		var s := Label.new()
		s.theme_type_variation = &"CaptionLabel"
		s.text = ("%dm" % roundi(Vector2(at.x - p.x, at.z - p.z).length())) + ("  ·  " + status if status != "" else "")
		texts.add_child(s)
		_list.add_child(row)
	if not any:
		var l := Label.new()
		l.theme_type_variation = &"LoreLabel"
		l.text = "No works of damnation await."
		_list.add_child(l)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = load("res://ui/theme.tres") as Theme
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.005, 0.004, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.offset_right = -300.0
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_map)
	_canvas.resized.connect(_canvas.queue_redraw)
	_root.add_child(_canvas)
	var side := PanelContainer.new()
	side.theme_type_variation = &"InfernalPanel"
	side.anchor_left = 1.0
	side.anchor_right = 1.0
	side.anchor_bottom = 1.0
	side.offset_left = -290.0
	side.offset_right = -16.0
	side.offset_top = 16.0
	side.offset_bottom = -16.0
	_root.add_child(side)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 10)
	side.add_child(col)
	_title = Label.new()
	_title.theme_type_variation = &"HeaderLabel"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size.x = 200.0
	col.add_child(_title)
	var cap := Label.new()
	cap.theme_type_variation = &"CaptionLabel"
	cap.text = "WORKS OF DAMNATION"
	col.add_child(cap)
	col.add_child(HSeparator.new())
	_list = VBoxContainer.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 10)
	col.add_child(_list)
	var legend := Label.new()
	legend.theme_type_variation = &"CaptionLabel"
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend.custom_minimum_size.x = 200.0
	legend.text = "▲ YOU   ◆ LANDMARK   ◯ OBJECTIVE   ◆ BOSS (GOLD)   ● ALLY   · ANGEL\nTAB / M / ESC  CLOSE"
	col.add_child(legend)
