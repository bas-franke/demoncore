class_name Basecamp
extends Node3D
## Basecamp Hell: the hub every game start and every run end lands in. A basalt plateau ringed by
## a lava moat under a burning sky. The chosen demon walks around (HubAvatar) and trades with four
## merchants (HubShopkeeper -> HubShopUI, upgrades from Meta / data/meta/upgrades.json):
##   Grimmaul the blacksmith (west), Vesper the occultist (east), the soul broker (south-west), and
##   Ossek the cartographer beside the hellgate (map selection).
## The hellgate (north) starts a run on Meta.selected_map; the summoning circle (south-east) goes
## back to the demon select. Everything is built in code from primitives, Blender props and two
## shaders (lava.gdshader, portal.gdshader).
##
## Hooks for other systems:
##   Basecamp.add_interactable(node)       # add your own HubInteractable (e.g. a quest board)
##   get_tree().get_first_node_in_group(&"basecamp")
##   signal run_starting                     # just before the scene changes to the run

signal run_starting

const DEMON_SELECT_SCENE := "res://scenes/menu/demon_select.tscn"
const SETTINGS_SCENE := "res://scenes/ui/settings_menu.tscn"
const SHOP_PANEL_SCENE := "res://ui/components/shop_panel.tscn"
const LOADOUT_PANEL_SCRIPT := "res://ui/components/loadout_panel.gd"
## Meta shop id -> Progression shop id whose wares the same merchant also sells.
const PROGRESSION_SHOPS := {"blacksmith": "hellforge", "occultist": "occult", "soul_broker": "bindings"}
## Prefixes on ShopPanel item ids, so one buy callback can route to Meta or Progression.
const META_PREFIX := "meta:"
const PROG_PREFIX := "prog:"

## Layout, shared with HubScenery (which builds the camp around these spots).
const X0 := HubScenery.X0
const X1 := HubScenery.X1
const Z0 := HubScenery.Z0
const Z1 := HubScenery.Z1
const SPAWN := HubScenery.SPAWN
const GATE := HubScenery.GATE
const FIRE := HubScenery.FIRE
const SMITH := HubScenery.SMITH
const OCCULT := HubScenery.OCCULT
const BROKER := HubScenery.BROKER
const CARTO := HubScenery.CARTO
const CIRCLE := HubScenery.CIRCLE
const COVENANT := HubScenery.COVENANT

const CAM_PITCH := deg_to_rad(52.0)
const CAM_DIST := 15.5
const CAM_FOV := 40.0
## Ambient corruption (0..1) over the whole camp (Corruption autoload). The ambient blight is
## noise-varied (crack clusters, cooled-obsidian patches, thin spots) and adds no foot-height glow
## (art-style round 2); 0.6 keeps the flagstones readable. Try values with `-- --blight=<x>`.
const BLIGHT := 0.6
## Interactable names show within this distance of the avatar (keeps the screen uncluttered).
const NAME_RANGE := 9.0
const HINT := "WASD  walk        E  interact        Tab  quick menu        C  codex        Esc  settings"

var avatar: HubAvatar
var scenery: HubScenery
var _camera: Camera3D
var _cam_focus := SPAWN
var _cam_zoom := 1.0
var _ui: HubShopUI
var _shop: CanvasLayer  # ShopPanel (UI role), created on first use
var _shop_keeper: HubShopkeeper
var _settings: CanvasLayer
var _codex: CanvasLayer  # CodexScreen (UI role), C key
var _fade: ColorRect
var _banner: Label
var _banner_sub: Label
var _souls_label: Label
var _hint: Label
var _gate: HubInteractable
var _merchants := {}  # shop id -> HubShopkeeper
var _active: HubInteractable
var _leaving := false
var _life: HubLife
var _boards: HubBoards
var _board_ui: HubBoardUI
var _pit: HubPit
var _news := ""
var _loadout_ui: HubLoadoutUI
var _loadout_panel: CanvasLayer  # LoadoutPanel (UI role) when it loads
var _quick: HubQuickMenu


func _ready() -> void:
	add_to_group(&"basecamp")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	get_tree().paused = false
	Engine.time_scale = 1.0
	Sfx.play_music(&"menu")
	scenery = HubScenery.new()
	add_child(scenery)
	scenery.build()
	# Spires, basalt organs and brimstone islets in the lava around the plateau (terrain role).
	scenery.add_child(HellDressing.around(Rect2(X0, Z0, X1 - X0, Z1 - Z0), -1.6))
	_build_camera()
	_build_interactables()
	# Ambient camp NPCs (Kesh by the gate, Pip by the fire, ...): data/npcs/npcs.json (characters-new).
	CharacterRoster.populate_basecamp(self)
	_build_camp_life()
	avatar = HubAvatar.new()
	avatar.position = SPAWN
	avatar.rotation.y = 0.0
	add_child(avatar)
	HubWardrobe.install(self)  # characters-polish: skin wardrobe (mirror + likeness + SkinPicker)
	_cam_focus = avatar.position
	# No walking trail here either: on the flagstones its pale char reads as a bright smear.
	var corruption := get_node_or_null(^"/root/Corruption")
	if corruption:
		corruption.set(&"ambient", BLIGHT)
	_build_ui()
	_update_camera(1.0)
	_arrival()
	_announce_growth()
	_dev_args()


# ---------------------------------------------------------------- camera & interactables

func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.fov = CAM_FOV
	_camera.near = 0.2
	_camera.far = 120.0
	add_child(_camera)
	_camera.current = true


## The merchants, the hellgate prompt, the summoning circle and the Covenant lectern.
func _build_interactables() -> void:
	_add_merchant("blacksmith", HubShopkeeper.Look.BLACKSMITH, SMITH, PI * 0.5 + 0.35)
	_add_merchant("occultist", HubShopkeeper.Look.OCCULTIST, OCCULT, -PI * 0.5 - 0.35)
	_add_merchant("soul_broker", HubShopkeeper.Look.SOUL_BROKER, BROKER, -PI * 0.25 + PI)
	_add_merchant("cartographer", HubShopkeeper.Look.CARTOGRAPHER, CARTO, PI + 0.4)

	_gate = _interactable("Descend", "", GATE + Vector3(0.0, 0.0, 1.6), 3.4, 1.6)
	_gate.interacted.connect(_open_loadout)
	_refresh_gate_label()
	Meta.map_selected.connect(func(_id: StringName) -> void: _refresh_gate_label())

	_interactable("Change demon", "Summoning Circle", CIRCLE, 2.2, 1.6).interacted.connect(_change_demon)

	var covenant: Dictionary = Meta.shops.get("covenant", {})
	var lectern := _interactable("Swear pacts", String(covenant.get("name", "The Covenant")), COVENANT, 2.0, 2.2)
	lectern.interacted.connect(func() -> void:
		if _leaving or _menu_open():
			return
		avatar.frozen = true
		avatar.face(COVENANT)
		_ui.open_pacts())


func _interactable(verb: String, label: String, at: Vector3, radius: float, height: float) -> HubInteractable:
	var it := HubInteractable.new()
	it.verb = verb
	it.label = label
	it.radius = radius
	it.prompt_height = height
	it.position = at
	add_child(it)
	return it


func _refresh_gate_label() -> void:
	var m := Meta.get_map(Meta.selected_map)
	_gate.label = "Hellgate  ·  %s" % String(m.get("name", "The Heavens"))
	_gate.refresh()


## `yaw` = rest facing in Godot convention (0 faces -Z; PI faces the camera, +Z).
func _add_merchant(shop_id: String, look: HubShopkeeper.Look, at: Vector3, yaw: float) -> void:
	var k := HubShopkeeper.new()
	k.shop_id = shop_id
	k.look = look
	k.rest_yaw = yaw
	var shop: Dictionary = Meta.shops.get(shop_id, {})
	var title := String(shop.get("title", shop_id.capitalize()))
	k.label = "%s, %s" % [String(shop.get("name", "")), title.split(" of ")[0]] if shop.has("name") else title
	k.prompt_height = 3.6 if look != HubShopkeeper.Look.OCCULTIST else 3.9
	k.position = at
	add_child(k)
	scenery.obstacles.append([at, 0.7])  # wanderers steer around the merchant
	if look == HubShopkeeper.Look.CARTOGRAPHER:
		k.verb = "Choose a road"
		k.refresh()
	# A warm pool of lantern light at every stall (lighting pass with visuals: amber pools against
	# the red camp, only a hint of the merchant's own colour).
	var tint := Color.from_string(String(shop.get("color", "")), Art.EMBER)
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	_lantern(at + fwd * 1.1 + right * 1.0, Color(1.0, 0.68, 0.4).lerp(tint, 0.2))
	k.interacted.connect(_open_merchant.bind(k))
	_merchants[shop_id] = k


## Iron lantern on a bone post; its light makes the warm pool a merchant stands in.
func _lantern(at: Vector3, color: Color) -> void:
	var root := Art.pivot(self, at)
	var bone := Art.mat(Art.BONE.darkened(0.2), 0.7, 0.0, 0.5, false, 0.0, &"bone")
	var iron := Art.mat(Art.OBSIDIAN, 0.4, 0.8, 0.4, false, 0.0, &"metal")
	Art.part(root, Art.cylinder(0.04, 0.06), bone, Vector3(0.0, 1.3, 0.0), Vector3(1.0, 2.6, 1.0))
	Art.part(root, Art.box(), iron, Vector3(0.0, 2.55, -0.25), Vector3(0.05, 0.05, 0.55))
	Art.part(root, Art.box(), iron, Vector3(0.0, 2.25, -0.5), Vector3(0.22, 0.32, 0.22))
	var core := Art.part(root, Art.sphere(), Art.glow(color, 3.0), Vector3(0.0, 2.25, -0.5), Vector3.ONE * 0.16)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l := Art.light(root, color, 4.2, 6.5, Vector3(0.0, 2.1, -0.6))
	l.light_specular = 0.5
	l.omni_attenuation = 1.3
	scenery.add_flicker(l)
	scenery.add_post(at, 0.25)


# ---------------------------------------------------------------- camp life, boards, pit

## Inhabitants and progress-gated set pieces (HubLife), the Ledger + trophy wall (HubBoards) and
## the Proving Pit (HubPit).
func _build_camp_life() -> void:
	_life = HubLife.new()
	_life.name = "Life"
	add_child(_life)
	_news = _life.build(scenery)
	if _life.level >= HubLife.ENDING_LEVEL:
		_reconquest_light()

	_board_ui = HubBoardUI.new()
	add_child(_board_ui)
	_board_ui.closed.connect(_on_ui_closed)
	_boards = HubBoards.new()
	_boards.name = "Boards"
	add_child(_boards)
	_boards.build(scenery, _board_ui)
	_boards.board_opened.connect(func() -> void: avatar.frozen = true)
	_boards.trial_accepted.connect(func(t: Dictionary) -> void: _enter_gate(Meta.start_trial.bind(t)))

	_pit = HubPit.new()
	_pit.name = "Pit"
	add_child(_pit)
	_pit.build(scenery)
	_pit.interactable.interacted.connect(_open_pit_menu)
	_pit.exited.connect(_on_pit_exited)


## A camp level reached since the last visit gets its own banner after the arrival one.
func _announce_growth() -> void:
	if _news == "":
		return
	await get_tree().create_timer(6.5).timeout
	if is_inside_tree() and not _leaving:
		_show_banner("The Camp Grows", _news, UIPalette.BRIMSTONE)
		Sfx.play(&"toll", 0.0, -4.0)


func _open_pit_menu() -> void:
	if _leaving or _menu_open() or _pit.active:
		return
	avatar.frozen = true
	_ui.open_rites()


func _enter_pit(rites: Array) -> void:
	if _leaving or _pit.active:
		return
	avatar.frozen = true
	Sfx.play(&"cast", 0.05, -4.0)
	var tw := _fade.create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.35)
	await tw.finished
	avatar.visible = false
	if _active and is_instance_valid(_active):
		_active.set_focused(false)
	_active = null
	await _pit.enter(rites)
	_hint.text = "WASD  move        Your weapons and rites strike on their own        E / Esc  leave the pit"
	_fade.create_tween().tween_property(_fade, "color:a", 0.0, 0.5)


## After the ending the camp's light turns a warmer, triumphant gold (visuals role's overlay ops on
## top of the basecamp_hell preset). Waits for Atmosphere to bind this scene first: binding a new
## scene clears overlays.
func _reconquest_light() -> void:
	var atmo := get_node_or_null(^"/root/Atmosphere")
	if atmo == null:
		return
	await get_tree().create_timer(0.4).timeout
	if is_inside_tree():
		atmo.call(&"push_overlay", &"reconquest", {
			"sun.color~": [[1.0, 0.72, 0.42], 0.6], "sun.energy*": 1.15,
			"env.exposure*": 1.06, "grade.saturation*": 1.08, "env.fog_density*": 0.7,
		}, 3.0)


## The hellgate's loadout step: the UI role's LoadoutPanel when it is available, else the hub's own
## HubLoadoutUI. Both take RunLoadout data and emit confirmed({weapon, ability, keepsake}).
func _open_loadout() -> void:
	if _leaving or _menu_open():
		return
	avatar.frozen = true
	if _loadout_panel == null:
		var script := load(LOADOUT_PANEL_SCRIPT) as Script if ResourceLoader.exists(LOADOUT_PANEL_SCRIPT) else null
		if script and script.can_instantiate():
			_loadout_panel = script.new() as CanvasLayer
			add_child(_loadout_panel)
			_loadout_panel.connect(&"closed", _on_ui_closed)
			_loadout_panel.connect(&"confirmed", func(choice: Dictionary) -> void:
				_enter_gate(Meta.start_run_with_loadout.bind(choice)))
	if _loadout_panel:
		var m := Meta.get_map(Meta.selected_map)
		_loadout_panel.call(&"open", {
			"title": "The Hellgate",
			"subtitle": "The road: %s. Choose what you carry." % String(m.get("name", "The Heavens")),
			"current": Meta.loadout, "weapons": RunLoadout.weapons(), "abilities": RunLoadout.abilities(),
			"keepsakes": RunLoadout.keepsakes(),
		})
	else:
		_loadout_ui.open()


# ---------------------------------------------------------------- quick menu (Tab)

## Destinations for the quick menu: [{id, label, hint, at (stand spot), node (HubInteractable)}].
func _quick_entries() -> Array:
	var out: Array = []
	for id: String in ["blacksmith", "occultist", "soul_broker", "cartographer"]:
		var k: HubShopkeeper = _merchants.get(id)
		if k:
			out.append({"id": id, "label": k.label, "hint": "Trade", "node": k})
	out.append({"id": "gate", "label": "Hellgate", "hint": "Loadout and descend", "node": _gate})
	for it in get_tree().get_nodes_in_group(&"hub_interactables"):
		var h := it as HubInteractable
		if h == _gate or h is HubShopkeeper or h.label == "":
			continue
		out.append({"id": String(h.name), "label": h.label, "hint": h.verb, "node": h})
	return out


## Teleports the avatar in front of the chosen interactable (quick fade) and uses it.
func _quick_travel(entry: Dictionary) -> void:
	var node := entry.get("node") as HubInteractable
	if not is_instance_valid(node):
		avatar.frozen = false
		return
	var tw := _fade.create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.2)
	await tw.finished
	# Stand toward the plaza centre from it, just inside its reach.
	var at := node.global_position
	var away := Vector3(0.0, 0.0, 2.0) - Vector3(at.x, 0.0, at.z)
	away = away.normalized() if away.length() > 0.1 else Vector3.BACK
	avatar.global_position = Vector3(at.x, 0.0, at.z) + away * minf(node.radius * 0.6, 1.6)
	avatar.face(at)
	_cam_focus = avatar.global_position
	_update_camera(1.0)
	_fade.create_tween().tween_property(_fade, "color:a", 0.0, 0.25)
	avatar.frozen = false
	_update_focus()
	node.interact()


func _leave_pit() -> void:
	var tw := _fade.create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.3)
	await tw.finished
	_pit.leave()


func _on_pit_exited() -> void:
	avatar.visible = true
	avatar.frozen = false
	_hint.text = HINT
	_cam_focus = avatar.global_position
	_fade.create_tween().tween_property(_fade, "color:a", 0.0, 0.5)


# ---------------------------------------------------------------- ui

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	# Top-left: place name. Top-right: soul counter.
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = "Basecamp Hell"
	title.add_theme_font_size_override(&"font_size", 30)
	title.position = Vector2(24.0, 14.0)
	root.add_child(title)
	_souls_label = Label.new()
	_souls_label.theme_type_variation = &"InkLabel"
	_souls_label.add_theme_font_size_override(&"font_size", 26)
	_souls_label.add_theme_color_override(&"font_color", UIPalette.SOUL)
	_souls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_souls_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_souls_label.offset_left = -360.0
	_souls_label.offset_right = -24.0
	_souls_label.offset_top = 18.0
	root.add_child(_souls_label)
	Meta.souls_changed.connect(func(_t: int) -> void: _update_souls())
	_update_souls()

	_hint = Label.new()
	_hint.theme_type_variation = &"InkLabel"
	_hint.add_theme_font_size_override(&"font_size", 16)
	_hint.add_theme_color_override(&"font_color", UIPalette.ASH_TEXT)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -40.0
	_hint.offset_bottom = -14.0
	_hint.text = HINT
	root.add_child(_hint)

	# Arrival banner (run summary or welcome).
	var bc := VBoxContainer.new()
	bc.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	bc.offset_left = -400.0
	bc.offset_right = 400.0
	bc.offset_top = 56.0  # above the Dialogue subtitles (~150 px)
	bc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bc)
	_banner = Label.new()
	_banner.theme_type_variation = &"TitleLabel"
	_banner.add_theme_font_size_override(&"font_size", 44)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bc.add_child(_banner)
	_banner_sub = Label.new()
	_banner_sub.theme_type_variation = &"LoreLabel"
	_banner_sub.add_theme_font_size_override(&"font_size", 20)
	_banner_sub.add_theme_color_override(&"font_color", UIPalette.BONE)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bc.add_child(_banner_sub)
	_banner.modulate.a = 0.0
	_banner_sub.modulate.a = 0.0

	_ui = HubShopUI.new()
	add_child(_ui)
	_ui.closed.connect(_on_ui_closed)
	_ui.map_chosen.connect(func(_id: StringName) -> void: _react_purchase())
	_ui.rites_chosen.connect(_enter_pit)
	_loadout_ui = HubLoadoutUI.new()
	add_child(_loadout_ui)
	_loadout_ui.closed.connect(_on_ui_closed)
	_loadout_ui.confirmed.connect(func(choice: Dictionary) -> void:
		_enter_gate(Meta.start_run_with_loadout.bind(choice)))
	_quick = HubQuickMenu.new()
	add_child(_quick)
	_quick.closed.connect(_on_ui_closed)
	_quick.chosen.connect(_quick_travel)

	var fl := CanvasLayer.new()
	fl.layer = 50
	add_child(fl)
	_fade = ColorRect.new()
	_fade.color = Color(0.0, 0.0, 0.0, 1.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fl.add_child(_fade)
	_fade.create_tween().tween_property(_fade, "color:a", 0.0, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _update_souls() -> void:
	_souls_label.text = "✧ %d Souls" % Meta.souls


func _arrival() -> void:
	var s := Meta.pending_summary
	Meta.pending_summary = {}
	if s.is_empty():
		_show_banner("Basecamp Hell", "The damned keep the fires lit for your return.", UIPalette.BRIMSTONE)
		return
	var head := "Triumphant Return" if s.get("victory", false) else "Dragged Back Below"
	var sub := "+%d souls   ·   %d angels slain   ·   %s endured" % [int(s.souls), int(s.kills), TextFormat.clock(float(s.get("time", 0.0)))]
	# Progression's own haul (Sin Shards, Hellstone, heat bonus) on a second line.
	var prog := get_node_or_null(^"/root/Progression")
	if prog and prog.has_method(&"rewards_text"):
		var extra := String(prog.call(&"rewards_text"))
		if extra != "":
			sub += "\n" + extra
	if s.has("trial_score"):
		var best_note := "  ·  a new best!" if bool(s.get("trial_new_best", false)) \
			else "  ·  best %d" % int(s.get("trial_best", 0))
		sub += "\nTrial score %d%s" % [int(s.trial_score), best_note]
	_show_banner(head, sub, UIPalette.HOLY_GOLD if s.get("victory", false) else UIPalette.BLOOD_BRIGHT)
	Sfx.play(&"gold", 0.05)


func _show_banner(head: String, sub: String, color: Color) -> void:
	_banner.text = head
	_banner.add_theme_color_override(&"font_color", color)
	_banner_sub.text = sub
	var tw := create_tween()
	tw.tween_interval(0.6)
	tw.tween_property(_banner, "modulate:a", 1.0, 0.8)
	tw.parallel().tween_property(_banner_sub, "modulate:a", 1.0, 0.8).set_delay(0.3)
	tw.tween_interval(3.5)
	tw.tween_property(_banner, "modulate:a", 0.0, 1.2)
	tw.parallel().tween_property(_banner_sub, "modulate:a", 0.0, 1.2)


# ---------------------------------------------------------------- interaction

## Registers an extra interactable (it only needs to be in the tree; this just parents it).
func add_interactable(node: HubInteractable) -> void:
	if node.get_parent() == null:
		add_child(node)


## Talk first if the merchant has an unseen story beat (Dialogue role), then open its wares.
func _open_merchant(k: HubShopkeeper) -> void:
	if _leaving or _menu_open():
		return
	avatar.frozen = true
	avatar.face(k.global_position)
	_shop_keeper = k
	var dlg := get_node_or_null(^"/root/Dialogue")
	if dlg and not bool(dlg.call(&"is_active")) and bool(dlg.call(&"has_new", k.shop_id)):
		var conv := String(dlg.call(&"start_for", k.shop_id, true))
		if conv != "":
			await dlg.conversation_finished
			if not is_inside_tree() or _leaving:
				return
	if k.shop_id == "cartographer":
		_ui.open_maps()
	else:
		_open_shop_panel(k.shop_id)


func _open_shop_panel(shop_id: String) -> void:
	if _shop == null:
		var ps := load(SHOP_PANEL_SCENE) as PackedScene
		if ps == null:
			push_warning("Basecamp: %s missing; shop unavailable" % SHOP_PANEL_SCENE)
			avatar.frozen = false
			return
		_shop = ps.instantiate() as CanvasLayer
		add_child(_shop)
		_shop.connect(&"closed", _on_ui_closed)
		_shop.connect(&"purchased", func(_id: String) -> void: _react_purchase())
	var shop: Dictionary = Meta.shops.get(shop_id, {})
	# Story role: the merchant's greeting is a line of their (run-aware) chatter when they have any.
	var greeting := String(shop.get("greeting", ""))
	var dlg := get_node_or_null(^"/root/Dialogue")
	if dlg:
		var line := String(dlg.call(&"chatter", shop_id))
		if line != "":
			greeting = line
	_shop.call(&"open", {
		"title": String(shop.get("name", shop_id.capitalize())),
		"subtitle": String(shop.get("title", "")) + "  —  “" + greeting + "”",
		"currency_glyph": _souls_glyph(), "currency_name": "Souls", "currency_color": UIPalette.SOUL,
		"currency": func() -> int: return Meta.souls,
		"items": _shop_items.bind(shop_id),
		"wallets": _shop_wallets(shop_id),
		"buy": _buy_item,
		"pause": false,
	})


## Extra header wallets (Sin Shards, Hellstone) for the merchants that sell Progression wares.
func _shop_wallets(shop_id: String) -> Array:
	var out: Array = []
	var prog := get_node_or_null(^"/root/Progression")
	if prog == null or not PROGRESSION_SHOPS.has(shop_id):
		return out
	for cid: StringName in [&"sin_shards", &"hellstone"]:
		var cd: Dictionary = prog.call(&"get_currency_def", cid)
		out.append({"glyph": String(cd.get("icon", "◆")), "color": cd.get("color", UIPalette.BRIMSTONE),
			"name": String(cd.get("name", cid)),
			"amount": func() -> int: return int(prog.call(&"get_currency", cid))})
	return out


## ShopPanel item list for a merchant: its Meta (souls) upgrades, then the Progression wares it
## also sells. Wares priced in another currency carry their own glyph / colour / holding
## (ShopPanel per-item currency), so the price and affordability are shown correctly.
func _shop_items(shop_id: String) -> Array:
	var items: Array = []
	var accent := Color.from_string(String(Meta.shops.get(shop_id, {}).get("color", "")), UIPalette.EMBER)
	for d in Meta.upgrades_for_shop(shop_id):
		var id := StringName(d.id)
		var req := Meta.requirement_text(id)
		var lv := Meta.get_level(id)
		items.append({
			"id": META_PREFIX + String(id), "name": d.get("name", id), "description": d.get("description", ""),
			"glyph": d.get("icon", "✦"), "color": accent, "cost": Meta.next_cost(id),
			"level": lv, "max_level": Meta.get_max_level(id),
			"locked": req != "" and not Meta.is_maxed(id), "locked_reason": req,
			"effect_now": Meta.effect_text(id, lv), "effect_next": Meta.effect_text(id, lv + 1) if not Meta.is_maxed(id) else "",
			"flavor": d.get("flavor", ""), "category": "Souls",
		})
	var prog := get_node_or_null(^"/root/Progression")
	if prog and PROGRESSION_SHOPS.has(shop_id):
		for pid: StringName in prog.call(&"get_shop_items", PROGRESSION_SHOPS[shop_id]):
			var info: Dictionary = prog.call(&"item_info", pid)
			var reason := String(info.get("reason", ""))
			var is_unlock := String(info.get("kind", "")) == "unlock"
			var cur := String(info.get("currency", "souls"))
			var in_souls := cur == "souls"
			var item := {
				"id": PROG_PREFIX + String(pid), "name": info.get("name", pid),
				"description": info.get("description", ""), "glyph": info.get("icon", "✦"),
				"color": info.get("currency_color", accent), "cost": int(info.cost),
				"level": int(info.get("level", 0)), "max_level": 0 if is_unlock else int(info.get("max_level", 1)),
				"owned": is_unlock and bool(info.get("maxed", false)),
				"locked": reason.begins_with("Requires"), "locked_reason": reason,
				"effect_now": info.get("effect", ""), "effect_next": info.get("next_effect", ""),
				# (progression) school branches / rites carry their own tab name in "category".
				"category": String(info.get("category", "")) if String(info.get("category", "")) != "" \
						else ("Souls" if in_souls else String(info.get("currency_name", cur))),
			}
			if not in_souls:
				item.currency_glyph = String(info.get("currency_icon", "◆"))
				item.currency_color = info.get("currency_color", UIPalette.BRIMSTONE)
				item.currency_name = String(info.get("currency_name", cur))
				item.currency_amount = int(prog.call(&"get_currency", StringName(cur)))
			items.append(item)
	return items


func _buy_item(item_id: String) -> bool:
	if item_id.begins_with(META_PREFIX):
		return Meta.buy(StringName(item_id.trim_prefix(META_PREFIX)))
	var prog := get_node_or_null(^"/root/Progression")
	if prog and item_id.begins_with(PROG_PREFIX):
		return bool(prog.call(&"buy", StringName(item_id.trim_prefix(PROG_PREFIX))))
	return false


func _react_purchase() -> void:
	if is_instance_valid(_shop_keeper):
		_shop_keeper.react()
	avatar.cheer()


func _souls_glyph() -> String:
	return "✧"


func _on_ui_closed() -> void:
	avatar.frozen = false


## True while any hub overlay (shop, list, settings, dialogue) owns the input.
func _menu_open() -> bool:
	if HubWardrobe.open_now:  # characters-polish
		return true
	if _loadout_panel != null and _loadout_panel.visible:
		return true
	if _ui.is_open() or _settings_open() or (_codex != null and _codex.visible) or _board_ui.is_open() \
			or _loadout_ui.is_open() or _quick.is_open():
		return true
	if _shop != null and _shop.visible:
		return true
	var dlg := get_node_or_null(^"/root/Dialogue")
	return dlg != null and bool(dlg.call(&"is_active"))


## Walks into the hellgate (charge-up, fade), then calls `then` (Meta.start_run_with_loadout /
## Meta.start_trial / Meta.start_run).
func _enter_gate(then: Callable = Callable()) -> void:
	if _leaving:
		return
	if not then.is_valid():
		then = Meta.start_run
	_leaving = true
	avatar.frozen = true
	avatar.face(GATE + Vector3(0.0, 0.0, -1.0))
	avatar.cheer()
	Sfx.play(&"cast", 0.05)
	Sfx.play(&"boss_charge", 0.0, -6.0)
	Sfx.play(&"portal_enter", 0.0, -2.0)
	run_starting.emit()
	var tw := create_tween()
	scenery.gate_charging = true
	var surface := scenery.gate_surface
	tw.tween_method(func(v: float) -> void: surface.set_instance_shader_parameter(&"charge", v), 0.0, 1.0, 1.2)
	tw.parallel().tween_property(scenery.gate_light, "light_energy", 12.0, 1.2)
	tw.parallel().tween_property(self, "_cam_zoom", 0.75, 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_fade, "color", Color(0.25, 0.02, 0.0, 1.0), 1.4).from(Color(0.25, 0.02, 0.0, 0.0)) \
		.set_delay(0.3)
	tw.tween_property(_fade, "color", Color(0.0, 0.0, 0.0, 1.0), 0.3)
	tw.tween_callback(then)


func _change_demon() -> void:
	if _leaving:
		return
	_leaving = true
	avatar.frozen = true
	Sfx.play(&"ui_click")
	var tw := _fade.create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.7)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(DEMON_SELECT_SCENE))


func _open_settings() -> void:
	if _settings == null:
		var ps := load(SETTINGS_SCENE) as PackedScene
		if ps == null:
			return
		_settings = ps.instantiate() as CanvasLayer
		add_child(_settings)
		if _settings.has_signal(&"closed"):
			_settings.connect(&"closed", func() -> void: avatar.frozen = false)
	avatar.frozen = true
	_settings.call(&"open")


func _settings_open() -> bool:
	return _settings != null and _settings.visible


func _unhandled_input(event: InputEvent) -> void:
	if _leaving or _menu_open():
		return
	if _pit.active:
		if event.is_action_pressed(&"interact") or event.is_action_pressed(&"pause") \
				or event.is_action_pressed(&"ui_cancel"):
			_leave_pit()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_accept"):
		if _active:
			_active.interact()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"pause"):
		_open_settings()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"hub_menu"):
		avatar.frozen = true
		_quick.open(_quick_entries())
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo 			and (event as InputEventKey).physical_keycode == KEY_C:
		_open_codex()
		get_viewport().set_input_as_handled()


## The lore Codex (scenes/ui/codex_screen.gd, UI role).
func _open_codex() -> void:
	if _codex == null:
		_codex = CodexScreen.new()
		add_child(_codex)
		_codex.connect(&"closed", func() -> void: avatar.frozen = false)
	avatar.frozen = true
	_codex.call(&"open")


# ---------------------------------------------------------------- per-frame

func _process(delta: float) -> void:
	_update_focus()
	_update_camera(delta)


## Picks the nearest interactable in range and shows its prompt.
func _update_focus() -> void:
	if _menu_open() or _pit.active:
		return
	var best: HubInteractable = null
	var best_d := INF
	if not _leaving:
		for n in get_tree().get_nodes_in_group(&"hub_interactables"):
			var it := n as HubInteractable
			var d := it.flat_distance(avatar.global_position)
			it.set_near(d < NAME_RANGE)
			if d < it.radius and d < best_d:
				best_d = d
				best = it
	if best != _active:
		if _active and is_instance_valid(_active):
			_active.set_focused(false)
		_active = best
		if _active:
			_active.set_focused(true)
			Sfx.play(&"ui_hover", 0.05, -4.0)


func _update_camera(delta: float) -> void:
	if avatar == null:
		return
	# Follow the training Player while the Proving Pit is in use.
	var target := _pit.player.global_position if _pit and _pit.active and is_instance_valid(_pit.player) \
		else avatar.global_position
	# Keep the framing inside the plateau.
	target.x = clampf(target.x, X0 + 6.0, X1 - 6.0)
	target.z = clampf(target.z, Z0 + 1.0, Z1 - 4.0)
	_cam_focus = _cam_focus.lerp(target, 1.0 - exp(-5.0 * delta))
	var dist := CAM_DIST * _cam_zoom
	var offset := Vector3(0.0, sin(CAM_PITCH), cos(CAM_PITCH)) * dist
	# Aim north of the avatar, more so near the gate, so the hellgate stays in frame.
	var north := lerpf(1.5, 4.0, smoothstep(-3.0, -8.0, _cam_focus.z))
	var look := _cam_focus + Vector3(0.0, 0.8, -north)
	_camera.position = look + offset
	_camera.look_at(look, Vector3.UP)


# ---------------------------------------------------------------- dev

## Dev args (after "--"), for screenshots and smoke tests:
##   --hub-at=<blacksmith|occultist|soul_broker|cartographer|gate|circle|covenant|pit|ledger|trophies|bar|
##             quarry|kennel|monument>  start next to it
##   --hub-open=<shop id|shop:<id>|maps|pacts|rites|ledger|trophies|loadout|trials|quick>  open after 1 s
##   --hub-pit=<ability id,...>        enter the Proving Pit with those rites after a second
##   --camp=<0..3>                     force the camp development level (HubLife)
##   --hub-enter                       walk through the hellgate after two seconds
func _dev_args() -> void:
	var spots := {
		"blacksmith": SMITH, "occultist": OCCULT, "soul_broker": BROKER, "cartographer": CARTO,
		"gate": GATE + Vector3(0.0, 0.0, 1.6), "circle": CIRCLE, "covenant": COVENANT,
		"pit": HubPit.CENTER + Vector3(-HubPit.RADIUS - 0.8, 0.0, 0.4), "ledger": HubBoards.LEDGER,
		"trophies": HubBoards.WALL + Vector3(0.0, 0.0, 2.2), "bar": HubLife.BAR + Vector3(2.0, 0.0, 0.0),
		"quarry": HubLife.QUARRY + Vector3(2.0, 0.0, 3.0), "kennel": HubLife.KENNEL, "monument": HubLife.MONUMENT,
		"trials": HubBoards.TRIALS + Vector3(0.0, 0.0, 1.0), "captive": HubLife.CAPTIVE, "throne": HubLife.THRONE,
	}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hub-at="):
			var key := arg.substr(9)
			if spots.has(key):
				# Stand a little toward the plaza centre so the merchant is in range and in view.
				var at: Vector3 = spots[key]
				avatar.position = at + (Vector3(0.0, 0.0, 3.0) - at).normalized() * 1.8
				_cam_focus = avatar.position
				_update_camera(1.0)
		elif arg.begins_with("--hub-open="):
			var what := arg.substr(11)
			await get_tree().create_timer(1.0).timeout
			if what == "maps":
				_ui.open_maps()
			elif what == "pacts":
				_ui.open_pacts()
			elif what == "rites":
				_open_pit_menu()
			elif what == "loadout":
				_open_loadout()
			elif what == "trials":
				_boards.open_trials()
			elif what == "quick":
				avatar.frozen = true
				_quick.open(_quick_entries())
			elif what == "ledger":
				_boards.open_ledger()
			elif what == "trophies":
				_boards.open_trophies()
			elif what.begins_with("shop:"):  # straight to the wares, skipping any dialogue
				avatar.frozen = true
				_open_shop_panel(what.substr(5))
			elif _merchants.has(what):
				_open_merchant(_merchants[what])
		elif arg.begins_with("--hub-pit="):
			await get_tree().create_timer(1.0).timeout
			var ids := Array(arg.substr(10).split(",", false))
			_enter_pit(ids)
		elif arg == "--hub-enter":
			await get_tree().create_timer(2.0).timeout
			_enter_gate()
