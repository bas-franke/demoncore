class_name PassiveData
extends Resource
## A stackable passive item. Each level adds `amount_per_level` to the Player property named `stat`.

@export var display_name := "Passive"
@export_multiline var description := ""
@export var color := Color.WHITE
## Emoji or short text shown on level-up cards.
@export var icon := "?"
## Name of a numeric Player property, e.g. &"might", &"move_speed", &"pickup_radius".
@export var stat: StringName
@export var amount_per_level := 0.1
@export var max_level := 5
