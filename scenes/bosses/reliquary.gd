class_name ReliquaryOfSin
extends Node3D
## Boss reward: a horned black-iron reliquary bound in tarnished gold, its seams leaking crimson
## light. It rises out of the ground on a blood sigil, beats like a heart, and when the demon comes
## close (or after a few seconds) it bursts open into a ring of relic soul shards worth `xp_total`.
## Use ReliquaryOfSin.drop(world_position, xp_total).

const GEM_SCENE := preload("res://scenes/pickups/xp_gem.tscn")
const MODEL := "res://assets/models/bosses/reliquary.glb"
const OPEN_RADIUS := 2.8
const AUTO_OPEN_TIME := 6.0
const RISE_TIME := 1.1
const LINGER_TIME := 1.4
const SINK := 1.6

var xp_total := 300.0
var delay := 0.6

var _body: Node3D
var _lid: Node3D
var _seam_mat: StandardMaterial3D
var _heart_mat: StandardMaterial3D
var _sigil: BossTelegraph
var _light: OmniLight3D
var _t := 0.0
var _risen := false
var _rise_t := 0.0
var _wait_t := 0.0
var _opened := false
var _open_t := 0.0


## Spawns a reliquary that rises at `at` (XZ) after `wait` seconds.
static func drop(at: Vector3, xp: float, wait: float = 0.6) -> void:
	if Game.world == null:
		return
	var r := ReliquaryOfSin.new()
	r.xp_total = xp
	r.delay = wait
	Game.spawn(r, Vector3(at.x, 0.0, at.z))


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_build()
	_body.position.y = -SINK
	_body.visible = false


func _process(delta: float) -> void:
	_t += delta
	if delay > 0.0:
		delay -= delta
		if delay <= 0.0:
			_body.visible = true
			Sfx.play(&"impact", 0.05, -6.0)
			HolyFX.motes(global_position + Vector3(0.0, 0.1, 0.0), 14, Art.SOUL, 1.2, 1.6, 1.4, 0.06)
		return
	var heart := pow(maxf(sin(_t * 4.4), 0.0), 6.0) + 0.6 * pow(maxf(sin(_t * 4.4 - 0.9), 0.0), 8.0)
	if not _risen:
		_rise_t += delta
		var k := clampf(_rise_t / RISE_TIME, 0.0, 1.0)
		_body.position.y = -SINK * (1.0 - _ease_out_cubic(k))
		_body.rotation.y = (1.0 - k) * 0.6
		_sigil.show_disc(global_position, 1.9, Art.SOUL, k, minf(_rise_t * 3.0, 1.0), 1.4)
		if randf() < delta * 14.0:
			HolyFX.motes(global_position + Vector3(randf_range(-0.6, 0.6), 0.05, randf_range(-0.6, 0.6)),
					2, Art.EMBER, 0.3, 1.2, 0.8, 0.04)
		if k >= 1.0:
			_risen = true
			get_tree().call_group(&"camera_rig", &"shake", 0.15)
	if _opened:
		_open_t += delta
		_sigil.show_disc(global_position, 1.9, Art.SOUL, 1.0, maxf(1.0 - _open_t / LINGER_TIME, 0.0), 1.4)
		if _open_t >= LINGER_TIME and not is_queued_for_deletion():
			var tw := create_tween()
			tw.tween_property(_body, "position:y", -SINK, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(_light, "light_energy", 0.0, 0.8)
			tw.tween_callback(queue_free)
			set_process(false)
		return
	# Waiting: a slow, heavy heartbeat in the seams and the light.
	_seam_mat.albedo_color = HolyFX.scaled(Art.SOUL, 1.4 + 2.2 * heart)
	_heart_mat.albedo_color = HolyFX.scaled(Art.SOUL, 2.0 + 3.0 * heart)
	_light.light_energy = 1.2 + 1.8 * heart
	_body.scale = Vector3.ONE * (1.0 + 0.025 * heart)
	if _risen:
		_sigil.show_disc(global_position, 1.9, Art.SOUL, 1.0, 0.7 + 0.3 * heart, 1.4)
		_wait_t += delta
		var p := Game.player
		var close := false
		if p and is_instance_valid(p):
			var d := p.global_position - global_position
			d.y = 0.0
			close = d.length() <= OPEN_RADIUS
		if close or _wait_t >= AUTO_OPEN_TIME:
			_open()


func _open() -> void:
	_opened = true
	_body.scale = Vector3.ONE
	Sfx.play(&"soul", 0.0, 2.0)
	Sfx.play(&"impact", 0.1, -3.0)
	get_tree().call_group(&"camera_rig", &"shake", 0.3)
	var lt := _lid.create_tween()
	lt.tween_property(_lid, "position", _lid.position + Vector3(0.0, 1.4, 0.25), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	lt.parallel().tween_property(_lid, "rotation", Vector3(-1.1, 0.3, 0.2), 0.4)
	lt.tween_property(_lid, "scale", Vector3.ONE * 0.01, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_seam_mat.albedo_color = HolyFX.scaled(Art.SOUL, 4.0)
	var top := global_position + Vector3(0.0, 0.9, 0.0)
	HolyFX.flash(top, 2.2, 0.5, Art.SOUL, 3.0)
	HolyFX.column(global_position, 0.5, 9.0, 0.7, Art.SOUL, 1.8)
	HolyFX.motes(top, 24, Art.SOUL, 1.4, 2.4, 1.6, 0.08)
	HolyFX.motes(top, 10, Art.EMBER, 1.0, 3.0, 1.2, 0.05)
	var lt2 := _light.create_tween()
	lt2.tween_property(_light, "light_energy", 6.0, 0.08)
	lt2.tween_property(_light, "light_energy", 1.0, 0.9)
	_spill_shards()


func _spill_shards() -> void:
	var n := clampi(int(xp_total / 30.0), 8, 16)
	var each := maxi(ceili(xp_total / float(n)), 25)  # >= 25 keeps every shard a radiant relic
	for i in n:
		var a := TAU * float(i) / float(n) + randf_range(-0.2, 0.2)
		var r := randf_range(1.4, 2.8)
		var gem: XPGem = GEM_SCENE.instantiate()
		gem.value = each
		Game.spawn(gem, global_position + Vector3(cos(a) * r, 0.4, sin(a) * r))


# ---------------------------------------------------------------- construction

func _build() -> void:
	_sigil = BossTelegraph.new()
	add_child(_sigil)
	_body = Art.pivot(self)
	_seam_mat = HolyFX.additive(Art.SOUL, 1.6)
	_heart_mat = HolyFX.additive(Art.SOUL, 2.0)
	# Blender-made coffer (tools/blender/models/bosses/reliquary.py); its front faces Blender -Y,
	# which imports as +Z, so turn it to face the game's forward (-Z).
	var glb := GlbModel.create(MODEL, false)
	glb.rotation.y = PI
	_body.add_child(glb)
	if glb.scene_root:
		_lid = glb.scene_root.find_child("lid", true, false) as Node3D
		_swap_glow(glb.scene_root)
	if _lid == null:
		_lid = Art.pivot(_body, Vector3(0.0, 0.83, 0.0))
	_light = Art.light(self, Art.SOUL, 1.2, 5.0, Vector3(0.0, 1.0, 0.0))


## Seams and sigils pulse with one shared additive material; the heart-stone with another.
func _swap_glow(n: Node) -> void:
	var mi := n as MeshInstance3D
	if mi and mi.mesh:
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			if src == null:
				continue
			match src.resource_name:
				"Reliquary_SeamGlow", "Reliquary_SigilGlow":
					mi.set_surface_override_material(i, _seam_mat)
				"Reliquary_HeartCrystal":
					mi.set_surface_override_material(i, _heart_mat)
	for c in n.get_children():
		_swap_glow(c)

static func _ease_out_cubic(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)
