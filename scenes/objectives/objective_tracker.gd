class_name ObjectiveTracker
extends CanvasLayer
## Objective tracker + world markers, created by ObjectiveDirector.
##   - Top-right list (under "Angels slain"): one row per open objective with its glyph, title,
##     a status line (distance while dormant, "3 / 4", "0:21" while active) and a thin progress bar.
##   - Markers: every open objective (and a living boss) gets a diamond over it on screen, or an
##     arrow pinned to the screen edge pointing at it when it is off screen.
## Everything is drawn in code with UIPalette colours. Other UI can move the list with
## `list_top` / `list_right` or hide parts with `show_list` / `show_markers`.

const ROW_WIDTH := 290.0
const BAR_H := 3.0
## Screen-edge margins for pinned markers (left, top, right, bottom): clear of the HUD's life bar,
## timer and the minimap / ability dock at the bottom.
const EDGE_INSET := Vector4(40.0, 86.0, 40.0, 128.0)
const ARROW := 11.0
const DIAMOND := 9.0
## Markers fade in beyond this distance (closer, the beacon and ground zone speak for themselves).
const NEAR_FADE := Vector2(5.0, 9.0)

## The owning director (set before add_child).
var director: Node
## Offset of the list from the top-right corner.
var list_top := 104.0
var list_right := 26.0
var show_list := true
var show_markers := true

var _root: Control
var _list: VBoxContainer
var _markers: Control
var _rows := {}  # Objective instance id (int) -> Dictionary of row controls
var _font: Font


func _ready() -> void:
	layer = 4  # under the HUD's menus, over the world
	_font = UIPalette.serif()
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_markers = Control.new()
	_markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_markers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_markers.draw.connect(_draw_markers)
	_root.add_child(_markers)
	_list = VBoxContainer.new()
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_theme_constant_override(&"separation", 8)
	_root.add_child(_list)


func _process(_delta: float) -> void:
	var objs: Array[Objective] = []
	if director and is_instance_valid(director):
		objs.assign(director.get(&"objectives"))
	_update_rows(objs)
	_list.visible = show_list and _list.get_child_count() > 0
	_list.size = _list.get_combined_minimum_size()
	_list.position = Vector2(_root.size.x - list_right - ROW_WIDTH, list_top)
	_markers.queue_redraw()


# ---------------------------------------------------------------- list

func _update_rows(objs: Array[Objective]) -> void:
	var seen := {}
	for o in objs:
		if not is_instance_valid(o):
			continue
		var key := o.get_instance_id()
		seen[key] = true
		if not _rows.has(key):
			_rows[key] = _make_row(o)
		_refresh_row(_rows[key], o)
	for key: int in _rows.keys():
		if not seen.has(key):
			var row: Dictionary = _rows[key]
			(row.root as Control).queue_free()
			_rows.erase(key)


func _make_row(o: Objective) -> Dictionary:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size.x = ROW_WIDTH
	box.add_theme_constant_override(&"separation", 1)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override(&"separation", 8)
	box.add_child(top)
	# Painted in code (UI role's GlyphIcon), so emoji glyphs never depend on the OS font.
	var glyph := GlyphIcon.new()
	glyph.glyph = o.glyph
	glyph.color = o.color
	glyph.custom_minimum_size = Vector2(20.0, 20.0)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(glyph)
	var title := _label(o.title, 17, UIPalette.BONE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	top.add_child(title)
	var status := _label("", 15, UIPalette.ASH_TEXT)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(status)
	var bar_bg := ColorRect.new()
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.color = Color(0.0, 0.0, 0.0, 0.55)
	bar_bg.custom_minimum_size = Vector2(ROW_WIDTH - 26.0, BAR_H)
	bar_bg.size_flags_horizontal = Control.SIZE_SHRINK_END
	box.add_child(bar_bg)
	var bar := ColorRect.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.color = o.color
	bar.size = Vector2(0.0, BAR_H)
	bar_bg.add_child(bar)
	_list.add_child(box)
	box.modulate.a = 0.0
	box.create_tween().tween_property(box, "modulate:a", 1.0, 0.5)
	return {root = box, title = title, status = status, bar = bar, bar_bg = bar_bg, glyph = glyph}


func _refresh_row(row: Dictionary, o: Objective) -> void:
	var status := row.status as Label
	var title := row.title as Label
	var bar := row.bar as ColorRect
	var box := row.root as Control
	var dist := _distance_to(o.marker_position())
	match o.state:
		Objective.State.DORMANT:
			title.add_theme_color_override(&"font_color", UIPalette.ASH_TEXT.lerp(UIPalette.BONE, 0.35))
			var left := o.time_to_expire()
			# Warn when an untouched objective is about to fade.
			if left >= 0.0 and left < 30.0:
				status.text = "%dm  fades %s" % [roundi(dist), Objective.fmt_time(left)]
			else:
				status.text = "%dm" % roundi(dist)
		Objective.State.ACTIVE:
			title.add_theme_color_override(&"font_color", UIPalette.BONE_BRIGHT)
			status.text = o.status_text
			status.add_theme_color_override(&"font_color", UIPalette.BRIMSTONE)
		Objective.State.COMPLETED:
			status.text = "done"
			status.add_theme_color_override(&"font_color", UIPalette.HELLFIRE)
			box.modulate.a = move_toward(box.modulate.a, 0.0, get_process_delta_time() * 0.4)
		_:
			status.text = "failed" if o.state == Objective.State.FAILED else "gone"
			status.add_theme_color_override(&"font_color", UIPalette.SMOKE)
			box.modulate.a = move_toward(box.modulate.a, 0.0, get_process_delta_time() * 0.5)
	var w := (row.bar_bg as Control).custom_minimum_size.x
	bar.size = Vector2(w * clampf(o.progress, 0.0, 1.0), BAR_H)


func _label(text: String, font_size: int, tint: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = text
	l.add_theme_font_override(&"font", _font)
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_color", tint)
	l.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	l.add_theme_constant_override(&"outline_size", 4)
	return l


# ---------------------------------------------------------------- markers

func _draw_markers() -> void:
	if not show_markers:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if director and is_instance_valid(director):
		for o: Objective in director.get(&"objectives"):
			if is_instance_valid(o) and not o.is_finished():
				var a := 1.0 if o.is_active() else 0.75
				_marker(cam, o.marker_position() + Vector3(0.0, 2.6, 0.0), o.color, o.glyph, a)
	var boss := get_tree().get_first_node_in_group(&"boss") as Node3D
	if boss and not (boss is Enemy and (boss as Enemy).is_dying):
		_marker(cam, boss.global_position + Vector3(0.0, 4.0, 0.0), UIPalette.HOLY, "☠", 1.0, true)


func _marker(cam: Camera3D, world: Vector3, tint: Color, glyph: String, alpha: float,
		offscreen_only: bool = false) -> void:
	var rect := _markers.get_rect()
	var dist := _distance_to(world)
	var behind := cam.is_position_behind(world)
	var sp := cam.unproject_position(world)
	var inner := rect.grow_individual(-EDGE_INSET.x, -EDGE_INSET.y, -EDGE_INSET.z, -EDGE_INSET.w)
	var on_screen := not behind and inner.has_point(sp)
	if on_screen:
		if offscreen_only:
			return
		var k := smoothstep(NEAR_FADE.x, NEAR_FADE.y, dist) * alpha
		if k <= 0.01:
			return
		var bob := sin(Time.get_ticks_msec() * 0.004) * 3.0
		_diamond(sp + Vector2(0.0, bob), DIAMOND, tint, k)
		_glyph(sp + Vector2(0.0, bob), glyph, tint, k)
		return
	# Off screen: pin to the inset rectangle along the ray from the screen centre.
	var c := inner.get_center()
	var dir := (sp - c)
	if behind:
		dir = -dir
	if dir.length_squared() < 1.0:
		dir = Vector2.UP
	dir = dir.normalized()
	var half := inner.size * 0.5
	var t := minf(half.x / maxf(absf(dir.x), 0.0001), half.y / maxf(absf(dir.y), 0.0001))
	var at := c + dir * t
	# Keep pinned markers off the objective list (top-right): slide them left of it.
	if _list.visible:
		var list_rect := Rect2(_list.position, _list.size).grow(14.0)
		if list_rect.has_point(at):
			at.x = list_rect.position.x
	var pulse := 0.8 + 0.2 * sin(Time.get_ticks_msec() * 0.005)
	var tip := at + dir * (ARROW + 6.0)
	var side := Vector2(-dir.y, dir.x) * ARROW * 0.6
	var col := Color(tint, alpha * pulse)
	_markers.draw_colored_polygon(PackedVector2Array([tip, at + dir * 4.0 + side, at + dir * 4.0 - side]), col)
	_diamond(at, DIAMOND + 2.0, tint, alpha)
	_glyph(at, glyph, tint, alpha)
	var txt := "%dm" % roundi(dist)
	var tw := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var label_at := at - dir * 26.0 + Vector2(-tw * 0.5, 5.0)
	_markers.draw_string_outline(_font, label_at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.8 * alpha))
	_markers.draw_string(_font, label_at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(UIPalette.BONE, alpha))


func _diamond(at: Vector2, r: float, tint: Color, alpha: float) -> void:
	var pts := PackedVector2Array([at + Vector2(0, -r * 1.25), at + Vector2(r, 0), at + Vector2(0, r * 1.25), at + Vector2(-r, 0)])
	_markers.draw_colored_polygon(pts, Color(0.05, 0.02, 0.02, 0.8 * alpha))
	pts.append(pts[0])
	_markers.draw_polyline(pts, Color(tint, alpha), 1.5, true)


func _glyph(at: Vector2, glyph: String, tint: Color, alpha: float) -> void:
	glyph = GlyphIcon.plain(glyph)  # text-safe stand-in for emoji glyphs (UI role)
	var fs := 13
	var sz := _font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var p := at + Vector2(-sz.x * 0.5, fs * 0.36)
	_markers.draw_string(_font, p, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(tint, alpha))


func _distance_to(world: Vector3) -> float:
	var p := Game.player
	if p == null or not is_instance_valid(p):
		return 0.0
	var d := world - p.global_position
	d.y = 0.0
	return d.length()
