extends Node
## Prints an enemy model's node tree with mesh / surface counts (perf: where do instances go?).
##   godot --headless --path . res://tools/perf/model_tree.tscn -- --only=cherub,ophan


func _ready() -> void:
	var world := Node3D.new()
	add_child(world)
	Game.world = world
	var ids := PackedStringArray(["cherub"])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			ids = a.substr(7).split(",")
	for id in ids:
		var data := load("res://data/enemies/%s.tres" % id) as EnemyData
		var e := (load("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate() as Enemy
		e.setup(data)
		world.add_child(e)
		await get_tree().process_frame
		await get_tree().process_frame
		print("[TREE] ==== %s" % id)
		_dump(e.model, 0)
		e.queue_free()
	get_tree().quit()


func _dump(n: Node, depth: int) -> void:
	var info := ""
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		info = " MESH surf=%d shadow=%d %s" % [mi.mesh.get_surface_count() if mi.mesh else 0, mi.cast_shadow,
				mi.mesh.get_class() if mi.mesh else ""]
	elif n is GeometryInstance3D:
		info = " GEOM"
	print("[TREE] %s%s (%s)%s" % ["  ".repeat(depth), n.name, n.get_class(), info])
	for c in n.get_children():
		_dump(c, depth + 1)
