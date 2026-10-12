class_name ListPanel
extends CanvasLayer
## Modal list window in the shared style (the ShopPanel's sibling for choices rather than
## purchases): keeper name + greeting, wallet, an optional summary gauge (e.g. total heat), a
## scrolling list of ChoiceRows, and a footer hint. Esc / pause / ui_cancel closes.
##
##   var lp := ListPanel.new()
##   add_child(lp)
##   lp.open({
##       "title": "Ossek the Cartographer", "subtitle": "Every road ends in a cathedral.",
##       "wallet": {"glyph": "◈", "color": UIPalette.SOUL, "name": "Souls", "amount": func() -> int: return Meta.souls},
##       "gauge": {"label": "HEAT", "value": 3, "max": 10, "color": UIPalette.BLOOD_BRIGHT,
##                 "text": "+30% souls"},                 # optional, or a Callable returning the dict
##       "rows": func() -> Array: return build_rows(),    # Array of ChoiceRow (rebuilt by refresh())
##       "footer": "Esc  leave",
##       "pause": false,
##   })
##   lp.refresh()   # after a choice changed something: rebuilds rows, wallet and gauge, keeps focus

signal closed

const PANEL_MAX := Vector2(900.0, 640.0)

var _cfg: Dictionary = {}
var _root: Control
var _dim: ColorRect
var _frame: PanelContainer
var _title: Label
var _subtitle: Label
var _wallet: CurrencyCounter
var _gauge_box: VBoxContainer
var _gauge: InfernalBar
var _gauge_label: Label
var _list: VBoxContainer
var _scroll: ScrollContainer
var _footer: Label
var _pause_tree := false


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		close()
		get_viewport().set_input_as_handled()
	elif get_viewport().gui_get_focus_owner() == null and not event.is_echo() and (
			event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"ui_down")):
		_focus(0)  # nothing focused (mouse clicked away): directions bring the cursor back
		get_viewport().set_input_as_handled()


func open(config: Dictionary) -> void:
	_cfg = config
	_title.text = str(config.get("title", ""))
	_subtitle.text = str(config.get("subtitle", ""))
	_subtitle.visible = _subtitle.text != ""
	_footer.text = str(config.get("footer", "ESC  LEAVE")).to_upper()
	var w: Dictionary = config.get("wallet", {})
	_wallet.visible = not w.is_empty()
	if not w.is_empty():
		_wallet.setup(str(w.get("glyph", "◈")), w.get("color", UIPalette.SOUL), str(w.get("name", "")))
	_pause_tree = bool(config.get("pause", false))
	visible = true
	if _pause_tree:
		get_tree().paused = true
	refresh(true)
	Sfx.play(&"ui_click")
	_frame.modulate.a = 0.0
	_frame.create_tween().tween_property(_frame, "modulate:a", 1.0, 0.25)


func close() -> void:
	if not visible:
		return
	visible = false
	if _pause_tree:
		get_tree().paused = false
	Sfx.play(&"ui_back")
	closed.emit()


func is_open() -> bool:
	return visible


## Rebuilds rows, wallet and gauge from the config callables; keeps focus on the same row index.
func refresh(snap := false) -> void:
	var focus_i := -1
	var owner_focus := get_viewport().gui_get_focus_owner()
	for i in _list.get_child_count():
		if owner_focus and _list.get_child(i).is_ancestor_of(owner_focus):
			focus_i = i
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var rows_v: Variant = _cfg.get("rows", [])
	var rows: Array = (rows_v as Callable).call() if rows_v is Callable else rows_v
	for r: Variant in rows:
		if r is Control:
			_list.add_child(r)
	var w: Dictionary = _cfg.get("wallet", {})
	if not w.is_empty():
		var amt: Variant = w.get("amount", 0)
		_wallet.set_amount(int((amt as Callable).call()) if amt is Callable else int(amt), snap)
	var g_v: Variant = _cfg.get("gauge", {})
	var g: Dictionary = (g_v as Callable).call() if g_v is Callable else g_v
	_gauge_box.visible = not g.is_empty()
	if not g.is_empty():
		_gauge.fill_color = g.get("color", UIPalette.BLOOD_BRIGHT)
		_gauge.segment_value = 1.0
		_gauge.set_values(float(g.get("value", 0)), maxf(float(g.get("max", 1)), 1.0))
		_gauge_label.text = "%s  %d / %d   %s" % [str(g.get("label", "")), int(g.get("value", 0)),
			int(g.get("max", 1)), str(g.get("text", ""))]
	_layout()
	_focus.call_deferred(maxi(focus_i, 0))


func _focus(i: int) -> void:
	if not visible or _list.get_child_count() == 0:
		return
	for j in range(i, _list.get_child_count()) + range(0, i):
		var row := _list.get_child(j) as ChoiceRow
		var b := row.first_button() if row else null
		if b:
			b.grab_focus()
			return


func _layout() -> void:
	var vp := _root.size
	var w := minf(PANEL_MAX.x, vp.x * 0.92)
	var h := minf(PANEL_MAX.y, vp.y * 0.88)
	_frame.size = Vector2.ZERO
	_frame.size = Vector2(w, h)
	_frame.position = (vp - _frame.size) * 0.5


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = load("res://ui/theme.tres") as Theme
	add_child(_root)
	_root.resized.connect(_layout)
	_dim = ColorRect.new()
	_dim.color = Color(0.03, 0.006, 0.004, 0.72)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_dim)
	_frame = PanelContainer.new()
	_frame.theme_type_variation = &"InfernalPanel"
	_root.add_child(_frame)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 10)
	_frame.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var tcol := VBoxContainer.new()
	tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tcol.add_theme_constant_override(&"separation", 0)
	head.add_child(tcol)
	_title = Label.new()
	_title.theme_type_variation = &"TitleLabel"
	_title.add_theme_font_size_override(&"font_size", 36)
	tcol.add_child(_title)
	_subtitle = Label.new()
	_subtitle.theme_type_variation = &"LoreLabel"
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.custom_minimum_size.x = 200.0
	tcol.add_child(_subtitle)
	_wallet = CurrencyCounter.new()
	_wallet.font_size = 24
	_wallet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_wallet)
	col.add_child(HSeparator.new())
	_gauge_box = VBoxContainer.new()
	_gauge_box.add_theme_constant_override(&"separation", 4)
	col.add_child(_gauge_box)
	_gauge_label = Label.new()
	_gauge_label.theme_type_variation = &"CaptionLabel"
	_gauge_box.add_child(_gauge_label)
	_gauge = InfernalBar.new()
	_gauge.custom_minimum_size = Vector2(0, 10)
	_gauge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gauge.trail_color = Color(0, 0, 0, 0)
	_gauge_box.add_child(_gauge)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	col.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 8)
	_scroll.add_child(_list)
	var foot := HBoxContainer.new()
	col.add_child(foot)
	_footer = Label.new()
	_footer.theme_type_variation = &"CaptionLabel"
	_footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_footer)
	var leave := Button.new()
	leave.theme_type_variation = &"GhostButton"
	leave.text = "LEAVE"
	leave.pressed.connect(close)
	Sfx.wire_button(leave, &"ui_back")
	foot.add_child(leave)
