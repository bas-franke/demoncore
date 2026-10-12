class_name ProfaneGround
extends Node3D
## Hell terrain left behind by a defiled holy site (the baptismal font objective, events): the
## ground inside `radius` stays blighted (Corruption.stamp refreshed every few seconds) for
## `duration` seconds (< 0 = the rest of the run). Inside it the demon regenerates `regen` HP/s
## and angels burn for `burn_dps`. A faint crimson ring marks its edge.
## Use ProfaneGround.create(at, radius, duration, regen, burn_dps). In group "profane_ground".

const TICK := 0.5
const RESTAMP := 6.0

var radius := 9.0
var duration := -1.0
var regen := 2.5
var burn_dps := 8.0

var _t := 0.0
var _tick_t := 0.0
var _stamp_t := 0.0
var _ring: BossTelegraph


static func create(at: Vector3, r: float, life: float = -1.0, heal_per_s: float = 2.5,
		dps: float = 8.0) -> ProfaneGround:
	if Game.world == null:
		return null
	var g := ProfaneGround.new()
	g.radius = r
	g.duration = life
	g.regen = heal_per_s
	g.burn_dps = dps
	Game.spawn(g, Vector3(at.x, 0.0, at.z))
	return g


## True when `pos` stands on any profane ground.
static func covers(tree: SceneTree, pos: Vector3) -> bool:
	for n in tree.get_nodes_in_group(&"profane_ground"):
		var g := n as ProfaneGround
		if g and Vector2(pos.x - g.global_position.x, pos.z - g.global_position.z).length() <= g.radius:
			return true
	return false


func _ready() -> void:
	add_to_group(&"profane_ground")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_ring = BossTelegraph.new()
	add_child(_ring)
	_stamp()


func _process(delta: float) -> void:
	_t += delta
	var fade := 1.0
	if duration > 0.0:
		fade = clampf((duration - _t) / 3.0, 0.0, 1.0)
		if _t >= duration:
			queue_free()
			return
	_ring.show_disc(global_position, radius, Art.CRIMSON, 0.0, (0.35 + 0.1 * sin(_t * 1.7)) * fade, 1.1)
	if randf() < delta * 6.0:
		var a := randf() * TAU
		var r := sqrt(randf()) * radius
		HolyFX.motes(global_position + Vector3(cos(a) * r, 0.1, sin(a) * r), 1, Art.EMBER, 0.2, 1.4, 1.2, 0.05)
	_stamp_t -= delta
	if _stamp_t <= 0.0:
		_stamp()
	_tick_t -= delta
	if _tick_t > 0.0:
		return
	_tick_t = TICK
	var r2 := radius * radius
	var p := Game.player
	if p and not p.is_dead and p.global_position.distance_squared_to(global_position) <= r2:
		p.heal(regen * TICK)
	for n in Perf.enemies():  # perf: shared per-frame list
		var e := n as Enemy
		if e and not e.is_dying and not e.is_in_group(&"boss") \
				and e.global_position.distance_squared_to(global_position) <= r2:
			e.take_damage(burn_dps * TICK)


## Blights the whole disc (a few overlapping stamps; the Corruption brush is a disc too).
func _stamp() -> void:
	_stamp_t = RESTAMP
	var corruption := get_tree().root.get_node_or_null(^"Corruption")
	if corruption == null or not corruption.has_method(&"stamp"):
		return
	corruption.call(&"stamp", global_position, radius * 0.6, 1.0)
	for i in 6:
		var a := TAU * float(i) / 6.0
		corruption.call(&"stamp", global_position + Vector3(cos(a), 0.0, sin(a)) * radius * 0.55, radius * 0.45, 1.0)
