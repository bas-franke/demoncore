extends SceneTree
## QA full-flow smoke test (docs/team/qa.md):
##   <godot> --headless --fixed-fps 60 --path . --script res://tools/qa/flow_smoke.gd -- --autopilot [--secs=40] [--map=<id>]
## boot (main_scene) -> Basecamp Hell -> for each map: run on autopilot for --secs of game time
## -> RunState.end_run -> back to the hub. Checks the scene changes, that the right map loaded, the
## player exists and fought (kills > 0), and counts engine/script errors per phase through a Logger.
## --demons adds one short run per playable demon (visible mesh, kills) on the first/--map map.
## Prints "  ok"/"  FAIL" lines, a per-phase error table and "flow_smoke: PASS|FAIL"; exits 1 on FAIL.
## Duck-typed (a -s script compiles before the autoloads exist). Restores the user:// saves it touches.

const HUB := "res://scenes/basecamp/basecamp.tscn"
const RUN := "res://scenes/main.tscn"
const SAVES := ["user://meta_save.json", "user://progression.json", "user://story.json",
	"user://settings.cfg"]

var _fails: PackedStringArray = []
var _backup := {}  # path -> String
var _log: QALogger
var _secs := 40.0
var _only_map := ""
var _demons := false  # --demons: also one short run per data/demons/*.tres
var _isolated := false  # SaveProfile in use: the real saves are never touched, skip backup/restore


## Collects every error/warning the engine reports, tagged with the current phase.
class QALogger extends Logger:
	var phase := "boot"
	var errors := {}  # phase -> Array[String]
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var kind := "WARNING" if error_type == ERROR_TYPE_WARNING else "ERROR"
		var msg := rationale if rationale != "" else code
		var where := "%s:%d" % [file, line]
		if not _script_backtraces.is_empty() and _script_backtraces[0].get_frame_count() > 0:
			where = "%s:%d" % [_script_backtraces[0].get_frame_file(0), _script_backtraces[0].get_frame_line(0)]
		_mutex.lock()
		if not errors.has(phase):
			errors[phase] = []
		var s := "%s %s (%s @ %s)" % [kind, msg, function, where]
		if not (errors[phase] as Array).has(s):
			(errors[phase] as Array).append(s)
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			_secs = a.substr(7).to_float()
		elif a.begins_with("--map="):
			_only_map = a.substr(6)
		elif a == "--demons":
			_demons = true
	# Isolated saves (progression's SaveProfile; before the autoloads' _ready loads them).
	if ResourceLoader.exists("res://scripts/save_profile.gd"):
		load("res://scripts/save_profile.gd").call(&"use", "qa_flow")
		_isolated = true
	_log = QALogger.new()
	OS.add_logger(_log)
	_run.call_deferred()


func _run() -> void:
	for path: String in SAVES:
		if not _isolated and FileAccess.file_exists(path):
			_backup[path] = FileAccess.get_file_as_string(path)
	var game: Node = root.get_node(^"Game")
	var maps: Node = root.get_node(^"Maps")
	var rs: Node = root.get_node(^"RunState")
	_check(bool(game.get(&"autopilot")), "autopilot flag parsed (pass -- --autopilot)")
	if _only_map != "":
		await _frames(5)  # Meta restores the saved map choice deferred; --map must survive that
		_check(String(maps.get(&"selected_id")) == _only_map,
			"--map=%s dev arg selects the map (Maps.selected_id=%s)" % [_only_map, maps.get(&"selected_id")])

	# Boot: the project's main scene.
	var main_scene := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	_log.phase = "boot"
	_check(change_scene_to_file(main_scene) == OK, "boot scene %s loads" % main_scene)
	await _frames(60)
	_check(current_scene != null, "boot scene is current")

	# Hub.
	_log.phase = "basecamp"
	change_scene_to_file(HUB)
	await _frames(60)
	_check(_scene_is(HUB), "basecamp loads")

	var ids: PackedStringArray = maps.call(&"ids")
	_check(not ids.is_empty(), "Maps has registered maps (%s)" % ", ".join(ids))
	for id in ids:
		if _only_map != "" and id != _only_map:
			continue
		_log.phase = "run:" + id
		maps.call(&"start_run", StringName(id))
		await _frames(10)
		_check(_scene_is(RUN), "[%s] run scene loads" % id)
		var t0 := Time.get_ticks_msec()
		await _game_seconds(game, _secs)
		var cur: Node = maps.get(&"current_map")
		var cur_def: Dictionary = maps.get(&"current_def")
		_check(is_instance_valid(cur) and String(cur_def.get("id", "")) == id,
			"[%s] map is live (current_def.id=%s)" % [id, cur_def.get("id", "?")])
		var player: Node = game.get(&"player")
		_check(is_instance_valid(player), "[%s] player exists" % id)
		var kills: int = game.get(&"kills")
		var elapsed: float = game.get(&"elapsed")
		print("  info [%s] %.0fs game time in %.1fs wall, kills=%d, enemies=%d, nodes=%d" % [id, elapsed,
			(Time.get_ticks_msec() - t0) / 1000.0, kills, get_nodes_in_group(&"enemies").size(),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
		_check(kills > 0, "[%s] autopilot killed something (%d)" % [id, kills])
		_log.phase = "end:" + id
		var res: Dictionary = rs.call(&"end_run", false, &"slain")
		_check(not res.is_empty() and not bool(rs.get(&"active")), "[%s] run ends" % id)
		await _frames(150)  # end screen delay (1.4 s) + open
		if id == ids[0]:
			# "Try again" from the end screen: run -> run without the hub in between.
			_log.phase = "restart:" + id
			rs.call(&"restart_run")
			await _frames(10)
			await _game_seconds(game, 5.0)
			_check(_scene_is(RUN) and bool(rs.get(&"active")) and is_instance_valid(game.get(&"player")),
				"[%s] restart_run starts a fresh run" % id)
			rs.call(&"end_run", false, &"slain")
			await _frames(150)
		rs.call(&"return_to_basecamp")
		await _frames(60)
		_check(_scene_is(HUB), "[%s] back in basecamp" % id)

	if _demons:
		await _demon_runs(game, maps, rs, ids[0] if _only_map == "" else _only_map)

	_restore_saves()
	OS.remove_logger(_log)
	print("\n--- errors / warnings by phase ---")
	var total_err := 0
	for phase: String in _log.errors:
		var lines: Array = _log.errors[phase]
		print("[%s] %d unique" % [phase, lines.size()])
		for l: String in lines:
			print("    " + l)
			if l.begins_with("ERROR"):
				total_err += 1
	print("flow_smoke: unique errors=%d" % total_err)
	if _fails.is_empty():
		print("flow_smoke: PASS")
		quit(0)
	else:
		print("flow_smoke: FAIL\n  " + "\n  ".join(_fails))
		quit(1)


## One short run per playable demon: the player spawns with a visible mesh (no invisible demon when
## a .glb is missing, tools/qa/BUGS.md B1) and kills something.
func _demon_runs(game: Node, maps: Node, rs: Node, map_id: String) -> void:
	for f in DirAccess.get_files_at("res://data/demons/"):
		if not f.ends_with(".tres"):
			continue
		var id := f.get_basename()
		_log.phase = "demon:" + id
		game.set(&"selected_character", load("res://data/demons/" + f))
		maps.call(&"start_run", StringName(map_id))
		await _frames(10)
		await _game_seconds(game, _secs)
		var player: Node = game.get(&"player")
		var meshes := 0
		if is_instance_valid(player):
			for m in player.find_children("*", "MeshInstance3D", true, false):
				if (m as MeshInstance3D).mesh != null and (m as MeshInstance3D).is_visible_in_tree():
					meshes += 1
		_check(meshes > 0, "[demon %s] player has visible meshes (%d)" % [id, meshes])
		# Soft: the autopilot kites melee kits out of their own reach (tools/qa/BUGS.md B2).
		if int(game.get(&"kills")) == 0:
			print("  WARN [demon %s] autopilot killed nothing in %.0fs" % [id, float(game.get(&"elapsed"))])
		rs.call(&"end_run", false, &"slain")
		await _frames(150)
		rs.call(&"return_to_basecamp")
		await _frames(60)
		_check(_scene_is(HUB), "[demon %s] back in basecamp" % id)


func _scene_is(path: String) -> bool:
	return current_scene != null and current_scene.scene_file_path == path


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## Waits until Game.elapsed reaches `secs` (or 4x that many frames at 60 fps, if the run stalls).
func _game_seconds(game: Node, secs: float) -> void:
	var cap := int(secs * 60.0 * 4.0)
	for i in cap:
		await process_frame
		if float(game.get(&"elapsed")) >= secs:
			return
		var run_state: Node = root.get_node(^"RunState")
		if not bool(run_state.get(&"active")) and i > 60:
			# The demon died (or the run was won): a legitimate run end, not a stall.
			print("  info run ended by itself at %.1fs: %s" % [float(game.get(&"elapsed")),
				(run_state.get(&"last_result") as Dictionary).get("cause", "?")])
			await _frames(30)
			return
	var pl: Node = game.get(&"player")
	var hp: Variant = pl.get(&"hp") if is_instance_valid(pl) else null
	var rs: Node = root.get_node(^"RunState")
	var modal := PackedStringArray()  # visible CanvasLayers that process while paused (menus)
	for n in root.find_children("*", "CanvasLayer", true, false):
		var cl := n as CanvasLayer
		if cl.visible and cl.process_mode == Node.PROCESS_MODE_ALWAYS:
			modal.append(String(cl.name))
	_check(false, "game time stalled at %.1fs (paused=%s, run active=%s, hp=%s, always-layers=%s)" % [
		float(game.get(&"elapsed")), paused, rs.get(&"active"), hp, ",".join(modal)])


func _restore_saves() -> void:
	if _isolated:
		return
	for path: String in SAVES:
		if _backup.has(path):
			var f := FileAccess.open(path, FileAccess.WRITE)
			for i in 20:  # other Godot processes (parallel workers) may hold the file briefly
				if f != null:
					break
				OS.delay_msec(250)
				f = FileAccess.open(path, FileAccess.WRITE)
			if f == null:
				push_warning("flow_smoke: cannot restore %s (%s)" % [path, error_string(FileAccess.get_open_error())])
				continue
			f.store_string(_backup[path])
			f.close()
		elif FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
