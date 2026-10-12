class_name Keybinds
## Rebindable controls: which actions the player may rebind, persistence of their overrides in
## user://keybinds.cfg, and short display labels for key hints ("Space", "LMB", "Pad A").
## Static helpers only; Settings._ready() calls Keybinds.load_and_apply() once at startup.
##
##   Keybinds.label(&"dash")                 # "Space" (first keyboard/mouse binding)
##   Keybinds.rebind(&"dash", event)          # replaces the keyboard/mouse binding, saves
##   Keybinds.reset(&"dash") / reset_all()    # back to project.godot defaults
##
## Only keyboard / mouse bindings are rebound; gamepad bindings stay as authored. Actions that do
## not exist in the InputMap (e.g. an ability action not added yet) are skipped silently.

const PATH := "user://keybinds.cfg"

## Rebindable actions in display order: [action, label]. Add your action here to make it show
## up in Settings > Controls (it must exist in the InputMap at runtime).
const ACTIONS := [
	[&"move_up", "Move up"],
	[&"move_down", "Move down"],
	[&"move_left", "Move left"],
	[&"move_right", "Move right"],
	[&"dash", "Dash"],
	[&"ability_1", "Ability I"],
	[&"ability_2", "Ability II"],
	[&"ability_3", "Ability III"],
	[&"ability_4", "Ability IV"],
	[&"map_overview", "Map & objectives"],
	[&"interact", "Interact"],
	[&"pause", "Pause"],
]

## Defaults captured before any override is applied: action -> Array[InputEvent].
static var _defaults := {}


## Loads user overrides and applies them to the InputMap. Safe to call more than once.
static func load_and_apply() -> void:
	_capture_defaults()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for entry: Array in ACTIONS:
		var action: StringName = entry[0]
		if not InputMap.has_action(action) or not cfg.has_section_key("keys", String(action)):
			continue
		var ev: Variant = cfg.get_value("keys", String(action))
		if ev is InputEvent:
			_set_primary(action, ev)


## Rebinds the action's keyboard/mouse binding to `event` and saves.
static func rebind(action: StringName, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		return
	_capture_defaults()
	_set_primary(action, event)
	save()


static func reset(action: StringName) -> void:
	_capture_defaults()
	if not _defaults.has(action):
		return
	InputMap.action_erase_events(action)
	for ev: InputEvent in _defaults[action]:
		InputMap.action_add_event(action, ev)
	save()


static func reset_all() -> void:
	for entry: Array in ACTIONS:
		reset(entry[0])


static func save() -> void:
	var cfg := ConfigFile.new()
	for entry: Array in ACTIONS:
		var action: StringName = entry[0]
		if not InputMap.has_action(action):
			continue
		var ev := primary_event(action)
		var def := _default_primary(action)
		# Only store real overrides so new project defaults still reach existing players.
		if ev and not (def and ev.is_match(def, true) and def.is_match(ev, true)):
			cfg.set_value("keys", String(action), ev)
	var err := cfg.save(PATH)
	if err != OK:
		push_warning("Keybinds: could not save %s (error %d)" % [PATH, err])


## The first keyboard or mouse event bound to `action` (null if none).
static func primary_event(action: StringName) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey or ev is InputEventMouseButton:
			return ev
	return null


## Short label for HUD key hints and the controls list ("" when unbound or unknown).
static func label(action: StringName) -> String:
	return event_label(primary_event(action))


static func event_label(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code := k.keycode
		# QA: the headless display server errors on the layout query (spammed every headless check).
		if k.physical_keycode != KEY_NONE and DisplayServer.get_name() != "headless":
			# Show what the key prints on the player's layout (Z on AZERTY for physical W, etc.).
			code = DisplayServer.keyboard_get_keycode_from_physical(k.physical_keycode)
		if code == KEY_NONE:
			code = k.physical_keycode
		var s := OS.get_keycode_string(code)
		match s:
			"Escape": return "Esc"
			"Space": return "Space"
			"Shift": return "Shift"
			"Ctrl": return "Ctrl"
		return s
	if ev is InputEventMouseButton:
		match (ev as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT: return "LMB"
			MOUSE_BUTTON_RIGHT: return "RMB"
			MOUSE_BUTTON_MIDDLE: return "MMB"
			MOUSE_BUTTON_XBUTTON1: return "M4"
			MOUSE_BUTTON_XBUTTON2: return "M5"
		return "Mouse %d" % (ev as InputEventMouseButton).button_index
	if ev is InputEventJoypadButton:
		return "Pad %d" % (ev as InputEventJoypadButton).button_index
	return ""


# ---------------------------------------------------------------- internals

static func _capture_defaults() -> void:
	for entry: Array in ACTIONS:
		var action: StringName = entry[0]
		if _defaults.has(action) or not InputMap.has_action(action):
			continue
		var evs: Array[InputEvent] = []
		for ev in InputMap.action_get_events(action):
			evs.append(ev.duplicate())
		_defaults[action] = evs


static func _default_primary(action: StringName) -> InputEvent:
	for ev: InputEvent in _defaults.get(action, []):
		if ev is InputEventKey or ev is InputEventMouseButton:
			return ev
	return null


## Replaces the first keyboard/mouse event (keeps secondary keys such as arrow keys and pads).
static func _set_primary(action: StringName, event: InputEvent) -> void:
	var evs := InputMap.action_get_events(action)
	var replaced := false
	InputMap.action_erase_events(action)
	for ev in evs:
		if not replaced and (ev is InputEventKey or ev is InputEventMouseButton):
			InputMap.action_add_event(action, event)
			replaced = true
		else:
			InputMap.action_add_event(action, ev)
	if not replaced:
		InputMap.action_add_event(action, event)
