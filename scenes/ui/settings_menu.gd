extends CanvasLayer
## Settings overlay. Instance res://scenes/ui/settings_menu.tscn anywhere, call open(),
## and listen for `closed` (e.g. to give focus back). Changes apply live; saved on close.
## Esc / Start / ui_cancel also closes it. Works while the tree is paused (process ALWAYS).
## Three pages: General (audio buses/gameplay), Graphics (preset + individual options; rows are
## built in code from GFX_ROWS), Controls (key rebinding, scenes/ui/settings_controls.gd) and
## Access (text speed, flashes, shake, UI scale: scenes/ui/settings_access.gd).
## Q/E or LB/RB switch pages.

signal closed

const PARCHMENT := UIPalette.BONE
const PALE_GOLD := UIPalette.BONE_BRIGHT
const GOLD := UIPalette.BRIMSTONE
const PAGE_COUNT := 4
const GRABBER_SIZE := 18

const FPS_CHOICES := [30, 60, 90, 120, 144, 165, 240, 0]
const ON_OFF := ["Off", "On"]

## Graphics rows: [property, label, kind, data]
##   kind "cycle": data = Array of option names (index = value; bools use ON_OFF)
##   kind "slider": data = [min, max, step]
const GFX_ROWS := [
	["graphics_preset", "Quality preset", "cycle", ["Low", "Medium", "High", "Ultra", "Custom"]],
	["window_mode", "Display", "cycle", ["Windowed", "Borderless", "Exclusive"]],
	["render_scale", "Render scale", "slider", [0.5, 1.0, 0.05]],
	["antialiasing", "Anti-aliasing", "cycle", ["Off", "FXAA", "MSAA 2x", "MSAA 4x", "TAA"]],
	["shadow_quality", "Shadows", "cycle", ["Off", "Low", "Medium", "High", "Ultra"]],
	["ssao_quality", "Ambient occlusion", "cycle", ["Off", "Low", "Medium", "High"]],
	["glow", "Glow", "cycle", ON_OFF],
	["dof", "Depth of field", "cycle", ON_OFF],
	["volumetrics", "Light shafts & fog", "cycle", ON_OFF],
	["mist", "Ground mist", "cycle", ON_OFF],
	["particle_density", "Particles", "slider", [0.0, 1.5, 0.05]],
	["decor_density", "Decor density", "slider", [0.25, 1.5, 0.05]],
	["blight_quality", "Blight detail", "cycle", ["Off", "Low", "Full"]],
	["vsync", "VSync", "cycle", ON_OFF],
	["max_fps", "Frame limit", "cycle", ["30", "60", "90", "120", "144", "165", "240", "Unlimited"]],
	["ui_scale", "Interface scale", "slider", [0.75, 1.5, 0.05]],
]

static var _grabber_tex: Texture2D
static var _grabber_hi_tex: Texture2D

@onready var center: Control = %Center
@onready var title: Label = %Title
@onready var music_slider: HSlider = %Music
@onready var sound_slider: HSlider = %Sound
@onready var shake_slider: HSlider = %Shake
@onready var music_value: Label = %MusicValue
@onready var sound_value: Label = %SoundValue
@onready var shake_value: Label = %ShakeValue
@onready var damage_toggle: CheckButton = %DamageNumbers
@onready var fullscreen_toggle: CheckButton = %Fullscreen
@onready var done_button: Button = %Done
@onready var general_tab: Button = %GeneralTab
@onready var graphics_tab: Button = %GraphicsTab
@onready var general_panel: Control = %Panel
@onready var gfx_panel: Control = %GfxPanel
@onready var gfx_grid: GridContainer = %GfxGrid

## property -> {"control": Control, "value": Label, "kind": String, "data": Array}
var _gfx: Dictionary = {}
var _page := 0
var _controls_tab: Button
var _controls: SettingsControlsPage
var _access_tab: Button
var _access: SettingsAccessPage
var _ambience_slider: HSlider
var _ambience_value: Label
var _ui_slider: HSlider  # "Interface" volume (UI bus; music/sfx roles)
var _ui_value: Label


func _ready() -> void:
	visible = false
	for s: HSlider in [music_slider, sound_slider, shake_slider]:
		_style_slider(s)
		s.mouse_entered.connect(_hover)
		s.focus_entered.connect(_hover)
	for t: CheckButton in [damage_toggle, fullscreen_toggle]:
		_style_toggle(t)
		t.mouse_entered.connect(_hover)
		t.focus_entered.connect(_hover)
	for b: Button in [done_button, general_tab, graphics_tab]:
		b.mouse_entered.connect(_hover)
		b.focus_entered.connect(_hover)

	music_slider.value_changed.connect(_on_music_changed)
	sound_slider.value_changed.connect(_on_sound_changed)
	shake_slider.value_changed.connect(_on_shake_changed)
	damage_toggle.toggled.connect(_on_damage_toggled)
	fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)
	done_button.pressed.connect(close)
	general_tab.pressed.connect(_show_page.bind(0, true))
	graphics_tab.pressed.connect(_show_page.bind(1, true))

	_build_graphics_rows()
	Settings.graphics_changed.connect(_on_graphics_changed)
	_build_ambience_row()
	_build_ui_volume_row()
	_build_controls_page()
	_build_access_page()
	for t: Button in [general_tab, graphics_tab, _controls_tab, _access_tab]:
		t.theme_type_variation = &"TabButton"
		t.custom_minimum_size = Vector2(150, 40)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or (_controls and _controls.is_capturing()):
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif _is_page_key(event, -1):
		_show_page(posmod(_page - 1, PAGE_COUNT), true)
		get_viewport().set_input_as_handled()
	elif _is_page_key(event, 1):
		_show_page(posmod(_page + 1, PAGE_COUNT), true)
		get_viewport().set_input_as_handled()
	else:
		UINav.recover_focus(event, [general_tab, graphics_tab, _controls_tab, _access_tab][_page])


func _is_page_key(event: InputEvent, dir: int) -> bool:
	return UINav.page_dir(event) == dir


func open() -> void:
	_sync_from_settings()
	visible = true
	Sfx.play(&"ui_click")
	_show_page(_page, false)

	var tw := center.create_tween()
	tw.tween_property(center, "modulate:a", 1.0, 0.4).from(0.0).set_trans(Tween.TRANS_SINE)


func close() -> void:
	if not visible:
		return
	Settings.save_settings()
	visible = false
	Sfx.play(&"ui_back")
	closed.emit()


func _show_page(page: int, sound: bool) -> void:
	_page = page
	general_panel.visible = page == 0
	gfx_panel.visible = page == 1
	_controls.visible = page == 2
	_access.visible = page == 3
	var tabs: Array[Button] = [general_tab, graphics_tab, _controls_tab, _access_tab]
	for i in tabs.size():
		tabs[i].set_pressed_no_signal(page == i)
	if sound:
		Sfx.play(&"ui_click")
	# Wire focus between tabs/pages so pads can reach everything.
	var first_ctl: Control = music_slider
	var last_ctl: Control = fullscreen_toggle
	if page == 1:
		first_ctl = _gfx["graphics_preset"]["control"]
		last_ctl = _gfx["ui_scale"]["control"]
	elif page == 2:
		_controls.refresh()
		first_ctl = _controls.first_control if _controls.first_control else _controls.last_control
		last_ctl = _controls.last_control
	elif page == 3:
		_access.refresh()
		first_ctl = _access.first_control
		last_ctl = _access.last_control
	first_ctl.grab_focus()
	for t: Button in tabs:
		t.focus_neighbor_bottom = t.get_path_to(first_ctl)
	first_ctl.focus_neighbor_top = first_ctl.get_path_to(tabs[page])
	last_ctl.focus_neighbor_bottom = last_ctl.get_path_to(done_button)
	done_button.focus_neighbor_top = done_button.get_path_to(last_ctl)
	if visible:
		UIFit.scale_to_fit.call_deferred(center.get_child(0))


func _sync_from_settings() -> void:
	music_slider.set_value_no_signal(Settings.music_volume)
	sound_slider.set_value_no_signal(Settings.sfx_volume)
	_ambience_slider.set_value_no_signal(float(Settings.get(&"ambience_volume")))
	_ui_slider.set_value_no_signal(float(Settings.get(&"ui_volume")))
	shake_slider.set_value_no_signal(Settings.screen_shake)
	damage_toggle.set_pressed_no_signal(Settings.damage_numbers)
	fullscreen_toggle.set_pressed_no_signal(Settings.fullscreen)
	_update_labels()
	_sync_graphics()


func _update_labels() -> void:
	music_value.text = _pct(music_slider.value)
	sound_value.text = _pct(sound_slider.value)
	_ambience_value.text = _pct(_ambience_slider.value)
	_ui_value.text = _pct(_ui_slider.value)
	shake_value.text = _pct(shake_slider.value)


func _pct(v: float) -> String:
	return "%d%%" % roundi(v * 100.0)


func _hover() -> void:
	Sfx.play(&"ui_hover", 0.03)


# ---------------------------------------------------------------- extra rows / pages

## Third audio slider (the Ambience bus) inserted right after "Sound" in the general grid.
func _build_ambience_row() -> void:
	var grid := sound_slider.get_parent()
	var label := Label.new()
	label.theme_type_variation = &"InkLabel"
	label.add_theme_font_size_override(&"font_size", 21)
	label.text = "Ambience"
	_ambience_slider = HSlider.new()
	_ambience_slider.custom_minimum_size = Vector2(250, 26)
	_ambience_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ambience_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ambience_slider.max_value = 1.0
	_ambience_slider.step = 0.01
	_style_slider(_ambience_slider)
	_ambience_slider.value_changed.connect(_on_ambience_changed)
	_ambience_slider.mouse_entered.connect(_hover)
	_ambience_slider.focus_entered.connect(_hover)
	_ambience_value = sound_value.duplicate() as Label
	var at := sound_value.get_index() + 1
	grid.add_child(label)
	grid.move_child(label, at)
	grid.add_child(_ambience_slider)
	grid.move_child(_ambience_slider, at + 1)
	grid.add_child(_ambience_value)
	grid.move_child(_ambience_value, at + 2)


## Fourth audio slider (the UI bus: clicks, hovers, shop, toasts), right after "Ambience".
## Added by the music/sfx roles; mirrors _build_ambience_row.
func _build_ui_volume_row() -> void:
	var grid := sound_slider.get_parent()
	var label := Label.new()
	label.theme_type_variation = &"InkLabel"
	label.add_theme_font_size_override(&"font_size", 21)
	label.text = "Interface"
	_ui_slider = HSlider.new()
	_ui_slider.custom_minimum_size = Vector2(250, 26)
	_ui_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ui_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ui_slider.max_value = 1.0
	_ui_slider.step = 0.01
	_style_slider(_ui_slider)
	_ui_slider.value_changed.connect(_on_ui_volume_changed)
	_ui_slider.mouse_entered.connect(_hover)
	_ui_slider.focus_entered.connect(_hover)
	_ui_value = sound_value.duplicate() as Label
	var at := _ambience_value.get_index() + 1
	grid.add_child(label)
	grid.move_child(label, at)
	grid.add_child(_ui_slider)
	grid.move_child(_ui_slider, at + 1)
	grid.add_child(_ui_value)
	grid.move_child(_ui_value, at + 2)


func _on_ui_volume_changed(v: float) -> void:
	Settings.set(&"ui_volume", v)
	_update_labels()
	Sfx.play(&"ui_hover", 0.02)  # plays on the UI bus, so it previews the new level


func _build_controls_page() -> void:
	_controls_tab = Button.new()
	_controls_tab.toggle_mode = true
	_controls_tab.text = "Controls"
	_controls_tab.pressed.connect(_show_page.bind(2, true))
	_controls_tab.mouse_entered.connect(_hover)
	_controls_tab.focus_entered.connect(_hover)
	graphics_tab.get_parent().add_child(_controls_tab)
	_controls = SettingsControlsPage.new()
	_controls.visible = false
	gfx_panel.get_parent().add_child(_controls)
	_controls.get_parent().move_child(_controls, gfx_panel.get_index() + 1)
	_controls.rebound.connect(_on_rebound)


func _build_access_page() -> void:
	_access_tab = Button.new()
	_access_tab.toggle_mode = true
	_access_tab.text = "Access"
	_access_tab.tooltip_text = "Accessibility"
	_access_tab.pressed.connect(_show_page.bind(3, true))
	_access_tab.mouse_entered.connect(_hover)
	_access_tab.focus_entered.connect(_hover)
	graphics_tab.get_parent().add_child(_access_tab)
	_access = SettingsAccessPage.new()
	_access.visible = false
	_controls.add_sibling(_access)


func _on_rebound(_action: StringName) -> void:
	var hud := get_tree().get_first_node_in_group(&"hud")
	if hud and hud.get(&"widgets"):
		hud.get(&"widgets").call(&"refresh_key_hints")


func _on_ambience_changed(v: float) -> void:
	Settings.set(&"ambience_volume", v)
	_update_labels()
	Sfx.play(&"ui_hover", 0.02)


# ---------------------------------------------------------------- graphics page

func _build_graphics_rows() -> void:
	for row: Array in GFX_ROWS:
		var prop: String = row[0]
		var kind: String = row[2]
		var data: Array = row[3]
		var label := Label.new()
		label.text = row[1]
		label.theme_type_variation = &"InkLabel"
		label.add_theme_font_size_override(&"font_size", 20)
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		gfx_grid.add_child(label)

		var ctl: Control
		if kind == "slider":
			var s := HSlider.new()
			s.min_value = data[0]
			s.max_value = data[1]
			s.step = data[2]
			s.custom_minimum_size = Vector2(250, 26)
			s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_style_slider(s)
			s.value_changed.connect(_on_gfx_slider.bind(prop))
			if prop == "ui_scale":
				# Rescaling the UI under the cursor while dragging is jarring: apply on release.
				s.drag_ended.connect(func(_changed: bool) -> void: _commit_ui_scale(s.value))
			ctl = s
		else:
			var b := Button.new()
			b.custom_minimum_size = Vector2(250, 38)
			b.add_theme_font_size_override(&"font_size", 19)
			b.pressed.connect(_cycle.bind(prop, 1))
			b.gui_input.connect(_on_cycler_input.bind(prop))
			ctl = b
		ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ctl.mouse_entered.connect(_hover)
		ctl.focus_entered.connect(_hover)
		gfx_grid.add_child(ctl)

		var value := Label.new()
		value.custom_minimum_size = Vector2(70, 0)
		value.theme_type_variation = &"InkLabel"
		value.add_theme_color_override(&"font_color", PALE_GOLD)
		value.add_theme_font_size_override(&"font_size", 20)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		gfx_grid.add_child(value)
		var pad := Control.new()  # keeps values clear of the scrollbar
		pad.custom_minimum_size = Vector2(6, 0)
		gfx_grid.add_child(pad)
		_gfx[prop] = {"control": ctl, "value": value, "kind": kind, "data": data}


func _get_index(prop: String) -> int:
	var v: Variant = Settings.get(prop)
	if prop == "max_fps":
		var i := FPS_CHOICES.find(int(v))
		return i if i >= 0 else FPS_CHOICES.size() - 1
	if v is bool:
		return 1 if v else 0
	return int(v)


func _set_index(prop: String, i: int) -> void:
	if prop == "graphics_preset":
		Settings.apply_preset(i)
	elif prop == "max_fps":
		Settings.max_fps = FPS_CHOICES[i]
	elif Settings.get(prop) is bool:
		Settings.set(prop, i == 1)
	else:
		Settings.set(prop, i)


func _cycle(prop: String, dir: int) -> void:
	var opts: Array = _gfx[prop]["data"]
	var n := opts.size()
	if prop == "graphics_preset":
		n = 4  # "Custom" isn't selectable, it's what you get after tweaking
	var cur := _get_index(prop)
	var i := posmod(cur + dir, n)
	if cur >= n:
		i = 2 if dir > 0 else 1  # from Custom: step to High (or Medium)
	_set_index(prop, i)
	if prop == "window_mode":
		fullscreen_toggle.set_pressed_no_signal(Settings.fullscreen)
	_sync_graphics()
	Sfx.play(&"ui_click")


func _on_cycler_input(event: InputEvent, prop: String) -> void:
	var dir := 0
	if event.is_action_pressed(&"ui_left"):
		dir = -1
	elif event.is_action_pressed(&"ui_right"):
		dir = 1
	elif event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		dir = -1
	if dir != 0:
		_cycle(prop, dir)
		get_viewport().set_input_as_handled()


func _on_gfx_slider(v: float, prop: String) -> void:
	if prop == "ui_scale":
		var s: HSlider = _gfx[prop]["control"]
		if not s.has_focus() or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_gfx[prop]["value"].text = _pct(v)
			return  # dragging: commit on drag_ended
		_commit_ui_scale(v)
		return
	Settings.set(prop, v)
	_sync_graphics()
	Sfx.play(&"ui_hover", 0.02)


func _commit_ui_scale(v: float) -> void:
	Settings.ui_scale = v
	_sync_graphics()
	Sfx.play(&"ui_hover", 0.02)


func _on_graphics_changed() -> void:
	if visible:
		_sync_graphics()


func _sync_graphics() -> void:
	for prop: String in _gfx:
		var row: Dictionary = _gfx[prop]
		var value: Label = row["value"]
		if row["kind"] == "slider":
			var s: HSlider = row["control"]
			s.set_value_no_signal(float(Settings.get(prop)))
			value.text = _pct(s.value)
		else:
			var b: Button = row["control"]
			var opts: Array = row["data"]
			b.text = "‹   %s   ›" % opts[clampi(_get_index(prop), 0, opts.size() - 1)]
			value.text = ""


# ---------------------------------------------------------------- handlers

func _on_music_changed(v: float) -> void:
	Settings.music_volume = v
	_update_labels()
	Sfx.play(&"ui_hover", 0.02)


func _on_sound_changed(v: float) -> void:
	Settings.sfx_volume = v
	_update_labels()
	Sfx.play(&"ui_click", 0.02)  # preview at the new volume


func _on_shake_changed(v: float) -> void:
	Settings.screen_shake = v
	_update_labels()
	Sfx.play(&"ui_hover", 0.02)


func _on_damage_toggled(on: bool) -> void:
	Settings.damage_numbers = on
	Sfx.play(&"ui_click")


func _on_fullscreen_toggled(on: bool) -> void:
	Settings.fullscreen = on
	_sync_graphics()
	Sfx.play(&"ui_click")


# ---------------------------------------------------------------- styling

func _style_slider(s: HSlider) -> void:
	# Track and fill come from the theme; only the diamond grabber is drawn here.
	s.add_theme_icon_override(&"grabber", _get_grabber(false))
	s.add_theme_icon_override(&"grabber_highlight", _get_grabber(true))
	s.add_theme_icon_override(&"grabber_disabled", _get_grabber(false))


func _style_toggle(_t: CheckButton) -> void:
	pass  # the theme styles CheckButton (flat, parchment text, gold focus hairline)


## A small gold lozenge with a dark core.
static func _get_grabber(highlight: bool) -> Texture2D:
	if highlight and _grabber_hi_tex:
		return _grabber_hi_tex
	if not highlight and _grabber_tex:
		return _grabber_tex
	var img := Image.create_empty(GRABBER_SIZE, GRABBER_SIZE, false, Image.FORMAT_RGBA8)
	var c := (GRABBER_SIZE - 1) * 0.5
	var outer := c
	var edge := PALE_GOLD if highlight else GOLD
	var core := Color(0.12, 0.08, 0.05) if not highlight else Color(0.35, 0.18, 0.08)
	for y in GRABBER_SIZE:
		for x in GRABBER_SIZE:
			var d := absf(x - c) + absf(y - c)  # diamond distance
			var col := core if d < outer - 2.5 else edge
			col.a = clampf(outer + 0.5 - d, 0.0, 1.0)
			img.set_pixel(x, y, col)
	var tex := ImageTexture.create_from_image(img)
	if highlight:
		_grabber_hi_tex = tex
	else:
		_grabber_tex = tex
	return tex
