extends Node
## Story QA: loads Basecamp Hell, walks the avatar up to an NPC so its prompt, "!" marker and
## offering hint are focused, for screenshots. Use a dev save so the real one is untouched:
##   godot --path . res://tools/story/camp_probe.tscn -- --story --story-save=user://story_dev.json
##       [--probe=pip|kesh|malphine|crown] [--shot=out.png --shot-time=5]

const SPOTS := {"pip": Vector3(3.4, 0.0, 3.8), "kesh": Vector3(-3.2, 0.0, -6.8),
		"malphine": Vector3(5.0, 0.0, 2.6), "crown": Vector3(-2.6, 0.0, 3.6)}


func _ready() -> void:
	var probe := "pip"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--probe="):
			probe = a.substr(8)
	await get_tree().process_frame
	# Survive the scene change: hand "current scene" to a throwaway node, keep this one at root.
	var tree := get_tree()
	var dummy := Node.new()
	tree.root.add_child(dummy)
	tree.current_scene = dummy
	tree.change_scene_to_file("res://scenes/basecamp/basecamp.tscn")
	await tree.create_timer(2.0).timeout
	var camp := get_tree().current_scene
	var avatar: Variant = camp.get(&"avatar") if camp else null
	if avatar is Node3D:
		(avatar as Node3D).global_position = SPOTS.get(probe, Vector3.ZERO)
