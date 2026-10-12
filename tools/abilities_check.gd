extends SceneTree
## Validates data/abilities/*.json without running the game:
##   <godot> --headless --path . --script res://tools/abilities_check.gd
## Checks kinds, status ids, effect types, synergy tags, boon mod keys and level deltas.
## Prints a summary and exits with code 1 on any error.

const KINDS := ["bolt", "nova", "aura", "zone", "chain", "strike", "summon", "orbit", "cone", "line",
	"hook", "blink", "hex", "buff", "corpse", "harvest", "retaliate", "reflect", "mimic", "pride", "devour",
	"turret", "mine", "decoy", "whip"]
const EFFECTS := ["status", "explode", "chain", "heal", "soul", "zone", "spread", "empower", "ichor", "wrath",
	"raise", "decoy"]
## Boon mod keys (prefixed ones take a tag or status id after the colon).
const MOD_KEYS := ["damage", "cooldown", "area", "count", "duration", "crit", "crit_mult", "hp_cost_cut",
	"summon_count", "corpse_life", "dot_rate", "jumps", "execute", "knockback", "root_amp", "soul_cap",
	"soul_bonus", "wrath_gain", "wrath_cap"]
const MOD_PREFIXES := ["tag:", "tagcd:", "tagcrit:", "power:", "max:", "dur:", "spread:"]

var _errors := 0


func _init() -> void:
	var a := _json("abilities.json")
	var statuses: Dictionary = a.get("statuses", {})
	var all_tags := {}
	var ids := {}
	for d: Dictionary in a.get("abilities", []):
		var id := str(d.get("id", ""))
		if ids.has(id):
			_err("duplicate ability id %s" % id)
		ids[id] = true
		if not KINDS.has(str(d.get("kind", ""))):
			_err("%s: unknown kind %s" % [id, d.get("kind")])
		for t: Variant in d.get("tags", []):
			all_tags[str(t)] = true
		for s: Dictionary in d.get("status", []):
			if not statuses.has(str(s.get("id", ""))):
				_err("%s: unknown status %s" % [id, s.get("id")])
		for key in ["on_hit", "on_kill", "after"]:
			for fx: Dictionary in d.get(key, []):
				_check_effect(id, fx, statuses)
		for step: Dictionary in d.get("levels", []):
			if not step.has("text"):
				_err("%s: level step without text" % id)
			for k: String in step:
				if k != "text" and not (step[k] is float or step[k] is int):
					_err("%s: level key %s is not a number" % [id, k])
	for t: Variant in a.get("weapon_tags", {}).values():
		for tag: Variant in t:
			all_tags[str(tag)] = true

	var syn := _json("synergies.json").get("synergies", []) as Array
	for s: Dictionary in syn:
		for tag: String in s.get("requires", {}):
			if not all_tags.has(tag):
				_err("synergy %s needs tag %s that nothing has" % [s.get("id"), tag])
		for key in ["on_hit", "on_kill"]:
			for fx: Dictionary in (s.get(key, {}) as Dictionary).get("effects", []):
				_check_effect(str(s.get("id")), fx, statuses)
		for st: Dictionary in (s.get("hit_status", {}) as Dictionary).get("status", []):
			if not statuses.has(str(st.get("id", ""))):
				_err("synergy %s: unknown status %s" % [s.get("id"), st.get("id")])

	var evos := _json("evolutions.json").get("evolutions", []) as Array
	var boon_ids := {}
	for b: Dictionary in _json("boons.json").get("boons", []):
		boon_ids[str(b.get("id"))] = true
	for e: Dictionary in evos:
		if not ids.has(str(e.get("from", ""))):
			_err("evolution %s: unknown base ability %s" % [e.get("id"), e.get("from")])
		if not boon_ids.has(str(e.get("boon", ""))):
			_err("evolution %s: unknown boon %s" % [e.get("id"), e.get("boon")])
		var into: Dictionary = e.get("ability", {})
		if not KINDS.has(str(into.get("kind", ""))):
			_err("evolution %s: unknown kind %s" % [e.get("id"), into.get("kind")])

	var boons := _json("boons.json").get("boons", []) as Array
	var schools := {}
	for d: Dictionary in a.get("abilities", []):
		schools[str(d.get("school", ""))] = true
	for demon: String in a.get("demon_affinity", {}):
		if demon != "_doc" and not schools.has(str(a["demon_affinity"][demon].get("school", ""))):
			_err("demon_affinity %s: unknown school" % demon)
	for b: Dictionary in boons:
		for t: Variant in b.get("requires_all", []):
			if not all_tags.has(str(t)):
				_err("boon %s requires tag %s that nothing has" % [b.get("id"), t])
		for k: String in b.get("mods", {}):
			if not MOD_KEYS.has(k) and not MOD_PREFIXES.any(func(p: String) -> bool: return k.begins_with(p)):
				_err("boon %s: unknown mod key %s" % [b.get("id"), k])
		for key in ["on_hit", "on_kill"]:
			for fx: Dictionary in b.get(key, []):
				_check_effect(str(b.get("id")), fx, statuses)

	print("abilities_check: %d abilities, %d synergies, %d boons, %d evolutions, %d statuses, %d error(s)" % [
		ids.size(), syn.size(), boons.size(), evos.size(), statuses.size(), _errors])
	quit(1 if _errors > 0 else 0)


func _check_effect(owner: String, fx: Dictionary, statuses: Dictionary) -> void:
	if not EFFECTS.has(str(fx.get("do", ""))):
		_err("%s: unknown effect %s" % [owner, fx.get("do")])
	var st: Variant = fx.get("status", [])
	if st is Array:
		for s: Dictionary in st:
			if not statuses.has(str(s.get("id", ""))):
				_err("%s: effect uses unknown status %s" % [owner, s.get("id")])
	elif not statuses.has(str(st)):
		_err("%s: effect uses unknown status %s" % [owner, st])


func _json(file: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities/" + file))
	if not parsed is Dictionary:
		_err("cannot parse %s" % file)
		return {}
	return parsed


func _err(msg: String) -> void:
	_errors += 1
	push_error(msg)
	print("ERROR: ", msg)
