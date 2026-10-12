class_name RelicView
## Builders for showing Progression relics consistently (pause inventory, Codex tab, end ledger):
## a painted icon (GlyphIcon) in a rarity-coloured frame, the name, rarity pips + tier name
## (colour-blind safe) and the description. Static helpers only.
##
##   RelicView.row(Progression.get_relic(id))        # full row with description
##   RelicView.chip(relic, 40.0)                      # framed icon with a tooltip
## Relic dictionaries: {name, icon, tier (int) or rarity (id), description}; codex entries may add
## {discovered: bool, times_found: int} (undiscovered ones render as a dim "???" silhouette).


static func rarity_id(r: Dictionary) -> StringName:
	if r.has("rarity"):
		return StringName(str(r.rarity))
	return Rarity.id_of(int(r.get("tier", 0)))


static func chip(r: Dictionary, side := 40.0) -> PanelContainer:
	var known := bool(r.get("discovered", true))
	var col := UIPalette.rarity_color(rarity_id(r)) if known else UIPalette.LOCKED
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(side, side)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := UIPalette.box(UIPalette.SCORCH.lerp(col, 0.12), Color(col, 0.85), 1, 3, 3.0)
	sb.shadow_color = Color(col, 0.18)
	sb.shadow_size = 6
	frame.add_theme_stylebox_override(&"panel", sb)
	var g := GlyphIcon.new()
	g.glyph = str(r.get("icon", "✦")) if known else "?"
	g.color = col.lerp(UIPalette.BONE_BRIGHT, 0.3) if known else UIPalette.SMOKE
	frame.add_child(g)
	frame.tooltip_text = "%s\n%s" % [r.get("name", ""), r.get("description", "")] if known else "Undiscovered relic"
	return frame


static func row(r: Dictionary, show_count := false) -> HBoxContainer:
	var known := bool(r.get("discovered", true))
	var rid := rarity_id(r)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 10)
	h.add_child(chip(r, 38.0))
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override(&"separation", 0)
	h.add_child(texts)
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 8)
	texts.add_child(top)
	var n := Label.new()
	n.theme_type_variation = &"InkLabel"
	n.add_theme_font_size_override(&"font_size", 17)
	n.text = str(r.get("name", "")) if known else "???"
	n.add_theme_color_override(&"font_color", UIPalette.BONE_BRIGHT if known else UIPalette.SMOKE)
	top.add_child(n)
	var tier := Label.new()
	tier.theme_type_variation = &"CaptionLabel"
	tier.add_theme_font_size_override(&"font_size", 11)
	tier.text = "%s %s" % [UIPalette.rarity_mark(rid), String(rid).to_upper()]
	tier.add_theme_color_override(&"font_color", UIPalette.rarity_color(rid) if known else UIPalette.SMOKE)
	tier.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(tier)
	if show_count and known and int(r.get("times_found", 0)) > 1:
		var c := Label.new()
		c.theme_type_variation = &"CaptionLabel"
		c.text = "×%d" % int(r.times_found)
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(c)
	var d := Label.new()
	d.theme_type_variation = &"LoreLabel"
	d.add_theme_font_size_override(&"font_size", 14)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = 160.0
	d.text = str(r.get("description", "")) if known else "Not yet found. Elites and bosses carry relics."
	texts.add_child(d)
	return h
