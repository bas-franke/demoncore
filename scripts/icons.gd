class_name Icons
## Painted item icons (res://assets/icons/<id>.png, rendered by tools/blender/render_icons.py).
## Ids are file stems: a weapon's scene file ("hellfire_bolt"), a passive's .tres ("might"), plus
## "heal" (Taste of Blood) and "soul_shard". Every lookup returns null when no icon exists, so
## callers fall back to the text glyph.

const DIR := "res://assets/icons/"

static var _cache := {}


## Icon by id (file stem), or null.
static func get_icon(id: String) -> Texture2D:
	if id.is_empty():
		return null
	if _cache.has(id):
		return _cache[id]
	var path := DIR + id + ".png"
	if not ResourceLoader.exists(path):
		path = DIR + id + ".svg"  # code-authored SVG icons (ability icons)
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_cache[id] = tex
	return tex


## A weapon instance (or template) -> icon from its scene file stem.
static func for_weapon(weapon: Node) -> Texture2D:
	if weapon == null or not is_instance_valid(weapon):
		return null
	return get_icon(_stem(weapon.scene_file_path))


static func for_weapon_scene(scene: PackedScene) -> Texture2D:
	return get_icon(_stem(scene.resource_path)) if scene else null


static func for_passive(p: PassiveData) -> Texture2D:
	return get_icon(_stem(p.resource_path)) if p else null


## Ability icon (res://assets/icons/abilities/<id>.svg, tools/icons/build_ability_icons.py), or null.
static func for_ability(id: StringName) -> Texture2D:
	return get_icon("abilities/" + String(id)) if id != &"" else null


static func soul_shard() -> Texture2D:
	return get_icon("soul_shard")


## Level-up option -> icon, worked out from what the option's callable acts on:
## weapon.level_up (owned weapon), player.add_weapon(scene), player.add_passive(data), player.heal.
static func for_option(option: UpgradeOption) -> Texture2D:
	if option == null:
		return null
	var c := option.apply
	if c.is_valid():
		var obj := c.get_object()
		if obj is Weapon:
			return for_weapon(obj)
		for arg in c.get_bound_arguments():
			if arg is PackedScene:
				return for_weapon_scene(arg)
			if arg is PassiveData:
				return for_passive(arg)
			if arg is StringName:
				# Abilities: grant(id) / evolve(evolution id == the evolved ability's id).
				var t := for_ability(arg)
				if t:
					return t
		if c.get_method() == &"heal":
			return get_icon("heal")
	return null


static func _stem(path: String) -> String:
	return path.get_file().get_basename() if not path.is_empty() else ""
