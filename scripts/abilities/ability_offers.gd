class_name AbilityOffers
## Level-up cards for the ability system (static helpers used by the Abilities autoload, which
## Upgrades.roll calls through Abilities.extend_pool / ensure_choice).
##
## Per roll: up to 2 rank-ups of owned abilities, up to 2 new abilities (weighted toward owned
## tags, toward completing a synergy ("Completes: X") and toward the demon's favoured school),
## up to 2 boons (weighted toward owned tags; duo legendaries need both their schools) and every
## evolution that is ready (maxed ability + its boon).
## Option metas: &"rank" (roman numeral or ✦), &"ability_option" ("new" / "rank" / "boon" /
## "evolve"), &"tags" on new abilities.


static func extend_pool(ab: Node, pool: Array[UpgradeOption]) -> void:
	var ranks: Array[UpgradeOption] = []
	for id: StringName in ab.casters:
		var c: AbilityCaster = ab.casters[id]
		if not c.is_max_level():
			ranks.append(_rank_option(ab, c))
	ranks.shuffle()
	pool.append_array(ranks.slice(0, 2))
	if ab.casters.size() < ab.max_abilities:
		for id in weighted_pick(_ability_candidates(ab), 2):
			pool.append(_new_ability_option(ab, ab.defs[id]))
	for id in weighted_pick(_boon_candidates(ab), 2):
		pool.append(_boon_option(ab, id))
	for evo_id: StringName in ready_evolutions(ab):
		pool.append(_evolve_option(ab, evo_id))


## While the demon has fewer than two abilities, make sure one card offers a new one; a ready
## evolution always gets a card.
static func ensure_choice(ab: Node, picks: Array[UpgradeOption], pool: Array[UpgradeOption]) -> void:
	if picks.is_empty():
		return
	_force(picks, pool, "evolve")
	if ab.casters.size() < 2:
		_force(picks, pool, "new")


static func _force(picks: Array[UpgradeOption], pool: Array[UpgradeOption], kind: String) -> void:
	for o in picks:
		if o.get_meta(&"ability_option", "") == kind:
			return
	for o in pool:
		if o.get_meta(&"ability_option", "") == kind and not picks.has(o):
			picks[randi() % picks.size()] = o
			return


static func weighted_pick(weights: Dictionary, n: int) -> Array[StringName]:
	var out: Array[StringName] = []
	var pool := weights.duplicate()
	for i in n:
		var total := 0.0
		for k: StringName in pool:
			total += float(pool[k])
		if total <= 0.0:
			break
		var r := randf() * total
		for k: StringName in pool:
			r -= float(pool[k])
			if r <= 0.0:
				out.append(k)
				pool.erase(k)
				break
	return out


static func _ability_candidates(ab: Node) -> Dictionary:
	var tags: Dictionary = ab.owned_tags()
	var out := {}  # StringName -> weight
	for id: StringName in ab.def_order:
		if ab.casters.has(id) or not ab.is_unlocked(id):
			continue
		var def: AbilityDef = ab.defs[id]
		var w := 1.0
		for t in def.tags:
			if tags.has(t):
				w += 1.0
		if not ab.synergies_unlocked_by(def.tags).is_empty():
			w += 3.0
		if ab.is_favoured(def):
			w *= ab.affinity_weight()
		out[id] = w
	return out


static func _boon_candidates(ab: Node) -> Dictionary:
	var tags: Dictionary = ab.owned_tags()
	var out := {}
	for id: StringName in ab.boon_defs:
		var b: Dictionary = ab.boon_defs[id]
		if int(ab.boon_stacks.get(id, 0)) >= int(b.get("max", 3)):
			continue
		var req: Array = b.get("requires_tag", [])
		var w := 1.0
		# Duo legendaries need every tag in requires_all (two schools).
		var all_ok := true
		for t: Variant in b.get("requires_all", []):
			if not tags.has(str(t)):
				all_ok = false
		if not all_ok:
			continue
		if not req.is_empty():
			var ok := false
			for t: Variant in req:
				if tags.has(str(t)):
					ok = true
			if not ok:
				continue
			w = 2.5  # boons for what you already wield are worth showing more often
		elif ab.casters.is_empty():
			continue  # generic ability boons are useless before the first ability
		# Boons that feed a ready-to-max ability's evolution are worth flagging.
		if evolution_boons(ab).has(id):
			w += 2.0
		if b.get("legendary", false):
			w = 1.5
		out[id] = w
	return out


static func _synergy_hint(ab: Node, tags: PackedStringArray) -> String:
	var names: Array[String] = ab.synergies_unlocked_by(tags)
	return "" if names.is_empty() else "\nCompletes: %s" % ", ".join(names)


## "Hellfire · fire, area" line for cards, so players can plan synergies.
static func _tag_line(def: AbilityDef) -> String:
	return "%s · %s" % [def.school, ", ".join(def.tags)]


static func _new_ability_option(ab: Node, def: AbilityDef) -> UpgradeOption:
	var fav := ""
	if ab.is_favoured(def):
		fav = "\nFavoured school: +%d%% damage" % roundi(ab.affinity_damage() * 100.0)
	var o := UpgradeOption.new(def.name, "%s\n%s%s%s" % [def.desc, _tag_line(def), fav, _synergy_hint(ab, def.tags)],
		def.color, ab.grant.bind(def.id))
	o.icon = def.icon
	o.is_new = true
	o.set_meta(&"rank", "I")
	o.set_meta(&"ability_option", "new")
	o.set_meta(&"tags", def.tags)
	return o


static func _rank_option(ab: Node, c: AbilityCaster) -> UpgradeOption:
	var text := c.def.level_text(c.level + 1)
	if c.level + 1 >= c.def.max_level():
		var evo: Dictionary = evolution_for(ab, c.def.id)
		if not evo.is_empty():
			text += "\nMaxed + %s boon: evolves into %s" % [ab.boon_name(StringName(str(evo["boon"]))),
				(ab.defs[StringName(str(evo["into"]))] as AbilityDef).name]
	var o := UpgradeOption.new(c.def.name, text, c.def.color, ab.grant.bind(c.def.id))
	o.icon = c.def.icon
	o.set_meta(&"rank", Upgrades.roman(c.level + 1))
	o.set_meta(&"ability_option", "rank")
	return o


static func _boon_option(ab: Node, id: StringName) -> UpgradeOption:
	var b: Dictionary = ab.boon_defs[id]
	var color := Color.from_string(str(b.get("color", "#ffffff")), Color.WHITE)
	var o := UpgradeOption.new(str(b.get("name", id)), str(b.get("desc", "")), color, ab.take_boon.bind(id))
	o.icon = str(b.get("icon", "✦"))
	o.is_new = not ab.boon_stacks.has(id)
	o.set_meta(&"rank", Upgrades.roman(int(ab.boon_stacks.get(id, 0)) + 1))
	o.set_meta(&"ability_option", "boon")
	if b.get("legendary", false):
		o.set_meta(&"rarity", Rarity.LEGENDARY)
	return o


static func _evolve_option(ab: Node, evo_id: StringName) -> UpgradeOption:
	var evo: Dictionary = ab.evolutions[evo_id]
	var into: AbilityDef = ab.defs[StringName(str(evo["into"]))]
	var o := UpgradeOption.new("Evolve: %s" % into.name, "%s\nReplaces %s." % [into.desc,
		(ab.defs[StringName(str(evo["from"]))] as AbilityDef).name], into.color, ab.evolve.bind(evo_id))
	o.icon = into.icon
	o.is_new = true
	o.set_meta(&"rank", "✦")
	o.set_meta(&"ability_option", "evolve")
	return o


# ---------------------------------------------------------------- evolutions

## The evolution entry whose "from" is `ability_id` ({} if none).
static func evolution_for(ab: Node, ability_id: StringName) -> Dictionary:
	for k: StringName in ab.evolutions:
		if StringName(str(ab.evolutions[k]["from"])) == ability_id:
			return ab.evolutions[k]
	return {}


## Evolutions whose base ability is owned and maxed and whose boon has been taken.
static func ready_evolutions(ab: Node) -> Array[StringName]:
	var out: Array[StringName] = []
	for k: StringName in ab.evolutions:
		var e: Dictionary = ab.evolutions[k]
		var c: AbilityCaster = ab.get_caster(StringName(str(e["from"])))
		if c and c.is_max_level() and ab.boon_stacks.has(StringName(str(e["boon"]))) \
				and not ab.casters.has(StringName(str(e["into"]))):
			out.append(k)
	return out


## Boons that would complete an evolution for an owned ability.
static func evolution_boons(ab: Node) -> Array[StringName]:
	var out: Array[StringName] = []
	for k: StringName in ab.evolutions:
		var e: Dictionary = ab.evolutions[k]
		if ab.casters.has(StringName(str(e["from"]))):
			out.append(StringName(str(e["boon"])))
	return out


## Replaces the base ability with its evolved form (rank I of the evolved definition).
static func evolve(ab: Node, evo_id: StringName) -> void:
	var e: Dictionary = ab.evolutions.get(evo_id, {})
	if e.is_empty() or not is_instance_valid(ab.player):
		return
	var from := StringName(str(e["from"]))
	var into: AbilityDef = ab.defs[StringName(str(e["into"]))]
	var old: AbilityCaster = ab.get_caster(from)
	if old:
		ab.casters.erase(from)
		old.queue_free()
	ab.grant(into.id)
	var at: Vector3 = ab.player.global_position
	InfernalFx.flash_sphere(at + Vector3(0.0, 1.0, 0.0), into.color, 2.5, 0.5)
	AbilityFx.ring(at, 6.0, into.color, 0.7)
	ab.ability_evolved.emit(from, into.id)
	var hud: Node = ab.get_tree().get_first_node_in_group(&"hud")
	if hud and hud.has_method(&"toast"):
		hud.call(&"toast", "Evolved: %s" % into.name, into.color)
