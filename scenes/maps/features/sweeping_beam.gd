class_name SweepingBeam
extends Node3D
## Map hazard: a lance of holy light swept around `center` like a lighthouse (Heaven's Gate, the
## Sun Spire). Only one sweep at a time: the beam rests for `rest` s, its path lights up as a thin
## ground line for `tell` s, then it sweeps `arc` radians at `speed` rad/s. Inside the beam the demon
## takes `player_damage` per hit (every 0.5 s at most); angels are untouched (it is their light).

@export var length := 40.0
@export var width := 2.4
@export var speed := 0.55
@export var arc := PI * 0.9
@export var rest := 9.0
@export var tell := 1.4
@export var player_damage := 14.0
@export var inner_radius := 4.0
@export var color := Color(1.0, 0.9, 0.6)
## Seconds before the first sweep (lets a run settle before the lances start).
@export var start_delay := 5.0

var center := Vector3.ZERO

enum Phase { REST, TELL, SWEEP }

var _phase := Phase.REST
var _t := -1.0
var _angle := 0.0
var _dir := 1.0
var _swept := 0.0
var _hit_cd := 0.0
var _beam: MeshInstance3D
var _mat: StandardMaterial3D
var _line: BossTelegraph


func _ready() -> void:
	_t = start_delay
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.albedo_color = Color(color.r, color.g, color.b, 0.0) * 2.0
	var bm := BoxMesh.new()
	bm.size = Vector3(width, 2.2, length)
	_beam = MeshInstance3D.new()
	_beam.mesh = bm
	_beam.material_override = _mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	_beam.top_level = true
	add_child(_beam)
	_line = BossTelegraph.new()
	add_child(_line)


func _physics_process(delta: float) -> void:
	_hit_cd = maxf(_hit_cd - delta, 0.0)
	match _phase:
		Phase.REST:
			_t -= delta
			if _t <= 0.0:
				_phase = Phase.TELL
				_t = tell
				# start the sweep so it will cross the demon's bearing midway
				var p := Game.player
				var bearing := randf() * TAU
				if p:
					var d := p.global_position - center
					bearing = atan2(d.x, d.z)
				_dir = 1.0 if randf() < 0.5 else -1.0
				_angle = bearing - _dir * arc * 0.5
				_swept = 0.0
		Phase.TELL:
			_t -= delta
			var k := 1.0 - _t / tell
			_line.show_sector(center, Vector3(sin(_angle), 0, cos(_angle)), length, 0.05, color, k, 0.6, 1.4)
			if _t <= 0.0:
				_line.hide_now()
				_phase = Phase.SWEEP
				_beam.visible = true
				Sfx.play_at(&"beam", center, 0.05, 0.0)
		Phase.SWEEP:
			var step := speed * delta
			_angle += step * _dir
			_swept += step
			_place_beam(clampf(_swept / 0.3, 0.0, 1.0) * clampf((arc - _swept) / 0.3, 0.0, 1.0))
			_hurt()
			if _swept >= arc:
				_phase = Phase.REST
				_t = rest * randf_range(0.8, 1.2)
				_beam.visible = false


func _place_beam(fade: float) -> void:
	var dir := Vector3(sin(_angle), 0.0, cos(_angle))
	var mid := center + dir * (inner_radius + length * 0.5)
	_beam.global_transform = Transform3D(Basis(Vector3.UP, _angle), mid + Vector3(0, 1.1, 0))
	_mat.albedo_color = Color(color.r, color.g, color.b, 0.55 * fade) * 2.0


func _hurt() -> void:
	var p := Game.player
	if p == null or p.is_dead or _hit_cd > 0.0:
		return
	var rel := p.global_position - center
	rel.y = 0.0
	var dir := Vector3(sin(_angle), 0.0, cos(_angle))
	var along := rel.dot(dir)
	var across := absf(rel.dot(Vector3(dir.z, 0.0, -dir.x)))
	if along > inner_radius and along < inner_radius + length and across < width * 0.5 + 0.3:
		_hit_cd = 0.5
		p.take_damage(player_damage, p.global_position - dir)
		HolyFX.flash(p.global_position + Vector3(0, 1.0, 0), 1.2, 0.3, color, 2.0)
