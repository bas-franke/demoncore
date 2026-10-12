class_name FissureField
extends Node3D
## Map hazard (Ashen Wastes): hell has already broken through, and the ground vents. Every
## `interval` s a vent near the demon (or one of the map's `vents`) glows red for `tell` s, then
## erupts in a hellfire column: angels within `radius` take `enemy_damage` (hell is on your side),
## the demon takes a scorch of `player_damage` if it stands in it.

@export var interval := 3.2
@export var tell := 1.5
@export var radius := 3.2
@export var player_damage := 10.0
@export var enemy_damage := 70.0
@export var max_at_once := 4

## Fixed vent positions (lava pools / fissures); eruptions favour those within 22 m of the demon.
var vents: Array[Vector3] = []

const FIRE := Color(1.0, 0.32, 0.08)

var _t := 2.0
var _pending: Array[Dictionary] = []


func _physics_process(delta: float) -> void:
	var p := Game.player
	if p == null or p.is_dead:
		return
	_t -= delta
	if _t <= 0.0 and _pending.size() < max_at_once:
		_t = interval * randf_range(0.6, 1.4)
		var near: Array[Vector3] = []
		for v in vents:
			if v.distance_to(p.global_position) < 22.0:
				near.append(v)
		var at: Vector3
		if not near.is_empty() and randf() < 0.6:
			at = near[randi() % near.size()]
		else:
			var a := randf() * TAU
			at = Maps.clamp_to_bounds(p.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(4.0, 14.0))
		var ring := BossTelegraph.new()
		add_child(ring)
		_pending.append({"at": at, "t": tell, "ring": ring})
	for s in _pending.duplicate():
		s["t"] = float(s["t"]) - delta
		var k := 1.0 - float(s["t"]) / tell
		(s["ring"] as BossTelegraph).show_disc(s["at"], radius, FIRE, k, 0.5 + 0.5 * k, 1.8)
		if float(s["t"]) <= 0.0:
			_erupt(s["at"])
			(s["ring"] as BossTelegraph).queue_free()
			_pending.erase(s)


func _erupt(at: Vector3) -> void:
	HolyFX.column(at, 1.0, 9.0, 0.7, Art.HELLFIRE, 2.4)
	HolyFX.motes(at + Vector3(0, 0.4, 0), 14, Art.EMBER, 1.4, 3.0, 1.4, 0.08)
	Sfx.play_at(&"brimstone", at, 0.1, 0.0)
	ObjectiveFX.damage_enemies(at, radius, enemy_damage)
	var p := Game.player
	if p and not p.is_dead:
		var d := p.global_position - at
		d.y = 0.0
		if d.length() <= radius * 0.8:
			p.take_damage(player_damage, at)
