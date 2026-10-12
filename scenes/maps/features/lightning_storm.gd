class_name LightningStorm
extends Node3D
## Map hazard (Storm Spire): every `interval` s (jittered) lightning picks a spot near the demon
## (sometimes right on it), lights a cold sigil for `tell` s, then strikes: `player_damage` to the
## demon and `enemy_damage` to angels within `radius`. Lightning rods (`rods`, world positions)
## attract any strike that lands within `rod_pull` m of one: the bolt hits the rod instead and arcs
## through every angel within `rod_arc` m of it. Lure the host to the rods; stay off them yourself.

@export var interval := 5.0
@export var tell := 1.3
@export var radius := 2.6
@export var player_damage := 16.0
@export var enemy_damage := 45.0
@export var rod_pull := 9.0
@export var rod_arc := 6.0
@export var max_at_once := 3

var rods: Array[Vector3] = []

const BOLT := Color(0.7, 0.85, 1.0)

var _t := 3.0
var _pending: Array[Dictionary] = []  # {at, t, rod, ring}


func _physics_process(delta: float) -> void:
	var p := Game.player
	if p == null or p.is_dead:
		return
	_t -= delta
	if _t <= 0.0 and _pending.size() < max_at_once:
		_t = interval * randf_range(0.6, 1.3)
		var at := p.global_position
		if randf() > 0.35:
			var a := randf() * TAU
			at += Vector3(cos(a), 0.0, sin(a)) * randf_range(3.0, 11.0)
		_queue(Maps.clamp_to_bounds(at))
	for s in _pending.duplicate():
		s["t"] = float(s["t"]) - delta
		var ring: BossTelegraph = s["ring"]
		var k := 1.0 - float(s["t"]) / tell
		ring.show_disc(s["at"], radius if not s["rod"] else rod_arc, BOLT, k, 0.5 + 0.5 * k, 1.6 + k)
		if float(s["t"]) <= 0.0:
			_strike(s)
			ring.queue_free()
			_pending.erase(s)


func _queue(at: Vector3) -> void:
	var rod := false
	for r in rods:
		if Vector2(r.x - at.x, r.z - at.z).length() < rod_pull:
			at = r
			rod = true
			break
	var ring := BossTelegraph.new()
	add_child(ring)
	_pending.append({"at": at, "t": tell, "rod": rod, "ring": ring})


func _strike(s: Dictionary) -> void:
	var at: Vector3 = s["at"]
	var r := rod_arc if s["rod"] else radius
	HolyFX.column(at, 0.45, 26.0, 0.35, BOLT, 3.2)
	HolyFX.flash(at + Vector3(0, 1.0, 0), r, 0.35, BOLT, 3.0)
	# Visuals role: forked bolt + flash lights + screen flash from the Atmosphere rig (no extra sound).
	var atmo := get_node_or_null(^"/root/Atmosphere")
	if atmo and atmo.has_method(&"strike_lightning"):
		atmo.call(&"strike_lightning", at, 0.15, false)
	Sfx.play_at(&"smite", at, 0.1, 2.0)
	get_tree().call_group(&"camera_rig", &"shake", 0.18)
	ObjectiveFX.damage_enemies(at, r, enemy_damage * (1.6 if s["rod"] else 1.0))
	var p := Game.player
	if p and not p.is_dead:
		var d := p.global_position - at
		d.y = 0.0
		if d.length() <= r * 0.85:
			p.take_damage(player_damage, at)
