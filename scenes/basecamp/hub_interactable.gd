class_name HubInteractable
extends Node3D
## Something in Basecamp Hell the demon can walk up to and use (shopkeepers, the hellgate, the
## summoning circle). The hub picks the closest one within `radius` of the avatar, shows its
## floating prompt, and calls interact() on the interact key (E / Enter / gamepad X or A).
##
## Others can add their own: make a HubInteractable child of the Basecamp scene (or call
## Basecamp.add_interactable) and connect `interacted`.

signal interacted

## Verb shown in the prompt, e.g. "Trade".
@export var verb := "Use"
## Name shown in the prompt, e.g. "Grimmaul, Blacksmith".
@export var label := ""
## Activation distance on the ground plane (from this node's origin).
@export var radius := 2.6
## Height of the floating prompt above the origin.
@export var prompt_height := 3.0
## Model that gets the pulsing ember outline while focused (ArtStyle.outline, art-style role).
## Null = this node's own meshes (shopkeepers are their own model); set it for standalone
## interactables placed next to a model (the bar's succubus, ...).
@export var highlight: Node3D

var _prompt: Label3D
var _focused := false
var _near := true
var _t := 0.0


func _ready() -> void:
	add_to_group(&"hub_interactables")
	_prompt = Label3D.new()
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.fixed_size = true
	_prompt.pixel_size = 0.0011
	_prompt.font_size = 30
	_prompt.outline_size = 10
	_prompt.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	_prompt.modulate = UIPalette.BONE_BRIGHT
	_prompt.position = Vector3(0.0, prompt_height, 0.0)
	_prompt.render_priority = 10
	_prompt.outline_render_priority = 9
	add_child(_prompt)
	_refresh_prompt()


func _process(delta: float) -> void:
	_t += delta
	# The name floats faintly while the avatar is nearby; the key hint only shows when focused.
	var a := 1.0 if _focused else (0.6 if _near else 0.0)
	_prompt.modulate.a = lerpf(_prompt.modulate.a, a, 1.0 - exp(-10.0 * delta))
	_prompt.position.y = prompt_height + (0.05 * sin(_t * 2.4) if _focused else 0.0)


func set_focused(on: bool) -> void:
	if on == _focused:
		return
	_focused = on
	_refresh_prompt()
	var target: Node3D = highlight if is_instance_valid(highlight) else self
	if on:
		ArtStyle.outline(target, ArtStyle.INTERACT, 3.0, 0.6, 1.8)
	else:
		ArtStyle.clear_outline(target)


func is_focused() -> bool:
	return _focused


func interact() -> void:
	interacted.emit()


## Distance on the ground plane from `pos` to this interactable.
func flat_distance(pos: Vector3) -> float:
	return Vector2(pos.x - global_position.x, pos.z - global_position.z).length()


func _refresh_prompt() -> void:
	if _prompt == null:
		return
	if _focused:
		_prompt.text = "%s\n[E]  %s" % [label, verb]
		_prompt.font_size = 32
	else:
		_prompt.text = label
		_prompt.font_size = 26


## Whether the avatar is close enough for the unfocused name to show (set by the hub).
func set_near(on: bool) -> void:
	_near = on


## Re-renders the prompt text (after changing `label` or `verb`).
func refresh() -> void:
	_refresh_prompt()
