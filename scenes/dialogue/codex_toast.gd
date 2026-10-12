class_name CodexToast
extends CanvasLayer
## "New codex entry" notice (story role; agreed with the UI role, docs/team/ui.md). Listens to
## Dialogue.codex_unlocked and slides a small card in from the left edge: a sigil, "NEW CODEX
## ENTRY", the entry's title and where to read it. Unlocks that arrive together are queued; more
## than MAX_SINGLE at once collapse into one "N new codex entries" card. Never pauses, never takes
## input; runs while paused. Created by StoryHooks (child of the Dialogue autoload).

const LAYER := 88
const SHOW_TIME := 3.6
const SLIDE := 0.35
const MAX_SINGLE := 3
const GOLD := Color("e8c77a")
const INK := Color("eadcc4")
const DIM := Color("a8977c")

var _queue: Array[String] = []
var _busy := false
var _root: Control


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	Dialogue.codex_unlocked.connect(_on_unlocked)


func _on_unlocked(id: String) -> void:
	_queue.append(id)
	if not _busy:
		_show_next.call_deferred()  # let a burst of unlocks land first


func _show_next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	var title := ""
	if _queue.size() > MAX_SINGLE:
		title = "%d new entries" % _queue.size()
		_queue.clear()
	else:
		title = _title_of(_queue.pop_front())
	var card := _card(title)
	_root.add_child(card)
	card.position.x = -card.size.x - 20.0
	var tw := card.create_tween()
	tw.tween_property(card, "position:x", 24.0, SLIDE).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(SHOW_TIME)
	tw.tween_property(card, "modulate:a", 0.0, SLIDE)
	tw.tween_callback(card.queue_free)
	tw.tween_callback(_show_next)
	Sfx.play(&"toast", 0.03, -6.0)


func _title_of(id: String) -> String:
	for e in Dialogue.codex_entries():
		if e["id"] == id:
			return str(e["title"])
	return id.capitalize()


func _card(title: String) -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.03, 0.03, 0.9)
	sb.border_color = Color(GOLD, 0.7)
	sb.border_width_left = 3
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	sb.shadow_color = Color(0.3, 0.05, 0.02, 0.5)
	sb.shadow_size = 8
	panel.add_theme_stylebox_override(&"panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position.y = _root.get_viewport_rect().size.y * 0.36
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	panel.add_child(row)
	var sigil := Label.new()
	sigil.text = "✦"
	sigil.add_theme_font_size_override(&"font_size", 30)
	sigil.add_theme_color_override(&"font_color", GOLD)
	row.add_child(sigil)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 0)
	row.add_child(col)
	col.add_child(_label("NEW CODEX ENTRY", 13, DIM))
	col.add_child(_label(title, 21, INK))
	var where := "[C] in Basecamp  ·  Pause › Codex" if not _in_basecamp() else "Press C to read"
	col.add_child(_label(where, 13, DIM))
	panel.reset_size()
	return panel


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	l.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override(&"outline_size", 3)
	return l


func _in_basecamp() -> bool:
	var cs := get_tree().current_scene
	return cs != null and cs.is_in_group(&"basecamp")
