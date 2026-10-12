extends Node
## Dev tool for the Atmosphere autoload (added by it when one of these args is present):
##
## Screenshot tour of every preset (or a list), one PNG each, then quit:
##   godot --path . res://tools/atmo_test.tscn -- --atmo-tour=C:/tmp/shots
##   ... --atmo-tour-list=basecamp_hell,storm_spire   only these presets
##   ... --atmo-tour-boss       also <name>_boss.png with the boss overlays on (+ a strike)
##   ... --atmo-tour-run        also <name>_storm.png (run escalation 1 + a surge) and <name>_dawn.png
##   ... --atmo-tour-quality=0  Settings graphics preset 0..3 (Low..Ultra; not saved)
##
## Frame-time benchmark: "bare" (no preset yet) then each preset, appending one line per
## measurement to the file (CPU frame ms from wall clock, GPU ms from the viewport's measured time):
##   godot --path . res://tools/atmo_test.tscn -- --atmo-bench=C:/tmp/bench.txt --atmo-tour-quality=2
## tools/perf/atmo_bench.sh runs it for every quality tier.

const SETTLE := 5.0
const FIRST_WAIT := 4.0
const BENCH_SETTLE := 3.0
const BENCH_SECONDS := 4.0

var out_dir := ""
var bench_file := ""
var names := PackedStringArray()
var boss := false
var run := false
var quality := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--atmo-tour="):
			out_dir = arg.substr(12)
		elif arg.begins_with("--atmo-bench="):
			bench_file = arg.substr(13)
		elif arg.begins_with("--atmo-tour-list="):
			names = arg.substr(17).split(",", false)
		elif arg == "--atmo-tour-boss":
			boss = true
		elif arg == "--atmo-tour-run":
			run = true
		elif arg.begins_with("--atmo-tour-quality="):
			quality = arg.substr(20).to_int()
			Settings.apply_preset(quality)
	if names.is_empty():
		names = Atmosphere.get_preset_names()
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	if bench_file != "":
		await _bench()
	else:
		await _tour()
	get_tree().quit()


func _tour() -> void:
	var tree := get_tree()
	await _wait(FIRST_WAIT)
	for n in names:
		tree.paused = false
		Atmosphere.apply_preset(n)
		await _wait(SETTLE)
		_shot(n)
		if boss:
			Atmosphere.push_overlay(&"boss", "boss", 0.0)
			Atmosphere.push_overlay(&"boss_enraged", "boss_enraged", 0.0)
			Atmosphere.strike_lightning(Vector3.INF, 0.1)
			await _wait(0.12)
			_shot(n + "_boss")
			Atmosphere.pop_overlay(&"boss_enraged", 0.0)
			Atmosphere.pop_overlay(&"boss", 0.0)
		if run:
			var rw: Node = Atmosphere.get_node(^"RunWeather")
			rw.set(&"escalation", 1.0)
			rw.call(&"apply_escalation", 0.0)
			Atmosphere.push_overlay(&"surge", "surge", 0.0)
			await _wait(SETTLE)
			_shot(n + "_storm")
			Atmosphere.pop_overlay(&"surge", 0.0)
			Atmosphere.push_overlay(&"final_dawn", "final_dawn", 0.0)
			await _wait(SETTLE)
			_shot(n + "_dawn")
			for id: StringName in [&"final_dawn", &"run_storm", &"run_storm_local", &"run_calm"]:
				Atmosphere.pop_overlay(id, 0.0)


func _bench() -> void:
	# Uncapped, so the numbers are the real cost (not saved to settings.cfg).
	Settings.vsync = false
	Settings.max_fps = 0
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	await _wait(FIRST_WAIT)
	await _measure("bare", vp)
	for n in names:
		Atmosphere.apply_preset(n)
		await _wait(BENCH_SETTLE)
		await _measure(n, vp)


func _measure(label: String, vp: RID) -> void:
	var frames := 0
	var gpu := 0.0
	var cpu := 0.0
	var start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < int(BENCH_SECONDS * 1_000_000.0):
		await get_tree().process_frame
		frames += 1
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
	var wall_ms := float(Time.get_ticks_usec() - start) / 1000.0 / maxf(frames, 1)
	var line := "atmo_bench q=%d preset=%s frame_ms=%.2f gpu_ms=%.2f render_cpu_ms=%.2f fps=%.0f" % [
			Atmosphere.quality(), label, wall_ms, gpu / maxf(frames, 1), cpu / maxf(frames, 1),
			1000.0 / maxf(wall_ms, 0.001)]
	print(line)
	var f := FileAccess.open(bench_file, FileAccess.READ_WRITE if FileAccess.file_exists(bench_file) else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(line)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


func _shot(n: String) -> void:
	var path := out_dir.path_join(n + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("atmo_tour: ", path)
