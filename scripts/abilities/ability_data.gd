class_name AbilityData
## Loads data/abilities/*.json into the Abilities autoload (`ab`) at startup: abilities,
## statuses, weapon tags / statuses, demon affinities, synergies, boons and evolutions (whose
## evolved abilities join `defs` but not `def_order`, so they are never offered directly).

const DIR := "res://data/abilities/"


static func load_into(ab: Node) -> void:
	var a := read("abilities.json")
	ab.max_abilities = int(a.get("max_abilities", 5))
	for k: String in a.get("statuses", {}):
		ab.statuses[StringName(k)] = a["statuses"][k]
	ab.weapon_tags = a.get("weapon_tags", {})
	ab.weapon_status = a.get("weapon_status", {})
	ab.demon_affinity = a.get("demon_affinity", {})
	for d: Dictionary in a.get("abilities", []):
		var def := AbilityDef.from_dict(d)
		if ab.defs.has(def.id):
			push_warning("Duplicate ability id '%s'" % def.id)
		ab.defs[def.id] = def
		ab.def_order.append(def.id)
	for s: Dictionary in read("synergies.json").get("synergies", []):
		ab.synergy_defs.append(s)
	for b: Dictionary in read("boons.json").get("boons", []):
		ab.boon_defs[StringName(str(b["id"]))] = b
	for e: Dictionary in read("evolutions.json").get("evolutions", []):
		var into := AbilityDef.from_dict(e["ability"])
		ab.defs[into.id] = into
		ab.evolutions[StringName(str(e["id"]))] = {"from": e["from"], "boon": e["boon"], "into": into.id}


static func read(file: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + file))
	if not parsed is Dictionary:
		push_error("Abilities: could not parse %s" % (DIR + file))
		return {}
	return parsed
