class_name SarielModel
extends EnemyModel
## "Sariel, Herald of the Last Dawn": a towering six-winged seraph of ivory plate and gold, its
## head hidden under a faceless veil, a great halo of turning rings and unblinking eyes behind it,
## a spear of light in its right hand. The mesh and its animations are made in Blender
## (tools/blender/models/bosses/sariel.py -> res://assets/models/bosses/sariel.glb, ~4.3 m tall).
## The model node is built at 1/3 scale (feet at y = 0, forward -Z); the boss scales it by
## EnemyData.size (3), so in the world it stands at its real height.
##
## The Boss drives the pose every frame through the public fields below (targets; the model
## eases toward them) and reads `beat` (true for one frame at each wing downstroke). The fields
## weight Blender pose clips layered in an AnimationTree over the idle / glide wingbeat:
##   base: idle <-> glide (move ratio), time-scaled (slower, heavier beats when enraged)
##   then spread, summon, channel, raise, descent, kneel (filtered Blend2 layers, in that order).

const GLB := "res://assets/models/bosses/sariel.glb"
## The glb is authored at real size; EnemyData.size (3) scales it back up.
const MODEL_SCALE := 1.0 / 3.0
const FLAP_PERIOD := 1.8
const RAGE_FLAP_PERIOD := 2.3
const DESCENT_HEIGHT := 5.0
const RING_SPEEDS := [0.35, -0.5, 0.2]
## Overlay clips, bottom to top (later layers win where they overlap).
const LAYERS := [&"spread", &"summon", &"channel", &"raise", &"descent", &"kneel"]
## Feather chunk meshes are named wing<p><L|R>_<group><k>_mesh; they are shed in this group order
## (flight feathers first, the gilded coverts on the bone last).
const FEATHER_GROUPS := ["pri", "sec", "cov", "les"]
const ARMS := ["torso", "head", "shoulder_?", "elbow_?", "hand_?", "spear"]
## Joints each layer drives (the glTF export samples every animated joint into every clip, so the
## Blend2 filters are set from these name patterns).
const LAYER_JOINTS := {
	&"spread": ["torso", "wing*_mount", "wing*_pri?"],
	&"summon": ["torso", "head", "shoulder_?", "elbow_?", "hand_?", "spear", "wing*_mount"],
	&"channel": ARMS,
	&"raise": ["torso", "head", "shoulder_?", "elbow_?", "hand_?", "spear", "wing*_mount"],
	&"descent": ["body", "head", "shoulder_?", "elbow_?", "hand_?", "spear", "wing*_mount", "wing*_arm",
		"wing*_fore", "wing*_hand", "strip*", "veil*"],
	&"kneel": ["*"],
}

## Spear raised overhead (Judgement Pillars), 0..1.
var raise := 0.0
## Halo blazing / spinning fast (Radiant Sweep, Dawn Ring), 0..1.
var channel := 0.0
## Arms opened wide (Heavenly Host), 0..1.
var summon := 0.0
## Enraged: wings flung wide, brighter light, 0..1.
var spread := 0.0
## Death: kneels, 0..1.
var kneel := 0.0
## Death: wings disintegrate into feathers, 0..1 (one-way).
var dissolve := 0.0
## Intro: 1 = high in the sky, 0 = landed.
var descent := 0.0
## True for the frame a wing downstroke begins (the boss plays the wingbeat sound and clears it).
var beat := false

var _raise := 0.0
var _channel := 0.0
var _summon := 0.0
var _spread := 0.0
var _kneel := 0.0
var _move := 0.0
var _flap_t := 0.0
var _shed := 0

var _lift: Node3D
var _glb: GlbModel
var _tree: AnimationTree
var _halo: Node3D
var _spear_tip: Node3D
var _ring_spins: Array[Node3D] = []
var _halo_mats: Array[StandardMaterial3D] = []
var _halo_colors: Array[Color] = []
var _halo_energy: Array[float] = []
var _halo_light: OmniLight3D
var _eye_mat: StandardMaterial3D
var _spear_mat: StandardMaterial3D
var _veil_mat: StandardMaterial3D
var _wing_glow: ShaderMaterial
## Feather meshes (8 chunks per wing), hidden one by one as the wings dissolve.
var _chunks: Array[MeshInstance3D] = []
## Wing tips (fallback feather points once every chunk is gone).
var _points: Array[Node3D] = []


func build() -> void:
	_lift = Art.pivot(self)
	_glb = GlbModel.create(GLB)
	if _glb.scene_root == null:
		return
	_glb.scale = Vector3.ONE * MODEL_SCALE
	# Blender's -Y front exports as +Z; turn it to face the game's forward (-Z).
	_glb.rotation.y = PI
	_lift.add_child(_glb)
	var root := _glb.scene_root
	_halo = root.find_child("halo", true, false) as Node3D
	_spear_tip = root.find_child("spear_tip", true, false) as Node3D
	for i in 3:
		_ring_spins.append(root.find_child("halo_spin%d" % i, true, false) as Node3D)
	_make_materials()
	_retexture(root)
	if _halo:
		Art.no_shadows(_halo)
		_halo_light = Art.light(_halo, Art.HOLY, 1.8, 9.0)
	_collect_feathers(root)
	_setup_tree()
	# characters-polish: procedural wing / veil / strip physics, lean and flinch on top of the tree.
	motion = CharacterMotion.attach(_glb, self, null, _tree)
	if motion:
		motion.lean_accel *= 0.5
		motion.wing_k *= 0.6
		motion.wing_accel *= 0.6


func _make_materials() -> void:
	var specs := [[Art.HOLY, 2.4], [Art.GOLD, 1.7], [Art.HOLY_WHITE, 1.2], [Art.HOLY, 0.22]]
	for s: Array in specs:
		_halo_mats.append(HolyFX.additive(s[0], s[1]))
		_halo_colors.append(s[0])
		_halo_energy.append(s[1])
	_eye_mat = HolyFX.additive(Art.HOLY, 2.2)
	_spear_mat = HolyFX.additive(Art.HOLY_WHITE, 1.8)
	_veil_mat = HolyFX.additive(Art.HOLY, 0.5)


## Swaps the glowing parts (by Blender material name) for materials the boss can modulate.
func _retexture(n: Node) -> void:
	var mi := n as MeshInstance3D
	if mi and mi.mesh:
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			if src == null:
				continue
			var m: Material = null
			match src.resource_name:
				"Sariel_HaloInner":
					m = _halo_mats[0]
				"Sariel_HaloGold":
					m = _halo_mats[1]
				"Sariel_HaloOuter":
					m = _halo_mats[2]
				"Sariel_HaloDisc":
					m = _halo_mats[3]
				"Sariel_EyeIris":
					m = _eye_mat
				"Sariel_SpearLight":
					m = _spear_mat
				"Sariel_VeilGlow":
					m = _veil_mat
				"Sariel_WingGlow":
					if _wing_glow == null:
						var cur := mi.get_surface_override_material(i) as ShaderMaterial
						_wing_glow = (cur.duplicate() if cur else Art.emissive(Art.IVORY, Art.HOLY, 0.2, 0.75).duplicate()) as ShaderMaterial
					m = _wing_glow
			if m:
				mi.set_surface_override_material(i, m)
	for c in n.get_children():
		_retexture(c)


func _collect_feathers(root: Node) -> void:
	var order := {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var nm := String(n.name)
		if not nm.begins_with("wing"):
			continue
		if nm.ends_with("_hand") and n is Node3D:
			_points.append(n as Node3D)
		if n is MeshInstance3D and nm.ends_with("_mesh") and nm.length() > 12:
			# wing0L_pri2_mesh: group = chars 7..9, index = char 10.
			var g := FEATHER_GROUPS.find(nm.substr(7, 3))
			if g >= 0:
				_chunks.append(n as MeshInstance3D)
				order[n] = float(g) * 2.0 - float(nm.substr(10, 1).to_int()) * 0.5 + randf() * 1.6
	_chunks.sort_custom(func(a: MeshInstance3D, b: MeshInstance3D) -> bool: return order[a] < order[b])


static func _chunk_center(c: MeshInstance3D) -> Vector3:
	return c.to_global(c.get_aabb().get_center())


func _setup_tree() -> void:
	var ap := _glb.anim_player
	if ap == null:
		return
	ap.stop()
	for n in ap.get_animation_list():
		ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	var bt := AnimationNodeBlendTree.new()
	var idle := AnimationNodeAnimation.new()
	idle.animation = &"idle"
	var glide := AnimationNodeAnimation.new()
	glide.animation = &"glide" if ap.has_animation(&"glide") else &"idle"
	bt.add_node(&"idle", idle)
	bt.add_node(&"glide", glide)
	bt.add_node(&"move", AnimationNodeBlend2.new())
	bt.connect_node(&"move", 0, &"idle")
	bt.connect_node(&"move", 1, &"glide")
	bt.add_node(&"speed", AnimationNodeTimeScale.new())
	bt.connect_node(&"speed", 0, &"move")
	var prev := &"speed"
	for layer: StringName in LAYERS:
		if not ap.has_animation(layer):
			continue
		var clip := AnimationNodeAnimation.new()
		clip.animation = layer
		var clip_name := StringName("%s_clip" % layer)
		bt.add_node(clip_name, clip)
		var blend := AnimationNodeBlend2.new()
		blend.filter_enabled = true
		var anim := ap.get_animation(layer)
		var pats: Array = LAYER_JOINTS[layer]
		for i in anim.get_track_count():
			var path := anim.track_get_path(i)
			var joint := String(path.get_name(path.get_name_count() - 1))
			for p: String in pats:
				if joint.match(p):
					blend.set_filter_path(path, true)
					break
		bt.add_node(layer, blend)
		bt.connect_node(layer, 0, prev)
		bt.connect_node(layer, 1, clip_name)
		prev = layer
	bt.connect_node(&"output", 0, prev)
	_tree = AnimationTree.new()
	_tree.deterministic = false
	_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_glb.scene_root.add_child(_tree)
	_tree.tree_root = bt
	_tree.anim_player = _tree.get_path_to(ap)
	_tree.active = true
	for layer: StringName in LAYERS:
		_set_amount(layer, 0.0)
	_tree.advance(0.0)


func _set_amount(layer: StringName, v: float) -> void:
	_tree.set(StringName("parameters/%s/blend_amount" % layer), v)


# ---------------------------------------------------------------- animation

func animate(delta: float, move_ratio: float, state: int) -> void:
	super.animate(delta, move_ratio, state)
	_raise = _damp(_raise, raise, 7.0 if raise > _raise else 9.0, delta)
	_channel = _damp(_channel, channel, 4.0, delta)
	_summon = _damp(_summon, summon, 4.0, delta)
	_spread = _damp(_spread, spread, 1.5, delta)
	_kneel = _damp(_kneel, kneel, 2.2, delta)
	_move = _damp(_move, move_ratio, 4.0, delta)
	if _glb == null or _glb.scene_root == null:
		return

	_lift.position.y = descent * DESCENT_HEIGHT
	if motion:
		motion.weight = (1.0 - _kneel) * (1.0 - clampf(dissolve, 0.0, 1.0))  # characters-polish

	# Wingbeat clock (in step with the idle / glide clips: downstroke at their frame 0).
	var period := lerpf(FLAP_PERIOD, RAGE_FLAP_PERIOD, _spread)
	var time_scale := FLAP_PERIOD / period
	_flap_t += delta * time_scale
	if _flap_t >= FLAP_PERIOD:
		_flap_t -= FLAP_PERIOD
		if _kneel < 0.3 and dissolve <= 0.0:
			beat = true
	if _tree:
		_tree.set(&"parameters/move/blend_amount", _move)
		_tree.set(&"parameters/speed/scale", time_scale)
		_set_amount(&"spread", _spread)
		_set_amount(&"summon", _summon)
		_set_amount(&"channel", _channel)
		_set_amount(&"raise", _raise)
		_set_amount(&"descent", clampf(descent * 3.0, 0.0, 1.0))
		_set_amount(&"kneel", _kneel)
		_tree.advance(delta)

	# Halo: spins faster and blazes while channelling / enraged.
	var spin_mult := 1.0 + _channel * 4.0 + _spread * 0.8
	for i in _ring_spins.size():
		var r := _ring_spins[i]
		if r:
			r.rotation.z = wrapf(r.rotation.z + float(RING_SPEEDS[i]) * spin_mult * delta, -PI, PI)
	var bright := (1.0 + _channel * 1.2 + _spread * 0.6) * (1.0 - _kneel * 0.5)
	for i in _halo_mats.size():
		_halo_mats[i].albedo_color = HolyFX.scaled(_halo_colors[i], _halo_energy[i] * bright)
	_eye_mat.albedo_color = HolyFX.scaled(Art.HOLY, (2.2 + _channel * 2.0 + _spread * 1.5) * (1.0 - _kneel * 0.8))
	_veil_mat.albedo_color = HolyFX.scaled(Art.HOLY, (0.5 + _channel * 0.6 + _spread * 0.4) * (1.0 - _kneel * 0.7))
	if _halo:
		_halo.scale = Vector3.ONE * (1.0 + _channel * 0.12 + _spread * 0.1)
	if _halo_light:
		_halo_light.light_energy = (1.8 + _channel * 2.5 + _spread * 1.5) * (1.0 - _kneel * 0.6)
	var spear_e := 1.8 + 1.6 * _raise + 0.8 * _spread
	_spear_mat.albedo_color = HolyFX.scaled(Art.HOLY_WHITE, spear_e * (0.94 + 0.06 * sin(t * 13.0)))
	if _wing_glow:
		_wing_glow.set_shader_parameter(&"emission_energy", 0.2 + _spread * 0.9 + _channel * 0.3)

	# Death: the wings come apart layer by layer, each loosing a drift of falling feathers.
	var target := mini(roundi(dissolve * float(_chunks.size())), _chunks.size())
	while _shed < target:
		var c := _chunks[_shed]
		var at := _chunk_center(c)
		c.visible = false
		HolyFX.feathers(at, 4, 1.0, 2.4)
		HolyFX.motes(at, 4, Art.HOLY, 0.5, 1.2, 1.0)
		_shed += 1


static func _damp(from: float, to: float, rate: float, delta: float) -> float:
	return lerpf(from, to, 1.0 - exp(-rate * delta))


func set_flash(amount: float) -> void:
	Art.flash(self, amount)


func halo_global() -> Vector3:
	return _halo.global_position if _halo else global_position + Vector3.UP * 3.2


func spear_tip_global() -> Vector3:
	return _spear_tip.global_position if _spear_tip else global_position + Vector3.UP * 4.0


## World positions of a few still-attached feathers (for death bursts).
func wing_points(count: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var live: Array[MeshInstance3D] = []
	for c in _chunks:
		if c.visible:
			live.append(c)
	for i in count:
		if not live.is_empty():
			out.append(_chunk_center(live[randi() % live.size()]))
		elif not _points.is_empty():
			out.append(_points[randi() % _points.size()].global_position)
	return out
