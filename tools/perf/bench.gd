extends Node
## SINBOUND performance bench. Loads res://scenes/main.tscn and drives it through a fixed series of
## increasingly heavy phases, logging frame-time and renderer stats.
##
## Run (windowed, so rendering is actually measured; vsync is switched off at runtime):
##   godot --path . res://tools/perf/bench.tscn -- --autopilot --demon=lilaeth [--bench-label=name]
##   optional: --bench-short (halves phase durations)
##
## Output (res://tools/perf/results/):
##   bench_<label>_<stamp>.csv          one row per second per phase
##   bench_<label>_<stamp>_summary.txt  per-phase aggregate + scene scan (materials, lights, ...)
##
## The bench keeps the demon stationary and invulnerable, with xp_gain = 0 (no level-up pauses),
## tops enemies / soul shards up to each phase's target every frame, and keeps the boss alive.

const MAIN_SCENE := "res://scenes/main.tscn"
const GEM_SCENE := "res://scenes/pickups/xp_gem.tscn"
const RESULTS_DIR := "res://tools/perf/results"
const WARMUP := 2.0  # seconds at the start of a phase excluded from stats (spawn hitches)
const MAX_SPAWN_PER_FRAME := 25

## name, seconds, enemy target, shard target, boss, all weapons
var phases: Array[Dictionary] = [
	{"name": "baseline", "dur": 8.0, "enemies": 0, "gems": 0, "boss": false, "all_weapons": false},
	{"name": "enemies_150", "dur": 12.0, "enemies": 150, "gems": 0, "boss": false, "all_weapons": false},
	{"name": "enemies_300", "dur": 12.0, "enemies": 300, "gems": 0, "boss": false, "all_weapons": false},
	{"name": "e300_shards400", "dur": 12.0, "enemies": 300, "gems": 400, "boss": false, "all_weapons": false},
	{"name": "e300_shards400_boss", "dur": 14.0, "enemies": 300, "gems": 400, "boss": true, "all_weapons": false},
	{"name": "e300_shards400_boss_allweapons", "dur": 14.0, "enemies": 300, "gems": 400, "boss": true, "all_weapons": true},
	# Diagnostic phases (same load as above, one subsystem removed) to attribute cost:
	{"name": "diag_enemy_shadows_off", "dur": 10.0, "enemies": 300, "gems": 400, "boss": true, "all_weapons": true, "diag": "no_shadows"},
	{"name": "diag_enemy_models_hidden", "dur": 10.0, "enemies": 300, "gems": 400, "boss": true, "all_weapons": true, "diag": "hide_models"},
	{"name": "diag_vfx_hidden", "dur": 10.0, "enemies": 300, "gems": 400, "boss": true, "all_weapons": true, "diag": "hide_vfx"},
	{"name": "diag_post_fx_off", "dur": 10.0, "enemies": 300, "gems": 400, "boss": true, "all_weapons": true, "diag": "env_lite"},
	{"name": "diag_no_enemy_collide", "dur": 10.0, "enemies": 300, "gems": 400, "boss": true, "all_weapons": true, "diag": "no_enemy_collide"},
	{"name": "diag_enemy_ai_off", "dur": 10.0, "enemies": 300, "gems": 400, "boss": true, "all_weapons": true, "diag": "ai_off"},
]

var _main: Node
var _spawner: EnemySpawner
var _gem_scene: PackedScene
var _vp_rid: RID
var _phase_i := -1
var _phase_t := 0.0
var _sample_t := 0.0
var _last_usec := 0
var _skip_next := false
var _rule_i := 0
var _boss: Node
var _label := "run"
var _stamp := ""
var _csv: FileAccess
var _summary := PackedStringArray()

# per-phase accumulators
var _frames := PackedFloat64Array()      # ms, whole phase after warmup
var _gpu := PackedFloat64Array()
var _rcpu := PackedFloat64Array()
var _sec_frames := PackedFloat64Array()  # ms, current 1 s window
var _sec_gpu := 0.0
var _sec_rcpu := 0.0
var _sec_n := 0
var _phase_rows: Array[Dictionary] = []
var _scan := {}
var _env_saved := {}
var _spawn_us := 0.0
var _spawn_n := 0
var _gem_spawn_us := 0.0
var _gem_spawn_n := 0
var _phys_steps := 0
var _sec_phys := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bench-label="):
			_label = a.substr(14)
		elif a.begins_with("--bench-phases="):
			var keep := a.substr(15).split(",")
			phases = phases.filter(func(p: Dictionary) -> bool: return p["name"] in keep)
		elif a == "--bench-short":
			for p in phases:
				p["dur"] = p["dur"] * 0.5
	Game.autopilot = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_vp_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)
	_gem_scene = load(GEM_SCENE)

	var d := Time.get_datetime_dict_from_system()
	_stamp = "%04d%02d%02d_%02d%02d%02d" % [d.year, d.month, d.day, d.hour, d.minute, d.second]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RESULTS_DIR))
	_csv = FileAccess.open("%s/bench_%s_%s.csv" % [RESULTS_DIR, _label, _stamp], FileAccess.WRITE)
	_csv.store_line(",".join(PackedStringArray([
		"phase", "t", "fps", "avg_ms", "max_ms", "gpu_ms", "render_cpu_ms", "process_ms", "physics_ms", "physics_steps_per_frame",
		"draw_calls", "visible_draw_calls", "shadow_draw_calls", "primitives", "visible_primitives",
		"shadow_primitives", "objects", "visible_objects", "shadow_objects", "nodes", "objects_alive",
		"enemies", "gems", "video_mem_mb", "texture_mem_mb", "buffer_mem_mb", "pipeline_compiles_draw",
		"pipeline_compiles_spec", "physics_active_3d", "physics_pairs_3d"])))

	_main = load(MAIN_SCENE).instantiate()
	add_child(_main)
	_spawner = _main.get_node("EnemySpawner") as EnemySpawner
	_spawner.set_process(false)  # the bench controls population
	_summary.append("SINBOUND bench  label=%s  %s" % [_label, _stamp])
	_summary.append("GPU: %s / %s  driver %s" % [RenderingServer.get_video_adapter_vendor(),
			RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version()])
	_summary.append("CPU: %s (%d threads)  Window: %s  Godot %s" % [OS.get_processor_name(),
			OS.get_processor_count(), str(DisplayServer.window_get_size()), Engine.get_version_info().string])
	_summary.append("")
	_last_usec = Time.get_ticks_usec()
	_next_phase()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _last_usec) / 1000.0
	_last_usec = now
	if _phase_i < 0 or _phase_i >= phases.size():
		return
	_keep_player()
	var p := phases[_phase_i]
	_top_up(p)
	_apply_diag(p)
	_phase_t += ms / 1000.0

	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid)
	var rcpu := RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid) + RenderingServer.get_frame_setup_time_cpu()
	if _skip_next:
		_skip_next = false
	elif _phase_t > WARMUP:
		_frames.append(ms)
		_gpu.append(gpu)
		_rcpu.append(rcpu)
		_sec_frames.append(ms)
		_sec_gpu += gpu
		_sec_rcpu += rcpu
		_sec_n += 1
		_sec_phys += _phys_steps
		_sample_t += ms / 1000.0
		if _sample_t >= 1.0:
			_sample_t = 0.0
			_write_row(p)
		if _scan.is_empty() and _phase_t > p["dur"] * 0.6:
			_scan = _scan_scene()
			_scan["microbench"] = _microbench()
			_skip_next = true  # the scan itself hitches this frame
	_phys_steps = 0
	if _phase_t >= p["dur"]:
		_finish_phase()
		_next_phase()


func _physics_process(_delta: float) -> void:
	_phys_steps += 1


# ---------------------------------------------------------------- scenario control

## Diagnostic tweaks applied every frame to every enemy (including newly spawned ones).
func _apply_diag(p: Dictionary) -> void:
	var diag: String = p.get("diag", "")
	if diag == "":
		return
	if diag == "hide_vfx":
		# Everything spawned into the world that is not an enemy / boss / soul shard (projectiles,
		# death bursts, smoke, orbs, damage numbers, chalices...).
		for c in Game.world.get_children():
			if c is Node3D and not c is Enemy and not c is XPGem:
				(c as Node3D).visible = false
		return
	if diag == "env_lite":
		if _env_saved.is_empty():
			var we := _main.get_node("WorldEnvironment") as WorldEnvironment
			var env := we.environment
			_env_saved = {"env": env, "ssao": env.ssao_enabled, "glow": env.glow_enabled, "fog": env.fog_enabled,
					"vfog": env.volumetric_fog_enabled, "ssil": env.ssil_enabled, "ssr": env.ssr_enabled,
					"attr": we.camera_attributes, "we": we}
			env.ssao_enabled = false
			env.glow_enabled = false
			env.fog_enabled = false
			env.volumetric_fog_enabled = false
			env.ssil_enabled = false
			env.ssr_enabled = false
			we.camera_attributes = null  # DOF off
		return
	for n in get_tree().get_nodes_in_group(&"enemies"):
		var e := n as Enemy
		if e == null or e is Boss or e.model == null:
			continue
		match diag:
			"no_shadows":
				if not e.has_meta(&"_bench_diag"):
					e.set_meta(&"_bench_diag", true)
					Art.no_shadows(e.model)
			"hide_models":
				e.model.visible = false
			"ai_off":
				e.set_physics_process(false)
			"no_enemy_collide":
				e.collision_mask = 1  # world only: no enemy-vs-enemy separation in move_and_slide


var _tri_cache := {}


func _mesh_tris(m: Mesh) -> int:
	if m == null:
		return 0
	if not _tri_cache.has(m):
		var t := 0
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var ind = arr[Mesh.ARRAY_INDEX]
			var idx: int = (ind as PackedInt32Array).size() if ind != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			@warning_ignore("integer_division")
			t += idx / 3
		_tri_cache[m] = t
	return _tri_cache[m]


## Per enemy type (EnemyData.id): mesh instances, shadow casters, triangles, nodes, lights.
func _enemy_type_stats(list: Array[Enemy]) -> Dictionary:
	var out := {}
	for e in list:
		var id := String(e.data.id) if e.data.id != &"" else e.data.resource_path.get_file()
		if out.has(id):
			out[id]["count"] += 1
			continue
		var meshes := 0
		var shadows := 0
		var tris := 0
		var lights := 0
		var skeletons := 0
		var nodes := e.model.find_children("*", "", true, false)
		for c in nodes:
			if c is Skeleton3D:
				skeletons += 1
			if c is MeshInstance3D:
				meshes += 1
				tris += _mesh_tris((c as MeshInstance3D).mesh)
				if (c as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
					shadows += 1
			elif c is Light3D:
				lights += 1
		out[id] = {"count": 1, "mesh_instances": meshes, "shadow_casters": shadows, "tris": tris,
				"nodes": nodes.size(), "lights": lights, "skeletons": skeletons, "glb": e.model.glb != null}
	return out


## Times the pieces of Enemy._physics_process across all live enemies (one-off, in _process).
func _microbench() -> Dictionary:
	var list: Array[Enemy] = []
	for n in get_tree().get_nodes_in_group(&"enemies"):
		var e := n as Enemy
		if e and not e is Boss and not e.is_dying and e.model and e.is_physics_processing():
			list.append(e)
	if list.is_empty():
		return {}
	var dt := 1.0 / 60.0
	var t0 := Time.get_ticks_usec()
	for e in list:
		e.model.animate(dt, 0.5, EnemyModel.State.MOVING)
	var t1 := Time.get_ticks_usec()
	for e in list:
		e.move_and_slide()
	var t2 := Time.get_ticks_usec()
	for e in list:
		e.model.set_flash(0.0)
	var t3 := Time.get_ticks_usec()
	for e in list:
		e._physics_process(dt)
	var t4 := Time.get_ticks_usec()
	var gems := get_tree().get_nodes_in_group(&"gems")
	for g in gems:
		g._physics_process(dt)
	var t5 := Time.get_ticks_usec()
	var n_anim := 0
	for e in list:
		if e.model.glb and e.model.glb.anim_player:
			e.model.glb.anim_player.advance(dt)
			n_anim += 1
	var t6 := Time.get_ticks_usec()
	var n := float(list.size())
	return {
		"anim_players": n_anim, "anim_advance_total_ms": (t6 - t5) / 1000.0,
		"anim_advance_us_each": snappedf((t6 - t5) / maxf(n_anim, 1), 0.1),
		"gems": gems.size(), "gem_physics_total_ms": (t5 - t4) / 1000.0,
		"gem_us_each": snappedf((t5 - t4) / maxf(gems.size(), 1), 0.1),
		"spawn_enemy_us_avg": snappedf(_spawn_us / maxf(_spawn_n, 1), 0.1), "spawns_timed": _spawn_n,
		"spawn_gem_us_avg": snappedf(_gem_spawn_us / maxf(_gem_spawn_n, 1), 0.1),
		"per_enemy_type": _enemy_type_stats(list),
		"enemies": list.size(),
		"animate_total_ms": (t1 - t0) / 1000.0, "animate_us_each": snappedf((t1 - t0) / n, 0.1),
		"move_and_slide_total_ms": (t2 - t1) / 1000.0, "move_and_slide_us_each": snappedf((t2 - t1) / n, 0.1),
		"set_flash_total_ms": (t3 - t2) / 1000.0, "set_flash_us_each": snappedf((t3 - t2) / n, 0.1),
		"physics_process_total_ms": (t4 - t3) / 1000.0, "physics_process_us_each": snappedf((t4 - t3) / n, 0.1),
	}

func _keep_player() -> void:
	var pl := Game.player
	if pl == null:
		return
	pl.move_speed = 0.0
	pl.xp_gain = 0.0
	pl.armor = 1.0e6
	pl.max_hp = 1.0e6
	pl.hp = pl.max_hp
	if _boss and is_instance_valid(_boss):
		_boss.set(&"hp", 1.0e9)


func _top_up(p: Dictionary) -> void:
	if Game.player == null or Game.world == null:
		return
	var center := Game.player.global_position
	var n_en := get_tree().get_node_count_in_group(&"enemies")
	var budget := MAX_SPAWN_PER_FRAME
	var rules := _spawner.rules
	while n_en < int(p["enemies"]) and budget > 0 and not rules.is_empty():
		var data: EnemyData = rules[_rule_i % rules.size()].enemy
		_rule_i += 1
		var ts := Time.get_ticks_usec()
		var e := _spawner.spawn(data)
		_spawn_us += Time.get_ticks_usec() - ts
		_spawn_n += 1
		# Spawn in view (the crowd should be on screen), not on the off-screen ellipse.
		var a := randf() * TAU
		e.global_position = center + Vector3(cos(a) * randf_range(4.0, 17.0), 0.0, sin(a) * randf_range(3.0, 11.0))
		e.reset_physics_interpolation()
		n_en += 1
		budget -= 1
	var n_gem := get_tree().get_node_count_in_group(&"gems")
	budget = MAX_SPAWN_PER_FRAME
	while n_gem < int(p["gems"]) and budget > 0:
		var g := _gem_scene.instantiate()
		var roll := randf()
		g.set(&"value", 1 if roll < 0.6 else (8 if roll < 0.9 else 30))
		var a := randf() * TAU
		var ts := Time.get_ticks_usec()
		Game.spawn(g, center + Vector3(cos(a) * randf_range(3.5, 16.0), 0.4, sin(a) * randf_range(3.0, 10.0)))
		_gem_spawn_us += Time.get_ticks_usec() - ts
		_gem_spawn_n += 1
		n_gem += 1
		budget -= 1
	if p["boss"] and (_boss == null or not is_instance_valid(_boss)):
		_boss = _spawner.spawn_boss()
	if p["all_weapons"]:
		for w in Game.player.weapon_pool:
			if not Game.player.has_weapon(w):
				Game.player.add_weapon(w)


func _next_phase() -> void:
	_phase_i += 1
	if _phase_i >= phases.size():
		_finish()
		return
	_phase_t = 0.0
	_sample_t = 0.0
	_frames = PackedFloat64Array()
	_gpu = PackedFloat64Array()
	_rcpu = PackedFloat64Array()
	_phase_rows.clear()
	_scan = {}
	_spawn_us = 0.0
	_spawn_n = 0
	_gem_spawn_us = 0.0
	_gem_spawn_n = 0
	_reset_sec()
	print("[bench] phase %s" % phases[_phase_i]["name"])


func _reset_sec() -> void:
	_sec_frames = PackedFloat64Array()
	_sec_gpu = 0.0
	_sec_rcpu = 0.0
	_sec_n = 0
	_sec_phys = 0


# ---------------------------------------------------------------- sampling

func _vinfo(type: int, info: int) -> int:
	return RenderingServer.viewport_get_render_info(_vp_rid, type, info)


func _write_row(p: Dictionary) -> void:
	var avg := _mean(_sec_frames)
	var row := {
		"phase": p["name"], "t": snappedf(_phase_t, 0.01),
		"fps": snappedf(1000.0 / maxf(avg, 0.001), 0.1), "avg_ms": snappedf(avg, 0.01),
		"max_ms": snappedf(_max(_sec_frames), 0.01),
		"gpu_ms": snappedf(_sec_gpu / maxf(_sec_n, 1), 0.01),
		"render_cpu_ms": snappedf(_sec_rcpu / maxf(_sec_n, 1), 0.01),
		"process_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
		"physics_ms": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01),
		"physics_steps_per_frame": snappedf(float(_sec_phys) / maxf(_sec_n, 1), 0.01),
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"visible_draw_calls": _vinfo(RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"shadow_draw_calls": _vinfo(RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"visible_primitives": _vinfo(RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		"shadow_primitives": _vinfo(RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"visible_objects": _vinfo(RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
		"shadow_objects": _vinfo(RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"objects_alive": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"enemies": get_tree().get_node_count_in_group(&"enemies"),
		"gems": get_tree().get_node_count_in_group(&"gems"),
		"video_mem_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"texture_mem_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0, 0.1),
		"buffer_mem_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED) / 1048576.0, 0.1),
		"pipeline_compiles_draw": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW),
		"pipeline_compiles_spec": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION),
		"physics_active_3d": int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		"physics_pairs_3d": int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)),
	}
	var vals := PackedStringArray()
	for v in row.values():
		vals.append(str(v))
	_csv.store_line(",".join(vals))
	_csv.flush()
	_phase_rows.append(row)
	_reset_sec()


## One-off walk of the scene: unique materials/shaders, lights, particles, shadow casters,
## instance-uniform users, visibility ranges, MultiMeshes.
func _scan_scene() -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var cam := get_viewport().get_camera_3d()
	var mats := {}
	var shaders := {}
	var std_mats := 0
	var transparent_mats := 0
	var geo := 0
	var geo_visible := 0
	var shadow_casters := 0
	var instance_uniform_users := 0
	var vis_range := 0
	var mmi := 0
	var mm_instances := 0
	var cpu_particles := 0
	var cpu_particle_amount := 0
	var gpu_particles := 0
	var gpu_particle_amount := 0
	var by_owner := {}  # top-level category -> mesh instance count
	for n in _main.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		geo += 1
		if not gi.is_visible_in_tree():
			continue
		geo_visible += 1
		if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			shadow_casters += 1
		if gi.visibility_range_end > 0.0:
			vis_range += 1
		var cat := _category(gi)
		by_owner[cat] = by_owner.get(cat, 0) + 1
		var list: Array[Material] = []
		if gi.material_override:
			list.append(gi.material_override)
		if gi.material_overlay:
			list.append(gi.material_overlay)
		if gi is MeshInstance3D:
			var mi := gi as MeshInstance3D
			if mi.mesh:
				for s in mi.mesh.get_surface_count():
					var m := mi.get_surface_override_material(s)
					if m == null:
						m = mi.mesh.surface_get_material(s)
					if m:
						list.append(m)
		elif gi is MultiMeshInstance3D:
			mmi += 1
			var mm := (gi as MultiMeshInstance3D).multimesh
			if mm:
				mm_instances += mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
		elif gi is CPUParticles3D:
			cpu_particles += 1
			cpu_particle_amount += (gi as CPUParticles3D).amount
		elif gi is GPUParticles3D:
			gpu_particles += 1
			gpu_particle_amount += (gi as GPUParticles3D).amount
		var uses_iu := false
		for m in list:
			var mm2 := m
			while mm2:
				if not mats.has(mm2):
					mats[mm2] = true
					if mm2 is ShaderMaterial:
						var sh := (mm2 as ShaderMaterial).shader
						if sh:
							shaders[sh] = true
					else:
						std_mats += 1
					if mm2 is BaseMaterial3D and (mm2 as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
						transparent_mats += 1
				if mm2 is ShaderMaterial and _has_instance_uniforms((mm2 as ShaderMaterial).shader):
					uses_iu = true
				mm2 = mm2.next_pass
		if uses_iu:
			instance_uniform_users += 1
	var lights := 0
	var lights_visible := 0
	var lights_in_view := 0
	var lights_shadowed := 0
	for n in _main.find_children("*", "Light3D", true, false):
		var l := n as Light3D
		lights += 1
		if not l.is_visible_in_tree() or l.light_energy <= 0.0:
			continue
		lights_visible += 1
		if l.shadow_enabled:
			lights_shadowed += 1
		if l is DirectionalLight3D or cam == null:
			lights_in_view += 1
		else:
			var rng := (l as OmniLight3D).omni_range if l is OmniLight3D else (l as SpotLight3D).spot_range
			var pos := l.global_position
			# in view if the light center or its range sphere edge (toward the player) is in the frustum
			if cam.is_position_in_frustum(pos) or cam.is_position_in_frustum(pos.move_toward(Game.player.global_position, rng)):
				lights_in_view += 1
	var decals := _main.find_children("*", "Decal", true, false).size()
	var areas := _main.find_children("*", "Area3D", true, false).size()
	var bodies := _main.find_children("*", "CharacterBody3D", true, false).size()
	var res := {
		"geometry_instances": geo, "geometry_visible": geo_visible, "shadow_casters": shadow_casters,
		"unique_materials": mats.size(), "unique_shaders": shaders.size(), "standard_materials": std_mats,
		"transparent_std_materials": transparent_mats, "instance_uniform_users": instance_uniform_users,
		"visibility_range_set": vis_range, "multimesh_instances": mmi, "multimesh_items": mm_instances,
		"cpu_particle_systems": cpu_particles, "cpu_particle_amount": cpu_particle_amount,
		"gpu_particle_systems": gpu_particles, "gpu_particle_amount": gpu_particle_amount,
		"lights_total": lights, "lights_enabled": lights_visible, "lights_near_view": lights_in_view,
		"lights_shadowed": lights_shadowed, "decals": decals, "area3d": areas, "character_bodies": bodies,
		"geometry_by_category": by_owner, "scan_ms": (Time.get_ticks_usec() - t0) / 1000.0,
	}
	return res


var _iu_cache := {}
var _iu_re: RegEx


## True if the shader (or a file it #includes) declares an `instance uniform`.
func _has_instance_uniforms(sh: Shader) -> bool:
	if sh == null:
		return false
	if not _iu_cache.has(sh):
		_iu_cache[sh] = _code_has_iu(sh.code, 0)
	return _iu_cache[sh]


func _code_has_iu(code: String, _depth: int) -> bool:
	if _iu_re == null:
		_iu_re = RegEx.create_from_string("(?m)^\\s*instance\\s+uniform")
	# lit/toon declare their instance uniforms inside `#ifdef FLASHABLE` in the shared include.
	return _iu_re.search(code) != null or code.contains("#define FLASHABLE")


func _category(n: Node) -> String:
	var cur := n
	while cur and cur.get_parent() != _main:
		cur = cur.get_parent()
	if cur == null:
		return "?"
	if cur.name == &"Entities":
		var e := n
		while e and e.get_parent() != cur:
			e = e.get_parent()
		if e is Boss:
			return "Entities/boss"
		if e is Enemy:
			return "Entities/enemy"
		if e is XPGem:
			return "Entities/gem"
		return "Entities/other(%s)" % (e.get_script().resource_path.get_file() if e and e.get_script() else e.get_class())
	return String(cur.name)


# ---------------------------------------------------------------- aggregation

func _finish_phase() -> void:
	var p := phases[_phase_i]
	var sorted := _frames.duplicate()
	sorted.sort()
	var n := sorted.size()
	var avg := _mean(sorted)
	var worst1 := PackedFloat64Array()
	var k := maxi(1, int(ceil(n * 0.01)))
	for i in range(maxi(0, n - k), n):
		worst1.append(sorted[i])
	var low1 := _mean(worst1)
	var p50 := sorted[int(n * 0.5)] if n > 0 else 0.0
	var p99 := sorted[mini(n - 1, int(n * 0.99))] if n > 0 else 0.0
	_summary.append("== %s  (%d frames measured)" % [p["name"], n])
	_summary.append("   avg %.2f ms (%.1f fps) | median %.2f ms | p99 %.2f ms | 1%% low %.2f ms (%.1f fps) | max %.2f ms" % [
			avg, 1000.0 / maxf(avg, 0.001), p50, p99, low1, 1000.0 / maxf(low1, 0.001), _max(sorted)])
	_summary.append("   GPU %.2f ms | render-thread CPU %.2f ms" % [_mean(_gpu), _mean(_rcpu)])
	if not _phase_rows.is_empty():
		var keys := ["process_ms", "physics_ms", "physics_steps_per_frame","draw_calls", "visible_draw_calls", "shadow_draw_calls",
				"primitives", "visible_primitives", "shadow_primitives", "objects", "visible_objects",
				"shadow_objects", "nodes", "enemies", "gems", "video_mem_mb", "pipeline_compiles_draw",
				"physics_pairs_3d"]
		var parts := PackedStringArray()
		for key in keys:
			var s := 0.0
			for r in _phase_rows:
				s += float(r[key])
			parts.append("%s=%s" % [key, str(snappedf(s / _phase_rows.size(), 0.1))])
		_summary.append("   " + "  ".join(parts))
	if not _scan.is_empty():
		_summary.append("   scan: " + JSON.stringify(_scan))
	_summary.append("")
	print("\n".join(_summary.slice(_summary.size() - 5)))
	if not _env_saved.is_empty():
		var env: Environment = _env_saved["env"]
		env.ssao_enabled = _env_saved["ssao"]
		env.glow_enabled = _env_saved["glow"]
		env.fog_enabled = _env_saved["fog"]
		env.volumetric_fog_enabled = _env_saved["vfog"]
		env.ssil_enabled = _env_saved["ssil"]
		env.ssr_enabled = _env_saved["ssr"]
		(_env_saved["we"] as WorldEnvironment).camera_attributes = _env_saved["attr"]
		_env_saved = {}


func _finish() -> void:
	_csv.close()
	var path := "%s/bench_%s_%s_summary.txt" % [RESULTS_DIR, _label, _stamp]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(_summary))
	f.close()
	print("[bench] done -> %s" % ProjectSettings.globalize_path(path))
	get_tree().quit()


static func _mean(a: PackedFloat64Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += v
	return s / a.size()


static func _max(a: PackedFloat64Array) -> float:
	var m := 0.0
	for v in a:
		m = maxf(m, v)
	return m
