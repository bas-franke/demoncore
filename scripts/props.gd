class_name Props
## World props for the ruined gothic sanctum (SINBOUND), modelled in Blender
## (tools/blender/models/props/*.py -> res://assets/models/props/<name>.glb). Every builder takes a
## seeded RandomNumberGenerator and returns a new Node3D (origin on the ground, +Y up) holding plain
## MeshInstance3Ds with static (non-flashing) lit materials. Purely visual: no collisions.
##
##   var col := Props.broken_column(rng)          # one prop
##   var thing := Props.build(&"brazier", rng)    # by name (see BIG / SMALL / LANDMARKS)
##
## How a .glb is used: each file holds variant roots v0..vN. The first time a prop is needed its scene
## is instantiated once, every variant is flattened into ONE ArrayMesh per (Blender material, shadow)
## and cached. Instances only add MeshInstance3Ds that share those meshes, so decor.gd can still merge a
## whole chunk into a few draw calls. Blender material names map to the palette below (MATERIALS):
## stone gets a random tint per instance, moss on top faces, and the triplanar texture detail surface.
## Blender objects named "*_ns*" don't cast shadows; empties named "socket_<name>" are attachment
## points (fire, lights, candles, sigil) used by the builders here.
##
## Conventions used by decor.gd:
##   - MeshInstance3Ds with meta `keep` are never merged (flames, sigils: custom-vertex shaders)
##   - OmniLight3Ds carry meta `base_energy` (+ optional `pulse`) and are capped / flickered by decor
##   - large pieces cast shadows, small bits don't (cast_shadow is set per part)

const FLAME_SHADER := preload("res://shaders/flame.gdshader")
const SIGIL_SHADER := preload("res://shaders/sigil.gdshader")
const MODEL_DIR := "res://assets/models/props/"

# ---- palette
const STONE_A := Color(0.43, 0.41, 0.38)
const STONE_B := Color(0.33, 0.325, 0.32)
const STONE_C := Color(0.5, 0.47, 0.42)
const STONE_DARK := Color(0.25, 0.245, 0.24)
const MARBLE := Color(0.64, 0.62, 0.58)
const IRON := Color(0.1, 0.095, 0.09)
const STEEL_DARK := Color(0.36, 0.36, 0.37)
const BRONZE_GREEN := Color(0.25, 0.3, 0.27)
const BARK := Color(0.085, 0.072, 0.064)
const BARK_PALE := Color(0.22, 0.2, 0.18)
const WOOD := Color(0.2, 0.16, 0.12)
const GOLD_LEAF := Color(0.95, 0.64, 0.18)
const BANNER_RED := Color(0.32, 0.035, 0.035)
const BANNER_BLACK := Color(0.055, 0.05, 0.055)
const WAX := Color(0.55, 0.5, 0.41)
const GRASS_DRY := Color(0.22, 0.19, 0.1)
const GRASS_DARK := Color(0.085, 0.1, 0.05)
const FIRE_LIGHT := Color(1.0, 0.52, 0.22)
const HELL_LIGHT := Color(1.0, 0.16, 0.05)
const HOLY_LIGHT := Color(1.0, 0.82, 0.5)

## Small props (filler) and big features, with default weights (decor.gd uses per-theme tables).
const SMALL: Array[StringName] = [&"gravestone", &"rubble", &"grass_tuft", &"dead_shrub", &"bone_pile",
		&"candles", &"skull"]
const BIG: Array[StringName] = [&"broken_column", &"fallen_pillar", &"arch", &"statue_angel",
		&"statue_knight", &"dead_tree", &"golden_tree", &"iron_fence", &"brazier", &"banner", &"crypt",
		&"chains", &"gibbet"]
const LANDMARKS: Array[StringName] = [&"chapel_ruin", &"giant_sword", &"stone_circle", &"fallen_colossus"]

static var _own_mats: Array[ShaderMaterial] = []
static var _own_cache := {}
static var _flame_mat: ShaderMaterial
static var _sigil_mat: ShaderMaterial
static var _sigil_mesh: PlaneMesh
## prop name -> Array of variants {"parts": [{mesh, mat, shadow, src}], "sockets": {name: Transform3D}}
static var _models := {}


# ================================================================ materials

## Number / list of the moss materials Props creates itself (atmosphere.gd feeds them the fade focus).
static func material_count() -> int:
	return _own_mats.size()


static func static_materials() -> Array[ShaderMaterial]:
	return _own_mats


## Static lit material; moss > 0 makes a cached moss variant of Art.mat(). `surface` = texture-detail
## preset (Art.SURFACES: &"stone", &"metal", &"wood", ...).
static func mat(color: Color, rough: float = 0.85, metal: float = 0.0, grime: float = 0.5, moss: float = 0.0,
		sheen: float = 0.0, surface: StringName = &"") -> ShaderMaterial:
	if moss <= 0.0:
		return Art.mat(color, rough, metal, grime, false, sheen, surface)
	var key := "%s|%.2f|%.2f|%.2f|%.2f|%.2f|%s" % [color.to_html(), rough, metal, grime, moss, sheen, surface]
	if _own_cache.has(key):
		return _own_cache[key]
	var m := Art.mat(color, rough, metal, grime, false, sheen, surface).duplicate() as ShaderMaterial
	m.set_shader_parameter(&"moss", moss)
	_own_cache[key] = m
	_own_mats.append(m)
	return m


static func stone_mat(rng: RandomNumberGenerator) -> ShaderMaterial:
	match rng.randi_range(0, 2):
		0:
			return mat(STONE_A, 0.9, 0.0, 0.65, 0.55, 0.0, &"stone")
		1:
			return mat(STONE_B, 0.88, 0.0, 0.6, 0.5, 0.0, &"stone")
		_:
			return mat(STONE_C, 0.85, 0.0, 0.7, 0.45, 0.0, &"stone")


static func marble_mat() -> ShaderMaterial:
	return mat(MARBLE, 0.62, 0.0, 0.6, 0.4, 0.0, &"stone")


static func iron_mat() -> ShaderMaterial:
	return mat(IRON, 0.5, 0.75, 0.5, 0.0, 0.0, &"metal")


static func bark_mat(pale: bool = false) -> ShaderMaterial:
	return mat(BARK_PALE if pale else BARK, 0.95, 0.0, 0.35, 0.25, 0.0, &"wood")


static func bone_mat() -> ShaderMaterial:
	return mat(Art.BONE, 0.65, 0.0, 0.55, 0.0, 0.0, &"bone")


static func flame_material() -> ShaderMaterial:
	if _flame_mat == null:
		_flame_mat = ShaderMaterial.new()
		_flame_mat.shader = FLAME_SHADER
	return _flame_mat


static func sigil_material() -> ShaderMaterial:
	if _sigil_mat == null:
		_sigil_mat = ShaderMaterial.new()
		_sigil_mat.shader = SIGIL_SHADER
	return _sigil_mat


## Material for a Blender material name. `chosen` caches per-instance picks (one stone tint / one
## banner colour per prop instance).
static func material_for(blender_name: String, rng: RandomNumberGenerator, chosen: Dictionary,
		src: Material = null) -> Material:
	if chosen.has(blender_name):
		return chosen[blender_name]
	var m: Material
	match blender_name:
		"Prop_Stone":
			m = stone_mat(rng)
		"Prop_StoneDark":
			m = mat(STONE_DARK, 0.92, 0.0, 0.7, 0.5, 0.0, &"stone")
		"Prop_StoneLight":
			m = mat(STONE_C, 0.85, 0.0, 0.7, 0.45, 0.0, &"stone")
		"Prop_Marble":
			m = marble_mat()
		"Prop_Iron":
			m = iron_mat()
		"Prop_Steel":
			m = mat(STEEL_DARK, 0.42, 0.55, 0.7, 0.0, 0.0, &"metal")
		"Prop_SteelDark":
			m = mat(Color(0.14, 0.14, 0.15), 0.55, 0.5, 0.6, 0.0, 0.0, &"metal")
		"Prop_Bronze":
			m = mat(BRONZE_GREEN, 0.6, 0.35, 0.6, 0.35, 0.0, &"gold")
		"Prop_Bark":
			m = bark_mat(false)
		"Prop_BarkPale":
			m = bark_mat(true)
		"Prop_Wood":
			m = mat(WOOD, 0.9, 0.0, 0.5, 0.2, 0.0, &"wood")
		"Prop_Bone":
			m = bone_mat()
		"Prop_Gold":
			m = mat(Art.GOLD, 0.4, 0.9, 0.5, 0.0, 0.0, &"gold")
		"Prop_BannerCloth":
			m = mat(BANNER_RED if rng.randf() < 0.65 else BANNER_BLACK, 0.9, 0.0, 0.5, 0.0, 0.5, &"cloth")
		"Prop_Wax":
			m = mat(WAX, 0.55, 0.0, 0.3, 0.0, 0.6)
		"Prop_CandleFlame":
			m = Art.glow(Color(1.0, 0.6, 0.22), 3.2, false)
		"Prop_Ember":
			m = Art.emissive(Color(0.05, 0.03, 0.02), Art.EMBER, 2.5, 0.9, false)
		"Prop_Void":
			m = mat(Color(0.02, 0.02, 0.02), 1.0, 0.0, 0.0)
		"Prop_ObsidianAltar":
			m = mat(Art.OBSIDIAN, 0.6, 0.0, 0.4, 0.0, 0.0, &"stone")
		"Prop_HellRune":
			m = Art.emissive(Color(0.1, 0.02, 0.02), Art.HELLFIRE, 3.0, 0.4, false)
		"Prop_HolyRune":
			m = Art.emissive(Color(0.3, 0.25, 0.15), Art.HOLY, 2.2, 0.5, false)
		"Prop_Leaf":
			m = Art.emissive(Color(0.5, 0.33, 0.09), Color(1.0, 0.6, 0.16), 0.1, 0.7, false)
		"Prop_LeafDark":
			m = mat(Color(0.36, 0.22, 0.06), 0.8, 0.0, 0.4, 0.0, 0.6)
		"Prop_LeafFallen":
			m = mat(Color(0.6, 0.4, 0.12), 0.9, 0.0, 0.4)
		"Prop_GrassDry":
			m = mat(GRASS_DRY, 0.95, 0.0, 0.3, 0.0, 0.5)
		"Prop_GrassDark":
			m = mat(GRASS_DARK, 0.95, 0.0, 0.3, 0.0, 0.4)
		_:
			var b := src as BaseMaterial3D
			var c := b.albedo_color if b else Color(0.5, 0.5, 0.5)
			m = Art.mat(c, b.roughness if b else 0.8, b.metallic if b else 0.0, 0.5, false, 0.0,
					Art.surface_for_name(blender_name))
	chosen[blender_name] = m
	return m


# ================================================================ model loading

## Variants of a Blender prop (cached). Each variant = {"parts": [...], "sockets": {...}}.
static func variants(prop: StringName) -> Array:
	if _models.has(prop):
		return _models[prop]
	var out: Array = []
	var path := MODEL_DIR + String(prop) + ".glb"
	var ps := load(path) as PackedScene if ResourceLoader.exists(path) else null
	if ps == null:
		push_warning("Props: missing model %s (build it with tools/blender/build.py)" % path)
	else:
		var inst := ps.instantiate()
		var roots: Array[Node] = []
		for c in inst.get_children():
			if c is Node3D:
				roots.append(c)
		roots.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
		for r in roots:
			var groups := {}
			var sockets := {}
			_gather(r, Transform3D.IDENTITY, groups, sockets)
			var parts: Array = []
			for key: String in groups:
				var g: Dictionary = groups[key]
				var mesh := (g["st"] as SurfaceTool).commit()
				parts.append({"mesh": mesh, "mat": g["mat"], "shadow": g["shadow"], "src": g["src"]})
			out.append({"parts": parts, "sockets": sockets})
		inst.free()
	_models[prop] = out
	return out


static func _gather(node: Node, xf: Transform3D, groups: Dictionary, sockets: Dictionary) -> void:
	for c in node.get_children():
		if not c is Node3D:
			continue
		var cxf := xf * (c as Node3D).transform
		var nm := String(c.name)
		if nm.begins_with("socket_"):
			sockets[nm.trim_prefix("socket_")] = cxf
		if c is MeshInstance3D and (c as MeshInstance3D).mesh:
			var mesh := (c as MeshInstance3D).mesh
			var shadow := not nm.contains("_ns")
			for s in mesh.get_surface_count():
				var src := mesh.surface_get_material(s)
				var mname := src.resource_name if src else "Prop_Stone"
				var key := "%s|%d" % [mname, int(shadow)]
				if not groups.has(key):
					groups[key] = {"st": SurfaceTool.new(), "mat": mname, "shadow": shadow, "src": src}
				(groups[key]["st"] as SurfaceTool).append_from(mesh, s, cxf)
		_gather(c, cxf, groups, sockets)


## Adds the meshes of one variant of `prop` under `root`; returns its sockets {name: Transform3D}.
## `variant` < 0 picks one at random.
static func model(root: Node3D, prop: StringName, rng: RandomNumberGenerator, variant: int = -1) -> Dictionary:
	var vs := variants(prop)
	if vs.is_empty():
		return {}
	var v: Dictionary = vs[(rng.randi() % vs.size()) if variant < 0 else clampi(variant, 0, vs.size() - 1)]
	var chosen := {}
	for p: Dictionary in v["parts"]:
		var mi := MeshInstance3D.new()
		mi.mesh = p["mesh"]
		mi.material_override = material_for(p["mat"], rng, chosen, p["src"])
		if not p["shadow"]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return v["sockets"]


static func _root(rng: RandomNumberGenerator, scale_min: float = 0.9, scale_max: float = 1.1) -> Node3D:
	var root := Node3D.new()
	root.rotation.y = rng.randf() * TAU
	var s := rng.randf_range(scale_min, scale_max)
	root.scale = Vector3(s, s, s)
	return root


static func _simple(prop: StringName, rng: RandomNumberGenerator, smin: float = 0.9, smax: float = 1.1) -> Node3D:
	var root := _root(rng, smin, smax)
	model(root, prop, rng)
	return root


static func _flame(parent: Node3D, pos: Vector3, size: Vector2) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = flame_material()
	mi.position = pos + Vector3(0.0, size.y * 0.5, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 1.0
	mi.set_meta(&"keep", true)
	parent.add_child(mi)
	return mi


static func _fire_light(parent: Node3D, pos: Vector3, color: Color, energy: float, rng_: float,
		pulse: bool = false) -> OmniLight3D:
	var l := Art.light(parent, color, energy, rng_, pos)
	l.omni_attenuation = 1.4
	l.light_specular = 0.3
	l.light_volumetric_fog_energy = 1.6
	l.set_meta(&"base_energy", energy)
	if pulse:
		l.set_meta(&"pulse", true)
	return l


static func _socket(sockets: Dictionary, name: String, fallback: Vector3) -> Vector3:
	return (sockets[name] as Transform3D).origin if sockets.has(name) else fallback


# ================================================================ ruins

static func broken_column(rng: RandomNumberGenerator) -> Node3D:
	return _simple(&"broken_column", rng, 0.9, 1.15)


static func fallen_pillar(rng: RandomNumberGenerator) -> Node3D:
	return _simple(&"fallen_pillar", rng, 0.9, 1.15)


## Gothic pointed arch, half-collapsed arch or ruined wall with a pointed window.
static func arch(rng: RandomNumberGenerator) -> Node3D:
	return _simple(&"arch", rng, 0.95, 1.15)


static func gravestone(rng: RandomNumberGenerator) -> Node3D:
	return _simple(&"gravestone", rng, 0.85, 1.15)


## Stone sarcophagus: sealed, lid pushed aside, or lid fallen and broken.
static func crypt(rng: RandomNumberGenerator) -> Node3D:
	var root := _root(rng, 0.95, 1.1)
	model(root, &"crypt", rng)
	if rng.randf() < 0.5:
		var c := candles(rng, 3)
		c.position = Vector3(rng.randf_range(-0.6, 0.6), 0.0, 1.55)
		root.add_child(c)
	return root


# ================================================================ statues

## Weathered headless marble angel, wings broken.
static func statue_angel(rng: RandomNumberGenerator) -> Node3D:
	return _simple(&"statue_angel", rng, 0.9, 1.1)


## Kneeling knight in verdigris bronze, hands on his planted sword.
static func statue_knight(rng: RandomNumberGenerator) -> Node3D:
	return _simple(&"statue_knight", rng, 0.95, 1.15)


# ================================================================ trees

static func dead_tree(rng: RandomNumberGenerator) -> Node3D:
	return _simple(&"dead_tree", rng, 0.85, 1.2)


static func golden_tree(rng: RandomNumberGenerator) -> Node3D:
	return _simple(&"golden_tree", rng, 0.9, 1.15)


# ================================================================ iron, fire, cloth

static func iron_fence(rng: RandomNumberGenerator) -> Node3D:
	return _simple(&"iron_fence", rng, 1.0, 1.0)


static func brazier(rng: RandomNumberGenerator) -> Node3D:
	var root := _root(rng, 1.0, 1.1)
	var s := model(root, &"brazier", rng)
	var f := _socket(s, "fire", Vector3(0.0, 1.2, 0.0))
	_flame(root, f - Vector3(0, 0.05, 0), Vector2(1.0, 1.7))
	_flame(root, f + Vector3(0.16, -0.03, 0.06), Vector2(0.6, 1.0))
	_flame(root, f + Vector3(-0.14, -0.03, -0.05), Vector2(0.55, 0.9))
	_fire_light(root, f + Vector3(0, 0.8, 0), FIRE_LIGHT, 2.6, 8.0)
	return root


static func banner(rng: RandomNumberGenerator) -> Node3D:
	return _simple(&"banner", rng, 0.95, 1.1)


## Cluster of melted candles; `count` picks the cluster size (<=4 small, <=7 medium, else large).
static func candles(rng: RandomNumberGenerator, count: int = -1) -> Node3D:
	var root := Node3D.new()
	root.rotation.y = rng.randf() * TAU
	var v := -1
	if count > 0:
		v = 0 if count <= 4 else (1 if count <= 7 else 2)
	model(root, &"candles", rng, v)
	return root


static func chains(rng: RandomNumberGenerator) -> Node3D:
	return _simple(&"chains", rng, 1.0, 1.1)


## Iron cage hanging from a crooked gallows post.
static func gibbet(rng: RandomNumberGenerator) -> Node3D:
	return _simple(&"gibbet", rng, 0.95, 1.1)


# ================================================================ small filler

static func rubble(rng: RandomNumberGenerator) -> Node3D:
	return _simple(&"rubble", rng, 0.8, 1.3)


static func bone_pile(rng: RandomNumberGenerator) -> Node3D:
	return _simple(&"bone_pile", rng, 0.9, 1.2)


static func skull(rng: RandomNumberGenerator) -> Node3D:
	return _simple(&"skull", rng, 0.9, 1.3)


static func grass_tuft(rng: RandomNumberGenerator) -> Node3D:
	return _simple(&"grass_tuft", rng, 0.8, 1.3)


static func dead_shrub(rng: RandomNumberGenerator) -> Node3D:
	return _simple(&"dead_shrub", rng, 0.8, 1.2)


# ================================================================ landmarks

## Corner of a ruined chapel: broken coursed walls with pointed windows, buttresses, altar with
## candles, a burning brazier.
static func chapel_ruin(rng: RandomNumberGenerator) -> Node3D:
	var root := _root(rng, 1.0, 1.0)
	var s := model(root, &"chapel_ruin", rng)
	for k: String in ["candles", "candles2"]:
		if s.has(k):
			var c := candles(rng, 7 if k == "candles" else 5)
			c.position = (s[k] as Transform3D).origin
			root.add_child(c)
	if s.has("brazier"):
		var br := brazier(rng)
		br.position = (s["brazier"] as Transform3D).origin
		root.add_child(br)
	return root


## Colossal sword driven into the earth, holy runes glowing in the fuller.
static func giant_sword(rng: RandomNumberGenerator) -> Node3D:
	var root := _root(rng, 1.0, 1.0)
	var s := model(root, &"giant_sword", rng)
	_fire_light(root, _socket(s, "light", Vector3(0.6, 2.0, 0.6)), HOLY_LIGHT, 1.4, 6.0, true)
	return root


## Ring of standing stones around a glowing hellish sigil.
static func stone_circle(rng: RandomNumberGenerator) -> Node3D:
	var root := _root(rng, 1.0, 1.0)
	var s := model(root, &"stone_circle", rng)
	for k: String in s:
		if k.begins_with("candles"):
			var c := candles(rng, 4)
			c.position = (s[k] as Transform3D).origin
			root.add_child(c)
	if _sigil_mesh == null:
		_sigil_mesh = PlaneMesh.new()
		_sigil_mesh.size = Vector2(7.6, 7.6)
	var sig := MeshInstance3D.new()
	sig.mesh = _sigil_mesh
	sig.material_override = sigil_material()
	sig.position = _socket(s, "sigil", Vector3(0, 0.03, 0))
	sig.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sig.set_meta(&"keep", true)
	root.add_child(sig)
	_fire_light(root, _socket(s, "light", Vector3(0, 1.3, 0)), HELL_LIGHT, 3.2, 9.0, true)
	return root


## Toppled colossal angel head with a broken golden halo and a fallen stone wing.
static func fallen_colossus(rng: RandomNumberGenerator) -> Node3D:
	var root := _root(rng, 1.0, 1.0)
	var s := model(root, &"fallen_colossus", rng)
	if s.has("light"):
		_fire_light(root, (s["light"] as Transform3D).origin, HOLY_LIGHT, 0.9, 6.0, true)
	return root


# ================================================================ lookup

static func build(prop: StringName, rng: RandomNumberGenerator) -> Node3D:
	match prop:
		&"broken_column":
			return broken_column(rng)
		&"fallen_pillar":
			return fallen_pillar(rng)
		&"arch":
			return arch(rng)
		&"gravestone":
			return gravestone(rng)
		&"crypt":
			return crypt(rng)
		&"statue_angel":
			return statue_angel(rng)
		&"statue_knight":
			return statue_knight(rng)
		&"dead_tree":
			return dead_tree(rng)
		&"golden_tree":
			return golden_tree(rng)
		&"iron_fence":
			return iron_fence(rng)
		&"brazier":
			return brazier(rng)
		&"banner":
			return banner(rng)
		&"candles":
			return candles(rng)
		&"chains":
			return chains(rng)
		&"gibbet":
			return gibbet(rng)
		&"rubble":
			return rubble(rng)
		&"bone_pile":
			return bone_pile(rng)
		&"skull":
			return skull(rng)
		&"grass_tuft":
			return grass_tuft(rng)
		&"dead_shrub":
			return dead_shrub(rng)
		&"chapel_ruin":
			return chapel_ruin(rng)
		&"giant_sword":
			return giant_sword(rng)
		&"stone_circle":
			return stone_circle(rng)
		&"fallen_colossus":
			return fallen_colossus(rng)
	# Procedural holy / hellish props (docs/team/terrain.md); visual only here, like every Props prop.
	if PropKit.has(prop):
		return PropKit.build(prop, rng, false)
	push_warning("Props.build: unknown prop %s" % prop)
	return rubble(rng)


## Weighted pick from {name: weight}.
static func pick(table: Dictionary, rng: RandomNumberGenerator) -> StringName:
	var total := 0.0
	for k: StringName in table:
		total += float(table[k])
	var r := rng.randf() * total
	for k: StringName in table:
		r -= float(table[k])
		if r <= 0.0:
			return k
	return table.keys()[0]
