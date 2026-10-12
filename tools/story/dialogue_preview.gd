extends Node
## Dialogue preview / QA scene (story role). Plays one conversation over a dark backdrop and
## presses "confirm" (and the first choice) automatically, so screenshots can be taken.
##   godot --path . res://tools/story/dialogue_preview.tscn -- --story --talk=vesper_intro
##       [--demon=lilaeth] [--press-every=1.5] [--shot=out.png --shot-time=6]
## --story is needed because --shot otherwise puts Dialogue in test mode (no story playback).

var _talk := "vesper_intro"
var _every := 1.5


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--talk="):
			_talk = arg.substr(7)
		elif arg.begins_with("--press-every="):
			_every = arg.substr(14).to_float()
	var layer := CanvasLayer.new()
	var bg := ColorRect.new()
	bg.color = Color(0.14, 0.04, 0.03)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	add_child(layer)
	await get_tree().create_timer(0.3).timeout
	if _talk.begins_with("bark:"):
		Dialogue.bark(_talk.substr(5))
		return
	Dialogue.start(_talk)
	while Dialogue.is_active():
		await get_tree().create_timer(_every, true).timeout
		_press()


## Confirms the current line, or picks the first choice when choices are showing.
func _press() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus is Button:
		(focus as Button).pressed.emit()
		return
	var ev := InputEventAction.new()
	ev.action = &"ui_accept"
	ev.pressed = true
	Input.parse_input_event(ev)
