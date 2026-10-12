extends Node
## Roster cost report: for every res://data/enemies/*.tres, the warm cost of spawning one Enemy
## (instance + _ready + model build, averaged), its node / mesh / light / AnimationPlayer counts and
## the cost of its death. Sorted by spawn cost; flags anything over the budgets in
## docs/team/performance.md. Headless:
##   godot --headless --path . res://tools/perf/spawn_cost.tscn
## Optional user args: -- --only=seraph,archon   -- --gate (exit 1 if a type breaks a HARD_ limit)

const SPAWN_BUDGET_US := 1500
const MESH_BUDGET := 30
const N := 8
## QA gate (--gate): hard limits, ~4x the budgets so only real regressions fail.
const HARD_SPAWN_US := 5000
const HARD_MESHES := 60


func _ready() -> void:
	await _wait_quiet()
	var world := Node3D.new()
	add_child(world)
	Game.world = world
	await get_tree().process_frame
	var only := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7).split(",")
	var scene := load("res://scenes/enemies/enemy.tscn") as PackedScene
	var rows: Array = []
	for f in DirAccess.get_files_at("res://data/enemies"):
		var file := f.trim_suffix(".remap")
		if not file.ends_with(".tres"):
			continue
		var id := file.get_basename()
		if not only.is_empty() and not only.has(id):
			continue
		var data := load("res://data/enemies/" + file) as EnemyData
		if data == null:
			continue
		# Warm-up (first load of the model / textures / shaders is not what we measure).
		var w := scene.instantiate() as Enemy
		w.setup(data)
		world.add_child(w)
		w.free()
		var es: Array[Enemy] = []
		var t0 := Time.get_ticks_usec()
		for i in N:
			var e := scene.instantiate() as Enemy
			e.setup(data)
			e.position = Vector3(i * 3.0, 0.0, 0.0)
			world.add_child(e)
			es.append(e)
		@warning_ignore("integer_division")
		var spawn_us := (Time.get_ticks_usec() - t0) / N
		var counts := _count(es[0])
		await get_tree().physics_frame
		t0 = Time.get_ticks_usec()
		for e in es:
			e.die()
		@warning_ignore("integer_division")
		var die_us := (Time.get_ticks_usec() - t0) / N
		rows.append([spawn_us, id, counts, die_us])
		for c in world.get_children():
			c.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	print("[PERF] %-22s %8s %8s %6s %6s %5s %5s  flags" % ["enemy", "spawn_us", "die_us", "nodes", "meshes", "anims", "lights"])
	for r in rows:
		var c: Dictionary = r[2]
		var flags := ""
		if r[0] > SPAWN_BUDGET_US:
			flags += " SLOW-SPAWN"
		if c["meshes"] > MESH_BUDGET:
			flags += " MANY-MESHES"
		if c["lights"] > 0:
			flags += " LIGHTS"
		print("[PERF] %-22s %8d %8d %6d %6d %5d %5d %s" % [r[1], r[0], r[3], c["nodes"], c["meshes"], c["anims"], c["lights"], flags])
	if "--gate" in OS.get_cmdline_user_args():
		var bad := 0
		for r in rows:
			var c: Dictionary = r[2]
			if r[0] > HARD_SPAWN_US or c["meshes"] > HARD_MESHES:
				bad += 1
				print("[PERF] GATE FAIL: %s spawn %d us (max %d), %d meshes (max %d)" % [r[1], r[0], HARD_SPAWN_US, c["meshes"], HARD_MESHES])
		print("[PERF] roster gate: %s" % ("OK" if bad == 0 else "%d type(s) over the hard limits" % bad))
		get_tree().quit(1 if bad > 0 else 0)
		return
	get_tree().quit()


static func _count(root: Node) -> Dictionary:
	var d := {"nodes": 0, "meshes": 0, "anims": 0, "lights": 0}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		d["nodes"] += 1
		if n is GeometryInstance3D:
			d["meshes"] += 1
		elif n is AnimationMixer:
			d["anims"] += 1
		elif n is Light3D:
			d["lights"] += 1
		stack.append_array(n.get_children())
	return d


## Waits (max ~20 s) for Sfx's background synthesis to finish: it competes for the CPU and
## would make the first measurements meaningless.
func _wait_quiet() -> void:
	var t0 := Time.get_ticks_msec()
	while int(Sfx.get(&"_gen_task")) != -1 and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
