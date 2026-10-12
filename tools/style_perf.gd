extends Node
## Measures the GPU cost of the corruption (blight) shaders on a map: loads main.tscn (--map=<id>),
## removes the enemy spawner, then cycles Corruption.quality 2 -> 1 -> 0 (several rounds) and logs
## the average GPU frame time of each, with the whole screen blighted (ambient 1, worst case) and
## with only the player's trail (ambient 0, the normal run case). Run WINDOWED (vsync is turned off):
##   godot --path . res://tools/style_perf.tscn -- --map=sunlit_citadel
## Prints "style_perf: <case> q<quality> gpu=<ms> cpu=<ms>" lines and a summary, then quits.

const MAIN_SCENE := "res://scenes/main.tscn"
const SLOT := 3.0  # seconds per measurement
const WARMUP := 0.8  # seconds ignored after each switch
const ROUNDS := 3

var _steps: Array[Dictionary] = []
var _i := -1
var _t := 0.0
var _gpu := 0.0
var _cpu := 0.0
var _n := 0
var _results := {}  # "case q" -> Array[float] (gpu ms per slot)
var _vp: RID


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	add_child(load(MAIN_SCENE).instantiate())
	_vp = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	for r in ROUNDS:
		for amb in [1.0, 0.0]:
			for q in [2, 1, 0]:
				_steps.append({"amb": amb, "q": q})
	_t = -3.0  # let the map build and shaders compile first


func _process(delta: float) -> void:
	if get_tree().paused:
		get_tree().paused = false
	for s in get_tree().get_nodes_in_group(&"enemies"):
		s.queue_free()
	var sp := get_tree().current_scene.find_child("EnemySpawner", true, false)
	if sp:
		sp.queue_free()
	_t += delta
	if _i >= 0 and _t > WARMUP:
		_gpu += RenderingServer.viewport_get_measured_render_time_gpu(_vp)
		_cpu += RenderingServer.viewport_get_measured_render_time_cpu(_vp)
		_n += 1
	if _t >= SLOT or _i < 0 and _t >= 0.0:
		_finish_step()
		_i += 1
		if _i >= _steps.size():
			_summary()
			get_tree().quit()
			return
		var st: Dictionary = _steps[_i]
		Corruption.ambient = st["amb"]
		Corruption.quality = st["q"]
		_t = 0.0


func _finish_step() -> void:
	if _i < 0 or _n == 0:
		return
	var st: Dictionary = _steps[_i]
	var key := "%s q%d" % ["ambient" if st["amb"] > 0.0 else "trail", st["q"]]
	var gpu := _gpu / _n
	print("style_perf: %s gpu=%.3f ms cpu=%.3f ms (%d frames)" % [key, gpu, _cpu / _n, _n])
	if not _results.has(key):
		_results[key] = []
	(_results[key] as Array).append(gpu)
	_gpu = 0.0
	_cpu = 0.0
	_n = 0


func _summary() -> void:
	print("style_perf: summary (median GPU ms over %d rounds)" % ROUNDS)
	for key in _results:
		var a: Array = _results[key]
		a.sort()
		@warning_ignore("integer_division")
		print("  %-12s %.3f" % [key, a[a.size() / 2]])
