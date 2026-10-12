class_name DemonModel
extends Node3D
## A playable demon, modeled and animated in Blender (tools/blender/models/demons/<id>.py ->
## res://assets/models/demons/<id>.glb, see DemonData.get_model_path()). Forward is -Z, feet at
## y = 0, ~2 units to the top of the head (horns, wings and halos go higher).
##
##   var demon := DemonModel.new()
##   add_child(demon)
##   demon.build(demon_data)
##   # every physics frame:
##   demon.animate(delta, velocity.length() / move_speed)
##
## Blender animations: idle, walk (loops), attack, hit, death, cheer. The head turns via the
## never-keyed "look" joint (look_yaw + idle glances). The death sequence (the "death" clip, then
## a top-down dissolve into embers and ash) runs in _physics_process with PROCESS_MODE_ALWAYS, so
## it finishes even if the game pauses.

const KNEEL_TIME := 1.15
const DISSOLVE_TIME := 1.05
const ASH_COLOR := Color(0.32, 0.3, 0.29)
## move_ratio above which the walk cycle plays.
const WALK_THRESHOLD := 0.12
## Ground speed (m/s) each demon's walk clip covers at playback 1.0 (planted feet), measured in
## Blender with sbanim.stride_speed. Walk playback = actual speed / this, so feet never skate.
const WALK_CLIP_SPEED := {
	&"vharok": 5.44, &"nhazgul": 5.44, &"lilaeth": 7.2, &"iscariel": 7.2, &"morvane": 6.0, &"skarn": 5.99, &"ysolde": 6.0,
}
const DEFAULT_WALK_CLIP_SPEED := 6.0
## Per-demon feel on top of the shared motion layer (demons that share a Blender rig and clips,
## like Nhazgul on Vharok's, still move differently). Keys are CharacterMotion properties
## (multiplied when the name ends in "*"), plus "tics" (insect head ticks instead of slow glances)
## and "presence" (the ground brand's colour, when it shouldn't follow the glow).
const MOTION_PROFILES := {
	&"nhazgul": {
		"twitch": 0.55, "twitch_interval": 0.5, "buzz_amp": 0.07, "buzz_hz": 19.0,
		"lean_k*": 1.6, "lean_c*": 0.7, "wing_k*": 1.8, "dangle_k*": 1.5, "dangle_c*": 0.6,
		"tics": true, "presence": Color(0.78, 1.0, 0.18),
	},
	# The Turncoat: the charred wing (on his right as he faces you) is a stiff, twitching ruin; the
	# pale one still moves like Lilaeth's. The brand is the holy gold he betrayed.
	&"iscariel": {
		"wing_odd_side": 1.0, "wing_odd_k": 2.4, "wing_odd_amp": 0.45, "wing_odd_twitch": 0.55,
		"presence": Color(1.0, 0.8, 0.42),
	},
}
const PRESENCE_SHADER := preload("res://shaders/characters/presence_ring.gdshader")
## Diameter (m) of the presence brand under the player's demon.
const PRESENCE_SIZE := 2.6

## Extra head turn in radians (+ turns toward the model's -X, i.e. its left). Smoothed.
var look_yaw := 0.0
## Actual ground speed in m/s, set by the owner each frame (0 = unknown → use move_ratio).
var ground_speed := 0.0
## The DemonData this model was last built from.
var data: DemonData
## World position the next hit comes from (Player.take_damage sets it right before the hurt);
## Vector3.INF = unknown. Only trusted for a moment, so a stale source never steers a later hit.
var hit_source := Vector3.INF:
	set(v):
		hit_source = v
		_hit_source_ms = Time.get_ticks_msec()
var _hit_source_ms := 0
## Skin it wears (DemonSkins id) and the glow color that skin gives it (lights, embers, ash).
var skin_id := &"default"
var glow_color := Color(1.0, 0.3, 0.06)

var _model: GlbModel
## Holds _model; CharacterMotion squashes / stretches it (the animation never writes it).
var _pivot: Node3D
## Procedural secondary motion on top of the Blender clips (lean, wings, cloth, flinches).
var _motion: CharacterMotion
var _look: Node3D
var _light: OmniLight3D
var _light_energy := 0.8
var _embers: CPUParticles3D
var _ash: CPUParticles3D

# ---- animation state
var _t := 0.0
var _walk := 0.0
var _oneshot := &""
var _oneshot_left := 0.0
var _oneshot_age := 0.0
var _glance := 0.0
var _glance_target := 0.0
var _glance_timer := 3.0
var _look_yaw_now := 0.0
var _roar := 0.0
var _dying := false
var _death_t := 0.0
var _dissolve_ready := false
var _dissolve_top := 2.0
## [MeshInstance3D, rest scale, normalized height] per mesh, collected when the dissolve starts.
var _dissolve: Array = []
var _flash_tween: Tween
## The demon's own death (DemonDeath: ash / feathers / hex / crumble / unravel), set when the
## dissolve starts.
var _death_fx: DemonDeath
var _dissolve_heights: Array = []
## MOTION_PROFILES entry of this demon ({} = none).
var _profile: Dictionary = {}
## ASCENDANT: the victory roar, held (play_victory).
var _victory := false
var _victory_t := 0.0
## Ground brand under the player's demon (see show_presence); null elsewhere (menus).
var _presence: MeshInstance3D
var _presence_mat: ShaderMaterial


func _ready() -> void:
	set_physics_process(_dying)


# ---------------------------------------------------------------- building

## (Re)builds the model from `demon`, wearing `skin` (empty = the skin chosen for this demon,
## see DemonSkins).
func build(demon: DemonData, skin: StringName = &"") -> void:
	data = demon
	if _flash_tween:
		_flash_tween.kill()
		_flash_tween = null
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_clear_refs()
	if demon == null:
		return

	_model = GlbModel.create(demon.get_model_path())
	# Blender models face Blender -Y, which glTF imports as +Z; turn them to Godot's forward (-Z).
	_model.rotation.y = PI
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	_pivot.add_child(_model)
	if _model.scene_root == null:
		return
	_motion = CharacterMotion.attach(_model, self, _pivot)
	if _motion and demon.build == DemonData.Build.BRUTE:
		# Heavy bodies lean less and swing their gear harder.
		_motion.lean_accel *= 0.7
		_motion.dangle_accel *= 1.2
	_profile = MOTION_PROFILES.get(DemonSkins.demon_id_of(demon), {})
	if _motion:
		for key: String in _profile:
			if key.ends_with("*"):
				var prop := key.trim_suffix("*")
				_motion.set(prop, float(_motion.get(prop)) * float(_profile[key]))
			elif key in _motion:
				_motion.set(key, _profile[key])
	_look = _model.scene_root.find_child("look", true, false) as Node3D
	skin_id = skin if skin != &"" else DemonSkins.selected_id(DemonSkins.demon_id_of(demon))
	glow_color = DemonSkins.apply(self, skin_id)
	if skin_id != DemonSkins.DEFAULT_ID:
		_tint_rim.call_deferred()

	# One small light per demon: from the grimoire if it has one, else in front of the face.
	var book := _model.scene_root.find_child("grimoire", true, false) as Node3D
	if book:
		# Kept small and lifted above the book: at hip height a strong light pooled a big glowing
		# stain on the floor that read as a bug from the high game camera.
		_light_energy = 0.6
		_light = Art.light(book, glow_color, _light_energy, 2.0, Vector3(0.0, 0.45, 0.0))
	else:
		_light_energy = 0.7
		_light = Art.light(self, glow_color, _light_energy, 2.6, Vector3(0.0, 1.85, -0.45))
	_embers = InfernalFx.embers(self, glow_color, 6, 1.5, 0.3, Vector3(0.0, 1.3, 0.0), 2.4)
	_embers.gravity = Vector3(0.0, 0.9, 0.0)
	# Blender "fx_embers*" joints (e.g. Skarn's furnace stacks) vent a thin plume of embers.
	for vent in _model.scene_root.find_children("fx_embers*", "Node3D", true, false):
		var plume := InfernalFx.embers(vent as Node3D, glow_color, 5, 0.9, 0.04, Vector3.ZERO, 2.8)
		plume.gravity = Vector3(0.0, 2.2, 0.0)
		plume.initial_velocity_min = 0.4
		plume.initial_velocity_max = 1.0

	if _is_player_avatar():
		show_presence(true)
		# The run's end: a victory gets the held roar behind the ASCENDANT screen.
		var rs := get_node_or_null(^"/root/RunState")
		if rs and rs.has_signal(&"run_ended") and not rs.is_connected(&"run_ended", _on_run_ended):
			rs.connect(&"run_ended", _on_run_ended)

	_glance_timer = randf_range(2.0, 5.0)
	_model.play(&"idle", 0.0)
	if _model.anim_player:
		_model.anim_player.seek(randf() * 1.5, true)
	animate(0.0, 0.0)
	if is_inside_tree():
		reset_physics_interpolation()


func _clear_refs() -> void:
	_death_fx = null
	_victory = false
	_presence = null
	_presence_mat = null
	_model = null
	_pivot = null
	_motion = null
	_look = null
	_light = null
	_embers = null
	_ash = null
	_dissolve.clear()
	_dissolve_ready = false
	_dying = false
	_death_t = 0.0
	_oneshot = &""
	_oneshot_left = 0.0
	_roar = 0.0
	_walk = 0.0
	_look_yaw_now = 0.0
	process_mode = Node.PROCESS_MODE_INHERIT
	set_physics_process(false)


# ---------------------------------------------------------------- animation

## Call every physics frame. `move_ratio` = current speed / max speed (0 = idle, 1 = full walk).
func animate(delta: float, move_ratio: float) -> void:
	if _model == null or _model.anim_player == null or _dying or _victory:
		return
	_t += delta
	_walk = lerpf(_walk, clampf(move_ratio, 0.0, 1.3), 1.0 - exp(-10.0 * delta))
	var idle := 1.0 - clampf(_walk, 0.0, 1.0)

	# One-shots (hit / attack / cheer) play to the end, then hand back to idle/walk.
	if _oneshot != &"":
		_oneshot_left -= delta
		_oneshot_age += delta
		if _oneshot_left <= 0.0:
			_oneshot = &""
	if _oneshot == &"":
		if _walk > WALK_THRESHOLD:
			var rate := clampf(_walk, 0.55, 1.3)
			if ground_speed > 0.05 and data:
				var id := StringName(data.get_model_path().get_file().get_basename())
				rate = clampf(ground_speed / float(WALK_CLIP_SPEED.get(id, DEFAULT_WALK_CLIP_SPEED)), 0.3, 1.8)
			_model.play(&"walk", 0.2, rate)
		else:
			_model.play(&"idle", 0.3, 1.0)

	# Head: steady gaze ahead, a slow menacing glance now and then.
	_glance_timer -= delta
	var tics: bool = _profile.get("tics", false)
	if tics and _glance_timer <= 0.0:
		# Insect head: small, sudden ticks to a new angle every fraction of a second.
		_glance_target = randf_range(-0.35, 0.35) if randf() < 0.7 else 0.0
		_glance_timer = randf_range(0.25, 0.9)
	elif _glance_timer <= 0.0:
		if is_zero_approx(_glance_target) and randf() < 0.6:
			_glance_target = randf_range(0.35, 0.6) * (1.0 if randf() < 0.5 else -1.0)
			_glance_timer = randf_range(1.2, 2.2)
		else:
			_glance_target = 0.0
			_glance_timer = randf_range(3.0, 6.0)
	var quiet := idle if _oneshot == &"" else 0.0
	_glance = lerpf(_glance, _glance_target * quiet, 1.0 - exp(-(22.0 if tics else 2.5) * delta))
	var goal := clampf(look_yaw, -1.0, 1.0) * (1.0 if _oneshot != &"cheer" else 0.3) + _glance
	_look_yaw_now = lerpf(_look_yaw_now, goal, 1.0 - exp(-6.0 * delta))
	if _look:
		_look.rotation = Vector3(0.0, _look_yaw_now, 0.0)

	_roar = move_toward(_roar, 1.0 if _oneshot == &"cheer" and _oneshot_age > 0.4 else 0.0, delta * 3.0)
	if _light:
		_light.light_energy = _light_energy * (1.0 + sin(_t * 11.0) * 0.06 + sin(_t * 17.0) * 0.04 + _roar * 1.6)


func _play_oneshot(anim_name: StringName, blend: float) -> void:
	if _model == null or not _model.has_anim(anim_name):
		return
	_model.play(anim_name, blend, 1.0, true)
	_oneshot = anim_name
	_oneshot_age = 0.0
	_oneshot_left = _model.anim_player.get_animation(anim_name).length - blend * 0.5


# ---------------------------------------------------------------- reactions

## White hit-flash (0..1) on the whole model.
func set_flash(amount: float) -> void:
	Art.flash(self, amount)


## Hit flash + the "hit" recoil + a directional flinch away from `from_dir` (world direction the
## blow came from; zero = toward the nearest enemy, if any). Safe to call every frame.
func play_hurt(from_dir: Vector3 = Vector3.ZERO) -> void:
	if _model == null or _dying:
		return
	if _motion:
		var fresh := Time.get_ticks_msec() - _hit_source_ms < 150
		if from_dir.length_squared() < 0.0001 and hit_source != Vector3.INF and fresh and is_inside_tree():
			from_dir = hit_source - global_position
		hit_source = Vector3.INF
		if from_dir.length_squared() < 0.0001 and is_inside_tree():
			var e := Targeting.nearest_enemy(get_tree(), global_position, 4.0)
			if e:
				from_dir = e.global_position - global_position
		_motion.hit(from_dir, 1.0)
	if _flash_tween:
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_method(set_flash, 1.0, 0.0, 0.22)
	if _presence_mat:
		_flash_tween.parallel().tween_method(_pulse_presence, 1.0, 0.0, 0.35)
	if _oneshot == &"cheer" or (_oneshot == &"hit" and _oneshot_age < 0.2):
		return
	_play_oneshot(&"hit", 0.05)


## The "attack" swing / cast (optional; the game's weapons fire on their own).
func play_attack() -> void:
	if _model == null or _dying or _oneshot == &"cheer":
		return
	_play_oneshot(&"attack", 0.06)
	if _motion:
		_motion.kick(0.6)


## Plays "death" (stagger, kneel, slump), then dissolves top-down into embers and ash.
## Stays gone until play_cheer() or build().
func play_faint() -> void:
	if _model == null or _dying:
		return
	_dying = true
	_death_t = 0.0
	_oneshot = &""
	_dissolve_ready = false
	if _flash_tween:
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_method(set_flash, 1.0, 0.0, 0.4)
	_model.play(&"death", 0.1, 1.0, true)
	if _motion:
		# The death clip owns the body from here: fade the procedural layer out.
		create_tween().tween_property(_motion, "weight", 0.0, 0.35)
	if _presence_mat:
		create_tween().tween_method(func(v: float) -> void: _presence_mat.set_shader_parameter(&"energy", v),
			1.0, 0.0, 0.8)
	# Keep going behind the game-over screen (it pauses the tree).
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_physics_process(true)
	_burst_local(Vector3(0.0, 1.4, 0.0), glow_color, 18, 2.2)


## ASCENDANT: the "cheer" roar, held at its peak with the arms flung wide, embers bursting, the
## light and the presence brand blazing. Keeps playing while the end screen pauses the game.
func play_victory() -> void:
	if _model == null or _dying or _victory:
		return
	_victory = true
	_victory_t = 0.0
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_physics_process(true)
	_play_oneshot(&"cheer", 0.15)
	if _motion:
		_motion.kick(1.6)
	_burst_local(Vector3(0.0, 1.5, 0.0), glow_color, 40, 3.5)
	var hold := 1.0
	if _model.has_anim(&"cheer"):
		hold = _model.anim_player.get_animation(&"cheer").length * 0.62
	var tw := create_tween()
	tw.tween_interval(hold)
	tw.tween_callback(func() -> void:
		if _victory and _model:
			_model.set_speed(0.0))


func _on_run_ended(result: Dictionary) -> void:
	if bool(result.get("victory", false)) and is_inside_tree():
		play_victory()


## Menacing roar / flourish ("cheer"). Also restores a dissolved model.
func play_cheer() -> void:
	if _model == null:
		return
	if _dying:
		_revive()
	_play_oneshot(&"cheer", 0.1)
	if _motion:
		_motion.kick(1.2)
	_burst_local(Vector3(0.0, 1.5, 0.0), glow_color, 22, 2.6)


## The faint brand of rune dashes on the ground under the demon (on by default for the player's
## own demon, so it can be found in a horde). Takes the skin's glow color; pulses on hits.
func show_presence(on: bool) -> void:
	if not on:
		if _presence:
			_presence.queue_free()
			_presence = null
		return
	if _presence:
		return
	_presence_mat = ShaderMaterial.new()
	_presence_mat.shader = PRESENCE_SHADER
	# Skins recolour the brand with their glow; the true form may have its own (MOTION_PROFILES).
	var brand: Color = glow_color
	if skin_id == DemonSkins.DEFAULT_ID and _profile.has("presence"):
		brand = _profile["presence"]
	_presence_mat.set_shader_parameter(&"color", brand)
	var plane := PlaneMesh.new()
	plane.size = Vector2(PRESENCE_SIZE, PRESENCE_SIZE)
	_presence = MeshInstance3D.new()
	_presence.name = "Presence"
	_presence.mesh = plane
	_presence.material_override = _presence_mat
	_presence.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_presence.position.y = 0.04
	add_child(_presence)


func _is_player_avatar() -> bool:
	var n := get_parent()
	while n:
		if n.is_in_group(&"player"):
			return true
		n = n.get_parent()
	return false


func _pulse_presence(amount: float) -> void:
	if _presence_mat:
		_presence_mat.set_shader_parameter(&"pulse", amount)


## Skins: the faction rim light (Style.apply_faction, set by the owner right after build()) takes
## the skin's glow color. Runs deferred so it sees the rim the owner set; no rim = nothing to do.
func _tint_rim() -> void:
	if _model == null:
		return
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(_model, meshes)
	for mi in meshes:
		var rim: Variant = mi.get_instance_shader_parameter(&"rim_color")
		if rim is Color and (rim as Color).a > 0.0:
			mi.set_instance_shader_parameter(&"rim_color", Color(glow_color, (rim as Color).a))


## Rebuilds the model in another skin (menus / wardrobe). Doesn't save the choice: see
## DemonSkins.select().
func set_skin(id: StringName) -> void:
	if data and id != skin_id:
		build(data, id)
		play_cheer()


func _revive() -> void:
	_dying = false
	_death_t = 0.0
	if _death_fx:
		_death_fx.restore()
		_death_fx = null
	for entry: Array in _dissolve:
		var mi := entry[0] as MeshInstance3D
		if is_instance_valid(mi):
			mi.scale = entry[1]
			mi.visible = true
	_dissolve.clear()
	_dissolve_ready = false
	if _ash:
		_ash.queue_free()
		_ash = null
	if _embers:
		_embers.emitting = true
	if _light:
		_light.visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	set_physics_process(false)
	if _motion:
		_motion.weight = 1.0
	if _presence_mat:
		_presence_mat.set_shader_parameter(&"energy", 1.0)
	_model.play(&"idle", 0.0, 1.0, true)


func _physics_process(delta: float) -> void:
	if _victory and _model:
		_victory_step(delta)
		return
	if not _dying or _model == null:
		return
	_death_t += delta

	# Dissolve: a burning line sweeps down the body, each part crumbling to ash as it passes.
	var d := clampf((_death_t - KNEEL_TIME) / DISSOLVE_TIME, 0.0, 1.0)
	if d <= 0.0:
		return
	if not _dissolve_ready:
		_start_dissolve()
	var sweep := 1.08 - d * 1.22
	if _death_fx:
		_death_fx.step(d, sweep, _dissolve_heights)
	if _ash:
		_ash.position.y = clampf(sweep, 0.0, 1.0) * _dissolve_top
		_ash.emitting = d < 1.0
	if _light:
		_light.light_energy = _light_energy * 2.0 * (1.0 - d)
		_light.visible = d < 1.0
	if _embers and d > 0.4:
		_embers.emitting = false
	if d >= 1.0 and _death_t > KNEEL_TIME + DISSOLVE_TIME + 2.0:
		set_physics_process(false)


func _start_dissolve() -> void:
	_dissolve_ready = true
	_dissolve.clear()
	var top := 0.1
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(_model, meshes)
	var heights: Array[float] = []
	for mi in meshes:
		var h := to_local(mi.global_transform * mi.get_aabb().get_center()).y
		heights.append(h)
		top = maxf(top, h)
	_dissolve_top = top
	_dissolve_heights.clear()
	for i in meshes.size():
		_dissolve.append([meshes[i], meshes[i].scale, clampf(heights[i] / top, 0.0, 1.0)])
		_dissolve_heights.append(clampf(heights[i] / top, 0.0, 1.0))
	_death_fx = DemonDeath.new(self, DemonDeath.style_for(DemonSkins.demon_id_of(data)))
	_death_fx.start(meshes)

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.55, 1.0])
	ramp.colors = PackedColorArray([
		Color(1.0, 0.85, 0.6, 1.0),
		Color(glow_color, 1.0),
		Color(ASH_COLOR, 0.8),
		Color(ASH_COLOR.darkened(0.5), 0.0),
	])
	_ash = InfernalFx.make_particles(glow_color, 70, 1.5, 2.2)
	_ash.color_ramp = ramp
	_ash.local_coords = false
	_ash.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_ash.emission_box_extents = Vector3(0.45, 0.06, 0.35)
	_ash.initial_velocity_min = 0.3
	_ash.initial_velocity_max = 1.3
	_ash.spread = 50.0
	_ash.gravity = Vector3(0.0, 1.4, 0.0)
	_ash.scale_amount_min = 0.6
	_ash.scale_amount_max = 1.6
	_ash.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_ash.position = Vector3(0.0, top, 0.0)
	add_child(_ash)
	_ash.emitting = true


## Victory hold: the light pulses hot, embers burst now and then, the brand blazes.
func _victory_step(delta: float) -> void:
	_victory_t += delta
	var pulse := 0.5 + 0.5 * sin(_victory_t * 5.0)
	if _light:
		_light.light_energy = _light_energy * (2.2 + 0.8 * pulse)
	if _presence_mat:
		_presence_mat.set_shader_parameter(&"pulse", 0.5 + 0.4 * pulse)
	if fmod(_victory_t, 1.1) < delta:
		_burst_local(Vector3(0.0, 1.6, 0.0), glow_color, 14, 2.4)


func _collect_meshes(root: Node, out: Array[MeshInstance3D]) -> void:
	for child in root.get_children():
		if child is MeshInstance3D:
			out.append(child as MeshInstance3D)
		_collect_meshes(child, out)


## One-shot ember burst parented to the model (works without Game.world, e.g. on the menu).
func _burst_local(pos: Vector3, color: Color, amount: int, speed: float) -> void:
	var p := InfernalFx.make_particles(color, amount, 0.9)
	p.one_shot = true
	p.explosiveness = 0.85
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.35
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0.0, 1.6, 0.0)
	p.damping_min = speed * 0.6
	p.damping_max = speed * 1.2
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	p.position = pos
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
