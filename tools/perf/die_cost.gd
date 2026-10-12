extends Node
## Profiles deaths only: spawns N of each --only= type, waits, then kills them one per frame so
## the profiler (-d --profiling) attributes die() costs. Headless:
##   godot --headless --path . -d --profiling res://tools/perf/die_cost.tscn -- --only=archon


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	while int(Sfx.get(&"_gen_task")) != -1 and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
	var world := Node3D.new()
	add_child(world)
	Game.world = world
	var ids := PackedStringArray(["archon"])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			ids = a.substr(7).split(",")
	for id in ids:
		var data := load("res://data/enemies/%s.tres" % id) as EnemyData
		var es: Array[Enemy] = []
		for i in 12:
			var e := (load("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate() as Enemy
			e.setup(data)
			e.position = Vector3(i * 3.0, 0, 0)
			world.add_child(e)
			es.append(e)
		await get_tree().physics_frame
		var total := 0
		for e in es:
			var t1 := Time.get_ticks_usec()
			e.die()
			total += Time.get_ticks_usec() - t1
			await get_tree().process_frame
		@warning_ignore("integer_division")
		print("[PERF] %s die avg %d us" % [id, total / es.size()])
	get_tree().quit()
