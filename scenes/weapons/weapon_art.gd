class_name WeaponArt
## Cheap instancing of the Blender-made weapon meshes (res://assets/models/weapons/*.glb, built
## from tools/blender/models/weapons/*.py). Each .glb is loaded once and flattened into
## [mesh, transform, node path] parts; build() then just adds MeshInstance3Ds that share the
## meshes and cached materials (no PackedScene instancing per projectile).
##
## Materials (by Blender material name):
##   * "...Spirit..."  -> unshaded additive glow (ghost stuff), tinted by `tint` when given
##   * emissive        -> Art.emissive (emission re-tinted by `tint` when given)
##   * anything else   -> Art.mat with the surface-detail texture picked from the name
##
##   WeaponArt.build(WeaponArt.SCYTHE, spinner)
##   WeaponArt.build(WeaponArt.SOUL, vis, soul_color)
##   WeaponArt.build(WeaponArt.RUNE_STONES, pivot, Color(0, 0, 0, 0), "stone1")

const SCYTHE := "res://assets/models/weapons/reaper_scythe.glb"
const HELLFIRE_CORE := "res://assets/models/weapons/hellfire_core.glb"
const SWORD := "res://assets/models/weapons/ravager_sword.glb"
const CHAIN_LINK := "res://assets/models/weapons/chain_link.glb"
const SOUL := "res://assets/models/weapons/soul_wisp.glb"
const RUNE_STONES := "res://assets/models/weapons/rune_stone.glb"

const NO_TINT := Color(0.0, 0.0, 0.0, 0.0)

static var _parts := {}  # path -> Array of [Mesh, Transform3D, String path_of_names]
static var _mats := {}


## Adds the model at `path` under `parent` (in a fresh Node3D, returned). `only` keeps just the
## parts whose node path contains that name (e.g. one variant of several). Never null.
static func build(path: String, parent: Node3D, tint: Color = NO_TINT, only: String = "",
		shadows: bool = false, flashable: bool = false) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	for p: Array in parts(path):
		if only != "" and not (p[2] as String).contains(only):
			continue
		var mi := MeshInstance3D.new()
		var mesh: Mesh = p[0]
		mi.mesh = mesh
		mi.transform = p[1]
		if not shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in mesh.get_surface_count():
			mi.set_surface_override_material(i, material_for(mesh.surface_get_material(i), tint, flashable))
		root.add_child(mi)
	return root


## Every GeometryInstance3D under `root` (for fading a built model with `transparency`).
static func geometry(root: Node) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	if root is GeometryInstance3D:
		out.append(root as GeometryInstance3D)
	for c in root.get_children():
		out.append_array(geometry(c))
	return out


static func parts(path: String) -> Array:
	if _parts.has(path):
		return _parts[path]
	var out: Array = []
	var ps := load(path) as PackedScene if ResourceLoader.exists(path) else null
	if ps == null:
		push_warning("WeaponArt: missing model %s" % path)
	else:
		var inst := ps.instantiate()
		# Imported glTF faces Godot +Z (Blender -Y); turn it so the modelled front is Godot -Z
		# (Node3D forward), matching Basis.looking_at() everywhere in the weapon code.
		_collect(inst, Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO), "", out, true)
		inst.free()
	_parts[path] = out
	return out


static func _collect(n: Node, xf: Transform3D, names: String, out: Array, is_root: bool) -> void:
	var here := xf
	if n is Node3D and not is_root:
		here = xf * (n as Node3D).transform
	var path := names + "/" + String(n.name)
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out.append([(n as MeshInstance3D).mesh, here, path])
	for c in n.get_children():
		_collect(c, here, path, out, false)


static func material_for(src: Material, tint: Color, flashable: bool) -> Material:
	var key := "%d|%s|%d" % [src.get_instance_id() if src else 0, tint.to_html(), int(flashable)]
	if _mats.has(key):
		return _mats[key]
	var dst: Material
	var bm := src as BaseMaterial3D
	if bm == null:
		dst = Art.mat(Art.STONE, 0.8, 0.0, 0.3, flashable)
	else:
		var nm := bm.resource_name.to_lower()
		var emits := bm.emission_enabled and bm.emission_energy_multiplier > 0.0
		var glow_col := bm.emission if emits else bm.albedo_color
		if tint.a > 0.0:
			glow_col = tint.lerp(glow_col, 0.25) if not nm.contains("eye") else tint.lerp(Color.WHITE, 0.55)
		if nm.contains("spirit") and not nm.contains("eye"):
			dst = Art.glow(glow_col, clampf(bm.emission_energy_multiplier * 0.6, 0.6, 3.0), true, 0.55)
		elif emits:
			dst = Art.emissive(bm.albedo_color if tint.a <= 0.0 else bm.albedo_color.lerp(tint, 0.3), glow_col,
					bm.emission_energy_multiplier * 0.8, bm.roughness, flashable)
		else:
			dst = Art.mat(bm.albedo_color, bm.roughness, bm.metallic, 0.3, flashable, 0.0,
					Art.surface_for_name(bm.resource_name))
	_mats[key] = dst
	return dst
