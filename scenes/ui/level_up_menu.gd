extends CanvasLayer
## "Infernal Ascension": pauses the game and offers boons on tall dark cards. Handles several
## queued level-ups in a row. The layer is process_mode ALWAYS, so node tweens keep running
## while the tree is paused.

const CHOICES := 3
const CARD_SIZE := Vector2(272.0, 400.0)
## Brief delay so held inputs don't pick a card by accident.
const INPUT_GUARD := 0.45
const ICON_FRAME := 104.0

## Colours from the shared infernal palette (ui/palette.gd).
const PARCHMENT := UIPalette.BONE
const PALE_GOLD := UIPalette.BONE_BRIGHT
const GOLD := UIPalette.BRIMSTONE
const BRONZE := UIPalette.EMBER_DIM
const MUTED := UIPalette.ASH_TEXT

var _accepting := false
var _open_serial := 0
## Progression fate bar (reroll / banish charges). Built lazily under the cards.
var _fate_bar: HBoxContainer
var _reroll_button: Button
var _banish_button: Button
var _banish_mode := false

@onready var options_box: HBoxContainer = %Options
@onready var title: Label = %Title
@onready var subtitle: Label = %Subtitle
@onready var dim: ColorRect = $Root/Dim


func _ready() -> void:
	visible = false
	get_viewport().size_changed.connect(_fit_to_screen)
	# perf (docs/team/performance.md): the very first open() took ~40 ms (fonts, styles, icons
	# built on first use) while later ones take ~1 ms. Build one throwaway card set early.
	get_tree().create_timer(1.5, false).timeout.connect(_prewarm)


func _prewarm() -> void:
	if visible or Game.player == null or not is_instance_valid(Game.player):
		return
	var tmp: Array[Node] = []
	for option in Upgrades.roll(Game.player, CHOICES):
		var card := _make_card(option)
		card.modulate.a = 0.0
		options_box.add_child(card)
		tmp.append(card)
	await get_tree().process_frame
	for c in tmp:
		if is_instance_valid(c) and c.get_parent() == options_box:
			options_box.remove_child(c)
			c.queue_free()


## Number keys 1..3 pick a card directly (once the input guard has passed).
func _unhandled_input(event: InputEvent) -> void:
	if visible and _accepting and options_box.get_child_count() > 0 \
			and UINav.recover_focus(event, options_box.get_child(0) as Control):
		return  # keyboard / pad: a click on empty space left nothing focused
	if not visible or not _accepting or not event is InputEventKey or not event.pressed or event.echo:
		return
	var i := (event as InputEventKey).physical_keycode - KEY_1
	if i >= 0 and i < options_box.get_child_count():
		var card := options_box.get_child(i) as Button
		if card:
			card.grab_focus()
			card.pressed.emit()
			get_viewport().set_input_as_handled()


## Shrinks the whole offer when the window (or a large UI scale) leaves too little room.
func _fit_to_screen() -> void:
	var vbox := options_box.get_parent() as Control
	if vbox == null or not is_inside_tree():
		return
	var avail := get_viewport().get_visible_rect().size * Vector2(0.94, 0.9)
	var need := vbox.get_combined_minimum_size()
	var k := minf(1.0, minf(avail.x / maxf(need.x, 1.0), avail.y / maxf(need.y, 1.0)))
	vbox.pivot_offset = need * 0.5
	vbox.scale = Vector2(k, k)


func open() -> void:
	_open_serial += 1
	var serial := _open_serial
	var was_visible := visible
	Sfx.play(&"level_up", 0.0)
	_accepting = false
	var player := Game.player
	for c in options_box.get_children():
		options_box.remove_child(c)
		c.queue_free()
	var cards: Array[Button] = []
	var rolled := Upgrades.roll(player, CHOICES)
	for option in rolled:
		var card := _make_card(option)
		options_box.add_child(card)
		cards.append(card)
	_link_focus(cards)
	_update_fate_bar()
	visible = true
	_fit_to_screen.call_deferred()
	get_tree().paused = true
	_animate_in(cards, was_visible)

	await get_tree().create_timer(INPUT_GUARD, true).timeout
	if serial != _open_serial or not visible or cards.is_empty():
		return
	_accepting = true
	var first := cards[0]
	if not is_instance_valid(first):
		return
	var any_focused := false
	for c in cards:
		if is_instance_valid(c) and c.has_focus():
			any_focused = true
	if not any_focused:
		first.grab_focus()
	if Game.autopilot:
		# Bot pick (scripts/autopilot.gd): prefers abilities so automated runs exercise them.
		cards[clampi(Autopilot.pick_upgrade(rolled), 0, cards.size() - 1)].pressed.emit()


func _choose(option: UpgradeOption) -> void:
	if not _accepting or not visible:
		return
	if _banish_mode:
		_banish(option)
		return
	_accepting = false
	Sfx.play(&"select", 0.02)
	option.apply.call()
	if option.is_new:
		var hud := get_tree().get_first_node_in_group(&"hud")
		if hud and hud.has_method(&"toast"):
			hud.call(&"toast", "%s awakened" % option.title, option.color)
	var player := Game.player
	player.pending_level_ups -= 1
	if player.pending_level_ups > 0:
		open()
	else:
		visible = false
		get_tree().paused = false


# ---------------------------------------------------------------- animation

func _animate_in(cards: Array[Button], chained: bool) -> void:
	_center_pivot(title)
	_center_pivot.call_deferred(title)
	if not chained:
		dim.modulate.a = 0.0
		var dt := dim.create_tween()
		dt.tween_property(dim, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)

		title.modulate.a = 0.0
		subtitle.modulate.a = 0.0
		var tt := title.create_tween()
		tt.tween_property(title, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tt.parallel().tween_property(title, "scale", Vector2.ONE, 2.2).from(Vector2(1.06, 1.06)) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		var st := subtitle.create_tween()
		st.tween_interval(0.35)
		st.tween_property(subtitle, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)

	for i in cards.size():
		var card := cards[i]
		card.modulate.a = 0.0
		card.scale = Vector2(0.97, 0.97)
		var delay := (0.1 if chained else 0.35) + 0.14 * i
		var tw := card.create_tween()
		tw.tween_interval(delay)
		tw.tween_property(card, "modulate:a", 1.0, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(card, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		card.set_meta(&"scale_tw", tw)


func _center_pivot(c: Control) -> void:
	if is_instance_valid(c):
		c.pivot_offset = c.size * 0.5


## Gentle lift on focus: a slight scale and a warmer frame (the theme adds the ember glow).
func _hover(card: Button, on: bool) -> void:
	if not is_instance_valid(card) or not card.is_inside_tree() or card.is_queued_for_deletion():
		return
	if card.has_meta(&"scale_tw"):
		var old := card.get_meta(&"scale_tw") as Tween
		if old and old.is_valid():
			old.kill()
			card.modulate.a = 1.0
	var tw := card.create_tween()
	var to := Vector2(1.03, 1.03) if on else Vector2.ONE
	tw.tween_property(card, "scale", to, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	card.set_meta(&"scale_tw", tw)
	# QA: get_meta(key, null) errors when the key is missing (a null default counts as "no default").
	var frame := (card.get_meta(&"icon_frame") if card.has_meta(&"icon_frame") else null) as StyleBoxFlat
	if frame:
		frame.border_color = PALE_GOLD if on else Color(GOLD, 0.7)


# ---------------------------------------------------------------- cards

func _make_card(option: UpgradeOption) -> Button:
	var card := Button.new()
	card.theme_type_variation = &"CardButton"
	card.custom_minimum_size = CARD_SIZE
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.focus_mode = Control.FOCUS_ALL
	card.pivot_offset = CARD_SIZE * 0.5

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: StringName in [&"margin_left", &"margin_right"]:
		margin.add_theme_constant_override(side, 22)
	margin.add_theme_constant_override(&"margin_top", 18)
	margin.add_theme_constant_override(&"margin_bottom", 22)
	card.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 12)
	margin.add_child(box)

	# Sigil line: "NEW" for a power not yet held, otherwise the rank it rises to.
	var rank: String = str(option.get_meta(&"rank", ""))
	var sigil_text := "✦  NEW  ✦" if option.is_new else ("RANK  %s" % rank if rank != "" else "")
	var sigil := _label(sigil_text, 13, GOLD if option.is_new else MUTED)
	sigil.add_theme_constant_override(&"outline_size", 2)
	# Progression rarity (meta &"rarity", see Upgrades._roll_rarity): tier name + colour on the sigil.
	var tier := int(option.get_meta(&"rarity", 0))
	if tier > 0:
		# Pips + name, not just colour (colour-blind safe).
		sigil.text = "%s %s  ·  %s" % [UIPalette.rarity_mark(Rarity.id_of(tier)),
			Rarity.display_name(tier).to_upper(), sigil_text]
		sigil.add_theme_color_override(&"font_color", Rarity.color(tier))
		_tint_card(card, Rarity.color(tier), tier)
	box.add_child(sigil)

	# Framed icon.
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(ICON_FRAME, ICON_FRAME)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var fsb := _frame_style(option.color)
	frame.add_theme_stylebox_override(&"panel", fsb)
	card.set_meta(&"icon_frame", fsb)
	var tex := Icons.for_option(option)
	if tex:
		# Painted icon: fills the frame (its own dark vignette blends into the frame colour).
		fsb.set_content_margin_all(2.0)
		var art := TextureRect.new()
		art.texture = tex
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		art.custom_minimum_size = Vector2(ICON_FRAME, ICON_FRAME) - Vector2(4.0, 4.0)
		frame.add_child(art)
	else:
		var icon := GlyphIcon.new()  # painted in code, no emoji font
		icon.glyph = option.icon
		icon.color = option.color.lerp(PALE_GOLD, 0.5)
		icon.custom_minimum_size = Vector2(ICON_FRAME, ICON_FRAME) * 0.6
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		frame.add_child(icon)
	box.add_child(frame)

	var title_label := _label(option.title.to_upper(), 20, PALE_GOLD)
	title_label.theme_type_variation = &"TitleLabel"
	title_label.add_theme_font_size_override(&"font_size", 20)
	title_label.add_theme_constant_override(&"outline_size", 3)
	title_label.add_theme_constant_override(&"shadow_outline_size", 6)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title_label)

	var rule := HSeparator.new()
	rule.custom_minimum_size = Vector2(120.0, 0.0)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rule.modulate = Color(1, 1, 1, 0.8)
	box.add_child(rule)

	var desc := _label(option.description, 17, PARCHMENT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(desc)

	_ignore_mouse(margin)

	card.pressed.connect(_choose.bind(option))
	card.mouse_entered.connect(card.grab_focus)
	card.focus_entered.connect(_hover.bind(card, true))
	card.focus_entered.connect(Sfx.play.bind(&"ui_hover", 0.03, 0.0))
	card.focus_exited.connect(_hover.bind(card, false))
	return card


func _link_focus(cards: Array[Button]) -> void:
	var n := cards.size()
	for i in n:
		var c := cards[i]
		var left := cards[(i - 1 + n) % n]
		var right := cards[(i + 1) % n]
		c.focus_neighbor_left = c.get_path_to(left)
		c.focus_neighbor_right = c.get_path_to(right)
		c.focus_previous = c.get_path_to(left)
		c.focus_next = c.get_path_to(right)
		c.focus_neighbor_top = c.get_path_to(c)
		c.focus_neighbor_bottom = c.get_path_to(c)


## Rarer boons get a frame in their rarity colour and a stronger glow (theme styles cloned).
func _tint_card(card: Button, color: Color, tier: int) -> void:
	for st: StringName in [&"normal", &"hover", &"pressed", &"focus"]:
		var base := card.get_theme_stylebox(st) as StyleBoxFlat
		if base == null:
			continue
		var sb := base.duplicate() as StyleBoxFlat
		sb.border_color = color if st != &"normal" else Color(color, 0.75)
		if st != &"focus":
			sb.shadow_color = Color(color, 0.1 + 0.06 * tier)
			sb.shadow_size = 8 + 4 * tier
		card.add_theme_stylebox_override(st, sb)


func _frame_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.026, 0.022, 0.95).lerp(Color(color, 1.0), 0.12)
	sb.border_color = Color(GOLD, 0.7)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(1)
	sb.shadow_color = Color(color, 0.12)
	sb.shadow_size = 14
	return sb


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"InkLabel"
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text = text
	return l


func _ignore_mouse(node: Node) -> void:
	var c := node as Control
	if c:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)


# ---------------------------------------------------------------- reroll / banish (Progression)
# Charges come from Progression (meta upgrades "Second Augury" / "Anathema"). Reroll redraws the
# whole offer; banish arms a mode in which the next card picked is removed for the rest of the
# run (then the offer is redrawn). Neither consumes the pending level-up. Keys: R / B.

func _update_fate_bar() -> void:
	if _fate_bar == null:
		_fate_bar = HBoxContainer.new()
		_fate_bar.alignment = BoxContainer.ALIGNMENT_CENTER
		_fate_bar.add_theme_constant_override(&"separation", 18)
		options_box.get_parent().add_child(_fate_bar)
		_reroll_button = _fate_button(KEY_R, _reroll)
		_banish_button = _fate_button(KEY_B, _toggle_banish)
	_banish_mode = false
	_reroll_button.text = "↻  Reroll  (%d)   [R]" % Progression.rerolls_left
	_banish_button.text = "✕  Banish  (%d)   [B]" % Progression.banishes_left
	_reroll_button.visible = Progression.rerolls_left > 0
	_banish_button.visible = Progression.banishes_left > 0
	_fate_bar.visible = _reroll_button.visible or _banish_button.visible
	subtitle.modulate = Color.WHITE


func _fate_button(key: Key, action: Callable) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"GhostButton"
	b.focus_mode = Control.FOCUS_NONE  # keep keyboard/pad focus on the cards
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	var sc := Shortcut.new()
	sc.events = [ev]
	b.shortcut = sc
	b.pressed.connect(action)
	_fate_bar.add_child(b)
	return b


func _reroll() -> void:
	if not _accepting or not visible or not Progression.use_reroll():
		return
	Sfx.play(&"ui_click", 0.02)
	open()


func _toggle_banish() -> void:
	if not _accepting or not visible or Progression.banishes_left <= 0:
		return
	_banish_mode = not _banish_mode
	Sfx.play(&"ui_click", 0.02)
	_banish_button.text = ("Choose a boon to banish..." if _banish_mode
		else "✕  Banish  (%d)   [B]" % Progression.banishes_left)


func _banish(option: UpgradeOption) -> void:
	_banish_mode = false
	if not Progression.use_banish(option.title):
		return
	Sfx.play(&"ui_back", 0.02)
	var hud := get_tree().get_first_node_in_group(&"hud")
	if hud and hud.has_method(&"toast"):
		hud.call(&"toast", "%s banished" % option.title, Color("ff3b4f"))
	open()
