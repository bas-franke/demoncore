extends Node
## Read-only check (never saves): on a fresh unlock state, Heaven's Gate cannot be reached early.
##   godot --headless --path . res://tools/maps/gate_lock_check.tscn


func _ready() -> void:
	var saved: Array[String] = Meta.unlocked_maps.duplicate()
	Meta.unlocked_maps.clear()  # fresh save (in memory only)
	var fails := 0
	for id: StringName in [&"storm_spire", &"heavens_gate"]:
		var open := Meta.is_map_unlocked(id)
		var req := Meta.map_requirement(id)
		print("GATELOCK %s unlocked=%s requirement=\"%s\" cost=%d" % [id, open, req, Meta.map_cost(id)])
		if open or req == "":
			fails += 1
	# storm_spire bought, story not yet there: the Gate still asks for the story flag
	Meta.unlocked_maps.append("storm_spire")
	var flag := Dialogue.has_flag("known.march") if has_node(^"/root/Dialogue") else false
	var req2 := Meta.map_requirement(&"heavens_gate")
	print("GATELOCK with storm_spire: requirement=\"%s\" (known.march=%s)" % [req2, flag])
	if not flag and req2 == "":
		fails += 1
	print("GATELOCK DONE fails=%d" % fails)
	Meta.unlocked_maps.assign(saved)
	get_tree().quit(fails)
