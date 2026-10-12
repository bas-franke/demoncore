extends Node
## Atmosphere director (autoload "Atmosphere"): per-map lighting, sky, fog, colour grade and weather,
## authored as JSON presets in res://data/atmosphere/presets.json. Full API: docs/team/visuals.md.
##
##   Atmosphere.apply_preset("cathedral_city", 8.0)          # blend over 8 s (0 = snap)
##   Atmosphere.push_overlay(&"x", "run_storm", 5.0, 0.4)     # named / Dictionary overlay at 40 %
##   Atmosphere.set_weather("rain", 1.0) / strike_lightning() / flash() / heat_haze() / add_gloom()
##
## This node owns presets, blending and the API; the rest lives in scenes/world/atmo/:
## AtmoScene (driven scene nodes, applying a state), AtmoStack (overlays + overrides), AtmoRig (in-scene
## layers, lights, lightning, screen FX), AtmoEvents (child "Events": boss, gloom, clouds, flicker,
## haze, bloom), AtmoRunWeather (child "RunWeather": run escalation, surges, final-boss dawn).
## Presets are applied automatically from Maps.map_loaded, presets.json "_scenes", or a scene root
## meta "atmosphere_preset". Dev: `-- --atmo=<preset>`, `--atmo-tour=<dir>`, `--atmo-bench=<file>`;
## debug builds: F7 next preset, Shift+F7 lightning strike.

signal preset_changed(preset: String)
signal lightning_struck(position: Vector3, far: float)

enum Quality { LOW, MEDIUM, HIGH, ULTRA }

const CYCLE_BLEND := 14.0

## The current blended state ("section.key" -> value). Read-only for other systems.
var state := {}

var _presets := AtmoPresets.new()
var _preset := ""  # what was asked for (map preset)
var _base := ""  # what is showing (a step of the preset's weather cycle, or _preset)
var _stack := AtmoStack.new()  # overlays + overrides on top of the preset
var _from := {}
var _to := {}
var _blend_t := 1.0
var _blend_dur := 0.0
var _cycle: Array[Dictionary] = []
var _cycle_i := 0
var _cycle_left := 0.0
var _forced := ""  # --atmo=<preset>
var _scene: AtmoScene
var _rescan_left := 0.0
var _rescans := 0
var _events: AtmoEvents
var _run: AtmoRunWeather


func _ready() -> void:
	_presets.load_file()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--atmo="):
			_forced = arg.substr(7)
			if not _presets.has(_forced):
				push_warning("Atmosphere: unknown preset '%s' (--atmo)" % _forced)
				_forced = ""
		elif arg.begins_with("--atmo-tour=") or arg.begins_with("--atmo-bench"):
			var tour: Node = load("res://tools/atmo_tour.gd").new()
			tour.name = "AtmoTour"
			add_child(tour)
	# Runs while paused too, so a preset lands even if a menu pauses the first frames; blends and
	# timers get delta 0 while paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_events = AtmoEvents.new()
	_events.name = "Events"
	_events.director = self
	add_child(_events)
	_run = AtmoRunWeather.new()
	_run.name = "RunWeather"
	_run.director = self
	add_child(_run)
	# Deferred: autoloads registered after Atmosphere are not in the tree yet. By path, so one
	# broken autoload never cuts the others off.
	(func() -> void:
		_connect(^"/root/Maps", &"map_loaded", _on_maps_map_loaded)
		_connect(^"/root/Settings", &"graphics_changed", _on_settings_graphics_changed)).call_deferred()


func _process(delta: float) -> void:
	_bind_scene()
	if get_tree().paused:
		delta = 0.0  # hold blends, the weather cycle and drifting clouds while a menu is up
	if _scene == null:
		return
	if _preset == "":
		_auto_apply()
	if _preset == "":
		_events.update_clouds(delta, {})
		return
	# Late-built map parts (a map's own post pass, the ground) are picked up by a few slow rescans
	# after a preset is applied; after that the tree is never walked again.
	if _rescans > 0:
		_rescan_left -= delta
		if _rescan_left <= 0.0:
			_rescan_left = 1.0
			_rescans -= 1
			_scene.bind(false)
			_scene.apply(state, _allow())
	_update_cycle(delta)
	if _blend_t < 1.0:
		_blend_t = minf(_blend_t + delta / maxf(_blend_dur, 0.001), 1.0)
		state = AtmoPresets.lerp_state(_from, _to, smoothstep(0.0, 1.0, _blend_t))
		_scene.apply(state, _allow())
	_events.tick(delta)


# ================================================================ public API

## Switches to `preset` (see presets.json), blending over `blend` seconds (0 = snap). Clears weather
## overrides; keeps overlays (boss / run lighting survives a change). Returns false if unknown.
func apply_preset(preset: String, blend: float = 0.0) -> bool:
	if not _presets.has(preset):
		push_warning("Atmosphere: unknown preset '%s'" % preset)
		return false
	_bind_scene()
	if _scene == null:
		push_warning("Atmosphere: no current scene to apply '%s' to" % preset)
		return false
	if get_rig() == null:
		_scene.ensure_rig(quality(), _particle_density())
		_scene.rig.lightning.struck.connect(func(p: Vector3, far: float) -> void:
			lightning_struck.emit(p, far))
		_scene.bind(true)
	_preset = preset
	_rescans = 4
	_stack.clear_values()
	_cycle = _presets.cycle_of(preset)
	_cycle_i = 0
	_base = preset
	if not _cycle.is_empty():
		_base = _cycle[0]["preset"]
		_cycle_left = _cycle[0]["time"]
	# Named overlays pushed before the preset (e.g. run escalation) pick up its local versions.
	_stack.reresolve(_presets, _preset)
	_retarget(blend)
	print_verbose("Atmosphere: preset %s (showing %s) on %s" % [preset, _base, _scene.root.name])
	preset_changed.emit(preset)
	return true


func get_preset() -> String:
	return _preset


func has_preset(preset: String) -> bool:
	return _presets.has(preset)


func get_preset_names() -> PackedStringArray:
	return _presets.names()


## Layers an overlay on top of the preset. `overlay`: a name from presets.json "_overlays" (or the
## preset's own "overlays"), or a Dictionary like {"grade.vignette+": 0.2, "sun.energy*": 0.5}.
## `weight` 0..1 applies it partially. Pushing an existing id updates it in place.
func push_overlay(id: StringName, overlay: Variant, blend: float = 2.0, weight: float = 1.0) -> void:
	_bind_scene()
	var preset_name := ""
	var ops := {}
	if overlay is Dictionary:
		ops = AtmoPresets.parse_ops(overlay)
	else:
		preset_name = String(overlay)
		ops = _presets.overlay(preset_name, _preset)
		if ops.is_empty():
			push_warning("Atmosphere: unknown overlay '%s'" % overlay)
			return
	_stack.push(id, preset_name, ops, weight)
	_retarget(blend)


func pop_overlay(id: StringName, blend: float = 3.0) -> void:
	if _stack.pop(id):
		_retarget(blend)


func has_overlay(id: StringName) -> bool:
	return _stack.has(id)


## True if presets.json defines overlay `name` (globally or for the active preset).
func has_overlay_def(name: String) -> bool:
	return not _presets.overlay(name, _preset).is_empty()


## Overrides one weather layer's intensity: ash, embers, feathers, snow, rain, rays, wisps (0..1),
## lightning (strikes/min), clouds (0..1), gust (0..1). Cleared by clear_weather() or apply_preset().
func set_weather(layer: String, intensity: float, blend: float = 3.0) -> void:
	set_value("weather." + layer, intensity, blend)


## Removes a set_weather() override ("" = all of them).
func clear_weather(layer: String = "", blend: float = 3.0) -> void:
	if layer == "":
		_stack.clear_values("weather.")
	else:
		_stack.set_value("weather." + layer, null)
	_retarget(blend)


## Overrides any flat state key ("env.exposure", "grade.saturation", "fx.hellglow_energy", ...).
## Pass null to remove the override.
func set_value(key: String, value: Variant, blend: float = 2.0) -> void:
	_stack.set_value(key, value)
	_retarget(blend)


## Current blended value of a flat key (null if no preset is active).
func get_value(key: String) -> Variant:
	return state.get(key)


## The current scene's AtmoRig (null before a preset was applied there).
func get_rig() -> AtmoRig:
	return _scene.rig if _scene and is_instance_valid(_scene.rig) else null


## Lightning strike: `at` = ground point (default: random around the player); `far` 0 = right here,
## 1 = distant, < 0 = random. `with_sound` false = bolt, flash and lights only (no thunder / shake).
func strike_lightning(at: Vector3 = Vector3.INF, far: float = -1.0, with_sound: bool = true) -> void:
	var rig := get_rig()
	if rig:
		rig.lightning.strike(at, far, with_sound)


## Full-screen additive flash (strength ~0.1..0.6), fading at `decay` per second.
func flash(color: Color, strength: float = 0.35, decay: float = 3.0) -> void:
	var rig := get_rig()
	if rig:
		rig.flash(color, strength, decay)


## Screen-space heat shimmer around `pos` (hellfire casts, explosions). Skipped on Low quality.
func heat_haze(pos: Vector3, radius: float = 3.0, duration: float = 1.0, strength: float = 1.0) -> void:
	var rig := get_rig()
	if rig:
		rig.heat_burst(pos, radius, duration, strength)


## Pins the gloom (corruption darkness around the player, 0..1.5); < 0 returns it to the preset's
## fx.gloom plus kill pulses and corruption.
func set_gloom(amount: float) -> void:
	_events.set_gloom(amount)


## Adds a decaying gloom pulse (e.g. a corruption ability firing).
func add_gloom(amount: float) -> void:
	_events.add_gloom(amount)


func get_gloom() -> float:
	return _events.gloom


## Run escalation 0 (calm start) .. 1 (full storm), see AtmoRunWeather.
func get_escalation() -> float:
	return _run.escalation


## Global hellfire flicker strength (fx.flicker of the active state; 1 without a preset).
func flicker_strength() -> float:
	return float(state.get("fx.flicker", 1.0))


## Quality tier from the Settings graphics preset (custom settings: from particle density).
func quality() -> int:
	# Settings.PRESET_LOW..PRESET_ULTRA (0..3) line up with Quality.*; 4 = custom.
	var p := int(_setting(&"graphics_preset", Quality.HIGH))
	if p >= Quality.LOW and p <= Quality.ULTRA:
		return p
	var pd := _particle_density()
	if pd < 0.55:
		return Quality.LOW
	if pd < 0.9:
		return Quality.MEDIUM
	return Quality.HIGH if pd < 1.2 else Quality.ULTRA


# ================================================================ state

func _retarget(blend: float) -> void:
	if _base == "" or _scene == null:
		return
	_to = _stack.compose(_presets, _base)
	if state.is_empty():
		state = _to.duplicate()
	_from = state.duplicate()
	_blend_dur = maxf(blend, 0.0)
	_blend_t = 0.0
	if _blend_dur <= 0.0:
		_blend_t = 1.0
		state = _to.duplicate()
	else:
		# Discrete keys (toggles, tonemap) switch at the start of the blend.
		state = AtmoPresets.lerp_state(_from, _to, 0.0)
	_scene.apply(state, _allow())


func _update_cycle(delta: float) -> void:
	if _cycle.size() < 2 or _events.boss != null:
		return
	_cycle_left -= delta
	if _cycle_left > 0.0:
		return
	_cycle_i = (_cycle_i + 1) % _cycle.size()
	_cycle_left = _cycle[_cycle_i]["time"]
	var next: String = _cycle[_cycle_i]["preset"]
	if next != _base:
		_base = next
		_retarget(CYCLE_BLEND)


# ================================================================ scene binding

## Follows SceneTree.current_scene; a new scene drops every binding, overlay and the preset.
func _bind_scene() -> void:
	var cs := get_tree().current_scene
	if _scene and _scene.root == cs and (cs == null or is_instance_valid(cs)):
		return
	if _scene == null and cs == null:
		return
	_scene = AtmoScene.new(cs) if cs else null
	_preset = ""
	_base = ""
	_stack.clear()
	_cycle.clear()
	state = {}
	_events.reset()
	_run.reset()


func _auto_apply() -> void:
	if _forced != "":
		apply_preset(_forced)
	elif _scene.root.has_meta(&"atmosphere_preset"):
		apply_preset(String(_scene.root.get_meta(&"atmosphere_preset")))
	else:
		var p := _presets.scene_preset(_scene.root.scene_file_path)
		if p != "":
			apply_preset(p)


## What the graphics settings allow (glow / SSAO / volumetric fog).
func _allow() -> Dictionary:
	return {
		"ssao": int(_setting(&"ssao_quality", 2)) > 0,
		"glow": bool(_setting(&"glow", true)),
		"volumetrics": bool(_setting(&"volumetrics", true)),
	}


## A Settings value by name (default if Settings is missing).
func _setting(key: StringName, default: Variant) -> Variant:
	var st := get_node_or_null(^"/root/Settings")
	var v: Variant = st.get(key) if st else null
	return default if v == null else v


func _particle_density() -> float:
	return float(_setting(&"particle_density", 1.0))


func _connect(path: NodePath, sig: StringName, cb: Callable) -> void:
	var n := get_node_or_null(path)
	if n and n.has_signal(sig):
		n.connect(sig, cb)
	else:
		push_warning("Atmosphere: cannot connect %s.%s" % [path, sig])


func _on_settings_graphics_changed() -> void:
	var rig := get_rig()
	if rig:
		rig.set_quality(quality(), _particle_density())
	if _scene and not state.is_empty():
		_scene.apply_toggles(state, _allow())


func _on_maps_map_loaded(_map: Node3D, def: Dictionary) -> void:
	if _forced != "":
		return
	# The def's "atmosphere_preset", else a preset named like the map; else the map keeps its look.
	for key: String in ["atmosphere_preset", "id"]:
		var p := String(def.get(key, ""))
		if _presets.has(p):
			apply_preset(p)
			return
		if p != "" and key == "atmosphere_preset":
			push_warning("Atmosphere: map %s names unknown preset '%s'" % [def.get("id", "?"), p])


# ---------------------------------------------------------------- dev

func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build() or not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return
	var k := event as InputEventKey
	if k.keycode != KEY_F7:
		return
	if k.shift_pressed:
		strike_lightning(Vector3.INF, 0.1)
		return
	var names := get_preset_names()
	if names.is_empty():
		return
	var next := names[(names.find(_preset) + 1) % names.size()]
	apply_preset(next, 2.0)
	print("Atmosphere: preset ", next)
