extends Node
## Perf (autoload): debug performance overlay, stress / benchmark tooling and a few shared
## hot-path helpers. Owner: performance role (docs/team/performance.md).
##
## Debug keys (debug builds, or any build started with `-- --perf`):
##   F9         toggle the overlay (FPS, frame time, draw calls, nodes, enemies, ...)
##   F10        stress: spawn STRESS_COUNT (300) enemies around the player
##   Shift+F10  kill every enemy (no XP / FX, instant)
##
## Command line (after "--"):
##   --perf                 overlay on at start (works in release builds too)
##   --bench[=seconds]      benchmark: godmode, every weapon at max level, keeps --stress enemies
##                          alive, prints a "[PERF] ..." summary (and --bench-out=file) and quits.
##   --stress=N             enemy count for --bench (default 300)
##   --bench-out=path       also write the summary line to this file (appended)
##
##   godot --path . res://scenes/main.tscn -- --autopilot --bench=20 --stress=300
##   (--autopilot makes level-ups and story dialogue resolve themselves; tools/perf/bench.sh runs it)
##
## Hot-path helpers (use these instead of get_nodes_in_group in per-frame code):
##   Perf.enemies() -> Array[Node]     every node in group "enemies", fetched at most once per
##                                     frame / physics step and shared by all callers. Read-only;
##                                     entries may be queued for deletion (check is_dying etc.).
##   Perf.budget(&"key", per_frame)    true while fewer than `per_frame` calls with that key happened
##                                     this frame: cheap per-frame caps for FX / sounds / spawns.
##   Perf.track(node, &"key", max)     concurrency cap: false if `max` tracked nodes with that key
##                                     are alive, else counts `node` until it leaves the tree.

## Enemies spawned by F10 (and the default for --bench).
const STRESS_COUNT := 300
## Overlay text refresh rate (rebuilding strings every frame would itself cost time).
const OVERLAY_HZ := 4.0
## Frame-time samples kept for the overlay graph / stats (~2 s at 60 fps).
const SAMPLES := 120
## Frames longer than this count as hitches.
const HITCH_MS := 33.4

var overlay_visible := false
var enabled := false  # debug keys active (debug build or --perf)

var _layer: CanvasLayer
var _label: Label
var _graph: Control
var _refresh := 0.0
var _times := PackedFloat32Array()  # frame times in ms (ring buffer)
var _ti := 0
var _hitches := 0
var _last_tick := 0
## Accumulated usec spent in stress_spawn() (bench diagnostics).
var _spawn_usec := 0
var _spawned := 0
var _spawn_samples := PackedInt64Array()
var _ready_samples := PackedInt64Array()

# Shared enemy list cache.
var _enemy_cache: Array[Node] = []
var _enemy_key := -1
var _enemy_epoch := 0
var _icons_requested := false
var _props_warmed := false

# Per-frame budgets / concurrency counters.
var _budget_frame := -1
var _budgets := {}
var _alive := {}

# Benchmark state.
var _bench := false
var _bench_len := 20.0
var _bench_warm := 4.0
var _bench_t := 0.0
var _bench_count := STRESS_COUNT
var _bench_out := ""
var _bench_ft := PackedFloat32Array()
var _bench_acc := {}
var _bench_n := 0
var _bench_paused := 0
## QA perf gate: fail (exit 1) when the bench's average frame time exceeds this (ms). 0 = off.
var _bench_gate := 0.0
## Experiments toggled per enemy in --bench (A/B testing what costs what).
var _bench_exp := PackedStringArray()
## Restrict stress spawns to these enemy ids (bench experiments).
var _bench_only := PackedStringArray()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -1000  # sample before gameplay nodes
	_times.resize(SAMPLES)
	enabled = OS.is_debug_build()
	for arg in OS.get_cmdline_user_args():
		if arg == "--perf":
			enabled = true
			set_overlay(true)
		elif arg == "--bench" or arg.begins_with("--bench="):
			_bench = true
			enabled = true
			if arg.begins_with("--bench="):
				_bench_len = maxf(arg.substr(8).to_float(), 2.0)
		elif arg.begins_with("--stress="):
			_bench_count = maxi(arg.substr(9).to_int(), 0)
		elif arg.begins_with("--bench-exp="):
			_bench_exp = arg.substr(12).split(",")
		elif arg.begins_with("--bench-gate="):
			_bench_gate = arg.substr(13).to_float()
		elif arg.begins_with("--bench-out="):
			_bench_out = arg.substr(12)
	get_tree().node_added.connect(_on_node_added)
	# The first scene enters the tree before autoloads connect node_added.
	(func() -> void:
		var cs := get_tree().current_scene
		if cs and WARMUP_SCENES.has(cs.scene_file_path):
			_maybe_warmup(cs)).call_deferred()
	if _bench:
		Game.godmode = true
		set_overlay(true)
		if not _bench_exp.is_empty():
			get_tree().node_added.connect(_bench_experiment)
		if "nointerp" in _bench_exp:
			get_tree().physics_interpolation = false
		if "noglbskin" in _bench_exp:
			GlbSkin.enabled = false
		if "noskinbake" in _bench_exp:
			ProcModel.skin_bake_enabled = false
		if "allskin" in _bench_exp:
			_bench_only = PackedStringArray(["cherub", "villager_torch", "villager_pitchfork", "ophan", "holy_knight"])
		if "nolodhide" in _bench_exp:
			EnemyModel.lod_hide = false
		if "nocrowd" in _bench_exp:
			Crowd.enabled = false


func _exit_tree() -> void:
	# Drop the static caches / pools added for perf so quitting doesn't report leaked objects.
	GlbModel.clear_cache()
	DamageNumber._pool.clear()
	EnemyModel._corpse_pool.clear()
	InfernalFx._burst_pool.clear()
	Crowd.clear()
	_enemy_cache = []


# ---------------------------------------------------------------- shared helpers

## All nodes in group "enemies", cached per frame / physics step (one array for every caller).
func enemies() -> Array[Node]:
	# Deletions are flushed after each physics step and after the idle frame, so the cache key
	# combines both counters and whether we are inside a physics step.
	var key := Engine.get_process_frames() * 4096 + (Engine.get_physics_frames() % 2048) * 2 \
			+ int(Engine.is_in_physics_frame())
	# _enemy_epoch also changes whenever an enemy enters or leaves the tree (deferred calls can run
	# after the delete flush within the same step; a freed entry must never be handed out).
	key = key * 64 + (_enemy_epoch % 64)
	if key != _enemy_key:
		_enemy_key = key
		_enemy_cache = get_tree().get_nodes_in_group(&"enemies")
	return _enemy_cache


## Scenes that start the shader / pipeline warm-up in the background (menus and the hub, where
## a 192x108 offscreen render for a few seconds costs nothing noticeable). Warmup skips anything
## already warmed this session, so re-entering is free. --bench / --shot runs skip it.
const WARMUP_SCENES := ["res://scenes/menu/demon_select.tscn", "res://scenes/basecamp/basecamp.tscn"]


func _maybe_warmup(scene: Node) -> void:
	if _bench or not is_instance_valid(scene) or not scene.is_inside_tree():
		return
	if DisplayServer.get_name() == "headless":
		return
	Warmup.run(scene)
	_prewarm_icons()
	_prewarm_props()


## Builds the merged variants of every Blender prop (Props.variants, cached for the session) one
## per frame: the first use of a prop kind cost 6-46 ms (GLB load + merge), which used to land in
## the middle of a run when the sanctum decor streamed in a new kind.
func _prewarm_props() -> void:
	if _props_warmed or not DirAccess.dir_exists_absolute(Props.MODEL_DIR):
		return
	_props_warmed = true
	for f in DirAccess.get_files_at(Props.MODEL_DIR):
		var file := f.trim_suffix(".import").trim_suffix(".remap")
		if file.ends_with(".glb"):
			await get_tree().process_frame
			Props.variants(StringName(file.get_basename()))


## Same, all at once (call during a load, e.g. when a scene that streams props starts).
## Instant when the menus already warmed them.
func prewarm_props_now() -> void:
	if not DirAccess.dir_exists_absolute(Props.MODEL_DIR):
		return
	for f in DirAccess.get_files_at(Props.MODEL_DIR):
		var file := f.trim_suffix(".import").trim_suffix(".remap")
		if file.ends_with(".glb"):
			Props.variants(StringName(file.get_basename()))  # cached kinds return at once


## Background-loads every item / ability icon (the level-up and shop cards loaded them lazily,
## a few ms each, the first time a card showed them).
func _prewarm_icons() -> void:
	if _icons_requested or not DirAccess.dir_exists_absolute(Icons.DIR):
		return
	_icons_requested = true
	for dir: String in [Icons.DIR] + Array(DirAccess.get_directories_at(Icons.DIR)).map(
			func(d: String) -> String: return Icons.DIR + d + "/"):
		for f in DirAccess.get_files_at(dir):
			var file := f.trim_suffix(".import").trim_suffix(".remap")
			if file.ends_with(".png") or file.ends_with(".svg"):
				ResourceLoader.load_threaded_request(dir + file)


func _on_node_added(node: Node) -> void:
	if node.get_parent() == get_tree().root and WARMUP_SCENES.has(node.scene_file_path):
		_maybe_warmup.call_deferred(node)
	# Cheap filter: this runs for every node that enters the tree.
	if node is Enemy or (node is CharacterBody3D and node.is_in_group(&"enemies")):
		_enemy_epoch += 1
		node.tree_exiting.connect(_bump_enemy_epoch, CONNECT_ONE_SHOT)


# Enemy shadows on Low / Medium: owned by visuals (AtmoEvents._update_enemy_shadows, atmosphere
# quality < 2 = off), so Perf does not toggle cast_shadow itself (two systems would fight).


## Changes whenever an enemy enters or leaves the tree (cache invalidation for Crowd etc.).
func enemy_epoch() -> int:
	return _enemy_epoch


func _bump_enemy_epoch() -> void:
	_enemy_epoch += 1


## Per-frame budget: returns true for the first `per_frame` calls with `key` this frame.
func budget(key: StringName, per_frame: int) -> bool:
	var f := Engine.get_process_frames()
	if f != _budget_frame:
		_budget_frame = f
		_budgets.clear()
	var n: int = _budgets.get(key, 0)
	if n >= per_frame:
		return false
	_budgets[key] = n + 1
	return true


## Concurrency cap: if fewer than `max_alive` nodes tracked under `key` are alive, starts tracking
## `node` (until it exits the tree) and returns true. Otherwise returns false (skip the effect).
func track(node: Node, key: StringName, max_alive: int) -> bool:
	var n: int = _alive.get(key, 0)
	if n >= max_alive:
		return false
	_alive[key] = n + 1
	node.tree_exited.connect(func() -> void: _alive[key] = maxi(int(_alive.get(key, 1)) - 1, 0),
			CONNECT_ONE_SHOT)
	return true


## Number of live tracked nodes under `key` (see track()).
func alive_count(key: StringName) -> int:
	return _alive.get(key, 0)


# ---------------------------------------------------------------- stress tools

## Spawns `count` enemies around the player using the run's EnemySpawner (random active types).
func stress_spawn(count: int = STRESS_COUNT) -> int:
	var spawner := _find_spawner()
	if spawner == null or Game.player == null:
		push_warning("Perf.stress_spawn: no EnemySpawner / player in the current scene")
		return 0
	var pool: Array[EnemyData] = []
	for id in _bench_only:
		var d := load("res://data/enemies/%s.tres" % id) as EnemyData
		if d:
			pool.append(d)
	if pool.is_empty():
		for r in spawner.rules:
			if r and r.enemy and not pool.has(r.enemy):
				pool.append(r.enemy)
	if pool.is_empty():
		return 0
	var t0 := Time.get_ticks_usec()
	for i in count:
		var t1 := Time.get_ticks_usec()
		spawner.spawn(pool[i % pool.size()])
		_spawn_samples.append(Time.get_ticks_usec() - t1)
	_spawn_usec += Time.get_ticks_usec() - t0
	_spawned += count
	return count


## Frees every enemy at once (no deaths: no XP, FX or kill count).
func kill_all() -> void:
	for e in get_tree().get_nodes_in_group(&"enemies"):
		if not e.is_in_group(&"boss"):
			e.queue_free()


## Node counts by class under `root` (default: Game.world), biggest first. For finding bloat:
##   print(Perf.dump_world())
func dump_world(root: Node = null, top: int = 16) -> String:
	if root == null:
		root = Game.world
	if root == null or not is_instance_valid(root):
		return "(no world)"
	var counts := {}
	var stack: Array[Node] = [root]
	var total := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		total += 1
		var cls := n.get_class()
		counts[cls] = int(counts.get(cls, 0)) + 1
		stack.append_array(n.get_children())
	var keys := counts.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return counts[a] > counts[b])
	var parts := PackedStringArray()
	for i in mini(top, keys.size()):
		parts.append("%s=%d" % [keys[i], counts[keys[i]]])
	return "[PERF] world nodes=%d  %s" % [total, "  ".join(parts)]


func _find_spawner() -> EnemySpawner:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var s := scene.get_node_or_null(^"EnemySpawner") as EnemySpawner
	if s:
		return s
	for c in scene.find_children("*", "Node", true, false):
		if c is EnemySpawner:
			return c
	return null


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_F9:
			set_overlay(not overlay_visible)
		KEY_F10:
			if key.shift_pressed:
				kill_all()
			else:
				stress_spawn()
		_:
			return
	get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- overlay

## Render-thread CPU / GPU time of the main viewport (RenderingServer measurement, enabled with
## the overlay or a bench). CPU = culling, sorting, draw-call recording: what node counts cost.
func _render_cpu_ms() -> float:
	_measure_render()
	return RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()) 			+ RenderingServer.get_frame_setup_time_cpu()


func _render_gpu_ms() -> float:
	_measure_render()
	return RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())


var _measuring := false

func _measure_render() -> void:
	if not _measuring:
		_measuring = true
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func set_overlay(on: bool) -> void:
	overlay_visible = on
	if on and _layer == null:
		_build_overlay()
	if _layer:
		_layer.visible = on
	_refresh = 0.0


func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 120
	_layer.name = &"PerfOverlay"
	add_child(_layer)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.62)
	sb.set_content_margin_all(6.0)
	sb.set_corner_radius_all(3)
	panel.add_theme_stylebox_override(&"panel", sb)
	panel.position = Vector2(8, 140)  # below the HUD health bar
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	_label = Label.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "DejaVu Sans Mono", "monospace"])
	_label.add_theme_font_override(&"font", font)
	_label.add_theme_font_size_override(&"font_size", 13)
	_label.add_theme_color_override(&"font_color", Color(0.85, 1.0, 0.85))
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 3)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_label)
	_graph = Control.new()
	_graph.custom_minimum_size = Vector2(SAMPLES * 2, 40)
	_graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_graph.draw.connect(_draw_graph)
	box.add_child(_graph)


## Frame-time bars: green < 16.7 ms, yellow < 33 ms, red above. Line at 16.7 ms.
func _draw_graph() -> void:
	var h := _graph.size.y
	var scale := h / 50.0  # 50 ms = full height
	for i in SAMPLES:
		var ms := _times[(_ti + i) % SAMPLES]
		var col := Color(0.3, 0.9, 0.35) if ms < 16.8 else (Color(1.0, 0.85, 0.2) if ms < HITCH_MS else Color(1.0, 0.25, 0.2))
		var bh := minf(ms * scale, h)
		_graph.draw_rect(Rect2(i * 2, h - bh, 2, bh), col)
	_graph.draw_line(Vector2(0, h - 16.7 * scale), Vector2(SAMPLES * 2, h - 16.7 * scale), Color(1, 1, 1, 0.35))


func _process(delta: float) -> void:
	# Wall-clock frame time (delta is scaled by hitstop / time_scale and smoothed).
	var now := Time.get_ticks_usec()
	var ms := 0.0 if _last_tick == 0 else float(now - _last_tick) / 1000.0
	_last_tick = now
	_times[_ti] = ms
	_ti = (_ti + 1) % SAMPLES
	if ms > HITCH_MS:
		_hitches += 1
	if _bench:
		_bench_step(delta, ms)
		# Watchdog: a bench that never gets going (no player, stuck menu) must still exit.
		if Time.get_ticks_msec() > int((_bench_warm + _bench_len + 60.0) * 1000.0) + 30000:
			print("[PERF] TIMEOUT: bench did not finish (t=%.1f s of bench time)" % _bench_t)
			get_tree().quit(3)
	if not overlay_visible or _label == null:
		return
	_graph.queue_redraw()
	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = 1.0 / OVERLAY_HZ
	_label.text = _overlay_text()


func _overlay_text() -> String:
	var avg := 0.0
	var worst := 0.0
	for t in _times:
		avg += t
		worst = maxf(worst, t)
	avg /= SAMPLES
	var tree := get_tree()
	var lines := PackedStringArray()
	lines.append("FPS %d   frame %.2f ms avg  %.1f max   hitches %d" % [
		Engine.get_frames_per_second(), avg, worst, _hitches])
	lines.append("cpu: process %.2f ms  physics %.2f ms  nav %.2f ms" % [
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0])
	lines.append("render: cpu %.2f ms  gpu %.2f ms  (main viewport)" % [_render_cpu_ms(), _render_gpu_ms()])
	lines.append("draw calls %d   objects %d   prims %dk" % [
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0)])
	lines.append("nodes %d   orphans %d   world children %d" % [
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		Game.world.get_child_count() if is_instance_valid(Game.world) else 0])
	lines.append("enemies %d   gems %d   corpses %d   dmg nums %d" % [
		tree.get_node_count_in_group(&"enemies"), tree.get_node_count_in_group(&"gems"),
		EnemyModel.corpses_alive(), DamageNumber.active_count()])
	lines.append("physics: active %d  pairs %d   mem %.0f MB  vram %.0f MB" % [
		Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	if enabled:
		lines.append("F9 overlay  F10 +%d enemies  Shift+F10 clear" % STRESS_COUNT)
	return "\n".join(lines)


# ---------------------------------------------------------------- benchmark

const _BENCH_MONITORS := {
	"process_ms": Performance.TIME_PROCESS,
	"physics_ms": Performance.TIME_PHYSICS_PROCESS,
	"draw_calls": Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME,
	"objects": Performance.RENDER_TOTAL_OBJECTS_IN_FRAME,
	"nodes": Performance.OBJECT_NODE_COUNT,
}


func _bench_step(delta: float, ms: float) -> void:
	var player := Game.player
	if player == null or not is_instance_valid(player):
		return
	if _bench_t == 0.0:
		_bench_setup(player)
	_bench_t += delta
	# Keep the crowd topped up (weapons kill them continuously: deaths are part of the load).
	var have := get_tree().get_node_count_in_group(&"enemies")
	if have < _bench_count:
		var spawner := _find_spawner()
		if spawner:
			var n := mini(_bench_count - have, 40)  # spread the refill over frames
			stress_spawn(n)
	if _bench_t < _bench_warm:
		return
	if get_tree().paused:
		# A menu (level-up, dialogue) froze gameplay: such frames would flatter the numbers.
		# Count them and unpause (pass --autopilot so menus pick / skip themselves).
		_bench_paused += 1
		get_tree().paused = false
	_bench_ft.append(ms)
	_bench_n += 1
	for k: String in _BENCH_MONITORS:
		var v := Performance.get_monitor(_BENCH_MONITORS[k])
		if k.ends_with("_ms"):
			v *= 1000.0
		_bench_acc[k] = float(_bench_acc.get(k, 0.0)) + v
	_bench_acc["enemies"] = float(_bench_acc.get("enemies", 0.0)) + have
	_bench_acc["render_cpu_ms"] = float(_bench_acc.get("render_cpu_ms", 0.0)) + _render_cpu_ms()
	_bench_acc["render_gpu_ms"] = float(_bench_acc.get("render_gpu_ms", 0.0)) + _render_gpu_ms()
	if _bench_t >= _bench_warm + _bench_len:
		_bench_finish()


func _bench_experiment(node: Node) -> void:
	if not node is Enemy:
		return
	var e := node as Enemy
	if "spawns" in _bench_exp:
		var t_added := Time.get_ticks_usec()
		e.ready.connect(func() -> void: _ready_samples.append(Time.get_ticks_usec() - t_added), CONNECT_ONE_SHOT)
	if "nocollide" in _bench_exp:
		e.collision_mask = 1
	if "noprocess" in _bench_exp:
		e.ready.connect(func() -> void: e.set_physics_process(false), CONNECT_ONE_SHOT)
	if "hidemodel" in _bench_exp:
		e.ready.connect(func() -> void: e.model.visible = false, CONNECT_ONE_SHOT)
	if "noanim" in _bench_exp:
		e.ready.connect(func() -> void:
			if e.model.glb and e.model.glb.anim_player:
				e.model.glb.anim_player.process_mode = Node.PROCESS_MODE_DISABLED, CONNECT_ONE_SHOT)
	if "enemynointerp" in _bench_exp:
		e.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if "modelnointerp" in _bench_exp:
		e.ready.connect(func() -> void: e.model.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF, CONNECT_ONE_SHOT)
	if "fewmeshes" in _bench_exp:
		# Proxy for a skinned bake: keep only 2 render instances per model visible.
		e.ready.connect(func() -> void:
			var n := 0
			for g in e.model.find_children("*", "GeometryInstance3D", true, false):
				n += 1
				if n > 2:
					(g as GeometryInstance3D).visible = false, CONNECT_ONE_SHOT)
	if "noshadow" in _bench_exp:
		e.ready.connect(func() -> void: Art.no_shadows(e.model), CONNECT_ONE_SHOT)


func _bench_setup(player: Player) -> void:
	# Uncapped frame rate so the numbers mean something.
	Engine.max_fps = 0
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if "noweapons" in _bench_exp:
		for w in player.weapons:
			w.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		for scene in player.weapon_pool:
			if not player.has_weapon(scene) and player.weapons.size() < player.max_weapons:
				player.add_weapon(scene)
		for w in player.weapons:
			while not w.is_max_level():
				w.level_up()
	_bench_t = 0.0001


func _bench_finish() -> void:
	_bench = false
	var sorted := _bench_ft.duplicate()
	sorted.sort()
	var n := sorted.size()
	var total := 0.0
	for t in sorted:
		total += t
	var avg := total / maxf(n, 1)
	var p99: float = sorted[clampi(int(n * 0.99), 0, n - 1)] if n > 0 else 0.0
	var worst: float = sorted[n - 1] if n > 0 else 0.0
	var line := "[PERF] frames=%d avg_ms=%.2f fps=%.1f p99_ms=%.2f max_ms=%.2f" % [n, avg, 1000.0 / maxf(avg, 0.001), p99, worst]
	for k: String in _bench_acc:
		line += " %s=%.2f" % [k, float(_bench_acc[k]) / maxf(_bench_n, 1)]
	line += " kills=%d spawn_us_each=%.0f paused_frames=%d" % [Game.kills, float(_spawn_usec) / maxf(_spawned, 1), _bench_paused]
	print(line)
	print(dump_world())
	var decor := get_tree().current_scene.get_node_or_null(^"Decor") if get_tree().current_scene else null
	if decor and decor.get(&"slice_max_us") != null:
		print("[PERF] decor longest build slice: %.2f ms" % (float(decor.get(&"slice_max_us")) / 1000.0))
	if "spawns" in _bench_exp:
		var ss := _spawn_samples.duplicate()
		print("[PERF] first spawns us: ", ss.slice(0, 24))
		print("[PERF] first enter->ready us: ", _ready_samples.slice(0, 24))
		ss.sort()
		print("[PERF] spawn us p50=%d p90=%d max=%d" % [ss[ss.size() >> 1], ss[int(ss.size() * 0.9)], ss[ss.size() - 1]])
	if "listeners" in _bench_exp:
		for c in get_tree().node_added.get_connections():
			print("[PERF] node_added -> ", c["callable"])
		if Game.world:
			for c in Game.world.child_entered_tree.get_connections():
				print("[PERF] world.child_entered_tree -> ", c["callable"])
	if _bench_out != "":
		var f := FileAccess.open(_bench_out, FileAccess.READ_WRITE if FileAccess.file_exists(_bench_out) else FileAccess.WRITE)
		if f:
			f.seek_end()
			f.store_line(line)
	if _bench_gate > 0.0:
		if avg > _bench_gate:
			print("[PERF] GATE FAIL: avg frame %.2f ms > budget %.2f ms (%d enemies). See docs/team/performance.md" % [avg, _bench_gate, _bench_count])
			get_tree().quit(1)
			return
		print("[PERF] GATE OK: avg frame %.2f ms <= budget %.2f ms" % [avg, _bench_gate])
	get_tree().quit()
