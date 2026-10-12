extends Node
## Player settings (autoload "Settings"), persisted in user://settings.cfg.
##
## API (stable):
##   Settings.screen_shake: float (0..1)   Settings.damage_numbers: bool
##   Settings.music_volume / sfx_volume / ambience_volume / ui_volume: float (0..1)   (Sfx applies these to its buses live)
##   Settings.text_speed: float (dialogue typing multiplier)   Settings.reduce_flashes: bool (accessibility)
##   Settings.fullscreen: bool             (applies the window mode when set)
##   Settings.save_settings()
##   Settings.mark_seen(&"cucumber") / Settings.is_seen(&"cucumber")  # bestiary (saved on change)
## Setting damage_numbers keeps Game.show_damage_numbers in sync (and vice versa, e.g. debug F2).
## The settings screen is res://scenes/ui/settings_menu.tscn (instance it, call open()).
##
## Graphics (section [graphics] in settings.cfg; every setter applies live via res://scripts/graphics.gd):
##   Settings.graphics_preset: int  (PRESET_LOW/MEDIUM/HIGH/ULTRA; PRESET_CUSTOM once a value is tweaked)
##   Settings.apply_preset(Settings.PRESET_HIGH)
##   Settings.render_scale: float 0.5..1 (FSR 1 below 1)   Settings.antialiasing: int (Graphics.AA.*)
##   Settings.shadow_quality: int 0..4 (off/low/medium/high/ultra)
##   Settings.ssao_quality: int 0..3 (off/low/medium/high)
##   Settings.glow / dof / volumetrics (sun shafts + volumetric fog) / mist: bool
##   Settings.particle_density: float 0..1.5  -- READ THIS when sizing particle systems (multiply amounts)
##   Settings.decor_density: float 0.25..1.5  -- read by decor streaming (also applied to Decor's exports)
##   Settings.vsync: bool   Settings.max_fps: int (0 = unlimited)   Settings.ui_scale: float 0.75..1.5
##   Settings.window_mode: int (WINDOW_WINDOWED / WINDOW_BORDERLESS / WINDOW_EXCLUSIVE); `fullscreen` mirrors it
##   signal graphics_changed  (emitted after a change has been applied)
## Scene nodes (WorldEnvironment, DirectionalLight3D, Camera3D, Atmosphere, Decor) are configured
## automatically as they enter the tree (SceneTree.node_added -> Graphics.on_node_added).

signal graphics_changed

const PATH := "user://settings.cfg"
const GFX := preload("res://scripts/graphics.gd")

enum { PRESET_LOW, PRESET_MEDIUM, PRESET_HIGH, PRESET_ULTRA, PRESET_CUSTOM }
const PRESET_NAMES := ["Low", "Medium", "High", "Ultra", "Custom"]
enum { WINDOW_WINDOWED, WINDOW_BORDERLESS, WINDOW_EXCLUSIVE }

## Values per preset (keys = property names).
const PRESETS := [
	{  # Low
		"render_scale": 0.65, "antialiasing": 1, "shadow_quality": 1, "ssao_quality": 0,
		"glow": false, "dof": false, "volumetrics": false, "mist": false,
		"particle_density": 0.4, "decor_density": 0.5, "blight_quality": 1,
	},
	{  # Medium
		"render_scale": 0.85, "antialiasing": 1, "shadow_quality": 2, "ssao_quality": 1,
		"glow": true, "dof": false, "volumetrics": false, "mist": true,
		"particle_density": 0.7, "decor_density": 0.75, "blight_quality": 2,
	},
	{  # High (the authored look)
		"render_scale": 1.0, "antialiasing": 2, "shadow_quality": 3, "ssao_quality": 2,
		"glow": true, "dof": true, "volumetrics": true, "mist": true,
		"particle_density": 1.0, "decor_density": 1.0, "blight_quality": 2,
	},
	{  # Ultra
		"render_scale": 1.0, "antialiasing": 3, "shadow_quality": 4, "ssao_quality": 3,
		"glow": true, "dof": true, "volumetrics": true, "mist": true,
		"particle_density": 1.25, "decor_density": 1.25, "blight_quality": 2,
	},
]
const GRAPHICS_KEYS := ["graphics_preset", "render_scale", "antialiasing", "shadow_quality", "ssao_quality",
		"glow", "dof", "volumetrics", "mist", "particle_density", "decor_density", "blight_quality", "vsync", "max_fps", "ui_scale",
		"window_mode"]

var music_volume := 0.7
var sfx_volume := 0.8
## Ambience bus (wind, choirs, hellfire beds). Sfx reads it when present.
var ambience_volume := 0.8
## UI bus (menu clicks, hovers, shop, toasts). Sfx reads it when present (music/sfx roles).
var ui_volume := 0.8
## Accessibility (UI role). Dialogue typing speed multiplier (DialogueBox reads it; >= 10 = instant).
var text_speed := 1.0
## Tones down full-screen flashes (hit flash, lightning) and UI pulses/glows.
var reduce_flashes := false
var screen_shake := 1.0
var damage_numbers := true:
	set(v):
		damage_numbers = v
		if is_inside_tree():
			Game.show_damage_numbers = v
## Mirrors window_mode (true = any fullscreen mode).
var fullscreen := false:
	set(v):
		fullscreen = v
		if v and window_mode == WINDOW_WINDOWED:
			window_mode = WINDOW_BORDERLESS
		elif not v and window_mode != WINDOW_WINDOWED:
			window_mode = WINDOW_WINDOWED
		if is_inside_tree():
			_apply_fullscreen()
var window_mode: int = WINDOW_WINDOWED:
	set(v):
		window_mode = clampi(v, WINDOW_WINDOWED, WINDOW_EXCLUSIVE)
		if fullscreen != (window_mode != WINDOW_WINDOWED):
			fullscreen = window_mode != WINDOW_WINDOWED  # setter applies
		elif is_inside_tree():
			_apply_fullscreen()

# --- graphics (preset-controlled) ---
var graphics_preset: int = PRESET_HIGH:
	set(v):
		graphics_preset = clampi(v, PRESET_LOW, PRESET_CUSTOM)
var render_scale := 1.0:
	set(v): render_scale = clampf(v, 0.5, 1.0); _gfx_changed(true)
var antialiasing := 2:
	set(v): antialiasing = clampi(v, 0, 4); _gfx_changed(true)
var shadow_quality := 3:
	set(v): shadow_quality = clampi(v, 0, 4); _gfx_changed(true)
var ssao_quality := 2:
	set(v): ssao_quality = clampi(v, 0, 3); _gfx_changed(true)
var glow := true:
	set(v): glow = v; _gfx_changed(true)
var dof := true:
	set(v): dof = v; _gfx_changed(true)
var volumetrics := true:
	set(v): volumetrics = v; _gfx_changed(true)
var mist := true:
	set(v): mist = v; _gfx_changed(true)
var particle_density := 1.0:
	set(v): particle_density = clampf(v, 0.0, 1.5); _gfx_changed(true)
var decor_density := 1.0:
	set(v): decor_density = clampf(v, 0.25, 1.5); _gfx_changed(true)
## Corruption (blight) shader detail: 0 off, 1 crust only, 2 full. The Corruption autoload reads it
## (art-style role; cost in docs/team/art-style.md "Performance").
var blight_quality := 2:
	set(v): blight_quality = clampi(v, 0, 2); _gfx_changed(true)
# --- graphics (not part of presets) ---
var vsync := true:
	set(v): vsync = v; _gfx_changed(false)
var max_fps := 0:
	set(v): max_fps = maxi(v, 0); _gfx_changed(false)
var ui_scale := 1.0:
	set(v): ui_scale = clampf(v, 0.75, 1.5); _gfx_changed(false)

var _seen := {}  # String -> true
var _in_preset := false
var _loading := false
var _apply_queued := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node_added)
	load_settings()
	Game.show_damage_numbers = damage_numbers
	_apply_fullscreen()
	apply_graphics()
	# Rebound controls (ui/keybinds.gd). Deferred so actions other autoloads add exist by then.
	Keybinds.load_and_apply.call_deferred()


func _process(_delta: float) -> void:
	# Pick up changes made directly on Game (e.g. the debug F2 toggle).
	if Game.show_damage_numbers != damage_numbers:
		damage_numbers = Game.show_damage_numbers


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	_loading = true
	music_volume = clampf(float(cfg.get_value("audio", "music_volume", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx_volume", sfx_volume)), 0.0, 1.0)
	ambience_volume = clampf(float(cfg.get_value("audio", "ambience_volume", ambience_volume)), 0.0, 1.0)
	ui_volume = clampf(float(cfg.get_value("audio", "ui_volume", ui_volume)), 0.0, 1.0)
	text_speed = clampf(float(cfg.get_value("access", "text_speed", text_speed)), 0.25, 100.0)
	reduce_flashes = bool(cfg.get_value("access", "reduce_flashes", reduce_flashes))
	screen_shake = clampf(float(cfg.get_value("video", "screen_shake", screen_shake)), 0.0, 1.0)
	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
	damage_numbers = bool(cfg.get_value("game", "damage_numbers", damage_numbers))
	for key: String in GRAPHICS_KEYS:
		if cfg.has_section_key("graphics", key):
			var cur: Variant = get(key)
			var v: Variant = cfg.get_value("graphics", key, cur)
			match typeof(cur):
				TYPE_BOOL: set(key, bool(v))
				TYPE_INT: set(key, int(v))
				TYPE_FLOAT: set(key, float(v))
	_loading = false
	_seen.clear()
	var seen: Variant = cfg.get_value("bestiary", "seen", PackedStringArray())
	if seen is PackedStringArray or seen is Array:
		for id: Variant in seen:
			_seen[str(id)] = true


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "ambience_volume", ambience_volume)
	cfg.set_value("audio", "ui_volume", ui_volume)
	cfg.set_value("access", "text_speed", text_speed)
	cfg.set_value("access", "reduce_flashes", reduce_flashes)
	cfg.set_value("video", "screen_shake", screen_shake)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("game", "damage_numbers", damage_numbers)
	for key: String in GRAPHICS_KEYS:
		cfg.set_value("graphics", key, get(key))
	var seen := PackedStringArray()
	for id: String in _seen:
		seen.append(id)
	cfg.set_value("bestiary", "seen", seen)
	var err := cfg.save(PATH)
	if err != OK:
		push_warning("Settings: could not save %s (error %d)" % [PATH, err])


func mark_seen(id: StringName) -> void:
	var key := String(id)
	if key.is_empty() or _seen.has(key):
		return
	_seen[key] = true
	save_settings()


func is_seen(id: StringName) -> bool:
	return _seen.has(String(id))


# ---------------------------------------------------------------- graphics

## Sets every preset-controlled value from PRESETS[p] and applies them.
func apply_preset(p: int) -> void:
	if p < PRESET_LOW or p > PRESET_ULTRA:
		graphics_preset = PRESET_CUSTOM
		return
	_in_preset = true
	for key: String in PRESETS[p]:
		set(key, PRESETS[p][key])
	_in_preset = false
	graphics_preset = p
	_queue_apply()


## Applies all graphics settings now (viewport, window, every known scene node).
func apply_graphics() -> void:
	_apply_queued = false
	if not is_inside_tree():
		return
	GFX.apply(get_tree())
	graphics_changed.emit()


func _gfx_changed(preset_value: bool) -> void:
	if preset_value and not _in_preset and not _loading:
		graphics_preset = PRESET_CUSTOM
	_queue_apply()


func _queue_apply() -> void:
	if _loading or _apply_queued or not is_inside_tree():
		return
	_apply_queued = true
	apply_graphics.call_deferred()


func _on_node_added(node: Node) -> void:
	GFX.on_node_added(node)


func _apply_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var want := DisplayServer.WINDOW_MODE_WINDOWED
	match window_mode:
		WINDOW_BORDERLESS: want = DisplayServer.WINDOW_MODE_FULLSCREEN
		WINDOW_EXCLUSIVE: want = DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	var mode := DisplayServer.window_get_mode()
	if mode == want:
		return
	if want == DisplayServer.WINDOW_MODE_WINDOWED and mode != DisplayServer.WINDOW_MODE_FULLSCREEN \
			and mode != DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		return  # maximized/minimized windows count as windowed
	DisplayServer.window_set_mode(want)
