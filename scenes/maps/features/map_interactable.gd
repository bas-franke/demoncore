class_name MapInteractable
extends Node3D
## Base for map interactables the demon "uses" by standing in their circle (holy fonts, bells, the
## Seventh Gate). Progress fills while the player is inside `radius` and drains outside; at 1.0
## `_activate()` runs, then the feature rests for `cooldown` s (< 0 = single use).
## A ground sigil (BossTelegraph) shows the circle and the progress. In group "map_interactables".

signal activated(feature: MapInteractable)

@export var radius := 2.6
@export var channel_time := 2.0
@export var cooldown := -1.0
@export var tint := Color(1.0, 0.85, 0.5)
## Display name for toasts / tracker hooks.
@export var display_name := "Shrine"

var progress := 0.0
var used := false
var _rest := 0.0
var _ring: BossTelegraph


func _ready() -> void:
	add_to_group(&"map_interactables")
	_ring = BossTelegraph.new()
	add_child(_ring)
	_build()
	# HUD minimap (ui/components/minimap.gd) + map overview: a small ring in the feature's tint
	add_to_group(&"minimap_marker")
	set_meta(&"minimap_color", tint)
	set_meta(&"minimap_size", 4.0)
	set_meta(&"minimap_pin", false)


## Override: visuals.
func _build() -> void:
	pass


## Override: what happens when the channel completes.
func _activate() -> void:
	pass


## Override: extra rule (e.g. the Seventh Gate stays sealed until its wards fall).
func can_activate() -> bool:
	return true


## True when the feature can be used now: not spent, not resting, and can_activate() agrees.
func is_ready() -> bool:
	return not used and _rest <= 0.0 and can_activate()


func _physics_process(delta: float) -> void:
	_tick(delta)
	if _rest > 0.0:
		_rest -= delta
		if _rest <= 0.0:
			refresh_marker()
	var p := Game.player
	var inside := false
	if p and not p.is_dead and is_ready():
		var d := p.global_position - global_position
		d.y = 0.0
		inside = d.length() <= radius
	if inside:
		progress = minf(progress + delta / maxf(channel_time, 0.05), 1.0)
	else:
		progress = maxf(progress - delta / maxf(channel_time, 0.05) * 0.6, 0.0)
	if is_ready():
		_ring.show_disc(global_position, radius, tint, progress, 0.45 + 0.4 * progress, 1.2 + progress)
	else:
		_ring.hide_now()
	if progress >= 1.0:
		progress = 0.0
		if cooldown < 0.0:
			used = true
		else:
			_rest = cooldown
		_activate()
		activated.emit(self)
		refresh_marker()


## Override: per-frame animation.
func _tick(_delta: float) -> void:
	pass


## Small centred toast (same look as the loader's landmark toast).
func toast(text: String, color := Color(0.95, 0.85, 0.65)) -> void:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	l.position.y -= 160.0
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override(&"font_size", 22)
	l.add_theme_color_override(&"font_color", color)
	l.add_theme_color_override(&"font_outline_color", Color(0.05, 0.01, 0.01))
	l.add_theme_constant_override(&"outline_size", 6)
	layer.add_child(l)
	var tw := create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(l, ^"modulate:a", 0.0, 0.8)
	tw.tween_callback(layer.queue_free)


## Dims this feature's minimap marker while it is spent / resting (call when the state changes).
func refresh_marker() -> void:
	set_meta(&"minimap_color", Color(tint, 0.35) if not is_ready() else tint)
