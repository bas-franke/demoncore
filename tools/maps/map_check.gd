extends Node
## Headless sanity check for every registered map (docs/team/maps.md):
##   godot --headless --path . res://tools/maps/map_check.tscn [-- --map=<id>]
## Builds each bounded map, then verifies: the player spawn is walkable, every landmark /
## objective / enemy spawn marker is reachable from the spawn on the nav grid, and the
## build time / draw-call budget. Exits with code 1 on any failure.
## `-- --fast` (QA quick suite): 1 variant per map and 12 physics agents instead of 2 variants x 24 for
## 40 s each. Always run with `--fixed-fps 60 --disable-vsync`: the agent sim awaits physics frames,
## so without it the check runs in real time (~12 min for 10 maps; ~20 s with it).

var _failed := false
## Physics-agent sim size (--fast shrinks it).
var _agent_count := 24
var _agent_secs := 40


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var maps := Maps
	var only := ""
	var variants := 2
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			only = a.substr(6)
		elif a.begins_with("--variants="):
			variants = a.substr(11).to_int()
		elif a == "--fast":  # QA: quick-suite mode (docs/team/qa.md)
			variants = 1
			_agent_count = 12
			_agent_secs = 40  # shorter sims strand agents on the island maps (gilded_isles, the_breach)
	for d: Dictionary in maps.all():
		if only != "" and d["id"] != only:
			continue
		for v in variants:
			await _check(d, v + 1)
	print("MAP CHECK: %s" % ("FAILED" if _failed else "OK"))
	get_tree().quit(1 if _failed else 0)


func _check(d: Dictionary, variant: int = 1) -> void:
	var id: String = d["id"]
	var map: GameMap
	var path := String(d.get("scene", ""))
	if path != "":
		map = (load(path) as PackedScene).instantiate() as GameMap
	elif String(d.get("generator", "")) != "":
		map = (load(String(d["generator"])) as Script).new() as GameMap
	else:
		print("[%s] open map (no layout) - skipped" % id)
		return
	if map == null:
		_fail(id, "map scene/generator does not produce a GameMap")
		return
	var t0 := Time.get_ticks_msec()
	add_child(map)
	map.force_variant = variant
	map.build(d)
	var ms := Time.get_ticks_msec() - t0
	await get_tree().process_frame
	var nav := map.nav_stats()
	var meshes := _count(map, "MeshInstance3D")
	var lights := _count(map, "OmniLight3D")
	var shapes := _count(map, "CollisionShape3D")
	print("[%s v%d] built in %d ms | grid %s, %d/%d blocked | %d meshes, %d lights, %d colliders" %
			[id, variant, ms, nav["size"], nav["blocked"], nav["cells"], meshes, lights, shapes])
	var spawn := map.get_player_spawn()
	if not map.is_walkable(spawn):
		_fail(id, "player spawn %s is not walkable" % spawn)
	var reach := _reachable(map, spawn)
	var checks: Array[Node3D] = []
	checks.append_array(map.get_landmarks())
	checks.append_array(map.get_objective_points())
	checks.append_array(map.get_enemy_spawn_points())
	var kinds := {}
	for mk in checks:
		var p := mk.global_position
		var c := map._cell_of(p)
		var ok := map._in_grid(c) and reach.has(c.y * map._gw + c.x)
		if not ok:
			# landmarks may sit on their own footprint: accept any reachable cell within 4 m
			ok = _near_reachable(map, reach, p, 4.0 if mk.is_in_group(&"map_landmark") else 1.6)
		if not ok:
			_fail(id, "%s at %s is unreachable" % [mk.name, p])
		if mk.is_in_group(&"map_objective"):
			var k: StringName = mk.get_meta(&"kind")
			kinds[k] = int(kinds.get(k, 0)) + 1
	print("    landmarks %d, objectives %s, enemy spawns %d, reachable %.0f%% of open cells" % [
			map.get_landmarks().size(), kinds, map.get_enemy_spawn_points().size(),
			100.0 * float(reach.size()) / maxf(1.0, float(nav["cells"] - nav["blocked"]))])
	for k in [&"altar", &"ritual", &"relic", &"boss_arena"]:
		if not kinds.has(k):
			_fail(id, "no objective of kind %s" % k)
	if meshes > 600:
		_fail(id, "too many mesh instances after merge (%d)" % meshes)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--png="):
			_write_png(map, reach, a.substr(6).path_join("%s_v%d_nav.png" % [id, variant]))
	# steering sanity: from every enemy spawn, following steer() for a while must get closer
	# (no physics here, so an agent that walks into a blocked cell counts as stuck)
	var tf := Time.get_ticks_usec()
	for _k in 10:
		map._update_flow(map._cell_of(map.get_landmarks()[0].global_position))
	print("    flow field update: %.2f ms" % [float(Time.get_ticks_usec() - tf) / 10000.0])
	# the in-game path: time-sliced rebuild, FLOW_BUDGET cells per physics tick
	map._flow_begin(map._cell_of(map.get_player_spawn()))
	var ticks := 0
	var worst := 0
	while true:
		var t1 := Time.get_ticks_usec()
		var done := map._flow_step(map.FLOW_BUDGET)
		worst = maxi(worst, Time.get_ticks_usec() - t1)
		ticks += 1
		if done:
			break
	print("    sliced rebuild: %d ticks, worst tick %.2f ms" % [ticks, float(worst) / 1000.0])
	map._update_flow(map._cell_of(spawn))
	var arrived := 0
	var tried := 0
	for sp in map.get_enemy_spawn_points():
		var pos := sp.global_position
		if pos.distance_to(spawn) > map.FLOW_MAX * map.nav_cell * 0.9:
			continue
		tried += 1
		for _step in 600:
			var to := spawn - pos
			to.y = 0.0
			if to.length() < 3.0:
				arrived += 1
				break
			var next := pos + map.steer(pos, to.normalized()) * 0.4
			if map._blocked_at(next):
				break
			pos = next
	print("    steering: %d/%d enemy spawns in flow range reach the player spawn" % [arrived, tried])
	if tried > 0 and arrived < tried:
		print("    (warn) some agents stall without physics sliding")
	_probe(map)
	await _trace(map)
	await _physics_agents(map, spawn)
	map.queue_free()
	await get_tree().process_frame


## Real physics: 24 capsule bodies (enemy-sized, colliding with layer 1 like Enemy) start on
## random walkable spots 12-40 m from the "player" (a fixed point) and chase it with Maps-style
## steering + move_and_slide for 40 simulated seconds. Reports how many arrive within 3 m.
func _physics_agents(map: GameMap, target: Vector3) -> void:
	var agents: Array[CharacterBody3D] = []
	for i in _agent_count:
		var b := CharacterBody3D.new()
		b.collision_layer = 0
		b.collision_mask = 1
		b.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
		var cs := CollisionShape3D.new()
		var sh := CapsuleShape3D.new()
		sh.radius = 0.4
		sh.height = 1.6
		cs.shape = sh
		cs.position.y = 0.8
		b.add_child(cs)
		b.position = map.random_point(target, 12.0, 40.0)
		b.set_meta(&"start", b.position)
		add_child(b)
		agents.append(b)
	var steps := _agent_secs * Engine.physics_ticks_per_second
	var arrived := {}
	var stuck := {}
	for _s in steps:
		map._flow_cell = map._cell_of(target)
		if _s % 6 == 0:
			map._update_flow(map._flow_cell)
		for b in agents:
			if arrived.has(b):
				continue
			var to := target - b.global_position
			to.y = 0.0
			if to.length() < 3.0:
				arrived[b] = true
				continue
			# same un-stick nudge as Enemy (scenes/enemies/enemy.gd)
			var st: Dictionary = stuck.get(b, {"t": 0.0, "u": 0.0, "d": Vector3.ZERO})
			var want := map.steer(b.global_position, to.normalized())
			if float(st["u"]) > 0.0:
				st["u"] = float(st["u"]) - 1.0 / 30.0
				want = st["d"]
			elif b.get_real_velocity().length() < 0.6:
				st["t"] = float(st["t"]) + 1.0 / 30.0
				if float(st["t"]) > 0.5:
					st["t"] = 0.0
					st["d"] = map.unstick(b.global_position, want)
					st["u"] = 0.45 if st["d"] != Vector3.ZERO else 0.0
			else:
				st["t"] = 0.0
			stuck[b] = st
			b.velocity = want * 4.0
			b.move_and_slide()
			b.position.y = 0.0
		await get_tree().physics_frame
	print("    physics agents: %d/%d reached the target in %d s" % [arrived.size(), agents.size(), _agent_secs])
	for b in agents:
		if not arrived.has(b):
			var c := map._cell_of(b.global_position)
			print("      stuck at %s from %s (%.0f m away, flow dist %d, blocked %d)" % [b.global_position.snapped(Vector3.ONE * 0.1), (b.get_meta(&"start") as Vector3).snapped(Vector3.ONE * 0.1), b.global_position.distance_to(target), map._dist[c.y * map._gw + c.x], map._blocked[c.y * map._gw + c.x]])
	if arrived.size() < agents.size() * 0.8:
		_fail(String(map.map_id), "too many agents got stuck (%d/%d arrived)" % [arrived.size(), agents.size()])
	for b in agents:
		b.queue_free()


func _reachable(map: GameMap, from: Vector3) -> Dictionary:
	var out := {}
	var s := map._cell_of(from)
	if not map._in_grid(s):
		return out
	var q: Array[int] = [s.y * map._gw + s.x]
	out[q[0]] = true
	var head := 0
	while head < q.size():
		var i := q[head]
		head += 1
		var x := i % map._gw
		@warning_ignore("integer_division")
		var y := i / map._gw
		for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := Vector2i(x, y) + o
			if not map._in_grid(n):
				continue
			var ni: int = n.y * map._gw + n.x
			if out.has(ni) or map._blocked[ni] != 0:
				continue
			out[ni] = true
			q.append(ni)
	return out


func _near_reachable(map: GameMap, reach: Dictionary, p: Vector3, r: float) -> bool:
	var c := map._cell_of(p)
	var k := ceili(r / map.nav_cell)
	for dy in range(-k, k + 1):
		for dx in range(-k, k + 1):
			var n := c + Vector2i(dx, dy)
			if map._in_grid(n) and reach.has(n.y * map._gw + n.x):
				return true
	return false


## --png=<dir>: nav grid as an image (dark = blocked, grey = open, dim red = open but unreachable)
## with markers: white = player spawn, yellow = landmarks, cyan = objectives, red = enemy spawns.
func _write_png(map: GameMap, reach: Dictionary, path: String) -> void:
	const S := 4
	var img := Image.create(map._gw * S, map._gh * S, false, Image.FORMAT_RGB8)
	for y in map._gh:
		for x in map._gw:
			var i := y * map._gw + x
			var col := Color(0.12, 0.1, 0.1)
			if map._blocked[i] == 0:
				col = Color(0.55, 0.55, 0.5) if reach.has(i) else Color(0.5, 0.2, 0.2)
			img.fill_rect(Rect2i(x * S, y * S, S, S), col)
	var dot := func(p: Vector3, c: Color, r: int) -> void:
		var cell := map._cell_of(p)
		img.fill_rect(Rect2i(cell.x * S - r, cell.y * S - r, r * 2 + S, r * 2 + S), c)
	for mk in map.get_objective_points():
		dot.call(mk.global_position, Color.CYAN, 3)
	for mk in map.get_enemy_spawn_points():
		dot.call(mk.global_position, Color.RED, 3)
	for mk in map.get_landmarks():
		dot.call(mk.global_position, Color.YELLOW, 5)
	dot.call(map.get_player_spawn(), Color.WHITE, 6)
	img.save_png(path)
	print("    wrote %s" % path)


func _count(n: Node, cls: String) -> int:
	var c := 1 if n.get_class() == cls else 0
	for ch in n.get_children():
		c += _count(ch, cls)
	return c


func _fail(id: String, msg: String) -> void:
	_failed = true
	push_error("[%s] %s" % [id, msg])
	print("    FAIL: %s" % msg)


## --probe=x,z (with --map and --variants=1): prints the nav grid / flow distances around a point.
func _probe(map: GameMap) -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--probe="):
			continue
		var xz := a.substr(8).split(",")
		var at := Vector3(float(xz[0]), 0, float(xz[1]))
		map._update_flow(map._cell_of(map.get_player_spawn()))
		map._flow_cell = map._cell_of(map.get_player_spawn())
		var c := map._cell_of(at)
		for dy in range(-5, 6):
			var line := ""
			for dx in range(-5, 6):
				var n := c + Vector2i(dx, dy)
				var i := n.y * map._gw + n.x
				line += ("  ##" if map._blocked[i] else "%4d" % map._dist[i]) + ("*" if dx == 0 and dy == 0 else " ")
			print(line)
		var to := (map.get_player_spawn() - at).normalized()
		print("steer ", map.steer(at, to), " direct ", to, " unstick ", map.unstick(at, to))
		for b in map._blockers:
			if map._point_in_blocker(Vector2(at.x, at.z), b, 2.0):
				print("  near blocker ", b)


## --trace=x,z: one physics agent from that point toward the player spawn, positions every 0.5 s.
func _trace(map: GameMap) -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--trace="):
			continue
		var xz := a.substr(8).split(",")
		var target := map.get_player_spawn()
		map._flow_cell = map._cell_of(target)
		map._update_flow(map._flow_cell)
		var b := CharacterBody3D.new()
		b.collision_layer = 0
		b.collision_mask = 1
		b.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
		var cs := CollisionShape3D.new()
		var sh := CapsuleShape3D.new()
		sh.radius = 0.4
		sh.height = 1.6
		cs.shape = sh
		cs.position.y = 0.8
		b.add_child(cs)
		b.position = Vector3(float(xz[0]), 0, float(xz[1]))
		add_child(b)
		for s in 300:
			var to := target - b.global_position
			to.y = 0.0
			var d := map.steer(b.global_position, to.normalized())
			b.velocity = d * 4.0
			b.move_and_slide()
			if s % 15 == 0:
				print("  t=%.1f pos %s steer %s real %s" % [s / 30.0, b.global_position.snapped(Vector3.ONE * 0.1), d.snapped(Vector3.ONE * 0.01), b.get_real_velocity().snapped(Vector3.ONE * 0.1)])
			await get_tree().physics_frame
		b.queue_free()
