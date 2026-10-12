class_name DamageNumber
extends Label3D
## Floating damage figure. Use DamageNumber.spawn(amount, position[, color[, prefix]]) or, for a
## styled kind, DamageNumber.spawn_kind(amount, position, &"crit").
## Crisp heavy serif digits with a scorched outline that drift upward and fade. Styling (UI role):
##   normal  bone white            big (>= BIG_HIT)  hellfire gold, larger
##   crit    hellfire orange, larger, short pop + "!" suffix
##   player  blood red (damage the demon takes)       heal  venom green with "+"
##   holy    pale holy gold (smites, enemy holy damage) burn  ember orange, smaller (DoT ticks)
##   currency  shown with "+" (pickups)
## A non-white `color` passed to spawn() overrides the tint. At most MAX_ALIVE numbers exist at
## once; extra ones are dropped (big hits and crits always show) so swarms stay readable.

const OUTLINE := Color(0.06, 0.012, 0.008)
const PALE := Color(0.96, 0.9, 0.8)
const GOLD := Color(1.0, 0.76, 0.32)
## Tint for damage the demon takes (discrete hits only; contact ticks would spam).
const PLAYER_HIT := Color(1.0, 0.22, 0.16)
const CRIT := Color(1.0, 0.55, 0.12)
const HEAL := Color(0.62, 0.92, 0.38)
const HOLY := Color(1.0, 0.95, 0.72)
const BURN := Color(1.0, 0.48, 0.18)
const BIG_HIT := 30.0
const RISE := 0.9
const LIFE := 0.8
const MAX_ALIVE := 70

## kind -> [tint, font_size, outline_size, prefix, suffix, pop]
const KINDS := {
	&"normal": [Color.WHITE, 32, 8, "", "", false],
	&"crit": [CRIT, 44, 12, "", "!", true],
	&"player": [PLAYER_HIT, 34, 9, "-", "", false],
	&"heal": [HEAL, 30, 8, "+", "", false],
	&"holy": [HOLY, 34, 9, "", "", false],
	&"burn": [BURN, 26, 7, "", "", false],
	&"currency": [GOLD, 30, 8, "+", "", false],
}

static var _font: SystemFont
static var _alive := 0
## Perf: finished numbers are hidden and reused instead of freed (a Label3D + font setup per hit
## added up with crowds). Pooled nodes live in Game.world, so they go away with the run.
static var _pool: Array[DamageNumber] = []


## Numbers currently on screen (perf overlay).
static func active_count() -> int:
	return _alive


static func _obtain(at: Vector3) -> DamageNumber:
	while not _pool.is_empty():
		# QA: pooled nodes are freed with Game.world when a run ends; check before the typed assign.
		var v: Variant = _pool.pop_back()
		if not is_instance_valid(v):
			continue
		var p: DamageNumber = v
		if p.is_inside_tree() and p.get_parent() == Game.world:
			p.position = at
			p.scale = Vector3.ONE
			p.visible = true
			return p
	var n := DamageNumber.new()
	n.font = _get_font()
	n.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	n.no_depth_test = true
	n.outline_render_priority = 9
	n.pixel_size = 0.012
	n.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	Game.spawn(n, at)
	if not is_instance_valid(n) or not n.is_inside_tree():
		return null
	# Freed while showing (the world went away): release its slot.
	n.tree_exiting.connect(func() -> void:
		if n.visible:
			_alive = maxi(_alive - 1, 0))
	return n


static func _release(n: DamageNumber) -> void:
	if not is_instance_valid(n):
		return
	n.visible = false
	_alive = maxi(_alive - 1, 0)
	_pool.append(n)


static func _get_font() -> SystemFont:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(UIPalette.SERIF_NAMES)
		_font.font_weight = 700
		_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_font.allow_system_fallback = true
	return _font


static func spawn(amount: float, at: Vector3, color := Color.WHITE, prefix := "") -> void:
	var big := amount >= BIG_HIT
	_spawn(amount, at, color, prefix, "", 40 if big else 32, 10 if big else 8, false, big)


## Styled number (see the class doc for kinds). Unknown kinds fall back to &"normal".
static func spawn_kind(amount: float, at: Vector3, kind: StringName = &"normal") -> void:
	var k: Array = KINDS.get(kind, KINDS[&"normal"])
	var big := amount >= BIG_HIT
	var px: int = k[1]
	if big and kind == &"normal":
		px = 40
	_spawn(amount, at, k[0], k[3], k[4], px, k[2], k[5], big or kind == &"crit")


## A word instead of a number (kill confirms, "LAST STAND"): always shown, pops in. (gameplay)
static func spawn_text(word: String, at: Vector3, color: Color = GOLD, px: int = 40) -> void:
	_spawn(0.0, at, color, "", "", px, 12, true, true, word)


static func _spawn(amount: float, at: Vector3, color: Color, prefix: String, suffix: String,
		px: int, outline: int, pop: bool, important: bool, word := "") -> void:
	if not Game.show_damage_numbers or Game.world == null:
		return
	if _alive >= MAX_ALIVE and not important:
		return
	var n := _obtain(at + Vector3(randf_range(-0.25, 0.25), 0.15, randf_range(-0.15, 0.15)))
	if n == null:
		return
	n.text = word if word != "" else prefix + str(maxi(1, roundi(amount))) + suffix
	n.render_priority = 11 if important else 10
	n.font_size = px
	n.outline_size = outline
	var tint := color
	if color == Color.WHITE:
		tint = GOLD if amount >= BIG_HIT else PALE
	n.modulate = Color(tint, 0.0)
	n.outline_modulate = Color(OUTLINE, 0.0)
	_alive += 1

	var tw := n.create_tween()
	# Quick fade in, steady upward drift, gentle fade out. Crits pop in slightly oversized.
	tw.tween_property(n, "modulate:a", 1.0, 0.06)
	tw.parallel().tween_property(n, "outline_modulate:a", 0.9, 0.06)
	if pop:
		n.scale = Vector3.ONE * 1.45
		tw.parallel().tween_property(n, "scale", Vector3.ONE, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(n, "position:y", n.position.y + RISE, LIFE) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(n, "modulate:a", 0.0, LIFE * 0.5).from(1.0).set_delay(LIFE * 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(n, "outline_modulate:a", 0.0, LIFE * 0.5).from(0.9).set_delay(LIFE * 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(_release.bind(n))
