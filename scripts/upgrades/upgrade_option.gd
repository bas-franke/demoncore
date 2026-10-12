class_name UpgradeOption
extends RefCounted
## One choice shown on the level-up screen.

var title: String
var description: String
var color: Color
var apply: Callable
var icon := "?"
## True when this option grants something the player doesn't own yet.
var is_new := false


func _init(p_title: String, p_description: String, p_color: Color, p_apply: Callable) -> void:
	title = p_title
	description = p_description
	color = p_color
	apply = p_apply
