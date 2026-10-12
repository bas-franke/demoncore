extends Node3D
## Demon select: a ruined ritual chamber at night. Moonlight falls in a shaft through the broken
## ceiling, braziers and candles burn, and the demons wait on a semicircle of plinths around a
## glowing summoning circle. The chosen demon steps down from its plinth into the circle, under a
## pillar of ember-light, and roars. Everything except the `demons` list is built in code; the
## set pieces (altar, plinths, braziers, candles, pillars, window, chains, circle ring) are Blender
## models from tools/blender/models/menu/*.py (res://assets/models/menu/*.glb). The set itself is
## built by RitualChamber (ritual_chamber.gd); this script owns the camera, demons, UI and input.

## Every game start goes through the Basecamp Hell hub (runs start from its hellgate).
const BASECAMP_SCENE := "res://scenes/basecamp/basecamp.tscn"
const BESTIARY_SCENE := "res://scenes/ui/bestiary.tscn"
const SETTINGS_SCENE := "res://scenes/ui/settings_menu.tscn"
## Blender-made plinth (faces Godot +Z at yaw 0); the rest of the set is in RitualChamber.
const M_PLINTH := "res://assets/models/menu/plinth.glb"

const ARC_CENTER := RitualChamber.ARC_CENTER
const ARC_RADIUS := RitualChamber.ARC_RADIUS
## Total angle covered by the plinths (radians, ~140 degrees).
const ARC_SPAN := 2.44
const PLINTH_TOP := 0.5
## Where the chosen demon stands: the heart of the summoning circle.
const FRONT := RitualChamber.FRONT
const WALK_SPEED := 3.6
const CAM_POS := Vector3(1.0, 3.7, 11.0)
const CAM_LOOK := Vector3(0.45, 1.2, -0.4)
const CAM_FOV := 38.0

const TEXT := Color(0.86, 0.82, 0.74)
const TEXT_DIM := Color(0.6, 0.56, 0.5)
const ACCENT := Color(1.0, 0.5, 0.22)
const GOOD := Color(0.95, 0.75, 0.38)
const BAD := Color(0.72, 0.28, 0.26)
const PANEL_LINE := Color(0.75, 0.3, 0.12, 0.55)
const BAR_FILL := Color(0.62, 0.12, 0.07)
const BAR_EDGE := Color(1.0, 0.45, 0.18)

## [label, stat, base value, value at a full bar]
const STAT_BARS := [
	["Vitality", "max_hp", 100.0, 180.0],
	["Speed", "move_speed", 6.0, 8.0],
	["Might", "might", 1.0, 1.5],
	["Area", "area", 1.0, 1.5],
]

@export var demons: Array[DemonData] = []

var _index := 0
var _models: Array[DemonModel] = []
var _homes: Array[Vector3] = []
var _pos: Array[Vector3] = []
var _yaw: PackedFloat32Array = PackedFloat32Array()
var _arrived: Array[bool] = []
var _runes: Array[MeshInstance3D] = []
var _rune_dim: Array[Material] = []
var _rune_lit: Array[Material] = []
var _camera: Camera3D
var _cam_attrs: CameraAttributesPractical
## The set (environment, chamber, circle, fires); see RitualChamber.
var _chamber: RitualChamber
var _cam_kick := 0.0
var _t := 0.0
var _roar_timer := 8.0
var _starting := false
var _weapon_info := {}  # PackedScene -> [icon, name, description]

var _title: Label
var _hint: Label
var _hint_default := "←  →   or   A  D   choose        W  S   skin        Enter   begin"
var _hint_timer := 0.0
var _name_label: Label
var _title_label: Label
var _lore_label: Label
var _perk_label: Label
var _bars: Array[ProgressBar] = []
var _bar_values: Array[Label] = []
var _weapon_icon: Label
var _weapon_name: Label
var _weapon_desc: Label
## Skin chooser (characters-polish, scripts/characters/skin_picker.gd). W / S cycle skins.
var _skin_picker: SkinPicker
## Favoured ability school (Abilities.affinity_for), characters-polish.
var _affinity_label: Label
var _counter: Label
var _fade: ColorRect
var _bestiary: Node
var _settings_menu: Node


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	Sfx.play_music(&"menu")
	_chamber = RitualChamber.new()
	_chamber.name = &"Chamber"
	add_child(_chamber)
	_chamber.build()
	_build_camera()
	_build_plinths()
	_build_ui()
	if Game.selected_character is DemonData:
		var i := demons.find(Game.selected_character as DemonData)
		if i >= 0:
			_index = i
	if not demons.is_empty():
		# The chosen one starts in the circle (and roars as soon as the chamber fades in).
		_pos[_index] = FRONT
		_yaw[_index] = _face_yaw(FRONT, CAM_POS)
	_select(_index, false)
	_update_demons(0.0)
	_update_camera(0.0)
	var tw := _fade.create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------- camera

func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.fov = CAM_FOV
	_camera.near = 0.1
	_camera.far = 90.0
	_cam_attrs = CameraAttributesPractical.new()
	_cam_attrs.dof_blur_far_enabled = true
	_cam_attrs.dof_blur_far_distance = 14.0
	_cam_attrs.dof_blur_far_transition = 6.0
	_cam_attrs.dof_blur_near_enabled = false
	_cam_attrs.dof_blur_amount = 0.06
	_camera.attributes = _cam_attrs
	add_child(_camera)
	_camera.current = true


# ---------------------------------------------------------------- plinths & demons

func _build_plinths() -> void:
	var n := demons.size()
	for i in n:
		var a := _slot_angle(i)
		var home := ARC_CENTER + Vector3(sin(a), 0.0, -cos(a)) * ARC_RADIUS
		# Carved octagonal plinth (Blender model) whose step (model front, +Z) faces the circle.
		var to_front := Targeting.flat_dir(home, FRONT)
		var plinth := _chamber.prop(M_PLINTH, home, atan2(to_front.x, to_front.z))
		var d := demons[i]
		var glow := d.glow_color if d else Art.EMBER
		_rune_dim.append(Art.glow(glow, 0.5, true, 0.5))
		_rune_lit.append(Art.glow(glow, 2.2, true, 0.9))
		var rune := RitualChamber.find_mesh(plinth, "rune")
		if rune == null:
			# Model missing: a plain glowing ring so the selection still reads.
			rune = Art.part(self, Art.torus(0.9, 1.0), _rune_dim[i], home + Vector3(0.0, PLINTH_TOP + 0.005, 0.0),
					Vector3(0.72, 0.4, 0.72))
		rune.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rune.material_override = _rune_dim[i]
		_runes.append(rune)

		var m := DemonModel.new()
		add_child(m)
		m.build(d)
		_models.append(m)
		_homes.append(home)
		_pos.append(home)
		_yaw.append(_face_yaw(home, FRONT + Vector3(0.0, 0.0, 3.0)))
		_arrived.append(true)


func _slot_angle(i: int) -> float:
	var n := demons.size()
	if n <= 1:
		return 0.0
	return lerpf(-ARC_SPAN * 0.5, ARC_SPAN * 0.5, float(i) / float(n - 1))


## Yaw that makes a model at `from` (forward -Z) face `to`.
func _face_yaw(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return atan2(-d.x, -d.z)


# ---------------------------------------------------------------- ui

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	layer.add_child(margin)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 2)
	margin.add_child(col)

	_title = Label.new()
	_title.text = "SINBOUND"
	_title.theme_type_variation = &"TitleLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_title)
	var sub := _label("Rise, and unmake the Heavens.", 20, TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	var middle := HBoxContainer.new()
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(middle)
	var info := _build_info_panel()
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	middle.add_child(info)

	_hint = _label(_hint_default, 16, TEXT_DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_hint)

	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override("separation", 12)
	col.add_child(bottom)
	var left_pad := Control.new()
	left_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_pad.size_flags_stretch_ratio = 1.6
	bottom.add_child(left_pad)
	var prev := _button("‹", Vector2(56.0, 56.0), 30)
	prev.pressed.connect(func() -> void: _step(-1))
	bottom.add_child(prev)
	_counter = _label("", 18, TEXT)
	_counter.custom_minimum_size = Vector2(70.0, 0.0)
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_counter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(_counter)
	var next := _button("›", Vector2(56.0, 56.0), 30)
	next.pressed.connect(func() -> void: _step(1))
	bottom.add_child(next)
	var right_pad := Control.new()
	right_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(right_pad)
	var codex := _button("Codex", Vector2(140.0, 56.0), 20)
	codex.pressed.connect(_open_bestiary)
	bottom.add_child(codex)
	var settings := _button("Settings", Vector2(140.0, 56.0), 20)
	settings.pressed.connect(_open_settings)
	bottom.add_child(settings)
	var begin := _button("BEGIN", Vector2(200.0, 68.0), 30)
	begin.theme_type_variation = &"AccentButton"
	begin.pressed.connect(_begin)
	bottom.add_child(begin)

	_fade = ColorRect.new()
	_fade.color = Color(0.0, 0.0, 0.0, 1.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade)


func _build_info_panel() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"HudPanel"
	panel.custom_minimum_size = Vector2(430.0, 0.0)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	_name_label = _label("", 40, TEXT)
	box.add_child(_name_label)
	_title_label = _label("", 19, ACCENT)
	box.add_child(_title_label)
	box.add_child(_rule())
	_lore_label = _label("", 15, TEXT_DIM)
	_lore_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lore_label.custom_minimum_size = Vector2(390.0, 0.0)
	box.add_child(_lore_label)
	_perk_label = _label("", 16, TEXT)
	_perk_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_perk_label.custom_minimum_size = Vector2(390.0, 0.0)
	box.add_child(_perk_label)
	box.add_child(_gap(4.0))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	for row: Array in STAT_BARS:
		var l := _label(str(row[0]), 15, TEXT_DIM)
		l.custom_minimum_size = Vector2(78.0, 0.0)
		grid.add_child(l)
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.step = 0.001
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0.0, 12.0)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := StyleBoxFlat.new()
		fill.bg_color = BAR_FILL
		fill.border_color = BAR_EDGE
		fill.border_width_right = 2
		bar.add_theme_stylebox_override("fill", fill)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.04, 0.03, 0.03, 0.85)
		bg.border_color = Color(0.35, 0.3, 0.26, 0.6)
		bg.set_border_width_all(1)
		bar.add_theme_stylebox_override("background", bg)
		grid.add_child(bar)
		_bars.append(bar)
		var v := _label("", 15, TEXT)
		v.custom_minimum_size = Vector2(100.0, 0.0)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(v)
		_bar_values.append(v)

	box.add_child(_gap(6.0))
	box.add_child(_rule())
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 12)
	box.add_child(wrow)
	var icon_bg := PanelContainer.new()
	var isb := StyleBoxFlat.new()
	isb.bg_color = Color(0.06, 0.04, 0.035, 0.95)
	isb.border_color = BAR_EDGE.darkened(0.2)
	isb.set_border_width_all(2)
	isb.set_content_margin_all(6.0)
	icon_bg.add_theme_stylebox_override("panel", isb)
	icon_bg.custom_minimum_size = Vector2(58.0, 58.0)
	icon_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrow.add_child(icon_bg)
	_weapon_icon = Label.new()
	_weapon_icon.add_theme_font_size_override("font_size", 30)
	_weapon_icon.add_theme_color_override("font_color", ACCENT)
	_weapon_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_weapon_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_bg.add_child(_weapon_icon)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrow.add_child(text)
	text.add_child(_label("STARTING WEAPON", 12, ACCENT))
	_weapon_name = _label("", 21, TEXT)
	text.add_child(_weapon_name)
	_weapon_desc = _label("", 13, TEXT_DIM)
	_weapon_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_weapon_desc.custom_minimum_size = Vector2(300.0, 0.0)
	text.add_child(_weapon_desc)
	_affinity_label = _label("", 13, ACCENT)  # characters-polish: favoured school
	text.add_child(_affinity_label)
	box.add_child(_gap(4.0))
	box.add_child(_rule())
	_skin_picker = SkinPicker.new()
	box.add_child(_skin_picker)
	return panel


## "Favoured: Plague (+10% damage, offered 3x as often)" from Abilities.affinity_for(); "" if none.
func _affinity_text(d: DemonData) -> String:
	var abilities := get_node_or_null(^"/root/Abilities")
	if abilities == null or not abilities.has_method(&"affinity_for"):
		return ""
	var aff: Dictionary = abilities.call(&"affinity_for", DemonSkins.demon_id_of(d))
	if aff.is_empty():
		return ""
	return "Favoured school: %s  (+%d%% damage, offered %sx as often)" % [String(aff.get("school", "")),
		roundi(float(aff.get("damage", 0.1)) * 100.0), str(snappedf(float(aff.get("weight", 3.0)), 0.1)).trim_suffix(".0")]


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"InkLabel"
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _rule() -> Control:
	var r := ColorRect.new()
	r.color = PANEL_LINE
	r.custom_minimum_size = Vector2(0.0, 1.0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _gap(h: float) -> Control:
	var g := Control.new()
	g.custom_minimum_size = Vector2(0.0, h)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


func _button(text: String, min_size: Vector2, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE  # keep arrows / accept for _unhandled_input
	b.add_theme_font_size_override("font_size", font_size)
	b.mouse_entered.connect(func() -> void: Sfx.play(&"ui_hover", 0.05, -6.0))
	return b


# ---------------------------------------------------------------- selection

func _step(dir: int) -> void:
	Sfx.play(&"ui_click")
	_select(_index + dir)


func _select(i: int, announce: bool = true) -> void:
	if demons.is_empty() or _starting:
		return
	var prev := _index
	_index = wrapi(i, 0, demons.size())
	var d := demons[_index]
	if prev != _index:
		_cam_kick = 1.0
		_arrived[_index] = false
		if announce:
			Sfx.play(&"select", 0.04, -2.0)
	elif not announce:
		_arrived[_index] = false  # first frame: roar once the chamber fades in

	for k in _runes.size():
		_runes[k].material_override = _rune_lit[k] if k == _index else _rune_dim[k]

	_name_label.text = d.display_name
	_title_label.text = d.title.to_upper()
	_lore_label.text = "“%s”" % d.lore if d.lore != "" else ""
	_perk_label.text = d.perk_text
	# Progression unlocks: sealed demons can be viewed but not chosen.
	if not Progression.is_demon_unlocked(d):
		_perk_label.text = _sealed_text(d)
	else:
		_perk_label.text += "\n" + _mastery_text(d)
	_name_label.modulate = Color.WHITE if Progression.is_demon_unlocked(d) else Color(0.6, 0.55, 0.6)
	_counter.text = "%d / %d" % [_index + 1, demons.size()]
	_update_stats(d)
	_update_weapon(d)
	if _index < _models.size():
		_skin_picker.show_for(_models[_index])
	_affinity_label.text = _affinity_text(d)  # characters-polish
	_name_label.modulate.a = 0.0
	var nt := _name_label.create_tween()
	nt.tween_property(_name_label, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _update_stats(d: DemonData) -> void:
	for k in STAT_BARS.size():
		var row: Array = STAT_BARS[k]
		var base: float = row[2]
		var mod := d.get_stat_mod(StringName(str(row[1])))
		var value := base + mod
		var ratio := clampf(value / float(row[3]), 0.04, 1.0)
		var tw := _bars[k].create_tween()
		tw.tween_property(_bars[k], "value", ratio, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var shown := ""
		var delta_txt := ""
		match str(row[1]):
			"max_hp":
				shown = "%d" % roundi(value)
				delta_txt = "%+d" % roundi(mod)
			"move_speed":
				shown = "%.1f" % value
				delta_txt = "%+.1f" % mod
			_:
				shown = "%d%%" % roundi(value * 100.0)
				delta_txt = "%+d%%" % roundi(mod * 100.0)
		var l := _bar_values[k]
		if is_zero_approx(mod):
			l.text = shown
			l.add_theme_color_override("font_color", TEXT)
		else:
			l.text = "%s (%s)" % [shown, delta_txt]
			l.add_theme_color_override("font_color", GOOD if mod > 0.0 else BAD)


func _update_weapon(d: DemonData) -> void:
	var info := _get_weapon_info(d.starting_weapon)
	_weapon_icon.text = info[0]
	_weapon_name.text = info[1]
	_weapon_desc.text = info[2]


## [icon, name, description] read from a throwaway instance of the weapon scene (cached).
func _get_weapon_info(scene: PackedScene) -> Array:
	if scene == null:
		return ["—", "None", ""]
	if _weapon_info.has(scene):
		return _weapon_info[scene]
	var info: Array = ["?", "Unknown", ""]
	var node := scene.instantiate()
	var w := node as Weapon
	if w:
		info = [w.icon, w.display_name, w.description]
	if node:
		node.free()
	_weapon_info[scene] = info
	return info


func _begin() -> void:
	if _starting or demons.is_empty() or _overlay_open():
		return
	if not Progression.is_demon_unlocked(demons[_index]):
		Sfx.play(&"ui_back")
		_flash_hint(_sealed_text(demons[_index]).get_slice("\n", 0))
		return
	Game.selected_character = demons[_index]
	Sfx.play(&"select")
	Sfx.play(&"cast", 0.05, -3.0)
	_models[_index].play_cheer()
	_starting = true
	var tw := _fade.create_tween()
	tw.tween_interval(0.7)
	tw.tween_property(_fade, "color:a", 1.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(BASECAMP_SCENE))


## Progression mastery line: "Mastery III (40/160)  ·  Ravager's Fury I: ..." (or the next reward).
func _mastery_text(d: DemonData) -> String:
	@warning_ignore("static_called_on_instance")  # Progression is an autoload without a class_name
	var id := Progression.demon_id_of(d)
	var m := Progression.mastery_progress(id)
	var head := "Mastery %s" % Upgrades.roman(int(m.level))
	if not m.maxed:
		head += " (%d/%d)" % [int(m.into), int(m.need)]
	if int(m.signature_rank) > 0:
		return "%s  ·  %s" % [head, Progression.signature_text(id)]
	return "%s  ·  next: %s" % [head, m.next_reward] if String(m.next_reward) != "" else head


## Perk-panel text for a demon still locked by Progression (data/progression/unlocks.json).
func _sealed_text(d: DemonData) -> String:
	var u := Progression.get_demon_unlock(d)
	var cur := Progression.get_currency_def(StringName(String(u.get("currency", "sin_shards"))))
	return "SEALED.  Bind %s at the Soul Broker in Basecamp Hell (%s %d %s).\n%s" % [
		d.display_name, cur.icon, int(u.get("cost", 0)), cur.name, u.get("description", "")]


func _open_bestiary() -> void:
	Sfx.play(&"ui_click")
	if _bestiary == null or not is_instance_valid(_bestiary):
		var ps: PackedScene = null
		if ResourceLoader.exists(BESTIARY_SCENE):
			ps = load(BESTIARY_SCENE) as PackedScene
		if ps == null:
			_flash_hint("The Codex is sealed.")
			return
		_bestiary = ps.instantiate()
		add_child(_bestiary)
	if _bestiary.has_method(&"open"):
		_bestiary.call(&"open")


func _open_settings() -> void:
	Sfx.play(&"ui_click")
	if _settings_menu == null or not is_instance_valid(_settings_menu):
		var ps: PackedScene = null
		if ResourceLoader.exists(SETTINGS_SCENE):
			ps = load(SETTINGS_SCENE) as PackedScene
		if ps == null:
			_flash_hint("Settings are unavailable.")
			return
		_settings_menu = ps.instantiate()
		add_child(_settings_menu)
	if _settings_menu.has_method(&"open"):
		_settings_menu.call(&"open")


func _overlay_open() -> bool:
	for n: Node in [_bestiary, _settings_menu]:
		if n != null and is_instance_valid(n) and n.get(&"visible") == true:
			return true
	return false


func _flash_hint(text: String) -> void:
	_hint.text = text
	_hint_timer = 2.5


## Index of the demon closest to `screen_pos` (within a generous radius), or -1.
func _pick_demon(screen_pos: Vector2) -> int:
	var best := -1
	var best_d := 110.0
	for i in _models.size():
		var m := _models[i]
		for h: float in [0.6, 1.3, 2.0]:
			var p := m.global_position + Vector3(0.0, h, 0.0)
			if _camera.is_position_behind(p):
				continue
			var d := _camera.unproject_position(p).distance_to(screen_pos)
			if d < best_d:
				best_d = d
				best = i
	return best


func _unhandled_input(event: InputEvent) -> void:
	if _starting or _overlay_open():
		return
	if event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"move_left"):
		_step(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_right") or event.is_action_pressed(&"move_right"):
		_step(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_accept"):
		_begin()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				var hit := _pick_demon(mb.position)
				if hit == _index and _arrived[hit]:
					_models[hit].play_cheer()
					Sfx.play(&"cast", 0.05, -6.0)
				elif hit >= 0:
					Sfx.play(&"ui_click")
					_select(hit)
			MOUSE_BUTTON_WHEEL_UP:
				_step(-1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_step(1)


# ---------------------------------------------------------------- per-frame

func _process(delta: float) -> void:
	_t += delta
	if _title:
		# A slow, uneven ember pulse.
		var f := 0.88 + 0.08 * sin(_t * 1.3) + 0.04 * sin(_t * 4.7)
		_title.modulate = Color(1.0, f, f * 0.95, 1.0)
	if _hint:
		if _hint_timer > 0.0:
			_hint_timer -= delta
			if _hint_timer <= 0.0:
				_hint.text = _hint_default
		_hint.modulate.a = 0.55 + 0.25 * sin(_t * 2.0)
	_update_demons(delta)
	_update_lights()
	_update_camera(delta)

	if not _models.is_empty() and _arrived[_index] and not _starting:
		_roar_timer -= delta
		if _roar_timer <= 0.0:
			_roar_timer = randf_range(8.0, 12.0)
			_models[_index].play_cheer()


func _update_demons(delta: float) -> void:
	if _models.is_empty():
		return
	var sel_pos := _pos[_index]
	for i in _models.size():
		var m := _models[i]
		var target := FRONT if i == _index else _homes[i]
		var to := target - _pos[i]
		to.y = 0.0
		var dist := to.length()
		var ratio := 0.0
		if dist > 0.03:
			_pos[i] += to / dist * minf(dist, WALK_SPEED * delta)
			ratio = 0.62
			_yaw[i] = lerp_angle(_yaw[i], atan2(-to.x, -to.z), 1.0 - exp(-8.0 * delta))
			_arrived[i] = false
		else:
			_pos[i] = target
			var face_to := CAM_POS if i == _index else FRONT + Vector3(0.0, 0.0, 3.0)
			_yaw[i] = lerp_angle(_yaw[i], _face_yaw(_pos[i], face_to), 1.0 - exp(-4.0 * delta))
			if not _arrived[i]:
				_arrived[i] = true
				if i == _index and not _starting:
					m.play_cheer()
					Sfx.play(&"cast", 0.05, -5.0)
					_roar_timer = randf_range(8.0, 12.0)
		# Up on the plinth near home, on the floor once stepped off.
		var hd := Vector2(_pos[i].x - _homes[i].x, _pos[i].z - _homes[i].z).length()
		var y := PLINTH_TOP * (1.0 - smoothstep(0.5, 1.2, hd))
		m.position = Vector3(_pos[i].x, y, _pos[i].z)
		m.rotation.y = _yaw[i]
		# The others turn their heads toward the chosen one.
		if i != _index:
			var d := sel_pos - _pos[i]
			m.look_yaw = clampf(wrapf(atan2(-d.x, -d.z) - _yaw[i], -PI, PI) * 0.7, -0.9, 0.9)
		else:
			m.look_yaw = 0.0
		m.animate(delta, ratio)


## Light flicker / pulsing lives in the chamber (RitualChamber.update_lights).
func _update_lights() -> void:
	_chamber.update_lights(_t)


func _update_camera(delta: float) -> void:
	_cam_kick = move_toward(_cam_kick, 0.0, delta * 1.4)
	var sway := Vector3(sin(_t * 0.21) * 0.3, sin(_t * 0.17) * 0.12, cos(_t * 0.13) * 0.18)
	var look := CAM_LOOK + Vector3(sin(_t * 0.19) * 0.06, sin(_t * 0.23) * 0.03, 0.0)
	var pos := CAM_POS + sway
	# Slow push-in when a new demon is chosen.
	var k := sin(_cam_kick * PI) * 0.5
	pos += (look - pos).normalized() * k
	_camera.look_at_from_position(pos, look)
	_cam_attrs.dof_blur_far_distance = pos.distance_to(FRONT) + 4.0
