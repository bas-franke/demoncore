class_name AbilityDef
extends RefCounted
## One ability, parsed from an entry of data/abilities/abilities.json (see docs/team/abilities.md).
## Immutable after parsing; per-run state (level, cooldown) lives on the AbilityCaster.
##
## Level scaling: levels[i] holds the deltas for reaching rank i + 2. Keys:
##   "text"          upgrade text shown on the level-up card
##   "damage"        +fraction to the damage multiplier (0.3 = +30% of base)
##   "cooldown"      +fraction to the cooldown multiplier (-0.2 = 20% faster), floored at 0.25
##   "status_stacks" extra stacks for every status this ability applies
##   anything else   added to params[key] (count, radius, pierce, duration, ...)

var id: StringName
var name := ""
var school := ""
var tags := PackedStringArray()
var icon := "?"
var color := Color.WHITE
var desc := ""
## Behaviour archetype implemented by AbilityCaster (bolt, nova, aura, zone, chain, strike, ...).
var kind: StringName
var cooldown := 1.0
var damage := 0.0
## Fraction of max HP spent per cast (blood magic). 0 = free.
var hp_cost := 0.0
var params := {}  # String -> Variant (mostly float)
var status: Array = []  # Array of {"id": String, "stacks": int}
var on_hit: Array = []  # Array of effect dictionaries (see AbilityCombat.run_effect)
var on_kill: Array = []
## Effects run at the point of impact after the ability resolves (e.g. a burning crater).
var after: Array = []
var levels: Array = []  # Array of Dictionary


static func from_dict(d: Dictionary) -> AbilityDef:
	var a := AbilityDef.new()
	a.id = StringName(str(d.get("id", "")))
	a.name = str(d.get("name", a.id))
	a.school = str(d.get("school", ""))
	for t: Variant in d.get("tags", []):
		a.tags.append(str(t))
	a.icon = str(d.get("icon", "?"))
	a.color = Color.from_string(str(d.get("color", "#ffffff")), Color.WHITE)
	a.desc = str(d.get("desc", ""))
	a.kind = StringName(str(d.get("kind", "bolt")))
	a.cooldown = float(d.get("cooldown", 1.0))
	a.damage = float(d.get("damage", 0.0))
	a.hp_cost = float(d.get("hp_cost", 0.0))
	a.params = (d.get("params", {}) as Dictionary).duplicate(true)
	a.status = (d.get("status", []) as Array).duplicate(true)
	a.on_hit = (d.get("on_hit", []) as Array).duplicate(true)
	a.on_kill = (d.get("on_kill", []) as Array).duplicate(true)
	a.after = (d.get("after", []) as Array).duplicate(true)
	a.levels = (d.get("levels", []) as Array).duplicate(true)
	return a


func has_tag(tag: String) -> bool:
	return tags.has(tag)


func max_level() -> int:
	return levels.size() + 1


## Upgrade text for reaching `lv` (2..max_level).
func level_text(lv: int) -> String:
	var i := lv - 2
	if i < 0 or i >= levels.size():
		return ""
	return str((levels[i] as Dictionary).get("text", ""))


## Params plus the accumulated level deltas at rank `lv`, with the special keys
## "damage_mult", "cooldown_mult" and "status_stacks".
func stats_at(lv: int) -> Dictionary:
	var s := params.duplicate(true)
	s["damage_mult"] = 1.0
	s["cooldown_mult"] = 1.0
	s["status_stacks"] = 0.0
	for i in mini(lv - 1, levels.size()):
		var step: Dictionary = levels[i]
		for key: String in step:
			if key == "text":
				continue
			var v: Variant = step[key]
			if not (v is float or v is int):
				continue
			match key:
				"damage":
					s["damage_mult"] = float(s["damage_mult"]) + float(v)
				"cooldown":
					s["cooldown_mult"] = maxf(float(s["cooldown_mult"]) + float(v), 0.25)
				_:
					s[key] = float(s.get(key, 0.0)) + float(v)
	return s
