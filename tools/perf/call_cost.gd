extends Node
## Per-call costs of the enemy hot path (headless):
##   godot --headless --path . res://tools/perf/call_cost.tscn
## Prints microseconds per call for model.animate, set_flash (hit flash), take_damage and a crowded
## move_and_slide, per enemy type. Multiply by calls per frame to find what dominates.

const TYPES := ["choir_wisp", "seraph_sentinel", "penitent_statue", "thurible_priest", "ophanim", "dawn_lancer", "archon"]


func _ready() -> void:
	await _wait_quiet()
	var world := Node3D.new()
	add_child(world)
	Game.world = world
	await get_tree().process_frame
	for id in TYPES:
		var data := load("res://data/enemies/%s.tres" % id) as EnemyData
		if data == null:
			continue
		var es: Array[Enemy] = []
		for i in 30:
			var e := (load("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate() as Enemy
			e.setup(data)
			e.position = Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
			world.add_child(e)
			es.append(e)
		await get_tree().physics_frame
		var n := es.size()
		var t0 := Time.get_ticks_usec()
		for e in es:
			e.model.animate(0.016, 0.8, 0)
		var t_anim := float(Time.get_ticks_usec() - t0) / n
		for e in es:
			e.model.set_flash(0.6)  # first call builds Art.flash's mesh cache
		t0 = Time.get_ticks_usec()
		for e in es:
			e.model.set_flash(0.5)
		var t_flash := float(Time.get_ticks_usec() - t0) / n
		t0 = Time.get_ticks_usec()
		for e in es:
			e.velocity = Vector3(1, 0, 0)
			e.move_and_slide()
		var t_slide := float(Time.get_ticks_usec() - t0) / n
		var show := Game.show_damage_numbers
		Game.show_damage_numbers = false
		t0 = Time.get_ticks_usec()
		for e in es:
			e.take_damage(0.001)
		var t_dmg := float(Time.get_ticks_usec() - t0) / n
		Game.show_damage_numbers = true
		t0 = Time.get_ticks_usec()
		for e in es:
			DamageNumber.spawn(3.0, e.global_position)
		var t_num := float(Time.get_ticks_usec() - t0) / n
		Game.show_damage_numbers = show
		@warning_ignore("integer_division")
		var half := n / 3
		t0 = Time.get_ticks_usec()
		for i in half:
			Game.enemy_died.emit(es[i].global_position, data)
		var t_emit := float(Time.get_ticks_usec() - t0) / half
		t0 = Time.get_ticks_usec()
		for i in half:
			es[i].model.spawn_corpse()
		var t_corpse := float(Time.get_ticks_usec() - t0) / half
		t0 = Time.get_ticks_usec()
		for i in half:
			es[i].model.death_burst(es[i].global_position, data.size, false)
		var t_burst := float(Time.get_ticks_usec() - t0) / half
		t0 = Time.get_ticks_usec()
		for e in es:
			e.die()
		var t_die := float(Time.get_ticks_usec() - t0) / n
		print("   died listeners=%.0fus corpse=%.0fus death_burst(incl corpse)=%.0fus" % [t_emit, t_corpse, t_burst])
		var nodes := 0
		var stack: Array[Node] = [es[0].model]
		while not stack.is_empty():
			var x: Node = stack.pop_back()
			nodes += 1
			stack.append_array(x.get_children())
		print("%-16s nodes=%3d animate=%5.0fus flash=%5.0fus slide(crowd)=%5.0fus take_damage=%5.0fus dmg_number=%5.0fus die=%6.0fus" % [
			id, nodes, t_anim, t_flash, t_slide, t_dmg, t_num, t_die])
		for c in world.get_children():
			c.queue_free()
		await get_tree().process_frame
	get_tree().quit()


## Waits (max ~20 s) for Sfx's background synthesis to finish: it competes for the CPU and
## would make the first measurements meaningless.
func _wait_quiet() -> void:
	var t0 := Time.get_ticks_msec()
	while int(Sfx.get(&"_gen_task")) != -1 and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
