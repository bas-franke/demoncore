extends Control
## UI gallery for visual checks of the shared components and screens (owned by the UI role).
## Run windowed and screenshot:
##   godot --path . res://tools/ui/ui_gallery.tscn -- --view=shop --shot=user://shop.png --shot-time=1.5
## Views: components (default), shop, run_end (plays main.tscn, ends the run after 3 s),
##        victory (same, but a won run), levelup (main.tscn, forces a level-up after 3 s),
##        title (title scene, opens the main menu at 8 s), settings / controls (settings overlay pages),
##        pause (main.tscn, opens the pause menu after 3 s), access (settings accessibility page),
##        list (ListPanel + ChoiceRows, maps and pacts), codex (CodexScreen), glyphs (GlyphIcon sheet),
##        synergy (main.tscn + a synergy banner after 3 s), loadout (LoadoutPanel with RunLoadout data),
##        credits, mapview (main.tscn, map overview at 4 s), ledger (main.tscn, run ends, full ledger).

var _shop: ShopPanel
var _slots: Array[CooldownSlot] = []
var _t := 0.0


func _ready() -> void:
	var view := "components"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--view="):
			view = arg.substr(7)
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.1, 0.08)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	match view:
		"shop":
			_open_shop()
		"run_end", "victory", "levelup", "pause", "synergy", "mapview", "ledger":
			_run_scene(view)
		"title":
			var title: Node = load("res://scenes/menu/title.tscn").instantiate()
			add_child(title)
			await get_tree().create_timer(8.0).timeout
			title.call(&"_open_menu")
		"list":
			_open_list()
		"loadout":
			var lp := LoadoutPanel.new()
			add_child(lp)
			lp.open({"title": "The Hellgate", "subtitle": "Kesh holds the chain. Choose what you carry.",
				"current": {"weapon": "", "ability": "", "keepsake": ""}, "weapons": RunLoadout.weapons(),
				"abilities": RunLoadout.abilities(), "keepsakes": RunLoadout.keepsakes()})
		"credits":
			var cr := CreditsScreen.new()
			add_child(cr)
			cr.open()
		"codex":
			var cx := CodexScreen.new()
			add_child(cx)
			cx.open()
		"glyphs":
			var grid := GridContainer.new()
			grid.columns = 10
			grid.position = Vector2(40, 40)
			grid.add_theme_constant_override(&"h_separation", 18)
			grid.add_theme_constant_override(&"v_separation", 18)
			add_child(grid)
			for g: String in GlyphIcon.MAP.keys() + ["✦", "✠", "☾", "♆"]:
				var gi := GlyphIcon.new()
				gi.glyph = g
				gi.color = UIPalette.WRATH if grid.get_child_count() % 2 == 0 else UIPalette.HOLY_GOLD
				gi.custom_minimum_size = Vector2(56, 56)
				grid.add_child(gi)
		"settings", "controls", "graphics", "access":
			var sm: CanvasLayer = load("res://scenes/ui/settings_menu.tscn").instantiate()
			add_child(sm)
			sm.call(&"open")
			sm.call(&"_show_page", {"settings": 0, "graphics": 1, "controls": 2, "access": 3}[view], false)
			if "--dump" in OS.get_cmdline_user_args():
				await get_tree().create_timer(0.5).timeout
				dump_sizes(_shop.get_child(0))
		_:
			_components()


func _process(delta: float) -> void:
	_t += delta
	for i in _slots.size():
		var total := 4.0 + i * 2.0
		_slots[i].set_cooldown(maxf(0.0, total * (0.9 - 0.2 * i) - fmod(_t, total)), total)


func _components() -> void:
	var col := VBoxContainer.new()
	col.position = Vector2(40, 30)
	col.add_theme_constant_override(&"separation", 14)
	add_child(col)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = "DEMONCORE"
	col.add_child(title)
	for v: StringName in [&"HeaderLabel", &"InkLabel", &"LoreLabel", &"CaptionLabel", &"ValueLabel", &"CostLabel", &"DangerLabel"]:
		var l := Label.new()
		l.theme_type_variation = v
		l.text = "%s - Heaven's walls will fall 1234" % v
		col.add_child(l)
	var bars := VBoxContainer.new()
	col.add_child(bars)
	var hp := InfernalBar.new()
	hp.custom_minimum_size = Vector2(320, 14)
	hp.set_values(64, 100)
	hp.text_mode = InfernalBar.TEXT_VALUE_MAX
	hp.segment_value = 25
	bars.add_child(hp)
	var res := InfernalBar.new()
	res.custom_minimum_size = Vector2(260, 8)
	res.fill_color = UIPalette.WRATH
	res.set_values(40, 100)
	bars.add_child(res)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	col.add_child(row)
	for i in 4:
		var s := CooldownSlot.new()
		s.setup(StringName("a%d" % i), "Ability %d" % i, null, ["⚡", "☄", "✠", "♆"][i], [UIPalette.WRATH, UIPalette.BLOOD_BRIGHT, UIPalette.SOUL, UIPalette.HELLFIRE][i], ["SPACE", "Q", "E", "R"][i])
		if i == 2:
			s.set_charges(2)
		row.add_child(s)
		_slots.append(s)
	var cc := CurrencyCounter.new()
	cc.setup("◈", UIPalette.SOUL, "Souls")
	cc.set_amount(12345, true)
	col.add_child(cc)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override(&"separation", 12)
	col.add_child(btns)
	for v: StringName in [&"", &"AccentButton", &"GhostButton", &"TabButton", &"CardButton"]:
		var b := Button.new()
		b.theme_type_variation = v
		b.text = "Descend" if v == &"" else String(v)
		btns.add_child(b)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"InfernalPanel"
	panel.position = Vector2(760, 40)
	var pl := Label.new()
	pl.text = "InfernalPanel\nheavy modal frame"
	panel.add_child(pl)
	add_child(panel)


func _run_scene(view: String) -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(3.0).timeout
	if view == "levelup":
		var p := Game.player
		p.add_xp((p.xp_to_next - p.xp) / p.xp_gain + 0.01)
	elif view == "mapview":
		await get_tree().create_timer(1.0).timeout
		get_tree().get_first_node_in_group(&"hud").get(&"widgets").get_children().filter(
			func(c: Node) -> bool: return c is MapOverview)[0].call(&"open")
	elif view == "ledger":
		for i in 40:
			Game.enemy_struck.emit(null, randf_range(5.0, 60.0))
		RunState.end_run(false)
		await get_tree().create_timer(6.0).timeout
		var go := main.get_node(^"GameOver")
		for n in go.find_children("*", "RunLedger", true, false):
			(n as RunLedger).call(&"_open_breakdown")
	elif view == "synergy":
		get_tree().get_first_node_in_group(&"hud").call(&"synergy_banner", "Explosive Miasma",
			"Plague clouds detonate when set alight.", Color("9be05a"))
	elif view == "pause":
		main.get_node(^"PauseMenu").call(&"open")
	else:
		RunState.end_run(view == "victory")


func _open_list() -> void:
	var lp := ListPanel.new()
	add_child(lp)
	var ranks := {"zeal": 1, "famine": 0}
	lp.open({
		"title": "Ossek the Cartographer", "subtitle": "Every road ends in a cathedral, little flame.",
		"wallet": {"glyph": "◈", "color": UIPalette.SOUL, "name": "Souls", "amount": 340},
		"gauge": func() -> Dictionary:
			var h: int = ranks.zeal * 2 + ranks.famine
			return {"label": "HEAT", "value": h, "max": 10, "color": UIPalette.BLOOD_BRIGHT, "text": "+%d%% souls" % (h * 10)},
		"rows": func() -> Array:
			var out: Array = []
			var a := ChoiceRow.new()
			a.setup({"glyph": "⛧", "color": UIPalette.EMBER, "title": "The Ruined Sanctum", "subtitle": "where it began",
				"description": "Broken pews and a sky that will not close.", "tags": ["PERIL ✠"], "state": &"chosen"})
			a.add_action("Chosen", func() -> void: pass, &"", true)
			out.append(a)
			var b := ChoiceRow.new()
			b.setup({"glyph": "♛", "color": UIPalette.HOLY_GOLD, "title": "Cathedral City", "subtitle": "white spires",
				"description": "Bells, censers and a choir that never stops.", "tags": ["PERIL ✠✠✠", "BOSS: OZIAS"], "state": &"available"})
			b.add_action("Choose", func() -> void: pass, &"AccentButton")
			out.append(b)
			var c := ChoiceRow.new()
			c.setup({"glyph": "🔒", "title": "The Frozen Monastery", "description": "Sealed.", "state": &"locked",
				"note": "Requires Cathedral City cleared"})
			c.add_action("Unseal ◈ 500", func() -> void: pass, &"AccentButton", true)
			out.append(c)
			for id: String in ["zeal", "famine"]:
				var pr := ChoiceRow.new()
				pr.setup({"glyph": "⚡" if id == "zeal" else "☠", "color": UIPalette.BLOOD_BRIGHT,
					"title": "Pact of " + id.capitalize(), "description": "Angels strike harder.",
					"tags": ["+%d HEAT / RANK" % (2 if id == "zeal" else 1)],
					"state": &"active" if ranks[id] > 0 else &"available"})
				pr.add_stepper(ranks[id], 3, func(r: int) -> void:
					ranks[id] = clampi(r, 0, 3)
					lp.refresh())
				out.append(pr)
			return out,
	})


func _open_shop() -> void:
	_shop = load("res://ui/components/shop_panel.tscn").instantiate()
	add_child(_shop)
	var wallet := [340]
	var items := [
		{"id": "vigor", "name": "Unholy Vigor", "description": "+10 maximum life per rank.", "glyph": "♥", "color": UIPalette.BLOOD_BRIGHT, "cost": 120, "level": 2, "max_level": 5, "rarity": "common", "category": "Flesh", "effect_now": "+20 life", "effect_next": "+30 life", "flavor": "Stitched with the sinews of saints."},
		{"id": "wrath", "name": "Searing Wrath", "description": "+5% damage per rank.", "glyph": "🔥", "color": UIPalette.WRATH, "cost": 200, "level": 0, "max_level": 5, "rarity": "uncommon", "category": "Flesh"},
		{"id": "wings", "name": "Tattered Wings", "description": "Unlocks a second dash charge.", "glyph": "⚶", "color": UIPalette.SOUL, "cost": 900, "max_level": 0, "rarity": "epic", "category": "Flesh"},
		{"id": "horns", "name": "Crown of Horns", "description": "Bosses take 15% more damage.", "glyph": "♛", "cost": 500, "level": 3, "max_level": 3, "rarity": "rare", "category": "Flesh"},
		{"id": "pact", "name": "Pact of Ash", "description": "Start each run with a random boon.", "glyph": "✠", "cost": 300, "rarity": "legendary", "category": "Fate"},
		{"id": "shard", "name": "Shard of Pride", "description": "+1 reroll per run.", "glyph": "✧", "cost": 3, "currency_glyph": "✧", "currency_color": UIPalette.HOLY_BLUE, "currency_name": "Sin Shards", "currency_amount": 2, "category": "Fate", "rarity": "rare"},
		{"id": "sealed", "name": "???", "locked": true, "locked_reason": "Slay the Grand Inquisitor to unseal.", "cost": 1000, "category": "Fate"},
	]
	_shop.open({
		"title": "Mother Marrow", "subtitle": "Flesh is only a first draft, darling.",
		"wallets": [{"glyph": "✧", "color": UIPalette.HOLY_BLUE, "name": "Sin Shards", "amount": 2}],
		"currency": func() -> int: return wallet[0],
		"items": func() -> Array: return items,
		"buy": func(id: String) -> bool:
			for it: Dictionary in items:
				if it.id == id and int(it.get("cost", 0)) <= wallet[0]:
					wallet[0] -= int(it.cost)
					it.level = int(it.get("level", 0)) + 1
					it.owned = true
					return true
			return false,
	})


## Prints the minimum size of every Control under `n` (layout debugging).
func dump_sizes(n: Node, depth := 0) -> void:
	var c := n as Control
	if c:
		print("  ".repeat(depth), c.name, " min=", c.get_combined_minimum_size(), " size=", c.size)
	for ch in n.get_children():
		dump_sizes(ch, depth + 1)
