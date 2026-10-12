extends CanvasLayer
## Shown when the demon falls. A dark band rises across the screen, the word "UNMADE" fades in
## slowly in red serif, then the tally and the choices follow. Opened by main.gd on
## RunState.run_ended; a victorious run gets a golden "ASCENDANT" variant. The run currency
## (RunState) is shown and carried back to Basecamp Hell ("Return to Basecamp").

const DEMON_SELECT_SCENE := "res://scenes/menu/demon_select.tscn"
const PALE_GOLD := UIPalette.BONE_BRIGHT
const MUTED := UIPalette.ASH_TEXT
const BAND_FADE := 1.2
const WORD_DELAY := 0.5
const WORD_FADE := 2.4
const DETAILS_DELAY := 2.9

@onready var stats_box: HBoxContainer = %Stats
@onready var restart_button: Button = %Restart
@onready var change_button: Button = %ChangeDemon
@onready var quit_button: Button = %Quit
@onready var center: Control = %Center
@onready var dim: ColorRect = %Dim
@onready var band: TextureRect = %Band
@onready var title: Label = %Title
@onready var details: Control = %Details

var _ready_for_input := false
## Souls banked, extra tallies and the demon's powers (scenes/ui/run_ledger.gd).
var _ledger: RunLedger


func _ready() -> void:
	visible = false
	band.texture = _band_texture()
	restart_button.pressed.connect(_on_restart)
	# [gameplay] Ascension: "Ascend" after a won run plays on for score (RunState.ascend()).
	_ascend_button = Button.new()
	_ascend_button.name = &"Ascend"
	_ascend_button.theme_type_variation = &"AccentButton"
	_ascend_button.text = "Ascend"
	_ascend_button.tooltip_text = "Play on for score. The Host grows stronger every minute."
	restart_button.add_sibling(_ascend_button)
	restart_button.get_parent().move_child(_ascend_button, 0)
	_ascend_button.pressed.connect(_on_ascend)
	_ascend_button.mouse_entered.connect(_hover)
	_ascend_button.visible = false
	change_button.pressed.connect(_on_change_demon)
	quit_button.pressed.connect(_on_quit)
	for b: Button in [restart_button, change_button, quit_button]:
		b.mouse_entered.connect(_hover)
		b.focus_entered.connect(_hover)
	_ledger = RunLedger.new()
	details.add_child(_ledger)
	details.move_child(_ledger, stats_box.get_index() + 1)


var _ascend_button: Button


func open() -> void:
	var p := Game.player
	for c in stats_box.get_children():
		stats_box.remove_child(c)
		c.queue_free()
	_add_stat(TextFormat.clock(Game.elapsed), "Time endured", false)
	_add_stat(str(p.level if p else 1), "Ascension", true)
	_add_stat(str(Game.kills), "Angels slain", true)
	_add_stat(str(RunState.currency), RunState.CURRENCY_NAME + " claimed", true)
	var asc_run := bool(RunState.last_result.get("ascension", false))
	if asc_run:
		_add_stat(str(RunState.last_result.get("ascension_score", 0)), "Ascension score", true)
		_add_stat(str(RunState.last_result.get("ascension_best", 0)),
				"New best!" if RunState.last_result.get("ascension_new_best", false) else "Best", true)
	_ascend_button.visible = RunState.can_ascend()
	_apply_outcome(bool(RunState.last_result.get("victory", false)))
	_ledger.fill(RunState.last_result)

	visible = true
	_ready_for_input = false
	get_tree().paused = true
	Sfx.play_music(&"run_end")  # music role: defeat dirge, or victory stinger + fade (docs/team/music.md)
	Sfx.play(&"triumph" if RunState.run_won() else &"unmade", 0.0)
	for b: Button in [restart_button, change_button, quit_button, _ascend_button]:
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var dt := dim.create_tween()
	dt.tween_property(dim, "modulate:a", 1.0, 2.0).from(0.0).set_trans(Tween.TRANS_SINE)

	band.modulate.a = 0.0
	var bt := band.create_tween()
	bt.tween_property(band, "modulate:a", 1.0, BAND_FADE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	title.modulate.a = 0.0
	title.pivot_offset = title.size * 0.5
	var tt := title.create_tween()
	tt.tween_interval(WORD_DELAY)
	tt.tween_property(title, "modulate:a", 1.0, WORD_FADE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tt.parallel().tween_property(title, "scale", Vector2(1.05, 1.05), 7.0).from(Vector2.ONE) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	details.modulate.a = 0.0
	var de := details.create_tween()
	de.tween_interval(DETAILS_DELAY)
	de.tween_property(details, "modulate:a", 1.0, 1.4).set_trans(Tween.TRANS_SINE)
	de.parallel().tween_callback(_enable_input).set_delay(0.5)


## Title, subtitle and button labels for death vs victory (texts in the .tscn are the death ones).
func _apply_outcome(victory: bool) -> void:
	var sub := get_node_or_null(^"Root/Center/Details/Subtitle") as Label
	if RunState.last_result.get("ascension", false):
		title.text = "ASCENSION ENDS"
		title.add_theme_color_override(&"font_color", PALE_GOLD)
		if sub:
			sub.text = "Heaven paid dearly for every minute thou didst endure."
	elif victory:
		title.text = "ASCENDANT"
		title.add_theme_color_override(&"font_color", PALE_GOLD)
		if sub:
			sub.text = "The Host is broken. Hell remembers thy name."
	else:
		title.text = "UNMADE"
		title.add_theme_color_override(&"font_color", UIPalette.BLOOD_BRIGHT.darkened(0.15))
		if sub:
			sub.text = "Thy flesh returns to the pit. The Host sings on."
	restart_button.text = "Rise Again"
	change_button.text = "Return to Basecamp"


func _input(event: InputEvent) -> void:
	# Keyboard / pad: refocus the first choice if a mouse click left nothing focused (UI role).
	if visible and _ready_for_input:
		UINav.recover_focus(event, restart_button)


func _enable_input() -> void:
	if not visible:
		return
	_ready_for_input = true
	for b: Button in [restart_button, change_button, quit_button, _ascend_button]:
		b.focus_mode = Control.FOCUS_ALL
		b.mouse_filter = Control.MOUSE_FILTER_STOP
	if _ascend_button.visible:
		_ascend_button.grab_focus()
	else:
		restart_button.grab_focus()


func _add_stat(value: String, caption: String, divider_before: bool) -> void:
	if divider_before:
		var sep := VSeparator.new()
		sep.custom_minimum_size = Vector2(0.0, 52.0)
		sep.modulate = Color(1, 1, 1, 0.7)
		stats_box.add_child(sep)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(150.0, 0.0)
	box.add_theme_constant_override(&"separation", 0)
	var v := Label.new()
	v.theme_type_variation = &"TitleLabel"
	v.add_theme_font_size_override(&"font_size", 30)
	v.add_theme_color_override(&"font_color", PALE_GOLD)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.text = value
	box.add_child(v)
	var c := Label.new()
	c.theme_type_variation = &"LoreLabel"
	c.add_theme_font_size_override(&"font_size", 16)
	c.add_theme_color_override(&"font_color", MUTED)
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.text = caption
	box.add_child(c)
	stats_box.add_child(box)


func _band_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 0.5, 0.7, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.72), Color(0, 0, 0, 0.82),
		Color(0, 0, 0, 0.72), Color(0, 0, 0, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 1
	tex.height = 128
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	return tex


func _hover() -> void:
	if _ready_for_input:
		Sfx.play(&"ui_hover", 0.03)


func _on_restart() -> void:
	if not _ready_for_input:
		return
	Sfx.play(&"select", 0.02)
	RunState.restart_run()


func _on_change_demon() -> void:
	if not _ready_for_input:
		return
	Sfx.play(&"ui_click", 0.02)
	RunState.return_to_basecamp()


func _on_ascend() -> void:
	if not _ready_for_input or not RunState.can_ascend():
		return
	Sfx.play(&"select", 0.02)
	visible = false
	_ready_for_input = false
	RunState.ascend()  # unpauses
	Sfx.play_music(&"backyard")  # back to battle (music role may pick a dedicated track)


func _on_quit() -> void:
	if not _ready_for_input:
		return
	get_tree().quit()
