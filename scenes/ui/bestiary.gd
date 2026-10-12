extends CanvasLayer
## Bestiary (the record of the Host): one card per EnemyData found in res://data/enemies/ and res://data/bosses/.
## Enemies the player has met (Settings.is_seen(id)) get a slowly spinning live 3D preview
## (own SubViewport, camera and light); the rest show a dark "???" silhouette.
##
##   var b := preload("res://scenes/ui/bestiary.tscn").instantiate()
##   add_child(b)
##   b.open()        # emits `closed` when dismissed. Never touches get_tree().paused.

signal closed

const DATA_DIRS: Array[String] = ["res://data/enemies/", "res://data/bosses/"]
const CARD_SIZE := Vector2(252.0, 0.0)
const PREVIEW_SIZE := Vector2i(224, 168)
const PARCHMENT := Color("d9cdb2")
const PALE_GOLD := Color("e8d6a6")
const GOLD := Color("c8a862")
const BRONZE := Color("6e5a3a")
const MUTED := Color("9c917c")
const SEEN_BG := Color(0.085, 0.075, 0.068)
const BOSS_BG := Color(0.12, 0.05, 0.04)
const UNSEEN_BG := Color(0.05, 0.045, 0.04)
const SILHOUETTE := Color(0.012, 0.01, 0.01)
const SPIN_SPEED := 0.55
## Preview camera pitch (radians looking down) and field of view.
const PREVIEW_PITCH := 0.38
const PREVIEW_FOV := 30.0

# Each: {"spin": Node3D, "model": Node3D, "viewport": SubViewport}
var _previews: Array[Dictionary] = []
var _env: Environment
var _silhouette_mat: StandardMaterial3D
var _shadow_mat: StandardMaterial3D

@onready var root: Control = $Root
@onready var panel: Control = %Panel
@onready var grid: GridContainer = %Grid
@onready var counter: Label = %Counter
@onready var close_button: Button = %Close
@onready var title: Label = %Title


func _ready() -> void:
	visible = false
	close_button.pressed.connect(close)
	get_viewport().size_changed.connect(_update_columns)


func open() -> void:
	_rebuild()
	visible = true
	_update_columns()
	close_button.grab_focus()
	var tw := panel.create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.5).from(0.0).set_trans(Tween.TRANS_SINE)


func close() -> void:
	if not visible:
		return
	visible = false
	_clear()
	Sfx.play(&"ui_back")
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		close()
	elif event.is_action_pressed(&"ui_down", true) or event.is_action_pressed(&"ui_up", true) \
			or UINav.page_dir(event) != 0:
		# Keyboard / pad scrolling (the cards aren't focusable; Close keeps focus). UI role.
		var scroll := grid.get_parent().get_parent() as ScrollContainer
		if scroll:
			var step := 120 if (event.is_action_pressed(&"ui_down", true) or UINav.page_dir(event) > 0) else -120
			if UINav.page_dir(event) != 0:
				step *= 4
			scroll.scroll_vertical += step
	# Swallow everything else so the screen underneath doesn't react while we're open.
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	for p in _previews:
		var spin: Node3D = p["spin"]
		spin.rotation.y = fmod(spin.rotation.y + SPIN_SPEED * delta, TAU)
		var m := p["model"] as EnemyModel
		if m:
			m.animate(delta, 0.35, EnemyModel.State.MOVING)


# ---------------------------------------------------------------- data

## Every EnemyData in DATA_DIRS: [{"data": EnemyData, "path": String, "boss": bool}], regular
## enemies first (weakest first), then bosses.
static func find_enemy_data() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var known := {}
	for dir_path: String in DATA_DIRS:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for f: String in dir.get_files():
			# Exported builds list converted resources as "*.tres.remap"; load() takes the original path.
			var file := f.trim_suffix(".remap")
			if not (file.ends_with(".tres") or file.ends_with(".res")):
				continue
			var path := dir_path.path_join(file)
			if known.has(path) or not ResourceLoader.exists(path):
				continue
			known[path] = true
			var d := load(path) as EnemyData
			if d == null:
				continue
			out.append({"data": d, "path": path, "boss": dir_path.contains("bosses")})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["boss"] != b["boss"]:
			return not a["boss"]
		var da: EnemyData = a["data"]
		var db: EnemyData = b["data"]
		if not is_equal_approx(da.max_hp, db.max_hp):
			return da.max_hp < db.max_hp
		return str(a["path"]) < str(b["path"]))
	return out


## EnemyData.id if set (read dynamically so this works before/after the field exists),
## else the file name ("cucumber.tres" -> &"cucumber").
static func enemy_id(d: EnemyData, path: String) -> StringName:
	var v: Variant = d.get(&"id")
	if v != null and str(v) != "":
		return StringName(str(v))
	return StringName(path.get_file().get_basename())


static func behavior_text(d: EnemyData) -> String:
	match int(d.behavior):
		EnemyData.Behavior.CHASE:
			return "Pursuer"
		EnemyData.Behavior.SHOOT:
			return "Smiter"
		EnemyData.Behavior.CHARGE:
			return "Zealot"
		EnemyData.Behavior.HOP:
			return "Leaper"
		EnemyData.Behavior.SLAM:
			return "Crusher"
	return "Unknown"


# ---------------------------------------------------------------- cards

func _rebuild() -> void:
	_clear()
	var entries := find_enemy_data()
	var seen_count := 0
	for i in entries.size():
		var e := entries[i]
		var d: EnemyData = e["data"]
		var seen := Settings.is_seen(enemy_id(d, e["path"]))
		if seen:
			seen_count += 1
		_add_card(d, seen, e["boss"], i)
	counter.text = "Witnessed  %d / %d" % [seen_count, entries.size()]
	if entries.is_empty():
		var l := _ink_label("No record of the Host was found.", 20)
		grid.add_child(l)


func _clear() -> void:
	_previews.clear()
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()


func _update_columns() -> void:
	if grid == null:
		return
	var w := get_viewport().get_visible_rect().size.x - 160.0
	grid.columns = clampi(int(w / (CARD_SIZE.x + 16.0)), 1, 6)


func _add_card(d: EnemyData, seen: bool, boss: bool, index: int) -> void:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(card)
	var base := root.get_theme_stylebox(&"panel", &"PanelContainer")
	var sb := base.duplicate() as StyleBoxFlat
	if sb:
		sb.set_content_margin_all(12.0)
		sb.shadow_size = 8
		if boss:
			sb.border_color = GOLD
			sb.bg_color = Color(0.07, 0.035, 0.03, 0.9)
		elif not seen:
			sb.border_color = Color(BRONZE, 0.5)
			sb.bg_color = Color(0.03, 0.026, 0.024, 0.85)
		card.add_theme_stylebox_override(&"panel", sb)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_theme_constant_override(&"separation", 6)
	card.add_child(box)

	# Preview frame (rounded backdrop + 3D viewport + optional "???" overlay).
	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = SEEN_BG if seen else UNSEEN_BG
	if boss and seen:
		fsb.bg_color = BOSS_BG
	fsb.border_color = Color(GOLD, 0.6) if boss else Color(BRONZE, 0.8)
	fsb.set_border_width_all(1)
	fsb.set_corner_radius_all(1)
	fsb.anti_aliasing = true
	fsb.set_content_margin_all(0.0)
	frame.add_theme_stylebox_override(&"panel", fsb)
	box.add_child(frame)

	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(PREVIEW_SIZE)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.size = PREVIEW_SIZE
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(vp)
	_fill_preview(vp, d, seen)

	if not seen:
		var q := Label.new()
		q.text = "???"
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		q.theme_type_variation = &"TitleLabel"
		q.add_theme_font_size_override(&"font_size", 44)
		q.add_theme_color_override(&"font_color", Color(MUTED, 0.6))
		q.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(q)

	if boss:
		var badge_row := HBoxContainer.new()
		badge_row.alignment = BoxContainer.ALIGNMENT_CENTER
		badge_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var badge := PanelContainer.new()
		badge.theme_type_variation = &"Badge"
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bl := _ink_label("GREAT FOE", 13)
		bl.add_theme_color_override(&"font_color", GOLD)
		badge.add_child(bl)
		badge_row.add_child(badge)
		box.add_child(badge_row)

	var name_label := _ink_label((d.display_name if seen else "???").to_upper(), 19)
	name_label.theme_type_variation = &"TitleLabel"
	name_label.add_theme_font_size_override(&"font_size", 19)
	name_label.add_theme_constant_override(&"outline_size", 3)
	name_label.add_theme_constant_override(&"shadow_outline_size", 6)
	name_label.add_theme_color_override(&"font_color", PALE_GOLD if seen else MUTED)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(name_label)

	var flavor_text := d.flavor_text if seen else "Not yet witnessed. Endure, and it shall find thee."
	if flavor_text == "":
		flavor_text = "Of this one, little is written."
	var flavor := _ink_label(flavor_text, 15)
	flavor.theme_type_variation = &"LoreLabel"
	flavor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	flavor.custom_minimum_size = Vector2(CARD_SIZE.x - 30.0, 0.0)
	flavor.add_theme_color_override(&"font_color", MUTED)
	box.add_child(flavor)

	var stats := HBoxContainer.new()
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_theme_constant_override(&"separation", 6)
	box.add_child(stats)
	if seen:
		stats.add_child(_chip("HP %d" % roundi(d.max_hp), Color("d0644f")))
		stats.add_child(_chip("SPD %.1f" % d.speed, PARCHMENT))
		stats.add_child(_chip(behavior_text(d), PALE_GOLD))
	else:
		stats.add_child(_chip("HP ?", MUTED))
		stats.add_child(_chip("SPD ?", MUTED))
		stats.add_child(_chip("???", MUTED))

	# Slow staggered fade-in.
	card.modulate.a = 0.0
	var tw := card.create_tween()
	tw.tween_interval(0.05 * index)
	tw.tween_property(card, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE)


func _chip(text: String, fg: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.45)
	sb.border_color = Color(BRONZE, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(1)
	sb.anti_aliasing = true
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 1.0
	sb.content_margin_bottom = 1.0
	chip.add_theme_stylebox_override(&"panel", sb)
	var l := _ink_label(text, 13)
	l.add_theme_color_override(&"font_color", fg)
	chip.add_child(l)
	return chip


func _ink_label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"InkLabel"
	l.add_theme_font_size_override(&"font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ---------------------------------------------------------------- 3D previews

func _fill_preview(vp: SubViewport, d: EnemyData, seen: bool) -> void:
	var cam := Camera3D.new()
	cam.fov = PREVIEW_FOV
	cam.near = 0.05
	cam.far = 100.0
	cam.environment = _get_env()
	vp.add_child(cam)
	cam.current = true

	var key := DirectionalLight3D.new()
	key.basis = Basis.looking_at(Vector3(-0.45, -0.75, -0.55).normalized())
	key.light_energy = 1.25
	key.light_color = Color(1.0, 0.9, 0.72)
	vp.add_child(key)

	var spin := Node3D.new()
	spin.rotation.y = PI * 0.85  # models face -Z; start roughly facing the camera
	vp.add_child(spin)
	var holder := Node3D.new()
	spin.add_child(holder)

	var model: Node3D = null
	if d.model:
		var inst := d.model.instantiate()
		model = inst as Node3D
		if model == null and inst:
			inst.free()
	if model == null:
		model = Node3D.new()
		Art.part(model, Art.box(), Art.mat(Art.IVORY), Vector3(0.0, 0.4, 0.0), Vector3.ONE * 0.8)
	holder.add_child(model)  # EnemyModel builds its geometry in _ready
	if not seen:
		_silhouette(model)
	else:
		# Same pale-gold faction rim the angels wear in a run (docs/team/art-style.md).
		ArtStyle.apply_faction(model, ArtStyle.Faction.HOLY)

	# Frame the model: centre it on the spin axis and back the camera off to fit it.
	var box := _model_aabb(model, holder)
	var center := box.get_center()
	holder.position = -center
	var radius := maxf(box.size.length() * 0.5, 0.3)
	var dist := radius / sin(deg_to_rad(PREVIEW_FOV * 0.5)) * 0.92
	cam.position = Vector3(0.0, sin(PREVIEW_PITCH), cos(PREVIEW_PITCH)) * dist
	cam.basis = Basis.looking_at(-cam.position.normalized())

	# Soft contact shadow blob under the model.
	var blob := MeshInstance3D.new()
	blob.mesh = Art.cylinder()
	blob.material_override = _get_shadow_mat()
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blob.scale = Vector3(box.size.x * 0.9 + 0.2, 0.01, box.size.z * 0.9 + 0.2)
	blob.position.y = box.position.y - center.y + 0.005
	spin.add_child(blob)

	_previews.append({"spin": spin, "model": model, "viewport": vp})


## Merged AABB of every visual under `model`, in `space`'s local coordinates.
func _model_aabb(model: Node3D, space: Node3D) -> AABB:
	var inv := space.global_transform.affine_inverse()
	var out := AABB()
	var first := true
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var vi := n as VisualInstance3D
		if vi == null or not vi.visible:
			continue
		var b: AABB = (inv * vi.global_transform) * vi.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	if first:
		return AABB(Vector3(-0.5, 0.0, -0.5), Vector3.ONE)
	return out


## Flat black silhouette: every mesh gets one dark unshaded material; text/particles hide.
func _silhouette(n: Node) -> void:
	if n is Label3D or n is SpriteBase3D or n is GPUParticles3D or n is CPUParticles3D:
		(n as Node3D).visible = false
	elif n is GeometryInstance3D:
		(n as GeometryInstance3D).material_override = _get_silhouette_mat()
	for c in n.get_children():
		_silhouette(c)


func _get_env() -> Environment:
	if _env == null:
		_env = Environment.new()
		_env.background_mode = Environment.BG_CLEAR_COLOR
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_env.ambient_light_color = Color(0.7, 0.72, 0.85)
		_env.ambient_light_energy = 0.35
		_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	return _env


func _get_silhouette_mat() -> StandardMaterial3D:
	if _silhouette_mat == null:
		_silhouette_mat = StandardMaterial3D.new()
		_silhouette_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_silhouette_mat.albedo_color = SILHOUETTE
	return _silhouette_mat


func _get_shadow_mat() -> StandardMaterial3D:
	if _shadow_mat == null:
		_shadow_mat = StandardMaterial3D.new()
		_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shadow_mat.albedo_color = Color(0, 0, 0, 0.45)
	return _shadow_mat
