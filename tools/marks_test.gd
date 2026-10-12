extends Node
## Test harness for GroundMarks (res://tools/marks_test.tscn): the real run with a GroundMarks node.
##   godot --path . res://tools/marks_test.tscn -- --autopilot --shot=out.png --shot-time=45
## Extra user args:
##   --marks-demo   stamp a showcase of every mark type around the player shortly after start
##   --marks-perf   print FPS / frame time / live mark count every 5 s

@onready var marks: GroundMarks = $Main/GroundMarks


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--marks-perf" in args:
		var t := Timer.new()
		t.wait_time = 5.0
		t.autostart = true
		t.timeout.connect(func() -> void:
			print("MARKS t=%.0f fps=%d frame=%.2fms kills=%d" % [Game.elapsed,
				Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				Game.kills]))
		add_child(t)
	if "--marks-notaa" in args:
		await get_tree().process_frame
		get_viewport().use_taa = false
		get_viewport().scaling_3d_scale = 1.0
		get_viewport().msaa_3d = Viewport.MSAA_2X
		print("MARKS taa off")
	if "--marks-stress" in args:
		_stress()
	if "--marks-demo" in args:
		await get_tree().create_timer(1.0, false).timeout
		_demo()


## Fakes a heavy fight through the real Game signals: ~10 kills/s around the player, an elite
## every 8 s, a boss death at 20 s, and steady contact damage.
func _stress() -> void:
	var kinds: Array[Resource] = []
	for id in ["choir_wisp", "seraph_sentinel", "ophanim", "thurible_priest", "dawn_lancer"]:
		kinds.append(load("res://data/enemies/%s.tres" % id))
	var elite: Resource = load("res://data/enemies/archon.tres")
	await get_tree().process_frame
	print("MARKS vp taa=%s scale=%.2f msaa=%d" % [get_viewport().use_taa, get_viewport().scaling_3d_scale,
		get_viewport().msaa_3d])
	if Game.player and "xp_gain" in Game.player:
		Game.player.xp_gain = 0.0  # no level-up menu pausing the screenshot
	var t := 0.0
	var next_elite := 4.0
	var boss_done := false
	while is_inside_tree():
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		var c := Game.player.global_position if Game.player else Vector3.ZERO
		if randf() < 10.0 * dt:
			var a := randf() * TAU
			Game.enemy_died.emit(c + Vector3(cos(a), 0, sin(a)) * randf_range(2.0, 11.0), kinds.pick_random())
		if t > next_elite:
			next_elite += 8.0
			Game.enemy_died.emit(c + Vector3(randf_range(-7, 7), 0, randf_range(-5, 5)), elite)
		if t > 20.0 and not boss_done:
			boss_done = true
			Game.boss_died.emit(c + Vector3(0, 0, -4))
		Game.player_hit.emit(12.0 * dt)


func _demo() -> void:
	var c := Game.player.global_position if Game.player else Vector3.ZERO
	marks.add_crater(c + Vector3(-6, 0, -1), 6.2, 1.5)
	marks.add_crater(c + Vector3(7, 0, -3), 9.0, 2.2, true)
	for i in 6:
		var p := c + Vector3(-7.0 + i * 2.6, 0, 4.0)
		marks.add_mark(GroundMarks.Cell.HOLY_BURN if i % 3 else GroundMarks.Cell.SIGIL, p, 2.2, 1.1)
		if i % 2 == 0:
			marks.add_mark(GroundMarks.Cell.FEATHERS, p + Vector3(0.3, 0, 0.2), 2.0, 0.35,
				GroundMarks.PALE_GOLD)
	for i in 4:
		marks.add_mark(GroundMarks.Cell.SCORCH, c + Vector3(-3.0 + i * 2.0, 0, 7.0), 1.4, 0.9)
	for cell in [GroundMarks.Cell.DROPS, GroundMarks.Cell.SPLATTER, GroundMarks.Cell.SMEAR]:
		marks.add_mark(cell, c + Vector3(randf_range(-1.5, 1.5), 0, randf_range(1.0, 2.0)), 0.9, 0.3,
			GroundMarks.BLOOD_GLOW)
