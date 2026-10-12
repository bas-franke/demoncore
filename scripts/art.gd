class_name Art
## Dark-fantasy material + model-building kit (replaces the old cel-shaded Toon look).
## Surfaces are physically lit with procedural weathering; glowing things use emissive
## or unshaded additive materials. No outlines.
##
##   var steel := Art.mat(Art.STEEL, 0.35, 0.9)               # rough, metallic
##   var chest := Art.part(root, Art.box(), steel, Vector3(0, 1.2, 0), Vector3(0.6, 0.5, 0.35))
##   var halo := Art.part(root, Art.torus(0.4, 0.46), Art.glow(Art.HOLY, 3.0), Vector3(0, 2.1, 0))
##   Art.flash(model_root, 1.0)                                # hit flash on all flashable meshes

const LIT := preload("res://shaders/lit.gdshader")
const LIT_STATIC := preload("res://shaders/lit_static.gdshader")

# ---- palette: muted, desaturated, with two strong accents (infernal ember vs. holy gold)
const OBSIDIAN := Color(0.06, 0.055, 0.06)
const ASH := Color(0.24, 0.23, 0.22)
const STONE := Color(0.42, 0.4, 0.37)
const BONE := Color(0.72, 0.68, 0.58)
const IVORY := Color(0.86, 0.83, 0.76)
const STEEL := Color(0.55, 0.56, 0.58)
const BRONZE := Color(0.55, 0.4, 0.22)
const GOLD := Color(0.83, 0.66, 0.3)
const BLOOD := Color(0.42, 0.04, 0.05)
const CRIMSON := Color(0.6, 0.08, 0.07)
const LEATHER := Color(0.23, 0.15, 0.1)
const CLOTH_DARK := Color(0.13, 0.11, 0.12)
const MOSS := Color(0.22, 0.26, 0.15)
# Emissive accents (use with glow()/emissive mats; >1 values bloom).
const EMBER := Color(1.0, 0.38, 0.08)
const HELLFIRE := Color(1.0, 0.22, 0.05)
const HOLY := Color(1.0, 0.85, 0.5)
const HOLY_WHITE := Color(1.0, 0.97, 0.88)
const SOUL := Color(0.85, 0.12, 0.18)

## Surface detail presets: texture res://assets/textures/surf_<type>.png (tools/build_surfaces.gd)
## applied triplanar by the lit shader. [strength, repeats per meter, bump].
## Texture feature sizes (per tile): stone 4 slabs, metal ~25 cm scratches, cloth 112 threads,
## leather 72 grains, skin 120 pores, feather 8x8 feathers, wood 21 rings, chainmail 16 rings,
## scales 10 across, rope 4 cords, marble 2 main veins.
const SURFACES := {
	&"stone": [1.0, 0.9, 1.3], &"metal": [0.65, 1.6, 0.5], &"gold": [0.55, 2.0, 0.45],
	&"cloth": [0.75, 3.0, 0.5], &"leather": [0.8, 2.5, 0.7], &"skin": [0.55, 2.0, 0.45],
	&"bone": [0.8, 1.6, 0.7], &"feather": [0.85, 1.6, 0.7], &"wood": [0.9, 1.5, 0.9],
	&"crystal": [0.6, 2.0, 0.7], &"marble": [0.8, 0.8, 0.6], &"chainmail": [0.9, 3.0, 0.9],
	&"scales": [0.85, 2.0, 0.8], &"rust": [0.9, 1.5, 1.0], &"moss_rock": [1.0, 0.9, 1.2],
	&"parchment": [0.6, 1.5, 0.5], &"rope": [0.85, 6.0, 0.8],
}
## Material-name keywords → surface type (Blender material names, lower-cased; first match wins).
## Specific materials come before generic shape words ("IvoryPlate" = bone, "SteelMailArmor" =
## chainmail, "RustedIron" = rust).
const SURFACE_KEYWORDS := [
	["rust", &"rust"], ["corrod", &"rust"], ["oxid", &"rust"],
	["chainmail", &"chainmail"], ["mail", &"chainmail"], ["hauberk", &"chainmail"], ["coif", &"chainmail"],
	["moss", &"moss_rock"], ["lichen", &"moss_rock"], ["overgrown", &"moss_rock"],
	["marble", &"marble"], ["alabaster", &"marble"],
	["crystal", &"crystal"], ["shard", &"crystal"], ["gem", &"crystal"], ["glass", &"crystal"],
	["quartz", &"crystal"], ["amethyst", &"crystal"], ["prism", &"crystal"],
	["parchment", &"parchment"], ["paper", &"parchment"], ["scroll", &"parchment"], ["vellum", &"parchment"],
	["page", &"parchment"],
	["rope", &"rope"], ["cord", &"rope"], ["twine", &"rope"], ["hemp", &"rope"], ["binding", &"rope"],
	["scale", &"scales"], ["carapace", &"scales"], ["drake", &"scales"], ["wyrm", &"scales"],
	["reptile", &"scales"], ["serpent", &"scales"], ["lizard", &"scales"], ["dragon", &"scales"],
	["leather", &"leather"], ["hide", &"leather"], ["strap", &"leather"], ["membrane", &"leather"],
	["belt", &"leather"], ["glove", &"leather"], ["boot", &"leather"], ["pelt", &"leather"], ["grip", &"leather"],
	["feather", &"feather"], ["wing", &"feather"], ["plume", &"feather"], ["pinion", &"feather"],
	["cloth", &"cloth"], ["robe", &"cloth"], ["cape", &"cloth"], ["cloak", &"cloth"], ["silk", &"cloth"],
	["banner", &"cloth"], ["veil", &"cloth"], ["hood", &"cloth"], ["fabric", &"cloth"], ["linen", &"cloth"],
	["wool", &"cloth"], ["sash", &"cloth"], ["tabard", &"cloth"], ["shroud", &"cloth"], ["ribbon", &"cloth"],
	["burlap", &"cloth"],
	["skin", &"skin"], ["flesh", &"skin"],
	["bone", &"bone"], ["ivory", &"bone"], ["skull", &"bone"], ["horn", &"bone"], ["antler", &"bone"],
	["tooth", &"bone"], ["teeth", &"bone"], ["claw", &"bone"], ["fang", &"bone"], ["tusk", &"bone"],
	["talon", &"bone"],
	["gold", &"gold"], ["brass", &"gold"], ["bronze", &"gold"], ["gilt", &"gold"], ["copper", &"gold"],
	["steel", &"metal"], ["iron", &"metal"], ["metal", &"metal"], ["chain", &"metal"], ["blade", &"metal"],
	["armor", &"metal"], ["armour", &"metal"], ["plate", &"metal"], ["silver", &"metal"], ["helm", &"metal"],
	["gauntlet", &"metal"], ["pauldron", &"metal"], ["sword", &"metal"],
	["wood", &"wood"], ["bark", &"wood"], ["branch", &"wood"], ["trunk", &"wood"], ["haft", &"wood"],
	["plank", &"wood"], ["timber", &"wood"],
	["stone", &"stone"], ["rock", &"stone"], ["obsidian", &"stone"], ["granite", &"stone"],
	["brick", &"stone"], ["rubble", &"stone"], ["statue", &"stone"], ["grave", &"stone"], ["column", &"stone"],
	["pillar", &"stone"], ["basalt", &"stone"], ["slate", &"stone"], ["masonry", &"stone"], ["tomb", &"stone"],
	["crypt", &"stone"],
]

static var _mats := {}
static var _glows := {}
static var _surface_tex := {}


## Surface type for a material name (e.g. "Vharok_ObsidianPlate" → &"stone"), or &"" if unknown.
static func surface_for_name(material_name: String) -> StringName:
	var n := material_name.to_lower()
	for pair in SURFACE_KEYWORDS:
		if n.contains(pair[0]):
			return pair[1]
	return &""


static func _apply_surface(m: ShaderMaterial, surface: StringName) -> void:
	if surface == &"" or not SURFACES.has(surface):
		return
	if not _surface_tex.has(surface):
		var path := "res://assets/textures/surf_%s.png" % surface
		_surface_tex[surface] = load(path) if ResourceLoader.exists(path) else null
	var tex: Texture2D = _surface_tex[surface]
	if tex == null:
		return
	var p: Array = SURFACES[surface]
	m.set_shader_parameter(&"detail_tex", tex)
	m.set_shader_parameter(&"detail_strength", p[0])
	m.set_shader_parameter(&"detail_scale", p[1])
	m.set_shader_parameter(&"detail_bump", p[2])


## Cached lit material. `flashable` = false for static scenery (saves instance-uniform slots).
## `surface` adds a texture-detail preset (see SURFACES), e.g. &"stone", &"metal", &"cloth".
static func mat(color: Color, roughness: float = 0.8, metallic: float = 0.0, grime: float = 0.35,
		flashable: bool = true, sheen: float = 0.0, surface: StringName = &"") -> ShaderMaterial:
	var key := "%s|%.2f|%.2f|%.2f|%d|%.2f|%s" % [color.to_html(), roughness, metallic, grime, int(flashable), sheen, surface]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = LIT if flashable else LIT_STATIC
	m.set_shader_parameter(&"albedo", color)
	m.set_shader_parameter(&"roughness", roughness)
	m.set_shader_parameter(&"metallic", metallic)
	m.set_shader_parameter(&"grime", grime)
	m.set_shader_parameter(&"sheen", sheen)
	_apply_surface(m, surface)
	_mats[key] = m
	return m


## Lit material that also glows (eyes, runes, cracks of hellfire, holy inlays).
static func emissive(color: Color, glow_color: Color, energy: float = 2.0, roughness: float = 0.5,
		flashable: bool = true) -> ShaderMaterial:
	var key := "E%s|%s|%.2f|%.2f|%d" % [color.to_html(), glow_color.to_html(), energy, roughness, int(flashable)]
	if _mats.has(key):
		return _mats[key]
	var m := mat(color, roughness, 0.0, 0.1, flashable).duplicate() as ShaderMaterial
	m.set_shader_parameter(&"emission", glow_color)
	m.set_shader_parameter(&"emission_energy", energy)
	_mats[key] = m
	return m


## Unshaded glowing material (halos, flames, magic). `additive` for light-like blending.
static func glow(color: Color, energy: float = 2.0, additive: bool = true, alpha: float = 1.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%d|%.2f" % [color.to_html(), energy, int(additive), alpha]
	if _glows.has(key):
		return _glows[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, alpha)
	if additive or alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glows[key] = m
	return m


## Adds a MeshInstance3D with `material` to `parent`.
static func part(parent: Node3D, mesh: Mesh, material: Material, pos := Vector3.ZERO,
		scl := Vector3.ONE, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	if material is StandardMaterial3D and (material as StandardMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif material is ShaderMaterial and (material as ShaderMaterial).shader == ArtStyle.HOLY_GLOW_SHADER:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # light bodies cast no shadow
	parent.add_child(mi)
	return mi


static func pivot(parent: Node3D, pos := Vector3.ZERO, rot := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation = rot
	parent.add_child(n)
	return n


## Hit flash (0..1) on every flashable mesh under `root`.
## Perf: flash() is called every frame on every recently hit enemy / corpse, and walking a
## 30-100 node model each time was one of the biggest per-frame costs with crowds. The flashable
## meshes under `root` are cached in its metadata and re-collected every FLASH_REFRESH calls (so
## parts added later still pick it up within a moment), or at once if a cached mesh was freed.
## Call flash_invalidate(root) after swapping a model's parts/materials to refresh immediately.
const FLASH_REFRESH := 45
const _FLASH_META := &"_art_flash"

static func flash(root: Node, amount: float) -> void:
	var cache: Array = root.get_meta(_FLASH_META) if root.has_meta(_FLASH_META) else []
	# cache = [calls_left, last_amount, meshes...]
	if cache.is_empty() or int(cache[0]) <= 0:
		cache = [FLASH_REFRESH, -1.0]
		_collect_flashable(root, cache)
		root.set_meta(_FLASH_META, cache)
	cache[0] = int(cache[0]) - 1
	if float(cache[1]) == amount:
		return
	cache[1] = amount
	for i in range(2, cache.size()):
		var gi: Object = cache[i]
		if not is_instance_valid(gi):
			cache[0] = 0  # stale: rebuild next call
			continue
		(gi as GeometryInstance3D).set_instance_shader_parameter(&"flash", amount)


## Forces the next flash(root, ...) to re-scan root's meshes.
static func flash_invalidate(root: Node) -> void:
	if root.has_meta(_FLASH_META):
		root.remove_meta(_FLASH_META)


static func _collect_flashable(root: Node, out: Array) -> void:
	if root is GeometryInstance3D:
		var gi := root as GeometryInstance3D
		var sm := gi.material_override as ShaderMaterial
		var flashable := sm != null and sm.shader == LIT
		if not flashable and gi is MeshInstance3D:
			# Imported (Blender) models use per-surface override materials instead.
			var mi := gi as MeshInstance3D
			if mi.mesh:
				for i in mi.mesh.get_surface_count():
					var s := mi.get_surface_override_material(i) as ShaderMaterial
					if s and s.shader == LIT:
						flashable = true
						break
		if flashable:
			out.append(gi)
	for c in root.get_children():
		_collect_flashable(c, out)


static func no_shadows(root: Node) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in root.get_children():
		no_shadows(c)


## Small warm/cold point light (braziers, eyes, halos). Keep counts low; they are not free.
static func light(parent: Node3D, color: Color, energy: float = 1.5, rng: float = 4.0, pos := Vector3.ZERO,
		shadows: bool = false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.position = pos
	l.shadow_enabled = shadows
	parent.add_child(l)
	return l


# ---- shared unit meshes (same sizes as Toon's)
static func sphere() -> SphereMesh:
	return Toon.sphere()

static func capsule(r: float = 0.25, h: float = 1.0) -> CapsuleMesh:
	return Toon.capsule(r, h)

static func box() -> BoxMesh:
	return Toon.box()

static func cylinder(top: float = 0.5, bottom: float = 0.5) -> CylinderMesh:
	return Toon.cylinder(top, bottom)

## Cone pointing up (+Y), height 1, base radius `r`.
static func cone(r: float = 0.5) -> CylinderMesh:
	return Toon.cylinder(0.0, r)

static func prism() -> PrismMesh:
	return Toon.prism()

static func torus(inner: float = 0.35, outer: float = 0.5) -> TorusMesh:
	return Toon.torus(inner, outer)


# ---- baked textures (tools/blender/bake.py; GlbModel calls this for textured GLB materials)
static var _tex_mats := {}

## Cached lit material driven by baked textures (UV mapped; mesh needs tangents for `normal`).
## `orm` packs R = ambient occlusion, G = roughness, B = metallic (the glTF layout); `roughness`
## and `metallic` multiply it. `emission_tex` (if any) multiplies `glow_color * energy`.
## Weathering grime is kept light (the bake already has wear). `surface` (see SURFACES) adds the
## triplanar micro detail at TEXTURED_DETAIL x its usual strength: the atlas carries the macro
## wear (edges, cavities, stains), the tiling detail the sub-texel grain (weave, pores, barbs).
const TEXTURED_DETAIL := 0.55

static func textured_mat(albedo_tex: Texture2D, normal_tex: Texture2D = null, orm: Texture2D = null,
		emission_tex: Texture2D = null, tint := Color.WHITE, roughness: float = 1.0,
		metallic: float = 1.0, glow_color := Color.BLACK, energy: float = 0.0,
		flashable: bool = true, sheen: float = 0.0, orm_has_ao: bool = true,
		grime: float = 0.1, surface: StringName = &"") -> ShaderMaterial:
	var ids := []
	for t in [albedo_tex, normal_tex, orm, emission_tex]:
		ids.append(t.get_instance_id() if t else 0)
	var key := "%s|%s|%.2f|%.2f|%s|%.2f|%d|%.2f|%d|%.2f|%s" % [str(ids), tint.to_html(), roughness, metallic,
		glow_color.to_html(), energy, int(flashable), sheen, int(orm_has_ao), grime, surface]
	if _tex_mats.has(key):
		return _tex_mats[key]
	var m := ShaderMaterial.new()
	m.shader = LIT if flashable else LIT_STATIC
	m.set_shader_parameter(&"use_textures", true)
	m.set_shader_parameter(&"albedo", tint)
	m.set_shader_parameter(&"roughness", roughness)
	m.set_shader_parameter(&"metallic", metallic)
	m.set_shader_parameter(&"grime", grime)
	m.set_shader_parameter(&"contact_dark", 0.2)
	m.set_shader_parameter(&"sheen", sheen)
	if albedo_tex:
		m.set_shader_parameter(&"albedo_tex", albedo_tex)
	if normal_tex:
		m.set_shader_parameter(&"normal_tex", normal_tex)
	if orm:
		m.set_shader_parameter(&"orm_tex", orm)
	m.set_shader_parameter(&"ao_strength", 1.0 if (orm and orm_has_ao) else 0.0)
	if energy > 0.0:
		m.set_shader_parameter(&"emission", glow_color)
		m.set_shader_parameter(&"emission_energy", energy)
		if emission_tex:
			m.set_shader_parameter(&"emission_tex", emission_tex)
	if surface != &"":
		_apply_surface(m, surface)
		var ds: Variant = m.get_shader_parameter(&"detail_strength")
		if ds != null:
			m.set_shader_parameter(&"detail_strength", float(ds) * TEXTURED_DETAIL)
	_tex_mats[key] = m
	return m
