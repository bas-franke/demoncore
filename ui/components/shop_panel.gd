class_name ShopPanel
extends CanvasLayer
## Reusable shopkeeper screen: header with the keeper's name and the wallet, optional category
## tabs, a responsive grid of item cards, a detail pane with a Buy button. Data-driven and
## decoupled: it never touches Meta/Progression itself, you pass callables.
##
##   var shop: ShopPanel = preload("res://ui/components/shop_panel.tscn").instantiate()
##   add_child(shop)
##   shop.open({
##       "title": "Mother Marrow", "subtitle": "Flesh is only a first draft.",
##       "currency_glyph": "◈", "currency_name": "Souls", "currency_color": UIPalette.SOUL,
##       "currency": func() -> int: return Meta.souls,         # or a plain int
##       "items": func() -> Array: return build_items(),        # or a plain Array (see below)
##       "buy": func(id: String) -> bool: return Meta.buy(id),  # true = bought
##       "pause": false,                                         # pause the tree while open
##   })
##   shop.closed.connect(...)
##
## Item dictionary (only "id" and "name" are required):
##   id, name, description, glyph ("✦"), icon (Texture2D or res:// path), color (Color),
##   cost (int, <0 hides the price), level (int), max_level (int, 0 = one-off purchase),
##   rarity ("common".."legendary"/"cursed"), category (String, makes tabs),
##   locked (bool), locked_reason (String), owned (bool, one-off already bought),
##   effect_now / effect_next (Strings shown as "Now" -> "Next"), flavor (String, slanted line).
## Per-item currency (wares priced in something other than the main wallet):
##   currency_glyph, currency_color, currency_name, and either currency_amount (int: what the player
##   holds of it) or affordable (bool). Extra header wallets: config "wallets": [{glyph, color, name,
##   amount (int or Callable)}].
## With "items"/"currency" given as callables the panel refreshes itself after every purchase;
## with plain values call refresh(items, currency) yourself (e.g. from `purchase_requested`).

signal purchase_requested(item_id: String)
signal purchased(item_id: String)
signal purchase_failed(item_id: String, reason: String)
signal closed

const CARD_SIZE := Vector2(196.0, 132.0)
const PANEL_MAX := Vector2(1180.0, 760.0)
const PANEL_FRAC := Vector2(0.92, 0.88)

var _cfg: Dictionary = {}
var _items: Array = []
var _currency := 0
var _category := ""
var _selected_id := ""
var _cards := {}  # item id (String) -> Button
var _pause_tree := false

@onready var _root: Control = $Root
@onready var _dim: ColorRect = $Root/Dim
@onready var _frame: PanelContainer = %Frame
@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _wallet_box: HBoxContainer = %Wallet
@onready var _tabs: HBoxContainer = %Tabs
@onready var _body: BoxContainer = %Body
@onready var _grid: GridContainer = %Grid
@onready var _detail: PanelContainer = %Detail
@onready var _d_icon: PanelContainer = %DIcon
@onready var _d_name: Label = %DName
@onready var _d_rarity: Label = %DRarity
@onready var _d_level: Label = %DLevel
@onready var _d_desc: Label = %DDesc
@onready var _d_effect: RichTextLabel = %DEffect
@onready var _d_flavor: Label = %DFlavor
@onready var _d_cost: Label = %DCost
@onready var _buy: Button = %Buy
@onready var _leave: Button = %Leave
@onready var _empty: Label = %Empty

var _wallet: CurrencyCounter
var _extra_wallets: Array[CurrencyCounter] = []


func _ready() -> void:
	visible = false
	_wallet = CurrencyCounter.new()
	_wallet.font_size = 26
	_wallet_box.add_child(_wallet)
	_buy.pressed.connect(_on_buy)
	_leave.pressed.connect(close)
	Sfx.wire_button(_leave, &"ui_back")
	_root.resized.connect(_layout)
	# Autowrapped labels report huge heights while unsized; re-fit whenever the content settles.
	_frame.minimum_size_changed.connect(_queue_layout)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		close()
		get_viewport().set_input_as_handled()
	elif UINav.page_dir(event) != 0 and _tabs.get_child_count() > 1:
		# Q / E, PageUp / PageDown or pad LB / RB cycle categories.
		_cycle_tab(UINav.page_dir(event))
		get_viewport().set_input_as_handled()
	else:
		UINav.recover_focus(event, _grid.get_child(0) as Control if _grid.get_child_count() > 0 else _leave)


## Opens the shop (see the class doc for `config` keys).
func open(config: Dictionary) -> void:
	_cfg = config
	_title.text = str(config.get("title", "Merchant of Sin"))
	_subtitle.text = str(config.get("subtitle", ""))
	_subtitle.visible = _subtitle.text != ""
	_wallet.setup(str(config.get("currency_glyph", "◈")), config.get("currency_color", UIPalette.SOUL),
		str(config.get("currency_name", "Souls")))
	_pause_tree = bool(config.get("pause", false))
	_category = ""
	_selected_id = ""
	_reload(true)
	visible = true
	if _pause_tree:
		get_tree().paused = true
	Sfx.play(&"ui_click")
	_layout()
	_animate_in()
	_focus_first.call_deferred()


func close() -> void:
	if not visible:
		return
	visible = false
	if _pause_tree:
		get_tree().paused = false
	Sfx.play(&"ui_back")
	closed.emit()


## Replace the item list / wallet from outside (when you passed plain values to open()).
func refresh(items: Array = [], currency: int = -1) -> void:
	if not items.is_empty():
		_items = items
	if currency >= 0:
		_currency = currency
		_wallet.set_amount(_currency)
	_rebuild_tabs()
	_rebuild_grid()
	_show_detail(_find(_selected_id))


func is_open() -> bool:
	return visible


# ---------------------------------------------------------------- data

func _reload(snap: bool) -> void:
	var items_v: Variant = _cfg.get("items", [])
	if items_v is Callable:
		_items = (items_v as Callable).call()
	elif items_v is Array:
		_items = items_v
	var cur_v: Variant = _cfg.get("currency", 0)
	if cur_v is Callable:
		_currency = int((cur_v as Callable).call())
	else:
		_currency = int(cur_v)
	_wallet.set_amount(_currency, snap)
	_refresh_extra_wallets(snap)
	_rebuild_tabs()
	_rebuild_grid()
	_show_detail(_find(_selected_id))


func _refresh_extra_wallets(snap: bool) -> void:
	var defs: Array = _cfg.get("wallets", [])
	while _extra_wallets.size() < defs.size():
		var c := CurrencyCounter.new()
		c.font_size = 20
		_wallet_box.add_child(c)
		_wallet_box.move_child(c, 0)
		_extra_wallets.append(c)
	for i in _extra_wallets.size():
		var c := _extra_wallets[i]
		c.visible = i < defs.size()
		if not c.visible:
			continue
		var d: Dictionary = defs[i]
		c.setup(str(d.get("glyph", "◆")), d.get("color", UIPalette.BRIMSTONE), str(d.get("name", "")))
		var amt: Variant = d.get("amount", 0)
		c.set_amount(int((amt as Callable).call()) if amt is Callable else int(amt), snap)


func _find(id: String) -> Dictionary:
	for it: Dictionary in _items:
		if str(it.get("id", "")) == id:
			return it
	return {}


func _visible_items() -> Array:
	if _category == "":
		return _items
	return _items.filter(func(it: Dictionary) -> bool: return str(it.get("category", "")) == _category)


## "" when purchasable, else the reason it is not.
func _block_reason(it: Dictionary) -> String:
	if it.is_empty():
		return "Choose an offering"
	if bool(it.get("locked", false)):
		return str(it.get("locked_reason", "Sealed"))
	var max_level := int(it.get("max_level", 0))
	if max_level <= 0 and bool(it.get("owned", false)):
		return "Already yours"
	if max_level > 0 and int(it.get("level", 0)) >= max_level:
		return "Mastered"
	if not _affordable(it):
		return "Not enough %s" % str(it.get("currency_name", _cfg.get("currency_name", "souls"))).to_lower()
	return ""


## Affordability against the item's own currency when it has one, else the main wallet.
func _affordable(it: Dictionary) -> bool:
	var cost := int(it.get("cost", 0))
	if it.has("affordable"):
		return bool(it.affordable)
	if it.has("currency_amount"):
		return cost <= int(it.currency_amount)
	return cost <= _currency


func _price_text(it: Dictionary) -> String:
	return "%s %d" % [str(it.get("currency_glyph", _cfg.get("currency_glyph", "◈"))), int(it.get("cost", 0))]


func _price_color(it: Dictionary) -> Color:
	return it.get("currency_color", _cfg.get("currency_color", UIPalette.SOUL))


# ---------------------------------------------------------------- building

func _rebuild_tabs() -> void:
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	var cats: Array[String] = []
	for it: Dictionary in _items:
		var c := str(it.get("category", ""))
		if c != "" and not cats.has(c):
			cats.append(c)
	_tabs.visible = cats.size() > 1
	if cats.size() <= 1:
		_category = ""
		return
	if not cats.has(_category):
		_category = cats[0]
	for c in cats:
		var b := Button.new()
		b.theme_type_variation = &"TabButton"
		b.toggle_mode = true
		b.text = c.to_upper()
		b.focus_mode = Control.FOCUS_NONE
		b.set_pressed_no_signal(c == _category)
		b.pressed.connect(_select_tab.bind(c))
		Sfx.wire_button(b)
		_tabs.add_child(b)


func _cycle_tab(dir: int) -> void:
	var names: Array[String] = []
	for b: Button in _tabs.get_children():
		names.append(b.text)
	var i := 0
	for j in names.size():
		if names[j] == _category.to_upper():
			i = j
	var next_i := (i + dir + names.size()) % names.size()
	for it: Dictionary in _items:
		var c := str(it.get("category", ""))
		if c.to_upper() == names[next_i]:
			_select_tab(c)
			Sfx.play(&"ui_click", 0.03)
			return


func _select_tab(cat: String) -> void:
	_category = cat
	for b: Button in _tabs.get_children():
		b.set_pressed_no_signal(b.text == cat.to_upper())
	_selected_id = ""
	_rebuild_grid()
	_focus_first.call_deferred()


func _rebuild_grid() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_cards.clear()
	var list := _visible_items()
	_empty.visible = list.is_empty()
	for it: Dictionary in list:
		var card := _make_card(it)
		_grid.add_child(card)
		_cards[str(it.get("id", ""))] = card
	_layout()


func _make_card(it: Dictionary) -> Button:
	var id := str(it.get("id", ""))
	var tint: Color = it.get("color", UIPalette.rarity_color(it.get("rarity", "common")))
	var reason := _block_reason(it)
	var locked := bool(it.get("locked", false))

	var card := Button.new()
	card.theme_type_variation = &"CardButton"
	card.custom_minimum_size = CARD_SIZE
	card.focus_mode = Control.FOCUS_ALL
	card.tooltip_text = str(it.get("name", id))

	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: StringName in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		pad.add_theme_constant_override(side, 10)
	card.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 4)
	pad.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 10)
	col.add_child(top)
	top.add_child(_icon_frame(it, tint, 48.0, locked))
	var name_col := VBoxContainer.new()
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.add_theme_constant_override(&"separation", 0)
	top.add_child(name_col)
	var nm := _label(str(it.get("name", id)), &"InkLabel", 17,
		UIPalette.LOCKED.lightened(0.3) if locked else UIPalette.BONE_BRIGHT)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.max_lines_visible = 2
	name_col.add_child(nm)
	var rarity := str(it.get("rarity", ""))
	if rarity != "":
		name_col.add_child(_label("%s %s" % [UIPalette.rarity_mark(rarity), rarity.to_upper()], &"CaptionLabel", 11,
			UIPalette.rarity_color(rarity)))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)

	var bottom := HBoxContainer.new()
	col.add_child(bottom)
	bottom.add_child(_pips(it))
	var price := Label.new()
	price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var cost := int(it.get("cost", 0))
	var max_level := int(it.get("max_level", 0))
	if locked:
		price.theme_type_variation = &"CaptionLabel"
		price.text = "SEALED"
	elif (max_level <= 0 and bool(it.get("owned", false))) or (max_level > 0 and int(it.get("level", 0)) >= max_level):
		price.theme_type_variation = &"CaptionLabel"
		price.text = "OWNED" if max_level <= 0 else "MASTERED"
		price.add_theme_color_override(&"font_color", UIPalette.BRIMSTONE)
	elif cost >= 0:
		price.theme_type_variation = &"CostLabel"
		price.add_theme_font_size_override(&"font_size", 18)
		price.text = _price_text(it)
		price.add_theme_color_override(&"font_color", _price_color(it))
		if not _affordable(it):
			price.add_theme_color_override(&"font_color", Color(UIPalette.DANGER, 0.85))
	bottom.add_child(price)

	_ignore_mouse(pad)
	if reason != "":
		card.modulate = Color(0.78, 0.74, 0.72) if not locked else Color(0.6, 0.56, 0.55)
	card.focus_entered.connect(_on_card_focus.bind(id))
	card.mouse_entered.connect(_on_card_focus.bind(id))
	card.pressed.connect(_on_card_pressed.bind(id))
	card.focus_entered.connect(Sfx.play.bind(&"ui_hover", 0.03, -4.0))
	return card


func _icon_frame(it: Dictionary, tint: Color, side: float, locked: bool) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(side, side)
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var sb := UIPalette.box(UIPalette.SCORCH.lerp(tint, 0.15), Color(tint, 0.7) if not locked else UIPalette.IRON, 1, 2, 2.0)
	sb.shadow_color = Color(tint, 0.15)
	sb.shadow_size = 8
	frame.add_theme_stylebox_override(&"panel", sb)
	var tex: Texture2D = null
	var icon_v: Variant = it.get("icon", null)
	if icon_v is Texture2D:
		tex = icon_v
	elif icon_v is String and ResourceLoader.exists(icon_v):
		tex = load(icon_v) as Texture2D
	if tex and not locked:
		var art := TextureRect.new()
		art.texture = tex
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(art)
	else:
		# Painted in code (GlyphIcon), so emoji glyphs from data never depend on the OS font.
		var g := GlyphIcon.new()
		g.glyph = "🔒" if locked else str(it.get("glyph", "✦"))
		g.color = UIPalette.LOCKED.lightened(0.2) if locked else tint.lerp(UIPalette.BONE_BRIGHT, 0.35)
		g.custom_minimum_size = Vector2(side, side) * 0.62
		g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		frame.add_child(g)
	return frame


## Level pips: ◆◆◇◇ (filled = bought ranks). Empty control for one-off items.
func _pips(it: Dictionary) -> Control:
	var max_level := int(it.get("max_level", 0))
	var l := Label.new()
	l.theme_type_variation = &"InkLabel"
	l.add_theme_font_size_override(&"font_size", 13)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if max_level <= 0:
		return l
	var lv := clampi(int(it.get("level", 0)), 0, max_level)
	if max_level > 8:
		l.text = "%d / %d" % [lv, max_level]
	else:
		l.text = "◆".repeat(lv) + "◇".repeat(max_level - lv)
	l.add_theme_color_override(&"font_color", UIPalette.BRIMSTONE)
	return l


func _show_detail(it: Dictionary) -> void:
	_detail.visible = true
	for c in _d_icon.get_children():
		c.queue_free()
	if it.is_empty():
		_d_name.text = "Choose an offering"
		_d_rarity.text = ""
		_d_level.text = ""
		_d_desc.text = "Every gift down here has a price. Pick one to see what it costs."
		_d_effect.text = ""
		_d_flavor.text = ""
		_d_cost.text = ""
		_d_icon.visible = false
		_buy.disabled = true
		_buy.text = "PURCHASE"
		return
	var tint: Color = it.get("color", UIPalette.rarity_color(it.get("rarity", "common")))
	var locked := bool(it.get("locked", false))
	_d_icon.visible = true
	var frame := _icon_frame(it, tint, 84.0, locked)
	_d_icon.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	_d_icon.add_child(frame)
	_d_name.text = str(it.get("name", ""))
	var rarity := str(it.get("rarity", ""))
	_d_rarity.text = ("%s %s" % [UIPalette.rarity_mark(rarity), rarity.to_upper()]) if rarity != "" else ""
	_d_rarity.add_theme_color_override(&"font_color", UIPalette.rarity_color(rarity))
	var max_level := int(it.get("max_level", 0))
	_d_level.text = ("Rank %d of %d" % [int(it.get("level", 0)), max_level]) if max_level > 0 else ""
	_d_desc.text = str(it.get("locked_reason", "Sealed.")) if locked else str(it.get("description", ""))
	var now_t := str(it.get("effect_now", ""))
	var next_t := str(it.get("effect_next", ""))
	var bb := ""
	if now_t != "":
		bb += "[color=#a08a7c]Now[/color]  %s" % now_t
	if next_t != "":
		bb += ("\n" if bb != "" else "") + "[color=#e0662a]Next[/color]  [b]%s[/b]" % next_t
	_d_effect.text = bb
	_d_effect.visible = bb != ""
	_d_flavor.text = str(it.get("flavor", ""))
	_d_flavor.visible = _d_flavor.text != ""
	var cost := int(it.get("cost", 0))
	var reason := _block_reason(it)
	_d_cost.text = _price_text(it) if cost >= 0 else ""
	_d_cost.add_theme_color_override(&"font_color", _price_color(it) if _affordable(it) else UIPalette.DANGER)
	_buy.disabled = reason != ""
	_buy.text = "PURCHASE" if reason == "" else reason.to_upper()


# ---------------------------------------------------------------- interaction

func _on_card_focus(id: String) -> void:
	if _selected_id == id:
		return
	_selected_id = id
	_show_detail(_find(id))


func _on_card_pressed(id: String) -> void:
	# First press selects (mouse); pressing the already-selected card buys (keyboard / pad flow).
	if _selected_id != id:
		_on_card_focus(id)
		return
	_on_buy()


func _on_buy() -> void:
	var it := _find(_selected_id)
	var reason := _block_reason(it)
	if it.is_empty():
		return
	if reason != "":
		Sfx.play(&"shop_deny", 0.02)
		if not _affordable(it) and not it.has("currency_glyph"):
			_wallet.deny()
		purchase_failed.emit(_selected_id, reason)
		return
	purchase_requested.emit(_selected_id)
	var buy_v: Variant = _cfg.get("buy", null)
	if not buy_v is Callable:
		return  # caller handles purchase_requested and calls refresh()
	var ok := bool((buy_v as Callable).call(_selected_id))
	if ok:
		Sfx.play(&"shop_buy", 0.02)
		purchased.emit(_selected_id)
		var keep := _selected_id
		_reload(false)
		_selected_id = keep
		_show_detail(_find(keep))
		_flash_card(keep)
	else:
		Sfx.play(&"shop_deny", 0.02)
		_wallet.deny()
		purchase_failed.emit(_selected_id, "refused")


func _flash_card(id: String) -> void:
	var card: Button = _cards.get(id)
	if card == null:
		return
	card.grab_focus()
	card.modulate = Color(1.8, 1.4, 0.9)
	card.create_tween().tween_property(card, "modulate", Color.WHITE, 0.6).set_trans(Tween.TRANS_SINE)


func _focus_first() -> void:
	if not visible:
		return
	if _cards.has(_selected_id):
		(_cards[_selected_id] as Button).grab_focus()
	elif _grid.get_child_count() > 0:
		(_grid.get_child(0) as Button).grab_focus()
	else:
		_leave.grab_focus()


# ---------------------------------------------------------------- layout

## Fits the frame to the window and switches the detail pane below the grid on narrow screens.
func _layout() -> void:
	if _root == null:
		return
	var vp := _root.size
	var w := minf(PANEL_MAX.x, vp.x * PANEL_FRAC.x)
	var h := minf(PANEL_MAX.y, vp.y * PANEL_FRAC.y)
	var narrow := w < 860.0
	_body.vertical = narrow
	_detail.custom_minimum_size = Vector2(0.0, 220.0) if narrow else Vector2(320.0, 0.0)
	var grid_w := w - 60.0 - (0.0 if narrow else 340.0)
	_grid.columns = maxi(1, int(grid_w / (CARD_SIZE.x + 12.0)))
	# Shrink back to the minimum first: a plain Control never shrinks on its own.
	_frame.size = Vector2.ZERO
	_frame.size = Vector2(w, h)
	_frame.position = (vp - _frame.size) * 0.5


var _layout_queued := false


func _queue_layout() -> void:
	if _layout_queued:
		return
	_layout_queued = true
	(func() -> void:
		_layout_queued = false
		_layout()).call_deferred()


func _animate_in() -> void:
	_dim.modulate.a = 0.0
	_dim.create_tween().tween_property(_dim, "modulate:a", 1.0, 0.3)
	_frame.pivot_offset = _frame.size * 0.5
	_frame.modulate.a = 0.0
	_frame.scale = Vector2(0.97, 0.97)
	var tw := _frame.create_tween().set_parallel()
	tw.tween_property(_frame, "modulate:a", 1.0, 0.25)
	tw.tween_property(_frame, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------- helpers

func _label(text: String, variation: StringName, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = text
	return l


func _ignore_mouse(node: Node) -> void:
	var c := node as Control
	if c:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)
