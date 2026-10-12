class_name InquisitorLane
extends Node3D
## A lane of judgement (the Grand Inquisitor's "Chains of Penance" and "Censure"): a lane of light
## charges on the ground for `tell` seconds, then a chain of white fire lashes down its length and
## damages the demon once if it stands inside. Use InquisitorLane.cast(from, dir, length, width,
## tell, damage). In group "boss_hazards" (dissipate() cancels it while it is still charging).

const STRIKE_LIFE := 0.4
const PLAYER_RADIUS := 0.35

var dir := Vector3.FORWARD
var length := 12.0
var width := 1.2
var tell := 1.1
var damage := 22.0

var _t := 0.0
var _struck := false
var _tele: HolyTelegraph
var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D


## characters-new: hazard tint. Read from HolyFX.hazard_tint when created (ProcBoss sets it around
## its casts); Art.HOLY = the original look.
var tint: Color = HolyFX.hazard_tint


static func cast(from: Vector3, direction: Vector3, len_m: float, width_m: float, tell_s: float,
		dmg: float) -> InquisitorLane:
	if Game.world == null:
		return null
	var l := InquisitorLane.new()
	var d := Vector3(direction.x, 0.0, direction.z)
	l.dir = d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD
	l.length = len_m
	l.width = width_m
	l.tell = tell_s
	l.damage = dmg
	Game.spawn(l, Vector3(from.x, 0.0, from.z))
	return l


func _ready() -> void:
	add_to_group(&"boss_hazards")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_tele = HolyTelegraph.new()
	add_child(_tele)


func _physics_process(delta: float) -> void:
	_t += delta
	if not _struck:
		_tele.show_line(global_position, dir, length, width, clampf(_t / maxf(tell, 0.01), 0.0, 1.0))
		if _t >= tell:
			_strike()
		return
	var k := clampf((_t - tell) / STRIKE_LIFE, 0.0, 1.0)
	_beam_mat.albedo_color = HolyFX.scaled(HolyFX.white_of(tint), 2.8 * (1.0 - k) * (1.0 - k))
	_beam.scale.x = width * 0.7 * (1.0 - k * 0.7)
	if k >= 1.0:
		queue_free()


func _strike() -> void:
	_struck = true
	_tele.hide_now()
	var mid := dir * length * 0.5 + Vector3(0.0, 0.25, 0.0)
	_beam = HolyFX.glow_part(self, Art.box(), HolyFX.white_of(tint), 2.8, mid, Vector3(width * 0.7, 0.25, length))
	_beam.rotation.y = atan2(-dir.x, -dir.z)
	_beam_mat = _beam.material_override as StandardMaterial3D
	Sfx.play(&"chain", 0.1, -2.0)
	HolyFX.motes(global_position + dir * length * 0.5, 6, tint, length * 0.25, 1.2, 0.6)
	var p := Game.player
	# damage 0 = a pure warning lane (e.g. the path of a charge that does its own damage).
	if damage > 0.0 and p and is_instance_valid(p) and not p.is_dead and hits(p.global_position):
		p.take_damage(damage)
		Sfx.play(&"holy_hit", 0.08)


## True when `point` (XZ) lies within the lane (plus the demon's radius).
func hits(point: Vector3) -> bool:
	var d := point - global_position
	d.y = 0.0
	var along := d.dot(dir)
	if along < -PLAYER_RADIUS or along > length + PLAYER_RADIUS:
		return false
	return (d - dir * along).length() <= width * 0.5 + PLAYER_RADIUS


## Boss died: cancel a lane still charging; a struck one finishes fading.
func dissipate() -> void:
	if _struck:
		return
	_tele.hide_now()
	queue_free()
