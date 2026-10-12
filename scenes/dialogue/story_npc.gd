class_name StoryNpc
extends HubInteractable
## A talkable Basecamp NPC without a shop (Pip, Kesh the Breachwarden, Duchess Malphine): a
## CharacterRoster NPC model (res://data/npcs/npcs.json, characters-new) wrapped in a
## HubInteractable. It turns to watch the demon; talking plays its next story beat (Dialogue pool
## = speaker id) or, with nothing new, a line of chatter as a bark. Offerings work through the
## StoryMarker the hooks attach. Spawned by StoryHooks via StoryNpc.create().

## Speaker / pool id in the dialogue data.
var speaker := ""
## Yaw the model faces when nobody is near (0 = facing -Z, PI = the camera).
var rest_yaw := PI

var _model: Node3D
var _yaw := PI


## A StoryNpc for roster NPC `npc_id`, or null if the roster has no model for it.
static func create(npc_id: String, speaker_id: String) -> StoryNpc:
	var def: Dictionary = CharacterRoster.npcs().get(npc_id, {})
	if def.is_empty():
		return null
	var n := StoryNpc.new()
	n.speaker = speaker_id
	n.set_meta(&"npc_id", npc_id)
	n.prompt_height = float(def.get("height", 1.8)) + 0.5
	return n


func _ready() -> void:
	verb = "Talk"
	radius = 2.4
	var sp: Dictionary = Dialogue.speaker(speaker)
	label = str(sp.get("name", speaker.capitalize()))
	super._ready()
	_yaw = rest_yaw
	_model = CharacterRoster.spawn_npc(self, StringName(get_meta(&"npc_id")), Vector3.ZERO, _yaw)


func _process(delta: float) -> void:
	super._process(delta)
	if _model == null:
		return
	var avatar := get_tree().get_first_node_in_group(&"hub_avatar") as Node3D
	var want := rest_yaw
	if avatar and flat_distance(avatar.global_position) < 6.0:
		var dv := avatar.global_position - global_position
		want = atan2(-dv.x, -dv.z)
	_yaw = lerp_angle(_yaw, want, 1.0 - exp(-4.0 * delta))
	_model.rotation.y = _yaw


func interact() -> void:
	super.interact()
	if _model and _model.has_method(&"talk"):
		_model.call(&"talk")
	if Dialogue.is_active():
		return
	if Dialogue.has_new(speaker):
		Dialogue.start_for(speaker)
	else:
		Dialogue.bark(speaker, true)
