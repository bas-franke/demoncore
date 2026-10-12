class_name JudgementPillar
extends Node3D
## One "Judgement Pillar": a golden ground sigil charges for `tell` seconds (a faint shaft of light
## gathers above it), then a column of light slams down and damages the player once if they are
## inside `radius`. Use JudgementPillar.cast(at, radius, tell, damage). In group "boss_hazards".

const COLUMN_HEIGHT := 18.0
const SLAM_TIME := 0.09
const FADE_TIME := 0.55
const PLAYER_RADIUS := 0.35

var radius := 1.6
var tell := 1.2
var damage := 24.0

var _t := 0.0
var _slammed := false
var _sigil: BossTelegraph
var _shaft: MeshInstance3D
var _shaft_mat: StandardMaterial3D
var _core: MeshInstance3D
var _core_mat: StandardMaterial3D
var _shell: MeshInstance3D
var _shell_mat: StandardMaterial3D
var _light: OmniLight3D


## characters-new: hazard tint. Read from HolyFX.hazard_tint when created (ProcBoss sets it around
## its casts); Art.HOLY = the original look.
var tint: Color = HolyFX.hazard_tint


static func cast(at: Vector3, r: float, tell_time: float, dmg: float) -> JudgementPillar:
	if Game.world == null:
		return null
	var p := JudgementPillar.new()
	p.radius = r
	p.tell = tell_time
	p.damage = dmg
	Game.spawn(p, Vector3(at.x, 0.0, at.z))
	return p


func _ready() -> void:
	add_to_group(&"boss_hazards")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_sigil = BossTelegraph.new()
	add_child(_sigil)
	_shaft = HolyFX.glow_part(self, Art.cylinder(), tint, 0.0, Vector3(0.0, COLUMN_HEIGHT * 0.5, 0.0),
			Vector3(radius, COLUMN_HEIGHT, radius))
	_shaft_mat = _shaft.material_override as StandardMaterial3D
	_core = HolyFX.glow_part(self, Art.cylinder(), HolyFX.white_of(tint), 2.6, Vector3.ZERO,
			Vector3(radius * 1.7, COLUMN_HEIGHT, radius * 1.7))
	_core_mat = _core.material_override as StandardMaterial3D
	_shell = HolyFX.glow_part(self, Art.cylinder(), tint, 1.1, Vector3.ZERO,
			Vector3(radius * 2.3, COLUMN_HEIGHT, radius * 2.3))
	_shell_mat = _shell.material_override as StandardMaterial3D
	_core.visible = false
	_shell.visible = false
	_light = Art.light(self, tint, 0.0, radius * 4.0, Vector3(0.0, 1.2, 0.0))
	_sigil.show_disc(global_position, radius, tint, 0.0, 0.0)


func _physics_process(delta: float) -> void:
	_t += delta
	if not _slammed:
		var k := clampf(_t / maxf(tell, 0.01), 0.0, 1.0)
		var pulse := 0.85 + 0.15 * sin(_t * 18.0)
		_sigil.show_disc(global_position, radius, tint, k, minf(_t * 6.0, 1.0) * pulse, 1.4 + k)
		_shaft_mat.albedo_color = HolyFX.scaled(tint, 0.06 + 0.28 * k * k)
		_shaft.scale = Vector3(radius * lerpf(1.8, 0.7, k), COLUMN_HEIGHT, radius * lerpf(1.8, 0.7, k))
		_light.light_energy = 0.6 * k
		if _t >= tell:
			_slam()
		return
	var st := _t - tell
	if st < SLAM_TIME:
		# Column drops from the sky onto the sigil.
		var drop := 1.0 - st / SLAM_TIME
		_core.position.y = COLUMN_HEIGHT * 0.5 + drop * COLUMN_HEIGHT
		_shell.position.y = _core.position.y
		return
	_core.position.y = COLUMN_HEIGHT * 0.5
	_shell.position.y = COLUMN_HEIGHT * 0.5
	var fk := clampf((st - SLAM_TIME) / FADE_TIME, 0.0, 1.0)
	var inv := 1.0 - fk
	_core.scale = Vector3(radius * 1.7 * inv, COLUMN_HEIGHT, radius * 1.7 * inv)
	_shell.scale = Vector3(radius * 2.3 * (0.6 + 0.4 * inv), COLUMN_HEIGHT, radius * 2.3 * (0.6 + 0.4 * inv))
	_core_mat.albedo_color = HolyFX.scaled(HolyFX.white_of(tint), 2.6 * inv)
	_shell_mat.albedo_color = HolyFX.scaled(tint, 1.1 * inv * inv)
	_light.light_energy = 5.0 * inv * inv
	_sigil.show_disc(global_position, radius, tint, 1.0, inv * 0.8, 2.0)
	if fk >= 1.0:
		queue_free()


func _slam() -> void:
	_slammed = true
	_shaft.visible = false
	_core.visible = true
	_shell.visible = true
	_core.position.y = COLUMN_HEIGHT * 1.5
	_shell.position.y = COLUMN_HEIGHT * 1.5
	_light.light_energy = 5.0
	Sfx.play(&"smite", 0.12, -2.0)
	get_tree().call_group(&"camera_rig", &"shake", 0.14)
	HolyFX.motes(global_position + Vector3(0.0, 0.2, 0.0), 8, tint, radius * 0.8, 1.8, 0.8)
	var p := Game.player
	if p and is_instance_valid(p) and not p.is_dead:
		var d := p.global_position - global_position
		d.y = 0.0
		if d.length() <= radius + PLAYER_RADIUS:
			p.take_damage(damage)
			Sfx.play(&"holy_hit", 0.08)


## Boss died: cancel unfired pillars, let fired ones finish fading.
func dissipate() -> void:
	if _slammed:
		return
	var tw := create_tween()
	tw.tween_property(_shaft_mat, "albedo_color", Color(0.0, 0.0, 0.0, 1.0), 0.3)
	tw.tween_callback(queue_free)
	set_physics_process(false)
	_sigil.hide_now()
