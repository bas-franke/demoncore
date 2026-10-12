class_name AscensionScore
extends CanvasLayer
## Minimal Ascension score readout (gameplay role; the UI role may restyle or replace it: any node
## in group "ascension_hud" makes RunState skip adding this one). Added by RunState.ascend() to the
## run scene, top-centre under the timer: "ASCENSION II  ·  12 480".

var _label: Label


func _ready() -> void:
	layer = 5
	add_to_group(&"ascension_hud")
	_label = Label.new()
	_label.theme_type_variation = &"ValueLabel"
	_label.add_theme_font_size_override(&"font_size", 22)
	_label.add_theme_color_override(&"font_color", Color("ff9a52"))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_label.offset_top = 64.0
	_label.offset_left = -200.0
	_label.offset_right = 200.0
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	RunState.score_changed.connect(func(_s: int) -> void: _refresh())
	_refresh()


func _process(_delta: float) -> void:
	visible = RunState.ascending
	if visible and Engine.get_process_frames() % 15 == 0:
		_refresh()


func _refresh() -> void:
	_label.text = "ASCENSION %s  ·  %s" % [_roman(int(RunState.ascension_minutes()) + 1), _group(RunState.ascension_score)]


static func _group(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


static func _roman(n: int) -> String:
	const VALS := [10, 9, 5, 4, 1]
	const SYMS := ["X", "IX", "V", "IV", "I"]
	var out := ""
	for i in VALS.size():
		while n >= VALS[i]:
			out += SYMS[i]
			n -= VALS[i]
	return out
