extends Objective
## "Assassinate the Bishop": a bishop's procession sets out from a shrine along a road of
## `waypoints` stops toward a cathedral sigil `route_length` m away, censer-bearers and sentinels
## marching around it. It walks at a stately `walk_speed` until the demon closes within
## `panic_distance` (or wounds it); then the bishop flees. Kill the bishop before it reaches the
## sigil and is taken up (fail), or before `time_limit` s once panicked.
## params: route_length, waypoints, walk_speed, panic_distance, flee_speed, hp, hp_per_minute,
##         escorts (enemy ids), time_limit, model (enemy id whose model it wears).

const SAINT_SCENE := preload("res://scenes/objectives/saint/saint.tscn")
const TITLES := ["Bishop Anselm", "Bishop Cyrene", "Bishop Morrow", "Archbishop Valerian",
		"Bishop Ilse of the Lamps", "Cardinal Oswin"]

var _bishop: SaintEnemy
var _has_bishop := false
var _name := "Bishop"
var _end := Vector3.ZERO
var _route: Array[Vector3] = []
var _zone: BossTelegraph
var _end_zone: BossTelegraph
var _panicked := false
var _arrived := false
var _last_pos := Vector3.ZERO


func _build() -> void:
	_name = TITLES.pick_random()
	_zone = ObjectiveFX.zone(self)
	_end_zone = ObjectiveFX.zone(self)
	# A roadside shrine where the procession forms up.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var c := Props.candles(rng, 6)
	add_child(c)
	status_text = "Ambush the procession"


func _ready() -> void:
	super()
	_plan_route()
	_bishop = _make_bishop()
	_has_bishop = _bishop != null


func _plan_route() -> void:
	var p := Game.player.global_position if Game.player else global_position - Vector3.FORWARD
	var away := global_position - p
	away.y = 0.0
	var dir := away.normalized() if away.length() > 0.1 else Vector3.FORWARD
	var n := maxi(int(param("waypoints", 4)), 1)
	var length := float(param("route_length", 38.0))
	var at := global_position
	# A winding road: each leg bends a little.
	for i in n:
		dir = dir.rotated(Vector3.UP, randf_range(-0.6, 0.6))
		at = ObjectiveFX.walkable(at + dir * length / float(n))
		_route.append(at)
	_end = _route.back()


func _make_bishop() -> SaintEnemy:
	var base := ObjectiveFX.enemy_data(str(param("model", "thurible_priest")))
	if base == null:
		return null
	var d := base.duplicate() as EnemyData
	d.display_name = _name
	d.size = base.size * 1.35
	d.max_hp = float(param("hp", 380.0)) + float(param("hp_per_minute", 110.0)) * Game.elapsed / 60.0
	d.speed = float(param("flee_speed", 4.4))
	d.xp_value = 50
	d.knockback_scale = 0.2
	d.behavior = EnemyData.Behavior.CHASE
	var s := SAINT_SCENE.instantiate() as SaintEnemy
	s.setup(d, 1.0)
	s.flee_speed = d.speed
	s.route = _route.duplicate()
	s.route_speed = float(param("walk_speed", 1.8))
	s.panic_distance = float(param("panic_distance", 7.0))
	s.blessing_interval = 3.2
	s.set_physics_process(false)  # forms up until the demon draws near
	s.route_finished.connect(_on_route_finished)
	s.panicked.connect(_on_panicked)
	Game.spawn.call_deferred(s, global_position)
	return s


func marker_position() -> Vector3:
	if _has_bishop and is_instance_valid(_bishop) and _bishop.is_inside_tree():
		return _bishop.global_position
	return global_position


func _tick(_delta: float) -> void:
	if not _has_bishop:
		fail()
		return
	if not is_instance_valid(_bishop) or _bishop.is_dying:
		complete()
		return
	if not _bishop.is_inside_tree():
		return
	_last_pos = _bishop.global_position
	_end_zone.show_disc(_end, 3.0, Art.HOLY_WHITE, 0.0, 0.55, 1.2)
	if state == State.DORMANT:
		_zone.show_disc(global_position, 2.0, Art.HOLY, 0.0, 0.5, 1.0)
		if _player_distance(_bishop.global_position) <= 24.0 or _bishop.hp < _bishop.max_hp:
			activate()
		return
	progress = 1.0 - clampf(_bishop.hp / maxf(_bishop.max_hp, 1.0), 0.0, 1.0)
	if _panicked:
		var left := float(param("time_limit", 35.0)) - active_time
		status_text = "%d%%  %s" % [roundi((1.0 - progress) * 100.0), fmt_time(left)]
		if left <= 0.0:
			_bishop.ascend()
			fail()
	else:
		var d := Vector2(_end.x - _last_pos.x, _end.z - _last_pos.z).length()
		status_text = "%dm to the cathedral" % roundi(d)
	if _arrived:
		_bishop.ascend()
		fail()


func _on_activated() -> void:
	_zone.hide_now()
	if is_instance_valid(_bishop):
		_bishop.set_physics_process(true)
		_minimap_follow(_bishop)
		var ids: Array = param("escorts", ["thurible_priest"])
		for i in ids.size():
			_spawn_enemy(str(ids[i]), _bishop.global_position + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0)))
	_toast("%s's procession sets out" % _name, Color("fff4cf"))
	Sfx.play(&"toll", 0.0, -2.0)


func _on_panicked() -> void:
	if _panicked:
		return
	_panicked = true
	active_time = 0.0  # the flight timer starts now
	_toast("%s breaks and runs!" % _name, Color("9fd4ff"))


func _on_route_finished() -> void:
	_arrived = true


func _on_finished(completed: bool) -> void:
	_zone.hide_now()
	_end_zone.hide_now()
	if completed:
		global_position = Vector3(_last_pos.x, 0.0, _last_pos.z)
		reset_physics_interpolation()
		ObjectiveFX.corruption_burst(_last_pos, 0.9)
		_toast("%s will preach no more" % _name, Art.HELLFIRE)
	elif _has_bishop and is_instance_valid(_bishop) and not _bishop.is_dying:
		_toast("%s is taken up into the light" % _name, Art.HOLY_WHITE)
		_bishop.ascend()
