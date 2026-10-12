extends CanvasLayer
## Boss health bar, bottom-center, in the old soulslike manner: the boss's name in a serif face
## above a long, thin, square-edged dark bar; a deep crimson fill with a gold-touched highlight,
## and a pale gold "damage" segment that lingers, then drains after each blow. Damage dealt in a
## recent flurry is totalled at the right end of the name line. Fades in while a node in group
## "boss" exists, fades out otherwise. All styling is local (StyleBoxFlat overrides).

const IVORY := Color(0.88, 0.85, 0.78)
const FRAME := Color(0.42, 0.36, 0.24, 0.85)
const BACK := Color(0.035, 0.03, 0.03, 0.82)
const FILL := Color(0.52, 0.06, 0.06)
const FILL_RAGE := Color(0.66, 0.1, 0.05)
const FILL_TOP := Color(0.78, 0.28, 0.16, 0.55)
const LAG := Color(0.86, 0.7, 0.38, 0.9)
const BAR_MAX_WIDTH := 980.0
const BAR_WIDTH_FRAC := 0.62
const BAR_HEIGHT := 11.0
const INSET := 2.0
const BOTTOM_MARGIN := 46.0
const SIDE_MARGIN := 24.0
const LAG_HOLD := 0.7
const LAG_DRAIN := 0.32  # fraction of the bar per second (speeds up for big chunks)
const TALLY_TIME := 1.8
const FADE_SPEED := 1.6

## Holy palette (UI role proposal, see docs/team/objectives.md): radiant gold fill for the angel,
## the blood-red segment shows the damage the demon just dealt. Off = the original crimson bar.
@export var holy_style := false

static var _serif: SystemFont

var _box: VBoxContainer
var _name_row: HBoxContainer
var _name_label: Label
var _tally_label: Label
var _bar: Control
var _lag_panel: Panel
var _fill: Panel
var _fill_top: Panel
var _fill_style: StyleBoxFlat

var _alpha := 0.0
var _ratio := 1.0
var _lag := 1.0
var _hold := 0.0
var _flash := 0.0
var _boss_id := 0
var _enraged := false
var _last_hp := 0.0
var _tally := 0.0
var _tally_t := 0.0
var _phase_lines: Array = []  # HP ratios (float) where the boss changes phase
var _notches: Array[Panel] = []
# Active colours (crimson set or the holy set, chosen in _ready()).
var _c_fill := FILL
var _c_rage := FILL_RAGE
var _c_top := FILL_TOP
var _c_lag := LAG
var _c_frame := FRAME

@onready var root: Control = $Root


func _ready() -> void:
	if holy_style:
		_c_fill = Color(0.93, 0.76, 0.36)
		_c_rage = Color(1.0, 0.96, 0.82)
		_c_top = Color(1.0, 0.97, 0.86, 0.7)
		_c_lag = Color(0.7, 0.08, 0.05, 0.95)
		_c_frame = Color(0.85, 0.72, 0.42, 0.9)
	_build()
	_box.visible = false


func _process(delta: float) -> void:
	var b := get_tree().get_first_node_in_group(&"boss") as Enemy
	if b != null:
		if b.get_instance_id() != _boss_id:
			_boss_id = b.get_instance_id()
			_ratio = 1.0
			_lag = 1.0
			_hold = 0.0
			_tally = 0.0
			_tally_t = 0.0
			_last_hp = b.hp
			_name_label.text = b.data.display_name if b.data else "Herald"
		var hp_now := 0.0 if b.is_dying else maxf(b.hp, 0.0)
		if hp_now < _last_hp - 0.001:
			_tally += _last_hp - hp_now
			_tally_t = TALLY_TIME
			_hold = LAG_HOLD
			_flash = 1.0
		_last_hp = hp_now
		_ratio = clampf(hp_now / maxf(b.max_hp, 1.0), 0.0, 1.0)
		# Duck-typed so every boss script works (Boss, InquisitorBoss, ...): `is_enraged` pulses
		# the fill, phase_thresholds() (HP ratios) draws notches where its phases change.
		_enraged = b.get(&"is_enraged") == true
		var lines: Array = b.call(&"phase_thresholds") if b.has_method(&"phase_thresholds") else []
		if lines != _phase_lines:
			_set_phase_notches(lines)

	# Lingering damage segment.
	if _lag < _ratio:
		_lag = _ratio
	elif _hold > 0.0:
		_hold -= delta
	else:
		_lag = move_toward(_lag, _ratio, LAG_DRAIN * (1.0 + (_lag - _ratio) * 3.0) * delta)

	# Damage tally.
	if _tally_t > 0.0:
		_tally_t -= delta
		if _tally_t <= 0.0:
			_tally = 0.0
	_tally_label.text = str(roundi(_tally)) if _tally >= 1.0 else ""
	_tally_label.modulate.a = clampf(_tally_t / 0.4, 0.0, 1.0)

	_alpha = move_toward(_alpha, 1.0 if b != null else 0.0, delta * FADE_SPEED)
	_box.visible = _alpha > 0.001
	if not _box.visible:
		return
	_box.modulate.a = _alpha * _alpha * (3.0 - 2.0 * _alpha)
	_flash = maxf(_flash - delta * 5.0, 0.0)
	_layout()


func _layout() -> void:
	var w := minf(BAR_MAX_WIDTH, root.size.x * BAR_WIDTH_FRAC)
	w = minf(w, root.size.x - SIDE_MARGIN * 2.0)
	_bar.custom_minimum_size = Vector2(w, BAR_HEIGHT)
	_name_row.custom_minimum_size.x = w
	var bs := _box.get_combined_minimum_size()
	_box.size = bs
	# Rises a few pixels as it fades in.
	var rise := (1.0 - _alpha) * 10.0
	# Sit above the HUD's ability dock when it has slots.
	var hud := get_tree().get_first_node_in_group(&"hud")
	var reserved: float = hud.call(&"bottom_reserved") if hud and hud.has_method(&"bottom_reserved") else 0.0
	var bottom := maxf(BOTTOM_MARGIN, reserved + 8.0)
	_box.position = Vector2((root.size.x - bs.x) * 0.5, root.size.y - bottom - bs.y + rise)

	var inner := Vector2(w - INSET * 2.0, BAR_HEIGHT - INSET * 2.0)
	_lag_panel.position = Vector2(INSET, INSET)
	_lag_panel.size = Vector2(inner.x * _lag, inner.y)
	_lag_panel.visible = _lag > _ratio + 0.0005
	_fill.position = Vector2(INSET, INSET)
	_fill.size = Vector2(inner.x * _ratio, inner.y)
	_fill.visible = _ratio > 0.0005
	_fill_top.position = Vector2(INSET, INSET)
	_fill_top.size = Vector2(inner.x * _ratio, maxf(inner.y * 0.3, 1.0))
	_fill_top.visible = _fill.visible

	for i in _notches.size():
		_notches[i].position = Vector2(INSET + inner.x * float(_phase_lines[i]) - 1.0, -2.0)
		_notches[i].size = Vector2(2.0, BAR_HEIGHT + 4.0)
		# A notch the fill has already passed dims.
		_notches[i].modulate.a = 1.0 if _ratio > float(_phase_lines[i]) else 0.35

	var col := _c_fill
	if _enraged:
		col = _c_fill.lerp(_c_rage, 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.003))
	_fill_style.bg_color = col.lerp(Color(1.0, 0.85, 0.7), _flash * 0.35)


## Phase notches: thin gold ticks over the bar at each phase threshold.
func _set_phase_notches(lines: Array) -> void:
	_phase_lines = lines.duplicate()
	for n in _notches:
		n.queue_free()
	_notches.clear()
	for i in lines.size():
		var n := _panel(_style(Color(0.95, 0.82, 0.5, 0.95), 0, Color.TRANSPARENT))
		_bar.add_child(n)
		_notches.append(n)


# ---------------------------------------------------------------- construction

func _build() -> void:
	_box = VBoxContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override(&"separation", 4)
	root.add_child(_box)

	_name_row = HBoxContainer.new()
	_name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_name_row)
	_name_label = _make_label(24, HORIZONTAL_ALIGNMENT_LEFT)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.text = "Sariel, Herald of the Last Dawn"
	_name_row.add_child(_name_label)
	_tally_label = _make_label(20, HORIZONTAL_ALIGNMENT_RIGHT)
	_tally_label.add_theme_color_override(&"font_color", Color(0.9, 0.84, 0.7))
	_name_row.add_child(_tally_label)

	_bar = Control.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.custom_minimum_size = Vector2(BAR_MAX_WIDTH, BAR_HEIGHT)
	_box.add_child(_bar)

	var bg_style := _style(BACK, 1, _c_frame)
	bg_style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	bg_style.shadow_size = 6
	var bg := _panel(bg_style)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bar.add_child(bg)
	_lag_panel = _panel(_style(_c_lag, 0, Color.TRANSPARENT))
	_bar.add_child(_lag_panel)
	_fill_style = _style(_c_fill, 0, Color.TRANSPARENT)
	_fill = _panel(_fill_style)
	_bar.add_child(_fill)
	_fill_top = _panel(_style(_c_top, 0, Color.TRANSPARENT))
	_bar.add_child(_fill_top)


func _make_label(font_size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	l.add_theme_font_override(&"font", _serif_font())
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_color", IVORY)
	l.add_theme_color_override(&"font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	l.add_theme_constant_override(&"shadow_offset_x", 0)
	l.add_theme_constant_override(&"shadow_offset_y", 2)
	l.add_theme_constant_override(&"shadow_outline_size", 6)
	l.add_theme_constant_override(&"outline_size", 0)
	return l


func _panel(style: StyleBoxFlat) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override(&"panel", style)
	return p


## Square-cornered flat box (no cartoon pill).
func _style(bg: Color, border: int, border_color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(0)
	sb.anti_aliasing = false
	if border > 0:
		sb.set_border_width_all(border)
		sb.border_color = border_color
	return sb


static func _serif_font() -> SystemFont:
	if _serif == null:
		_serif = SystemFont.new()
		_serif.font_names = PackedStringArray(["Cinzel", "Trajan Pro", "EB Garamond", "Cormorant Garamond",
			"Garamond", "Palatino Linotype", "Book Antiqua", "Times New Roman", "serif"])
		_serif.font_weight = 500
		_serif.allow_system_fallback = true
	return _serif
