class_name HubNpc
extends HubInteractable
## A talkable ambient Basecamp NPC from res://data/npcs/npcs.json (characters-new): wraps the
## roster model (spawned with its collision) in a HubInteractable. Talking makes the model react
## (talk()) and plays, in order of preference: an unseen story beat from the Dialogue pool named
## by `speaker` (story role can add one any time), a repeatable line from that pool as a bark,
## else one of the entry's own "lines" as a subtitle. Placed by CharacterRoster.populate_basecamp
## for entries with "talk": true. (Pip, Kesh and Malphine are the story role's StoryNpc instead.)

var npc_id := ""
## Dialogue speaker / pool id (defaults to npc_id).
var speaker := ""
var lines: Array = []
## Show `lines` as narration instead of speech (e.g. the kennel).
var narrate := false
var model: ProcModel

var _last_line := -1


## A HubNpc for npcs.json entry `id`, or null if unknown.
static func create(id: String) -> HubNpc:
	var def: Dictionary = CharacterRoster.npcs().get(id, {})
	if def.is_empty():
		return null
	var n := HubNpc.new()
	n.npc_id = id
	n.speaker = String(def.get("speaker", id))
	n.lines = def.get("lines", [])
	n.narrate = bool(def.get("narrate", false))
	n.label = String(def.get("name", id.capitalize()))
	n.verb = String(def.get("verb", "Talk"))
	n.radius = float(def.get("talk_radius", 2.4))
	n.prompt_height = float(def.get("height", 1.8)) + 0.5
	return n


func _ready() -> void:
	super._ready()
	model = CharacterRoster.spawn_npc(self, StringName(npc_id), Vector3.ZERO, 0.0)


func interact() -> void:
	super.interact()
	if model:
		model.talk()
	var dlg := get_node_or_null(^"/root/Dialogue")
	if dlg:
		if bool(dlg.call(&"is_active")):
			return
		if speaker == "":
			pass  # no dialogue pool: our own lines only
		elif bool(dlg.call(&"has_new", speaker)) and String(dlg.call(&"start_for", speaker)) != "":
			return
		elif String(dlg.call(&"bark", speaker, true)) != "":
			return
	if lines.is_empty():
		return
	# A line of our own, never the same one twice in a row.
	var i := randi() % lines.size()
	if lines.size() > 1 and i == _last_line:
		i = (i + 1) % lines.size()
	_last_line = i
	if dlg == null:
		return
	if narrate or speaker == "":
		dlg.call(&"narrate", String(lines[i]))
	else:
		dlg.call(&"say", speaker, String(lines[i]))
