class_name ArtStyle
## Art-direction helpers on top of the Art material kit (res://scripts/art.gd): faction palettes,
## rim light, opt-in outlines, the hellfire / holy-glow shader materials, hit flash and death
## dissolve with faction colors. Style guide: docs/team/art-style.md.
##
##   ArtStyle.apply_faction(model, ArtStyle.Faction.HOLY, is_elite)  # rim (+ gold outline: elites)
##   ArtStyle.outline(shopkeeper, ArtStyle.INTERACT, 3.0, 0.6)       # pulsing ember outline
##   Art.part(root, Art.sphere(), ArtStyle.hellfire(), ...)           # molten crust material
##   Art.part(root, Art.torus(), ArtStyle.holy_glow(), ...)           # radiant halo
##   ArtStyle.hit_flash(model)                                        # 0.15 s white flash
##   ArtStyle.dissolve(corpse, ArtStyle.Faction.HOLY, 0.9)            # burn into gold, then free
##
## Rim / outline / flash / dissolve only affect meshes using the flashable lit shader
## (Art.mat(), Art.emissive(), Art.textured_mat(), GLB models via GlbModel). They are per-instance
## (instance uniforms / material_overlay), so cached shared materials are never modified.

enum Faction { DEMON, HOLY, NEUTRAL }

# ---------------------------------------------------------------- palette
# Infernal side (the player): hot, saturated, glowing from inside dark matter.
const HELL_OBSIDIAN := Art.OBSIDIAN
const HELL_CHAR := Color(0.045, 0.03, 0.03)
const HELL_BLOOD := Art.BLOOD
const HELL_CRIMSON := Art.CRIMSON
const HELL_EMBER := Art.EMBER
const HELL_FIRE := Art.HELLFIRE
const HELL_CORE := Color(1.0, 0.78, 0.4)
const HELL_SOUL := Art.SOUL
# Heaven (enemies): sterile, cool-warm whites and polished gold, glowing on the surface.
const HEAVEN_MARBLE := Art.IVORY
const HEAVEN_BONE := Art.BONE
const HEAVEN_GOLD := Art.GOLD
const HEAVEN_STEEL := Art.STEEL
const HEAVEN_LIGHT := Art.HOLY
const HEAVEN_WHITE := Art.HOLY_WHITE
const HEAVEN_SKY := Color(0.62, 0.74, 0.86)
# Corruption (what the player leaves behind). Same values as corruption.gdshaderinc.
const BLIGHT_CHAR := Color(0.045, 0.03, 0.03)
const BLIGHT_ASH := Color(0.16, 0.13, 0.12)
const BLIGHT_BLOOD := Color(0.24, 0.025, 0.02)
const BLIGHT_EMBER := Color(1.0, 0.3, 0.06)

## Rim light (color, strength) per faction. Demons glow ember on the silhouette, angels pale gold.
const RIM_DEMON := Color(1.0, 0.32, 0.08, 0.7)
const RIM_HOLY := Color(1.0, 0.86, 0.6, 0.55)
const RIM_NEUTRAL := Color(0.6, 0.6, 0.65, 0.3)
## Outline colors (gameplay emphasis only).
const ELITE := Color(1.0, 0.78, 0.38)
const INTERACT := Color(1.0, 0.36, 0.08)
const TARGET := Color(1.0, 0.15, 0.1)

const HELLFIRE_SHADER := preload("res://shaders/style/hellfire.gdshader")
const HOLY_GLOW_SHADER := preload("res://shaders/style/holy_glow.gdshader")
const OUTLINE_SHADER := preload("res://shaders/style/outline.gdshader")
const OUTLINE_MASK_SHADER := preload("res://shaders/style/outline_mask.gdshader")

## Ready-made presets (text .tres, tweak in the inspector). Load with load(ArtStyle.MAT_...).
const MAT_HELLFIRE_ROCK := "res://assets/materials/hellfire_rock.tres"
const MAT_HELLFIRE_LAVA := "res://assets/materials/hellfire_lava.tres"
const MAT_HELLFIRE_BRAND := "res://assets/materials/hellfire_brand.tres"
const MAT_HOLY_HALO := "res://assets/materials/holy_halo.tres"
const MAT_HOLY_AURA := "res://assets/materials/holy_aura.tres"
const MAT_OUTLINE_ELITE := "res://assets/materials/outline_elite.tres"
const MAT_OUTLINE_INTERACT := "res://assets/materials/outline_interact.tres"

static var _hellfire := {}
static var _holy := {}
static var _outlines := {}
static var _smoothed := {}  # ArrayMesh -> smoothed-normal twin (or null), twins map to themselves


# ---------------------------------------------------------------- faction look

## Rim + (for elites) outline in the faction's colors on every lit mesh under `root`.
## Call once after the model is built (GLB models included).
static func apply_faction(root: Node, faction: Faction, elite: bool = false) -> void:
	match faction:
		Faction.DEMON:
			set_rim(root, RIM_DEMON)
		Faction.HOLY:
			set_rim(root, RIM_HOLY)
			if elite:
				outline(root, ELITE, 2.2, 0.0, 1.4)
		_:
			set_rim(root, RIM_NEUTRAL)


## Fresnel rim light (rgb = color, a = strength; Color(0, 0, 0, 0) = off) on every lit mesh.
static func set_rim(root: Node, rim: Color) -> void:
	for g in _lit_meshes(root):
		g.set_instance_shader_parameter(&"rim_color", rim)


## Screen-space silhouette outline on every lit mesh under `root` (material_overlay).
## `width` in pixels at 1080p, `pulse` 0..1 breathing. Cached per (color, width, pulse).
## The overlay is a stencil mask pass (the body) chained to the hull pass, so only the outer
## silhouette is drawn, without lines where body parts overlap.
static func outline(root: Node, color: Color = ELITE, width: float = 2.5, pulse: float = 0.0,
		energy: float = 1.6) -> void:
	var m := outline_overlay(color, width, pulse, energy)
	for g in _lit_meshes(root):
		g.material_overlay = m
		_prepare_outline_normals(g)


## Removes outlines added by outline().
static func clear_outline(root: Node) -> void:
	for g in _lit_meshes(root):
		var o := g.material_overlay as ShaderMaterial
		if o and (o.shader == OUTLINE_MASK_SHADER or o.shader == OUTLINE_SHADER):
			g.material_overlay = null


## The hull pass alone (has interior lines; prefer outline_overlay() for material_overlay).
static func outline_material(color: Color = ELITE, width: float = 2.5, pulse: float = 0.0,
		energy: float = 1.6) -> ShaderMaterial:
	var key := "%s|%.2f|%.2f|%.2f" % [color.to_html(), width, pulse, energy]
	if not _outlines.has(key):
		var m := ShaderMaterial.new()
		m.shader = OUTLINE_SHADER
		m.set_shader_parameter(&"color", color)
		m.set_shader_parameter(&"width", width)
		m.set_shader_parameter(&"pulse", pulse)
		m.set_shader_parameter(&"energy", energy)
		# After the mask pass (both are in the transparent pass, sorted by priority first).
		m.render_priority = 1
		_outlines[key] = m
	return _outlines[key]


## Mask pass with the hull chained as next_pass: what outline() puts on material_overlay.
static func outline_overlay(color: Color = ELITE, width: float = 2.5, pulse: float = 0.0,
		energy: float = 1.6) -> ShaderMaterial:
	var key := "M%s|%.2f|%.2f|%.2f" % [color.to_html(), width, pulse, energy]
	if not _outlines.has(key):
		var m := ShaderMaterial.new()
		m.shader = OUTLINE_MASK_SHADER
		m.render_priority = 0
		m.next_pass = outline_material(color, width, pulse, energy)
		_outlines[key] = m
	return _outlines[key]


## Picks the hull extrusion for `g` (outline.gdshader `outline_mode`) so hard edges don't gap:
## Art primitives with split normals extrude radially (they are centred on their origin), rigid
## ArrayMeshes get a cached twin with smoothed normals in CUSTOM0. Skinned / blend-shape meshes keep
## their normals (CUSTOM0 isn't skinned).
static func _prepare_outline_normals(g: GeometryInstance3D) -> void:
	var mi := g as MeshInstance3D
	if mi == null or mi.mesh == null:
		return
	var mesh := mi.mesh
	if mesh is BoxMesh or mesh is PrismMesh or mesh is CylinderMesh:
		mi.set_instance_shader_parameter(&"outline_mode", 1.0)
		return
	if mesh is ArrayMesh:
		var smooth := _smoothed_mesh(mesh as ArrayMesh)
		if smooth:
			mi.mesh = smooth
			mi.set_instance_shader_parameter(&"outline_mode", 2.0)


## Twin of `src` with per-position averaged normals in CUSTOM0 (RGBA float), cached per source.
## Returns null for meshes it can't safely rebuild (skinned, blend shapes, no normals).
static func _smoothed_mesh(src: ArrayMesh) -> ArrayMesh:
	if _smoothed.has(src):
		return _smoothed[src]  # twins map to themselves
	var out: ArrayMesh = null
	if src.get_blend_shape_count() == 0:
		out = ArrayMesh.new()
		for si in src.get_surface_count():
			var arrays := src.surface_get_arrays(si)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var nrms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			if arrays[Mesh.ARRAY_BONES] != null or nrms.size() != verts.size():
				out = null
				break
			# Sum the normals of every vertex sharing a (quantized) position.
			var acc := {}  # Vector3i -> Vector3
			var keys: Array[Vector3i] = []
			keys.resize(verts.size())
			for i in verts.size():
				var k := Vector3i((verts[i] * 2000.0).round())
				keys[i] = k
				acc[k] = (acc.get(k, Vector3.ZERO) as Vector3) + nrms[i]
			var custom := PackedFloat32Array()
			custom.resize(verts.size() * 4)
			for i in verts.size():
				var nn := (acc[keys[i]] as Vector3).normalized()
				custom[i * 4] = nn.x
				custom[i * 4 + 1] = nn.y
				custom[i * 4 + 2] = nn.z
				custom[i * 4 + 3] = 0.0
			arrays[Mesh.ARRAY_CUSTOM0] = custom
			var fmt := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
			out.add_surface_from_arrays(src.surface_get_primitive_type(si), arrays, [], {}, fmt)
			out.surface_set_material(si, src.surface_get_material(si))
	_smoothed[src] = out
	if out:
		_smoothed[out] = out
	return out


# ---------------------------------------------------------------- materials

## Cached molten-crust material (res://shaders/style/hellfire.gdshader). `molten` 0 = rock with
## faint veins, 0.35 = cracked lava rock, 0.8 = mostly lava. `heat_gradient` > 0 = hotter at the
## bottom (pools, brazier bowls).
static func hellfire(molten: float = 0.35, energy: float = 3.0, crack_scale: float = 2.2,
		heat_gradient: float = 0.0) -> ShaderMaterial:
	var key := "%.2f|%.2f|%.2f|%.2f" % [molten, energy, crack_scale, heat_gradient]
	if not _hellfire.has(key):
		var m := ShaderMaterial.new()
		m.shader = HELLFIRE_SHADER
		m.set_shader_parameter(&"molten", molten)
		m.set_shader_parameter(&"energy", energy)
		m.set_shader_parameter(&"crack_scale", crack_scale)
		m.set_shader_parameter(&"heat_gradient", heat_gradient)
		_hellfire[key] = m
	return _hellfire[key]


## Cached radiant light-body material (res://shaders/style/holy_glow.gdshader). Additive.
static func holy_glow(core: Color = HEAVEN_WHITE, edge: Color = HEAVEN_LIGHT, energy: float = 2.2,
		rim_weight: float = 0.65) -> ShaderMaterial:
	var key := "%s|%s|%.2f|%.2f" % [core.to_html(), edge.to_html(), energy, rim_weight]
	if not _holy.has(key):
		var m := ShaderMaterial.new()
		m.shader = HOLY_GLOW_SHADER
		m.set_shader_parameter(&"core_color", core)
		m.set_shader_parameter(&"edge_color", edge)
		m.set_shader_parameter(&"energy", energy)
		m.set_shader_parameter(&"rim_weight", rim_weight)
		_holy[key] = m
	return _holy[key]


# ---------------------------------------------------------------- feedback

## White hit flash on `root` that decays over `duration` seconds (tween bound to `root`).
## Models with their own flash timer (Enemy, DemonModel) don't need this.
static func hit_flash(root: Node3D, duration: float = 0.15, amount: float = 1.0) -> Tween:
	if root == null or not root.is_inside_tree():
		return null
	var tw := root.create_tween()
	tw.tween_method(func(v: float) -> void: Art.flash(root, v), amount, 0.0, maxf(duration, 0.01))
	return tw


## Death dissolve in the faction's color (angels burn into gold light, demons into embers),
## then frees `root`. See Dissolve for the details.
static func dissolve(root: Node3D, faction: Faction = Faction.HOLY, duration: float = 0.8,
		free_when_done: bool = true) -> Tween:
	var c := HEAVEN_LIGHT
	if faction == Faction.DEMON:
		c = HELL_EMBER
	elif faction == Faction.NEUTRAL:
		c = HEAVEN_BONE
	return Dissolve.play(root, duration, c, free_when_done)


# ---------------------------------------------------------------- internals

static func _lit_meshes(root: Node) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	if root:
		_collect_lit(root, out)
	return out


static func _collect_lit(n: Node, out: Array[GeometryInstance3D]) -> void:
	if n is GeometryInstance3D and not n is GPUParticles3D and not n is CPUParticles3D:
		var g := n as GeometryInstance3D
		if Dissolve.supports(g):
			out.append(g)
	for c in n.get_children():
		_collect_lit(c, out)
