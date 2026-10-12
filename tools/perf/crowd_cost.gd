extends Node
## Crowd physics cost: N enemies packed around the origin, all sliding inward (headless):
##   godot --headless --path . res://tools/perf/crowd_cost.tscn
## Compares move_and_slide with enemy-enemy collisions on vs off (mask = world only), and off +
## Crowd.push() separation (what the game uses).

const N := 300


func _ready() -> void:
	await _wait_quiet()
	var world := Node3D.new()
	add_child(world)
	Game.world = world
	var data := load("res://data/enemies/seraph_sentinel.tres") as EnemyData
	var es: Array[Enemy] = []
	for i in N:
		var e := (load("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate() as Enemy
		e.setup(data)
		var a := randf() * TAU
		e.position = Vector3(cos(a), 0, sin(a)) * randf_range(1.0, 9.0)
		world.add_child(e)
		e.set_physics_process(false)
		es.append(e)
	for mode in ["collide", "collide_slides2", "collide_slides1", "nocollide", "crowd", "position", "nocollide_nomodel"]:
		seed(7)
		for e in es:
			var a := randf() * TAU
			e.position = Vector3(cos(a), 0, sin(a)) * randf_range(1.0, 9.0)
			e.collision_mask = 5 if mode.begins_with("collide") else 1
			e.max_slides = 2 if mode == "collide_slides2" else (1 if mode == "collide_slides1" else 6)
			if mode == "nocollide_nomodel" and e.model.get_parent() == e:
				e.remove_child(e.model)
		var total := 0
		var push_us := 0
		for tick in 30:
			await get_tree().physics_frame
			var t0 := Time.get_ticks_usec()
			for e in es:
				e.velocity = -e.position.normalized() * 3.0
				if mode == "crowd":
					var tp := Time.get_ticks_usec()
					e.velocity += Crowd.push(e)
					push_us += Time.get_ticks_usec() - tp
				if mode == "position":
					e.position += e.velocity / 30.0
				else:
					e.move_and_slide()
			total += Time.get_ticks_usec() - t0
		print("%s: move_and_slide for %d packed enemies = %.2f ms per tick (Crowd.push %.2f ms)" % [mode, N, total / 30.0 / 1000.0, push_us / 30.0 / 1000.0])
	get_tree().quit()


## Waits (max ~20 s) for Sfx's background synthesis to finish: it competes for the CPU and
## would make the first measurements meaningless.
func _wait_quiet() -> void:
	var t0 := Time.get_ticks_msec()
	while int(Sfx.get(&"_gen_task")) != -1 and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
