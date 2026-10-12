class_name RunLoadout
## Pre-run loadout options for the hellgate (basecamp role): the starting weapon, a starting
## ability and a keepsake. Static helpers over other systems' data; the chosen loadout itself is
## stored in Meta.loadout and applied by Meta when the run's Player spawns.
##
##   RunLoadout.weapons()     # [{path, name, icon, description, unlocked}]  (weapon_pool scenes)
##   RunLoadout.abilities()   # [{id, name, icon, school, description, color, unlocked}]
##   RunLoadout.keepsakes()   # [{id, name, icon, description, giver, giver_name, min_affinity,
##                            #   affinity, available, effects}]  (data/meta/keepsakes.json)
##   RunLoadout.apply_effects(player, effects)   # {stat, amount} / {type: run_stat, stat, amount}

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const KEEPSAKES_PATH := "res://data/meta/keepsakes.json"

static var _weapons: Array[Dictionary] = []
static var _keepsakes: Array[Dictionary] = []


## Every weapon in the Player's level-up pool (the same list a run offers), with display info read
## from an uninstanced template. `unlocked` follows Progression's weapon unlocks.
static func weapons() -> Array[Dictionary]:
	if _weapons.is_empty():
		var ps := load(PLAYER_SCENE) as PackedScene
		var probe := ps.instantiate() if ps else null
		if probe:
			for scene: PackedScene in probe.get(&"weapon_pool"):
				var w := scene.instantiate() as Weapon
				if w == null:
					continue
				_weapons.append({"path": scene.resource_path, "name": w.display_name, "icon": w.icon,
						"description": w.description, "unlocked": true})
				w.free()
			probe.free()
	var prog := _node(^"Progression")
	for w in _weapons:
		w.unlocked = prog == null or bool(prog.call(&"is_weapon_unlocked", load(String(w.path))))
	return _weapons


## Every ability in the Abilities registry, sorted by school then name.
static func abilities() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ab := _node(^"Abilities")
	if ab == null:
		return out
	var prog := _node(^"Progression")
	var defs: Dictionary = ab.get(&"defs")
	for id: StringName in defs:
		var d := defs[id] as AbilityDef
		out.append({"id": String(id), "name": d.name, "icon": d.icon, "school": d.school,
				"description": d.desc, "color": d.color,
				"unlocked": prog == null or bool(prog.call(&"is_ability_unlocked", id))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.school) + String(a.name) < String(b.school) + String(b.name))
	return out


## Keepsakes with their giver's current affinity (Dialogue role: 0..5, raised by offerings).
static func keepsakes() -> Array[Dictionary]:
	if _keepsakes.is_empty():
		var parsed := JsonIO.read_dict(KEEPSAKES_PATH, "RunLoadout", true)
		for k: Variant in parsed.get("keepsakes", []):
			if k is Dictionary and (k as Dictionary).has("id"):
				_keepsakes.append(k)
	var dlg := _node(^"Dialogue")
	var out: Array[Dictionary] = []
	for k in _keepsakes:
		var e := k.duplicate()
		var giver := String(k.get("giver", ""))
		e.affinity = int(dlg.call(&"affinity", giver)) if dlg else 0
		e.available = int(e.affinity) >= int(k.get("min_affinity", 3))
		var sp: Dictionary = dlg.call(&"speaker", giver) if dlg else {}
		e.giver_name = String(sp.get("name", giver.capitalize()))
		out.append(e)
	return out


static func keepsake(id: String) -> Dictionary:
	for k in keepsakes():
		if String(k.id) == id:
			return k
	return {}


## Applies modifier effects to a freshly ready Player: {stat, amount} -> Player.apply_stat,
## {type: run_stat, stat, amount} -> Progression.apply_stat (luck, rerolls, ...). Other types
## (soul_gain, heat, score_mult, random_ability) are handled by Meta.
static func apply_effects(player: Node, effects: Array) -> void:
	var prog := _node(^"Progression")
	for e: Dictionary in effects:
		if e.has("stat") and String(e.get("type", "")) == "":
			player.call(&"apply_stat", StringName(e.stat), float(e.get("amount", 0.0)))
		elif String(e.get("type", "")) == "run_stat" and prog:
			prog.call(&"apply_stat", StringName(e.get("stat", "")), float(e.get("amount", 0.0)))


## Sum of `amount` over effects of `type` (e.g. "soul_gain", "heat", "score_mult").
static func total(effects: Array, type: String) -> float:
	var t := 0.0
	for e: Dictionary in effects:
		if String(e.get("type", "")) == type:
			t += float(e.get("amount", 0.0))
	return t


static func _node(path: NodePath) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(path) if tree else null
