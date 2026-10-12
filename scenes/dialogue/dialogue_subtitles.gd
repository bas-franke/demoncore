class_name DialogueSubtitles
extends CanvasLayer
## Non-blocking lines: barks (boss taunts, demon quips, NPC asides) and narration. Owned by the
## Dialogue autoload. Lines are queued and shown one at a time; they never pause the game and
## keep running while the tree is paused (e.g. narration over the game-over screen).
##   Barks:     bottom centre, "Name — text" on a dark strip, in the speaker's colour.
##   Narration: upper third, large italic text with no name, for the voice of the Pit.

const LAYER := 90
const MIN_TIME := 2.4
const MAX_TIME := 7.5
const PER_CHAR := 0.055
const FADE := 0.35
## Clear of the boss bar and the ability button at the bottom of the HUD.
const BARK_BOTTOM := 178.0

var _queue: Array[Dictionary] = []  # {speaker: Dictionary, text: String, narrator: bool}
var _current: Control
var _left := 0.0
var _root: Control
var _italic: FontVariation


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_italic = FontVariation.new()
	_italic.base_font = _root.get_theme_default_font()
	_italic.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(0.2, 1.0), Vector2.ZERO)


func _process(delta: float) -> void:
	if _current:
		_left -= delta
		if _left <= 0.0:
			_dismiss()
	elif not _queue.is_empty():
		_show(_queue.pop_front())


## Queues one line. `speaker` is a DialogueDB speaker dict (empty or id "narrator" = narration).
func push(speaker: Dictionary, text: String) -> void:
	var narrator := speaker.is_empty() or str(speaker.get("id", "")) == "narrator"
	_queue.append({"speaker": speaker, "text": text, "narrator": narrator})


## Drops queued lines and fades out the current one.
func clear() -> void:
	_queue.clear()
	if _current:
		_dismiss()


func is_busy() -> bool:
	return _current != null or not _queue.is_empty()


func _show(item: Dictionary) -> void:
	var text: String = item["text"]
	var narrator: bool = item["narrator"]
	var speaker: Dictionary = item["speaker"]
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_constant_override(&"outline_size", 5)
	label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	var box: Control
	if narrator:
		label.add_theme_font_override(&"normal_font", _italic)
		label.add_theme_font_size_override(&"normal_font_size", 28)
		label.add_theme_color_override(&"default_color", Color("d8c8a8"))
		label.text = "[center]%s[/center]" % text
		box = label
		box.anchor_left = 0.5
		box.anchor_right = 0.5
		box.anchor_top = 0.2
		box.anchor_bottom = 0.2
		box.offset_left = -480.0
		box.offset_right = 480.0
		box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	else:
		var col: Color = speaker.get("color", Color("e8d6a6"))
		label.add_theme_font_size_override(&"normal_font_size", 21)
		label.add_theme_color_override(&"default_color", Color("eadcc4"))
		label.text = "[center][color=#%s]%s[/color]   %s[/center]" % [col.to_html(false),
				str(speaker.get("name", "")), text]
		var panel := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.015, 0.015, 0.72)
		sb.set_corner_radius_all(4)
		sb.border_color = Color(col, 0.5)
		sb.border_width_left = 3
		sb.content_margin_left = 18.0
		sb.content_margin_right = 18.0
		sb.content_margin_top = 8.0
		sb.content_margin_bottom = 8.0
		panel.add_theme_stylebox_override(&"panel", sb)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.custom_minimum_size = Vector2(minf(820.0, 120.0 + text.length() * 10.0), 0.0)
		panel.add_child(label)
		box = panel
		box.anchor_left = 0.5
		box.anchor_right = 0.5
		box.anchor_top = 1.0
		box.anchor_bottom = 1.0
		box.offset_bottom = -BARK_BOTTOM
		box.offset_top = -BARK_BOTTOM
		box.grow_horizontal = Control.GROW_DIRECTION_BOTH
		box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(box)
	_current = box
	_left = clampf(MIN_TIME + text.length() * PER_CHAR, MIN_TIME, MAX_TIME) * (1.3 if narrator else 1.0)
	box.modulate.a = 0.0
	box.create_tween().tween_property(box, "modulate:a", 1.0, FADE * (2.0 if narrator else 1.0))


func _dismiss() -> void:
	var box := _current
	_current = null
	var tw := box.create_tween()
	tw.tween_property(box, "modulate:a", 0.0, FADE)
	tw.tween_callback(box.queue_free)
