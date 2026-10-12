class_name DemonSkins
## Demon skins: palette swaps of the Blender demon models, unlocked by meta progression.
## Data: res://data/skins/skins.json (see its _doc). Stateless helper; the persistent parts (which
## skin each demon wears, unlock state) live in the Progression save when that autoload exists
## (flag "skin:<model_id>", lifetime stats, shop unlocks), else for the session only.
##
##   DemonSkins.list_for(&"vharok") -> Array[Dictionary]       # every skin that fits
##   DemonSkins.is_unlocked(skin) / DemonSkins.unlock_hint(skin)
##   DemonSkins.selected_id(&"vharok") / DemonSkins.select(&"vharok", &"soulfire")
##   DemonSkins.apply(demon_model, &"soulfire")                 # DemonModel.build() applies the
##                                                               # selected skin by itself
## Dev arg: --all-skins (or Progression's --unlock-all) unlocks every skin for the session.
##
## How a skin recolors: each mesh surface's (converted) lit material is duplicated once per
## skin and cached; its `albedo` multiplier is tinted by the category of the Blender material
## name (CATEGORIES), and glowing materials take the skin's glow color.

const DATA_PATH := "res://data/skins/skins.json"
const DEFAULT_ID := &"default"
## Category -> Blender material name keywords (lower case). First match wins, in this order.
const CATEGORIES := [
	["skin", ["skin", "flesh", "lip"]],
	["trim", ["bronze", "gold", "gilt", "brass", "clasp", "key", "halochar", "embroider", "wax"]],
	["horn", ["horn", "claw", "bone", "antler", "fang", "teeth", "tooth", "tusk", "ivory", "spike", "thorn", "mask", "talon", "chitin"]],
	["metal", ["iron", "steel", "plate", "obsidian", "blade", "chain", "armor", "metal"]],
	["cloth", ["cloth", "robe", "silk", "wool", "linen", "rag", "leather", "cord", "rope", "hood", "shroud", "strap",
		"membrane", "hide", "feather", "hair", "tabard", "parchment", "page", "book", "wrap", "belt", "boot", "lining"]],
]

static var _skins: Array[Dictionary] = []
static var _by_id := {}
## Session-only selection when there is no Progression save: model id -> skin id.
static var _session_choice := {}
## [skin id, source material instance id] -> skinned material.
static var _mat_cache := {}
static var _all_unlocked := false
static var _loaded := false


# ---------------------------------------------------------------- catalog

static func all() -> Array[Dictionary]:
	_load()
	return _skins


static func get_skin(id: StringName) -> Dictionary:
	_load()
	return _by_id.get(String(id), {})


## Skins that fit the demon with model id `demon_id` (default first).
static func list_for(demon_id: StringName) -> Array[Dictionary]:
	_load()
	var out: Array[Dictionary] = []
	for s in _skins:
		var demons: Array = s.get("demons", [])
		if demons.is_empty() or demons.has(String(demon_id)):
			out.append(s)
	return out


# ---------------------------------------------------------------- unlocks & selection

static func is_unlocked(skin: Dictionary) -> bool:
	if skin.is_empty():
		return false
	var u: Dictionary = skin.get("unlock", {})
	if u.is_empty() or _all_unlocked:
		return true
	var prog := _progression()
	if prog == null:
		return false
	if u.has("unlock"):
		return bool(prog.call(&"is_unlocked", StringName(u.unlock)))
	if u.has("stat"):
		var stats: Dictionary = prog.get(&"stats")
		return float(stats.get(String(u.stat), 0)) >= float(u.get("min", 1))
	return true


## What the player must do, e.g. "Win a run." (empty when unlocked).
static func unlock_hint(skin: Dictionary) -> String:
	if is_unlocked(skin):
		return ""
	return String(skin.get("hint", "Locked."))


## The skin `demon_id` wears (falls back to the default if the choice is locked / unknown).
static func selected_id(demon_id: StringName) -> StringName:
	var id := DEFAULT_ID
	var prog := _progression()
	if prog:
		id = StringName(str(prog.call(&"get_flag", "skin:%s" % demon_id, String(DEFAULT_ID))))
	else:
		id = _session_choice.get(demon_id, DEFAULT_ID)
	var skin := get_skin(id)
	if skin.is_empty() or not is_unlocked(skin):
		return DEFAULT_ID
	return id


## Chooses (and saves) the skin `demon_id` wears. Returns false if it is locked or unknown.
static func select(demon_id: StringName, skin_id: StringName) -> bool:
	var skin := get_skin(skin_id)
	if skin.is_empty() or not is_unlocked(skin):
		return false
	var prog := _progression()
	if prog:
		prog.call(&"set_flag", "skin:%s" % demon_id, String(skin_id))
	else:
		_session_choice[demon_id] = skin_id
	return true


## Model id of a DemonData (the .glb name), used as the key for skin choices.
static func demon_id_of(demon: DemonData) -> StringName:
	if demon == null:
		return &""
	return StringName(demon.get_model_path().get_file().get_basename())


# ---------------------------------------------------------------- applying

## Recolors `model` (a built DemonModel) with skin `skin_id`. Returns the glow color it now uses.
static func apply(model: DemonModel, skin_id: StringName) -> Color:
	var skin := get_skin(skin_id)
	var base_glow: Color = model.data.glow_color if model.data else Art.EMBER
	if skin.is_empty() or skin_id == DEFAULT_ID or not skin.has("glow"):
		_recolor(model, {}, String(DEFAULT_ID))
		return base_glow
	_recolor(model, skin, String(skin_id))
	var g: Array = skin.glow
	return Color(g[0], g[1], g[2])


static func _recolor(root: Node, skin: Dictionary, skin_id: String) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var mi := n as MeshInstance3D
		if mi and mi.mesh:
			for i in mi.mesh.get_surface_count():
				_recolor_surface(mi, i, skin, skin_id)
		for c in n.get_children():
			stack.append(c)


static func _recolor_surface(mi: MeshInstance3D, surface: int, skin: Dictionary, skin_id: String) -> void:
	# The original (converted, shared) material is remembered on the mesh the first time, so
	# skins can be swapped back and forth.
	var key := "skin_src_%d" % surface
	var src: ShaderMaterial = mi.get_meta(key) as ShaderMaterial if mi.has_meta(key) else null
	if src == null:
		if skin.is_empty():
			return  # never skinned: already wearing the original
		src = mi.get_surface_override_material(surface) as ShaderMaterial
		if src == null:
			return
		mi.set_meta(key, src)
	if skin.is_empty():
		mi.set_surface_override_material(surface, src)
		return
	var cache_key := [skin_id, src.get_instance_id()]
	var m: ShaderMaterial = _mat_cache.get(cache_key)
	if m == null:
		m = _make(src, skin, _category(mi.mesh.surface_get_material(surface)))
		_mat_cache[cache_key] = m
	mi.set_surface_override_material(surface, m)


static func _make(src: ShaderMaterial, skin: Dictionary, category: String) -> ShaderMaterial:
	var m := src.duplicate() as ShaderMaterial
	var energy: Variant = src.get_shader_parameter(&"emission_energy")
	if energy != null and float(energy) > 0.0:
		# Glow: take the skin's color, keep the original's brightness (eyes stay hottest).
		var g: Array = skin.glow
		var glow := Color(g[0], g[1], g[2])
		var old_emit: Variant = src.get_shader_parameter(&"emission")
		var old_lum := (old_emit as Color).get_luminance() if old_emit is Color else 0.5
		m.set_shader_parameter(&"emission", glow.lerp(Color.WHITE, clampf(old_lum - 0.55, 0.0, 0.35)))
		m.set_shader_parameter(&"emission_energy", float(energy) * float(skin.get("glow_energy", 1.0)))
		var glow_alb: Variant = src.get_shader_parameter(&"albedo")
		if glow_alb is Color:
			m.set_shader_parameter(&"albedo", glow.darkened(0.45))
		return m
	var tints: Dictionary = skin.get("tints", {})
	if category == "" or not tints.has(category):
		return m
	var alb: Color = src.get_shader_parameter(&"albedo") if src.get_shader_parameter(&"albedo") is Color else Color.WHITE
	var tint: Variant = tints[category]
	if tint is Array:
		# Multiply the (textured) albedo.
		var t: Array = tint
		m.set_shader_parameter(&"albedo", Color(alb.r * t[0], alb.g * t[1], alb.b * t[2], alb.a))
	elif tint is Dictionary:
		# Replace: a flat new surface (dark textures can't be multiplied into gold). The baked
		# normal map stays for the relief; the albedo / ORM textures are dropped.
		var d: Dictionary = tint
		var c: Array = d.get("color", [1, 1, 1])
		m.set_shader_parameter(&"albedo", Color(c[0], c[1], c[2], alb.a))
		m.set_shader_parameter(&"albedo_tex", null)
		m.set_shader_parameter(&"orm_tex", null)
		m.set_shader_parameter(&"metallic", float(d.get("metallic", 0.0)))
		m.set_shader_parameter(&"roughness", float(d.get("roughness", 0.6)))
	return m


static func _category(blender_mat: Material) -> String:
	var nm := blender_mat.resource_name.to_lower() if blender_mat else ""
	for entry: Array in CATEGORIES:
		for kw: String in entry[1]:
			if nm.contains(kw):
				return entry[0]
	return ""


# ---------------------------------------------------------------- internals

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var args := OS.get_cmdline_user_args()
	# --unlock-all is Progression's dev arg for every unlock; skins follow it.
	_all_unlocked = args.has("--all-skins") or args.has("--unlock-all")
	var parsed := JsonIO.read_dict(DATA_PATH, "DemonSkins")
	for s: Variant in parsed.get("skins", []):
		if s is Dictionary and (s as Dictionary).has("id"):
			_skins.append(s)
			_by_id[String(s.id)] = s


static func _progression() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return null
	return loop.root.get_node_or_null(^"Progression")
