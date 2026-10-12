class_name GlbModel
extends Node3D
## Wraps a Blender-made model (res://assets/models/<category>/<name>.glb, built by
## tools/blender/build.py). Converts the imported Principled/Standard materials to the game's
## lit shader (so Art.flash hit-flashes work and the look matches the world) and plays the
## named animations exported from Blender NLA tracks (idle, walk, attack, windup, hit, death...).
##
##   var m := GlbModel.create("res://assets/models/enemies/choir_wisp.glb")
##   add_child(m)
##   m.play(&"walk")           # cross-fades; unknown names are ignored
##   m.set_flash(1.0)

## Animations that loop automatically.
const LOOPING := [&"idle", &"walk", &"run", &"fly", &"hover", &"channel"]

var scene_root: Node3D
var anim_player: AnimationPlayer
var current := &""
## True when GlbSkin turned the joints into one skinned mesh (see joint()).
var skinned := false


static func create(path: String, flashable: bool = true) -> GlbModel:
	var m := GlbModel.new()
	m.setup(path, flashable)
	return m


## PackedScenes by path, kept alive for the whole session. Without this, a node instanced from a
## PackedScene does not hold a reference to it, so once the last holder dropped it the next
## create() re-parsed the .glb scene from disk (3-5 ms per enemy spawn; perf role).
static var _scenes := {}
## Imported material -> converted Art material, per flashable flag (perf: convert_materials ran
## string-keyed cache lookups for every surface of every instance).
static var _converted := [{}, {}]


## Drops the scene / material caches (Perf calls this at quit).
static func clear_cache() -> void:
	_scenes.clear()
	_converted = [{}, {}]


## Cached load of a model scene (see _scenes).
static func get_scene(path: String) -> PackedScene:
	var ps: PackedScene = _scenes.get(path)
	if ps == null:
		ps = load(path) as PackedScene
		if ps:
			_scenes[path] = ps
	return ps


func setup(path: String, flashable: bool = true) -> void:
	var ps := get_scene(path)
	if ps == null:
		push_warning("GlbModel: cannot load %s" % path)
		return
	scene_root = ps.instantiate() as Node3D
	add_child(scene_root)
	convert_materials(scene_root, flashable)
	anim_player = _find_player(scene_root)
	if anim_player:
		for n in anim_player.get_animation_list():
			if StringName(n) in LOOPING:
				anim_player.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		# perf round 3: horde models become one skinned mesh with bone-track clips (GlbSkin).
		if GlbSkin.wants(path):
			skinned = GlbSkin.convert(self, path, flashable)
		if anim_player.has_animation(&"idle"):
			play(&"idle", 0.0)


## A joint of the model by name: the node itself, or for skinned (GlbSkin) models a
## BoneAttachment3D following that bone. Null if missing.
func joint(joint_name: String) -> Node3D:
	if scene_root == null:
		return null
	if skinned:
		return GlbSkin.attachment(self, joint_name)
	return scene_root.find_child(joint_name, true, false) as Node3D


func has_anim(anim_name: StringName) -> bool:
	return anim_player != null and anim_player.has_animation(anim_name)


## Cross-fades to `anim_name` (no-op if missing or already playing, unless `restart`).
func play(anim_name: StringName, blend: float = 0.15, speed: float = 1.0, restart: bool = false) -> void:
	if not has_anim(anim_name):
		return
	if current == anim_name and not restart and anim_player.is_playing():
		anim_player.speed_scale = speed
		return
	current = anim_name
	anim_player.play(anim_name, blend)
	anim_player.speed_scale = speed
	if restart:
		anim_player.seek(0.0, true)


func set_speed(speed: float) -> void:
	if anim_player:
		anim_player.speed_scale = speed


func set_flash(amount: float) -> void:
	Art.flash(self, amount)


## Replaces every surface material with the matching Art lit material (cached, shared).
## Materials carrying baked textures (tools/blender/bake.py) become Art.textured_mat;
## `use_textures` = false ignores them (debug / comparison).
static func convert_materials(root: Node, flashable: bool = true, use_textures: bool = true) -> void:
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				var src := mi.get_active_material(i) as BaseMaterial3D
				if src == null:
					continue
				var memo: Dictionary = _converted[int(flashable)]
				var dst: Material = memo.get(src) if use_textures else null
				if dst:
					mi.set_surface_override_material(i, dst)
					continue
				if use_textures and _is_textured(src):
					dst = _textured(src, flashable)
				elif src.emission_enabled and src.emission_energy_multiplier > 0.0:
					dst = Art.emissive(src.albedo_color, src.emission, src.emission_energy_multiplier,
						src.roughness, flashable)
				else:
					# Texture detail is chosen from the Blender material name (Art.SURFACE_KEYWORDS).
					var surface := Art.surface_for_name(src.resource_name)
					var sheen := 0.25 if surface in [&"cloth", &"skin", &"feather"] else 0.0
					dst = Art.mat(src.albedo_color, src.roughness, src.metallic, 0.3, flashable, sheen, surface)
				if use_textures:
					memo[src] = dst
				mi.set_surface_override_material(i, dst)
	for c in root.get_children():
		convert_materials(c, flashable, use_textures)


static func _is_textured(src: BaseMaterial3D) -> bool:
	return src.albedo_texture != null or src.normal_texture != null or src.roughness_texture != null


## Imported glTF PBR textures -> Art.textured_mat. The glTF importer splits the packed
## occlusion/roughness/metallic image into ao/roughness/metallic slots that share one texture.
static func _textured(src: BaseMaterial3D, flashable: bool) -> ShaderMaterial:
	var orm: Texture2D = src.roughness_texture
	if orm == null:
		orm = src.metallic_texture
	var has_ao := src.ao_enabled and src.ao_texture != null and src.ao_texture == orm
	var nrm: Texture2D = src.normal_texture if src.normal_enabled else null
	var glow := Color.BLACK
	var energy := 0.0
	var etex: Texture2D = null
	if src.emission_enabled and src.emission_energy_multiplier > 0.0:
		glow = src.emission
		energy = src.emission_energy_multiplier
		etex = src.emission_texture
	var surface := Art.surface_for_name(src.resource_name)
	var sheen := 0.25 if surface in [&"cloth", &"skin", &"feather"] else 0.0
	return Art.textured_mat(src.albedo_texture, nrm, orm, etex, src.albedo_color, src.roughness, src.metallic,
		glow, energy, flashable, sheen, has_ao, 0.1, surface)


static func _find_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for c in root.get_children():
		var p := _find_player(c)
		if p:
			return p
	return null
